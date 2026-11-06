import SwiftUI
import VoxboardShared

/// Pick the language Vox.md uses for its interface, independent of the
/// device language — for example English on a German phone. The selection is
/// applied on the next launch.
struct AppLanguageSettingsView: View {
    @State private var selection: AppLanguage = AppLanguagePreference.current()

    private var languages: [AppLanguage] {
        AppLanguage.allCases.filter { $0 != .system }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("App Language")
                        .font(.custom("Geist-SemiBold", size: 34, relativeTo: .largeTitle))
                        .tracking(-0.8)
                        .foregroundStyle(Geist.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose which language Vox.md uses")
                        .font(Geist.body(.callout))
                        .foregroundStyle(Geist.muted)
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .padding(.bottom, 4)

                VStack(spacing: 0) {
                    systemRow
                    ForEach(languages) { language in
                        GeistDivider().padding(.leading, 14)
                        languageRow(language)
                    }
                }
                .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                        .stroke(Geist.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))

                Text("Language changes take effect the next time Vox.md is opened.")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Geist.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Geist.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Rows

    private var systemRow: some View {
        selectRow(
            title: Text("Use System Language"),
            caption: Text("Follows your device language"),
            language: .system
        )
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        selectRow(
            title: Text(language.nativeDisplayName),
            caption: nil,
            language: language
        )
    }

    private func selectRow(
        title: Text,
        caption: Text?,
        language: AppLanguage
    ) -> some View {
        let isSelected = language == selection
        return Button {
            select(language)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(Geist.label(.body))
                        .foregroundStyle(Geist.text)
                    if let caption {
                        caption
                            .font(Geist.mono(size: 11.5, relativeTo: .caption))
                            .foregroundStyle(Geist.muted)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Geist.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ language: AppLanguage) {
        guard language != selection else { return }
        selection = language
        AppLanguagePreference.set(language)
    }
}
