import SwiftUI
import VoxboardShared

/// Download and select the on-device speech recognition model.
struct ModelTabView: View {
    @Environment(ModelManager.self) private var modelManager
    @State private var automaticAvailability: SystemTranscriptionAvailability = .unavailable
    @State private var storageSummary: String?
    @State private var voiceAutoStopEnabled = AppConstants.voiceAutoStopEnabled
    @State private var isVoiceAutoStopAdvancedOptionsExpanded = false
    @State private var voiceAutoStopPauseDuration = AppConstants.voiceAutoStopPauseDuration
    @State private var enabledVoiceAutoStopCapturePaths = Set(
        VoiceAutoStopCapturePath.allCases.filter {
            AppConstants.voiceAutoStopCapturePathEnabled($0)
        }
    )
    /// Continuous dictation is stored per capture path; the picker applies one
    /// choice to every path (keyboard delivery is request-scoped, so its stored
    /// value is ignored by policy — it always ends its recording).
    @State private var voiceAutoStopSavesSegmentsAndContinues =
        VoiceAutoStopCapturePath.allCases.allSatisfy {
            AppConstants.voiceAutoStopContinuousModeEnabled(for: $0)
        }

    private var whisperModels: [WhisperModelInfo] {
        WhisperModelInfo.availableModels.filter { !$0.engine.isParakeet }
    }

