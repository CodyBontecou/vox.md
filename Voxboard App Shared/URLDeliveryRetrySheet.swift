import SwiftUI
import VoxboardShared

struct URLDeliveryRetrySheet: View {
    let receipt: URLDeliveryReceipt
    let coordinator: URLDeliveryCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPresetID = ""
    @State private var presets: [CapturePreset] = []

    private var shortID: String {
        UUID(uuidString: receipt.id).map { String($0.uuidString.lowercased().prefix(8)) } ?? String(localized: "Unknown")
    }

    private var matchingPresets: [CapturePreset] {
        presets.filter {
            !$0.exportSettings.urlDelivery.requiresCredentialMigration
                && receipt.matchesDestination($0.exportSettings.urlDelivery)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Saved Capture") {
                    Text(receipt.origin ?? String(localized: "Saved Endpoint")).textSelection(.enabled)
                    Text("\(receipt.date.formatted(date: .abbreviated, time: .shortened)) · \(shortID)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Authorization") {
                    Picker("Use Credentials", selection: $selectedPresetID) {
                        Text("Saved Delivery Credentials").tag("")
                        ForEach(matchingPresets) { preset in Text(preset.accessibilityName).tag(preset.id) }
                    }
                    Text("Choose a preset to deliberately use its current credentials, including a newly saved token. Only presets with the exact original endpoint are offered.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("To correct credentials, cancel and edit them in Capture Presets first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if URLComponents(string: receipt.urlString)?.scheme == "http" {
                        Text("This saved endpoint uses unencrypted HTTP. Your capture and credentials will be sent without encryption.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("The endpoint may already have received this capture. Retry keeps the original content, endpoint, and Idempotency-Key. The receiver must deduplicate that key to avoid duplicates.")
                    Text("This does not write another note or audio attachment.")
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        guard let id = UUID(uuidString: receipt.id) else { return }
                        let authorization = matchingPresets.first { $0.id == selectedPresetID }?.exportSettings.urlDelivery
                        Task { await coordinator.retry(id: id, authorization: authorization) }
                        dismiss()
                    }
                    .disabled(UUID(uuidString: receipt.id) == nil
                        || (!selectedPresetID.isEmpty && !matchingPresets.contains { $0.id == selectedPresetID }))
                    .accessibilityIdentifier("url_delivery_confirm_retry")
                }
            }
            .navigationTitle("Retry URL Delivery")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { presets = CapturePresetStore.loadFlows() }
        }
    }
}
