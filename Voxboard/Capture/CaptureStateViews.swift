import AVFoundation
import Photos
import SwiftUI
import UIKit
import VoxboardShared

// MARK: - A · Vault unreachable

/// Inline banner shown when the active Route's vault folder bookmark can no
/// longer be resolved. Capturing continues; delivery waits in the inbox.
struct CaptureVaultUnreachableBanner: View {
    let regrantAccess: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Geist.warning)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Vault folder access expired")
                    .font(.custom("Geist-SemiBold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Geist.text)
                Text("Keep capturing. Everything is held on this iPhone and delivers as soon as access is back.")
                    .font(Geist.caption(.subheadline))
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: regrantAccess) {
                    Text("Re-grant access")
                        .font(.custom("Geist-SemiBold", size: 13.5, relativeTo: .footnote))
                        .foregroundStyle(Geist.bg)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Geist.text, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("capture_vault_regrant")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Geist.Palette.amber400, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture_vault_unreachable")
    }
}

/// Resolves whether a destination's vault bookmark still grants access.
enum CaptureVaultReachability {
    static func isReachable(_ destination: CaptureDestination) -> Bool {
        guard let resolution = try? CaptureBookmarkResolver.resolve(destination.rootBookmark),
              !resolution.isStale else { return false }
        let url = resolution.url
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Replaces the destination's folder bookmark with a freshly picked one,
    /// keeping its note target, placement and templates.
    static func regrant(destination: CaptureDestination, folderURL: URL) async throws {
        guard let root = AppConstants.captureDirectoryURL else { return }
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer { if didAccess { folderURL.stopAccessingSecurityScopedResource() } }
        let bookmark = try folderURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let store = CaptureLibraryStore(
            fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename)
        )
        _ = try await store.update { library in
            guard let index = library.destinations.firstIndex(where: { $0.id == destination.id }) else { return }
            library.destinations[index].rootBookmark = bookmark
            library.destinations[index].rootName = folderURL.lastPathComponent
        }
    }
}

// MARK: - B · Microphone off

struct CaptureMicrophoneOffCard: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Microphone is off for Vox.md")
                    .font(.custom("Geist-SemiBold", size: 16, relativeTo: .callout))
            } icon: {
                Image(systemName: "mic.slash")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Geist.text)
            Text("Audio is transcribed on this iPhone and saved beside your note. It never leaves your devices.")
                .font(Geist.caption(.subheadline))
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openSettings) {
                Text("Open Settings")
                    .font(.custom("Geist-SemiBold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Geist.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Geist.text, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("capture_microphone_open_settings")
        }
        .padding(16)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture_microphone_off")
    }
}

// MARK: - C · Offline processing

/// One finished Route run whose optional on-device processing step could not
/// run. The raw transcript was delivered; processing can be retried.
struct CaptureRouteProgress: Equatable, Identifiable {
    enum StepState: Equatable { case done, paused, skipped }

    let id = UUID()
    let transcriptID: UUID
    let flowID: String
    let audioDuration: TimeInterval
    let engineName: String
    let processingName: String
    let placementLabel: String
    var processingState: StepState = .paused
    var isRetrying = false
}