    private var parakeetModels: [WhisperModelInfo] {
        WhisperModelInfo.availableModels.filter { $0.engine.isParakeet }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SettingsSignalPageHeader(
                    title: "Models",
                    subtitle: "Everything runs on this iPhone. Routes can override the model.",
                    backLabel: "Back"
                )
                .accessibilityElement(children: .contain)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                automaticSection
                modelSection(title: "Parakeet · Fast, English-first", models: parakeetModels)
                modelSection(title: "Whisper · Most languages", models: whisperModels)
                if let storageSummary {
                    // Board footer: "Using 1.2 GB of 64 GB free".
                    Text(storageSummary)
                        .font(Geist.mono(size: 11.5, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                        .accessibilityIdentifier("models.storage")
                }
                voiceAutoStopSection
                    .padding(.top, 14)
                languageSection
                    .padding(.top, 14)
            }
            .padding(.horizontal, Geist.Spacing.four)
            .padding(.top, Geist.Spacing.two)
            .padding(.bottom, Geist.Spacing.six)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Geist.bg.ignoresSafeArea())
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        // The Models board has no bar: the header carries the circular Back.
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(modelManager.selectedModelId)|\(modelManager.selectedLanguage)|\(modelManager.installedModelsRevision)") {
            let service = AppTranscriptionServices.shared
            automaticAvailability = await service.availability(
                modelID: TranscriptionBackendID.automatic,
                language: modelManager.selectedLanguage
            )
            if modelManager.isAutomaticSelection, automaticAvailability == .supported {
                try? await service.prepare(
                    modelID: TranscriptionBackendID.automatic,
                    fallbackModelID: modelManager.preferredFallbackModelID,
                    language: modelManager.selectedLanguage
                )
                automaticAvailability = await service.availability(
                    modelID: TranscriptionBackendID.automatic,
                    language: modelManager.selectedLanguage
                )
            }
            if modelManager.isAutomaticSelection {
                let ready = await service.canTranscribe(
                    modelID: TranscriptionBackendID.automatic,
                    fallbackModelID: modelManager.preferredFallbackModelID,
                    language: modelManager.selectedLanguage
                )
                AppConstants.sharedDefaults?.set(ready, forKey: AppConstants.automaticBackendReadyKey)
            }
        }
        .task(id: modelManager.installedModelsRevision) {
            storageSummary = await Self.storageSummary()
        }
        .onChange(of: voiceAutoStopEnabled) { _, enabled in
            AppConstants.voiceAutoStopEnabled = enabled
        }
        .onChange(of: voiceAutoStopPauseDuration) { _, duration in
            AppConstants.voiceAutoStopPauseDuration = duration
        }
        .onChange(of: enabledVoiceAutoStopCapturePaths) { _, enabledPaths in
            for path in VoiceAutoStopCapturePath.allCases {
                AppConstants.setVoiceAutoStopCapturePathEnabled(
                    enabledPaths.contains(path),
                    for: path
                )
            }
        }
        .onChange(of: voiceAutoStopSavesSegmentsAndContinues) { _, savesAndContinues in
            for path in VoiceAutoStopCapturePath.allCases {
                AppConstants.setVoiceAutoStopContinuousModeEnabled(
                    savesAndContinues,
                    for: path
                )
            }
        }
        .alert(
            "Model Operation Failed",
            isPresented: Binding(
                get: { modelManager.modelOperationError != nil },
                set: { if !$0 { modelManager.modelOperationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                modelManager.modelOperationError = nil
            }
        } message: {
            Text(modelManager.modelOperationError
                 ?? String(localized: "The model operation could not be completed."))
        }
    }

    /// Models board: the selectable "Automatic · RECOMMENDED" card with a
    /// leading radio. Tapping it selects Automatic.
    private var automaticSection: some View {
        let selected = modelManager.isAutomaticSelection
        return Button {
            if !selected { modelManager.selectAutomatic() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .strokeBorder(selected ? Geist.accent : Geist.Palette.gray600, lineWidth: selected ? 6 : 1.5)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Automatic")
                            .font(.custom("Geist-SemiBold", size: 17, relativeTo: .body))
                            .foregroundStyle(Geist.text)
                        SignalBadge(text: "Recommended")
                    }
                    Text(automaticFallbackDescription)
                        .font(Geist.body(.callout))
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("models.automatic.fallback")
                    if automaticAvailability != .ready {
                        // Only worth a line when Apple Speech is not ready.
                        Label(automaticAvailabilityLabel, systemImage: automaticAvailabilityIcon)
                            .font(Geist.caption())
                            .foregroundStyle(automaticAvailability == .unavailable ? Geist.Palette.amber900 : Geist.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .strokeBorder(selected ? Geist.accent : Geist.border, lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("models.automatic")
    }

    private var fallbackModel: WhisperModelInfo? {
        guard let id = modelManager.preferredFallbackModelID else { return nil }
        return WhisperModelInfo.availableModels.first { $0.id == id && modelManager.isModelDownloaded($0) }
    }

    private var automaticFallbackDescription: String {
        if let fallbackModel {
            return String(localized: "Apple Speech for live text. Falls back to \(fallbackModel.name) when a language isn’t supported or you’re offline.")
        }
        return String(localized: "Apple Speech for live text. Download a local model below to use as its fallback.")
    }

    /// "Using 1.2 GB of 64 GB free": installed model files vs. free space.
    nonisolated private static func storageSummary() async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            var used: Int64 = 0
            for model in WhisperModelInfo.availableModels {
                guard let url = model.localURL else { continue }
                used += directorySize(url)
            }
            let home = URL(fileURLWithPath: NSHomeDirectory())
            guard let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage else { return nil }
            let style = ByteCountFormatStyle(style: .file)
            return String(localized: "Using \(used.formatted(style)) of \(free.formatted(style)) free")
        }.value
    }

    nonisolated private static func directorySize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: keys)
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let file = enumerator?.nextObject() as? URL {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private var automaticAvailabilityLabel: String {
        switch automaticAvailability {
        case .ready: return String(localized: "Apple Speech ready for this language")
        case .supported: return String(localized: "Apple Speech available; system asset may need preparation")
        case .unavailable: return String(localized: "Apple Speech unavailable; a downloaded fallback is required")
        }
    }

    private var automaticAvailabilityIcon: String {
        switch automaticAvailability {
        case .ready: return "checkmark.circle.fill"
        case .supported: return "arrow.down.circle"
        case .unavailable: return "exclamationmark.triangle"
        }
    }

    private func modelSection(
        title: LocalizedStringKey,
        models: [WhisperModelInfo]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .modelsSectionTitle()
                .padding(.horizontal, 4)
                .padding(.top, 10)

            VStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    if index > 0 { GeistDivider() }
                    modelRow(for: model)
                }
            }
            .padding(.horizontal, 14)
            .background(Geist.card)
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
        }
    }

    /// Models board row: name, mono meta line (with a thin progress bar
    /// while downloading) and one trailing pill.
    private func modelRow(for model: WhisperModelInfo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Geist.Spacing.two) {
                    Text(model.name)
                        .font(Geist.label(.body))
                        .foregroundStyle(Geist.text)
                    if model.isBundled {
                        Text("Bundled")
                            .font(Geist.caption(.caption))
                            .foregroundStyle(Geist.muted)
                            .padding(.horizontal, Geist.Spacing.two)
                            .frame(height: 20)
                            .background(Geist.Palette.gray100)
                            .clipShape(Capsule())
                    }
                }

