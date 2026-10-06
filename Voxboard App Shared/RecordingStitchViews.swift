import SwiftUI
import VoxboardShared

struct RecordingStitchSelection: Identifiable {
    let id = UUID()
    var recordingIDs: [UUID] = []
}

/// Native, explicit selection; proximity suggestions only preselect a review.
struct RecordingStitchSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var queue: RecordingJobQueue
    @State private var selectedIDs: Set<UUID>
    @State private var showAllRecordings: Bool
    @State private var stitchingTask: Task<Void, Never>?
    @State private var errorMessage: String?
    let onStitched: (RecordingJob) -> Void

    init(queue: RecordingJobQueue, selection: RecordingStitchSelection, onStitched: @escaping (RecordingJob) -> Void = { _ in }) {
        self.queue = queue
        self.onStitched = onStitched
        _selectedIDs = State(initialValue: Set(selection.recordingIDs))
        _showAllRecordings = State(initialValue: selection.recordingIDs.isEmpty)
    }

    private var recordings: [RecordingJob] {
        queue.stitchableJobs.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Combine clips in recorded order. Your originals stay available, including after Undo Stitch.")
                    if queue.isStitching {
                        ProgressView("Stitching audio…")
                            .accessibilityIdentifier("stitch-progress")
                    } else {
                        Text(selectedIDs.count == 1 ? String(localized: "1 clip selected")
                             : String(localized: "\(selectedIDs.count) clips selected"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Times are only a hint that clips belong together. Gaps are not added and overlaps are not trimmed. Nothing is transcribed or sent until you choose a preset later.")
                }

                Section("Clips — Oldest First") {
                    ForEach(recordings.filter { showAllRecordings || selectedIDs.contains($0.id) }) { job in
                        clipButton(job)
                    }
                    if !showAllRecordings {
                        Button("Select Other Recordings") { showAllRecordings = true }
                            .disabled(queue.isStitching)
                    }
                    if recordings.isEmpty {
                        Text("No saved, idle recordings are available to stitch.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Stitch Recordings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        if queue.isStitching { stitchingTask?.cancel() }
                        else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stitch") { stitch() }
                        .disabled(selectedIDs.count < 2 || queue.isProcessing || queue.isCaptureActive || queue.isStitching)
                        .accessibilityIdentifier("confirm-recording-stitch")
                        .accessibilityHint("Make a separate recording from selected clips, oldest first")
                }
            }
            .interactiveDismissDisabled(queue.isStitching)
            .onChange(of: recordings.map(\.id)) { _, ids in
                if !queue.isStitching { selectedIDs.formIntersection(ids) }
            }
            .onDisappear { stitchingTask?.cancel() }
            .alert("Could Not Stitch", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 420, idealHeight: 580)
        #endif
    }

    private func clipButton(_ job: RecordingJob) -> some View {
        let selected = selectedIDs.contains(job.id)
        let name: String
        if case .preset(let preset) = job.delivery { name = preset.accessibilityName }
        else { name = String(localized: "Saved Recording") }
        return Button {
            if selected { selectedIDs.remove(job.id) }
            else { selectedIDs.insert(job.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(name) · \(duration(job.duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(queue.isStitching)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("stitch-clip-\(job.id.uuidString.lowercased())")
    }

    private func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func stitch() {
        let ids = recordings.filter { selectedIDs.contains($0.id) }.map(\.id)
        stitchingTask = Task {
            do {
                let job = try await queue.stitchRecordings(ids)
                onStitched(job)
                dismiss()
            } catch is CancellationError {
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
