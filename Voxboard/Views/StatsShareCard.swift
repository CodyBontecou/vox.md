import SwiftUI
import UIKit
import VoxboardShared

// MARK: - Model

/// The three looks a stats share image can take. The raw value is persisted,
/// so the sheet reopens on the style the person last shared.
enum StatsShareCardStyle: String, CaseIterable, Identifiable {
    case sentence
    case file
    case story

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .sentence: return "Sentence"
        case .file: return ".md file"
        case .story: return "Story"
        }
    }

    /// Point size of the card; rendered at 3x for sharing.
    var size: CGSize {
        switch self {
        case .sentence, .file: return CGSize(width: 390, height: 640)
        case .story: return CGSize(width: 390, height: 693)
        }
    }
}

/// Totals only: nothing in here can carry what was said, note names or paths.
struct StatsShareCardData: Equatable {
    struct Source: Equatable {
        let name: String
        let count: String
    }

    struct Day: Equatable {
        let weekday: String
        let total: Int
    }

    let recordingCount: Int
    let captureCount: Int
    let recordings: String
    let captures: String
    let recorded: String
    let attachments: String
    let averageTake: String
    let thisWeek: String
    let days: [Day]
    let topSources: [Source]
}

// MARK: - Card

struct StatsShareCard: View {
    let data: StatsShareCardData
    let style: StatsShareCardStyle

    var body: some View {
        Group {
            switch style {
            case .sentence: SentenceCard(data: data)
            case .file: FileCard(data: data)
            case .story: StoryCard(data: data)
            }
        }
        .frame(width: style.size.width, height: style.size.height)
        .environment(\.dynamicTypeSize, .large)
    }
}

/// Fixed palette and fixed-size type so the image looks the same in light,
/// dark and at any Dynamic Type size, wherever it ends up.
private enum Card {
    static let ink = hex(0x0B0B0B)
    static let paper = hex(0xF4F4F1)
    static let cream = hex(0xF2F2EE)
    static let charcoal = hex(0x2A2A28)
    static let dim = hex(0x9A9A95)
    static let indigo = hex(0x2F3BE8)
    static let indigoLight = hex(0x6E78FF)
    static let lavender = hex(0xC4C8FF)
    static let darkText = hex(0x121212)
    static let fileMuted = hex(0x5E5E5A)
    static let fileFaint = hex(0x8A8A85)
    static let fileLineNumber = hex(0xA3A39E)
    static let fileRule = hex(0xDEDED8)

    static let domain = "vox.isolated.tech"