                Text(modelMetaLine(model))
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("models.meta.\(model.id)")

                if let state = modelManager.downloadState(for: model.id),
                   !modelManager.isModelDownloaded(model) {
                    downloadProgressView(state)
                        .padding(.top, 6)
                        .accessibilityLabel(Text("Downloading"))
                    Text("Keep Vox.md open")
                        .font(Geist.caption(.caption))
                        .foregroundStyle(Geist.faint)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            modelActionView(for: model)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 64)
    }

    private func isFallback(_ model: WhisperModelInfo) -> Bool {
        modelManager.isAutomaticSelection && fallbackModel?.id == model.id
    }

    /// "Not installed · 1.6 GB · best accuracy", "Downloading · 38%",
    /// "Installed · lowest battery use", "Installed · fallback for Automatic".
    private func modelMetaLine(_ model: WhisperModelInfo) -> String {
        guard modelManager.isModelDownloaded(model) else {
            if let state = modelManager.downloadState(for: model.id) {
                guard state.phase == .transferring else { return downloadStatusText(state) }
                if let progress = state.fractionCompleted {
                    let percent = progress.formatted(.percent.precision(.fractionLength(0)))
                    return String(localized: "Downloading · \(percent)")
                }
                return downloadStatusText(state)
            }
            if let trait = modelTrait(model) {
                return String(localized: "Not installed · \(model.sizeLabel) · \(trait)")
            }
            return String(localized: "Not installed · \(model.sizeLabel)")
        }
        if isFallback(model) {
            return String(localized: "Installed · fallback for Automatic")
        }
        if modelManager.selectedModelId == model.id {
            return String(localized: "Installed · in use")
        }
        return String(localized: "Installed · \(modelTrait(model) ?? model.sizeLabel)")
    }

    /// Short trade-off note per model for its meta line.
    private func modelTrait(_ model: WhisperModelInfo) -> String? {
        switch model.id {
        case "ggml-tiny": String(localized: "fastest")
        case "ggml-base": String(localized: "lowest battery use")
        case "ggml-small": String(localized: "balanced")
        case "ggml-medium": String(localized: "more accurate")
        case "ggml-large-v3-turbo": String(localized: "best accuracy")
        case "parakeet-v2": String(localized: "English only")
        case "parakeet-v3": String(localized: "25 languages")
        default: nil
        }
    }

    /// The board's pills: soft-indigo "Fallback", ghost "Use", solid "Get",
    /// ghost "Cancel". Installed models keep Delete in the pill's menu.
    @ViewBuilder
    private func modelActionView(for model: WhisperModelInfo) -> some View {
        if modelManager.isModelDownloaded(model) {
            if modelManager.selectedModelId == model.id {
                Menu {
                    deleteButton(for: model)
                } label: {
                    ModelPill(title: "Selected", kind: .fallback, systemImage: "checkmark")
                }
                .accessibilityLabel("\(model.name) is selected")
                .accessibilityIdentifier("models.selected.\(model.id)")
            } else if isFallback(model) {
                Menu {
                    Button("Use for All Captures") { modelManager.selectModel(model) }
                    deleteButton(for: model)
                } label: {
                    ModelPill(title: "Fallback", kind: .fallback)
                }
                .accessibilityLabel("\(model.name) is Automatic’s fallback")
                .accessibilityIdentifier("models.fallback.\(model.id)")
            } else {
                Menu {
                    Button("Use for All Captures") { modelManager.selectModel(model) }
                    Button("Make Automatic’s Fallback") {
                        if !modelManager.isAutomaticSelection { modelManager.selectAutomatic() }
                        modelManager.setFallbackModel(model)
                    }
                    deleteButton(for: model)
                } label: {
                    ModelPill(title: "Use", kind: .ghost)
                }
                .accessibilityLabel("Use \(model.name)")
                .accessibilityIdentifier("models.use.\(model.id)")
            }
        } else if let state = modelManager.downloadState(for: model.id) {
            downloadingView(for: model, state: state)
        } else {
            Button {
                modelManager.startDownload(model)
            } label: {
                ModelPill(title: "Get", kind: .solid)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Download \(model.name)"))
            .accessibilityIdentifier("models.get.\(model.id)")
        }
    }

    private func deleteButton(for model: WhisperModelInfo) -> some View {
        Button(role: .destructive) {
            modelManager.deleteModel(model)
        } label: {
            Label("Delete \(model.name) model", systemImage: "trash")
        }
    }

    private func downloadingView(
        for model: WhisperModelInfo,
        state: ModelDownloadState
    ) -> some View {
        // Progress and status sit in the row's meta line; the trailing
        // control is the board's ghost "Cancel" pill.
        Button {
            modelManager.cancelDownload(model)
        } label: {
            ModelPill(title: "Cancel", kind: .ghost)
        }
        .buttonStyle(.plain)
        .disabled(state.isCancelling)
        .opacity(state.isCancelling ? 0.5 : 1)
        .accessibilityLabel("Cancel \(model.name) download")
    }

    @ViewBuilder
    private func downloadProgressView(_ state: ModelDownloadState) -> some View {
        if let progress = state.fractionCompleted {
            // Board: a 4pt indigo bar on the well track.
            Capsule()
                .fill(Geist.well)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Geist.accent)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .clipShape(Capsule())
                .accessibilityElement()
                .accessibilityValue(Text(progress.formatted(.percent.precision(.fractionLength(0)))))
        } else {
            ProgressView()
                .controlSize(.small)
                .tint(Geist.Palette.blue700)
        }
    }

    private func downloadStatusText(_ state: ModelDownloadState) -> String {
        switch state.phase {
        case .preparing:
            return String(localized: "Preparing…")
        case .listingFiles:
            return String(localized: "Finding files…")
        case .verifying:
            return String(localized: "Verifying…")
        case .cancelling:
            return String(localized: "Cancelling…")
        case .transferring:
            if let fileProgressDescription = state.fileProgressDescription {
                return fileProgressDescription
            }
            if let progress = state.fractionCompleted {
                return progress.formatted(.percent.precision(.fractionLength(0)))
            }
            return String(localized: "Downloading…")
        }
    }

    private var voiceAutoStopSection: some View {
        let modelID = VoiceActivityModelAsset.id
        let isDownloaded = modelManager.isVoiceActivityModelDownloaded
        let downloadState = modelManager.downloadState(for: modelID)

        return VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            VStack(alignment: .leading, spacing: Geist.Spacing.one) {
                Text("Voice Auto-Stop")
                    .modelsSectionTitle()
                Text("A small on-device voice detector can stop any live recording on this iPhone or iPad after you finish speaking, regardless of the transcription model or capture destination.")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                HStack(spacing: Geist.Spacing.three) {
                    VStack(alignment: .leading, spacing: Geist.Spacing.one) {
                        Text("Voice Pause Detection")
                            .font(Geist.label(.body))
                            .foregroundStyle(Geist.text)
                        Text(isDownloaded
                             ? String(localized: "Installed · Runs on device")
                             : String(localized: "Optional companion model · About 1 MB"))
                            .font(Geist.mono())
                            .foregroundStyle(Geist.muted)
                    }
                    Spacer(minLength: Geist.Spacing.two)

                    if isDownloaded {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(Geist.caption())
                            .foregroundStyle(Geist.Palette.blue900)

                        Button {
                            modelManager.deleteVoiceActivityModel()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(GeistButtonStyle(variant: .tertiary, size: .small))
                        .frame(width: Geist.ControlHeight.small)
                        .accessibilityLabel("Delete voice pause detection model")
                    } else if let downloadState {
                        VStack(alignment: .trailing, spacing: Geist.Spacing.one) {
                            downloadProgressView(downloadState)
                                .frame(width: 88)
                            Text(downloadStatusText(downloadState))
                                .font(Geist.mono())
                                .foregroundStyle(Geist.muted)
                        }
                        Button {
                            modelManager.cancelVoiceActivityDownload()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(GeistButtonStyle(variant: .tertiary, size: .small))
                        .frame(width: Geist.ControlHeight.small)
                        .disabled(downloadState.isCancelling)
                        .accessibilityLabel("Cancel voice pause detection download")
                    } else {
                        Button("Download Auto-Stop") {
                            modelManager.startVoiceActivityDownload()
                        }
                        .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
                    }
                }

                GeistDivider()

                Toggle("Enable Voice Auto-Stop", isOn: $voiceAutoStopEnabled)
                    .font(Geist.body())
                    .foregroundStyle(Geist.text)
                    .disabled(!isDownloaded)

                DisclosureGroup(isExpanded: $isVoiceAutoStopAdvancedOptionsExpanded) {
                    VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                        GeistDivider()

                        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                            Text("Capture Paths")
                                .font(Geist.label(.body))
                                .foregroundStyle(Geist.text)

                            ForEach(VoiceAutoStopCapturePath.allCases, id: \.self) { path in
                                Toggle(isOn: voiceAutoStopCapturePathBinding(for: path)) {
                                    VStack(alignment: .leading, spacing: Geist.Spacing.one) {
                                        Text(voiceAutoStopCapturePathTitle(path))
                                            .font(Geist.body())
                                            .foregroundStyle(Geist.text)
                                        Text(voiceAutoStopCapturePathDescription(path))
                                            .font(Geist.caption())
                                            .foregroundStyle(Geist.muted)
                                    }
                                }
                                .tint(Geist.accent)
                                .padding(.trailing, Geist.Spacing.one)
                            }
                        }
                        .disabled(!isDownloaded || !voiceAutoStopEnabled)

                        voiceAutoStopPreferenceMenus
                            .disabled(!isDownloaded || !voiceAutoStopEnabled)

                        Text(isDownloaded
                            ? "Choose exactly where auto-stop runs. Every enabled path works with Automatic, Whisper, and Parakeet. Pause timing is approximate. Keep Listening saves each finished thought as its own segment and keeps recording until you stop it."
                            : "Until this companion is downloaded, live recordings keep using manual stop.")
                            .font(Geist.caption())
                            .foregroundStyle(Geist.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Geist.Spacing.two)
                } label: {
                    Text("Advanced Options")
                        .font(Geist.label(.body))
                        .foregroundStyle(Geist.text)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: Geist.ControlHeight.large,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                        .accessibilityHint("Show or hide capture path settings.")
                }
                .tint(Geist.text)
            }
            .padding(Geist.Spacing.four)
            .background(Geist.card)
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
        }
    }

    private var voiceAutoStopPreferenceMenus: some View {
        VStack(spacing: 0) {
            Menu {
                Picker("Pause Length", selection: $voiceAutoStopPauseDuration) {
                    Text("0.5 seconds").tag(0.5)
                    Text("0.75 seconds").tag(0.75)
                    Text("1 second").tag(1.0)
                    Text("1.5 seconds").tag(1.5)
                    Text("2 seconds").tag(2.0)
                }
            } label: {
                VoiceAutoStopMenuLabel(
                    title: "Pause Length",
                    value: voiceAutoStopPauseDurationLabel
                )
            }
            .accessibilityLabel("Pause Length")
            .accessibilityValue(voiceAutoStopPauseDurationLabel)
            .accessibilityHint("Choose how long silence lasts before auto-stop responds.")
            .accessibilityIdentifier("voiceAutoStop.pauseLength")

            GeistDivider()
                .padding(.leading, Geist.Spacing.three)

            Menu {
                Picker(
                    "On End of Speech",
                    selection: $voiceAutoStopSavesSegmentsAndContinues
                ) {
                    Text("Stop Recording").tag(false)
                    Text("Save Segment & Keep Listening").tag(true)
                }
            } label: {
                VoiceAutoStopMenuLabel(
                    title: "On End of Speech",
                    value: voiceAutoStopEndOfSpeechLabel
                )
            }
            .accessibilityLabel("On End of Speech")
            .accessibilityValue(voiceAutoStopEndOfSpeechLabel)
            .accessibilityHint("Choose whether auto-stop ends recording or saves a segment and keeps listening.")
            .accessibilityIdentifier("voiceAutoStop.endOfSpeech")
        }
        .background(Geist.Palette.grayAlpha100)
        .overlay(
            RoundedRectangle(cornerRadius: Geist.Radius.small, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.small, style: .continuous))
    }

    private var voiceAutoStopPauseDurationLabel: LocalizedStringKey {
        switch voiceAutoStopPauseDuration {
        case 0.5: return "0.5 seconds"
        case 0.75: return "0.75 seconds"
        case 1.5: return "1.5 seconds"
        case 2.0: return "2 seconds"
        default: return "1 second"
        }
    }

    private var voiceAutoStopEndOfSpeechLabel: LocalizedStringKey {
        voiceAutoStopSavesSegmentsAndContinues
            ? "Save Segment & Keep Listening"
            : "Stop Recording"
    }

    private func voiceAutoStopCapturePathBinding(
        for path: VoiceAutoStopCapturePath
    ) -> Binding<Bool> {
        Binding(
            get: { enabledVoiceAutoStopCapturePaths.contains(path) },
            set: { isEnabled in
                if isEnabled {
                    enabledVoiceAutoStopCapturePaths.insert(path)
                } else {
                    enabledVoiceAutoStopCapturePaths.remove(path)
                }
            }
        )
    }

    private func voiceAutoStopCapturePathTitle(
        _ path: VoiceAutoStopCapturePath
    ) -> LocalizedStringKey {
        switch path {
        case .keyboard:
            return "Keyboard"
        case .inAppDraft:
            return "In-App · Add to Draft"
        case .inAppImmediate:
            return "In-App · Send Immediately"
        case .quickRecord:
            return "Widgets & Quick Record"
        case .liveActivity:
            return "Live Activity"
        case .watch:
            return "Apple Watch"
        }
    }

    private func voiceAutoStopCapturePathDescription(
        _ path: VoiceAutoStopCapturePath
    ) -> LocalizedStringKey {
        switch path {
        case .keyboard:
            return "Voice input from the Vox.md keyboard"
        case .inAppDraft:
            return "Voice Capture with Add to Draft selected"
        case .inAppImmediate:
            return "Voice Capture with Send Immediately selected"
        case .quickRecord:
            return "Lock Screen widgets, controls, and Quick Record shortcuts"
        case .liveActivity:
            return "Recording started from the Live Activity"
        case .watch:
            return "iPhone recording started from Apple Watch"
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            Text("Transcription Language")
                .modelsSectionTitle()

            Group {
                if modelManager.selectedModel?.engine.isParakeet == true {
                    Text("Parakeet detects language automatically. Manual language hints are unavailable for this engine.")
                        .font(Geist.body())
                        .foregroundStyle(Geist.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .geistCard(padding: Geist.Spacing.four)
                } else {
                    VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                        Picker("Transcription Language", selection: Binding(
                            get: { modelManager.selectedLanguage },
                            set: { modelManager.selectedLanguage = $0 }
                        )) {
                            ForEach(modelManager.availableLanguages, id: \.code) { language in
                                Text(language.name).tag(language.code)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(Geist.body())
                        .tint(Geist.text)
                        .frame(maxWidth: .infinity, minHeight: Geist.ControlHeight.large, alignment: .leading)
                        .padding(.horizontal, Geist.Spacing.four)
                        .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous)
                                .stroke(Geist.border, lineWidth: 1)
                        )

                        if modelManager.isAutomaticSelection {
                            Text("System Language follows your device language. Choose a language explicitly when the recording uses another language.")
                                .font(Geist.caption())
                                .foregroundStyle(Geist.muted)
                        }
                    }
                }
            }
        }
    }
}