struct CaptureRouteProgressCard: View {
    let progress: CaptureRouteProgress
    let keepTranscriptOnly: () -> Void
    let retrySummary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ROUTE PROGRESS")
                    .font(Geist.mono(size: 10.5, relativeTo: .caption2))
                    .tracking(0.6)
                    .foregroundStyle(Geist.muted)
                VStack(alignment: .leading, spacing: 10) {
                    doneRow(String(localized: "Captured · \(Self.format(progress.audioDuration)) audio"))
                    doneRow(String(localized: "Transcribed · \(progress.engineName), on device"))
                    processingRow
                    doneRow(String(localized: "Delivered · \(progress.placementLabel)"))
                }
            }
            .padding(14)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )

            if progress.processingState == .paused {
                HStack(spacing: 8) {
                    Button(action: keepTranscriptOnly) {
                        Text("Keep transcript only")
                            .font(.custom("Geist-SemiBold", size: 14, relativeTo: .subheadline))
                            .foregroundStyle(Geist.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Geist.card, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).stroke(Geist.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button(action: retrySummary) {
                        Group {
                            if progress.isRetrying {
                                ProgressView().tint(Geist.bg)
                            } else {
                                Text("Retry summary")
                            }
                        }
                        .font(.custom("Geist-SemiBold", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(Geist.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Geist.text, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(progress.isRetrying)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture_route_progress")
    }

    private var processingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            switch progress.processingState {
            case .done:
                checkmark
                Text(verbatim: String(localized: "\(progress.processingName) · added"))
                    .font(Geist.body(.subheadline))
            case .skipped:
                Image(systemName: "minus.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(Geist.muted)
                Text(verbatim: String(localized: "\(progress.processingName) · skipped"))
                    .font(Geist.body(.subheadline))
                    .foregroundStyle(Geist.muted)
            case .paused:
                Circle()
                    .strokeBorder(Geist.Palette.amber900, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: String(localized: "\(progress.processingName) · paused"))
                        .font(Geist.body(.subheadline))
                    Text("Apple Intelligence isn’t available right now. Raw transcript delivered instead; summary will be added under it when ready.")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(Geist.text)
    }

    private func doneRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            checkmark
            Text(verbatim: text)
                .font(Geist.body(.subheadline))
                .foregroundStyle(Geist.text)
                .lineLimit(2)
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 17))
            .foregroundStyle(Geist.success)
            .accessibilityHidden(true)
    }

    static func format(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Attachments (inline voice clip, image and sketch thumbnails)

/// Inline voice clip card: play/pause, waveform with playback progress and a
/// mono status line ("0:42 · transcribed above · on-device").
struct CaptureInlineAudioChip: View {
    let url: URL?
    let label: String
    let hasTranscript: Bool
    let remove: () -> Void

    @State private var player = CaptureInlineAudioPlayer()

    private static let heights: [CGFloat] = [6, 10, 16, 9, 20, 14, 22, 12, 8, 18, 22, 16, 10, 6, 12, 20, 14, 8, 16, 22, 18, 10, 6, 14, 20, 12, 8, 16, 10, 6, 12, 8, 6, 4]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.toggle(url: url)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Geist.bg)
                    .frame(width: 40, height: 40)
                    .background(Geist.text, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(url == nil)
            .accessibilityLabel(Text(player.isPlaying ? "Pause voice clip" : "Play voice clip"))

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geometry in
                    let count = Self.heights.count
                    let played = Int((player.progress * Double(count)).rounded(.down))
                    HStack(spacing: 2) {
                        ForEach(0..<count, id: \.self) { index in
                            Capsule()
                                .fill(index < played ? Geist.text : Geist.Palette.gray500)
                                .frame(width: 3, height: Self.heights[index])
                        }
                    }
                    .frame(width: geometry.size.width, height: 22, alignment: .leading)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        player.seek(url: url, fraction: value.location.x / max(1, geometry.size.width))
                    })
                }
                .frame(height: 22)
                .accessibilityHidden(true)
                Text(verbatim: statusLine)
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
            }
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Geist.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(label)"))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Geist.border, lineWidth: 1))
        .task(id: url) { player.load(url: url) }
        .onDisappear { player.stop() }
    }

    private var statusLine: String {
        var parts = [CaptureRouteProgressCard.format(player.isPlaying || player.progress > 0 ? player.currentTime : player.duration)]
        if hasTranscript { parts.append(String(localized: "transcribed above")) }
        parts.append(String(localized: "on-device"))
        return parts.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class CaptureInlineAudioPlayer {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL?) {
        guard let url, audioPlayer?.url != url else { return }
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
        duration = audioPlayer?.duration ?? 0
    }

    func toggle(url: URL?) {
        load(url: url)
        guard let audioPlayer else { return }
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP])
            audioPlayer.play()
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    func seek(url: URL?, fraction: CGFloat) {
        load(url: url)
        guard let audioPlayer, audioPlayer.duration > 0 else { return }
        audioPlayer.currentTime = audioPlayer.duration * Double(min(1, max(0, fraction)))
        tick()
    }

    func stop() {
        audioPlayer?.stop()
        timer?.invalidate()
        isPlaying = false
    }

    private func tick() {
        guard let audioPlayer else { return }
        currentTime = audioPlayer.currentTime
        progress = audioPlayer.duration > 0 ? audioPlayer.currentTime / audioPlayer.duration : 0
        if !audioPlayer.isPlaying, isPlaying {
            isPlaying = false
            timer?.invalidate()
            progress = 0
            currentTime = 0
        }
    }
}

/// 104-pt rounded thumbnail for a staged image or sketch.
struct CaptureInlineImageTile: View {
    let url: URL?
    let label: String
    let isSketch: Bool
    let remove: () -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSketch ? Geist.card : Geist.Palette.gray300)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: isSketch ? .fit : .fill)
                    .padding(isSketch ? 10 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            Text(verbatim: isSketch ? String(localized: "Sketch") : "[\(label)]")
                .font(Geist.mono(size: 11.5, relativeTo: .caption))
                .foregroundStyle(image == nil || isSketch ? Geist.muted : Color.white)
                .shadow(color: image == nil || isSketch ? .clear : .black.opacity(0.5), radius: 2)
                .lineLimit(1)
                .padding(10)
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSketch ? Geist.border : Color.clear, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Geist.text)
                    .frame(width: 24, height: 24)
                    .background(Geist.card.opacity(0.9), in: Circle())
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(label)"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: label))
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 480, height: 480))
            }.value
        }
    }
}

