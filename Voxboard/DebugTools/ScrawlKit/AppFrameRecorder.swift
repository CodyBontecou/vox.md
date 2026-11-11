// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
#if os(iOS)
  import AVFoundation
  import CoreMedia
  import os
  import QuartzCore
  import UIKit

  /// Records the app's own windows, not the screen, with the microphone into an H.264 `.mp4`.
  ///
  /// No screen-recording consent is needed: the microphone asks once and iOS remembers. If it's
  /// denied, the movie is video only. ScrawlKit's `OverlayWindow` is left out, so the strip, ink,
  /// and toasts never appear in the movie; Scrawl on the Mac draws touches and strokes
  /// from the timeline.
  ///
  /// Frames are drawn on the main thread (UIKit requires it) into pixel buffers from the writer's
  /// pool and handed to `MovieWriter`'s background encoding queue. `FramePacer` keeps capture at
  /// 30 fps when idle, backs off to 10–12 fps while scrolling or dragging so 120 Hz ProMotion
  /// frames keep their budget, and captures a settled frame once motion stops. Video and audio are
  /// both stamped on the host clock (`CMClockGetHostTimeClock`, the clock behind `CACurrentMediaTime`),
  /// and the writer's session starts at the first frame, so movie time 0 is the timeline's t=0.
  @MainActor
  final class AppFrameRecorder: NSObject, ScrawlRecorder {
    /// Movie pixels per point: 1.5× (capped at `maxLongEdge`) keeps main-thread drawing and
    /// encoding within a 120 Hz frame budget on Pro Max phones (660×1434 on a 440×956-point phone,
    /// matching Scrawl's 1600 px phone keyframe cap) while keeping 10.5 pt code and UI text sharp.
    nonisolated static let pixelsPerPoint: CGFloat = 1.5
    nonisolated static let maxLongEdge: CGFloat = 1600
    nonisolated static let framesPerSecond: Float = 30
    /// Average H.264 bitrate for recordings sent to a Mac: about 0.76 MB a second with audio.
    nonisolated static let videoBitRate = 6_000_000
    /// For HTTPS endpoints, whose uploads must stay under 95 MB: 3 Mbps video plus 96 kbps audio
    /// is about 0.39 MB a second, so the 3-minute cap (`Scrawl.hostedRecordingLimit`) comes to
    /// about 70 MB, leaving room for the encoder overshooting its average.
    nonisolated static let hostedVideoBitRate = 3_000_000
    nonisolated static let audioBitRate = 96000
    nonisolated static let signposter = OSSignposter(subsystem: "dev.kitlangton.scrawl", category: "PointsOfInterest")

    private enum State { case idle, starting, recording, finished }

    var onInterruption: (@MainActor @Sendable () -> Void)?
    var startupTrace: StartupTrace?
    private(set) var recordsAudio = false
    private(set) var pacer = FramePacer()
    static private(set) var lastMetrics: FramePacer.Metrics?
    private let videoBitRate: Int
    var method: ScrawlCaptureMethod { .appFrames }
    var isAvailable: Bool { true }

    private var state = State.idle
    private var startCompletion: (@MainActor @Sendable (Result<Date, any Error>) -> Void)?
    private var audioReady = false
    private var capturedFirstFrame = false
    private var startedAt = Date()
    private var firstFrameTime = CMTime.invalid
    private var writer: MovieWriter?
    private var microphone: MicrophoneCapture?
    private var displayLink: CADisplayLink?
    private var canvas = CGSize.zero
    private var observers: [any NSObjectProtocol] = []
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let temporaryMovie = FileManager.default.temporaryDirectory
      .appending(path: "scrawl-\(UUID().uuidString).mp4")

    init(videoBitRate: Int = AppFrameRecorder.videoBitRate) {
      self.videoBitRate = videoBitRate
      super.init()
    }

    nonisolated static func canvasSize(
      for points: CGSize,
      pixelsPerPoint: CGFloat = AppFrameRecorder.pixelsPerPoint,
      maxLongEdge: CGFloat = AppFrameRecorder.maxLongEdge
    ) -> CGSize {
      let longest = max(points.width, points.height)
      let scale = longest > 0 ? min(pixelsPerPoint, maxLongEdge / longest) : pixelsPerPoint
      return CGSize(width: even(points.width * scale), height: even(points.height * scale))
    }

    func start(microphone wantsMicrophone: Bool, completion: @escaping @MainActor @Sendable (Result<Date, any Error>) -> Void) {
      guard state == .idle else { return }
      state = .starting
      startedAt = Date()
      let start = MovieWriter.now()
      firstFrameTime = start
      startCompletion = completion
      // The writer/pixel pool and microphone have independent startup paths. UIKit capture
      // stays on main; all encoder and audio setup runs off it.
      begin(audio: wantsMicrophone, at: start)
      guard state == .starting else { return }
      observeBackgrounding()
      startupTrace?.mark("permissionBegin")
      guard wantsMicrophone else {
        startupTrace?.mark("permissionEnd")
        audioReady = true
        completeStartIfReady()
        return
      }
      switch AVAudioApplication.shared.recordPermission {
      case .granted:
        startupTrace?.mark("permissionEnd")
        startMicrophone()
      case .undetermined:
        AVAudioApplication.requestRecordPermission { granted in
          Task { @MainActor in
            self.startupTrace?.mark("permissionEnd")
            if granted {
              self.startMicrophone()
            } else {
              self.audioReady = true
              self.completeStartIfReady()
            }
          }
        }
      default:
        startupTrace?.mark("permissionEnd")
        audioReady = true
        completeStartIfReady()
      }
    }

    private func startMicrophone() {
      guard state == .starting || state == .recording else { return }
      let microphone = MicrophoneCapture()
      microphone.startupTrace = startupTrace
      self.microphone = microphone
      if let writer { microphone.attach(writer) }
      microphone.start { running in
        Task { @MainActor in
          guard self.state == .starting || self.state == .recording else { return }
          if !running {
            self.startupTrace?.mark("microphoneUnavailable")
            microphone.stop()
            self.microphone = nil
          }
          self.audioReady = true
          self.completeStartIfReady()
        }
      }
    }

    private func begin(audio: Bool, at start: CMTime) {
      guard let scene = Scrawl.activeScene else {
        failStart(RecorderError.noScene)
        return
      }
      let points = scene.coordinateSpace.bounds.size
      canvas = Self.canvasSize(for: points)
      pacer = FramePacer()
      let url = temporaryMovie
      let canvas = canvas
      let bitRate = videoBitRate
      let trace = startupTrace
      Task {
        do {
          let writer = try await Task.detached(priority: .userInitiated) {
            trace?.mark("writerBegin")
            do {
              let writer = try MovieWriter(url: url, size: canvas, audio: audio, videoBitRate: bitRate)
              try writer.begin(at: start)
              trace?.mark("writerEnd")
              return writer
            } catch {
              try? FileManager.default.removeItem(at: url)
              throw error
            }
          }.value
          guard state == .starting else {
            writer.cancel(removing: url)
            return
          }
          self.writer = writer
          microphone?.attach(writer)
          state = .recording
          let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
          link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: Self.framesPerSecond, preferred: Self.framesPerSecond)
          link.add(to: .main, forMode: .common)
          displayLink = link
          // Capture on the next display turn, after the overlay's initial layout can commit.
          completeStartIfReady()
        } catch {
          guard state == .starting else { return }
          failStart(error)
        }
      }
    }

    private func completeStartIfReady() {
      guard state == .recording, audioReady, capturedFirstFrame, let completion = startCompletion else { return }
      startCompletion = nil
      completion(.success(startedAt))
    }

    private func failStart(_ error: any Error) {
      let completion = startCompletion
      cancel()
      completion?(.failure(error))
    }

    func stop(writingTo movie: URL, completion: @escaping @MainActor @Sendable ((any Error)?) -> Void) {
      guard state == .recording, let writer else {
        completion(RecorderError.notRecording)
        return
      }
      let end = MovieWriter.now()
      state = .finished
      Self.lastMetrics = pacer.metrics
      let m = pacer.metrics
      Self.signposter.emitEvent(
        "CaptureSummary",
        "frames=\(m.framesCaptured) skippedCadence=\(m.ticksSkippedCadence) skippedBudget=\(m.ticksSkippedBudget) skippedBusy=\(m.ticksSkippedWriterBusy) meanDrawMs=\(m.meanDrawMs, format: .fixed(precision: 2)) maxDrawMs=\(m.maxDrawMs, format: .fixed(precision: 2)) hitches120=\(m.estimatedHitches120Hz)"
      )
      tearDown()
      // finishWriting has to complete even if the stop came from the app leaving the foreground.
      backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Scrawl recording") { [weak self] in
        MainActor.assumeIsolated { self?.endBackgroundTask() }
      }
      let temporaryMovie = temporaryMovie
      writer.finish(at: end) { error in
        Task { @MainActor in
          var failure = error
          if failure == nil {
            do {
              try? FileManager.default.removeItem(at: movie)
              try FileManager.default.moveItem(at: temporaryMovie, to: movie)
            } catch {
              failure = error
            }
          }
          if failure != nil { try? FileManager.default.removeItem(at: temporaryMovie) }
          self.recordsAudio = writer.audioSampleCount > 0
          self.writer = nil
          self.endBackgroundTask()
          completion(failure)
        }
      }
    }

    func cancel() {
      state = .finished
      startCompletion = nil
      Self.lastMetrics = pacer.metrics
      tearDown()
      writer?.cancel(removing: temporaryMovie)
      writer = nil
    }

    private func tearDown() {
      displayLink?.invalidate()
      displayLink = nil
      microphone?.stop()
      microphone = nil
      for observer in observers {
        NotificationCenter.default.removeObserver(observer)
      }
      observers = []
    }

    private func endBackgroundTask() {
      guard backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }

    /// Frames stop once the app is in the background and the microphone is cut off, so the
    /// recording finishes there rather than leave a gap (or a movie the system kills mid-write).
    /// Brief interruptions while still in the foreground (Control Center, a call banner, Siri)
    /// keep recording; the microphone restarts when the interruption ends.
    private func observeBackgrounding() {
      observers.append(NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.state == .starting || self.state == .recording else { return }
          if self.startCompletion != nil {
            self.failStart(RecorderError.notRecording)
          } else {
            self.onInterruption?()
          }
        }
      })
    }

    @objc private func tick(_ link: CADisplayLink) {
      guard state == .recording, let writer else { return }
      let now = CACurrentMediaTime()
      let time = capturedFirstFrame ? MovieWriter.now() : firstFrameTime
      if let moveTime = Scrawl.shared.lastTouchMoveMediaTime {
        pacer.noteInteractionMovement(at: moveTime)
      }
      let interacting = Scrawl.shared.isInteractingForCapture
      let writerReady = writer.isReadyForVideo(at: time)
      let decision = pacer.decide(
        linkTimestamp: link.timestamp,
        targetTimestamp: link.targetTimestamp,
        now: now,
        isInteracting: interacting,
        writerReady: writerReady
      )
      guard case .capture = decision else {
        if case let .skip(reason) = decision, reason != .cadence {
          Self.signposter.emitEvent("CaptureSkip", "\(String(describing: reason))")
        }
        return
      }
      let turnElapsed = max(0, now - link.timestamp)
      if let drawDuration = renderFrame(at: time, interacting: interacting) {
        pacer.recordCapture(
          at: now,
          drawDuration: drawDuration,
          turnElapsed: turnElapsed,
          isInteracting: interacting
        )
        capturedFirstFrame = true
        completeStartIfReady()
      }
    }

    /// Draws every visible app window, back to front, into a pooled pixel buffer and hands it to
    /// the writer queue. Returns the main-thread draw duration in seconds when a frame was captured.
    @discardableResult
    private func renderFrame(at time: CMTime, interacting: Bool = false) -> TimeInterval? {
      guard state == .recording, let writer, let scene = Scrawl.activeScene,
            let pixelBuffer = writer.dequeuePixelBuffer(for: time)
      else { return nil }
      let signpostID = Self.signposter.makeSignpostID()
      let interval = Self.signposter.beginInterval(
        "CaptureDraw",
        id: signpostID,
        "interacting=\(interacting ? 1 : 0)"
      )
      let t0 = CACurrentMediaTime()
      let drew = draw(scene, into: pixelBuffer)
      let drawDuration = max(0, CACurrentMediaTime() - t0)
      Self.signposter.endInterval(
        "CaptureDraw",
        interval,
        "ms=\(drawDuration * 1000, format: .fixed(precision: 2))"
      )
      guard drew else {
        writer.abandonPixelBuffer(pixelBuffer)
        return nil
      }
      writer.enqueueVideo(pixelBuffer, at: time)
      if !capturedFirstFrame { startupTrace?.mark("firstCapture") }
      return drawDuration
    }

    func draw(_ scene: UIWindowScene, into pixelBuffer: CVPixelBuffer) -> Bool {
      let windows = Self.recordedWindows(in: scene)
      guard !windows.isEmpty else { return false }
      let bounds = scene.coordinateSpace.bounds
      guard bounds.width > 0, bounds.height > 0 else { return false }

      CVPixelBufferLockBaseAddress(pixelBuffer, [])
      defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
      let width = CVPixelBufferGetWidth(pixelBuffer)
      let height = CVPixelBufferGetHeight(pixelBuffer)
      guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
            let context = CGContext(
              data: base,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
      else { return false }

      // Fit the scene into the movie (it only differs from the start if the device rotates),
      // with UIKit's top-left origin.
      let scale = min(CGFloat(width) / bounds.width, CGFloat(height) / bounds.height)
      let offsetX = (CGFloat(width) - bounds.width * scale) / 2
      let offsetY = (CGFloat(height) - bounds.height * scale) / 2
      // Pooled buffers hold the last frame drawn into them, and no window can be trusted to paint
      // every pixel (`isOpaque` is true by default even on clear windows).
      context.setFillColor(UIColor.black.cgColor)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.translateBy(x: offsetX, y: CGFloat(height) - offsetY)
      context.scaleBy(x: scale, y: -scale)
      context.interpolationQuality = .low

      UIGraphicsPushContext(context)
      defer { UIGraphicsPopContext() }
      for window in windows {
        if window.windowScene != nil {
          window.drawHierarchy(in: window.frame, afterScreenUpdates: false)
        } else {
          window.layer.render(in: context)
        }
      }
      // The keyboard is drawn by another process and comes out black, so a labelled panel stands
      // in for it wherever it is (mid-slide too), over anything any window drew there.
      if let keyboard = KeyboardTracker.shared.frame(in: scene) {
        KeyboardPanel.draw(in: keyboard, dark: scene.traitCollection.userInterfaceStyle == .dark)
      }
      return true
    }

    /// Every window that may show something, back to front. None is skipped as covered: `isOpaque`
    /// defaults to true on every window, including clear full-screen overlays (a host app's
    /// passthrough window, `UITextEffectsWindow` with an edit menu), and skipping what lies under
    /// one recorded black movies.
    static func recordedWindows(in scene: UIWindowScene) -> [UIWindow] {
      scene.windows
        .enumerated()
        .filter { _, window in
          shouldRecordWindow(window)
        }
        .sorted { lhs, rhs in
          lhs.element.windowLevel == rhs.element.windowLevel
            ? lhs.offset < rhs.offset
            : lhs.element.windowLevel < rhs.element.windowLevel
        }
        .map(\.element)
    }

    static func shouldRecordWindow(_ window: UIWindow) -> Bool {
      guard !(window is OverlayWindow), !isKeyboardHost(window),
            !window.isHidden, window.alpha > 0.01, !window.frame.isEmpty
      else { return false }
      if isTextEffectsWindow(window) {
        return hasVisibleTextEffects(in: window)
      }
      return true
    }

    /// The system's keyboard window (`UIRemoteKeyboardWindow` today): its keys are another
    /// process's layers, so drawing it costs a full-screen snapshot for black pixels. Matching by
    /// name only saves that work; the keyboard panel covers the keyboard's frame whichever window
    /// drew there, so a renamed class still records cleanly. `UITextEffectsWindow` is kept when it
    /// holds visible in-app text UI (edit menus, callout bars, the loupe); when empty, skipping it
    /// avoids a redundant full-screen snapshot pass on every frame.
    private static func isKeyboardHost(_ window: UIWindow) -> Bool {
      NSStringFromClass(type(of: window)).contains("Keyboard")
    }

    private static func isTextEffectsWindow(_ window: UIWindow) -> Bool {
      NSStringFromClass(type(of: window)).contains("TextEffects")
    }

    /// True when a `UITextEffectsWindow` has visible non-container subviews (edit menu, callout,
    /// magnifier loupe, or input accessory content) rather than only empty full-screen host views.
    static func hasVisibleTextEffects(in window: UIWindow) -> Bool {
      let windowSize = window.bounds.size
      func check(_ view: UIView, depth: Int) -> Bool {
        guard depth <= 6, !view.isHidden, view.alpha > 0.01,
              view.bounds.width >= 1, view.bounds.height >= 1
        else { return false }
        if view is UIControl || view is UILabel || view is UIImageView || view is UIVisualEffectView {
          return true
        }
        let isFullWindowContainer = abs(view.bounds.width - windowSize.width) < 1
          && abs(view.bounds.height - windowSize.height) < 1
        if !isFullWindowContainer, view.subviews.isEmpty {
          if let bg = view.backgroundColor, bg != .clear {
            return true
          }
          if view.layer.contents != nil || (view.layer.sublayers?.isEmpty == false) {
            return true
          }
        }
        for subview in view.subviews {
          if check(subview, depth: depth + 1) {
            return true
          }
        }
        return false
      }
      for child in window.subviews {
        if check(child, depth: 1) {
          return true
        }
      }
      return false
    }

    /// H.264 wants even dimensions.
    nonisolated private static func even(_ value: CGFloat) -> CGFloat {
      max(2, (value / 2).rounded() * 2)
    }
  }

  nonisolated enum RecorderError: LocalizedError {
    case noScene, notRecording, cannotWrite(String)

    var errorDescription: String? {
      switch self {
      case .noScene: "No active window scene to record"
      case .notRecording: "Not recording"
      case let .cannotWrite(reason): "Could not write the movie: \(reason)"
      }
    }
  }

  // MARK: - Movie Writer

  /// The `AVAssetWriter` behind an app-frame recording. Pixel-buffer pool allocation, video encoding,
  /// and audio sample appends run on `queue` so the main thread only takes `stateLock` across a few
  /// scalar fields (never across `AVAssetWriter` or buffer-pool calls) to dequeue a pre-allocated
  /// buffer and hand the drawn buffer off.
  nonisolated final class MovieWriter: @unchecked Sendable {
    private struct WriterState {
      var start = CMTime.invalid
      var lastQueuedVideoTime = CMTime.invalid
      var videoInFlight = false
      var isFinishing = false
      var pool: CVPixelBufferPool?
      var sparePixelBuffer: CVPixelBuffer?
      var audioSamples = 0
    }

    private let queue = DispatchQueue(label: "dev.kitlangton.scrawl.writer", qos: .userInitiated)
    private let stateLock = NSLock()
    private var state = WriterState()
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audio: AVAssetWriterInput?
    private var lastVideoTime = CMTime.invalid
    private var lastPixelBuffer: CVPixelBuffer?

    /// Now on the host clock, which video frames and (converted) audio samples share.
    static func now() -> CMTime {
      CMClockGetTime(CMClockGetHostTimeClock())
    }

    init(url: URL, size: CGSize, audio withAudio: Bool, videoBitRate: Int = AppFrameRecorder.videoBitRate) throws {
      writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
      writer.shouldOptimizeForNetworkUse = false

      video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(size.width),
        AVVideoHeightKey: Int(size.height),
        AVVideoColorPropertiesKey: [
          AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
          AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
          AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: videoBitRate,
          AVVideoExpectedSourceFrameRateKey: Int(AppFrameRecorder.framesPerSecond),
          AVVideoMaxKeyFrameIntervalKey: Int(AppFrameRecorder.framesPerSecond),
          AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
          AVVideoAllowFrameReorderingKey: false,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
      ])
      video.expectsMediaDataInRealTime = true
      adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width),
        kCVPixelBufferHeightKey as String: Int(size.height),
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      ])
      guard writer.canAdd(video) else { throw RecorderError.cannotWrite("video input rejected") }
      writer.add(video)

      if withAudio {
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC,
          AVNumberOfChannelsKey: 1,
          AVSampleRateKey: 48000,
          AVEncoderBitRateKey: AppFrameRecorder.audioBitRate,
        ])
        audio.expectsMediaDataInRealTime = true
        if writer.canAdd(audio) {
          writer.add(audio)
          self.audio = audio
        } else {
          self.audio = nil
        }
      } else {
        audio = nil
      }
    }

    func begin(at time: CMTime) throws {
      guard writer.startWriting() else {
        throw RecorderError.cannotWrite(writer.error?.localizedDescription ?? "startWriting failed")
      }
      writer.startSession(atSourceTime: time)
      let pool = adaptor.pixelBufferPool
      var initialSpare: CVPixelBuffer?
      if let pool {
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &initialSpare)
      }
      stateLock.lock()
      state.start = time
      state.pool = pool
      state.sparePixelBuffer = initialSpare
      stateLock.unlock()
    }

    /// The pool holding the adaptor's reusable pixel buffers (exists once writing has begun).
    var pixelBufferPool: CVPixelBufferPool? {
      stateLock.lock()
      defer { stateLock.unlock() }
      return state.pool
    }

    var audioSampleCount: Int {
      stateLock.lock()
      defer { stateLock.unlock() }
      return state.audioSamples
    }

    /// Whether a frame at `time` can be accepted right now without waiting on the encoder queue.
    func isReadyForVideo(at time: CMTime) -> Bool {
      stateLock.lock()
      defer { stateLock.unlock() }
      return !state.isFinishing && !state.videoInFlight && state.start.isValid
        && (state.lastQueuedVideoTime.isValid ? time > state.lastQueuedVideoTime : time >= state.start)
    }

    /// Claims a pre-allocated pixel buffer (or allocates one from the pool) and marks a frame in flight.
    func dequeuePixelBuffer(for time: CMTime) -> CVPixelBuffer? {
      stateLock.lock()
      guard !state.isFinishing, !state.videoInFlight, state.start.isValid,
            state.lastQueuedVideoTime.isValid ? time > state.lastQueuedVideoTime : time >= state.start
      else {
        stateLock.unlock()
        return nil
      }
      state.videoInFlight = true
      if let spare = state.sparePixelBuffer {
        state.sparePixelBuffer = nil
        stateLock.unlock()
        return spare
      }
      let pool = state.pool
      stateLock.unlock()

      guard let pool else {
        stateLock.lock()
        state.videoInFlight = false
        stateLock.unlock()
        return nil
      }
      var buffer: CVPixelBuffer?
      guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
            let buffer
      else {
        stateLock.lock()
        state.videoInFlight = false
        stateLock.unlock()
        return nil
      }
      return buffer
    }

    /// Returns an unused pixel buffer when `draw` fails before `enqueueVideo`.
    func abandonPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
      stateLock.lock()
      if state.sparePixelBuffer == nil, !state.isFinishing {
        state.sparePixelBuffer = pixelBuffer
      }
      state.videoInFlight = false
      stateLock.unlock()
    }

    /// Enqueues a drawn frame for asynchronous H.264 encoding on `queue` and pre-allocates the next
    /// spare pixel buffer off the main thread.
    func enqueueVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
      stateLock.lock()
      guard !state.isFinishing, state.start.isValid,
            state.lastQueuedVideoTime.isValid ? time > state.lastQueuedVideoTime : time >= state.start
      else {
        state.videoInFlight = false
        stateLock.unlock()
        return
      }
      state.lastQueuedVideoTime = time
      state.videoInFlight = true
      stateLock.unlock()

      let bufferBox = UncheckedBuffer(pixelBuffer)
      queue.async { [self] in
        appendVideoOnQueue(bufferBox.value, at: time)
      }
    }

    /// Synchronous append entry point used by benchmarks to compare synchronous vs asynchronous append.
    func appendVideoSynchronously(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
      let bufferBox = UncheckedBuffer(pixelBuffer)
      queue.sync {
        stateLock.lock()
        guard !state.isFinishing, state.start.isValid,
              state.lastQueuedVideoTime.isValid ? time > state.lastQueuedVideoTime : time >= state.start
        else {
          stateLock.unlock()
          return
        }
        state.lastQueuedVideoTime = time
        state.videoInFlight = true
        stateLock.unlock()
        appendVideoOnQueue(bufferBox.value, at: time)
      }
    }

    func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
      enqueueVideo(pixelBuffer, at: time)
    }

    /// Waits for any queued video or audio appends to finish on `queue` (used by deterministic benchmarks).
    func flushForTesting() {
      queue.sync {}
    }

    private func appendVideoOnQueue(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
      let signpostID = AppFrameRecorder.signposter.makeSignpostID()
      let interval = AppFrameRecorder.signposter.beginInterval("VideoAppend", id: signpostID)
      defer { AppFrameRecorder.signposter.endInterval("VideoAppend", interval) }

      // These frames were accepted before finish/cancel and precede it on this serial queue.
      // Dropping them just because finish was requested loses a quick tap's only frame.
      if writer.status == .writing, video.isReadyForMoreMediaData,
         lastVideoTime.isValid ? time > lastVideoTime : true
      {
        if adaptor.append(pixelBuffer, withPresentationTime: time) {
          lastVideoTime = time
          lastPixelBuffer = pixelBuffer
        }
      }
      var nextSpare: CVPixelBuffer?
      stateLock.lock()
      let needsSpare = !state.isFinishing && state.sparePixelBuffer == nil
      stateLock.unlock()
      if needsSpare, let pool = adaptor.pixelBufferPool {
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &nextSpare)
      }
      stateLock.lock()
      if !state.isFinishing, state.sparePixelBuffer == nil {
        state.sparePixelBuffer = nextSpare
      }
      state.videoInFlight = false
      stateLock.unlock()
    }

    /// Appends a microphone buffer already stamped on the host clock. Audio from before the first
    /// frame is dropped.
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
      let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      stateLock.lock()
      let allowed = !state.isFinishing && state.start.isValid && time >= state.start
      stateLock.unlock()
      guard allowed, audio != nil else { return }
      let box = UncheckedSampleBuffer(sampleBuffer)
      queue.async { [self] in
        stateLock.lock()
        let isFinishing = state.isFinishing
        stateLock.unlock()
        guard let audio, !isFinishing, writer.status == .writing, audio.isReadyForMoreMediaData else { return }
        if audio.append(box.value) {
          stateLock.lock()
          state.audioSamples += 1
          stateLock.unlock()
        }
      }
    }

    /// Ends the movie at `end` (the last frame holds until then) and finishes the file.
    func finish(at end: CMTime, completion: @escaping @Sendable ((any Error)?) -> Void) {
      stateLock.lock()
      let alreadyFinishing = state.isFinishing
      state.isFinishing = true
      state.sparePixelBuffer = nil
      stateLock.unlock()
      guard !alreadyFinishing else {
        completion(RecorderError.cannotWrite("already finishing"))
        return
      }
      queue.async { [self] in
        guard writer.status == .writing, lastVideoTime.isValid else {
          let reason = writer.error?.localizedDescription ?? "no frames were recorded"
          if writer.status == .writing { writer.cancelWriting() }
          completion(RecorderError.cannotWrite(reason))
          return
        }
        // With an audio track the movie ends at the last frame rather than at `endSession`, so the
        // last frame is repeated at `end` to make the movie as long as the timeline.
        if let lastPixelBuffer, end > lastVideoTime, video.isReadyForMoreMediaData,
           adaptor.append(lastPixelBuffer, withPresentationTime: end)
        {
          lastVideoTime = end
        }
        self.lastPixelBuffer = nil
        video.markAsFinished()
        audio?.markAsFinished()
        writer.endSession(atSourceTime: max(end, lastVideoTime))
        writer.finishWriting { [self] in
          if writer.status == .completed {
            completion(nil)
          } else {
            completion(RecorderError.cannotWrite(writer.error?.localizedDescription ?? "finishWriting failed"))
          }
        }
      }
    }

    func cancel(removing url: URL? = nil) {
      stateLock.lock()
      let alreadyFinishing = state.isFinishing
      state.isFinishing = true
      state.sparePixelBuffer = nil
      stateLock.unlock()
      guard !alreadyFinishing else { return }
      queue.async { [self] in
        self.lastPixelBuffer = nil
        if writer.status == .writing { writer.cancelWriting() }
        if let url { try? FileManager.default.removeItem(at: url) }
      }
    }
  }

  nonisolated private struct UncheckedBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
    init(_ value: CVPixelBuffer) { self.value = value }
  }

  nonisolated private struct UncheckedSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
    init(_ value: CMSampleBuffer) { self.value = value }
  }

  // MARK: - Microphone

  /// The microphone through `AVAudioEngine`. AVFAudio only: AVFoundation's capture-session and
  /// capture-device APIs would make App Store review demand a camera purpose string
  /// (ITMS-90683) from every app that links ScrawlKit.
  ///
  /// A tap on the input node delivers PCM buffers stamped with host time; each becomes a
  /// `CMSampleBuffer` on the host clock and goes to the `MovieWriter`. Starting, stopping, and
  /// restarting run on `queue`. When the engine's configuration changes (a route or sample-rate
  /// change) or an interruption ends, the tap is reinstalled and the engine started again.
  nonisolated final class MicrophoneCapture: @unchecked Sendable {
    var startupTrace: StartupTrace?
    // Audio-session ownership is process-wide: an old capture must finish restoring before
    // the next capture snapshots it. Separate per-capture queues raced on rapid restarts.
    private static let audioQueue = DispatchQueue(label: "dev.kitlangton.scrawl.microphone", qos: .userInitiated)
    private var queue: DispatchQueue { Self.audioQueue }
    private let lock = NSLock()
    private var writer: MovieWriter?
    private var pendingSamples: [CMSampleBuffer] = []
    private var stopped = false
    /// Guarded by `lock`, like `writer`.
    private let stream = MicrophoneStream()
    /// The rest is touched only on `queue`.
    private lazy var engine = AVAudioEngine()
    private var audioSession: AudioSessionSnapshot?
    private var observers: [any NSObjectProtocol] = []
    private var isRunning = false

    /// Configures the audio session and starts the engine off the main thread; `completion` gets
    /// whether the microphone is running.
    func start(completion: @escaping @Sendable (Bool) -> Void) {
      queue.async { [self] in
        completion(configureAndRun())
      }
    }

    /// Sends samples to `writer` from now on.
    func attach(_ writer: MovieWriter) {
      lock.lock()
      defer { lock.unlock() }
      guard !stopped else { return }
      self.writer = writer
      for sample in pendingSamples { writer.appendAudio(sample) }
      pendingSamples.removeAll()
    }

    /// Stops the engine and puts the app's audio session back the way it was.
    func stop() {
      lock.lock()
      guard !stopped else { lock.unlock(); return }
      stopped = true
      writer = nil
      pendingSamples.removeAll()
      lock.unlock()
      queue.async { [self] in
        for observer in observers {
          NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        if isRunning {
          engine.inputNode.removeTap(onBus: 0)
          engine.stop()
          isRunning = false
        }
        audioSession?.restore()
        audioSession = nil
      }
    }

    private func configureAndRun() -> Bool {
      lock.lock()
      let cancelled = stopped
      lock.unlock()
      guard !cancelled else { return false }
      startupTrace?.mark("audioSessionBegin")
      let shared = AVAudioSession.sharedInstance()
      let snapshot = AudioSessionSnapshot(shared)
      do {
        // Mix with (rather than interrupt) other audio, and keep the app's own sound on the
        // speaker or Bluetooth headphones instead of the receiver.
        try shared.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try shared.setActive(true)
        startupTrace?.mark("audioSessionEnd")
        try installTapAndStart()
        startupTrace?.mark("microphoneReady")
      } catch {
        print("Scrawl: microphone unavailable: \(error.localizedDescription)")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        snapshot.restore()
        return false
      }
      audioSession = snapshot
      isRunning = true
      observe()
      return true
    }

    /// Taps the input node in its current hardware format and starts the engine.
    private func installTapAndStart() throws {
      startupTrace?.mark("engineBegin")
      let input = engine.inputNode
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        throw RecorderError.cannotWrite("no microphone input")
      }
      input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
        self?.deliver(buffer, at: when)
      }
      engine.prepare()
      try engine.start()
      startupTrace?.mark("engineEnd")
    }

    /// Runs again after the engine stopped itself (configuration change, interruption, or a
    /// media services reset, which needs a new engine).
    private func restart(rebuildingEngine: Bool = false) {
      guard isRunning else { return }
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      if rebuildingEngine {
        engine = AVAudioEngine()
        observeConfigurationChanges()
      }
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        try installTapAndStart()
      } catch {
        print("Scrawl: microphone could not restart: \(error.localizedDescription)")
      }
    }

    private func observe() {
      observeConfigurationChanges()
      let center = NotificationCenter.default
      observers.append(center.addObserver(
        forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: nil
      ) { [weak self] notification in
        let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        guard let self, rawType.flatMap(AVAudioSession.InterruptionType.init) == .ended else { return }
        queue.async { self.restart() }
      })
      observers.append(center.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil
      ) { [weak self] _ in
        guard let self else { return }
        queue.async { self.restart(rebuildingEngine: true) }
      })
    }

    private func observeConfigurationChanges() {
      observers.append(NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
      ) { [weak self] _ in
        guard let self else { return }
        queue.async { self.restart() }
      })
    }

    /// On the engine's tap thread.
    private func deliver(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime) {
      let time = when.isHostTimeValid
        ? CMClockMakeHostTimeFromSystemUnits(when.hostTime)
        : CMTimeSubtract(MovieWriter.now(), CMTime(value: CMTimeValue(buffer.frameLength), timescale: CMTimeScale(buffer.format.sampleRate)))
      lock.lock()
      defer { lock.unlock() }
      guard !stopped, let sampleBuffer = stream.sampleBuffer(for: buffer, at: time) else { return }
      if let writer {
        writer.appendAudio(sampleBuffer)
      } else {
        // At most roughly half a second of 48 kHz mono audio while the writer gets ready.
        pendingSamples.append(sampleBuffer)
        while pendingSamples.count > 6 { pendingSamples.removeFirst() }
      }
    }
  }

  // MARK: - Microphone Stream

  /// Turns tap buffers into one steady stream for the writer's AAC input. That input fails the
  /// whole movie if its source format changes midway, and a route change (AirPods, a headset)
  /// changes the tap's sample rate or channel count, so every buffer is converted to `format`.
  /// Timestamps run on contiguously from the first buffer, so resampling can't make audio overlap
  /// or step backwards, and resync to the tap's host time only after a real gap (an interruption
  /// or restart); a buffer that is more than `tolerance` early is dropped.
  nonisolated final class MicrophoneStream {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    private static let tolerance = CMTime(value: 50, timescale: 1000)
    private var converter: AVAudioConverter?
    private var nextTime = CMTime.invalid

    func sampleBuffer(for buffer: AVAudioPCMBuffer, at time: CMTime) -> CMSampleBuffer? {
      if nextTime.isValid, time < CMTimeSubtract(nextTime, Self.tolerance) { return nil }
      guard let converted = convert(buffer), converted.frameLength > 0 else { return nil }
      if !nextTime.isValid || time > CMTimeAdd(nextTime, Self.tolerance) {
        nextTime = time
      }
      let sampleBuffer = converted.sampleBuffer(presentationTime: nextTime)
      nextTime = CMTimeAdd(nextTime, CMTime(value: CMTimeValue(converted.frameLength), timescale: CMTimeScale(Self.format.sampleRate)))
      return sampleBuffer
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
      let target = Self.format
      if buffer.format == target { return buffer }
      if converter?.inputFormat != buffer.format {
        converter = AVAudioConverter(from: buffer.format, to: target)
        converter?.downmix = true
      }
      guard let converter else { return nil }
      let ratio = target.sampleRate / buffer.format.sampleRate
      let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
      guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
      let input = ConverterInput(buffer)
      var error: NSError?
      let status = converter.convert(to: output, error: &error) { _, inputStatus in
        input.next(inputStatus)
      }
      return status == .error ? nil : output
    }
  }

  /// Hands one buffer to `AVAudioConverter`, then reports no more data for now (the converter
  /// keeps its resampling state for the next buffer).
  nonisolated private final class ConverterInput {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
      self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
      guard let buffer else {
        status.pointee = .noDataNow
        return nil
      }
      self.buffer = nil
      status.pointee = .haveData
      return buffer
    }
  }

  nonisolated extension AVAudioPCMBuffer {
    /// A copy of these frames as a `CMSampleBuffer` starting at `presentationTime`, in the
    /// buffer's own format.
    func sampleBuffer(presentationTime: CMTime) -> CMSampleBuffer? {
      let frames = CMItemCount(frameLength)
      let sampleRate = format.sampleRate
      guard frames > 0, sampleRate > 0 else { return nil }
      var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate.rounded())),
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: .invalid
      )
      var sampleBuffer: CMSampleBuffer?
      guard CMSampleBufferCreate(
        allocator: kCFAllocatorDefault,
        dataBuffer: nil,
        dataReady: false,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: format.formatDescription,
        sampleCount: frames,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sampleBuffer
      ) == noErr, let sampleBuffer else { return nil }
      // Copies the frames: the engine reuses the tap's buffer.
      guard CMSampleBufferSetDataBufferFromAudioBufferList(
        sampleBuffer,
        blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags: 0,
        bufferList: audioBufferList
      ) == noErr else { return nil }
      return sampleBuffer
    }
  }

  /// The app's audio session as it was before recording, to put back afterwards.
  nonisolated struct AudioSessionSnapshot {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions

    init(_ session: AVAudioSession) {
      category = session.category
      mode = session.mode
      options = session.categoryOptions
    }

    func restore() {
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(category, mode: mode, options: options)
      // Apps that play or record audio themselves manage their own session; for everything else
      // (the default solo-ambient or ambient) an active session left behind would silence other
      // apps' audio, so it goes back to inactive.
      let managesOwnAudio: Set<AVAudioSession.Category> = [.playback, .playAndRecord, .record, .multiRoute]
      if !managesOwnAudio.contains(category) {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
      }
    }
  }
#endif
#endif