/// 36pt capsule action from the Models board.
private struct ModelPill: View {
    enum Kind { case ghost, fallback, solid }

    let title: LocalizedStringKey
    let kind: Kind
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(title)
        }
        .font(.custom("Geist-SemiBold", size: 13.5, relativeTo: .footnote))
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(background, in: Capsule())
        .overlay {
            if kind == .ghost { Capsule().strokeBorder(Geist.border, lineWidth: 1) }
        }
        .contentShape(Capsule())
        .lineLimit(1)
        .fixedSize()
    }

    private var foreground: Color {
        switch kind {
        case .ghost: Geist.text
        case .fallback: Geist.accentText
        case .solid: Geist.bg
        }
    }

    private var background: Color {
        switch kind {
        case .ghost: Geist.card
        case .fallback: Geist.accentSoft
        case .solid: Geist.text
        }
    }
}

private struct VoiceAutoStopMenuLabel: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.one) {
            Text(title)
                .font(Geist.caption())
                .foregroundStyle(isEnabled ? Geist.muted : Geist.faint)

            HStack(spacing: Geist.Spacing.two) {
                Text(value)
                    .font(Geist.label(.body))
                    .foregroundStyle(isEnabled ? Geist.text : Geist.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Geist.Spacing.two)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Geist.faint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Geist.Spacing.three)
        .padding(.vertical, Geist.Spacing.two)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private extension View {
    /// Signal section label: mono, uppercase, muted.
    func modelsSectionTitle() -> some View {
        self
            .textCase(.uppercase)
            .font(Geist.mono(size: 11, relativeTo: .caption))
            .tracking(0.66)
            .foregroundStyle(Geist.muted)
            .accessibilityAddTraits(.isHeader)
    }
}
