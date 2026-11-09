#if canImport(FoundationModels)
import FoundationModels
#endif
import CoreText
import LinkPresentation
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VoxboardShared

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        ShareSignal.registerFonts()
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
        let model = ShareCaptureModel(providers: providers, extensionContext: extensionContext)
        let host = UIHostingController(rootView: ShareCaptureView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}

@MainActor
@Observable
private final class ShareCaptureModel {
    var destinations: [CaptureDestination] = []
    var presets: [CapturePresetProfile] = []
    var selectedPresetID: String?
    var selectedDestinationID: UUID?
    var libraryDefaultDestinationID: UUID?
    var note = ""
    var isLoading = true
    var isSubmitting = false
    var isQueuedForLater = false
    var errorMessage: String?
    var locationDecision: (reason: CaptureLocationUnavailableReason, attemptedAt: Date)?
    /// Shared page preview: thumbnail and an on-device summary of its text.
    var pageThumbnail: UIImage?
    var pageSummary: String?

    private let providers: [NSItemProvider]
    private weak var extensionContext: NSExtensionContext?
    private let requestID = UUID()
    private var loadedPayloads: [CapturePayload] = []
    private var captureRootURL: URL?
    private var cancellationRequested = false
    private var pendingSendWithoutLocationOutcome: CaptureLocationOutcome?
    private let locationProvider: any CaptureLocationOutcomeProviding = CaptureLocationService()

    init(providers: [NSItemProvider], extensionContext: NSExtensionContext?) {
        self.providers = providers
        self.extensionContext = extensionContext
    }

