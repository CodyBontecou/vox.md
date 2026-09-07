import SwiftUI

/// A non-generic boundary between the capture coordinator's UI sections.
///
/// Moving a large builder into another `some View` getter does not bound its
/// metadata: Swift can still resolve the opaque return types recursively. This
/// wrapper stores AnyView, so a parent's type never contains a section's Content.
/// Keep erasure here rather than scattering AnyView through the coordinator.
/// See docs/capture-view-regression-tests.md for the guardrails and device gate.
struct CaptureViewSection: View {
    private let content: AnyView

    init<Content: View>(@ViewBuilder _ content: () -> Content) {
        self.content = AnyView(content())
    }

    var body: AnyView { content }
}
