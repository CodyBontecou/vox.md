import SwiftUI
import VoxboardShared

/// Per-route quick-action editor (Signal "Route quick actions").
///
/// Shows a live preview of the pinned row, the ordered pinned list (drag to
/// reorder, "−" to unpin), a MORE ACTIONS grid to pin, the "Same actions on
/// Mac, iPad and keyboard" toggle and Reset (back to the default row).
///
/// Push it from a route editor with `RouteQuickActionsView(presetID: preset.id)`.
/// `presetID` is `CapturePreset.id` (a `String`).
struct RouteQuickActionsView: View {
    let presetID: String
    @Bindable var preferences: CaptureToolbarPreferences

    @State private var editMode: EditMode = .active

    init(presetID: String, preferences: CaptureToolbarPreferences = .shared) {
        self.presetID = presetID
        self.preferences = preferences
    }

    private var pinned: [CaptureToolbarAction] {
        preferences.pinnedActions(forRoute: presetID)
    }

    private var routeName: String {
        CapturePresetStore.flow(id: presetID)?.displayName ?? String(localized: "this route")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick actions")
                        .font(Geist.display(28))
                        .foregroundStyle(Geist.text)
                    Text("Shown above the keyboard when you type into **\(routeName)**. Pin as many as you like — the row scrolls sideways. Everything else stays under •••.")
                        .font(Geist.body(.subheadline))
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))

                previewStrip
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            Section {
                if pinned.isEmpty {
                    Text("Nothing pinned. Everything stays under •••.")
                        .font(Geist.body(.subheadline))
                        .foregroundStyle(Geist.muted)
                }
                ForEach(pinned) { action in
                    HStack(spacing: 10) {
                        Text(verbatim: glyph(action))
                            .font(Geist.mono(size: 13, relativeTo: .footnote))
                            .frame(width: 52, alignment: .leading)
                        Text(action.shortTitle)
                            .font(Geist.body())
                        Spacer(minLength: 8)
                        Button {
                            withAnimation { preferences.unpin(action, forRoute: presetID) }
                        } label: {
                            Text(verbatim: "−")
                                .font(.system(size: 18))
                                .foregroundStyle(Geist.Palette.gray1000)
                                .frame(width: 32, height: 32)
                                .background(Geist.bg, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Unpin \(action.accessibilityLabel)"))
                    }
                    .frame(minHeight: 48)
                    .foregroundStyle(Geist.text)
                    // 48pt rows as on the board; the system's default
                    // vertical insets made each row about 80pt tall.
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .onMove { source, destination in
                    preferences.movePinnedActions(from: source, to: destination, forRoute: presetID)
                }
            } header: {
                HStack {
                    Text("PINNED · IN ORDER")
                    Spacer()
                    Text("\(pinned.count) pinned · row scrolls")
                        .accessibilityIdentifier("route_quick_actions_count")
                }
                .font(Geist.mono(size: 11, relativeTo: .caption))
                .tracking(0.6)
                .foregroundStyle(Geist.muted)
            }

            Section {
                moreActions
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } header: {
                Text("MORE ACTIONS")
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .tracking(0.6)
                    .foregroundStyle(Geist.muted)
            }

            Section {
                Toggle("Same actions on Mac, iPad and keyboard", isOn: syncBinding)
                    .tint(Geist.accent)
                    .accessibilityIdentifier("route_quick_actions_sync")
            } footer: {
                Text("Applies to every route. When off, Mac, iPad and the Vox keyboard keep their own rows.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Geist.bg)
        .environment(\.defaultMinListRowHeight, 48)
        .environment(\.editMode, $editMode)
        .navigationTitle("Quick actions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") {
                    withAnimation { preferences.resetPins(forRoute: presetID) }
                }
                .disabled(!preferences.hasCustomPins(forRoute: presetID))
                .accessibilityHint("Use the default quick actions for this route")
            }
        }
    }

    // MARK: Sections

    private var previewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pinned) { action in
                    Text(verbatim: glyph(action))
                        .font(Geist.mono(size: 12.5, relativeTo: .footnote))
                        .foregroundStyle(Geist.text)
                        .padding(.horizontal, 9)
                        .frame(minWidth: 36, minHeight: 36)
                        .background(Geist.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Geist.border, lineWidth: 1)
                        )
                }
            }
            .padding(8)
        }
        .frame(minHeight: 52)
        .background(Geist.Palette.gray200, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var moreActions: some View {
        let rest = preferences.unpinnedActions(forRoute: presetID)
        let text = rest.filter { !$0.isMedia }
        let media = rest.filter(\.isMedia)
        return VStack(alignment: .leading, spacing: 10) {
            if rest.isEmpty {
                Text("Every action is pinned.")
                    .font(Geist.body(.subheadline))
                    .foregroundStyle(Geist.muted)
            }
            if !text.isEmpty {
                RouteQuickActionsFlowLayout(spacing: 6) {
                    ForEach(text) { pinChip($0) }
                }
            }
            if !media.isEmpty {
                Text(CaptureQuickActionGroup.media.title)
                    .font(Geist.mono(size: 10.5, relativeTo: .caption2))
                    .tracking(0.6)
                    .foregroundStyle(Geist.muted)
                RouteQuickActionsFlowLayout(spacing: 6) {
                    ForEach(media) { pinChip($0) }
                }
            }
        }
    }

    private func pinChip(_ action: CaptureToolbarAction) -> some View {
        Button {
            withAnimation { preferences.pin(action, forRoute: presetID) }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: glyph(action))
                    .font(Geist.mono(size: 12, relativeTo: .footnote))
                Text(action.shortTitle)
                    .font(Geist.body(.footnote))
            }
            .foregroundStyle(Geist.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .overlay(
                Capsule().strokeBorder(Geist.Palette.gray600, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Pin \(action.accessibilityLabel)"))
    }

    private func glyph(_ action: CaptureToolbarAction) -> String {
        CaptureQuickActionGlyph.text(for: action, timestampFormat: preferences.timestampFormat)
            ?? action.glyph
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { preferences.syncsQuickActionsAcrossSurfaces },
            set: { preferences.setSyncsQuickActionsAcrossSurfaces($0) }
        )
    }
}

/// Wraps content-sized chips onto as many lines as needed.
private struct RouteQuickActionsFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
