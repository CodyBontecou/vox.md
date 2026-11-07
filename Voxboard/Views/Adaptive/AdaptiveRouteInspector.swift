import SwiftUI
import UIKit
import VoxboardShared

// MARK: - Route summary

/// CAPTURE / PROCESS / SHAPE / DELIVER and the "WILL WRITE" Markdown for the
/// composer's current route, rendered with the pipeline's
/// `CaptureMarkdownRenderer` (iOS twin of the Mac workspace preview).
@MainActor
enum AdaptiveRouteSummary {
    struct Step: Identifiable, Equatable {
        let kind: String
        let title: String
        var id: String { kind }
    }

    static func steps(for viewModel: QuickCaptureViewModel) -> [Step] {
        let profile = viewModel.selectedVoxProfile
        let destination = viewModel.selectedDestination
        let process: String
        if let profile, profile.captureProcessingEnabled, profile.postProcessingMode != .none {
            process = "\(profile.postProcessingMode.displayName) · " + String(localized: "on device")
        } else {
            process = String(localized: "As typed · no processing")
        }
        let shape: String
        if let template = entryTemplate(for: viewModel) {
            shape = template.name
        } else if let destination, !(destination.entryPrefix + destination.entrySuffix).isEmpty {
            let firstLine = destination.entryPrefix.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            shape = ["{time}", "{timestamp}", "{hour}", "{minute}"].contains(where: { firstLine.contains($0) })
                ? String(localized: "Timestamped entry")
                : String(localized: "Route template")
        } else {
            shape = String(localized: "Plain entry")
        }
        return [
            // Apple Pencil is iPad-only; the Duo inner screen lists the rest.
            Step(kind: String(localized: "CAPTURE"), title: UIDevice.current.userInterfaceIdiom == .pad
                ? String(localized: "Voice, text, Pencil, photos")
                : String(localized: "Voice, text, photos")),
            Step(kind: String(localized: "PROCESS"), title: process),
            Step(kind: String(localized: "SHAPE"), title: shape),
            Step(kind: String(localized: "DELIVER"), title: deliverSummary(for: viewModel)),
        ]
    }

    static func deliverSummary(for viewModel: QuickCaptureViewModel) -> String {
        guard let destination = viewModel.selectedDestination else {
            return String(localized: "Choose a destination")
        }
        if let override = viewModel.draft.relativeNotePathOverride {
            return (override as NSString).lastPathComponent + " · " + String(localized: "append")
        }
        let note: String
        switch destination.noteTarget {
        case .rollingNote(_, let period):
            note = period == .daily
                ? String(localized: "Daily note")
                : String(localized: "\(period.rawValue.capitalized) note")
        case .newNote:
            note = String(localized: "New note")
        case .existingNote(let path):
            note = (path as NSString).lastPathComponent
        }
        switch viewModel.draft.placementOverride ?? destination.placement {
        case .append:
            return note + " · " + String(localized: "append")
        case .prepend:
            return note + " · " + String(localized: "prepend")
        case .beneathHeading:
            return note + " › " + (headingMarkdown(for: destination) ?? "") + " · " + String(localized: "append")
        }
    }

    static func headingMarkdown(for destination: CaptureDestination?) -> String? {
        guard let destination,
              case .beneathHeading(let selector, _, _) = destination.placement else { return nil }
        return String(repeating: "#", count: max(1, min(6, selector.level ?? 2))) + " " + selector.title
    }

    static func entryTemplate(for viewModel: QuickCaptureViewModel) -> CaptureEntryTemplate? {
        let id = viewModel.draft.entryTemplateID ?? viewModel.selectedDestination?.entryTemplateID
        guard let id else { return nil }
        return viewModel.entryTemplates.first { $0.id == id }
    }

    /// The Markdown this draft will write (prefix + rendered entry + suffix).
    static func willWrite(for viewModel: QuickCaptureViewModel) -> String? {
        guard let destination = viewModel.selectedDestination,
              let destinationID = viewModel.effectiveDestinationID,
              viewModel.draft.hasCaptureContent,
              let request = try? viewModel.draft.makeRequest(
                source: .app,
                resolvedDestinationID: destinationID,
                voxProfile: viewModel.selectedVoxProfile
              ),
              let rendered = try? CaptureMarkdownRenderer().render(request, for: destination) else {
            return nil
        }
        let template = entryTemplate(for: viewModel)
        let prefixTemplate = template?.entryPrefix ?? destination.entryPrefix
        let entry = CaptureEntryTemplateRenderer.entry(rendered, under: prefixTemplate, for: request)
        let renderer = CaptureEntryTemplateRenderer()
        let prefix = renderer.render(prefixTemplate, for: request)
        let suffix = renderer.render(template?.entrySuffix ?? destination.entrySuffix, for: request)
        let output = (prefix + entry + suffix).trimmingCharacters(in: .newlines)
        let maxLength = 1_200
        return output.count > maxLength ? String(output.prefix(maxLength)) + "…" : output
    }
}

// MARK: - Inspector

/// The route column beside the composer: steps, live "WILL WRITE" preview and
/// "Edit route". In the two-pane layout it also carries "Send to <route>".
struct AdaptiveRouteInspector: View {
    @Bindable var viewModel: QuickCaptureViewModel
    let layout: CaptureComposerLayout
    let commands: CaptureComposerCommands

    @State private var editingRouteID: String?

