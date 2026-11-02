import SwiftUI
import UIKit

struct CaptureDraftPreview: View {
    let text: String
    let presetName: String
    let destination: String?
    let attachmentCount: Int
    let configureDestination: () -> Void
    @State private var hasCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heading
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        CaptureMarkdownLine(line: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                if attachmentCount > 0 {
                    Label("\(attachmentCount) attachments", systemImage: "paperclip")
                        .font(Geist.caption()).foregroundStyle(Geist.muted)
                }
                Divider()
                delivery
                Text("Draft preview. Preset formatting and processing are applied when you send.")
                    .font(Geist.caption(.caption2))
                    .foregroundStyle(Geist.faint)
            }
            .padding(22)
        }
        .background(Geist.Palette.background100)
        .accessibilityIdentifier("capture_draft_preview")
        .task(id: hasCopied) {
            guard hasCopied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hasCopied = false
        }
    }

    private var heading: some View {
        HStack {
            Label("DRAFT PREVIEW", systemImage: "doc.text")
                .font(Geist.mono(.caption2, medium: true))
                .tracking(1)
                .foregroundStyle(Geist.Palette.blue700)
            Spacer()
            Button {
                UIPasteboard.general.string = text
                hasCopied = true
            } label: {
                Image(systemName: hasCopied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Geist.muted)
            .accessibilityLabel(hasCopied ? "Draft Markdown copied" : "Copy draft Markdown")
        }
    }

    private var delivery: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DESTINATION").font(Geist.mono(.caption2, medium: true))
                .tracking(1).foregroundStyle(Geist.faint)
            Label(presetName, systemImage: "tray")
                .font(Geist.label()).foregroundStyle(Geist.text)
            if let destination {
                Text(verbatim: destination)
                    .font(Geist.mono(.caption))
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("Choose where this goes", action: configureDestination)
                    .font(Geist.caption()).foregroundStyle(Geist.Palette.blue700)
                    .frame(minHeight: 44)
            }
        }
    }
}

/// A deliberately local preview: Markdown images never fetch remote content.
/// Source text remains authoritative; this is not the processed delivery output.
struct CaptureMarkdownLine: View {
    let line: String

    var body: some View {
        if line.hasPrefix("### ") {
            inline(String(line.dropFirst(4))).font(.headline)
        } else if line.hasPrefix("## ") {
            inline(String(line.dropFirst(3))).font(.title2.weight(.semibold))
        } else if line.hasPrefix("# ") {
            inline(String(line.dropFirst(2))).font(.system(.title, design: .serif))
        } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
            Label {
                inline(String(line.dropFirst(6)))
            } icon: {
                Image(systemName: line.hasPrefix("- [x]") ? "checkmark.square.fill" : "square")
                    .foregroundStyle(Geist.Palette.blue700)
            }
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").foregroundStyle(Geist.Palette.blue700)
                inline(String(line.dropFirst(2)))
            }
        } else if line.hasPrefix("> ") {
            inline(String(line.dropFirst(2))).italic().foregroundStyle(Geist.muted)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Geist.Palette.blue700).frame(width: 2) }
        } else if line.isEmpty {
            Color.clear.frame(height: 4)
        } else {
            inline(line)
        }
    }

    private func inline(_ value: String) -> Text {
        if let markdown = try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(markdown).foregroundColor(Geist.text)
        }
        return Text(verbatim: value).foregroundColor(Geist.text)
    }
}