    static func sans(_ size: CGFloat, weight: String = "SemiBold") -> Font {
        .custom("Geist-\(weight)", fixedSize: size)
    }

    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "GeistMono-Medium" : "GeistMono-Regular", fixedSize: size)
    }

    static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func label(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .textCase(.uppercase)
            .font(mono(10))
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

// MARK: A · Sentence

private struct SentenceCard: View {
    let data: StatsShareCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                (Text("Vox") + Text(".md").foregroundColor(Card.indigoLight))
                    .font(Card.sans(19))
                    .tracking(-0.3)
                Spacer()
                Text("Since day one")
                    .textCase(.uppercase)
                    .font(Card.mono(11))
                    .tracking(0.66)
                    .foregroundStyle(Card.dim)
            }

            VStack(alignment: .leading, spacing: 0) {
                data.recordingCount == 1 ? Text("1 recording,") : Text("\(data.recordings) recordings,")
                data.captureCount == 1 ? Text("1 capture,") : Text("\(data.captures) captures,")
                Text("\(data.recorded) out loud.")
                    .foregroundStyle(Card.indigoLight)
            }
            .font(Card.sans(42))
            .tracking(-1.4)
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            VStack(spacing: 8) {
                WeekBars(days: data.days, height: 56, hot: Card.indigoLight, cold: Card.charcoal)
                HStack(spacing: 4) {
                    ForEach(Array(data.days.enumerated()), id: \.offset) { _, day in
                        Text(day.weekday)
                            .font(Card.mono(10))
                            .foregroundStyle(Card.dim)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                stat(data.attachments, label: "Attachments")
                stat(data.averageTake, label: "Avg take")
                stat(data.thisWeek, label: "This week")
            }

            if !data.topSources.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(data.topSources.enumerated()), id: \.offset) { index, source in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%02d", index + 1))
                                .font(Card.mono(11))
                                .foregroundStyle(Card.dim)
                                .frame(width: 20, alignment: .leading)
                            Text(source.name)
                                .font(Card.sans(18, weight: "Medium"))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(source.count)
                                .font(Card.mono(12))
                                .foregroundStyle(Card.dim)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Card.charcoal).frame(height: 1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("Counted on-device · no words included")
                Spacer()
                Text(verbatim: Card.domain)
            }
            .font(Card.mono(10))
            .foregroundStyle(Card.dim)
        }
        .foregroundStyle(Card.paper)
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Card.ink)
    }

    private func stat(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Card.sans(26))
                .tracking(-0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Card.label(label, color: Card.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: B · Raw .md file

private struct FileCard: View {
    let data: StatsShareCardData

    private enum Line {
        case text(Text)
        case heading
        case source(StatsShareCardData.Source)
    }

    private var lines: [Line] {
        func key(_ name: String, _ value: String) -> Line {
            .text(Text(verbatim: "\(name): ").foregroundColor(Card.indigo) + Text(verbatim: value))
        }
        var lines: [Line] = [
            .text(Text(verbatim: "---").foregroundColor(Card.fileFaint)),
            key("recordings", data.recordings),
            key("captures", data.captures),
            key("spoken", data.recorded),
            key("attachments", data.attachments),
            .text(Text(verbatim: "---").foregroundColor(Card.fileFaint)),
            .text(Text(verbatim: "")),
            .heading,
            .text(Text(verbatim: "")),
        ]
        if !data.topSources.isEmpty {
            lines.append(.text(Text("## where it came from").foregroundColor(Card.fileMuted)))
            lines += data.topSources.map { .source($0) }
            lines.append(.text(Text(verbatim: "")))
        }
        lines.append(.text(Text("## this week").foregroundColor(Card.fileMuted)))
        lines.append(.text(sparkline + Text(verbatim: " ") + Text("\(data.thisWeek) entries").foregroundColor(Card.fileMuted)))
        return lines
    }

    private var sparkline: Text {
        let blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        let maximum = max(data.days.map(\.total).max() ?? 0, 1)
        return data.days.reduce(Text(verbatim: "")) { result, day in
            guard day.total > 0 else {
                return result + Text(verbatim: "·").foregroundColor(Card.fileFaint)
            }
            let index = min(blocks.count - 1, max(0, Int((Double(day.total) / Double(maximum) * Double(blocks.count - 1)).rounded())))
            return result + Text(verbatim: blocks[index]).foregroundColor(Card.indigo)
        }
    }

    private var heading: Text {
        var duration = AttributedString("\u{00A0}\(data.recorded)\u{00A0}")
        duration.backgroundColor = Card.indigo
        duration.foregroundColor = Card.paper
        return Text(verbatim: "# ").font(Card.mono(40)).foregroundColor(Card.fileLineNumber)
            + Text("I talked to my notes for ")
            + Text(duration)
            + Text(verbatim: ".")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Card.indigo).frame(width: 8, height: 8)
                Text(verbatim: "~/vault/stats.md")
                Spacer()
                Text(verbatim: "Vox.md")
            }
            .font(Card.mono(11))
            .foregroundStyle(Card.fileMuted)
            .padding(.horizontal, 22)

            Rectangle().fill(Card.fileRule).frame(height: 1)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "\(index + 1)")
                            .font(Card.mono(13))
                            .foregroundStyle(Card.fileLineNumber)
                            .frame(width: 28, alignment: .trailing)
                            .padding(.trailing, 8)
                        content(for: line)
                    }
                }
            }
            .padding(.trailing, 22)

            Spacer(minLength: 0)

            HStack {
                Text("counted on-device · no words included")
                Spacer()
                Text(verbatim: Card.domain)
            }
            .font(Card.mono(10))
            .foregroundStyle(Card.fileMuted)
            .padding(.horizontal, 22)
        }
        .foregroundStyle(Card.darkText)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Card.cream)
    }

    @ViewBuilder
    private func content(for line: Line) -> some View {
        switch line {
        case .text(let text):
            text
                .font(Card.mono(13))
                .lineLimit(1)
                .frame(minHeight: 18, alignment: .leading)
        case .heading:
            heading
                .font(Card.sans(38))
                .tracking(-1.2)
                .lineSpacing(-2)
                .minimumScaleFactor(0.6)
                .padding(.vertical, 4)
        case .source(let source):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "- [x] \(source.name.lowercased())")
                    .lineLimit(1)
                DottedLeader()
                    .stroke(Card.fileFaint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 5]))
                    .frame(height: 2)
                Text(verbatim: source.count)
            }
            .font(Card.mono(13))
        }
    }
}

