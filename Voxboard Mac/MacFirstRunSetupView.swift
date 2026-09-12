import AppKit
import AVFoundation
import SwiftUI
import VoxboardShared

/// Compact, Mac-native setup shown once before the main capture workspace.
///
/// The view owns the setup interaction and persistence. Its callbacks let the
/// presenting root update sheet state without coupling this screen to app
/// navigation.
struct MacFirstRunSetupView: View {
    static let didFinishStorageKey = "macFirstRunSetupDidFinish"
    static let didSkipStorageKey = "macFirstRunSetupDidSkip"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Environment(ModelManager.self) private var modelManager

    @Bindable private var viewModel: QuickCaptureViewModel
    private let onComplete: () -> Void
    private let onSkip: () -> Void

    @AppStorage(Self.didFinishStorageKey, store: AppConstants.sharedDefaults)
    private var didFinishSetup = false
    @AppStorage(Self.didSkipStorageKey, store: AppConstants.sharedDefaults)
    private var didSkipSetup = false
    @AppStorage(MacHotKeyStore.storageKey, store: AppConstants.sharedDefaults)
    private var storedQuickCaptureShortcut = ""

    @State private var notesFolderBookmark = Data()
    @State private var notesFolderName = ""
    @State private var notesFolderPath = ""
    @State private var microphoneAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var isRequestingMicrophone = false
    @State private var isPreparing = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        viewModel: QuickCaptureViewModel,
        onComplete: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onComplete = onComplete
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 44)
                .padding(.top, 34)
                .padding(.bottom, 28)

            Divider()

            VStack(spacing: 0) {
                notesFolderRow
                Divider().padding(.leading, 54)
                transcriptionRow
                Divider().padding(.leading, 54)
                microphoneRow
                Divider().padding(.leading, 54)
                quickCaptureRow
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 10)

            Divider()

            footer
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
        }
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .tint(MacBrand.orange)
        .task {
            await prepare()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMicrophoneAuthorization()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            MacAppIconView(size: 76)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Welcome to Vox.md")
                    .font(.system(size: 28, weight: .semibold))
                Text("Capture thoughts without breaking your flow.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
    }

    private var notesFolderRow: some View {
        setupRow(
            symbol: "folder.fill",
            symbolColor: MacBrand.orangeText,
            title: String(localized: "Notes Folder"),
            detail: notesFolderPath.isEmpty
                ? String(localized: "Choose where Vox.md should write Markdown")
                : notesFolderPath
        ) {
            Button(notesFolderBookmark.isEmpty ? "Choose…" : "Change…") {
                chooseNotesFolder()
            }
            .disabled(isPreparing || isSaving)
            .accessibilityIdentifier("mac_first_run_choose_folder")
        }
    }

    private var transcriptionRow: some View {
        setupRow(
            symbol: "waveform.badge.magnifyingglass",
            symbolColor: MacBrand.orangeText,
            title: String(localized: "Transcription Model"),
            detail: transcriptionModelDetail
        ) {
            transcriptionModelMenu
        }
    }

    private var microphoneRow: some View {
        setupRow(
            symbol: microphoneAuthorization == .authorized ? "mic.fill" : "mic",
            symbolColor: microphoneAuthorization == .authorized
                ? MacBrand.complete
                : MacBrand.muted,
            title: String(localized: "Microphone"),
            detail: microphoneDetail
        ) {
            switch microphoneAuthorization {
            case .authorized:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(MacBrand.complete)
            case .notDetermined:
                Button(isRequestingMicrophone ? "Requesting…" : "Allow…") {
                    Task { await requestMicrophoneAccess() }
                }
                .disabled(isRequestingMicrophone || isSaving)
                .accessibilityIdentifier("mac_first_run_allow_microphone")
            case .denied, .restricted:
                Button("Open Settings…") {
                    openMicrophoneSettings()
                }
            @unknown default:
                EmptyView()
            }
        }
    }

    private var quickCaptureRow: some View {
        setupRow(
            symbol: "keyboard",
            symbolColor: .secondary,
            title: String(localized: "Quick Capture"),
            detail: quickCaptureShortcut == nil
                ? String(localized: "Set a global shortcut for the selected preset")
                : String(localized: "Starts or stops the selected preset from anywhere")
        ) {
            Button(quickCaptureShortcut?.displayString ?? String(localized: "Configure…")) {
                openSettingsPane(.shortcuts)
            }
            .accessibilityIdentifier("mac_first_run_quick_capture")
        }
    }

    private var transcriptionModelMenu: some View {
        Menu {
            if !modelManager.downloadedModels.isEmpty {
                Section("Ready on This Mac") {
                    ForEach(modelManager.downloadedModels) { model in
                        Button {
                            modelManager.selectModel(model)
                        } label: {
                            Label(
                                "\(model.name) · \(model.sizeLabel)",
                                systemImage: modelManager.selectedModelId == model.id
                                    ? "checkmark" : "waveform"
                            )
                        }
                    }
                }
            }

            let downloadableModels = WhisperModelInfo.availableModels.filter {
                !modelManager.isModelDownloaded($0)
            }
            if !downloadableModels.isEmpty {
                Section("Download a Model") {
                    ForEach(downloadableModels) { model in
                        Button {
                            modelManager.selectModel(model)
                            modelManager.startDownload(model)
                        } label: {
                            Label(
                                downloadableModelLabel(model),
                                systemImage: model.id == "parakeet-v3"
                                    ? "sparkles" : "arrow.down.circle"
                            )
                        }
                        .disabled(modelManager.downloadState(for: model.id) != nil)
                    }
                }
            }

            if let model = modelManager.selectedModel,
               modelManager.downloadState(for: model.id) != nil {
                Divider()
                Button("Cancel \(model.name) Download", role: .destructive) {
                    modelManager.cancelDownload(model)
                }
            }

            Divider()
            Button("Manage Models…", systemImage: "gearshape") {
                openSettingsPane(.transcription)
            }
        } label: {
            HStack(spacing: 6) {
                if let model = modelManager.selectedModel,
                   modelManager.downloadState(for: model.id) != nil {
                    ProgressView()
                        .controlSize(.small)
                } else if let model = modelManager.selectedModel,
                          modelManager.isModelDownloaded(model) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MacBrand.complete)
                }
                Text(transcriptionActionTitle)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("mac_first_run_transcription_model")
    }

    @ViewBuilder
    private func setupRow<Trailing: View>(
        symbol: String,
        symbolColor: Color,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(symbolColor)
                .frame(width: 40, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)
            trailing()
        }
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let setupErrorMessage {
                Label(setupErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(MacBrand.orangeText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mac_first_run_error")
            }

            HStack(spacing: 8) {
                Label("Transcription and processing stay on this Mac.", systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Not Now", role: .cancel) {
                    skip()
                }
                .keyboardShortcut(.cancelAction)

                Button("Customize…") {
                    openSettingsPane(.general)
                }

                Button(isSaving ? "Finishing…" : "Finish Setup") {
                    Task { await finish() }
                }
                .keyboardShortcut(.defaultAction)
                .tint(MacBrand.orange)
                .foregroundStyle(MacBrand.onOrange)
                .disabled(!canFinishSetup)
                .accessibilityIdentifier("mac_first_run_finish")
            }
        }
        .tint(MacBrand.orange)
    }

    private var transcriptionModelDetail: String {
        guard let model = modelManager.selectedModel else {
            return String(localized: "No local model selected")
        }
        if let downloadState = modelManager.downloadState(for: model.id) {
            return downloadState.isCancelling
                ? String(localized: "\(model.name) · \(model.sizeLabel) · Cancelling download")
                : String(localized: "\(model.name) · \(model.sizeLabel) · Downloading in background")
        }
        if modelManager.isModelDownloaded(model) {
            return "\(model.name) · \(model.sizeLabel)"
        }
        return String(localized: "\(model.name) · \(model.sizeLabel) · Download required")
    }

    private var transcriptionActionTitle: String {
        guard let model = modelManager.selectedModel else {
            return String(localized: "Choose…")
        }
        if let downloadState = modelManager.downloadState(for: model.id) {
            return downloadState.isCancelling
                ? String(localized: "Cancelling…")
                : String(localized: "Downloading…")
        }
        return modelManager.isModelDownloaded(model)
            ? String(localized: "Ready")
            : String(localized: "Set Up…")
    }

    private var quickCaptureShortcut: MacHotKeyShortcut? {
        _ = storedQuickCaptureShortcut
        return MacHotKeyStore.load(for: .selectedPreset)
    }

    private var selectedModelIsReady: Bool {
        guard let model = modelManager.selectedModel else { return false }
        return modelManager.isModelDownloaded(model)
            && modelManager.downloadState(for: model.id) == nil
    }

    private var selectedModelIsInstalling: Bool {
        guard let model = modelManager.selectedModel,
              let downloadState = modelManager.downloadState(for: model.id) else { return false }
        return !downloadState.isCancelling
    }

    private var selectedModelAllowsSetupCompletion: Bool {
        selectedModelIsReady || selectedModelIsInstalling
    }

    private var canFinishSetup: Bool {
        !notesFolderBookmark.isEmpty
            && selectedModelAllowsSetupCompletion
            && !isPreparing
            && !isSaving
    }

    private var setupErrorMessage: String? {
        errorMessage ?? modelManager.modelOperationError
    }

    private func downloadableModelLabel(_ model: WhisperModelInfo) -> String {
        if model.id == "parakeet-v3" {
            return String(localized: "\(model.name) · \(model.sizeLabel) · Recommended")
        }
        return "\(model.name) · \(model.sizeLabel)"
    }

    private var microphoneDetail: String {
        switch microphoneAuthorization {
        case .authorized:
            return String(localized: "Available for voice capture")
        case .notDetermined:
            return String(localized: "Permission is requested only when you allow it")
        case .denied:
            return String(localized: "Access is off in Privacy & Security")
        case .restricted:
            return String(localized: "Access is restricted on this Mac")
        @unknown default:
            return String(localized: "Permission status unavailable")
        }
    }

    @MainActor
    private func prepare() async {
        await viewModel.load()
        if notesFolderBookmark.isEmpty,
           let destination = viewModel.selectedPresetDestination,
           let resolution = try? CaptureBookmarkResolver.resolve(destination.rootBookmark),
           !resolution.isStale {
            notesFolderBookmark = destination.rootBookmark
            notesFolderName = destination.rootName
            notesFolderPath = abbreviatedPath(resolution.url)
        }
        refreshMicrophoneAuthorization()
        isPreparing = false
    }

    @MainActor
    private func chooseNotesFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a Notes Folder")
        panel.message = String(localized: "Vox.md will create a daily Markdown journal inside this folder.")
        panel.prompt = String(localized: "Choose Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let folderURL = panel.url?.standardizedFileURL else { return }

        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { folderURL.stopAccessingSecurityScopedResource() }
        }

        do {
            notesFolderBookmark = try folderURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            notesFolderName = folderURL.lastPathComponent
            notesFolderPath = abbreviatedPath(folderURL)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Vox.md could not remember that folder: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func requestMicrophoneAccess() async {
        guard microphoneAuthorization == .notDetermined else {
            refreshMicrophoneAuthorization()
            return
        }
        isRequestingMicrophone = true
        _ = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        refreshMicrophoneAuthorization()
        isRequestingMicrophone = false
    }

    @MainActor
    private func finish() async {
        guard !notesFolderBookmark.isEmpty else {
            errorMessage = String(localized: "Choose a notes folder to finish setup.")
            return
        }
        guard selectedModelAllowsSetupCompletion else {
            errorMessage = String(localized: "Choose a ready transcription model or start a model download to finish setup.")
            return
        }

        isSaving = true
        errorMessage = nil

        if microphoneAuthorization == .notDetermined {
            await requestMicrophoneAccess()
        }

        guard let preset = viewModel.selectedVoxProfile else {
            isSaving = false
            errorMessage = String(localized: "No enabled Capture Preset is available.")
            return
        }

        let destination = CaptureDestination(
            id: viewModel.selectedPresetDestination?.id ?? UUID(),
            name: preset.accessibilityName,
            rootBookmark: notesFolderBookmark,
            rootName: notesFolderName,
            noteTarget: .rollingNote(
                pathTemplate: "Journal/{period}.md",
                period: .daily
            ),
            placement: .append,
            attachmentsFolderName: "attachments"
        )

        do {
            try await viewModel.saveSelectedPresetDestination(destination)
            didSkipSetup = false
            didFinishSetup = true
            onComplete()
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func skip() {
        didSkipSetup = true
        didFinishSetup = true
        onSkip()
        dismiss()
    }

    @MainActor
    private func refreshMicrophoneAuthorization() {
        microphoneAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    @MainActor
    private func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func openSettingsPane(_ destination: MacSettingsDestination) {
        AppConstants.sharedDefaults?.set(
            destination.rawValue,
            forKey: MacSettingsDestination.storageKey
        )
        openSettings()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .macSelectSettingsPane,
                object: destination.rawValue
            )
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == homePath || path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }
}
