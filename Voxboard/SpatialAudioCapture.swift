import AVFoundation
import UIKit
import VoxboardShared

// Spatial Audio capture on iPhone (#133, WWDC25 session 251).
//
// `AVAudioEngine` input taps can't deliver first-order ambisonics, so a
// Spatial Audio take records through an `AVCaptureSession` instead of the
// engine (never both: the capture session reconfigures the built-in mics,
// which would trip the engine's configuration-change handling mid-take).
// The capture session has two audio data outputs from the built-in mic:
//   - FOA (4 ch, ACN/SN3D) → the kept `.mp4`'s APAC track + metadata;
//   - stereo → the kept file's compatibility track, and, downmixed to
//     16 kHz mono, the same transcription stream and journal the engine tap
//     feeds, so pre-roll, live transcription and recovery keep working.
// Anything that keeps this from starting falls back to the engine (Stereo,
// then mono) without failing the recording. See docs/stereo-recording.md (Spatial Audio).

/// Whether this device can record Spatial Audio.
nonisolated enum SpatialAudioCaptureSupport: Equatable, Sendable {
    case supported
    /// Microphone access isn't granted yet, so the mic can't be checked.
    case needsMicrophoneAccess
    /// Not an iPhone, iOS before 26, or a microphone without FOA capture.
    case unavailable

    /// Pure decision, for tests.
    static func evaluate(
        isPhone: Bool,
        osSupportsSpatialCapture: Bool,
        microphoneAuthorized: Bool,
        microphoneSupportsAmbisonics: () -> Bool
    ) -> SpatialAudioCaptureSupport {
        guard isPhone, osSupportsSpatialCapture else { return .unavailable }
        guard microphoneAuthorized else { return .needsMicrophoneAccess }
        return microphoneSupportsAmbisonics() ? .supported : .unavailable
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedHardwareAnswer: Bool?

    /// The current answer. The hardware check (creating a capture input for
    /// the default microphone) runs once per process, only after microphone
    /// access is granted; it never prompts or starts capture.
    static var current: SpatialAudioCaptureSupport {
        let isPhone = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .phone }
        var osSupports = false
        if #available(iOS 26.0, *) { osSupports = true }
        return evaluate(
            isPhone: isPhone,
            osSupportsSpatialCapture: osSupports,
            microphoneAuthorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            microphoneSupportsAmbisonics: {
                cacheLock.withLock {
                    if let cachedHardwareAnswer { return cachedHardwareAnswer }
                    let answer = defaultMicrophoneSupportsAmbisonics()
                    cachedHardwareAnswer = answer
                    return answer
                }
            }
        )
    }

    private static func defaultMicrophoneSupportsAmbisonics() -> Bool {
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        return input.isMultichannelAudioModeSupported(.firstOrderAmbisonics)
    }
}

/// What the recorder needs from a running Spatial Audio capture. Not gated on
/// iOS 26 so `PersistentRecorder` can store it; only `SpatialAudioRecorder`
/// (iOS 26) conforms.
nonisolated protocol SpatialTakeRecording: AnyObject {
    /// Starts the kept file `seedDuration` seconds back (the 16 kHz journal's
    /// pre-roll). False when the writer can't start; the take then keeps
    /// the 16 kHz journal as its audio.
    func beginTake(url: URL, quality: RecordingQuality, seedDuration: TimeInterval) -> Bool
    func setPaused(_ paused: Bool)
    /// Finishes the kept `.mp4`; nil when nothing usable was written.
    func finishTake() -> URL?
    func discardTake()
    /// Stops capture. Any open take is discarded.
    func stop()
}

/// Factory, so callers don't need availability checks. Main actor (it reads
/// the audio route like `StereoRecordingInput`).
enum SpatialAudioRecording {
    struct StartFailure: Error, CustomStringConvertible {
        var description: String
    }

    /// Debug knob for device testing: `-VoxSpatialAutoConfiguresSession YES`
    /// lets the capture session configure the app's audio session itself.
    /// Off by default so the recorder keeps owning the session (category,
    /// options and the per-take re-assert stay as they are).
    static let autoConfiguresSessionKey = "VoxSpatialAutoConfiguresSession"