    func load() async {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.bontecou.Voxboard"
        ) else {
            fail("Shared capture storage is unavailable.")
            return
        }
        let captureRoot = container.appendingPathComponent("Capture", isDirectory: true)
        captureRootURL = captureRoot
        do {
            let library = try await CaptureLibraryStore(
                fileURL: captureRoot.appendingPathComponent(CaptureLibraryStore.defaultFilename)
            ).load()
            destinations = library.destinations
            libraryDefaultDestinationID = library.defaultDestinationID
            let sharedDefaults = UserDefaults(suiteName: "group.bontecou.Voxboard")
            presets = CapturePresetProfileStore.enabledProfiles(defaults: sharedDefaults)
            for index in presets.indices where presets[index].captureDestinationID == nil {
                presets[index].captureDestinationID = library.legacyFlowBindings[presets[index].id]
            }
            selectedPresetID = CapturePresetProfileStore.selectedProfileID(defaults: sharedDefaults)
            selectedDestinationID = resolvedDestinationID(
                profile: selectedPreset,
                libraryDefaultID: library.defaultDestinationID
            )
            guard selectedDestinationID != nil else {
                throw ShareCaptureError.destinationRequired
            }
            loadedPayloads = try await ShareItemLoader.load(
                providers: providers,
                requestID: requestID,
                captureRootURL: captureRoot
            )
            guard !cancellationRequested else {
                removeStagingDirectory()
                finishCancellation()
                return
            }
            isLoading = false
            loadPagePreview()
        } catch is CancellationError {
            removeStagingDirectory()
            if cancellationRequested { finishCancellation() }
        } catch {
            removeStagingDirectory()
            if cancellationRequested {
                finishCancellation()
            } else {
                fail(error.localizedDescription)
            }
        }
    }

    /// Lightweight description of the first shared item for the preview card.
    var sharedItemSummary: (title: String, detail: String, symbol: String)? {
        guard let first = loadedPayloads.first else { return nil }
        let extra = loadedPayloads.count > 1
            ? String(localized: " · \(loadedPayloads.count) items")
            : ""
        switch first {
        case .url(let url, let title):
            let host = url.host().map { $0 + url.path() } ?? url.absoluteString
            return (title?.isEmpty == false ? title! : host, host + extra, "link")
        case .text(let text):
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return (line, String(localized: "Text") + extra, "text.alignleft")
        case .image(let asset, _, _):
            return (asset.originalFilename, String(localized: "Image") + extra, "photo")
        case .audio(let asset, _), .retainedAudio(let asset, _):
            return (asset.originalFilename, String(localized: "Audio") + extra, "waveform")
        case .file(let asset):
            return (asset.originalFilename, String(localized: "File") + extra, "doc")
        case .scannedDocument(let pages, _, _):
            return (String(localized: "Scanned document"), String(localized: "\(pages.count) pages") + extra, "doc.text.viewfinder")
        case .sketch:
            return (String(localized: "Sketch"), String(localized: "Drawing") + extra, "scribble")
        }
    }

    var selectedPreset: CapturePresetProfile? {
        guard let selectedPresetID else { return nil }
        return presets.first(where: { $0.id == selectedPresetID })
    }

    private var sharedPageURL: URL? {
        for payload in loadedPayloads {
            if case .url(let url, _) = payload { return url }
        }
        return nil
    }

    /// Thumbnail via LinkPresentation and a short summary of the page. Both
    /// are best-effort and never block sending.
    private func loadPagePreview() {
        guard let url = sharedPageURL else { return }
        Task { @MainActor [weak self] in
            if let image = await SharePagePreview.thumbnail(for: url) { self?.pageThumbnail = image }
        }
        Task { @MainActor [weak self] in
            if let summary = await SharePagePreview.summary(for: url) { self?.pageSummary = summary }
        }
    }

    /// "→ Inbox/{title}.md · link, note and page summary" for the selected route.
    var destinationLine: String? {
        guard let destination = destinations.first(where: { $0.id == selectedDestinationID }) else { return nil }
        var path: String
        switch destination.noteTarget {
        case .newNote(let template), .rollingNote(let template, _): path = template
        case .existingNote(let relativePath): path = relativePath
        }
        if (path as NSString).pathExtension.isEmpty { path += ".md" }
        if case .beneathHeading(let heading, _, _) = destination.placement {
            path += " › ## \(heading.title)"
        }
        var parts: [String] = []
        for payload in loadedPayloads {
            let part: String
            switch payload {
            case .url: part = String(localized: "link")
            case .text: part = String(localized: "text")
            case .image: part = String(localized: "image")
            case .audio, .retainedAudio: part = String(localized: "audio")
            case .file, .scannedDocument, .sketch: part = String(localized: "file")
            }
            if !parts.contains(part) { parts.append(part) }
        }
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(String(localized: "note")) }
        if pageSummary != nil { parts.append(String(localized: "page summary")) }
        let contents = parts.isEmpty ? "" : " · " + ListFormatter.localizedString(byJoining: parts)
        return "→ \(path)\(contents)"
    }

    func applySelectedPresetDestination() {
        selectedDestinationID = CapturePresetRouteResolver.destinationID(
            selectionMode: .inherited,
            explicitDestinationID: nil,
            profile: selectedPreset,
            destinations: destinations,
            libraryDefaultDestinationID: libraryDefaultDestinationID,
            allowsLegacyFallback: !CapturePresetProfileStore.hasOwnedRouteMigration(
                defaults: UserDefaults(suiteName: "group.bontecou.Voxboard")
            )
        )
        if let selectedPresetID {
            CapturePresetProfileStore.selectCaptureProfile(
                id: selectedPresetID,
                defaults: UserDefaults(suiteName: "group.bontecou.Voxboard")
            )
        }
    }

    func submit() async {
        guard !isSubmitting, !cancellationRequested else { return }
        if isQueuedForLater {
            await openQueuedCapture()
            return
        }
        guard let captureRootURL, let selectedDestinationID else {
            fail(ShareCaptureError.destinationRequired.localizedDescription)
            return
        }
        var payloads: [CapturePayload] = []
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var textBudget = CaptureInputBudget()
            for payload in loadedPayloads {
                if case .text(let text) = payload {
                    try textBudget.reserveText(characters: text.count)
                }
            }
            try textBudget.reserveText(characters: trimmed.count)
        } catch {
            fail(error.localizedDescription)
            return
        }
        if !trimmed.isEmpty { payloads.append(.text(trimmed)) }
        payloads.append(contentsOf: loadedPayloads)
        // The page summary follows its link as a quote; skipped if it would
        // exceed the text budget.
        if let summary = pageSummary,
           let linkIndex = payloads.firstIndex(where: { if case .url = $0 { return true } else { return false } }) {
            var summaryBudget = CaptureInputBudget()
            let quoted = summary.split(whereSeparator: \.isNewline).map { "> \($0)" }.joined(separator: "\n")
            if (try? summaryBudget.reserveText(characters: quoted.count + trimmed.count)) != nil {
                payloads.insert(.text(quoted), at: linkIndex + 1)
            }
        }
        guard !payloads.isEmpty else {
            fail(ShareCaptureError.emptyShare.localizedDescription)
            return
        }

        isSubmitting = true
        do {
            let profile = selectedPreset
            var locationOutcome: CaptureLocationOutcome?
            var locationDecisionOverride: CaptureLocationDecisionOverride?
            if let policy = profile?.locationPolicy, policy.isEnabled {
                let usedExplicitSendWithout = pendingSendWithoutLocationOutcome != nil
                let outcome: CaptureLocationOutcome
                if let pendingSendWithoutLocationOutcome {
                    outcome = pendingSendWithoutLocationOutcome
                } else {
                    outcome = await locationProvider.resolveLocation(
                        policy: policy,
                        source: .shareExtension
                    )
                }
                pendingSendWithoutLocationOutcome = nil
                if case .unavailable(let reason, let attemptedAt) = outcome,
                   !usedExplicitSendWithout {
                    switch policy.unavailableBehavior {
                    case .ask:
                        locationDecision = (reason, attemptedAt)
                        isSubmitting = false
                        return
                    case .cancel:
                        isSubmitting = false
                        cancel()
                        return
                    case .sendWithoutLocation:
                        break
                    }
                }
                locationOutcome = outcome
                if usedExplicitSendWithout {
                    locationDecisionOverride = .sendWithoutLocation
                }
            }
            let processingState = profile?.processingState(for: payloads) ?? .notRequested
            let request = CaptureRequest(
                id: requestID,
                source: .shareExtension,
                destinationID: selectedDestinationID,
                payloads: payloads,
                frontmatter: profile?.staticFrontmatter ?? [:],
                voxProfile: profile,
                voxProcessingState: processingState,
                locationOutcome: locationOutcome,
                locationDecisionOverride: locationDecisionOverride
            )
            try await CaptureInbox(rootDirectoryURL: captureRootURL).enqueue(request)
            isQueuedForLater = true
            if cancellationRequested {
                extensionContext?.completeRequest(returningItems: nil)
                return
            }
            await openQueuedCapture()
            return
        } catch {
            isSubmitting = false
            if cancellationRequested {
                removeStagingDirectory()
                finishCancellation()
            } else {
                fail(error.localizedDescription)
            }
        }
    }

    func retryUnavailableLocation() async {
        locationDecision = nil
        pendingSendWithoutLocationOutcome = nil
        await submit()
    }

    func sendWithoutUnavailableLocation(alwaysForPreset: Bool) async {
        guard let decision = locationDecision else { return }
        pendingSendWithoutLocationOutcome = .unavailable(
            decision.reason,
            attemptedAt: decision.attemptedAt
        )
        if alwaysForPreset, let presetID = selectedPreset?.id {
            CapturePresetStore.setLocationUnavailableBehavior(
                .sendWithoutLocation,
                presetID: presetID,
                defaults: UserDefaults(suiteName: "group.bontecou.Voxboard")
            )
            if let index = presets.firstIndex(where: { $0.id == presetID }) {
                presets[index].locationPolicy.unavailableBehavior = .sendWithoutLocation
            }
        }
        locationDecision = nil
        await submit()
    }

    func cancelUnavailableLocation() {
        locationDecision = nil
        pendingSendWithoutLocationOutcome = nil
        cancel()
    }

    private func resolvedDestinationID(
        profile: CapturePresetProfile?,
        libraryDefaultID: UUID?
    ) -> UUID? {
        CapturePresetRouteResolver.destinationID(
            selectionMode: .inherited,
            explicitDestinationID: nil,
            profile: profile,
            destinations: destinations,
            libraryDefaultDestinationID: libraryDefaultID,
            allowsLegacyFallback: !CapturePresetProfileStore.hasOwnedRouteMigration(
                defaults: UserDefaults(suiteName: "group.bontecou.Voxboard")
            )
        )
    }

    private func openQueuedCapture() async {
        isSubmitting = true
        errorMessage = nil
        let callback = URL(string: "voxboard://capture-request?id=\(requestID.uuidString)")!
        let didOpen = await extensionContext?.open(callback) ?? false
        if didOpen {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            isSubmitting = false
            fail(String(localized: "Capture is safely queued in Vox.md. Open Vox.md to finish delivery, then tap Done here."))
        }
    }

    func cancel() {
        cancellationRequested = true
        if isQueuedForLater {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        // Do not delete staging while an enqueue may be committing a request
        // that references it. The submit path finishes cancellation once it
        // has atomically reached either queued or failed state.
        if isSubmitting || isLoading { return }
        removeStagingDirectory()
        finishCancellation()
    }

    private func finishCancellation() {
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: "VoxboardShare",
                code: NSUserCancelledError,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Capture cancelled")]
            )
        )
    }

    private func fail(_ message: String) {
        errorMessage = message
        isLoading = false
    }

    private func removeStagingDirectory() {
        guard let captureRootURL else { return }
        let staging = captureRootURL
            .appendingPathComponent("inbox-staging", isDirectory: true)
            .appendingPathComponent(requestID.uuidString.lowercased(), isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
    }
}

