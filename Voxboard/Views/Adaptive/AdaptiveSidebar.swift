import SwiftUI
import VoxboardShared

/// What the regular-width detail area shows.
enum AdaptiveSection: Hashable {
    case capture
    case activity
    case library
    case settings

    init?(debugName: String?) {
        switch debugName {
        case "capture": self = .capture
        case "activity": self = .activity
        case "library": self = .library
        case "settings": self = .settings
        default: return nil
        }
    }
}

/// iPad sidebar: ROUTES with letter tiles, then VIEWS (Activity with its
/// pending count, Library, and Settings pinned to the bottom).
struct AdaptiveSidebar: View {
    @Bindable var viewModel: QuickCaptureViewModel
    @Binding var section: AdaptiveSection
    let activityCount: Int
    let selectRoute: (CapturePresetProfile) -> Void

    private var routes: [CapturePresetProfile] {
        viewModel.voxProfiles.filter(\.isEnabled)
    }

    private var selectedRouteID: String? {
        viewModel.selectedVoxProfile?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Vox.md")
                .font(.custom("Geist-SemiBold", size: 22, relativeTo: .title2))
                .tracking(-0.44)
                .foregroundStyle(Geist.text)
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
                .accessibilityAddTraits(.isHeader)

            sectionLabel(String(localized: "ROUTES"))
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                        routeRow(route, index: index)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: CGFloat(max(1, routes.count)) * 48)

            sectionLabel(String(localized: "VIEWS"))
                .padding(.top, 20)
                .padding(.bottom, 6)

            viewRow(
                title: "Activity",
                section: .activity,
                dot: activityCount > 0 ? Geist.warning : nil,
                trailing: activityCount > 0 ? "\(activityCount)" : nil
            )
            .accessibilityIdentifier("sidebar_activity")
            viewRow(title: "Library", section: .library)
                .accessibilityIdentifier("sidebar_library")

            Spacer(minLength: 12)

            viewRow(title: "Settings", section: .settings)
                .accessibilityIdentifier("sidebar_settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Geist.Palette.gray200.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Geist.mono(size: 11, relativeTo: .caption))
            .tracking(0.66)
            .foregroundStyle(Geist.muted)
            .padding(.horizontal, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func routeRow(_ route: CapturePresetProfile, index: Int) -> some View {
        let isOn = section == .capture && route.id == selectedRouteID
        return Button {
            selectRoute(route)
        } label: {
            HStack(spacing: 10) {
                SignalRouteTile(
                    letter: route.displayName.isEmpty ? "•" : route.displayName,
                    size: 26,
                    isPrimary: index == 0,
                    isInk: index == 1
                )
                Text(verbatim: route.displayName)
                    .font(.custom(isOn ? "Geist-SemiBold" : "Geist-Regular", size: 15, relativeTo: .body))
                    .foregroundStyle(Geist.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(rowBackground(isOn))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: route.accessibilityName))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("sidebar_route_\(route.id)")
    }

    private func viewRow(
        title: LocalizedStringKey,
        section target: AdaptiveSection,
        dot: Color? = nil,
        trailing: String? = nil
    ) -> some View {
        let isOn = section == target
        return Button {
            section = target
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(dot ?? Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.horizontal, 8)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.custom(isOn ? "Geist-SemiBold" : "Geist-Regular", size: 15, relativeTo: .body))
                    .foregroundStyle(Geist.text)
                Spacer(minLength: 0)
                if let trailing {
                    Text(verbatim: trailing)
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(rowBackground(isOn))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func rowBackground(_ isOn: Bool) -> some View {
        if isOn {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Geist.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Geist.border, lineWidth: 1)
                )
        }
    }
}
