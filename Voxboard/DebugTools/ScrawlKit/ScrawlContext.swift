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

  public extension Scrawl {
    /// Names the screen the app is showing ("Settings › Experimental"), so recordings say which
    /// page they were on. While recording, each change lands on the timeline. `nil` clears it.
    ///
    /// The most recent setter wins: this call, or the latest `.scrawlScreen` view still on screen.
    static func screen(_ name: String?) {
      ScrawlAppContext.shared.setScreen(name, token: ScrawlAppContext.manualToken, promote: true)
    }

    /// Sets an app-defined value that helps whoever reads the recording ("session" = "ses_…",
    /// "server" = "studio"). `nil` clears it. Recordings include every value at their start and
    /// each change while recording. Only what you pass here is sent.
    static func context(_ key: String, _ value: String?) {
      ScrawlAppContext.shared.setContext(key, value, token: ScrawlAppContext.manualToken, promote: true)
    }
  }

  public extension View {
    /// Names the screen this view shows while it's visible (`Scrawl.screen(_:)`), following
    /// `name` as it changes. When the view goes away, the screen it covered comes back.
    func scrawlScreen(_ name: String) -> some View {
      modifier(ScrawlScreenModifier(name: name))
    }

    /// Sets an app-defined value (`Scrawl.context(_:_:)`) while this view is visible, following
    /// `value` as it changes. `nil` leaves the key to enclosing views; when the view goes away, the
    /// value it covered comes back.
    func scrawlContext(_ key: String, _ value: String?) -> some View {
      modifier(ScrawlContextModifier(key: key, value: value))
    }
  }

  private struct ScrawlScreenModifier: ViewModifier {
    let name: String
    @State private var token = UUID()

    func body(content: Content) -> some View {
      content
        .onAppear { ScrawlAppContext.shared.setScreen(name, token: token, promote: true) }
        .onChange(of: name) { _, name in
          ScrawlAppContext.shared.setScreen(name, token: token, promote: false)
        }
        .onDisappear { ScrawlAppContext.shared.setScreen(nil, token: token, promote: false) }
    }
  }

  private struct ScrawlContextModifier: ViewModifier {
    let key: String
    let value: String?
    @State private var token = UUID()

    func body(content: Content) -> some View {
      content
        .onAppear { ScrawlAppContext.shared.setContext(key, value, token: token, promote: true) }
        .onChange(of: value) { _, value in
          ScrawlAppContext.shared.setContext(key, value, token: token, promote: false)
        }
        .onChange(of: key) { old, key in
          ScrawlAppContext.shared.setContext(old, nil, token: token, promote: false)
          ScrawlAppContext.shared.setContext(key, value, token: token, promote: true)
        }
        .onDisappear { ScrawlAppContext.shared.setContext(key, nil, token: token, promote: false) }
    }
  }

  /// The screen and context values the host app has declared, and their changes during the
  /// current recording.
  ///
  /// Each screen or key is a stack of setters (a view's token, or the static API's): the most
  /// recently appeared one still present wins.
  @MainActor
  final class ScrawlAppContext {
    static let shared = ScrawlAppContext()
    static let manualToken = UUID()

    private struct Entry {
      let token: UUID
      var value: String
    }

    private var screens: [Entry] = []
    private var values: [String: [Entry]] = [:]
    private var startedAt: Date?
    private var startScreen: String?
    private var startValues: [String: String] = [:]
    private var screenLog: [[String: Any]] = []
    private var contextLog: [[String: Any]] = []

    var currentScreen: String? { screens.last?.value }

    var currentValues: [String: String] {
      values.compactMapValues { $0.last?.value }
    }

    func setScreen(_ name: String?, token: UUID, promote: Bool) {
      let before = currentScreen
      Self.set(&screens, Self.cleaned(name), token: token, promote: promote)
      let after = currentScreen
      guard after != before, let t = elapsed else { return }
      screenLog.append(["t": t, "name": after ?? NSNull()])
    }

    func setContext(_ key: String, _ value: String?, token: UUID, promote: Bool) {
      let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty else { return }
      let before = values[key]?.last?.value
      var stack = values[key] ?? []
      Self.set(&stack, Self.cleaned(value), token: token, promote: promote)
      values[key] = stack.isEmpty ? nil : stack
      let after = stack.last?.value
      guard after != before, let t = elapsed else { return }
      contextLog.append(["t": t, "key": key, "value": after ?? NSNull()])
    }

    /// The recording has started at `date`: changes from now on are timed from it.
    func begin(at date: Date) {
      startedAt = date
      startScreen = currentScreen
      startValues = currentValues
      screenLog = []
      contextLog = []
    }

    /// Ends the recording and returns its timeline keys (`shortVersion`, `context`,
    /// `contextChanges`, `screens`).
    func end() -> [String: Any] {
      var screens = screenLog
      if let startScreen {
        screens.insert(["t": 0.0, "name": startScreen], at: 0)
      }
      let info: [String: Any] = [
        "shortVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        "context": startValues,
        "contextChanges": contextLog,
        "screens": screens,
      ]
      startedAt = nil
      startScreen = nil
      startValues = [:]
      screenLog = []
      contextLog = []
      return info
    }

    private var elapsed: Double? {
      guard let startedAt, Scrawl.shared.isRecording else { return nil }
      return (max(Date().timeIntervalSince(startedAt), 0) * 1000).rounded() / 1000
    }

    private static func set(_ stack: inout [Entry], _ value: String?, token: UUID, promote: Bool) {
      let index = stack.firstIndex { $0.token == token }
      guard let value else {
        if let index { stack.remove(at: index) }
        return
      }
      if let index, !promote {
        stack[index].value = value
      } else {
        if let index { stack.remove(at: index) }
        stack.append(Entry(token: token, value: value))
      }
    }

    private static func cleaned(_ value: String?) -> String? {
      guard let value else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }
#endif
#endif
