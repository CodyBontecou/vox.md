// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
#if os(iOS)
  import QuartzCore
  import UIKit

  /// The red ink drawn over the app while recording, in `OverlayWindow` under the strip.
  ///
  /// Every coalesced touch is a sample (the main thread is often busy drawing the recording's
  /// frames, so one sample per event made strokes jagged). Samples are smoothed and given a width
  /// by `InkStrokeBuilder`, and drawn by `InkTrace` as a curve. Each stroke has its own container
  /// layer: finished stretches go into chunk layers that never change, and only the live tip (the
  /// last few points, through iOS's predicted touches) is redrawn on each touch. Predicted points
  /// are dropped on the next event and never recorded.
  ///
  /// Strokes fade `InkFade.hold` after the pen last lifted, together with any drawn just before.
  final class InkView: UIView {
    /// Records a finished stroke (smoothed, unpredicted samples); returns its timeline index.
    var onStroke: @MainActor ([InkSample]) -> Int? = { _ in nil }
    /// Strokes (timeline indices) started fading at `uptime`.
    var onFade: @MainActor ([Int], TimeInterval) -> Void = { _, _ in }

    private final class Stroke {
      let container = CALayer()
      let live = CAShapeLayer()
      var builder = InkStrokeBuilder()
      var trace = InkTrace()
      /// Frozen stretches not yet moved into a chunk layer of their own.
      var open = CGMutablePath()
      var openCount = 0
      var logIndex: Int?
    }

    /// Frozen curve points per chunk layer: the live layer redraws at most this many plus the tip.
    private static let chunkPoints = 48
    private static let red = UIColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1).cgColor

    private var strokes: [Int: Stroke] = [:]
    private var active: (id: Int, stroke: Stroke)?
    private var nextID = 1
    private var fade = InkFade()
    private var fadeTimer: Task<Void, Never>?

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      backgroundColor = .clear
      autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    // MARK: Touches

    func began(_ touch: UITouch, with event: UIEvent?) {
      let id = nextID
      nextID += 1
      let stroke = Stroke()
      withoutAnimation {
        stroke.container.frame = bounds
        stroke.live.fillColor = Self.red
        stroke.live.fillRule = .nonZero
        stroke.container.addSublayer(stroke.live)
        layer.addSublayer(stroke.container)
      }
      strokes[id] = stroke
      active = (id, stroke)
      fadeTimer?.cancel()
      if let group = fade.penDown(id, at: touch.timestamp) { startFading(group) }
      add(coalesced(touch, event), to: stroke)
      draw(stroke, predicted: event?.predictedTouches(for: touch) ?? [])
    }

    func moved(_ touch: UITouch, with event: UIEvent?) {
      guard let stroke = active?.stroke else { return }
      add(coalesced(touch, event), to: stroke)
      draw(stroke, predicted: event?.predictedTouches(for: touch) ?? [])
    }

    /// The finger lifted (or the touch was cancelled): the stroke ends where it was, with its end
    /// tapered, and goes on the timeline.
    func ended(_ touch: UITouch, with event: UIEvent?) {
      guard let (_, stroke) = active else { return }
      active = nil
      add(coalesced(touch, event), to: stroke)
      stroke.builder.finish(at: touch.preciseLocation(in: self), time: touch.timestamp)
      freeze(stroke)
      setLive(stroke, stroke.trace.tail(finished: true))
      stroke.logIndex = onStroke(stroke.trace.smoothedSamples)
      fade.penUp(at: touch.timestamp)
      scheduleFade()
    }

    /// Removes all ink (a new recording, or this one finished), fading it quickly if `animated`.
    func clear(animated: Bool) {
      fadeTimer?.cancel()
      fadeTimer = nil
      active = nil
      fade = InkFade()
      let containers = strokes.values.map(\.container)
      strokes = [:]
      guard animated else {
        withoutAnimation { containers.forEach { $0.removeFromSuperlayer() } }
        return
      }
      CATransaction.begin()
      CATransaction.setCompletionBlock { containers.forEach { $0.removeFromSuperlayer() } }
      for container in containers {
        Self.fadeOut(container, duration: 0.2)
      }
      CATransaction.commit()
    }

    // MARK: Drawing

    private func coalesced(_ touch: UITouch, _ event: UIEvent?) -> [UITouch] {
      let touches = event?.coalescedTouches(for: touch) ?? []
      return touches.isEmpty ? [touch] : touches
    }

    private func add(_ touches: [UITouch], to stroke: Stroke) {
      for touch in touches {
        stroke.builder.add(touch.preciseLocation(in: self), at: touch.timestamp)
      }
    }

    private func draw(_ stroke: Stroke, predicted: [UITouch]) {
      freeze(stroke)
      let ahead = stroke.builder.predicting(predicted.map { ($0.preciseLocation(in: self), $0.timestamp) })
      setLive(stroke, stroke.trace.tail(predicted: ahead))
    }

    /// Hands new samples to the trace and moves what became final out of the live layer.
    private func freeze(_ stroke: Stroke) {
      stroke.trace.append(stroke.builder.samples[stroke.trace.samples.count...])
      let frozen = stroke.trace.freeze()
      guard !frozen.isEmpty else { return }
      InkTrace.add(frozen, to: stroke.open)
      stroke.openCount += frozen.count
      guard stroke.openCount >= Self.chunkPoints else { return }
      let chunk = CAShapeLayer()
      chunk.fillColor = Self.red
      chunk.fillRule = .nonZero
      chunk.path = stroke.open.copy()
      withoutAnimation { stroke.container.insertSublayer(chunk, below: stroke.live) }
      stroke.open = CGMutablePath()
      stroke.openCount = 0
    }

    private func setLive(_ stroke: Stroke, _ tail: [InkTrace.Point]) {
      let path = stroke.open.mutableCopy() ?? CGMutablePath()
      InkTrace.add(tail, to: path)
      withoutAnimation { stroke.live.path = path }
    }

    // MARK: Fading

    private func scheduleFade() {
      fadeTimer?.cancel()
      guard let at = fade.fadeAt else { return }
      let delay = max(at - ProcessInfo.processInfo.systemUptime, 0)
      fadeTimer = Task { [weak self] in
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled, let self else { return }
        if let group = self.fade.advance(to: ProcessInfo.processInfo.systemUptime) { self.startFading(group) }
      }
    }

    private func startFading(_ group: InkFade.Group) {
      let fading = group.strokes.compactMap { strokes[$0] }
      onFade(fading.compactMap(\.logIndex), group.start)
      for stroke in fading {
        Self.fadeOut(stroke.container, duration: InkFade.duration)
      }
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(InkFade.duration + 0.05))
        guard let self else { return }
        for id in self.fade.removeFaded(at: ProcessInfo.processInfo.systemUptime) {
          self.strokes.removeValue(forKey: id)?.container.removeFromSuperlayer()
        }
      }
    }

    private static func fadeOut(_ layer: CALayer, duration: TimeInterval) {
      let animation = CABasicAnimation(keyPath: "opacity")
      animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
      animation.toValue = 0
      animation.duration = duration
      animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer.opacity = 0
      layer.add(animation, forKey: "fade")
    }

    private func withoutAnimation(_ body: () -> Void) {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      body()
      CATransaction.commit()
    }
  }
#endif
#endif
