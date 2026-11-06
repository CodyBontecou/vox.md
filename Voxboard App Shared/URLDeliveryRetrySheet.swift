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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            GeistSectionLabel(number: "", title: "Saved Capture")
                            Text(verbatim: shortID.uppercased())
                                .font(Geist.mono(size: 11, relativeTo: .caption))
                                .foregroundStyle(Geist.muted)
                        }
                        Text(receipt.origin ?? String(localized: "Saved Endpoint"))
                            .font(Geist.mono(size: 12.5, relativeTo: .footnote))
                            .foregroundStyle(Geist.text)
                            .textSelection(.enabled)
                        Text("\(receipt.date.formatted(date: .abbreviated, time: .shortened)) · \(shortID)")
                            .font(Geist.mono(size: 11.5, relativeTo: .caption))
                            .foregroundStyle(Geist.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Geist.border, lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                        GeistSectionLabel(number: "", title: "Authorization")
                        Picker("Use Credentials", selection: $selectedPresetID) {
                            Text("Saved Delivery Credentials").tag("")
                            ForEach(matchingPresets) { preset in Text(preset.accessibilityName).tag(preset.id) }
                        }
                        .tint(Geist.text)
                        .font(Geist.label())
                        Text("Choose a route to deliberately use its current credentials, including a newly saved token. Only routes with the exact original endpoint are offered.")
                            .font(Geist.caption(.caption))
                            .foregroundStyle(Geist.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("To correct credentials, cancel and edit them in Routes first.")
                            .font(Geist.caption(.caption))
                            .foregroundStyle(Geist.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Geist.border, lineWidth: 1)
                    )

                    if URLComponents(string: receipt.urlString)?.scheme == "http" {
                        Label {
                            Text("This saved endpoint uses unencrypted HTTP. Your capture and credentials will be sent without encryption.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "lock.open")
                        }
                        .font(Geist.caption(.caption))
                        .foregroundStyle(Geist.Palette.amber900)
                    }

                    VStack(spacing: Geist.Spacing.two) {
                        Button("Retry") {
                            guard let id = UUID(uuidString: receipt.id) else { return }
                            let authorization = matchingPresets.first { $0.id == selectedPresetID }?.exportSettings.urlDelivery
                            Task { await coordinator.retry(id: id, authorization: authorization) }
                            dismiss()
                        }
                        .buttonStyle(GeistButtonStyle(variant: .primary))
                        .disabled(UUID(uuidString: receipt.id) == nil
                            || (!selectedPresetID.isEmpty && !matchingPresets.contains { $0.id == selectedPresetID }))
                        .accessibilityIdentifier("url_delivery_confirm_retry")

                        Text("This does not write another note or audio attachment.")
                            .font(Geist.caption(.caption))
                            .foregroundStyle(Geist.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, Geist.Spacing.one)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Geist.Spacing.four)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Geist.bg.ignoresSafeArea())
            .navigationTitle("Retry URL Delivery")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { presets = CapturePresetStore.loadFlows() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Geist.Spacing.three) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Geist.Palette.amber900)
                .frame(width: 40, height: 40)
                .background(Geist.Palette.amber100, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Geist.Spacing.one) {
                Text("Retry this delivery?")
                    .font(.custom("Geist-SemiBold", size: 22, relativeTo: .title2))
                    .foregroundStyle(Geist.text)
                    .accessibilityAddTraits(.isHeader)
                Text("The endpoint may already have received this capture. Retry keeps the original content, endpoint, and Idempotency-Key. The receiver must deduplicate that key to avoid duplicates.")
                    .font(Geist.body(.subheadline))
                    .foregroundStyle(Geist.Palette.gray800)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
