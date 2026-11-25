import SwiftUI
import VoxboardShared

/// Phone route rail (#160): a vertical column of route tiles along one screen
/// edge, just above the capture controls, so a route can be picked and Speak
/// tapped without changing grip. It sits beside the header route pills; both
/// call the same `select`, so either leaves the draft in the same state.
///
/// The first route sits nearest the controls and later routes rise up the
/// edge. Long lists scroll inside the rail. Only the visible tiles take hits,
/// so the editor underneath stays usable.
struct CaptureRouteSideRail: View {
    static let hitTargetSide: CGFloat = 44
    static let tileSize: CGFloat = 30

    let profiles: [CapturePresetProfile]
    let selectedID: String?
    let isEnabled: Bool
    let select: (String) -> Void

    var body: some View {
        if profiles.count > 1 {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ScrollViewReader { scroller in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(profiles.enumerated()).reversed(), id: \.element.id) { index, profile in
                                    tile(profile, index: index)
                                        .id(profile.id)
                                        // VoiceOver reads routes in route order.
                                        .accessibilitySortPriority(Double(profiles.count - index))
                                }
                            }
                            .padding(.vertical, Geist.Spacing.one)
                        }
                        .defaultScrollAnchor(.bottom)
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.never)
                        .scrollBounceBehavior(.basedOnSize)
                        // Claim only the visible tiles, not a full-height strip
                        // over the editor.
                        .frame(height: viewportHeight(available: proxy.size.height))
                        .onChange(of: selectedID) { _, id in
                            withAnimation(.snappy) { scroller.scrollTo(id) }
                        }
                    }
                    Spacer().frame(height: Geist.Spacing.one)
                }
            }
            .frame(width: Self.hitTargetSide)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Route"))
            .accessibilityValue(Text(verbatim: selectedName))
            .accessibilityIdentifier("capture_route_rail")
        }
    }

    /// The selected route's name, read as the rail's value.
    private var selectedName: String {
        profiles.first { $0.id == selectedID }?.accessibilityName ?? ""
    }

    private func tile(_ profile: CapturePresetProfile, index: Int) -> some View {
        let isOn = profile.id == selectedID
        return Button {
            activate(id: profile.id)
        } label: {
            SignalRouteTile(
                letter: profile.routeTileLetter,
                size: Self.tileSize,
                circular: true,
                tone: SignalRouteTileTone.forRoute(at: index)
            )
            .padding(3)
            .background(Geist.bg, in: Circle())
            .overlay(Circle().stroke(isOn ? Geist.text : Geist.border, lineWidth: isOn ? 2 : 1))
            .frame(width: Self.hitTargetSide, height: Self.hitTargetSide)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: profile.accessibilityName))
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("capture_route_rail_\(profile.id)")
    }

    private func viewportHeight(available: CGFloat) -> CGFloat {
        let content = CGFloat(profiles.count) * Self.hitTargetSide + 2 * Geist.Spacing.one
        return min(max(0, available - Geist.Spacing.one), content)
    }

    /// The tile's action, callable from tests without synthetic touches. The
    /// coordinator still re-checks the route when it applies the selection.
    @discardableResult
    func activate(id: String) -> Bool {
        guard isEnabled,
              id != selectedID,
              profiles.contains(where: { $0.id == id && $0.isEnabled }) else { return false }
        select(id)
        return true
    }
}