private struct DottedLeader: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: C · 9:16 story

private struct StoryCard: View {
    let data: StatsShareCardData

    /// A decorative waveform, the same on every card.
    private let wave: [CGFloat] = [18, 40, 70, 30, 84, 52, 22, 60, 36, 12, 46, 26, 8]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(verbatim: "VOX.MD / STATS")
                Spacer()
                Text("Since day one")
                    .textCase(.uppercase)
                    .foregroundStyle(Card.lavender)
            }
            .font(Card.mono(11))
            .tracking(0.66)

            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(wave.enumerated()), id: \.offset) { _, height in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Card.paper)
                        .frame(height: height)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 84)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: data.recordings)
                    .font(Card.sans(132))
                    .tracking(-6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.vertical, -14)
                (Text("things I said out loud") + Text(" instead of typing.").foregroundColor(Card.lavender))
                    .font(Card.sans(26))
                    .tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    cell(data.recorded, label: Text("Recorded"))
                    cell(data.captures, label: Text("Captures"))
                }
                HStack(spacing: 1) {
                    cell(data.attachments, label: Text("Attachments"))
                    if let top = data.topSources.first {
                        cell(top.name, label: Text("Top source") + Text(verbatim: " · \(top.count)"))
                    } else {
                        cell("—", label: Text("Top source"))
                    }
                }
            }
            .background(Card.paper.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Text("Counted on-device")
                Spacer()
                Text(verbatim: Card.domain)
            }
            .font(Card.mono(10))
            .foregroundStyle(Card.lavender)
        }
        .foregroundStyle(Card.paper)
        .padding(.horizontal, 26)
        .padding(.top, 48)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Card.indigo)
    }

    private func cell(_ value: String, label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(Card.sans(28))
                .tracking(-0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            label
                .textCase(.uppercase)
                .font(Card.mono(10))
                .tracking(0.6)
                .foregroundStyle(Card.lavender)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Card.indigo)
    }
}

// MARK: - Shared pieces

private struct WeekBars: View {
    let days: [StatsShareCardData.Day]
    let height: CGFloat
    let hot: Color
    let cold: Color

    var body: some View {
        let maximum = max(days.map(\.total).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(day.total > 0 ? hot : cold)
                    .frame(height: day.total > 0 ? max(10, height * CGFloat(day.total) / CGFloat(maximum)) : 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Share sheet

struct StatsShareSheet: View {
    let data: StatsShareCardData

    @Environment(\.dismiss) private var dismiss
    @AppStorage("statsShareCardStyle") private var styleRawValue = StatsShareCardStyle.sentence.rawValue
    @State private var renderedCards: [StatsShareCardStyle: UIImage] = [:]

    private var style: StatsShareCardStyle {
        StatsShareCardStyle(rawValue: styleRawValue) ?? .sentence
    }

    private var styleBinding: Binding<StatsShareCardStyle> {
        Binding(get: { style }, set: { styleRawValue = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Geist.Spacing.four) {
                Picker("Style", selection: styleBinding) {
                    ForEach(StatsShareCardStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                    if let image = renderedCards[style] {
                        let shareImage = Image(uiImage: image)
                        ShareLink(
                            item: shareImage,
                            preview: SharePreview(Text("Vox.md stats"), image: shareImage)
                        ) {
                            Label("Share image", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(GeistButtonStyle(variant: .primary))
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: Geist.ControlHeight.large)
                    }

                    Text("The image shows totals only. It never includes what you said, note names, or vault paths.")
                        .font(Geist.mono(size: 11, relativeTo: .caption2))
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Geist.Spacing.four)
            .padding(.top, Geist.Spacing.two)
            .padding(.bottom, Geist.Spacing.four)
            .background(Geist.bg.ignoresSafeArea())
            .navigationTitle("Share stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: data) {
            renderedCards = Dictionary(uniqueKeysWithValues: StatsShareCardStyle.allCases.compactMap { style in
                render(style).map { (style, $0) }
            })
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = renderedCards[style] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .accessibilityLabel(Text("Preview of the shared stats image"))
                .id(style)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: style)
        } else {
            Color.clear
        }
    }

    @MainActor
    private func render(_ style: StatsShareCardStyle) -> UIImage? {
        let renderer = ImageRenderer(content: StatsShareCard(data: data, style: style))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
