// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
#if os(iOS)
  import UIKit

  /// Follows the system keyboard from its frame notifications: where it is at any moment
  /// (including mid-animation) for the app-frame recorder's keyboard panel, and whether it's up,
  /// as the `keyboard` context value (`visible`, or `hidden` once it goes down mid-recording).
  ///
  /// It only listens while Scrawl is configured, from before any recording, so a keyboard that is
  /// already up when recording starts is known.
  @MainActor
  final class KeyboardTracker {
    static let shared = KeyboardTracker()
    private static let contextKey = "keyboard"

    private let contextToken = UUID()
    private var observers: [any NSObjectProtocol] = []
    /// The latest animation in screen coordinates (`to` can be off screen); null when hidden.
    private var from = CGRect.null
    private var to = CGRect.null
    private var animationStart: CFTimeInterval = 0
    private var animationDuration: CFTimeInterval = 0
    private(set) var isVisible = false

    func setTracking(_ tracking: Bool) {
      guard tracking != !observers.isEmpty else { return }
      let center = NotificationCenter.default
      if tracking {
        observers = [
          center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
            let info = KeyboardChange(notification)
            MainActor.assumeIsolated { self?.willChangeFrame(info) }
          },
          center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didHide() }
          },
        ]
      } else {
        for observer in observers {
          center.removeObserver(observer)
        }
        observers = []
        from = .null
        to = .null
        setVisible(false)
        ScrawlAppContext.shared.setContext(Self.contextKey, nil, token: contextToken, promote: false)
      }
    }

    /// A recording is about to start: a keyboard that's down isn't worth a `hidden` in its context.
    func recordingWillBegin() {
      guard !isVisible else { return }
      ScrawlAppContext.shared.setContext(Self.contextKey, nil, token: contextToken, promote: false)
    }

    /// The keyboard's frame in `scene`'s coordinates right now, clipped to the scene, or nil when
    /// none of it is on screen.
    func frame(in scene: UIWindowScene, at now: CFTimeInterval = CACurrentMediaTime()) -> CGRect? {
      guard let screenFrame = screenFrame(at: now) else { return nil }
      let space = scene.coordinateSpace
      let frame = space.convert(screenFrame, from: scene.screen.coordinateSpace).intersection(space.bounds)
      return frame.isNull || frame.height < 1 || frame.width < 1 ? nil : frame
    }

    /// Where the keyboard is in screen coordinates, on or off screen.
    private func screenFrame(at now: CFTimeInterval) -> CGRect? {
      guard !to.isNull else { return nil }
      guard !from.isNull, animationDuration > 0 else { return to }
      let progress = min(max((now - animationStart) / animationDuration, 0), 1)
      // The keyboard's own curve is a spring; a cubic ease-out is close at 30 fps.
      let eased = 1 - pow(1 - progress, 3)
      return CGRect(
        x: from.minX + (to.minX - from.minX) * eased,
        y: from.minY + (to.minY - from.minY) * eased,
        width: from.width + (to.width - from.width) * eased,
        height: from.height + (to.height - from.height) * eased
      )
    }

    private func willChangeFrame(_ change: KeyboardChange) {
      let now = CACurrentMediaTime()
      // An interrupted animation carries on from where the keyboard is now.
      from = screenFrame(at: now) ?? change.begin
      to = change.end
      animationStart = now
      animationDuration = change.duration
      let screen = change.screen ?? Scrawl.activeScene?.screen
      let onScreen = screen.map { change.end.intersection($0.bounds) } ?? change.end
      setVisible(!onScreen.isNull && onScreen.height >= 1)
    }

    private func didHide() {
      from = .null
      to = .null
      setVisible(false)
    }

    private func setVisible(_ visible: Bool) {
      guard visible != isVisible else { return }
      isVisible = visible
      let value: String? = visible ? "visible" : (Scrawl.shared.isRecording ? "hidden" : nil)
      ScrawlAppContext.shared.setContext(Self.contextKey, value, token: contextToken, promote: false)
    }
  }

  /// What a keyboard frame notification says, read on the posting thread.
  nonisolated private struct KeyboardChange: @unchecked Sendable {
    let begin: CGRect
    let end: CGRect
    let duration: CFTimeInterval
    let screen: UIScreen?

    init(_ notification: Notification) {
      let info = notification.userInfo
      begin = (info?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue ?? .null
      end = (info?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .null
      duration = (info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
      screen = notification.object as? UIScreen
    }
  }

  /// The stand-in drawn where the keyboard is in app-frame recordings: the keyboard itself is
  /// rendered by another process, so the app's own drawing can't capture its keys.
  @MainActor
  enum KeyboardPanel {
    private struct Style {
      let background: UIColor
      let separator: UIColor
      let badge: UIImage
      let badgeSize: CGSize
    }

    private static var styles: [Bool: Style] = [:]

    /// Draws the panel into the current UIKit graphics context (in points).
    static func draw(in rect: CGRect, dark: Bool) {
      let style = style(dark: dark)
      style.background.setFill()
      UIRectFill(rect)
      style.separator.setFill()
      UIRectFill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0.5))

      let size = style.badgeSize
      guard size.width > 0, rect.height > size.height + 4 else { return }
      // Centred in the keys area, or in whatever part is on screen while it slides.
      style.badge.draw(in: CGRect(
        x: rect.midX - size.width / 2,
        y: rect.midY - size.height / 2,
        width: size.width,
        height: size.height
      ))
    }

    private static func style(dark: Bool) -> Style {
      if let style = styles[dark] { return style }
      // Close to the system keyboard's own backgrounds.
      let background = dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.835, blue: 0.86, alpha: 1)
      let separator = dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.08)
      let ink = dark ? UIColor(white: 1, alpha: 0.45) : UIColor(white: 0, alpha: 0.38)
      let font = UIFont.systemFont(ofSize: 15, weight: .medium)
      let label = NSAttributedString(string: "Keyboard", attributes: [.font: font, .foregroundColor: ink])
      let glyph = UIImage(systemName: "keyboard", withConfiguration: UIImage.SymbolConfiguration(font: font))?
        .withTintColor(ink, renderingMode: .alwaysOriginal)
      let labelSize = label.size()
      let glyphSize = glyph?.size ?? .zero
      let spacing: CGFloat = glyphSize == .zero ? 0 : 6
      let badgeSize = CGSize(
        width: (glyphSize.width + spacing + labelSize.width).rounded(.up),
        height: max(labelSize.height, glyphSize.height).rounded(.up)
      )
      let format = UIGraphicsImageRendererFormat.default()
      format.opaque = false
      let badge = UIGraphicsImageRenderer(size: badgeSize, format: format).image { _ in
        glyph?.draw(in: CGRect(
          x: 0,
          y: (badgeSize.height - glyphSize.height) / 2,
          width: glyphSize.width,
          height: glyphSize.height
        ))
        label.draw(at: CGPoint(
          x: glyphSize.width + spacing,
          y: (badgeSize.height - labelSize.height) / 2
        ))
      }
      let style = Style(background: background, separator: separator, badge: badge, badgeSize: badgeSize)
      styles[dark] = style
      return style
    }
  }
#endif
#endif