    private var routeName: String {
        viewModel.selectedVoxProfile?.displayName ?? String(localized: "Route")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stepsView
            // The Duo inner pane previews the Markdown (DuoInnerCapture); the
            // iPad inspector column lists the steps only (iPad board).
            if layout == .regularPane {
                willWriteBlock
            }
            if layout == .regularPane {
                sendButton
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, layout == .regularPane ? 28 : 20)
        .padding(.top, layout == .regularPane ? 24 : 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Geist.Palette.gray100.ignoresSafeArea())
        .sheet(item: editingRouteBinding) { route in
            AdaptiveRouteEditorSheet(routeID: route.id) {
                editingRouteID = nil
                viewModel.refreshVoxProfiles()
                Task { await viewModel.refreshLibrary() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Route inspector"))
        .accessibilityIdentifier("adaptive_route_inspector")
    }

    private var header: some View {
        HStack {
            Text(layout == .regularPane ? String(localized: "ROUTE") : String(localized: "THIS ROUTE"))
                .font(Geist.mono(size: 11, relativeTo: .caption))
                .tracking(0.66)
                .foregroundStyle(Geist.muted)
            Spacer()
            if layout == .regularPane { editRouteButton(title: "Edit") }
        }
    }

    @ViewBuilder
    private var stepsView: some View {
        let steps = AdaptiveRouteSummary.steps(for: viewModel)
        if layout == .regularPane {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(steps) { stepCard($0).frame(maxHeight: .infinity, alignment: .topLeading) }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(steps) { stepCard($0) }
            }
            editRouteButton(title: "Edit route")
                .padding(.top, 4)
        }
    }

    private func stepCard(_ step: AdaptiveRouteSummary.Step) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: step.kind)
                .font(Geist.mono(size: 10.5, relativeTo: .caption2))
                .tracking(0.63)
                .foregroundStyle(Geist.muted)
            Text(verbatim: step.title)
                .font(.custom("Geist-Medium", size: 14, relativeTo: .subheadline))
                .foregroundStyle(Geist.text)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Geist.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var willWriteBlock: some View {
        let markdown = AdaptiveRouteSummary.willWrite(for: viewModel)
        let heading = AdaptiveRouteSummary.headingMarkdown(for: viewModel.selectedDestination)
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: heading.map { String(localized: "WILL WRITE") + " · \($0)" } ?? String(localized: "WILL WRITE"))
                .font(Geist.mono(size: 10.5, relativeTo: .caption2))
                .tracking(0.63)
                .foregroundStyle(Color(captureHex: 0x9A9A95))
                .lineLimit(1)
            ScrollView {
                Text(verbatim: markdown ?? placeholder)
                    .font(Geist.mono(size: 12, relativeTo: .caption))
                    .lineSpacing(5)
                    .foregroundStyle(markdown == nil ? Color(captureHex: 0x8A8A85) : Color(captureHex: 0xE9E9E4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: layout == .regularPane ? .infinity : 320, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: layout != .regularPane)
        .background(Color(captureHex: 0x121212), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Will write"))
        .accessibilityValue(Text(verbatim: markdown ?? placeholder))
        .accessibilityIdentifier("adaptive_will_write")
    }

    private var placeholder: String {
        viewModel.selectedDestination == nil
            ? String(localized: "Set up where this route writes Markdown to see a preview.")
            : String(localized: "Start typing or speaking — the Markdown this route writes appears here.")
    }

    private var sendButton: some View {
        Button {
            commands.send?()
        } label: {
            Text("Send to \(routeName)")
                .font(.custom("Geist-SemiBold", size: 16, relativeTo: .body))
                .lineLimit(1)
                .foregroundStyle(Geist.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: Geist.ControlHeight.large)
                .background(Geist.accent, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!commands.canSend || commands.send == nil)
        .opacity(commands.canSend ? 1 : 0.35)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityHint(Text("Command Return"))
        .accessibilityIdentifier("adaptive_route_send")
    }

    private func editRouteButton(title: LocalizedStringKey) -> some View {
        Button {
            editingRouteID = viewModel.selectedVoxProfile?.id
        } label: {
            Text(title)
                .font(.custom("Geist-Medium", size: 14, relativeTo: .subheadline))
                .foregroundStyle(Geist.accentText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedVoxProfile == nil)
        .accessibilityIdentifier("adaptive_edit_route")
    }

    private var editingRouteBinding: Binding<AdaptiveRouteID?> {
        Binding(
            get: { editingRouteID.map(AdaptiveRouteID.init) },
            set: { editingRouteID = $0?.id }
        )
    }
}

struct AdaptiveRouteID: Identifiable, Hashable {
    let id: String
}

/// The existing route editor (`CapturePresetEditorView`), saved through
/// `CapturePresetStore` at every edit like the Routes list does.
struct AdaptiveRouteEditorSheet: View {
    let routeID: String
    let done: () -> Void

    @State private var flows: [CapturePreset] = CapturePresetStore.loadFlows()

    var body: some View {
        NavigationStack {
            if let binding = flowBinding {
                CapturePresetEditorView(preset: binding)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: done)
                        }
                    }
            } else {
                ContentUnavailableView("Route unavailable", systemImage: "arrow.triangle.branch")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: done)
                        }
                    }
            }
        }
    }

    private var flowBinding: Binding<CapturePreset>? {
        guard let fallback = flows.first(where: { $0.id == routeID }) else { return nil }
        return Binding(
            get: { flows.first(where: { $0.id == routeID }) ?? fallback },
            set: { updated in
                guard let index = flows.firstIndex(where: { $0.id == routeID }) else { return }
                flows[index] = updated
                CapturePresetStore.saveFlows(flows)
            }
        )
    }
}
