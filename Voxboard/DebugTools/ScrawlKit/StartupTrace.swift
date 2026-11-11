// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
#if os(iOS)
  import os
  import SwiftUI
  import UIKit

  /// Opt-in startup evidence. Only fixed stage names and monotonic timings, never capture content.
  nonisolated public struct ScrawlStartupEvent: Sendable, Codable {
    public let stage: String
    public let milliseconds: Double
    public let onMainThread: Bool
  }

  nonisolated final class StartupTrace: @unchecked Sendable {
    private let start = CACurrentMediaTime()
    private let id = AppFrameRecorder.signposter.makeSignpostID()
    private let lock = NSLock()
    private var recorded = Set<String>()
    private let receive: @Sendable (ScrawlStartupEvent) -> Void

    init(receive: @escaping @Sendable (ScrawlStartupEvent) -> Void) {
      self.receive = receive
      mark("recognized")
    }

    func mark(_ stage: String) {
      lock.lock()
      let first = recorded.insert(stage).inserted
      lock.unlock()
      guard first else { return }
      let ms = (CACurrentMediaTime() - start) * 1000
      AppFrameRecorder.signposter.emitEvent("ScrawlStartup", id: id, "stage=\(stage) ms=\(ms, format: .fixed(precision: 3))")
      receive(.init(stage: stage, milliseconds: ms, onMainThread: Thread.isMainThread))
    }
  }

  nonisolated private struct StartupTraceKey: EnvironmentKey {
    static let defaultValue: StartupTrace? = nil
  }

  nonisolated extension EnvironmentValues {
    var scrawlStartupTrace: StartupTrace? {
      get { self[StartupTraceKey.self] }
      set { self[StartupTraceKey.self] = newValue }
    }
  }

  /// The following display tick bounds presentation of a laid-out, nontransparent strip.
  /// This is not a render-server pixel measurement.
  struct StartupDrawProbe: UIViewRepresentable {
    let trace: StartupTrace?
    let visible: Bool

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
      guard visible, let trace else { return }
      view.arm(trace)
    }

    final class Probe: UIView {
      private var trace: StartupTrace?
      private var link: CADisplayLink?
      private var reported = false
      func arm(_ trace: StartupTrace) {
        guard self.trace !== trace else { return }
        self.trace = trace
        reported = false
        setNeedsLayout()
      }
      override func layoutSubviews() {
        super.layoutSubviews()
        guard window != nil, let trace, link == nil, !reported else { return }
        trace.mark("stripLayout")
        let link = CADisplayLink(target: self, selector: #selector(drawn))
        self.link = link
        link.add(to: .main, forMode: .common)
      }
      @objc private func drawn() {
        link?.invalidate()
        link = nil
        reported = true
        trace?.mark("firstDraw")
      }
      override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { link?.invalidate(); link = nil }
      }
    }
  }
#endif
#endif
