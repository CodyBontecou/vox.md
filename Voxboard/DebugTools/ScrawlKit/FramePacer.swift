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

/// Decides which display-link ticks `AppFrameRecorder` captures and which it skips so recording
/// yields to 120 Hz scrolling and animations on the main thread.
///
/// Time is passed in (seconds on `CACurrentMediaTime` / host clock), making the pacer a deterministic
/// value type that can be unit-tested without a display link.
nonisolated struct FramePacer: Equatable, Sendable {
  enum CaptureReason: Equatable, Sendable {
    case first
    case cadence
    case settled
    case starvationCap
  }

  enum SkipReason: Equatable, Sendable {
    case cadence
    case budgetTight
    case writerBusy
  }

  enum Decision: Equatable, Sendable {
    case capture(CaptureReason)
    case skip(SkipReason)
  }

  struct Metrics: Equatable, Sendable {
    var framesCaptured = 0
    var settledCatchUps = 0
    var ticksSkippedCadence = 0
    var ticksSkippedBudget = 0
    var ticksSkippedWriterBusy = 0
    var totalDrawMs = 0.0
    var maxDrawMs = 0.0
    var estimatedHitches120Hz = 0
    var estimatedHitches60Hz = 0

    var totalTicks: Int {
      framesCaptured + ticksSkippedCadence + ticksSkippedBudget + ticksSkippedWriterBusy
    }

    var meanDrawMs: Double {
      framesCaptured > 0 ? totalDrawMs / Double(framesCaptured) : 0
    }
  }

  /// Target interval when the UI is not actively scrolling or being dragged (30 fps).
  static let defaultIdleInterval: TimeInterval = 1.0 / 30.0
  /// Target interval while scrolling, dragging, or drawing (12 fps).
  static let defaultInteractionInterval: TimeInterval = 1.0 / 12.0
  /// Adaptive backoff never drops the target cadence below 10 fps (100 ms), keeping every timestamp
  /// within ±50 ms of a frame for `scrawl-helper`'s 80 ms keyframe decode tolerance.
  static let defaultMaxAdaptiveInterval: TimeInterval = 1.0 / 10.0
  /// Maximum gap allowed when skipping tight-budget ticks before forcing a capture anyway.
  static let defaultMaxStarvationInterval: TimeInterval = 0.14
  /// Minimum spacing before a settled catch-up frame after motion stops.
  static let defaultMinSettledInterval: TimeInterval = 1.0 / 60.0
  /// Hold window after touch-drag movement ends so momentum/spring settle isn't hitched.
  static let defaultSettleDelay: TimeInterval = 0.22
  /// Display-link jitter allowance so a 30 Hz link ticking at ~29.5–33.5 ms never skips every other tick.
  static let phaseTolerance: TimeInterval = 0.004
  static let proMotionBudget: TimeInterval = 1.0 / 120.0
  static let sixtyHzBudget: TimeInterval = 1.0 / 60.0

  var idleInterval: TimeInterval = FramePacer.defaultIdleInterval
  var interactionInterval: TimeInterval = FramePacer.defaultInteractionInterval
  var maxAdaptiveInterval: TimeInterval = FramePacer.defaultMaxAdaptiveInterval
  var maxStarvationInterval: TimeInterval = FramePacer.defaultMaxStarvationInterval
  var minSettledInterval: TimeInterval = FramePacer.defaultMinSettledInterval
  var settleDelay: TimeInterval = FramePacer.defaultSettleDelay

  private(set) var lastCaptureTime: TimeInterval?
  private(set) var lastInteractionTime: TimeInterval?
  private(set) var smoothedDrawDuration: TimeInterval?
  private(set) var lastCaptureWasInteracting = false
  private(set) var needsSettledFrame = false
  private(set) var metrics = Metrics()

  /// Records raw touch-drag or ink movement at `now`, holding interaction pacing for `settleDelay`.
  mutating func noteInteractionMovement(at now: TimeInterval) {
    lastInteractionTime = now
  }

  /// Whether interaction pacing is in effect at `now`.
  func isInteractionActive(explicit: Bool, at now: TimeInterval) -> Bool {
    if explicit { return true }
    guard let lastInteractionTime else { return false }
    return now >= lastInteractionTime && (now - lastInteractionTime) < settleDelay
  }

  /// Current target interval between captures, including adaptive draw-cost backoff.
  func targetInterval(interacting: Bool) -> TimeInterval {
    let base = interacting ? interactionInterval : idleInterval
    guard let draw = smoothedDrawDuration, draw > 0 else { return base }
    // Keep main-thread capture duty cycle under ~12.5% while scrolling and ~25% when idle.
    let multiplier = interacting ? 8.0 : 4.0
    return min(max(base, draw * multiplier), maxAdaptiveInterval)
  }

  /// Evaluates a display-link tick and decides whether to capture or skip.
  mutating func decide(
    linkTimestamp: TimeInterval,
    targetTimestamp: TimeInterval,
    now: TimeInterval,
    isInteracting: Bool,
    writerReady: Bool = true
  ) -> Decision {
    guard writerReady else {
      metrics.ticksSkippedWriterBusy += 1
      return .skip(.writerBusy)
    }
    let active = isInteractionActive(explicit: isInteracting, at: now)
    guard let lastCaptureTime else {
      return .capture(.first)
    }
    if !active, lastCaptureWasInteracting {
      needsSettledFrame = true
    }
    let elapsed = max(0, now - lastCaptureTime)

    if !active, needsSettledFrame, elapsed >= minSettledInterval - Self.phaseTolerance {
      if elapsed >= maxStarvationInterval || !isBudgetTight(linkTimestamp: linkTimestamp, targetTimestamp: targetTimestamp, now: now) {
        return .capture(.settled)
      }
      metrics.ticksSkippedBudget += 1
      return .skip(.budgetTight)
    }

    let required = targetInterval(interacting: active) - Self.phaseTolerance
    guard elapsed >= required else {
      metrics.ticksSkippedCadence += 1
      return .skip(.cadence)
    }

    if elapsed >= maxStarvationInterval {
      return .capture(.starvationCap)
    }
    if isBudgetTight(linkTimestamp: linkTimestamp, targetTimestamp: targetTimestamp, now: now) {
      metrics.ticksSkippedBudget += 1
      return .skip(.budgetTight)
    }
    return .capture(.cadence)
  }

  /// Records a completed frame draw and updates adaptive cost estimates and hitch counters.
  mutating func recordCapture(
    at now: TimeInterval,
    drawDuration: TimeInterval,
    turnElapsed: TimeInterval = 0,
    isInteracting: Bool
  ) {
    let active = isInteractionActive(explicit: isInteracting, at: now)
    lastCaptureTime = now
    if active {
      lastCaptureWasInteracting = true
    } else {
      if needsSettledFrame {
        metrics.settledCatchUps += 1
      }
      lastCaptureWasInteracting = false
      needsSettledFrame = false
    }
    let clamped = max(0, drawDuration)
    if let previous = smoothedDrawDuration {
      smoothedDrawDuration = previous * 0.65 + clamped * 0.35
    } else {
      smoothedDrawDuration = clamped
    }
    metrics.framesCaptured += 1
    let drawMs = clamped * 1000
    metrics.totalDrawMs += drawMs
    metrics.maxDrawMs = max(metrics.maxDrawMs, drawMs)
    let frameWork = max(0, turnElapsed) + clamped
    if frameWork > Self.proMotionBudget {
      metrics.estimatedHitches120Hz += 1
    }
    if frameWork > Self.sixtyHzBudget {
      metrics.estimatedHitches60Hz += 1
    }
  }

  /// True when the main thread has already spent significant time in this vsync turn (`> 1.8 ms`)
  /// and adding an estimated draw would exceed the 120 Hz frame budget or `targetTimestamp`.
  func isBudgetTight(
    linkTimestamp: TimeInterval,
    targetTimestamp: TimeInterval,
    now: TimeInterval
  ) -> Bool {
    let turnElapsed = max(0, now - linkTimestamp)
    guard turnElapsed > 0.0018 else { return false }
    let estimatedDraw = smoothedDrawDuration ?? 0.004
    if turnElapsed + estimatedDraw > Self.proMotionBudget {
      return true
    }
    if targetTimestamp > linkTimestamp, (targetTimestamp - now) < estimatedDraw {
      return true
    }
    return false
  }
}
#endif
