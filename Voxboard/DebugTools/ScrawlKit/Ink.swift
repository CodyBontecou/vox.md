// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
import CoreGraphics
import Foundation

// The pen: smoothing, width, geometry, and when strokes fade. Plain values with time passed in,
// so they're tested on the Mac; `InkView` draws them on iOS.

/// One-euro filter (Casiez, Roussel & Vogel, CHI 2012) on points: a low-pass whose cutoff rises
/// with speed, so slow, careful lines lose their jitter while fast ones don't lag. One cutoff from
/// the 2D speed for both axes, so a straight line stays straight (filtered separately, x and y
/// lag by different amounts and the line drifts off itself).
nonisolated struct OneEuroFilter: Equatable {
  var minCutoff: Double
  var beta: Double
  var derivativeCutoff: Double
  private var value: CGPoint?
  private var velocity = CGVector.zero
  private var time: TimeInterval?

  init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 1) {
    self.minCutoff = minCutoff
    self.beta = beta
    self.derivativeCutoff = derivativeCutoff
  }

  mutating func filter(_ point: CGPoint, at t: TimeInterval) -> CGPoint {
    guard let value, let time else {
      self.value = point
      self.time = t
      return point
    }
    let dt = max(t - time, 1.0 / 1000)
    let d = Self.alpha(cutoff: derivativeCutoff, dt: dt)
    velocity.dx += d * ((point.x - value.x) / dt - velocity.dx)
    velocity.dy += d * ((point.y - value.y) / dt - velocity.dy)
    let a = Self.alpha(cutoff: minCutoff + beta * hypot(velocity.dx, velocity.dy), dt: dt)
    let next = CGPoint(x: value.x + a * (point.x - value.x), y: value.y + a * (point.y - value.y))
    self.value = next
    self.time = t
    return next
  }

  static func alpha(cutoff: Double, dt: Double) -> Double {
    1 / (1 + 1 / (2 * .pi * cutoff) / dt)
  }
}

/// A point of a stroke as recorded: filtered position, the touch's own timestamp (seconds since
/// boot, as `UITouch.timestamp`), and the line's width there.
nonisolated struct InkSample: Equatable, Sendable {
  var point: CGPoint
  var time: TimeInterval
  var width: CGFloat
}

/// Turns raw touch positions (every coalesced one) into the stroke's samples: one-euro filtered,
/// at least `minSpacing` apart, with a width that thins as the finger speeds up (pressure plays no
/// part, like the Mac's ink).
nonisolated struct InkStrokeBuilder: Equatable {
  /// The line's width when drawn slowly, in points (the Mac draws about the same on keyframes).
  static let maxWidth: CGFloat = 4.6
  /// How much thinner a fast line gets: 0.45 makes it 55% of `maxWidth`.
  static let thinning: CGFloat = 0.45
  /// Points a second at which a line is thinnest.
  static let fastSpeed: Double = 1600
  static let minSpacing: CGFloat = 0.4

  private var filter = OneEuroFilter(minCutoff: 3, beta: 0.03)
  /// Low-passed speed in points a second.
  private var speed = 0.0
  private(set) var samples: [InkSample] = []

  mutating func add(_ point: CGPoint, at time: TimeInterval) {
    append(filter.filter(point, at: time), at: time)
  }

  /// Samples for iOS's predicted touches, run through a copy of the filter so the live tip
  /// continues the smoothed line. They're for drawing the tip only, never part of the stroke.
  func predicting(_ points: [(CGPoint, TimeInterval)]) -> [InkSample] {
    guard !points.isEmpty else { return [] }
    var copy = self
    copy.samples = samples.last.map { [$0] } ?? []
    for (point, time) in points {
      copy.add(point, at: time)
    }
    return Array(copy.samples.dropFirst(samples.isEmpty ? 0 : 1))
  }

  /// The finger lifted at `point`: the stroke ends exactly there.
  mutating func finish(at point: CGPoint, time: TimeInterval) {
    append(point, at: time)
  }

  private mutating func append(_ point: CGPoint, at time: TimeInterval) {
    if let last = samples.last {
      let distance = hypot(point.x - last.point.x, point.y - last.point.y)
      guard distance >= Self.minSpacing else { return }
      let dt = max(time - last.time, 1.0 / 1000)
      speed += (1 - exp(-dt / 0.04)) * (distance / dt - speed)
    }
    samples.append(InkSample(point: point, time: time, width: Self.width(forSpeed: speed)))
  }

  static func width(forSpeed speed: Double) -> CGFloat {
    let t = min(max(speed / fastSpeed, 0), 1)
    return maxWidth * (1 - thinning * t * t * (3 - 2 * t))
  }
}

