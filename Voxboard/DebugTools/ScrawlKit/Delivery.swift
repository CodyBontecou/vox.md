// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
import Foundation

/// What a Scrawl server said became of a recording it took: the JSON of its 2xx, or the `.sent`
/// and `.delivery` markers a Mac writes back over USB.
///
/// The Mac answers once it has built the bundle and tried to queue it into the agent session:
/// `{"ok":true,"delivered":bool,"state":"sent"|"queued"|"saved"|"processing","sessionTitle":…}`.
/// Servers from before `delivered` answered as soon as the files arrived; that reads as delivered.
nonisolated public enum IngestReply: Equatable, Sendable {
  /// Queued into the agent session `sessionTitle`.
  case delivered(sessionTitle: String)
  /// On the Mac, which couldn't reach the session and keeps trying on its own.
  case queued(sessionTitle: String)
  /// On the Mac, still being built or sent when it answered.
  case processing(sessionTitle: String)
  /// On the Mac and going no further (it has no session for this app).
  case saved

  /// Reads a 2xx response body.
  init(body: Data) {
    let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    self.init(json: json, fallbackTitle: "Scrawl")
  }

  /// Reads the USB markers: `.sent` holds the session's name; `.delivery`, written first by
  /// Macs that know it, holds the same JSON as an HTTP reply.
  init(sentMarker title: String, delivery: Data?) {
    let json = delivery.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
    self.init(json: json, fallbackTitle: title)
  }

  private init(json: [String: Any], fallbackTitle: String) {
    let title = (json["sessionTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
    guard let delivered = json["delivered"] as? Bool, !delivered else {
      self = .delivered(sessionTitle: title)
      return
    }
    switch json["state"] as? String {
    case "queued": self = .queued(sessionTitle: title)
    case "processing": self = .processing(sessionTitle: title)
    default: self = .saved
    }
  }

  public var isDelivered: Bool {
    if case .delivered = self { true } else { false }
  }
}

/// What the strip says about one recording on its way to an HTTPS endpoint, worked out from the
/// outbox's events and whether the network path is satisfied (`NWPathMonitor`). Time is passed
/// in, so it's a plain value that tests can drive.
///
/// - While an upload is running on a satisfied path it's "Sending…", however long that takes.
/// - With no byte progress for `stallAfter` on a satisfied path it's "Still sending…", never
///   "Queued": the phone is online, the upload is just slow.
/// - "Queued" is only for an unsatisfied path or an attempt that failed and is waiting to retry. A
///   retry starting on a satisfied path makes it "Sending…" again.
nonisolated struct DeliveryTracker: Equatable {
  enum Display: Equatable {
    /// `progress` is 0…1 once the upload reports bytes sent.
    case sending(progress: Double?)
    case stillSending(progress: Double?)
    case queued
    case sent(IngestReply)
    case failed(Outbox.Failure)
  }

  static let stallAfter: TimeInterval = 30

  private enum Phase: Equatable {
    case uploading
    case waitingToRetry
    case sent(IngestReply)
    case failed(Outbox.Failure)
  }

  let entry: String
  private(set) var pathSatisfied: Bool
  private var phase = Phase.uploading
  private var progress: Double?
  /// The last sign the upload is moving: its start, bytes sent, or the network coming back.
  private var lastActivity: Date

  /// Tracks `entry` from the moment it's handed to the outbox to send.
  init(entry: String, pathSatisfied: Bool, now: Date) {
    self.entry = entry
    self.pathSatisfied = pathSatisfied
    lastActivity = now
  }

  var isFinished: Bool {
    switch phase {
    case .sent, .failed: true
    case .uploading, .waitingToRetry: false
    }
  }

  mutating func apply(_ event: Outbox.Event, at now: Date) {
    guard event.id == entry, !isFinished else { return }
    switch event {
    case .started:
      phase = .uploading
      progress = nil
      lastActivity = now
    case let .progress(_, fraction):
      phase = .uploading
      progress = fraction
      lastActivity = now
    case .retrying:
      phase = .waitingToRetry
    case let .sent(_, reply):
      phase = .sent(reply)
    case let .failed(_, failure):
      phase = .failed(failure)
    }
  }

  mutating func setPath(satisfied: Bool, at now: Date) {
    // Waiting for the network isn't a stall: the clock starts again when it's back.
    if satisfied, !pathSatisfied { lastActivity = now }
    pathSatisfied = satisfied
  }

  func display(at now: Date) -> Display {
    switch phase {
    case let .sent(reply): return .sent(reply)
    case let .failed(failure): return .failed(failure)
    case .waitingToRetry: return .queued
    case .uploading:
      guard pathSatisfied else { return .queued }
      return now.timeIntervalSince(lastActivity) >= Self.stallAfter
        ? .stillSending(progress: progress)
        : .sending(progress: progress)
    }
  }

  /// When `display` will change without a new event (an upload stalling), if it will.
  func nextChange(after now: Date) -> Date? {
    guard phase == .uploading, pathSatisfied else { return nil }
    let stall = lastActivity.addingTimeInterval(Self.stallAfter)
    return stall > now ? stall : nil
  }
}
#endif
