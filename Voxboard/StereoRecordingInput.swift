import AVFoundation
import UIKit
import VoxboardShared

/// Stereo capture from the iPhone's built-in microphones (iOS 14+), following
/// Apple's "Capturing stereo audio from built-in microphones": select a
/// built-in mic data source with a stereo polar pattern and set the input
/// orientation to match the interface.
///
/// Only used for High and Lossless with the Stereo setting on. Everything else,
/// including an external, Bluetooth or AirPods input, or a device without a
/// stereo polar pattern, stays mono and still records.
///
/// Main actor only: it touches UIKit scenes and shared session state.
@MainActor
enum StereoRecordingInput {
    enum Outcome: Equatable {
        /// Stereo was not asked for; any earlier stereo selection was undone.
        case notRequested
        /// The built-in mic data source with this name is set to stereo.
        /// `routeConfirmed` is false when the route had not reported the
        /// stereo pattern yet; the input node's channel count decides then
        /// (see `keptChannelCount`).
        case stereo(dataSource: String, routeConfirmed: Bool)
        /// Stereo was asked for but is not available; recording stays mono.
        case unavailable(reason: String)

        var isStereo: Bool {
            if case .stereo = self { return true }
            return false
        }
    }

    /// What the selection needs to know about one built-in mic data source.
    struct DataSourceCandidate: Equatable {
        var orientation: AVAudioSession.Orientation?
        var supportsStereo: Bool
    }

    /// Index of the data source to record stereo from: the front (screen-side)
    /// microphones first, as Voice Memos does, then the back, then any other
    /// source with a stereo polar pattern. nil when none supports stereo.
    static func preferredStereoSourceIndex(in candidates: [DataSourceCandidate]) -> Int? {
        let stereo = candidates.indices.filter { candidates[$0].supportsStereo }
        for orientation in [AVAudioSession.Orientation.front, .back] {
            if let index = stereo.first(where: { candidates[$0].orientation == orientation }) {
                return index
            }
        }
        return stereo.first
    }

    /// True when the current input route is the built-in microphone. Stereo
    /// never overrides an input the person chose (wired, USB, Bluetooth,
    /// AirPods, CarPlay).
    static func routeAllowsStereo(_ inputPortTypes: [AVAudioSession.Port]) -> Bool {
        inputPortTypes.count == 1 && inputPortTypes.first == .builtInMic
    }

    /// Stereo input orientation for an interface orientation. Unknown (for
    /// example while the app records in the background) is portrait.
    static func stereoOrientation(for interface: UIInterfaceOrientation) -> AVAudioSession.StereoOrientation {
        switch interface {
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }

    /// Interface orientation of the foreground window scene, if any.
    static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }

    /// The data source this process switched to stereo, so it can be undone
    /// when Stereo is turned off or the quality goes back to Speech.
    private static var configuredSource: (port: String, source: NSNumber)?

    /// Applies (or undoes) stereo on the active session. Call after
    /// `setCategory` / `setActive` and before reading the input node's format.
    /// Never throws: on any failure the session is left mono.
    @discardableResult
    static func configure(
        session: AVAudioSession = .sharedInstance(),
        requested: Bool,
        orientation: UIInterfaceOrientation? = nil
    ) -> Outcome {
        // Shared session state: main actor only, checked at run time too.
        MainActor.preconditionIsolated()
        guard requested else {
            resetIfNeeded(session: session)
            return .notRequested
        }
        let routeInputs = session.currentRoute.inputs.map(\.portType)
        guard routeAllowsStereo(routeInputs) else {
            resetIfNeeded(session: session)
            return .unavailable(reason: "input route \(routeInputs.map(\.rawValue))")
        }
        guard let port = session.availableInputs?.first(where: { $0.portType == .builtInMic }),
              let sources = port.dataSources, !sources.isEmpty else {
            return .unavailable(reason: "built-in mic has no data sources")
        }
        let candidates = sources.map {
            DataSourceCandidate(
                orientation: $0.orientation,
                supportsStereo: $0.supportedPolarPatterns?.contains(.stereo) ?? false
            )
        }
        guard let index = preferredStereoSourceIndex(in: candidates) else {
            return .unavailable(reason: "no stereo polar pattern")
        }
        let source = sources[index]
        do {
            // The built-in mic is already the active input (checked above),
            // so its data source changes take effect immediately. No
            // setPreferredInput: pinning the built-in mic would stop iOS from
            // switching to AirPods or a headset plugged in later.
            try source.setPreferredPolarPattern(.stereo)
            try port.setPreferredDataSource(source)
            let interface = orientation ?? currentInterfaceOrientation()
            try session.setPreferredInputOrientation(stereoOrientation(for: interface))
            configuredSource = (port.uid, source.dataSourceID)
            // The route normally reports the new pattern at once. Give it a
            // moment if not (at most ~200 ms, only when a stereo take starts),
            // but don't treat a late report as failure: the input node's
            // channel count, read next, is what decides stereo vs mono.
            let routeConfirmed = waitForRoute(timeout: 0.2) {
                let selected = session.currentRoute.inputs.first?.selectedDataSource
                return stereoApplied(
                    selectedDataSourceID: selected?.dataSourceID,
                    selectedPattern: selected?.selectedPolarPattern,
                    requestedDataSourceID: source.dataSourceID
                )
            }
            return .stereo(dataSource: source.dataSourceName, routeConfirmed: routeConfirmed)
        } catch {
            resetIfNeeded(session: session)
            return .unavailable(reason: "stereo setup failed: \(error.localizedDescription)")
        }
    }