/// A stroke's outline, built as it grows: a centripetal Catmull-Rom curve through the samples,
/// drawn as discs joined by quads (filled with the nonzero rule, so overlaps and hairpins never
/// leave holes). The start tapers in over `taperLength`, and the end tapers once the finger lifts.
///
/// Behind the tip, samples also get a centered smoothing (`smoothed`), which takes out finger
/// jitter without the lag a smoothing filter on the live input would add. The tip itself stays
/// on the latest sample.
///
/// A segment is final once its smoothing can't change and it's more than `taperLength` from the
/// end, so `freeze()` hands each segment out once for drawing into a layer that never changes;
/// only `tail` (the last few points plus any predicted ones) is redrawn on each touch.
nonisolated struct InkTrace: Equatable {
  struct Point: Equatable {
    var point: CGPoint
    var radius: CGFloat
  }

  static let taperLength: CGFloat = 10
  /// The width at the very tip of a taper, as a fraction of the full width.
  static let taperTip: CGFloat = 0.35
  /// About one curve point per this many points of length.
  static let step: CGFloat = 1.5

  private(set) var samples: [InkSample] = []
  /// Length along the samples to each sample.
  private(set) var lengths: [CGFloat] = []
  /// Segments (sample i to i + 1) that are final.
  private(set) var frozen = 0

  var length: CGFloat { lengths.last ?? 0 }

  /// The samples as drawn (smoothed), for the timeline once the stroke is finished.
  var smoothedSamples: [InkSample] {
    samples.indices.map { k in
      var sample = samples[k]
      sample.point = Self.smoothed(k, count: samples.count) { samples[$0].point }
      return sample
    }
  }

  mutating func append(_ new: some Sequence<InkSample>) {
    for sample in new {
      let step = samples.last.map { hypot(sample.point.x - $0.point.x, sample.point.y - $0.point.y) } ?? 0
      lengths.append(length + step)
      samples.append(sample)
    }
  }

  /// The curve points of segments that just became final, starting at the first one's start.
  mutating func freeze() -> [Point] {
    var points: [Point] = []
    let n = samples.count
    // Segment i reads smoothed samples up to i + 2, final once two more samples follow them.
    while frozen + 4 < n, length - lengths[frozen + 1] >= Self.taperLength {
      points += segment(frozen, count: n, sample: { samples[$0] }, length: { lengths[$0] }, total: nil, includeStart: points.isEmpty)
      frozen += 1
    }
    return points
  }

  /// The rest of the stroke after the frozen segments: while drawing, through any `predicted`
  /// samples (for the live tip only); once `finished`, with the end tapered.
  func tail(predicted: [InkSample] = [], finished: Bool = false) -> [Point] {
    guard !samples.isEmpty else { return [] }
    let n = samples.count + predicted.count
    if n == 1 {
      return [Point(point: samples[0].point, radius: samples[0].width / 2 * 0.8)]
    }
    var predictedLengths: [CGFloat] = []
    var previous = samples[samples.count - 1].point
    for sample in predicted {
      predictedLengths.append((predictedLengths.last ?? length) + hypot(sample.point.x - previous.x, sample.point.y - previous.y))
      previous = sample.point
    }
    let count = samples.count
    let sample = { (k: Int) in k < count ? samples[k] : predicted[k - count] }
    let length = { (k: Int) in k < count ? lengths[k] : predictedLengths[k - count] }
    var points: [Point] = []
    for index in frozen ..< (n - 1) {
      points += segment(index, count: n, sample: sample, length: length, total: finished ? self.length : nil, includeStart: points.isEmpty)
    }
    return points
  }

  /// The whole stroke, finished.
  var outline: [Point] {
    var copy = self
    copy.frozen = 0
    return copy.tail(finished: true)
  }

  /// Sample k's position after a centered 1-2-3-2-1 smoothing, narrower near the ends (which stay
  /// exactly where they were).
  static func smoothed(_ k: Int, count n: Int, _ point: (Int) -> CGPoint) -> CGPoint {
    let r = min(2, k, n - 1 - k)
    guard r > 0 else { return point(k) }
    let weights: [CGFloat] = r == 1 ? [1, 2, 1] : [1, 2, 3, 2, 1]
    var x: CGFloat = 0
    var y: CGFloat = 0
    var total: CGFloat = 0
    for (offset, weight) in zip(-r ... r, weights) {
      let p = point(k + offset)
      x += p.x * weight
      y += p.y * weight
      total += weight
    }
    return CGPoint(x: x / total, y: y / total)
  }

  private func segment(
    _ i: Int,
    count n: Int,
    sample: (Int) -> InkSample,
    length: (Int) -> CGFloat,
    total: CGFloat?,
    includeStart: Bool
  ) -> [Point] {
    func point(_ k: Int) -> CGPoint { Self.smoothed(k, count: n) { sample($0).point } }
    let p1 = point(i)
    let p2 = point(i + 1)
    // Past the ends the curve continues straight.
    let p0 = i > 0 ? point(i - 1) : CGPoint(x: 2 * p1.x - p2.x, y: 2 * p1.y - p2.y)
    let p3 = i + 2 < n ? point(i + 2) : CGPoint(x: 2 * p2.x - p1.x, y: 2 * p2.y - p1.y)
    let steps = max(1, min(12, Int((hypot(p2.x - p1.x, p2.y - p1.y) / Self.step).rounded(.up))))
    let (w1, w2) = (sample(i).width, sample(i + 1).width)
    let (l1, l2) = (length(i), length(i + 1))
    return ((includeStart ? 0 : 1) ... steps).map { k in
      let u = CGFloat(k) / CGFloat(steps)
      return Point(
        point: Self.catmullRom(p0, p1, p2, p3, u),
        radius: (w1 + (w2 - w1) * u) / 2 * Self.taper(along: l1 + (l2 - l1) * u, total: total)
      )
    }
  }

  static func taper(along: CGFloat, total: CGFloat?) -> CGFloat {
    func ramp(_ distance: CGFloat) -> CGFloat {
      let x = min(max(distance / taperLength, 0), 1)
      return taperTip + (1 - taperTip) * (1 - (1 - x) * (1 - x))
    }
    let start = ramp(along)
    guard let total else { return start }
    return min(start, ramp(total - along))
  }

  /// Centripetal Catmull-Rom (Barry and Goldman's form) from `p1` (u = 0) to `p2` (u = 1): no
  /// cusps or loops where points bunch up or spread out.
  static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ u: CGFloat) -> CGPoint {
    func knot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { max(sqrt(hypot(b.x - a.x, b.y - a.y)), 1e-4) }
    func mix(_ a: CGPoint, _ b: CGPoint, _ ta: CGFloat, _ tb: CGFloat, _ t: CGFloat) -> CGPoint {
      let w = (t - ta) / (tb - ta)
      return CGPoint(x: a.x + (b.x - a.x) * w, y: a.y + (b.y - a.y) * w)
    }
    let t0: CGFloat = 0
    let t1 = t0 + knot(p0, p1)
    let t2 = t1 + knot(p1, p2)
    let t3 = t2 + knot(p2, p3)
    let t = t1 + (t2 - t1) * u
    let a1 = mix(p0, p1, t0, t1, t)
    let a2 = mix(p1, p2, t1, t2, t)
    let a3 = mix(p2, p3, t2, t3, t)
    let b1 = mix(a1, a2, t0, t2, t)
    let b2 = mix(a2, a3, t1, t3, t)
    return mix(b1, b2, t1, t2, t)
  }

  /// Adds discs at `points` and quads between them to `path`, all wound the same way, so the
  /// nonzero fill is their union.
  static func add(_ points: [Point], to path: CGMutablePath) {
    var previous: Point?
    for point in points {
      path.move(to: CGPoint(x: point.point.x + point.radius, y: point.point.y))
      path.addArc(center: point.point, radius: point.radius, startAngle: 0, endAngle: -2 * .pi, clockwise: true)
      path.closeSubpath()
      if let a = previous {
        let dx = point.point.x - a.point.x
        let dy = point.point.y - a.point.y
        let distance = hypot(dx, dy)
        if distance > 0.01 {
          let nx = -dy / distance
          let ny = dx / distance
          path.move(to: CGPoint(x: a.point.x + nx * a.radius, y: a.point.y + ny * a.radius))
          path.addLine(to: CGPoint(x: point.point.x + nx * point.radius, y: point.point.y + ny * point.radius))
          path.addLine(to: CGPoint(x: point.point.x - nx * point.radius, y: point.point.y - ny * point.radius))
          path.addLine(to: CGPoint(x: a.point.x - nx * a.radius, y: a.point.y - ny * a.radius))
          path.closeSubpath()
        }
      }
      previous = point
    }
  }

  static func path(_ points: [Point]) -> CGPath {
    let path = CGMutablePath()
    add(points, to: path)
    return path
  }
}

