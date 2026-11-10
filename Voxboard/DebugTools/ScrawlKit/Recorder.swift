// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
#if os(iOS)
  import ReplayKit
  import UIKit

  /// How ScrawlKit records the screen.
  nonisolated public enum ScrawlCaptureMethod: String, Equatable, Sendable {
    /// Draws the app's own windows into the movie (`AppFrameRecorder`). No screen-recording
    /// prompt; the microphone asks once. The strip and ink stay out of the video; the system
    /// keyboard shows as a labelled panel (its keys are another process's); system alerts and
    /// some layers (video players, camera previews, some Metal or backdrop effects) may not appear.
    case appFrames
    /// ReplayKit's in-app screen recording: the exact pixels on screen, overlay included, behind
    /// iOS's "Record screen and microphone?" consent alert.
    case replayKit
  }

  /// Something that records the app into a movie, on the clock the timeline uses: t=0 is the
  /// movie's first frame.
  @MainActor
  protocol ScrawlRecorder: AnyObject {
    var startupTrace: StartupTrace? { get set }
    var method: ScrawlCaptureMethod { get }
    var isAvailable: Bool { get }
    /// Whether the finished movie has the microphone in it. Read after `stop`.
    var recordsAudio: Bool { get }
    /// Called when the recorder can't go on (the app went to the background); the recording
    /// should be stopped as if the user had sent it.
    var onInterruption: (@MainActor @Sendable () -> Void)? { get set }
    /// Starts recording. `completion` gets the instant of the movie's first frame, or an error.
    func start(microphone: Bool, completion: @escaping @MainActor @Sendable (Result<Date, any Error>) -> Void)
    /// Stops and writes the movie to `movie` (replacing any file there).
    func stop(writingTo movie: URL, completion: @escaping @MainActor @Sendable ((any Error)?) -> Void)
    /// Stops and throws the recording away.
    func cancel()
  }

  nonisolated extension ScrawlCaptureMethod {
    @MainActor
    /// `hosted`: the recording goes to an HTTPS endpoint, so it has to fit under its upload limit.
    func makeRecorder(hosted: Bool) -> any ScrawlRecorder {
      switch self {
      case .appFrames: AppFrameRecorder(videoBitRate: hosted ? AppFrameRecorder.hostedVideoBitRate : AppFrameRecorder.videoBitRate)
      case .replayKit: ReplayKitRecorder()
      }
    }
  }

  /// ReplayKit's in-app recording (`RPScreenRecorder`).
  @MainActor
  final class ReplayKitRecorder: ScrawlRecorder {
    var startupTrace: StartupTrace?
    var onInterruption: (@MainActor @Sendable () -> Void)?

    var method: ScrawlCaptureMethod { .replayKit }
    var isAvailable: Bool { RPScreenRecorder.shared().isAvailable }
    var recordsAudio: Bool { RPScreenRecorder.shared().isMicrophoneEnabled }

    func start(microphone: Bool, completion: @escaping @MainActor @Sendable (Result<Date, any Error>) -> Void) {
      let recorder = RPScreenRecorder.shared()
      recorder.isMicrophoneEnabled = microphone
      recorder.startRecording { error in
        Task { @MainActor in
          if let error {
            completion(.failure(error))
          } else {
            completion(.success(.now))
          }
        }
      }
    }

    func stop(writingTo movie: URL, completion: @escaping @MainActor @Sendable ((any Error)?) -> Void) {
      // ReplayKit refuses to write over an existing file; never lose a recording to a name clash.
      try? FileManager.default.removeItem(at: movie)
      RPScreenRecorder.shared().stopRecording(withOutput: movie) { error in
        Task { @MainActor in completion(error) }
      }
    }

    func cancel() {
      RPScreenRecorder.shared().stopRecording { _, _ in }
    }
  }
#endif
#endif