    /// Starts spatial capture. `onTranscriptionSamples` gets 16 kHz mono
    /// Float32 on the capture queue, like the engine tap's converted output.
    /// `onInterruption` runs on the main queue when capture stops on its own.
    static func start(
        preRollSeconds: TimeInterval,
        onTranscriptionSamples: @escaping (UnsafeBufferPointer<Float>) -> Void,
        onInterruption: @escaping (String) -> Void
    ) -> Result<SpatialTakeRecording, StartFailure> {
        guard #available(iOS 26.0, *) else {
            return .failure(StartFailure(description: "requires iOS 26"))
        }
        let routeInputs = AVAudioSession.sharedInstance().currentRoute.inputs.map(\.portType)
        // FOA is built-in mic only (`multichannelAudioMode` is ignored on an
        // external mic). Never override AirPods, wired, USB or CarPlay.
        guard StereoRecordingInput.routeAllowsStereo(routeInputs) else {
            return .failure(StartFailure(description: "input route \(routeInputs.map(\.rawValue))"))
        }
        let recorder = SpatialAudioRecorder(
            preRollSeconds: preRollSeconds,
            onTranscriptionSamples: onTranscriptionSamples,
            onInterruption: onInterruption
        )
        do {
            try recorder.start(
                autoConfiguresSession: UserDefaults.standard.bool(forKey: autoConfiguresSessionKey)
            )
            return .success(recorder)
        } catch {
            recorder.stop()
            return .failure(StartFailure(description: "\(error)"))
        }
    }
}

/// Adapts `AVCaptureSpatialAudioMetadataSampleGenerator` to the writer.
@available(iOS 26.0, *)
nonisolated final class CaptureSpatialAudioMetadataSource: SpatialAudioMetadataSource {
    private let generator = AVCaptureSpatialAudioMetadataSampleGenerator()

    var formatDescription: CMFormatDescription { generator.timedMetadataSampleBufferFormatDescription }

    func analyze(_ sampleBuffer: CMSampleBuffer) -> OSStatus {
        generator.analyzeAudioSample(sampleBuffer)
    }

    func makeMetadataSample() -> CMSampleBuffer? {
        // "new…": returned retained (+1).
        generator.newTimedMetadataSampleBufferAndResetAnalyzer()?.takeRetainedValue()
    }
}

