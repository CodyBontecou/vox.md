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

  nonisolated public enum ScrawlTrigger: Equatable, Sendable {
    /// Hold three fingers on the screen for half a second to start or stop. On paired devices this
    /// also turns off iOS's three-finger text-editing gestures in the app (see
    /// `Scrawl.suppressesSystemEditingGestures`), which would otherwise open the Undo · Cut · Copy
    /// bar when a text field is focused.
    case threeFingerLongPress
    /// No gesture: call `Scrawl.shared.start()` and `stop()` yourself.
    case none
  }

  public extension View {
    /// Adds Scrawl to this window: once configured on the device, touches are watched (for the
    /// timeline) and the trigger starts and stops recordings. Unconfigured devices
    /// stay completely inert (no gesture recognizers, overlay window, or network calls).
    ///
    /// This modifier also registers `.onOpenURL` so `<scheme>://scrawl?url=...&token=...` and
    /// `<scheme>://scrawl?reset=1` setup links (plus the legacy `tether` host) work automatically.
    /// In SwiftUI, `.onOpenURL` accumulates handlers via a preference and invokes every registered
    /// closure for each incoming URL rather than consuming the event at the first modifier, so a
    /// host app's own `.onOpenURL` continues to receive its links. Host apps that also want to
    /// short-circuit their own URL router on Scrawl links can check `if !Scrawl.handleSetupURL(url) { ... }`.
    func scrawl(trigger: ScrawlTrigger = .threeFingerLongPress, isEnabled: Bool = true) -> some View {
      background(ScrawlInstaller(trigger: trigger, isEnabled: isEnabled))
        .onOpenURL { url in
          if isEnabled {
            _ = Scrawl.handleSetupURL(url)
          }
        }
    }
  }

  private struct ScrawlInstaller: UIViewRepresentable {
    let trigger: ScrawlTrigger
    let isEnabled: Bool

    func makeUIView(context _: Context) -> InstallerView {
      InstallerView(trigger: trigger, isEnabled: isEnabled)
    }

    func updateUIView(_ uiView: InstallerView, context _: Context) {
      uiView.update(trigger: trigger, isEnabled: isEnabled)
    }
  }

  /// Attaches the touch observer and the trigger to its window only when enabled and configured.
  final class InstallerView: UIView {
    private var trigger: ScrawlTrigger
    private var isEnabled: Bool
    private weak var installedOn: UIWindow?
    private var installedTrigger: ScrawlTrigger?
    private var touchObserver: TouchObserver?
    private var triggerRecognizer: UILongPressGestureRecognizer?

    init(trigger: ScrawlTrigger, isEnabled: Bool) {
      self.trigger = trigger
      self.isEnabled = isEnabled
      super.init(frame: .zero)
      isUserInteractionEnabled = false
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(configurationDidChange),
        name: Scrawl.configurationDidChangeNotification,
        object: nil
      )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      syncInstall()
    }

    func update(trigger: ScrawlTrigger, isEnabled: Bool) {
      self.trigger = trigger
      self.isEnabled = isEnabled
      syncInstall()
    }

    @objc private func configurationDidChange() {
      syncInstall()
    }

    private func syncInstall() {
      guard isEnabled, Scrawl.isConfigured, let window else {
        uninstall()
        return
      }
      if window === installedOn, installedTrigger == trigger {
        return
      }
      uninstall()
      installedOn = window
      installedTrigger = trigger
      let observer = TouchObserver()
      window.addGestureRecognizer(observer)
      touchObserver = observer
      if case .threeFingerLongPress = trigger {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(triggered(_:)))
        press.numberOfTouchesRequired = 3
        press.minimumPressDuration = 0.5
        press.cancelsTouchesInView = false
        window.addGestureRecognizer(press)
        triggerRecognizer = press
        Scrawl.shared.threeFingerTriggers += 1
      }
    }

    private func uninstall() {
      if let installedOn {
        if let touchObserver {
          installedOn.removeGestureRecognizer(touchObserver)
        }
        if let triggerRecognizer {
          installedOn.removeGestureRecognizer(triggerRecognizer)
        }
      }
      if triggerRecognizer != nil {
        Scrawl.shared.threeFingerTriggers -= 1
      }
      touchObserver = nil
      triggerRecognizer = nil
      installedOn = nil
      installedTrigger = nil
    }

    @objc private func triggered(_ press: UILongPressGestureRecognizer) {
      guard press.state == .began, Scrawl.isConfigured else { return }
      Scrawl.shared.triggerRecognized()
    }
  }

  /// Sees every touch in the window without taking part: it never recognizes, never cancels or
  /// delays touches, and works alongside every other gesture.
  final class TouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var fingers = Set<ObjectIdentifier>()
    override init(target: Any?, action: Selector?) {
      super.init(target: target, action: action)
      cancelsTouchesInView = false
      delaysTouchesBegan = false
      delaysTouchesEnded = false
      delegate = self
    }

    convenience init() { self.init(target: nil, action: nil) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { forward(touches, .began, event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { forward(touches, .moved, event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { forward(touches, .ended, event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { forward(touches, .cancelled, event) }

    /// Called once every finger has lifted (or the system took the touches).
    override func reset() {
      super.reset()
      fingers.removeAll()
      Scrawl.shared.touchesReset()
    }

    private func forward(_ touches: Set<UITouch>, _ phase: UITouch.Phase, _: UIEvent) {
      guard let window = view as? UIWindow else { return }
      if phase == .began {
        fingers.formUnion(touches.map(ObjectIdentifier.init))
        if fingers.count == 3, Scrawl.shared.threeFingerTriggers > 0 { Scrawl.shared.prepareToStart() }
      } else if phase == .ended || phase == .cancelled {
        fingers.subtract(touches.map(ObjectIdentifier.init))
      }
      for touch in touches {
        Scrawl.shared.record(touch: touch, in: window, phase: phase)
      }
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool { true }
  }
#endif
#endif
