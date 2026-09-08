import AppIntents
import VoxboardCaptureCore

@available(iOS 17.0, macOS 14.0, *)
enum CapturePresetWidgetSource: String, AppEnum {
    case followCaptureBar
    case custom

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Preset Source"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .followCaptureBar: "Follow Capture Bar",
        .custom: "Custom",
    ]
}

/// Native collection parameters expose cardinality, but the selected SDK does
/// not guarantee a reorder UI. Named slots make per-instance order explicit.
struct CapturePresetWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Capture Presets"
    static let description = IntentDescription(
        "Follow your Capture Bar, or choose up to six presets in order. Small shows First; medium and large show all chosen slots. Empty positions are not replaced."
    )

    @Parameter(title: "Preset Source", default: .followCaptureBar)
    var source: CapturePresetWidgetSource

    @Parameter(title: "First", description: "First position. This is the preset shown in a small widget.")
    var first: CapturePresetWidgetEntity?
    @Parameter(title: "Second", description: "Second position in medium and large widgets.")
    var second: CapturePresetWidgetEntity?
    @Parameter(title: "Third", description: "Third position in medium and large widgets.")
    var third: CapturePresetWidgetEntity?
    @Parameter(title: "Fourth", description: "Fourth position in medium and large widgets.")
    var fourth: CapturePresetWidgetEntity?
    @Parameter(title: "Fifth", description: "Fifth position in medium and large widgets.")
    var fifth: CapturePresetWidgetEntity?
    @Parameter(title: "Sixth", description: "Sixth position in medium and large widgets.")
    var sixth: CapturePresetWidgetEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$source, .equalTo, CapturePresetWidgetSource.custom) {
            Summary("\(\.$source)") {
                \.$first
                \.$second
                \.$third
                \.$fourth
                \.$fifth
                \.$sixth
            }
        } otherwise: {
            Summary("\(\.$source)")
        }
    }

    /// Copy IDs into an immutable value before querying storage. Entries never
    /// retain an IntentParameter reference or consult defaults from their body.
    var selection: CapturePresetWidgetSelection {
        switch source {
        case .followCaptureBar: return .followCaptureBar
        case .custom: return .custom(slots: [first?.id, second?.id, third?.id, fourth?.id, fifth?.id, sixth?.id])
        }
    }
}
