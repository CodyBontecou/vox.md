import SwiftUI

/// Shown while a Lock Screen control / widget "Add to Draft" launch waits for
/// earlier work on the composer (usually the previous recording reaching the
/// draft) before it opens a new note and records (#115). Cancel ends the wait
/// without recording.
struct WidgetRecordLaunchWaitingBanner: View {
    let cancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text: give the message the full width, Cancel below.
                VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                    HStack(alignment: .firstTextBaseline, spacing: Geist.Spacing.two) {
                        ProgressView().controlSize(.small)
                        message
                    }
                    cancelButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Geist.Spacing.two) {
                    ProgressView().controlSize(.small)
                    message
                    Spacer(minLength: Geist.Spacing.two)
                    cancelButton
                }
            }
        }
        .padding(.horizontal, Geist.Spacing.four)
        .padding(.vertical, Geist.Spacing.two)
        .frame(minHeight: Geist.ControlHeight.medium)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Geist.border, lineWidth: 1))
        .padding(.horizontal, Geist.Spacing.four)
        .padding(.bottom, Geist.Spacing.two)
        // Cancel stays its own control for VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture_widget_record_waiting")
    }

    private var message: some View {
        Text("Saving the recording to your durable draft…")
            .font(Geist.caption())
            .foregroundStyle(Geist.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cancelButton: some View {
        Button("Cancel", action: cancel)
            .font(Geist.caption())
            .accessibilityIdentifier("capture_widget_record_cancel")
    }
}