private enum ShareItemLoader {
    static func load(
        providers: [NSItemProvider],
        requestID: UUID,
        captureRootURL: URL
    ) async throws -> [CapturePayload] {
        var payloads: [CapturePayload] = []
        var budget = CaptureInputBudget()
        try budget.reserveSharedItems(providers.count)
        let stagingDirectory = captureRootURL
            .appendingPathComponent("inbox-staging", isDirectory: true)
            .appendingPathComponent(requestID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        for provider in providers {
            try Task.checkCancellation()
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try await loadURL(provider),
               CaptureWebLink.isValid(url) {
                payloads.append(.url(url, title: provider.suggestedName))
                continue
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try await loadText(provider) {
                try budget.reserveText(characters: text.count)
                payloads.append(.text(text))
                continue
            }
            guard let typeIdentifier = preferredFileType(from: provider.registeredTypeIdentifiers) else {
                continue
            }
            let copiedURL = try await copyFile(
                provider: provider,
                typeIdentifier: typeIdentifier,
                to: stagingDirectory
            )
            let relativePath = "inbox-staging/\(requestID.uuidString.lowercased())/\(copiedURL.lastPathComponent)"
            try Task.checkCancellation()
            let values = try copiedURL.resourceValues(forKeys: [.fileSizeKey])
            try budget.reserveAsset(bytes: Int64(values.fileSize ?? 0))
            let asset = try CaptureAssetReference(
                relativePath: relativePath,
                originalFilename: copiedURL.lastPathComponent,
                contentTypeIdentifier: typeIdentifier,
                byteCount: values.fileSize.map(Int64.init)
            )
            let type = UTType(typeIdentifier)
            if type?.conforms(to: .image) == true {
                payloads.append(.image(asset, altText: provider.suggestedName, altTextOrigin: .placeholder))
            } else if type?.conforms(to: .audio) == true {
                payloads.append(.audio(asset, transcript: nil))
            } else {
                payloads.append(.file(asset))
            }
        }
        return payloads
    }

    private static func preferredFileType(from identifiers: [String]) -> String? {
        identifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image)
                || type.conforms(to: .audio)
                || type.conforms(to: .movie)
                || type.conforms(to: .pdf)
                || type.conforms(to: .data)
        }
    }

