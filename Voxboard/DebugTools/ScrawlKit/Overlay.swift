// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
#if os(iOS)
  import SwiftUI
  import UIKit

  /// A window above the app for freehand red strokes and the recording strip. It only exists from
  /// the start of a recording until the strip has animated away after it.
  /// ReplayKit recordings include it; app-frame recordings leave it out. Every touch except one on
  /// the strip or its bubbles (or single-finger drawing when `isDrawing` is active) passes through
  /// to the app below.
  final class OverlayWindow: UIWindow {
    private var regions: [OverlayRegion: CGRect] = [:]
    private unowned let scrawl: Scrawl
    private var drawingTouch: UITouch?
    private var presentationLink: CADisplayLink?
    private var presentationTrace: StartupTrace?
    private var afterPresentation: (@MainActor () -> Void)?
    private var preparationStart: CFTimeInterval?
    var isActivelyDrawing: Bool { drawingTouch != nil }
    /// The red ink, under the strip. UIKit layers rather than SwiftUI, so a touch redraws only the
    /// stroke's live tip.
    let ink = InkView()

    init(windowScene: UIWindowScene, scrawl: Scrawl) {
      self.scrawl = scrawl
      super.init(windowScene: windowScene)
      windowLevel = .alert + 10
      backgroundColor = .clear
      let host = UIHostingController(rootView: OverlayView(scrawl: scrawl) { [weak self] region, frame in
        guard let self else { return }
        regions[region] = frame.isEmpty ? nil : frame
        if region == .strip, !frame.isEmpty, let start = preparationStart {
          preparationStart = nil
          scrawl.startupObserver?(.init(stage: "prewarmLayout", milliseconds: (CACurrentMediaTime() - start) * 1000, onMainThread: true))
        }
      })
      host.view.backgroundColor = .clear
      rootViewController = host
      ink.frame = bounds
      // Index 0: under the root view whenever UIKit adds it.
      insertSubview(ink, at: 0)
      ink.onStroke = { [unowned scrawl] samples in scrawl.record(stroke: samples) }
      ink.onFade = { [unowned scrawl] strokes, uptime in scrawl.recordFade(of: strokes, at: uptime) }
      isHidden = true
    }

    func prepareLayout() {
      preparationStart = CACurrentMediaTime()
      // A hidden UIWindow doesn't mount SwiftUI's glass hierarchy. Mount it transparently
      // during the deliberate hold so its first body/layout aren't on recognition's frame.
      alpha = 0
      isHidden = false
      rootViewController?.loadViewIfNeeded()
      rootViewController?.view.frame = bounds
      rootViewController?.view.layoutIfNeeded()
    }

    func present(trace: StartupTrace?) {
      let hasLaidOutControls = regions[.strip] != nil
      isHidden = false
      alpha = 1
      // A transparently prepared strip already has content. Revealing the window does not
      // need another SwiftUI layout; observe its next presentation opportunity directly.
      if hasLaidOutControls {
        trace?.mark("stripLayout")
        presentationLink?.invalidate()
        presentationTrace = trace
        let link = CADisplayLink(target: self, selector: #selector(presented))
        presentationLink = link
        link.add(to: .main, forMode: .common)
      }
    }

    @objc private func presented() {
      presentationLink?.invalidate()
      presentationLink = nil
      if !isHidden, alpha > 0 { presentationTrace?.mark("firstDraw") }
      presentationTrace = nil
      let action = afterPresentation
      afterPresentation = nil
      // Let this display turn commit before cold AVFoundation/VideoToolbox initialization
      // can contend with UIKit, even though the setup itself runs on background queues.
      if let action { DispatchQueue.main.async(execute: action) }
    }

    func afterFirstPresentation(_ action: @escaping @MainActor () -> Void) {
      if presentationLink != nil {
        afterPresentation = action
      } else {
        action()
      }
    }

    func dismiss() {
      presentationLink?.invalidate()
      presentationLink = nil
      presentationTrace = nil
      afterPresentation = nil
      isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      guard alpha > 0, !isHidden else { return nil }
      if regions.values.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(point) }) {
        return super.hitTest(point, with: event)
      }
      if scrawl.isRecording || scrawl.isStarting, scrawl.isDrawing {
        return self
      }
      return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      // One finger draws at a time; others are ignored until it lifts.
      guard scrawl.isRecording || scrawl.isStarting, scrawl.isDrawing, drawingTouch == nil, let touch = touches.first else {
        if drawingTouch == nil { super.touchesBegan(touches, with: event) }
        return
      }
      drawingTouch = touch
      ink.began(touch, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let active = drawingTouch, touches.contains(active) else {
        super.touchesMoved(touches, with: event)
        return
      }
      ink.moved(active, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let active = drawingTouch, touches.contains(active) else {
        super.touchesEnded(touches, with: event)
        return
      }
      ink.ended(active, with: event)
      drawingTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let active = drawingTouch, touches.contains(active) else {
        super.touchesCancelled(touches, with: event)
        return
      }
      ink.ended(active, with: event)
      drawingTouch = nil
    }

    /// Removes the ink (a recording started or finished).
    func clearInk(animated: Bool) {
      drawingTouch = nil
      ink.clear(animated: animated)
    }
  }

  private struct OverlayView: View {
    let scrawl: Scrawl
    let reportFrame: @MainActor (OverlayRegion, CGRect) -> Void

    var body: some View {
      // The ink is `OverlayWindow.ink`, under this view.
      StripPlacement(mode: stripMode, actions: actions, notice: scrawl.isRecording ? scrawl.notice : nil)
        .environment(\.scrawlStartupTrace, scrawl.startupTrace)
    }

    private var stripMode: ScrawlStrip.Mode? {
      if scrawl.isRecording || scrawl.isStarting, let startedAt = scrawl.startedAt {
        return .recording(startedAt: startedAt, isDrawing: scrawl.isDrawing)
      }
      if let preparedAt = scrawl.preparedAt {
        return .recording(startedAt: preparedAt, isDrawing: false)
      }
      if scrawl.isDiscardPending {
        return .discarded
      }
      switch scrawl.uploadStatus {
      case .idle: return nil
      case .sending: return .sending(.init(progress: scrawl.sendProgress, stalled: scrawl.isSendStalled))
      case let .sent(target): return .sent(target)
      case .queued: return .queued
      case .failed: return .failed(scrawl.deliveryFailure)
      }
    }

    private var actions: ScrawlStrip.Actions {
      ScrawlStrip.Actions(
        toggleDrawing: { scrawl.toggleDrawing() },
        discard: { scrawl.discard() },
        send: {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          scrawl.stop()
        },
        undoDiscard: { scrawl.undoDiscard() },
        share: { scrawl.shareFailedRecording() },
        reportFrame: reportFrame
      )
    }
  }
#endif
#endif
