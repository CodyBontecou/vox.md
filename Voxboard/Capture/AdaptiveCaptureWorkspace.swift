import SwiftUI

/// Uses the space offered by the scene, including when an iPhone folds or a
/// window resizes. Keep the primary slot at the same structural identity so
/// resizing never recreates the composer's text view, selection, or undo stack.
struct AdaptiveCaptureWorkspace: View {
    let showsPreview: Bool
    let primary: CaptureViewSection
    let preview: CaptureViewSection

    static func supportsPreview(width: CGFloat, dynamicTypeSize: DynamicTypeSize) -> Bool {
        width >= 760 && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        HStack(spacing: 0) {
            primary
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            if showsPreview {
                Divider()
                preview
                    .frame(width: 300)
                    .accessibilityIdentifier("capture_preview_pane")
            }
        }
    }
}