    private static func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error { return continuation.resume(throwing: error) }
                if let url = item as? URL { return continuation.resume(returning: url) }
                if let value = item as? String { return continuation.resume(returning: URL(string: value)) }
                continuation.resume(returning: nil)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error { return continuation.resume(throwing: error) }
                continuation.resume(returning: item as? String)
            }
        }
    }

    private static func copyFile(
        provider: NSItemProvider,
        typeIdentifier: String,
        to directory: URL
    ) async throws -> URL {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
                if let error { return continuation.resume(throwing: error) }
                guard let sourceURL else {
                    return continuation.resume(throwing: ShareCaptureError.missingSharedFile)
                }
                var copiedDestination: URL?
                do {
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
                        throw ShareCaptureError.missingSharedFile
                    }
                    guard !isDirectory.boolValue else {
                        throw CaptureAssetStagerError.sourceIsDirectory(sourceURL.path)
                    }
                    let requestedName = suggestedName ?? sourceURL.lastPathComponent
                    let sourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
                    if let size = sourceValues.fileSize,
                       Int64(size) > CaptureAssetStager.defaultMaximumByteCount {
                        throw CaptureAssetStagerError.assetTooLarge(
                            filename: requestedName,
                            byteCount: Int64(size),
                            limit: CaptureAssetStager.defaultMaximumByteCount
                        )
                    }
                    let proposed = CaptureAssetStager.sanitizedFilename(
                        requestedName,
                        fallbackExtension: sourceURL.pathExtension
                    )
                    let destination = uniqueURL(directory.appendingPathComponent(proposed))
                    copiedDestination = destination
                    try FileManager.default.copyItem(at: sourceURL, to: destination)
                    let copiedValues = try destination.resourceValues(forKeys: [.fileSizeKey])
                    if let size = copiedValues.fileSize,
                       Int64(size) > CaptureAssetStager.defaultMaximumByteCount {
                        try? FileManager.default.removeItem(at: destination)
                        throw CaptureAssetStagerError.assetTooLarge(
                            filename: requestedName,
                            byteCount: Int64(size),
                            limit: CaptureAssetStager.defaultMaximumByteCount
                        )
                    }
                    continuation.resume(returning: destination)
                } catch {
                    if let copiedDestination {
                        try? FileManager.default.removeItem(at: copiedDestination)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func uniqueURL(_ initialURL: URL) -> URL {
        guard FileManager.default.fileExists(atPath: initialURL.path) else { return initialURL }
        let ext = initialURL.pathExtension
        let base = initialURL.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let candidate = initialURL.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}

/// Route tile tone by route order, mirroring the app's `SignalRouteTileTone`
/// (the extension does not compile GeistTheme): the first route indigo, the
/// second near-black ink (inverted in dark mode), every other route neutral.
private enum ShareRouteTileTone {
    case primary
    case ink
    case neutral

    static func forRoute(at index: Int?) -> ShareRouteTileTone {
        switch index {
        case 0: .primary
        case 1: .ink
        default: .neutral
        }
    }

    var fill: Color {
        switch self {
        case .primary: ShareSignal.accent
        case .ink: ShareSignal.text
        case .neutral: ShareSignal.well
        }
    }

    var letter: Color {
        switch self {
        case .primary: .white
        case .ink: ShareSignal.bg
        case .neutral: ShareSignal.text
        }
    }
}

/// Signal palette for the extension, which does not link the app's theme.
private enum ShareSignal {
    static let bg = dynamic(0xF2F2EE, 0x0B0B0B)
    static let card = dynamic(0xFFFFFF, 0x161616)
    static let well = dynamic(0xE3E3DC, 0x222220)
    static let border = dynamic(0xDEDED8, 0x2A2A28)
    static let text = dynamic(0x121212, 0xF4F4F1)
    static let muted = dynamic(0x5E5E5A, 0x9A9A95)
    static let accent = Color(uiColor: UIColor(hex: 0x2F3BE8))
    static let warningBorder = dynamic(0xF1C9B4, 0x6B3A1F)
    static let warning = dynamic(0xE8590C, 0xFF8A4C)

    // MARK: Type (Geist + Geist Mono)

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Geist-SemiBold"
        case .medium: name = "Geist-Medium"
        default: name = "Geist-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static func mono(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom("GeistMono-Regular", size: size, relativeTo: style)
    }

    private static var didRegisterFonts = false

    /// Extensions do not inherit the app's `UIAppFonts`. Registers Geist from
    /// this extension's bundle when present, otherwise from the containing
    /// app bundle (the .appex sits in Vox.md.app/PlugIns). If neither has the
    /// fonts, `Font.custom` falls back to the system face.
    static func registerFonts() {
        guard !didRegisterFonts else { return }
        didRegisterFonts = true
        let ownBundle = Bundle.main.bundleURL
        let appBundle = ownBundle.deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "GeistMono-Regular", "GeistMono-Medium"] {
            let file = "\(name).ttf"
            let candidates = [
                ownBundle.appendingPathComponent(file),
                ownBundle.appendingPathComponent("Fonts/\(file)"),
                appBundle.appendingPathComponent(file),
                appBundle.appendingPathComponent("Fonts/\(file)"),
            ]
            guard let url = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private struct ShareCaptureView: View {
    @Bindable var model: ShareCaptureModel

    private let routeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.isLoading {
                        HStack { Spacer(); ProgressView("Loading shared items…"); Spacer() }
                            .padding(.vertical, 40)
                    } else {
                        if let summary = model.sharedItemSummary {
                            previewCard(summary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Add a note")
                            TextEditor(text: $model.note)
                                .font(ShareSignal.sans(16))
                                .foregroundStyle(ShareSignal.text)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 110)
                                .padding(8)
                                .background(ShareSignal.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(ShareSignal.border, lineWidth: 1)
                                )
                                .overlay(alignment: .topLeading) {
                                    if model.note.isEmpty {
                                        Text("Why it matters…")
                                            .font(ShareSignal.sans(16))
                                            .foregroundStyle(ShareSignal.muted)
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 16)
                                            .allowsHitTesting(false)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .disabled(model.isQueuedForLater)
                                .accessibilityLabel("Optional capture note")
                                .accessibilityHint("Adds text before the shared content")
                        }

                        if !model.presets.isEmpty {
                            routePicker
                        }

                        if let line = model.destinationLine {
                            Text(verbatim: line)
                                .font(ShareSignal.mono(11.5))
                                .foregroundStyle(ShareSignal.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(Text("Destination: \(line)"))
                                .accessibilityIdentifier("share.destinationLine")
                        }

                        if let error = model.errorMessage {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(ShareSignal.warning)
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 5)
                                    .accessibilityHidden(true)
                                Text(error)
                                    .font(ShareSignal.sans(15, relativeTo: .subheadline))
                                    .foregroundStyle(ShareSignal.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ShareSignal.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(ShareSignal.warningBorder, lineWidth: 1)
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text("Error: \(error)"))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(ShareSignal.bg.ignoresSafeArea())
            .confirmationDialog(
                "Location",
                isPresented: Binding(
                    get: { model.locationDecision != nil },
                    set: { if !$0 { model.cancelUnavailableLocation() } }
                ),
                titleVisibility: .visible
            ) {
                Button("Retry") { Task { await model.retryUnavailableLocation() } }
                Button("Send Without Location") {
                    Task { await model.sendWithoutUnavailableLocation(alwaysForPreset: false) }
                }
                Button("Always Send Without Location for This Route") {
                    Task { await model.sendWithoutUnavailableLocation(alwaysForPreset: true) }
                }
                Button("Cancel", role: .cancel) { model.cancelUnavailableLocation() }
            } message: {
                Text("The shared items are preserved while you decide.")
            }
            .navigationTitle("Send to Vox.md")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ShareSignal.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.isQueuedForLater ? String(localized: "Done") : String(localized: "Cancel")) {
                        model.cancel()
                    }
                    .tint(ShareSignal.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSubmitting
                           ? String(localized: "Sending…")
                           : (model.isQueuedForLater ? String(localized: "Open Vox.md") : String(localized: "Send"))) {
                        Task { await model.submit() }
                    }
                    .font(ShareSignal.sans(15, .semibold))
                    // Filled accent pill, as on the Share sheet board.
                    .buttonStyle(.borderedProminent)
                    .tint(ShareSignal.accent)
                    .disabled(model.isLoading || model.isSubmitting || model.selectedDestinationID == nil)
                }
            }
            .task { await model.load() }
            .onChange(of: model.errorMessage) { _, message in
                guard let message else { return }
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    private func fieldLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(ShareSignal.sans(13, .medium, relativeTo: .footnote))
            .foregroundStyle(ShareSignal.muted)
    }

    private func previewCard(_ summary: (title: String, detail: String, symbol: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = model.pageThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: summary.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(ShareSignal.muted)
                }
            }
            .frame(width: 56, height: 56)
            .background(ShareSignal.well)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(ShareSignal.sans(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(ShareSignal.text)
                    .lineLimit(2)
                Text(summary.detail)
                    .font(ShareSignal.mono(11.5))
                    .foregroundStyle(ShareSignal.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
            if let pageSummary = model.pageSummary {
                Text(pageSummary)
                    .font(ShareSignal.sans(13, relativeTo: .footnote))
                    .foregroundStyle(ShareSignal.muted)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("Page summary: \(pageSummary)"))
            }
        }
        .padding(12)
        .background(ShareSignal.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ShareSignal.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var routePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Route")
            LazyVGrid(columns: routeColumns, spacing: 8) {
                ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
                    routeOption(preset, tone: ShareRouteTileTone.forRoute(at: index))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Route")
        }
        .disabled(model.isQueuedForLater)
        .onChange(of: model.selectedPresetID) { _, _ in
            model.applySelectedPresetDestination()
        }
    }

    /// `presets` are the enabled routes in the user's order (App Group
    /// `recordingFlows`), so the tile tone matches the app's route tiles.
    private func routeOption(_ preset: CapturePresetProfile, tone: ShareRouteTileTone) -> some View {
        let isSelected = model.selectedPresetID == preset.id
        return Button {
            model.selectedPresetID = preset.id
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let letter = preset.visibleName?.first {
                        Text(String(letter).uppercased())
                            .font(ShareSignal.sans(12, .bold, relativeTo: .caption))
                    } else if let emoji = CapturePresetEmoji.normalized(preset.emoji) {
                        Text(verbatim: emoji)
                            .font(.system(size: 12))
                    } else {
                        Image(systemName: preset.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(tone.letter)
                .frame(width: 26, height: 26)
                .background(tone.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
                Text(preset.visibleName ?? String(localized: "Icon-only route"))
                    .font(ShareSignal.sans(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(ShareSignal.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(ShareSignal.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? ShareSignal.accent : ShareSignal.border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.accessibilityName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Best-effort page preview for a shared link. Network access goes only to
/// the shared page's own host; summarizing runs on device.
private enum SharePagePreview {
    static func thumbnail(for url: URL) async -> UIImage? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let metadata = try? await provider.startFetchingMetadata(for: url),
              let imageProvider = metadata.imageProvider ?? metadata.iconProvider else { return nil }
        return await withCheckedContinuation { continuation in
            imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    /// One or two sentences: Foundation Models when available, otherwise the
    /// page's meta description or first paragraph.
    static func summary(for url: URL) async -> String? {
        guard let page = await fetchText(url) else { return nil }
        let fallback = page.description ?? page.firstParagraph
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable, !page.body.isEmpty {
            let excerpt = String(page.body.prefix(4_000))
            do {
                let session = LanguageModelSession(
                    instructions: "Summarize the web page text in one or two plain sentences. Do not add facts that are not in the text."
                )
                let response = try await session.respond(to: excerpt)
                let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !summary.isEmpty { return String(summary.prefix(400)) }
            } catch {}
        }
        #endif
        return fallback.map { String($0.prefix(400)) }
    }

    private struct PageText {
        var description: String?
        var firstParagraph: String?
        var body: String
    }

    private static func fetchText(_ url: URL) async -> PageText? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let html = String(data: data.prefix(1_500_000), encoding: .utf8)
                ?? String(data: data.prefix(1_500_000), encoding: .isoLatin1) else { return nil }
        let description = metaContent(html, names: ["og:description", "description", "twitter:description"])
        let paragraphs = matches(html, pattern: "<p[^>]*>(.*?)</p>")
            .map(plainText)
            .filter { $0.count > 60 }
        return PageText(
            description: description.map(plainText).flatMap { $0.isEmpty ? nil : $0 },
            firstParagraph: paragraphs.first,
            body: paragraphs.prefix(20).joined(separator: "\n")
        )
    }

    private static func metaContent(_ html: String, names: [String]) -> String? {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                "<meta[^>]+(?:name|property)=[\"']\(escaped)[\"'][^>]*content=[\"']([^\"']*)[\"']",
                "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]*(?:name|property)=[\"']\(escaped)[\"']",
            ]
            for pattern in patterns {
                if let value = matches(html, pattern: pattern).first, !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func matches(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#x27;": "'"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ShareCaptureError: Error, LocalizedError {
    case destinationRequired
    case emptyShare
    case missingSharedFile

    var errorDescription: String? {
        switch self {
        case .destinationRequired: return String(localized: "Configure a destination for a Route in Vox.md first.")
        case .emptyShare: return String(localized: "There is no supported content to capture.")
        case .missingSharedFile: return String(localized: "The shared file disappeared before Vox.md could copy it.")
        }
    }
}
