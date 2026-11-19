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
        case stereo(dataSource: String)
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
            try source.setPreferredPolarPattern(.stereo)
            try port.setPreferredDataSource(source)
            let interface = orientation ?? currentInterfaceOrientation()
            try session.setPreferredInputOrientation(stereoOrientation(for: interface))
            configuredSource = (port.uid, source.dataSourceID)
            return .stereo(dataSource: source.dataSourceName)
        } catch {
            resetIfNeeded(session: session)
            return .unavailable(reason: "stereo setup failed: \(error.localizedDescription)")
        }
    }

    /// Updates the stereo image for the current interface orientation, for
    /// example when a new take starts after the phone was rotated.
    static func updateOrientation(session: AVAudioSession = .sharedInstance()) {
        guard configuredSource != nil else { return }
        try? session.setPreferredInputOrientation(stereoOrientation(for: currentInterfaceOrientation()))
    }

    private static func resetIfNeeded(session: AVAudioSession) {
        guard let configured = configuredSource else { return }
        configuredSource = nil
        guard let port = session.availableInputs?.first(where: { $0.uid == configured.port }) else { return }
        if let source = port.dataSources?.first(where: { $0.dataSourceID == configured.source }) {
            try? source.setPreferredPolarPattern(nil)
        }
        try? port.setPreferredDataSource(nil)
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

    init(initialFrames: Int = 8_192) {
        capacity = max(1, initialFrames) * 2
        storage = .allocate(capacity: capacity)
    }

    deinit { storage.deallocate() }

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
