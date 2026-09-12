import SwiftUI

struct ImageAltTextSettings: View {
    @Binding var generateImageAltText: Bool
    let processingEnabled: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var unavailableReason = OnDeviceImageSupport.unavailableReason

    var body: some View {
        Toggle("Generate Image Alt Text", isOn: $generateImageAltText)
            .disabled(!processingEnabled || (unavailableReason != nil && !generateImageAltText))
            .accessibilityIdentifier("generate_image_alt_text")
            .task(id: scenePhase) { unavailableReason = OnDeviceImageSupport.unavailableReason }
        Text("Describe photos, screenshots, and sketches on this device when you attach them. Existing descriptions are preserved.")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("Keep Original and Apply To control text only. Image descriptions are optional.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if let unavailableReason {
            Text(unavailableReason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