/// When strokes fade. A stroke stays until `hold` after the pen last lifted, then fades over
/// `duration`. Strokes drawn in quick succession (a circle, then an arrow) are one group: putting
/// the pen down again before the group starts fading holds all of them, and they fade together.
nonisolated struct InkFade: Equatable {
  static let hold: TimeInterval = 1.5
  static let duration: TimeInterval = 0.3

  struct Group: Equatable {
    var strokes: [Int]
    var start: TimeInterval
  }

  /// Strokes on screen that haven't started fading.
  private(set) var held: [Int] = []
  /// When `held` starts fading; nil while the pen is down.
  private(set) var fadeAt: TimeInterval?
  private(set) var fading: [Group] = []
  private var penIsDown = false

  /// A stroke begins. Returns the earlier group if its time had already come.
  mutating func penDown(_ stroke: Int, at time: TimeInterval) -> Group? {
    let started = advance(to: time)
    held.append(stroke)
    penIsDown = true
    fadeAt = nil
    return started
  }

  mutating func penUp(at time: TimeInterval) {
    penIsDown = false
    fadeAt = held.isEmpty ? nil : time + Self.hold
  }

  /// Starts the held group fading if its time has come, and returns it.
  mutating func advance(to time: TimeInterval) -> Group? {
    guard !penIsDown, let fadeAt, fadeAt <= time, !held.isEmpty else { return nil }
    let group = Group(strokes: held, start: fadeAt)
    fading.append(group)
    held = []
    self.fadeAt = nil
    return group
  }

  /// Drops groups that have finished fading and returns their strokes.
  mutating func removeFaded(at time: TimeInterval) -> [Int] {
    let done = fading.filter { $0.start + Self.duration <= time }
    fading.removeAll { $0.start + Self.duration <= time }
    return done.flatMap(\.strokes)
  }

  /// 1 while held, easing out to 0 over `duration` once its group fades, 0 once gone.
  func opacity(of stroke: Int, at time: TimeInterval) -> Double {
    if held.contains(stroke) {
      guard !penIsDown, let fadeAt, time >= fadeAt else { return 1 }
      return Self.easeOut(fading: (time - fadeAt) / Self.duration)
    }
    guard let group = fading.first(where: { $0.strokes.contains(stroke) }) else { return 0 }
    return Self.easeOut(fading: (time - group.start) / Self.duration)
  }

  private static func easeOut(fading progress: Double) -> Double {
    let p = min(max(progress, 0), 1)
    return (1 - p) * (1 - p)
  }
}
#endif