/// Runs the capture session and owns the current take's writer. All capture
/// work and every writer call happen on `queue`.
@available(iOS 26.0, *)
nonisolated final class SpatialAudioRecorder: NSObject, SpatialTakeRecording,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {

    enum SetupError: Error, CustomStringConvertible {
        case noMicrophone
        case ambisonicsUnsupported
        case cannotAdd(String)
        case notRunning(String)
        case noBuffers(ambisonics: Int, stereo: Int)

        var description: String {
            switch self {
            case .noMicrophone: return "no capture microphone"
            case .ambisonicsUnsupported: return "microphone has no first-order ambisonics mode"
            case .cannotAdd(let what): return "capture session can't add \(what)"
            case .notRunning(let why): return "capture session not running: \(why)"
            case .noBuffers(let ambisonics, let stereo):
                return "no FOA/stereo buffers in time (FOA \(ambisonics) ch, stereo \(stereo) ch)"
            }
        }
    }

    /// How long `start` waits for the first 4-channel and 2-channel buffers.
    static let probeTimeout: TimeInterval = 0.75

    private let session = AVCaptureSession()
    private let ambisonicsOutput = AVCaptureAudioDataOutput()
    private let stereoOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "bontecou.Voxboard.spatial-capture", qos: .userInitiated)
    private let ring: SpatialSampleBufferRing
    private let onTranscriptionSamples: (UnsafeBufferPointer<Float>) -> Void
    private let onInterruption: (String) -> Void

    // Capture-queue state.
    private var ambisonicsSettings: [String: Any] = [:]
    private var writer: SpatialAudioFileWriter?
    private var pendingTake: (url: URL, quality: RecordingQuality, seed: TimeInterval)?
    private var paused = false
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private let transcriptionFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioFileConverter.whisperSampleRate,
        channels: 1,
        interleaved: false
    )!

    // Probe (start-up check) state, guarded by `probeLock`.
    private let probeLock = NSLock()
    private var firstAmbisonicsChannels = 0
    private var firstStereoChannels = 0
    private let probeReady = DispatchSemaphore(value: 0)
    private var observers: [NSObjectProtocol] = []

    init(
        preRollSeconds: TimeInterval,
        onTranscriptionSamples: @escaping (UnsafeBufferPointer<Float>) -> Void,
        onInterruption: @escaping (String) -> Void
    ) {
        ring = SpatialSampleBufferRing(maximumDuration: preRollSeconds)
        self.onTranscriptionSamples = onTranscriptionSamples
        self.onInterruption = onInterruption
    }

    func start(autoConfiguresSession: Bool) throws {
        guard let device = AVCaptureDevice.default(for: .audio) else { throw SetupError.noMicrophone }
        let input = try AVCaptureDeviceInput(device: device)
        guard input.isMultichannelAudioModeSupported(.firstOrderAmbisonics) else {
            throw SetupError.ambisonicsUnsupported
        }
        session.usesApplicationAudioSession = true
        session.automaticallyConfiguresApplicationAudioSession = autoConfiguresSession
        session.configuresApplicationAudioSessionToMixWithOthers = true

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw SetupError.cannotAdd("microphone input")
        }
        session.addInput(input)
        input.multichannelAudioMode = .firstOrderAmbisonics
        for output in [ambisonicsOutput, stereoOutput] {
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                throw SetupError.cannotAdd("audio data output")
            }
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: queue)
        }
        ambisonicsOutput.spatialAudioChannelLayoutTag = SpatialAudioRecordingFormat.ambisonicsLayoutTag
        stereoOutput.spatialAudioChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        // commitConfiguration validates the FOA output rules and throws an
        // Objective-C exception on violation; the setup above follows them.
        session.commitConfiguration()

        ambisonicsSettings = SpatialAudioRecordingFormat.ambisonicsSettings(
            recommended: ambisonicsOutput.recommendedAudioSettingsForAssetWriter(
                writingTo: SpatialAudioRecordingFormat.fileType
            )
        )
        observeSession()

        // startRunning blocks until running or failed; keep it off the main
        // thread's call stack (it still waits here, by design: the recorder
        // must know before falling back to the engine).
        queue.sync { session.startRunning() }
        guard session.isRunning else { throw SetupError.notRunning("startRunning returned") }

        // Spatial must really be flowing before the recorder commits to it.
        _ = probeReady.wait(timeout: .now() + Self.probeTimeout)
        let (ambisonics, stereo) = probeLock.withLock { (firstAmbisonicsChannels, firstStereoChannels) }
        guard ambisonics == SpatialAudioRecordingFormat.ambisonicsChannelCount, stereo == 2 else {
            throw SetupError.noBuffers(ambisonics: ambisonics, stereo: stereo)
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        // Removed in stop(), so only a session this recorder still owns reports.
        let report: (String) -> Void = { [weak self] reason in self?.onInterruption(reason) }
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            report("runtime error: \(error?.localizedDescription ?? "unknown")")
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main
        ) { note in
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
            report("interrupted (reason \(reason.map(String.init) ?? "unknown"))")
        })
    }

    // MARK: SpatialTakeRecording

    func beginTake(url: URL, quality: RecordingQuality, seedDuration: TimeInterval) -> Bool {
        queue.sync {
            discardOnQueue()
            paused = false
            guard let latest = ring.latestStereoEnd else {
                // No audio yet: start at the first buffer that arrives.
                pendingTake = (url, quality, 0)
                return true
            }
            return openWriter(url: url, quality: quality, startTime: CMTimeSubtract(
                latest, CMTime(seconds: max(0, seedDuration), preferredTimescale: 48_000)
            ))
        }
    }

    func setPaused(_ paused: Bool) {
        queue.async { [weak self] in
            self?.paused = paused
            self?.writer?.setPaused(paused)
        }
    }

    func finishTake() -> URL? {
        queue.sync {
            pendingTake = nil
            guard let writer else { return nil }
            self.writer = nil
            let result = writer.finish()
            KeyboardDebugLog.shared.log(
                "[SpatialAudio] Take finished: \(result.url == nil ? "no file" : "saved"), FOA frames=\(result.summary.ambisonicsFrames), stereo frames=\(result.summary.stereoFrames), dropped=\(result.summary.droppedBuffers), metadata=\(result.summary.wroteMetadata), analyzeFailures=\(result.summary.analyzeFailures)\(writer.error.map { ", error=\($0.localizedDescription)" } ?? "")"
            )
            return result.url
        }
    }

    func discardTake() {
        queue.sync { discardOnQueue() }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        queue.sync {
            discardOnQueue()
            if session.isRunning { session.stopRunning() }
            ring.removeAll()
        }
    }

    // MARK: Capture queue

    private func discardOnQueue() {
        pendingTake = nil
        writer?.discard()
        writer = nil
    }

    private func openWriter(url: URL, quality: RecordingQuality, startTime: CMTime) -> Bool {
        do {
            let writer = try SpatialAudioFileWriter(
                url: url,
                quality: quality,
                ambisonicsSettings: ambisonicsSettings,
                metadata: CaptureSpatialAudioMetadataSource(),
                startTime: startTime
            )
            // Pre-roll, interleaved by time so neither track starves the
            // writer's interleaving. The encoder may wait briefly here.
            let seed = (ring.buffers(.ambisonics, endingAfter: startTime).map { ($0, SpatialSampleBufferRing.Track.ambisonics) }
                + ring.buffers(.stereo, endingAfter: startTime).map { ($0, SpatialSampleBufferRing.Track.stereo) })
                .sorted { CMSampleBufferGetPresentationTimeStamp($0.0) < CMSampleBufferGetPresentationTimeStamp($1.0) }
            for (buffer, track) in seed {
                writer.append(buffer, to: track, waitIfBusy: 0.1)
            }
            self.writer = writer
            return true
        } catch {
            KeyboardDebugLog.shared.log("[SpatialAudio] ⚠️ Could not start the spatial file; keeping the 16 kHz recording: \(error)")
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let track: SpatialSampleBufferRing.Track = output === ambisonicsOutput ? .ambisonics : .stereo
        noteProbe(sampleBuffer, track: track)
        ring.append(sampleBuffer, track: track)
        if let pending = pendingTake, writer == nil {
            pendingTake = nil
            _ = openWriter(url: pending.url, quality: pending.quality,
                           startTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        if !paused { writer?.append(sampleBuffer, to: track) }
        if track == .stereo { feedTranscription(sampleBuffer) }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        KeyboardDebugLog.shared.log("[SpatialAudio] ⚠️ Capture dropped a \(output === ambisonicsOutput ? "FOA" : "stereo") buffer")
    }

    private func noteProbe(_ sampleBuffer: CMSampleBuffer, track: SpatialSampleBufferRing.Track) {
        probeLock.withLock {
            guard firstAmbisonicsChannels == 0 || firstStereoChannels == 0 else { return }
            let channels = SpatialAudioSampleBuffers.channelCount(of: sampleBuffer)
            switch track {
            case .ambisonics where firstAmbisonicsChannels == 0: firstAmbisonicsChannels = channels
            case .stereo where firstStereoChannels == 0: firstStereoChannels = channels
            default: break
            }
            if firstAmbisonicsChannels != 0, firstStereoChannels != 0 { probeReady.signal() }
        }
    }

    /// Stereo → 16 kHz mono (left and right averaged, like a stereo take).
    private func feedTranscription(_ sampleBuffer: CMSampleBuffer) {
        guard let input = SpatialAudioSampleBuffers.pcmBuffer(from: sampleBuffer) else { return }
        if converterInputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: transcriptionFormat)
            converter?.downmix = true
            converterInputFormat = input.format
        }
        guard let converter else { return }
        let ratio = transcriptionFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: transcriptionFormat, frameCapacity: capacity) else { return }
        var supplied = false
        converter.convert(to: output, error: nil) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let data = output.floatChannelData?[0], output.frameLength > 0 {
            onTranscriptionSamples(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
        }
    }
}