    /// Channels the kept file records. Two only when stereo was configured
    /// and the input node actually delivers two channels: the node's format
    /// is the ground truth, so a route that reports the pattern late still
    /// records stereo, and a two-channel input that was not configured for
    /// stereo (a USB or line-in interface) stays on today's mono path.
    static func keptChannelCount(outcome: Outcome, inputNodeChannels: AVAudioChannelCount) -> Int {
        outcome.isStereo && inputNodeChannels >= 2 ? 2 : 1
    }

    private static func waitForRoute(timeout: TimeInterval, until applied: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if applied() { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// True when the active route reports the requested data source with the
    /// stereo polar pattern selected.
    static func stereoApplied(
        selectedDataSourceID: NSNumber?,
        selectedPattern: AVAudioSession.PolarPattern?,
        requestedDataSourceID: NSNumber
    ) -> Bool {
        selectedDataSourceID == requestedDataSourceID && selectedPattern == .stereo
    }

    /// True while this process has a built-in mic data source set to stereo.
    static var hasStereoSelection: Bool { configuredSource != nil }

    /// Updates the stereo image for the current interface orientation, for
    /// example when a new take starts after the phone was rotated.
    static func updateOrientation(session: AVAudioSession = .sharedInstance()) {
        guard configuredSource != nil else { return }
        try? session.setPreferredInputOrientation(stereoOrientation(for: currentInterfaceOrientation()))
    }

    /// Undoes the stereo selection. The selection is kept on record if the
    /// session refuses, so the next listening start or stop tries again.
    /// (Session preferences are per process, so a relaunch always starts
    /// from the system default.)
    private static func resetIfNeeded(session: AVAudioSession) {
        MainActor.preconditionIsolated()
        guard let configured = configuredSource else { return }
        guard let port = session.availableInputs?.first(where: { $0.uid == configured.port }) else {
            // The built-in mic is not available right now (another route);
            // its preference does not apply until it is, so retry later.
            return
        }
        do {
            if let source = port.dataSources?.first(where: { $0.dataSourceID == configured.source }) {
                try source.setPreferredPolarPattern(nil)
            }
            try port.setPreferredDataSource(nil)
            configuredSource = nil
        } catch {
            KeyboardDebugLog.shared.log(
                "[StereoRecordingInput] ⚠️ Could not undo stereo input; will retry: \(error.localizedDescription)"
            )
        }
    }
}

/// Interleaves two Float32 channels (L R L R …) into a buffer the audio tap
/// reuses, so stereo capture does not allocate on every tap callback. It only
/// grows when a larger buffer arrives.
///
/// Not thread-safe: one instance belongs to one tap, which AVAudioEngine calls
/// serially. The returned pointer is valid until the next `interleave` call.
nonisolated final class StereoInterleaveScratch: @unchecked Sendable {
    private var storage: UnsafeMutablePointer<Float>
    private var capacity: Int
    private let counterLock = NSLock()
    private var duplicatedFrames = 0

    init(initialFrames: Int = 8_192) {
        capacity = max(1, initialFrames) * 2
        storage = .allocate(capacity: capacity)
    }

    deinit { storage.deallocate() }

    /// Frames that arrived mono on this stereo tap since the last call
    /// (after a route change), then resets the count.
    func takeDuplicatedFrameCount() -> Int {
        counterLock.withLock {
            defer { duplicatedFrames = 0 }
            return duplicatedFrames
        }
    }

    /// Copies a mono buffer into both channels and counts it, so the
    /// recorder can report that part of a stereo take is dual-mono.
    func duplicateMono(_ mono: UnsafePointer<Float>, frames: Int) -> UnsafeBufferPointer<Float> {
        if frames > 0 { counterLock.withLock { duplicatedFrames += frames } }
        return interleave(left: mono, right: mono, frames: frames)
    }

    /// Interleaves `frames` frames from `left` and `right`. Pass the same
    /// pointer twice to duplicate a mono buffer into both channels.
    func interleave(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frames: Int
    ) -> UnsafeBufferPointer<Float> {
        guard frames > 0 else { return UnsafeBufferPointer(start: storage, count: 0) }
        let needed = frames * 2
        if needed > capacity {
            storage.deallocate()
            capacity = needed
            storage = .allocate(capacity: capacity)
        }
        for frame in 0..<frames {
            storage[frame * 2] = left[frame]
            storage[frame * 2 + 1] = right[frame]
        }
        return UnsafeBufferPointer(start: storage, count: needed)
    }
}
