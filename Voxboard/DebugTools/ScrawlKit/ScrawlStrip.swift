// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
#if os(iOS)
  import Combine
  import QuartzCore
  import SwiftUI
  import UIKit

  nonisolated extension Color {
    /// #FF3B30, Scrawl's ink.
    static let scrawlRed = Color(red: 1.0, green: 0.231, blue: 0.188)
  }

  /// Parts of the overlay that take touches; everything else passes through to the app.
  nonisolated enum OverlayRegion: Hashable {
    case strip, bubble
  }

  /// The screen edge the strip sits on.
  nonisolated enum StripSide: String {
    case leading, trailing
  }

  /// The recording controls: a slim vertical strip on one edge of the screen.
  ///
  /// - Dot: pulses while recording; its ring fills once a minute. Hold it to see the elapsed time,
  ///   drag it to move the strip.
  /// - Draw (toggles drawing), Discard (with Undo), Send.
  ///
  /// Its motion is the "Liquid morph" prototype Kit chose (`site/public/prototype/strip`, variant
  /// A): one glass body that stretches out of a droplet, pours into the button you tap, buds
  /// bubbles off a liquid neck, and squashes as it's thrown. `LiquidStrip` runs the springs; this
  /// view draws its geometry.
  struct ScrawlStrip: View {
    enum Mode: Equatable {
      case recording(startedAt: Date, isDrawing: Bool)
      case sending(Sending)
      /// The server took it; what it said became of it.
      case sent(IngestReply)
      /// Saved on the phone; sends in the background when it can.
      case queued
      case failed(Failure)
      case discarded

      enum Phase {
        case recording, sending, sent, queued, failed, discarded
      }

      var phase: Phase {
        switch self {
        case .recording: .recording
        case .sending: .sending
        case .sent: .sent
        case .queued: .queued
        case .failed: .failed
        case .discarded: .discarded
        }
      }
    }

    /// An upload in progress: `progress` (0…1) once it reports bytes; `stalled` when it's on a
    /// working network but hasn't moved in a while.
    struct Sending: Equatable {
      var progress: Double?
      var stalled = false
    }

    /// Why a recording didn't send; every failure keeps Share.
    enum Failure: Equatable {
      case unreachable, linkExpired, tooLarge, rejected, notSaved

      init(_ failure: Outbox.Failure) {
        switch failure {
        case .unauthorized: self = .linkExpired
        case .tooLarge: self = .tooLarge
        case .rejected: self = .rejected
        }
      }

      var notice: Notice {
        switch self {
        case .unreachable: Notice("Mac didn't answer")
        case .linkExpired: Notice("Scrawl link expired", detail: "Ask Kit for a new one")
        case .tooLarge: Notice("Too large to send")
        case .rejected: Notice("Couldn't send", detail: "The server rejected it")
        case .notSaved: Notice("Couldn't save to send")
        }
      }
    }

    /// A short message in a bubble: one line, or two with `detail` (so long ones stay narrow).
    struct Notice: Equatable {
      var title: String
      var detail: String?

      init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
      }

      static let linkExpired = Failure.linkExpired.notice
    }

    struct Actions {
      var toggleDrawing: @MainActor () -> Void = {}
      var discard: @MainActor () -> Void = {}
      var send: @MainActor () -> Void = {}
      var undoDiscard: @MainActor () -> Void = {}
      var share: @MainActor () -> Void = {}
      var reportFrame: @MainActor (OverlayRegion, CGRect) -> Void = { _, _ in }
      /// The dot moved: translation since touch down and velocity (points per second).
      var gripMoved: @MainActor (CGSize, CGSize) -> Void = { _, _ in }
      /// The dot was let go: translation and velocity.
      var gripEnded: @MainActor (CGSize, CGSize) -> Void = { _, _ in }
      /// The dot's gesture ended, normally or not (called after `gripEnded`).
      var gripFinished: @MainActor () -> Void = {}
      /// The dot is being held still (shows the elapsed time).
      var holdChanged: @MainActor (Bool) -> Void = { _ in }
    }

    static let width: CGFloat = 42
    static let expandedHeight: CGFloat = Metrics.dotRow + Metrics.row * 3 + Metrics.divider
    /// How far the dot moves before a hold becomes a drag.
    static let dragThreshold: CGFloat = 8

    let model: LiquidStrip
    var actions = Actions()
    /// Identifies the glass shapes so they blend and morph together (iOS 26).
    let glass: Namespace.ID

    @GestureState private var dotPress = DotPress.idle
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scrawlStartupTrace) private var startupTrace

    private enum DotPress {
      case idle, holding, dragging
    }

    var body: some View {
      let geometry = model.geometry
      ZStack(alignment: .topLeading) {
        Color.clear
        LiquidGlass(geometry: geometry, isPresent: model.isPresent, namespace: glass)
        regions(geometry)
        controls(geometry)
          .frame(width: Metrics.hit)
          .position(geometry.column)
          .allowsHitTesting(geometry.controlsLive)
        if let phase = model.statusIcon {
          statusIcon(phase)
            .frame(width: Self.width, height: Self.width)
            .scaleEffect(geometry.iconScale)
            .opacity(geometry.iconOpacity)
            .position(geometry.icon)
            .allowsHitTesting(false)
        }
        if let bubble = model.bubble {
          bubbleContent(bubble)
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { model.measuredBubble($0, for: bubble) })
            .opacity(geometry.bubbleOpacity)
            .position(geometry.bubbleCenter)
            .allowsHitTesting(geometry.bubbleInteractive)
            .accessibilityHidden(geometry.bubbleOpacity < 0.3)
        }
      }
      .onChange(of: dotPress) { _, press in
        actions.holdChanged(press == .holding)
        if press == .idle { actions.gripFinished() }
      }
      .background {
        if let startupTrace {
          StartupDrawProbe(trace: startupTrace, visible: geometry.alpha > 0.05 && !geometry.body.isEmpty)
        }
      }
    }

    /// Invisible rectangles that tell `OverlayWindow` where touches belong to the strip. Each is
    /// measured before `.position`, which expands a view to fill its parent: measured after it, the
    /// region was the whole screen and the overlay swallowed every tap meant for the app. The status
    /// circle (sending, sent, …) has no controls, so touches on it reach the app.
    @ViewBuilder private func regions(_ geometry: LiquidStrip.Geometry) -> some View {
      if geometry.alpha > 0.05, geometry.controlsLive, !geometry.body.isEmpty {
        Color.clear
          .frame(width: geometry.body.width, height: geometry.body.height)
          .reportFrame(.strip, to: actions.reportFrame)
          .position(x: geometry.body.midX, y: geometry.body.midY)
          .allowsHitTesting(false)
      }
      if geometry.bubbleInteractive, let bubble = geometry.bubble {
        Color.clear
          .frame(width: bubble.width, height: bubble.height)
          .reportFrame(.bubble, to: actions.reportFrame)
          .position(x: bubble.midX, y: bubble.midY)
          .allowsHitTesting(false)
      }
    }

    private func controls(_ geometry: LiquidStrip.Geometry) -> some View {
      VStack(spacing: 0) {
        RecordingDot(startedAt: model.startedAt)
          .frame(width: Metrics.hit, height: Metrics.dotRow)
          .contentShape(Rectangle())
          .gesture(grip)
          .accessibilityHint(Text(verbatim: "Hold to show the time. Drag to move the controls."))
          .rowMotion(geometry.rows[0])

        StripButton(
          label: "Draw",
          value: model.isDrawing ? "On" : "Off",
          isActive: model.isDrawing,
          action: actions.toggleDrawing
        ) {
          Image(systemName: "pencil.tip")
        }
        .rowMotion(geometry.rows[1])

        Rectangle()
          .fill(.white.opacity(0.2))
          .frame(width: 18, height: 1 / displayScale)
          .frame(height: Metrics.divider)
          .accessibilityHidden(true)
          .rowMotion(geometry.rows[2])

        StripButton(label: "Discard recording", action: actions.discard) {
          Image(systemName: "xmark")
        }
        .rowMotion(geometry.rows[3])

        Button { actions.send() } label: {
          Image(systemName: "arrow.up")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color.scrawlRed, in: .circle)
            .frame(width: Metrics.hit, height: Metrics.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(StripButtonStyle())
        .accessibilityLabel(Text(verbatim: "Send recording"))
        .rowMotion(geometry.rows[4])
      }
    }

    /// Press the dot to show the time; move it past `dragThreshold` to drag the strip instead.
    private var grip: some Gesture {
      DragGesture(minimumDistance: 0, coordinateSpace: .global)
        .updating($dotPress) { value, press, _ in
          press = press == .dragging || value.translation.magnitude > Self.dragThreshold ? .dragging : .holding
        }
        .onChanged { value in actions.gripMoved(value.translation, value.velocity) }
        .onEnded { value in actions.gripEnded(value.translation, value.velocity) }
    }

    @ViewBuilder private func statusIcon(_ phase: Mode.Phase) -> some View {
      switch phase {
      case .recording:
        EmptyView()
      case .sending:
        if let progress = model.sendProgress {
          ZStack {
            Circle()
              .stroke(.white.opacity(0.22), lineWidth: 2.5)
            Circle()
              .trim(from: 0, to: max(progress, 0.02))
              .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
              .rotationEffect(.degrees(-90))
              .animation(.easeOut(duration: 0.3), value: progress)
          }
          .frame(width: 22, height: 22)
          .accessibilityElement()
          .accessibilityLabel(Text(verbatim: "Sending recording"))
          .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
        } else {
          ProgressView()
            .controlSize(.small)
            .tint(.white)
            .accessibilityLabel(Text(verbatim: "Sending recording"))
        }
      case .sent:
        Image(systemName: "checkmark")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.green)
          .accessibilityLabel(Text(verbatim: "Sent"))
      case .queued:
        Image(systemName: "tray.and.arrow.up")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.white.opacity(0.85))
          .accessibilityLabel(Text(verbatim: "Recording queued"))
      case .failed:
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.yellow)
          .accessibilityLabel(Text(verbatim: "Not sent"))
      case .discarded:
        Image(systemName: "trash")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.white.opacity(0.6))
          .accessibilityLabel(Text(verbatim: "Recording discarded"))
      }
    }

    /// A bubble's text at its natural size; the glass behind it is drawn by `LiquidGlass`.
    @ViewBuilder private func bubbleContent(_ bubble: LiquidStrip.Bubble) -> some View {
      Group {
        switch bubble {
        case .elapsed:
          ElapsedText(startedAt: model.startedAt)
        case let .sent(reply):
          sentText(reply)
        case let .sending(stalled):
          Text(stalled ? "Still sending…" : "Sending…")
        case .queued:
          Text(verbatim: "Queued · sends when online")
        case let .notice(notice):
          noticeText(notice)
        case let .failed(failure):
          HStack(spacing: 8) {
            noticeText(failure.notice)
            Button { actions.share() } label: {
              Label { Text(verbatim: "Share") } icon: { Image(systemName: "square.and.arrow.up") }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.white.opacity(0.18), in: .capsule)
                .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.plain)
          }
        case .discarded:
          HStack(spacing: 6) {
            Text(verbatim: "Discarded")
              .foregroundStyle(.white.opacity(0.75))
            Text(verbatim: "·")
              .foregroundStyle(.white.opacity(0.4))
              .accessibilityHidden(true)
            Button { actions.undoDiscard() } label: {
              Text(verbatim: "Undo")
                .foregroundStyle(.white)
                .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Undo discard"))
          }
        }
      }
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.white)
      .lineLimit(1)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .fixedSize()
    }

    @ViewBuilder private func noticeText(_ notice: Notice) -> some View {
      if let detail = notice.detail {
        VStack(alignment: .leading, spacing: 1) {
          Text(notice.title)
          Text(detail)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.75))
        }
        .accessibilityElement(children: .combine)
      } else {
        Text(notice.title)
      }
    }

    /// Delivered reads as one line; on the Mac but not yet delivered takes two, so the
    /// session's name fits.
    @ViewBuilder private func sentText(_ reply: IngestReply) -> some View {
      switch reply {
      case let .delivered(title):
        Text(verbatim: "Sent to \(Self.shortened(title))")
      case let .queued(title):
        noticeText(Notice("On your Mac", detail: "Sends to \(Self.shortened(title, to: 24)) when it can"))
      case let .processing(title):
        noticeText(Notice("On your Mac", detail: "Sending to \(Self.shortened(title, to: 30))…"))
      case .saved:
        Text(verbatim: "Saved on your Mac")
      }
    }

    private static func shortened(_ target: String, to length: Int = 36) -> String {
      target.count > length ? String(target.prefix(length)) + "…" : target
    }
  }

  nonisolated private enum Metrics {
    /// Minimum touch target.
    static let hit: CGFloat = 44
    static let row: CGFloat = 44
    /// The dot sits at the centre of the strip's rounded top.
    static let dotRow: CGFloat = ScrawlStrip.width
    static let divider: CGFloat = 9
    /// Each row's centre relative to the strip's centre: dot, draw, divider, discard, send.
    static let rowCenters: [Double] = {
      var top = -Double(ScrawlStrip.expandedHeight) / 2
      return [dotRow, row, divider, row, row].map { height in
        defer { top += Double(height) }
        return top + Double(height) / 2
      }
    }()

    static let dotIndex = 0, discardIndex = 3, sendIndex = 4
    /// The droplet a hidden bubble shrinks to, tucked inside the body.
    static let hiddenBubble = 28.0
    static let hiddenBubbleGap = -35.0
    /// How far a settled bubble sits from the strip.
    static let bubbleGap = 8.0
    /// Glass shapes closer than this blend into one (iOS 26), so a bubble shows a neck while it
    /// buds off or is absorbed and separates once it's settled `bubbleGap` away.
    static let glassSpacing: CGFloat = 7
    /// The prototype's neck reach for the iOS 18 shape (`LiquidShape`).
    static let neckReach = 18.0
    static let glassTint = 0.45
  }

  // MARK: - Motion

  /// Every spring and timing of prototype variant A ("Liquid morph", chosen by Kit) at its default
  /// knobs: response 0.42 s, bounce 0.18, exit 0.34 s, stagger 0.045 s. The prototype uses
  /// SwiftUI's mapping (stiffness (2π/d)², damping 4π(1−b)/d), so these are its exact springs; its
  /// "× m" configs are written out as durations.
  nonisolated enum StripMotion {
    /// The knobs: appearing, pouring, settling.
    static let change = Spring(duration: 0.42, bounce: 0.18)
    /// Half the response, no bounce: the glass fading in, the icon fading out.
    static let quick = Spring(duration: 0.21, bounce: 0)
    /// Leaving: sliding off after send, shrinking after discard.
    static let exit = Spring(duration: 0.34, bounce: 0)
    /// The glass fading away after send (exit × 1.25).
    static let exitFade = Spring(duration: 0.425, bounce: 0)
    /// The bottom edge as the droplet stretches (× 1.12), and as it pours (× 1.15): the near
    /// edge lags the far one.
    static let stretchLag = Spring(duration: 0.4704, bounce: 0.18)
    static let pourLag = Spring(duration: 0.483, bounce: 0.18)
    /// The droplet's squash relaxing (× 1.1, bounce + 0.2).
    static let unsquash = Spring(duration: 0.462, bounce: 0.38)
    /// Stretch along a throw (× 0.55, bounce 0.35).
    static let throwStretch = Spring(duration: 0.231, bounce: 0.35)
    /// The failed send's shake (× 0.45, bounce 0.55).
    static let shake = Spring(duration: 0.189, bounce: 0.55)
    /// Controls fanning out (× 0.8), gathering into the tapped button (× 0.7), fading (× 0.4).
    static let rowIn = Spring(duration: 0.336, bounce: 0)
    static let rowGather = Spring(duration: 0.294, bounce: 0)
    static let rowOut = Spring(duration: 0.168, bounce: 0)
    /// The status icon fading in (× 0.7) and popping from half size (× 0.8, with bounce).
    static let iconIn = Spring(duration: 0.294, bounce: 0)
    static let iconPop = Spring(duration: 0.336, bounce: 0.18)
    /// A bubble budding out (× 1.05, bounce + 0.2), growing (× 1, × 0.9), its text fading in
    /// (× 1.25); and being absorbed (× 0.9) with its text gone first (× 0.35).
    static let bubbleBud = Spring(duration: 0.441, bounce: 0.38)
    static let bubbleWidth = Spring(duration: 0.42, bounce: 0.18)
    static let bubbleHeight = Spring(duration: 0.378, bounce: 0.18)
    static let bubbleTextIn = Spring(duration: 0.525, bounce: 0)
    static let bubbleTextOut = Spring(duration: 0.147, bounce: 0)
    static let bubbleAbsorb = Spring(duration: 0.378, bounce: 0)

    /// Between rows fanning out from the middle.
    static let stagger = 0.045
    static let fanDelay = 0.04
    /// The pour runs this long before the status icon appears in the button.
    static let iconSwapDelay = 0.12
    /// Bubbles bud off once the pour has landed (or sooner between statuses).
    static let bubbleDelayAfterPour = 0.3
    static let bubbleDelay = 0.18
    /// "Sending…" waits this long, so a quick upload goes straight to "Sent to …".
    static let sendingBubbleDelay = 1.2
    static let shakeDelay = 0.06
    /// Sideways kick (points per second) for the failed shake.
    static let shakeVelocity = 900.0
    /// Scale kick when the status changes in place.
    static let gulpVelocity = 1.4
    /// Before leaving from a status, its bubble is absorbed.
    static let exitDelay = 0.22
    /// Throw speed (points per second) at which the stretch maxes out, and how far it goes.
    static let stretchSpeed = 2600.0
    static let maxStretch = 0.3
    /// Reduce Motion: fade out, change, fade in.
    static let reducedFade = 0.11
    /// Glass (de)materialising as the strip appears and once it has faded.
    static let glassPresence = Animation.smooth(duration: 0.2)

    /// How long the overlay window stays after the strip is told to leave: the bubble absorbed,
    /// then the slowest exit spring settled, plus a couple of frames.
    static var overlayLinger: Duration {
      .milliseconds(Int(((exitDelay + exitFade.settlingDuration) + 0.05) * 1000))
    }
  }

  // MARK: - Liquid strip model

  /// The strip's springs, in the overlay's coordinates. A display link steps them only while
  /// something is moving (SwiftUI's `Spring.update`), and `geometry` is what `ScrawlStrip` draws.
  /// A hand-run spring set, rather than `withAnimation`, because the motion needs per-edge springs
  /// (the far edge leads a pour), staggered per-row springs, velocity kicks (shake, throw), and
  /// stretch that follows a drag's speed.
  @MainActor
  @Observable
  final class LiquidStrip {
    typealias Phase = ScrawlStrip.Mode.Phase

    struct Row: Equatable {
      var opacity = 0.0
      var offset: CGFloat = 0
      var scale: CGFloat = 1
    }

    struct Geometry: Equatable {
      var alpha = 0.0
      var body = CGRect.zero
      var column = CGPoint.zero
      var rows = Array(repeating: Row(), count: 5)
      var controlsLive = false
      var icon = CGPoint.zero
      var iconScale: CGFloat = 1
      var iconOpacity = 0.0
      var bubble: CGRect?
      var bubbleCenter = CGPoint.zero
      var bubbleGap = 0.0
      var bubbleOpacity = 0.0
      var bubbleInteractive = false
      /// +1 on the right edge, −1 on the left.
      var direction: CGFloat = 1
    }

    enum Bubble: Equatable {
      case elapsed, sent(IngestReply), queued, failed(ScrawlStrip.Failure), discarded
      case sending(stalled: Bool)
      /// A message while recording (link expired, the length cap).
      case notice(ScrawlStrip.Notice)

      /// Only bubbles with a button (Share, Undo) take touches; the rest let them reach the app.
      var isInteractive: Bool {
        switch self {
        case .failed, .discarded: true
        default: false
        }
      }

      /// Bubbles beside the dot rather than the status circle.
      var isRecording: Bool {
        switch self {
        case .elapsed, .notice: true
        default: false
        }
      }
    }

    private(set) var geometry = Geometry()
    private(set) var statusIcon: Phase?
    /// The bubble's text (kept while it's absorbed).
    private(set) var bubble: Bubble?
    /// Whether the glass exists; false once an exit has faded it.
    private(set) var isPresent = false
    private(set) var startedAt = Date()
    private(set) var isDrawing = false
    /// How much of the upload has gone out, while sending.
    private(set) var sendProgress: Double?
    @ObservationIgnored private var sendStalled = false

    @ObservationIgnored var side = StripSide.trailing {
      didSet { if side != oldValue { wake() } }
    }

    @ObservationIgnored var reduceMotion = false

    private enum Key: Int, CaseIterable {
      case alpha, slide, scale, top, bottom, squashX, squashY, throwX, throwY, shake
      case gather, iconAlpha, iconScale, row0, row1, row2, row3, row4
      case bubbleWidth, bubbleHeight, bubbleGap, bubbleAlpha, placeX, placeY
    }

    private struct Value {
      var value: Double
      var velocity = 0.0
      var target: Double
      var spring = StripMotion.change

      init(_ value: Double) {
        self.value = value
        target = value
      }

      var isSettled: Bool { velocity == 0 && value == target }

      mutating func step(_ dt: Double) {
        guard !isSettled else { return }
        // Small substeps, as in the prototype, keep stiff springs stable on long frames.
        let steps = max(1, Int((dt / 0.004).rounded(.up)))
        for _ in 0 ..< steps {
          spring.update(value: &value, velocity: &velocity, target: target, deltaTime: dt / Double(steps))
        }
        if abs(velocity) < 0.01, abs(value - target) < 0.001 {
          value = target
          velocity = 0
        }
      }
    }

    private struct Timer {
      let at: Double
      let run: (LiquidStrip) -> Void
    }

    private struct Fade {
      let from: Double
      let to: Double
      let start: Double
      let done: ((LiquidStrip) -> Void)?
    }

    @ObservationIgnored private var values: [Value] = Key.allCases.map { key in
      switch key {
      case .slide: Value(16)
      case .scale, .squashX, .squashY, .throwX, .throwY, .iconScale: Value(1)
      case .top: Value(-21)
      case .bottom: Value(21)
      case .bubbleWidth, .bubbleHeight: Value(Metrics.hiddenBubble)
      case .bubbleGap: Value(Metrics.hiddenBubbleGap)
      default: Value(0)
      }
    }

    @ObservationIgnored private var phase: Phase?
    @ObservationIgnored private var clock = 0.0
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var fade: Fade?
    @ObservationIgnored private var fadeLevel = 1.0
    @ObservationIgnored private var instant = false
    @ObservationIgnored private var exiting = false
    @ObservationIgnored private var holding = false
    /// Where the controls gather from or into, relative to the strip's centre.
    @ObservationIgnored private var gatherY = 0.0
    @ObservationIgnored private var bubbleActive = false
    @ObservationIgnored private var notice: ScrawlStrip.Notice?
    @ObservationIgnored private var bubbleY = 0.0
    @ObservationIgnored private var measured: (bubble: Bubble, size: CGSize)?
    @ObservationIgnored private var restPoint: CGPoint?
    @ObservationIgnored private var held = false
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?

    // MARK: Inputs

    /// The strip's state from `Scrawl`. A new phase starts its transition.
    func apply(_ mode: ScrawlStrip.Mode?) {
      if case let .recording(startedAt, isDrawing) = mode {
        if self.startedAt != startedAt { self.startedAt = startedAt }
        if self.isDrawing != isDrawing { self.isDrawing = isDrawing }
      }
      if case let .sending(sending) = mode {
        if sendProgress != sending.progress { sendProgress = sending.progress }
        if sendStalled != sending.stalled {
          sendStalled = sending.stalled
          // Already saying "Sending…": the text changes in place.
          if phase == .sending, bubbleActive, case .sending = bubble {
            let change: (LiquidStrip) -> Void = { $0.showBubble(.sending(stalled: $0.sendStalled)) }
            if reduceMotion { applyInstant(change) } else { change(self) }
            wake()
          }
        }
      }
      let previous = phase
      let next = mode?.phase
      guard next != previous else { return }
      phase = next
      if next != .recording {
        holding = false
        held = false
      }
      if next == .recording, previous == nil, let restPoint {
        set(.placeX, restPoint.x)
        set(.placeY, restPoint.y)
      }
      let transition: (LiquidStrip) -> Void = { strip in
        strip.timers.removeAll()
        strip.exiting = false
        switch next {
        case .recording:
          strip.toStrip(from: previous)
          if strip.notice != nil { strip.after(StripMotion.bubbleDelayAfterPour) { $0.showRecordingBubble() } }
        case nil: strip.toGone(from: previous)
        case let status?: strip.toStatus(status, mode: mode, from: previous)
        }
      }
      if reduceMotion { reducedSwap(transition) } else { transition(self) }
      wake()
    }

    /// The dot is held still (elapsed-time bubble) or not.
    func setHolding(_ isHolding: Bool) {
      guard phase == .recording, isHolding != holding else { return }
      holding = isHolding
      let change: (LiquidStrip) -> Void = { strip in
        if isHolding {
          strip.showBubble(.elapsed)
        } else if strip.bubbleActive {
          strip.showRecordingBubble()
        }
      }
      if reduceMotion { applyInstant(change) } else { change(self) }
      wake()
    }

    /// A message beside the dot while recording; holding the dot shows the time over it.
    func setNotice(_ notice: ScrawlStrip.Notice?) {
      guard notice != self.notice else { return }
      self.notice = notice
      guard phase == .recording, !holding else { return }
      let change: (LiquidStrip) -> Void = { $0.showRecordingBubble() }
      if reduceMotion { applyInstant(change) } else { change(self) }
      wake()
    }

    /// While recording and not held: the notice if there is one, otherwise no bubble.
    private func showRecordingBubble() {
      guard phase == .recording, !holding else { return }
      if let notice {
        showBubble(.notice(notice))
      } else if bubbleActive {
        hideBubble()
      }
    }

    /// The bubble's text measured at its natural size.
    func measuredBubble(_ size: CGSize, for bubble: Bubble) {
      measured = (bubble, size)
      guard bubbleActive, self.bubble == bubble else { return }
      to(.bubbleWidth, size.width, StripMotion.bubbleWidth)
      to(.bubbleHeight, size.height, StripMotion.bubbleHeight)
      wake()
    }

    /// Where the strip rests: its edge and height in the current safe area.
    func rest(at point: CGPoint, animated: Bool) {
      let first = restPoint == nil
      restPoint = point
      guard !held else { return }
      if animated, !first, !reduceMotion {
        to(.placeX, point.x, StripMotion.change)
        to(.placeY, point.y, StripMotion.change)
      } else {
        set(.placeX, point.x)
        set(.placeY, point.y)
      }
      wake()
    }

    var place: CGPoint { CGPoint(x: self[.placeX], y: self[.placeY]) }

    /// Follows a drag exactly, keeping its velocity for the stretch.
    func drag(to point: CGPoint, velocity: CGSize) {
      held = true
      set(.placeX, point.x, velocity: velocity.width)
      set(.placeY, point.y, velocity: velocity.height)
      wake()
    }

    /// Lets go with the throw's velocity; call `rest(at:animated:)` with where it lands.
    func release(velocity: CGSize) {
      held = false
      values[Key.placeX.rawValue].velocity = velocity.width
      values[Key.placeY.rawValue].velocity = velocity.height
      wake()
    }

    // MARK: Transitions (variant A's flows)

    /// A squashed droplet stretches into the strip while the controls fan out from the middle.
    private func toStrip(from previous: Phase?) {
      let fresh = previous == nil || self[.alpha] < 0.3
      hideBubble(now: fresh)
      if fresh {
        set(.slide, 18)
        // The first frame already contains the droplet; hardware startup must never leave
        // an empty window. Keep the existing stretch/fan transition from this visible seed.
        set(.alpha, 0.15)
        set(.scale, 0.9)
        set(.top, -21)
        set(.bottom, 21)
        set(.squashX, 1.2)
        set(.squashY, 0.85)
        set(.gather, 1)
        gatherY = 0
        for key in Self.rowKeys { set(key, 0) }
        set(.iconAlpha, 0)
        statusIcon = nil
        present(true)
      } else {
        gatherY = (self[.top] + self[.bottom]) / 2
        set(.gather, 1)
        to(.iconAlpha, 0, StripMotion.quick)
      }
      to(.alpha, 1, StripMotion.quick)
      to(.slide, 0, StripMotion.change)
      to(.scale, 1, StripMotion.change)
      to(.squashX, 1, StripMotion.unsquash)
      to(.squashY, 1, StripMotion.unsquash)
      to(.top, -Double(ScrawlStrip.expandedHeight) / 2, StripMotion.change)
      to(.bottom, Double(ScrawlStrip.expandedHeight) / 2, StripMotion.stretchLag)
      to(.gather, 0, StripMotion.change)
      // Middle row first, then outward.
      let ring = [2, 1, 0, 1, 2]
      for (index, key) in Self.rowKeys.enumerated() {
        after(StripMotion.fanDelay + Double(ring[index]) * StripMotion.stagger) { $0.to(key, 1, StripMotion.rowIn) }
      }
    }

    /// The body pours into the tapped button (far edge first), becomes its status circle, and
    /// buds the status bubble off.
    private func toStatus(_ status: Phase, mode: ScrawlStrip.Mode?, from previous: Phase?) {
      let fromStrip = previous == .recording
      let target: Double = if fromStrip {
        Metrics.rowCenters[status == .discarded ? Metrics.discardIndex : Metrics.sendIndex]
      } else if self[.alpha] > 0.3 {
        (values[Key.top.rawValue].target + values[Key.bottom.rawValue].target) / 2
      } else {
        Metrics.rowCenters[Metrics.sendIndex]
      }
      if bubbleActive { hideBubble() }
      if previous == nil {
        for key in Self.rowKeys { set(key, 0) }
        present(true)
      }
      to(.alpha, 1, StripMotion.quick)
      to(.slide, 0, StripMotion.change)
      to(.scale, 1, StripMotion.change)
      let radius = Double(ScrawlStrip.width) / 2
      to(.top, target - radius, StripMotion.change)
      to(.bottom, target + radius, StripMotion.pourLag)
      if fromStrip {
        gatherY = target
        to(.gather, 1, StripMotion.rowGather)
        for key in Self.rowKeys { to(key, 0, StripMotion.rowOut) }
      }
      let gulp = !fromStrip && previous != nil
      let swap: (LiquidStrip) -> Void = { strip in
        strip.statusIcon = status
        strip.set(.iconAlpha, 0)
        strip.set(.iconScale, 0.5)
        strip.to(.iconAlpha, 1, StripMotion.iconIn)
        strip.to(.iconScale, 1, StripMotion.iconPop)
        if gulp { strip.values[Key.scale.rawValue].velocity += StripMotion.gulpVelocity }
      }
      if fromStrip { after(StripMotion.iconSwapDelay, swap) } else { swap(self) }
      let bubble: Bubble? = switch mode {
      case let .sent(reply)?: .sent(reply)
      case .queued?: .queued
      case let .failed(failure)?: .failed(failure)
      case .discarded?: .discarded
      default: nil
      }
      if let bubble {
        after(fromStrip ? StripMotion.bubbleDelayAfterPour : StripMotion.bubbleDelay) { $0.showBubble(bubble) }
      } else if status == .sending {
        after(StripMotion.sendingBubbleDelay) { $0.showBubble(.sending(stalled: $0.sendStalled)) }
      }
      if status == .failed {
        after(StripMotion.shakeDelay) { strip in
          strip.values[Key.shake.rawValue].velocity = -Double(strip.direction) * StripMotion.shakeVelocity
        }
      }
    }

    /// Absorbs any bubble, then slides off toward the edge with a squash (or shrinks away after
    /// a discard).
    private func toGone(from previous: Phase?) {
      if bubbleActive { hideBubble() }
      let wait = previous == .recording ? 0 : StripMotion.exitDelay
      if previous == .discarded {
        after(wait) { strip in
          strip.exiting = true
          strip.to(.scale, 0.35, StripMotion.exit)
          strip.to(.alpha, 0, StripMotion.exit)
          strip.to(.iconAlpha, 0, StripMotion.rowOut)
        }
      } else {
        after(wait) { strip in
          strip.exiting = true
          strip.to(.slide, 90, StripMotion.exit)
          strip.to(.squashX, 1.2, StripMotion.exit)
          strip.to(.squashY, 0.86, StripMotion.exit)
          strip.to(.alpha, 0, StripMotion.exitFade)
          strip.to(.iconAlpha, 0, StripMotion.exit)
        }
      }
    }

    /// A bubble buds out of the body: from a droplet tucked inside it, out past the neck, growing
    /// to fit its text.
    private func showBubble(_ kind: Bubble) {
      bubbleActive = true
      bubble = kind
      bubbleY = kind.isRecording
        ? Metrics.rowCenters[Metrics.dotIndex]
        : (values[Key.top.rawValue].target + values[Key.bottom.rawValue].target) / 2
      to(.bubbleGap, Metrics.bubbleGap, StripMotion.bubbleBud)
      if let measured, measured.bubble == kind {
        to(.bubbleWidth, measured.size.width, StripMotion.bubbleWidth)
        to(.bubbleHeight, measured.size.height, StripMotion.bubbleHeight)
      }
      to(.bubbleAlpha, 1, StripMotion.bubbleTextIn)
    }

    /// The bubble's text goes first, then it's drawn back into the body.
    private func hideBubble(now: Bool = false) {
      bubbleActive = false
      to(.bubbleAlpha, 0, StripMotion.bubbleTextOut)
      to(.bubbleGap, Metrics.hiddenBubbleGap, StripMotion.bubbleAbsorb)
      to(.bubbleWidth, Metrics.hiddenBubble, StripMotion.bubbleAbsorb)
      to(.bubbleHeight, Metrics.hiddenBubble, StripMotion.bubbleAbsorb)
      if now {
        set(.bubbleAlpha, 0)
        set(.bubbleGap, Metrics.hiddenBubbleGap)
        set(.bubbleWidth, Metrics.hiddenBubble)
        set(.bubbleHeight, Metrics.hiddenBubble)
      }
    }

    // MARK: Reduce Motion

    /// Fades the whole strip out, jumps to the new state, and fades back in.
    private func reducedSwap(_ change: @escaping (LiquidStrip) -> Void) {
      guard fade == nil else {
        applyInstant(change)
        return
      }
      fade = Fade(from: 1, to: 0, start: clock) { strip in
        strip.applyInstant(change)
        strip.fade = Fade(from: 0, to: 1, start: strip.clock, done: nil)
      }
    }

    private func applyInstant(_ change: (LiquidStrip) -> Void) {
      instant = true
      defer { instant = false }
      change(self)
      while !timers.isEmpty {
        let pending = timers.sorted { $0.at < $1.at }
        timers.removeAll()
        for timer in pending { timer.run(self) }
      }
    }

    // MARK: Springs and the frame loop

    private static let rowKeys: [Key] = [.row0, .row1, .row2, .row3, .row4]

    private subscript(_ key: Key) -> Double { values[key.rawValue].value }

    private var direction: CGFloat { side == .trailing ? 1 : -1 }

    private func to(_ key: Key, _ target: Double, _ spring: Spring) {
      values[key.rawValue].target = target
      values[key.rawValue].spring = spring
      if instant {
        values[key.rawValue].value = target
        values[key.rawValue].velocity = 0
      }
    }

    private func set(_ key: Key, _ value: Double, velocity: Double = 0) {
      values[key.rawValue].value = value
      values[key.rawValue].target = value
      values[key.rawValue].velocity = velocity
    }

    private func after(_ delay: Double, _ run: @escaping (LiquidStrip) -> Void) {
      timers.append(Timer(at: clock + delay, run: run))
    }

    private func present(_ isPresent: Bool) {
      guard self.isPresent != isPresent else { return }
      withAnimation(StripMotion.glassPresence) { self.isPresent = isPresent }
    }

    private func wake() {
      guard link == nil else { return }
      let link = CADisplayLink(target: LinkTarget(self), selector: #selector(LinkTarget.tick(_:)))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
      link.add(to: .main, forMode: .common)
      self.link = link
      lastTimestamp = nil
      advance(0)
    }

    fileprivate func tick(_ link: CADisplayLink) {
      let dt = lastTimestamp.map { min(max(link.timestamp - $0, 0), 1.0 / 20) } ?? 1.0 / 60
      lastTimestamp = link.timestamp
      advance(dt)
      let idle = timers.isEmpty && fade == nil && values.allSatisfy(\.isSettled)
      if idle {
        link.invalidate()
        self.link = nil
      }
    }

    private func advance(_ dt: Double) {
      clock += dt
      let now = clock
      let due = timers.filter { $0.at <= now }.sorted { $0.at < $1.at }
      if !due.isEmpty {
        timers.removeAll { $0.at <= now }
        for timer in due { timer.run(self) }
      }
      if let fade {
        let progress = min(max((clock - fade.start) / StripMotion.reducedFade, 0), 1)
        let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
        fadeLevel = fade.from + (fade.to - fade.from) * eased
        if progress >= 1 {
          self.fade = nil
          fade.done?(self)
        }
      }
      // Stretch along the direction of a throw or drag.
      var stretch = (x: 1.0, y: 1.0)
      if !reduceMotion, !exiting, phase == .recording {
        let speedX = min(abs(values[Key.placeX.rawValue].velocity) / StripMotion.stretchSpeed, StripMotion.maxStretch)
        let speedY = min(abs(values[Key.placeY.rawValue].velocity) / StripMotion.stretchSpeed, StripMotion.maxStretch)
        stretch = (1 + speedX - speedY * 0.45, 1 + speedY - speedX * 0.45)
      }
      if values[Key.throwX.rawValue].target != stretch.x { to(.throwX, stretch.x, StripMotion.throwStretch) }
      if values[Key.throwY.rawValue].target != stretch.y { to(.throwY, stretch.y, StripMotion.throwStretch) }
      for index in values.indices { values[index].step(dt) }
      publish()
      if exiting, isPresent, values[Key.alpha.rawValue].target == 0, self[.alpha] < 0.3 {
        present(false)
      }
    }

    /// Variant A's frame(): the body capsule, the bubble beside its inner edge, and the controls.
    private func publish() {
      let dir = direction
      let alpha = min(max(self[.alpha], 0), 1) * fadeLevel
      let ax = self[.placeX] + Double(dir) * (self[.slide] + self[.shake])
      let ay = self[.placeY]
      let scale = self[.scale]
      let width = Double(ScrawlStrip.width) * self[.squashX] * self[.throwX] * scale
      let height = max(0, (self[.bottom] - self[.top]) * self[.squashY] * self[.throwY] * scale)
      let cy = ay + (self[.top] + self[.bottom]) / 2

      var next = Geometry()
      next.direction = dir
      next.alpha = alpha
      next.body = CGRect(x: ax - width / 2, y: cy - height / 2, width: width, height: height)
      next.column = CGPoint(x: ax, y: ay)
      next.controlsLive = phase == .recording
      let gather = self[.gather]
      for (index, key) in Self.rowKeys.enumerated() {
        next.rows[index] = Row(
          opacity: self[key] * alpha,
          offset: gather * (gatherY - Metrics.rowCenters[index]) * 0.7,
          scale: 1 - 0.35 * gather
        )
      }
      next.icon = CGPoint(x: ax, y: cy)
      next.iconScale = max(0, self[.iconScale] * scale)
      next.iconOpacity = min(max(self[.iconAlpha], 0), 1) * alpha

      let gap = self[.bubbleGap]
      let bubbleWidth = max(0, self[.bubbleWidth])
      let bubbleHeight = max(0, self[.bubbleHeight])
      let inner = ax - Double(dir) * width / 2
      let near = inner - Double(dir) * gap
      let left = dir > 0 ? near - bubbleWidth : near
      let centerY = ay + bubbleY
      next.bubbleGap = gap
      next.bubbleCenter = CGPoint(x: left + bubbleWidth / 2, y: centerY)
      next.bubbleOpacity = min(max(self[.bubbleAlpha], 0), 1) * alpha
      next.bubbleInteractive = bubbleActive && self[.bubbleAlpha] > 0.5 && (bubble?.isInteractive ?? false)
      if bubbleWidth > 1, self[.bubbleAlpha] > 0.01 || gap > Metrics.hiddenBubbleGap + 1 {
        next.bubble = CGRect(x: left, y: centerY - bubbleHeight / 2, width: bubbleWidth, height: bubbleHeight)
      }
      if next != geometry { geometry = next }
    }
  }

  /// Breaks the display link's retain on the strip: once the strip is gone the link stops itself.
  nonisolated private final class LinkTarget: NSObject {
    weak var strip: LiquidStrip?

    init(_ strip: LiquidStrip) {
      self.strip = strip
    }

    @objc func tick(_ link: CADisplayLink) {
      MainActor.assumeIsolated {
        guard let strip else {
          link.invalidate()
          return
        }
        strip.tick(link)
      }
    }
  }

  // MARK: - Glass

  nonisolated enum StripGlassID: Hashable, Sendable {
    case strip, bubble
  }

  /// The strip's body and bubble. On iOS 26 they're two Liquid Glass capsules in a
  /// `GlassEffectContainer`, which blends them into one shape with a neck while they're within
  /// `glassSpacing` of each other. Before iOS 26 they're one material shape with the prototype's
  /// neck drawn in (`LiquidShape`).
  private struct LiquidGlass: View {
    let geometry: LiquidStrip.Geometry
    let isPresent: Bool
    let namespace: Namespace.ID
    @Environment(\.displayScale) private var displayScale

    var body: some View {
      Group {
        if #available(iOS 26, *) {
          GlassEffectContainer(spacing: Metrics.glassSpacing) {
            ZStack(alignment: .topLeading) {
              Color.clear
              if isPresent {
                if let bubble = geometry.bubble {
                  capsule(bubble, id: .bubble)
                }
                capsule(geometry.body, id: .strip)
              }
            }
          }
        } else {
          if isPresent {
            LiquidShape(geometry: geometry)
              .fill(.ultraThinMaterial)
              .overlay(LiquidShape(geometry: geometry).fill(.black.opacity(Metrics.glassTint)))
              .overlay(LiquidShape(geometry: geometry).stroke(.white.opacity(0.22), lineWidth: 1 / displayScale))
              .environment(\.colorScheme, .dark)
              .opacity(geometry.alpha)
              .transition(.opacity)
          }
        }
      }
      .allowsHitTesting(false)
    }

    @available(iOS 26, *)
    private func capsule(_ rect: CGRect, id: StripGlassID) -> some View {
      Color.clear
        .frame(width: rect.width, height: rect.height)
        .glassEffect(.regular.tint(.black.opacity(Metrics.glassTint)), in: .capsule)
        .glassEffectID(id, in: namespace)
        // The body materialises as it appears and once it has faded; the bubble's geometry is
        // already driven out of the body, so it needs no transition of its own.
        .glassEffectTransition(id == .strip ? .materialize : .identity)
        .opacity(geometry.alpha)
        .position(x: rect.midX, y: rect.midY)
    }
  }

  /// The body and bubble capsules unioned with variant A's metaball neck (a waisted bridge that
  /// thins as the gap opens), for the material fallback.
  nonisolated private struct LiquidShape: Shape {
    let geometry: LiquidStrip.Geometry

    func path(in _: CGRect) -> Path {
      let body = geometry.body
      var path = Self.capsule(body)
      guard let bubble = geometry.bubble else { return path }
      path = path.union(Self.capsule(bubble))
      let gap = geometry.bubbleGap
      guard gap < Metrics.neckReach, gap > -Double(bubble.height) else { return path }
      let reach = min(max(1 - gap / Metrics.neckReach, 0), 1)
      let bubbleRadius = min(bubble.width, bubble.height) / 2
      let bodyRadius = body.width / 2
      let dir = geometry.direction
      let bubbleCap = Cap(
        x: dir > 0 ? bubble.maxX - bubbleRadius : bubble.minX + bubbleRadius,
        y: bubble.midY,
        r: bubbleRadius
      )
      let bodyCap = Cap(
        x: body.midX,
        y: min(max(bubble.midY, body.minY + bodyRadius), body.maxY - bodyRadius),
        r: bodyRadius
      )
      let half = min(bubbleRadius, bodyRadius) * sin(Self.neckAngle) * (0.1 + 0.9 * pow(reach, 3))
      let neck = dir > 0
        ? Self.neck(from: bubbleCap, to: bodyCap, half: half)
        : Self.neck(from: bodyCap, to: bubbleCap, half: half)
      if let neck { path = path.union(neck) }
      return path
    }

    private struct Cap {
      let x: CGFloat
      let y: CGFloat
      let r: CGFloat
    }

    private static let neckAngle = 0.95

    private static func capsule(_ rect: CGRect) -> Path {
      guard rect.width > 0.5, rect.height > 0.5 else { return Path() }
      return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
    }

    private static func neck(from left: Cap, to right: Cap, half: CGFloat) -> Path? {
      let sine = sin(neckAngle), cosine = cos(neckAngle)
      let startX = left.x + left.r * cosine
      let endX = right.x - right.r * cosine
      guard endX - startX >= 0.5 else { return nil }
      let midX = (startX + endX) / 2
      let midY = (left.y + right.y) / 2
      var path = Path()
      path.move(to: CGPoint(x: startX, y: left.y - left.r * sine))
      path.addQuadCurve(to: CGPoint(x: endX, y: right.y - right.r * sine), control: CGPoint(x: midX, y: midY - half))
      path.addLine(to: CGPoint(x: endX, y: right.y + right.r * sine))
      path.addQuadCurve(to: CGPoint(x: startX, y: left.y + left.r * sine), control: CGPoint(x: midX, y: midY + half))
      path.closeSubpath()
      return path
    }
  }

  // MARK: - Controls

  /// A pulsing red dot inside a hairline ring that fills once per minute.
  private struct RecordingDot: View {
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      ZStack {
        Circle()
          .stroke(.white.opacity(0.16), lineWidth: 1.25)
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
          let elapsed = max(0, context.date.timeIntervalSince(startedAt))
          Circle()
            .trim(from: 0, to: elapsed.truncatingRemainder(dividingBy: 60) / 60)
            .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .accessibilityLabel(Self.spoken(elapsed))
        }
        Circle()
          .fill(Color.scrawlRed)
          .frame(width: 8, height: 8)
          .phaseAnimator(reduceMotion ? [true] : [true, false]) { dot, bright in
            dot.scaleEffect(bright ? 1 : 0.78).opacity(bright ? 1 : 0.55)
          } animation: { _ in
            .easeInOut(duration: 1)
          }
          .accessibilityHidden(true)
      }
      .frame(width: 18, height: 18)
      .accessibilityElement(children: .combine)
    }

    private static func spoken(_ elapsed: TimeInterval) -> String {
      let minutes = Int(elapsed) / 60
      let seconds = Int(elapsed) % 60
      return "Recording, \(minutes) \(minutes == 1 ? "minute" : "minutes") \(seconds) \(seconds == 1 ? "second" : "seconds")"
    }
  }

  private struct ElapsedText: View {
    let startedAt: Date

    var body: some View {
      TimelineView(.periodic(from: startedAt, by: 1)) { context in
        Text(Duration.seconds(max(0, context.date.timeIntervalSince(startedAt))).formatted(.time(pattern: .minuteSecond)))
          .monospacedDigit()
      }
    }
  }

  private struct StripButton<Icon: View>: View {
    let label: String
    var value = ""
    /// Tinted Scrawl red while on (the draw toggle).
    var isActive = false
    let action: @MainActor () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
      Button { action() } label: {
        icon
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(isActive ? Color.scrawlRed : .white.opacity(0.85))
          .frame(width: 32, height: 32)
          .background(Color.scrawlRed.opacity(isActive ? 0.22 : 0), in: .circle)
          .frame(width: Metrics.hit, height: Metrics.row)
          .contentShape(Rectangle())
          .animation(.snappy(duration: 0.15), value: isActive)
      }
      .buttonStyle(StripButtonStyle())
      .accessibilityLabel(label)
      .accessibilityValue(value)
    }
  }

  private struct StripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .scaleEffect(configuration.isPressed ? 0.86 : 1)
        .opacity(configuration.isPressed ? 0.7 : 1)
        .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
  }

  // MARK: - Placement

  /// Places the strip on the left or right edge, vertically wherever it was left (remembered per
  /// app), inside the safe area and above the keyboard. Dragging the dot moves it; a throw lands
  /// on the nearer edge, stretching along the way.
  ///
  /// `mode` comes straight from `Scrawl`; the first layout already seeds the entrance.
  struct StripPlacement: View {
    let mode: ScrawlStrip.Mode?
    let actions: ScrawlStrip.Actions
    /// Pins the edge (previews) instead of the remembered one.
    var sideOverride: StripSide?
    /// A message beside the dot while recording.
    var notice: ScrawlStrip.Notice?

    @AppStorage("dev.kitlangton.scrawl.strip.side") private var storedSide = StripSide.trailing
    /// 0 is the top of the space the strip can move in, 1 the bottom.
    @AppStorage("dev.kitlangton.scrawl.strip.position") private var position = 0.5
    @State private var liquid = LiquidStrip()
    @State private var latest: ScrawlStrip.Mode?
    @State private var isReady = false
    @State private var pressOrigin: CGPoint?
    @State private var isDragging = false
    /// The keyboard's top edge in screen coordinates while it's showing.
    @State private var keyboardTop: CGFloat?
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var side: StripSide { sideOverride ?? storedSide }

    var body: some View {
      GeometryReader { geometry in
        let area = StripArea(geometry, keyboardTop: keyboardTop)
        let rest = area.center(side: side, position: position)
        ScrawlStrip(model: liquid, actions: placed(actions, in: area), glass: glass)
          .onAppear { liquid.rest(at: rest, animated: false) }
          .onChange(of: rest) { _, rest in liquid.rest(at: rest, animated: true) }
      }
      .ignoresSafeArea(.keyboard)
      .onAppear {
        liquid.side = side
        liquid.reduceMotion = reduceMotion
        latest = mode
        liquid.setNotice(notice)
        isReady = true
        liquid.apply(latest)
      }
      .onChange(of: notice) { _, notice in liquid.setNotice(notice) }
      .onChange(of: mode) { _, next in
        latest = next
        if isReady { liquid.apply(next) }
        if next?.phase != .recording {
          pressOrigin = nil
          isDragging = false
        }
      }
      .onChange(of: side) { _, side in liquid.side = side }
      .onChange(of: reduceMotion) { _, reduce in liquid.reduceMotion = reduce }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
        keyboardTop = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.minY
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
        keyboardTop = nil
      }
    }

    private func placed(_ actions: ScrawlStrip.Actions, in area: StripArea) -> ScrawlStrip.Actions {
      var actions = actions
      actions.gripMoved = { translation, velocity in
        let origin = pressOrigin ?? liquid.place
        if pressOrigin == nil { pressOrigin = origin }
        if !isDragging {
          guard translation.magnitude > ScrawlStrip.dragThreshold else { return }
          isDragging = true
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        liquid.drag(to: area.clamp(origin.offset(by: translation)), velocity: velocity)
      }
      actions.gripEnded = { translation, velocity in
        defer {
          pressOrigin = nil
          isDragging = false
        }
        guard isDragging, let origin = pressOrigin else { return }
        let dropped = area.clamp(origin.offset(by: translation))
        // Where the throw would carry it decides the edge and height (as in the prototype).
        let landingX = dropped.x + velocity.width * 0.3
        let landingY = dropped.y + velocity.height * 0.3 * 0.25
        let landedSide = sideOverride ?? (landingX < area.size.width / 2 ? .leading : .trailing)
        storedSide = landedSide
        position = area.position(forY: landingY)
        liquid.side = landedSide
        liquid.release(velocity: velocity)
        liquid.rest(at: area.center(side: landedSide, position: position), animated: true)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
      }
      // A gesture the system cancelled never calls `gripEnded`: put the strip back.
      actions.gripFinished = {
        DispatchQueue.main.async {
          guard isDragging else {
            pressOrigin = nil
            return
          }
          pressOrigin = nil
          isDragging = false
          liquid.release(velocity: .zero)
          liquid.rest(at: area.center(side: side, position: position), animated: true)
        }
      }
      actions.holdChanged = { liquid.setHolding($0) }
      return actions
    }
  }

  /// The space the strip's centre can move in: the safe area above the keyboard, 6pt off the side
  /// edges and 8pt off the top and bottom.
  nonisolated private struct StripArea {
    let size: CGSize
    private let xRange: ClosedRange<CGFloat>
    private let yRange: ClosedRange<CGFloat>

    init(_ geometry: GeometryProxy, keyboardTop: CGFloat?) {
      size = geometry.size
      let keyboardOverlap = keyboardTop.map { max(0, geometry.frame(in: .global).maxY - $0) } ?? 0
      let halfWidth = ScrawlStrip.width / 2
      let halfHeight = ScrawlStrip.expandedHeight / 2
      let minX = 6 + halfWidth
      let minY = 8 + halfHeight
      xRange = minX ... max(minX, size.width - 6 - halfWidth)
      yRange = minY ... max(minY, size.height - keyboardOverlap - 8 - halfHeight)
    }

    func center(side: StripSide, position: Double) -> CGPoint {
      CGPoint(
        x: side == .leading ? xRange.lowerBound : xRange.upperBound,
        y: yRange.lowerBound + (yRange.upperBound - yRange.lowerBound) * min(max(position, 0), 1)
      )
    }

    func clamp(_ point: CGPoint) -> CGPoint {
      CGPoint(x: point.x.clamped(to: xRange), y: point.y.clamped(to: yRange))
    }

    func position(forY y: CGFloat) -> Double {
      let span = yRange.upperBound - yRange.lowerBound
      guard span > 0 else { return 0.5 }
      return (y.clamped(to: yRange) - yRange.lowerBound) / span
    }
  }

  private extension View {
    /// A row's fan-out / gather motion from `LiquidStrip`.
    func rowMotion(_ row: LiquidStrip.Row) -> some View {
      scaleEffect(row.scale)
        .offset(y: row.offset)
        .opacity(row.opacity)
        .allowsHitTesting(row.opacity > 0.3)
        .accessibilityHidden(row.opacity < 0.3)
    }

    func reportFrame(_ region: OverlayRegion, to report: @escaping @MainActor (OverlayRegion, CGRect) -> Void) -> some View {
      onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { report(region, $0) })
        .onDisappear { report(region, .zero) }
    }
  }

  nonisolated private extension CGPoint {
    func offset(by translation: CGSize) -> CGPoint {
      CGPoint(x: x + translation.width, y: y + translation.height)
    }
  }

  nonisolated private extension CGSize {
    var magnitude: CGFloat { hypot(width, height) }
  }

  nonisolated private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
      min(max(self, range.lowerBound), range.upperBound)
    }
  }

  #if DEBUG
    private struct StripPreview: View {
      let mode: ScrawlStrip.Mode
      var side = StripSide.trailing
      var notice: ScrawlStrip.Notice?

      var body: some View {
        ZStack {
          LinearGradient(colors: [.indigo, .teal, .orange], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
          StripPlacement(mode: mode, actions: .init(), sideOverride: side, notice: notice)
        }
      }
    }

    /// Plays variant A's flows on a loop through `StripPlacement`, the way the overlay drives it:
    /// appear, draw on, pour into send, sent bubble, slide off; appear, pour into discard, Undo
    /// toast, back to sending, failed with a shake, absorbed and gone.
    private struct StripCyclePreview: View {
      private static let steps: [(mode: ScrawlStrip.Mode?, seconds: Double)] = [
        (nil, 0.8),
        (.recording(startedAt: .now, isDrawing: false), 1.4),
        (.recording(startedAt: .now, isDrawing: true), 1.0),
        (.sending(.init()), 1.4),
        (.sent(.delivered(sessionTitle: "Fix the onboarding flow")), 2.2),
        (nil, 1.2),
        (.recording(startedAt: .now, isDrawing: false), 1.4),
        (.discarded, 2.4),
        (.sending(.init()), 1.4),
        (.queued, 2.0),
        (nil, 1.2),
        (.recording(startedAt: .now, isDrawing: false), 1.4),
        (.sending(.init()), 1.4),
        (.failed(.unreachable), 2.6),
        (nil, 1.2),
      ]
      @State private var step = 0

      var body: some View {
        ZStack {
          LinearGradient(colors: [.indigo, .teal, .orange], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
          StripPlacement(mode: Self.steps[step].mode, actions: .init(), sideOverride: .trailing)
        }
        .task {
          while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.steps[step].seconds))
            step = (step + 1) % Self.steps.count
          }
        }
      }
    }

    #Preview("Animated cycle (variant A)") {
      StripCyclePreview()
    }

    #Preview("Recording") {
      StripPreview(mode: .recording(startedAt: .now.addingTimeInterval(-42), isDrawing: false))
    }

    #Preview("Drawing on") {
      StripPreview(mode: .recording(startedAt: .now.addingTimeInterval(-75), isDrawing: true))
    }

    #Preview("Left edge") {
      StripPreview(mode: .recording(startedAt: .now.addingTimeInterval(-12), isDrawing: false), side: .leading)
    }

    #Preview("Sending") {
      StripPreview(mode: .sending(.init(progress: 0.42)))
    }

    #Preview("Sent") {
      StripPreview(mode: .sent(.delivered(sessionTitle: "Fix the onboarding flow")))
    }

    #Preview("On the Mac, retrying") {
      StripPreview(mode: .sent(.queued(sessionTitle: "Fix the onboarding flow")))
    }

    #Preview("On the Mac, sending") {
      StripPreview(mode: .sent(.processing(sessionTitle: "Fix the onboarding flow")))
    }

    #Preview("Failed") {
      StripPreview(mode: .failed(.unreachable))
    }

    #Preview("Queued") {
      StripPreview(mode: .queued)
    }

    #Preview("Link expired") {
      StripPreview(mode: .failed(.linkExpired))
    }

    #Preview("Recording, link expired") {
      StripPreview(mode: .recording(startedAt: .now.addingTimeInterval(-3), isDrawing: false), notice: .linkExpired)
    }

    #Preview("Discarded") {
      StripPreview(mode: .discarded)
    }
  #endif
#endif
#endif
