import SwiftUI
import VoxboardShared

/// Regular-width Library (DuoInnerLibrary): the searchable list on the left,
/// the selected capture's `CaptureDetailView` on the right.
struct AdaptiveLibrarySplit: View {
    @Bindable var viewModel: QuickCaptureViewModel
    var onNew: (() -> Void)?

    @State private var selection: Selection?

    private struct Selection {
        var item: LibraryItem
        var isPrimaryRoute: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                NavigationStack {
                    HistoryView(
                        viewModel: viewModel,
                        embedsInNavigationStack: false,
                        onSelectItem: { item, isPrimary in
                            selection = Selection(item: item, isPrimaryRoute: isPrimary)
                        },
                        selectedItemID: selection?.item.id,
                        onNew: onNew
                    )
                }
                .frame(width: listWidth(for: proxy.size.width))

                Rectangle()
                    .fill(Geist.border)
                    .frame(width: 1)
                    .ignoresSafeArea()

                NavigationStack {
                    detail
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Geist.bg.ignoresSafeArea())
    }

    /// Even halves on the Duo inner screen; a fixed list beside a wide detail
    /// on larger windows.
    private func listWidth(for width: CGFloat) -> CGFloat {
        width < 1000 ? floor(width / 2) : 400
    }

    @ViewBuilder
    private var detail: some View {
        if let selection {
            CaptureDetailView(
                item: selection.item,
                viewModel: viewModel,
                isPrimaryRoute: selection.isPrimaryRoute,
                showsBackButton: false,
                onDeleted: { self.selection = nil }
            )
            .id(selection.item.id)
            .background(Geist.Palette.gray100.ignoresSafeArea())
        } else {
            ZStack {
                Geist.Palette.gray100.ignoresSafeArea()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Geist.faint)
                    Text("Select a capture")
                        .font(Geist.heading(.title3))
                        .foregroundStyle(Geist.text)
                    Text("What was captured, where it went and how the route handled it shows here.")
                        .font(Geist.body(.callout))
                        .foregroundStyle(Geist.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
