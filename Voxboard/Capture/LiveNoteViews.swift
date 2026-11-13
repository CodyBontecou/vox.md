import SwiftUI
import VoxboardShared

/// The save state under the preset: "Saves as you go", "Saving…", "Saved",
/// or what needs attention.
struct LiveNoteStatusPill: View {
    let status: LiveNoteStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(foreground)
                .frame(width: 7, height: 7)
            Text(title)
                .font(Geist.label(.caption))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("live_note_status")
    }

    private var title: LocalizedStringKey {
        switch status {
        case .idle: "Saves as you go"
        case .saving: "Saving…"
        case .saved: "Saved"
        case .conflict: "Paused"
        case .unreachable: "On this iPhone"
        case .missing: "File missing"
        case .failed: "Not saved"
        }
    }

    private var foreground: Color {
        switch status {
        case .idle: Geist.muted
        case .saving: Geist.accentText
        case .saved: Geist.success
        case .conflict, .unreachable, .missing, .failed: Geist.Palette.amber900
        }
    }

    private var background: Color {
        switch status {
        case .idle: Geist.well
        case .saving: Geist.accentSoft
        case .saved: Geist.Palette.green100
        case .conflict, .unreachable, .missing, .failed: Geist.Palette.amber100
        }
    }
}

/// Problems with the open file, shown as a card under the path. Never a
/// modal: dictation and typing keep working in every state.
struct LiveNoteBanner: View {
    let status: LiveNoteStatus
    let fileName: String?
    var resolve: (LiveNoteConflictChoice) -> Void
    var reconnect: () -> Void
    var recreate: () -> Void

    var body: some View {
        if let content {
            VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: content.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Geist.Palette.amber900)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.title)
                            .font(Geist.heading(.callout))
                            .foregroundStyle(Geist.text)
                        Text(content.message)
                            .font(Geist.body(.subheadline))
                            .foregroundStyle(Geist.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                actions
            }
            .padding(Geist.Spacing.four)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Geist.Palette.amber400, lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
        }
    }

    private struct Content {
        var icon: String
        var title: LocalizedStringKey
        var message: LocalizedStringKey
    }

    private var content: Content? {
        switch status {
        case .conflict:
            Content(
                icon: "exclamationmark.triangle",
                title: "This file changed in another app",
                message: "You both edited it. Pick which version to keep."
            )
        case .unreachable:
            Content(
                icon: "icloud.slash",
                title: "Can’t reach your vault folder",
                message: "Keep going. Edits are kept on this iPhone and written to the file when the folder is back."
            )
        case .missing:
            Content(
                icon: "questionmark.folder",
                title: "This file was moved or deleted",
                message: "Your text is still here. Recreate the file, or start a new note."
            )
        case .failed(let message):
            Content(
                icon: "exclamationmark.triangle",
                title: "Couldn’t save",
                message: "\(message)"
            )
        default:
            nil
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .conflict:
            VStack(spacing: 8) {
                Button("Keep mine") { resolve(.keepMine) }
                    .buttonStyle(LiveNoteBannerButtonStyle(isPrimary: true))
                HStack(spacing: 8) {
                    Button("Use theirs") { resolve(.useTheirs) }
                        .buttonStyle(LiveNoteBannerButtonStyle(isPrimary: false))
                    Button("Save a copy") { resolve(.saveCopy) }
                        .buttonStyle(LiveNoteBannerButtonStyle(isPrimary: false))
                }
            }
        case .unreachable:
            Button("Reconnect folder", action: reconnect)
                .buttonStyle(LiveNoteBannerButtonStyle(isPrimary: true, fillsWidth: false))
        case .missing:
            Button("Recreate file", action: recreate)
                .buttonStyle(LiveNoteBannerButtonStyle(isPrimary: true, fillsWidth: false))
        default:
            EmptyView()
        }
    }
}

struct LiveNoteBannerButtonStyle: ButtonStyle {
    var isPrimary: Bool
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Geist.label(.subheadline))
            .foregroundStyle(isPrimary ? Color.white : Geist.text)
            .padding(.horizontal, 16)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: Geist.ControlHeight.medium)
            .background(isPrimary ? Geist.text : Geist.card, in: Capsule())
            .overlay(Capsule().stroke(isPrimary ? Color.clear : Geist.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// After New note: "<title> is in <preset>" with Reopen, for a few seconds.
struct LiveNoteClosedToast: View {
    let note: ClosedLiveNote
    var reopen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Geist.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if note.presetName.isEmpty {
                        Text("\(note.binding.title) is saved")
                    } else {
                        Text("\(note.binding.title) is in \(note.presetName)")
                    }
                }
                .font(Geist.label(.subheadline))
                .foregroundStyle(Geist.text)
                .lineLimit(1)
                Text(verbatim: note.binding.relativePath)
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button("Reopen", action: reopen)
                .font(Geist.label(.footnote))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Geist.text, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityIdentifier("live_note_reopen")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Geist.card, in: Capsule())
        .overlay(Capsule().stroke(Geist.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Recording: where the spoken words are going. Indigo when they're being
/// written into an open file right now; muted before the note's first save.
struct LiveNoteRecordingLineView: View {
    let text: String
    let isLive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isLive ? "doc.text" : "tray.and.arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(Geist.mono(size: 11.5, relativeTo: .caption))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(isLive ? Color(Geist.Palette.blue500) : Color(captureHex: 0x9A9A95))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("live_note_recording_line")
    }
}
