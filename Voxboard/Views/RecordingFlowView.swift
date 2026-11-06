import SwiftUI
import VoxboardShared

// MARK: - Controller (unchanged — only view layer is redesigned)

@Observable
final class CapturePresetController {
    enum Phase {
        case starting, recording, transcribing, done, error
    }

    var phase: Phase = .starting
    var transcriptionResult: String?
    var errorMessage: String?
    var transcriptionProgress: TranscriptionProgress?

    let modelId: String
    let language: String
    let requestId: String

    private let recorder = AudioRecorder()
    private var commandPollTimer: Timer?
    private let transcriptStore: TranscriptStore
    private let transcriptionService: OnDeviceTranscriptionService
    private var recordingStartedAt: TimeInterval = 0
    private var transcriptionStartedAt: TimeInterval?
    private var lastPublishedProgressPercent: Int?

    var recordingDuration: TimeInterval { recorder.recordingDuration }

    init(
        modelId: String,
        language: String,
        requestId: String,
        transcriptStore: TranscriptStore,
        transcriptionService: OnDeviceTranscriptionService = AppTranscriptionServices.shared
    ) {
        self.modelId = modelId
        self.language = language
        self.requestId = requestId
        self.transcriptStore = transcriptStore
        self.transcriptionService = transcriptionService
    }

    deinit { stopListeningForCommand() }

    func start() {
        let log = KeyboardDebugLog.shared
        log.log("[App:RecFlow] start() — model=\(modelId), requestId=\(requestId)")
        phase = .starting
        TranscriptionIPC.clearCommand()

        guard recorder.startRecording() else {
            phase = .error
            errorMessage = String(localized: "Could not access microphone")
            TranscriptionIPC.writeStatus(RecordingStatus(requestId: requestId, phase: .error, message: String(localized: "Mic unavailable")))
            return
        }

        recordingStartedAt = Date().timeIntervalSince1970
        phase = .recording
        TranscriptionIPC.writeStatus(RecordingStatus(requestId: requestId, phase: .recording, recordingStartedAt: recordingStartedAt))
        listenForStopCommand()
    }

    func stopAndTranscribe() {
        let log = KeyboardDebugLog.shared
        guard phase == .recording, recorder.isRecording else { return }
        stopListeningForCommand()

        guard let audioURL = recorder.stopRecording() else {
            phase = .error; errorMessage = String(localized: "No audio was captured")
            writeErrorResponse(String(localized: "No audio captured")); return
        }

        phase = .transcribing
        transcriptionProgress = nil
        lastPublishedProgressPercent = nil
        transcriptionStartedAt = Date().timeIntervalSince1970
        TranscriptionIPC.writeStatus(RecordingStatus(
            requestId: requestId,
            phase: .transcribing,
            recordingStartedAt: recordingStartedAt,
            recordingStoppedAt: transcriptionStartedAt
        ))
        let duration = recorder.recordingDuration

        let lang = language
        let reqId = requestId
        let selectedModelID = modelId
        let service = transcriptionService

        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid
        }

        Task.detached(priority: .userInitiated) {
            do {
                let result = try await service.transcribeResult(
                    audioURL: audioURL,
                    modelID: selectedModelID,
                    fallbackModelID: AppConstants.sharedDefaults?.string(forKey: AppConstants.selectedFallbackModelKey),
                    language: lang,
                    onProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  self.requestId == reqId,
                                  self.phase == .transcribing else { return }
                            if let current = self.transcriptionProgress?.exactFractionCompleted {
                                guard let incoming = progress.exactFractionCompleted,
                                      incoming >= current else { return }
                            }
                            self.transcriptionProgress = progress
                            guard let percent = progress.wholePercentCompleted,
                                  let fraction = progress.exactFractionCompleted,
                                  percent != self.lastPublishedProgressPercent else { return }
                            self.lastPublishedProgressPercent = percent
                            TranscriptionIPC.writeStatus(RecordingStatus(
                                requestId: reqId,
                                phase: .transcribing,
                                recordingStartedAt: self.recordingStartedAt,
                                recordingStoppedAt: self.transcriptionStartedAt,
                                transcriptionProgress: fraction
                            ))
                        }
                    }
                )
                log.log("[App:RecFlow] Transcription complete")

                let deliverySucceeded = try await MainActor.run { [weak self] in
                    guard let self else {
                        if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
                        return false
                    }
                    self.transcriptionProgress = nil
                    self.transcriptionResult = result.text
                    let response = TranscriptionResponse(requestId: reqId, text: result.text)
                    try TranscriptionIPC.writeResponse(response)
                    TranscriptionIPC.postResponseNotification()
                    self.transcriptStore.add(Transcript(
                        text: result.text,
                        duration: duration,
                        modelUsed: result.backendName,
                        language: result.language
                    ))
                    if let persistenceError = self.transcriptStore.lastPersistenceError {
                        throw persistenceError
                    }
                    TranscriptionIPC.writeStatus(RecordingStatus(requestId: reqId, phase: .done))
                    ReviewPromptManager.shared.recordSuccessfulTranscription(
                        totalTranscriptionCount: self.transcriptStore.transcripts.count,
                        transcriptDates: self.transcriptStore.transcripts.map(\.date)
                    )
                    self.phase = .done
                    if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
                    return true
                }
                if deliverySucceeded {
                    try? FileManager.default.removeItem(at: audioURL)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.transcriptionProgress = nil
                    self?.phase = .error
                    self?.errorMessage = error.localizedDescription
                    self?.writeErrorResponse(error.localizedDescription)
                    if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
                }
            }
        }
    }

    private func listenForStopCommand() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let ctrl = Unmanaged<CapturePresetController>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { ctrl.handleStopCommandIfNeeded() }
        }, TranscriptionIPC.stopCommandNotificationName, nil, .deliverImmediately)

        commandPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.handleStopCommandIfNeeded()
        }
    }

    private func stopListeningForCommand() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(
            center, Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(TranscriptionIPC.stopCommandNotificationName), nil
        )
        commandPollTimer?.invalidate(); commandPollTimer = nil
    }

    private func handleStopCommandIfNeeded() {
        guard phase == .recording,
              let command = TranscriptionIPC.readCommand(),
              command.requestId == requestId,
              command.action == .stop else { return }
        TranscriptionIPC.clearCommand()
        stopAndTranscribe()
    }

    private func writeErrorResponse(_ message: String) {
        let response = TranscriptionResponse(requestId: requestId, error: message)
        try? TranscriptionIPC.writeResponse(response)
        TranscriptionIPC.postResponseNotification()
        TranscriptionIPC.writeStatus(RecordingStatus(requestId: requestId, phase: .error, message: message))
    }
}

