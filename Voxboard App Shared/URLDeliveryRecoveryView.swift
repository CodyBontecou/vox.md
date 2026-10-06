import SwiftUI
import VoxboardShared

/// HTTP-only recovery. Metadata is shown without the body, credentials, full
/// endpoint path/query, or legacy transport-error descriptions.
struct URLDeliveryRecoveryView: View {
    let coordinator: URLDeliveryCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var retryReceipt: URLDeliveryReceipt?
    @State private var discardReceipt: URLDeliveryReceipt?
    @State private var showDiscardConfirmation = false

    var body: some View {
        List {
            Section {
                Text("Retry sends the saved JSON only. It does not write another note or audio attachment.")
                Text("The original endpoint and content stay unchanged. Opening or refreshing this list never sends.")
                    .foregroundStyle(.secondary)
            }
            if coordinator.receipts.isEmpty {
                ContentUnavailableView("No Pending Deliveries", systemImage: "tray",
                    description: Text("Failed or deferred URL deliveries appear here."))
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("url_deliveries_empty")
            } else {
                Section("Needs Attention") {
                    ForEach(coordinator.receipts) { receipt in receiptRow(receipt) }
                }
            }
            if let error = coordinator.lastError {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("url_deliveries_error") }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle("URL Deliveries")
        .accessibilityIdentifier("url_deliveries_screen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await coordinator.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh URL Deliveries")
                    .accessibilityIdentifier("url_deliveries_refresh")
            }
        }
        .task { await coordinator.refresh() }
        .refreshable { await coordinator.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await coordinator.refresh() } }
        }
        .sheet(item: $retryReceipt) { receipt in
            URLDeliveryRetrySheet(receipt: receipt, coordinator: coordinator)
                #if os(iOS)
                .presentationDetents([.large])
                #else
                .frame(minWidth: 500, minHeight: 440)
                #endif
        }
        .confirmationDialog("Discard URL delivery?", isPresented: $showDiscardConfirmation,
                            titleVisibility: .visible, presenting: discardReceipt) { receipt in
            Button("Discard", role: .destructive) {
                if let id = UUID(uuidString: receipt.id) { Task { await coordinator.discard(id: id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Removes the saved HTTP payload from this device. Existing notes and anything already received by the endpoint are not changed. This cannot be undone.")
        }
    }

    private func receiptRow(_ receipt: URLDeliveryReceipt) -> some View {
        let id = UUID(uuidString: receipt.id)
        let active = id.map { coordinator.activeIDs.contains($0) } ?? false
        let shortID = id.map { String($0.uuidString.lowercased().prefix(8)) } ?? String(localized: "Unknown")
        return VStack(alignment: .leading, spacing: 8) {
            Text(origin(receipt)).font(.headline).textSelection(.enabled)
            Text("\(receipt.date.formatted(date: .abbreviated, time: .shortened)) · \(shortID)")
                .font(.caption).foregroundStyle(.secondary)
            if active {
                HStack { ProgressView(); Text("Sending…") }
            } else {
                Text(status(receipt)).font(.subheadline.weight(.medium))
                Text(explanation(receipt)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                if active {
                    Button { if let id { Task { await coordinator.cancel(id: id) } } } label: {
                        Text("Cancel Send").frame(minWidth: 44, minHeight: 44)
                    }
                        .accessibilityIdentifier("url_delivery_cancel_\(receipt.id)")
                } else if receipt.outcome != .discarded {
                    Button {
                        if receipt.attempt == 0 && receipt.outcome == .pending, let id {
                            coordinator.dispatch(id: id)
                        } else {
                            retryReceipt = receipt
                        }
                    } label: {
                        Text(receipt.attempt == 0 && receipt.outcome == .pending ? "Send Now" : "Retry")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(id == nil)
                    .accessibilityIdentifier("url_delivery_retry_\(receipt.id)")
                }
                Button(role: .destructive) {
                    discardReceipt = receipt
                    showDiscardConfirmation = true
                } label: { Text("Discard").frame(minWidth: 44, minHeight: 44) }
                .disabled(active || id == nil)
                .accessibilityIdentifier("url_delivery_discard_\(receipt.id)")
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("url_delivery_\(receipt.id)")
    }

    private func origin(_ receipt: URLDeliveryReceipt) -> String {
        receipt.origin ?? String(localized: "Saved Endpoint")
    }

    private func status(_ receipt: URLDeliveryReceipt) -> String {
        switch receipt.outcome {
        case .pending where receipt.attempt == 0: return String(localized: "Ready to Send")
        case .needsAuthentication: return String(localized: "Authentication Required")
        case .retryable: return String(localized: "Delivery Failed")
        case .permanent: return String(localized: "Endpoint Rejected Delivery")
        case .unknownOutcome, .pending: return String(localized: "Outcome Unknown")
        case .discarded: return String(localized: "Cleanup Required")
        case .delivered: return String(localized: "Delivered")
        }
    }

    private func explanation(_ receipt: URLDeliveryReceipt) -> String {
        switch receipt.outcome {
        case .pending where receipt.attempt == 0:
            return String(localized: "Prepared locally. No HTTP attempt has been made.")
        case .needsAuthentication:
            return String(localized: "Correct the saved credentials for the original endpoint in Capture Presets, then Retry.")
        case .retryable, .permanent:
            if let code = receipt.statusCode { return String(localized: "The endpoint returned HTTP \(code). Retry only after correcting the cause.") }
            return String(localized: "Check your connection and endpoint before retrying.")
        case .unknownOutcome, .pending:
            return String(localized: "The endpoint may already have received this capture. Retry requires receiver-side deduplication.")
        case .discarded:
            return String(localized: "Sending is disabled for this identity. Choose Discard again to finish removing its local payload.")
        case .delivered:
            return String(localized: "No further HTTP attempt is needed.")
        }
    }
}