// MARK: - Attach · recent photos

/// Recent photos strip for the Attach sheet. Reads only what Photos access
/// allows (full or limited) and never prompts until the strip is shown.
@MainActor
@Observable
final class CaptureRecentPhotosModel {
    enum Access { case unknown, authorized, limited, denied }

    private(set) var access: Access = .unknown
    private(set) var assets: [PHAsset] = []
    private let imageManager = PHCachingImageManager()

    func load() async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        switch status {
        case .authorized: access = .authorized
        case .limited: access = .limited
        default:
            access = .denied
            assets = []
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 12
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched
    }

    func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        let scale = UIScreen.main.scale
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        let gate = CaptureResumeGate()
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: side * scale, height: side * scale),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded || image == nil, gate.claim() else { return }
                continuation.resume(returning: image)
            }
        }
    }

    /// Full-quality image data for attaching to the draft.
    static func imageData(for asset: PHAsset) async -> (Data, String)? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (data, uti ?? "public.jpeg"))
            }
        }
    }
}

/// Ensures a continuation resumes once when a callback may fire repeatedly.
private final class CaptureResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}

struct CaptureRecentPhotosStrip: View {
    let model: CaptureRecentPhotosModel
    let isDisabled: Bool
    let pick: (PHAsset) -> Void
    let manageLimitedAccess: () -> Void

    var body: some View {
        Group {
            switch model.access {
            case .unknown:
                placeholderRow
            case .denied:
                Text("Allow Photos access in Settings to see recent photos here. All photos still works.")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .padding(.horizontal, 4)
            case .authorized, .limited:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                            CaptureRecentPhotoButton(
                                model: model,
                                asset: asset,
                                label: String(localized: "Recent photo \(index + 1)")
                            ) { pick(asset) }
                            .disabled(isDisabled)
                        }
                        if model.access == .limited {
                            Button(action: manageLimitedAccess) {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("More")
                                        .font(.custom("Geist-Medium", size: 11, relativeTo: .caption2))
                                }
                                .foregroundStyle(Geist.accentText)
                                .frame(width: 72, height: 72)
                                .background(Geist.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Geist.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Choose more photos Vox.md can see"))
                        }
                    }
                }
            }
        }
        .frame(minHeight: 72)
        .task { await model.load() }
    }

    private var placeholderRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Geist.Palette.gray300)
                    .frame(width: 72, height: 72)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CaptureRecentPhotoButton: View {
    let model: CaptureRecentPhotosModel
    let asset: PHAsset
    let label: String
    let action: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Geist.Palette.gray300)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .task(id: asset.localIdentifier) {
            image = await model.thumbnail(for: asset, side: 72)
        }
    }
}

// MARK: - Route pills while typing

extension CapturePresetProfile {
    /// Letter for the route's Signal tile: the name's first letter, or the
    /// emoji for an icon-only route.
    var routeTileLetter: String {
        visibleName ?? CapturePresetEmoji.normalized(emoji) ?? "•"
    }
}

/// Horizontal route radio row shown in place of the route pill while the
/// keyboard is up (Signal "Capture keyboard" artboard), and always on a
/// foldable's cover screen ("Duo cover · capture"). Every pill keeps its
/// route-order letter tile; only the selected pill shows the name.
struct CaptureRoutePillsRow: View {
    let profiles: [CapturePresetProfile]
    let selectedID: String?
    let isEnabled: Bool
    var pillHeight: CGFloat = 40
    let select: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    let isOn = profile.id == selectedID
                    Button {
                        guard !isOn else { return }
                        select(profile.id)
                    } label: {
                        HStack(spacing: 8) {
                            SignalRouteTile(
                                letter: profile.routeTileLetter,
                                size: 26,
                                circular: true,
                                tone: SignalRouteTileTone.forRoute(at: index)
                            )
                            if isOn, let name = profile.visibleName {
                                Text(verbatim: name)
                                    .font(.custom("Geist-SemiBold", size: 15, relativeTo: .subheadline))
                                    .foregroundStyle(Geist.text)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, isOn ? 7 : 6)
                        .padding(.trailing, isOn ? 14 : 6)
                        .frame(height: pillHeight)
                        .background(isOn ? Geist.card : Color.clear, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isOn ? Geist.text : Geist.border, lineWidth: isOn ? 1.5 : 1)
                        )
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: profile.accessibilityName))
                    .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(!isEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Route"))
        .accessibilityIdentifier("capture_route_pills")
    }
}