// MARK: - View (Signal live recording — dark surface, mono timer)

struct CapturePresetView: View {
    let controller: CapturePresetController
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Geist.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, Geist.Spacing.two)

                phaseContent
                    .padding(.top, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: Geist.Spacing.four)

                actionBar
            }
            .padding(.horizontal, 24)
        }
        // The live recording artboard is a dark surface in either theme.
        .environment(\.colorScheme, .dark)
        .onAppear { controller.start() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Geist.onAccent)
                    .frame(width: 22, height: 22)
                    .background(Geist.accent, in: Circle())
                Text("Keyboard")
                    .font(.custom("Geist-SemiBold", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Geist.text)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 32)
            .background(Geist.Palette.gray200, in: Capsule(style: .continuous))
            .accessibilityHidden(true)

            Spacer()

            Label("On device", systemImage: "lock")
                .font(Geist.mono(size: 11.5, relativeTo: .caption))
                .foregroundStyle(Geist.muted)
        }
    }

    // MARK: - Phase Content

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .starting:
            VStack(alignment: .leading, spacing: 20) {
                GeistSectionLabel(number: "01", title: "Status")
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Geist.text)
                    Text("Starting…")
                        .font(Geist.display(34))
                        .foregroundStyle(Geist.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                }
            }

        case .recording:
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle()
                        .fill(Geist.recording)
                        .frame(width: 10, height: 10)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                        .accessibilityHidden(true)
                    Text(formatDuration(controller.recordingDuration))
                        .font(.custom("GeistMono-Medium", size: 44, relativeTo: .largeTitle))
                        .tracking(-0.9)
                        .monospacedDigit()
                        .foregroundStyle(Geist.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Recording")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                }
                .accessibilityElement(children: .combine)

                // Swipe-back prompt
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("←")
                            .font(Geist.label(.headline))
                        Text("Return to Your App")
                            .font(.custom("Geist-SemiBold", size: 21, relativeTo: .title3))
                    }
                    .foregroundStyle(Geist.text)
                    Text("Recording continues. Tap Stop on the keyboard when done.")
                        .font(Geist.body())
                        .foregroundStyle(Geist.muted)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .geistCard(padding: Geist.Spacing.four)
            }

        case .transcribing:
            VStack(alignment: .leading, spacing: 20) {
                GeistSectionLabel(number: "01", title: "Status")
                if let progress = controller.transcriptionProgress,
                   let fraction = progress.exactFractionCompleted,
                   let percent = progress.formattedWholePercentCompleted {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transcribing \(percent)")
                            .font(Geist.display(34))
                            .foregroundStyle(Geist.text)
                            .minimumScaleFactor(0.4)
                        ProgressView(value: fraction)
                            .tint(Geist.accent)
                            .frame(maxWidth: 320)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Transcription \(percent) complete")
                } else {
                    TranscribingDotsView()
                }
                Text("Processing audio on-device")
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
            }

        case .done:
            VStack(alignment: .leading, spacing: 20) {
                GeistSectionLabel(number: "01", title: "Status")
                Text("Transcript Ready")
                    .font(Geist.display(34))
                    .foregroundStyle(Geist.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                if let result = controller.transcriptionResult {
                    Text(result)
                        .font(.custom("Geist-Medium", size: 21, relativeTo: .title3))
                        .foregroundStyle(Geist.text)
                        .lineSpacing(4)
                        .lineLimit(8)
                }
            }

        case .error:
            VStack(alignment: .leading, spacing: 20) {
                GeistSectionLabel(number: "01", title: "Status")
                Text("Transcription Error")
                    .font(Geist.display(34))
                    .foregroundStyle(Geist.recording)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                Text(controller.errorMessage ?? String(localized: "Something went wrong"))
                    .font(Geist.body())
                    .foregroundStyle(Geist.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .geistCard(padding: Geist.Spacing.four)
            }
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private var actionBar: some View {
        HStack {
            Spacer()
            switch controller.phase {
            case .recording:
                Button(action: { controller.stopAndTranscribe() }) {
                    ZStack {
                        Circle()
                            .strokeBorder(Geist.text, lineWidth: 3)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Geist.recording)
                            .frame(width: 34, height: 34)
                    }
                    .frame(width: 88, height: 88)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop and Transcribe")

            case .done, .error:
                Button(action: { onDismiss() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SignalCircleButtonStyle(diameter: 56, filled: Geist.Palette.gray200))
                .accessibilityLabel("Close")

            default:
                Color.clear
                    .frame(width: 88, height: 88)
            }
            Spacer()
        }
        .padding(.vertical, 16)
    }

    // MARK: - Helpers

    private func formatDuration(_ d: TimeInterval) -> String {
        let m = Int(d) / 60
        let s = Int(d) % 60
        let t = Int((d * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", m, s, t)
    }
}
