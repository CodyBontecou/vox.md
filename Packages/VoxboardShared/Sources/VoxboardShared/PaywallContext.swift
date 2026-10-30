// Presentation-only context; never recorded or uploaded.
public enum PaywallContext: String, CaseIterable, Sendable {
    case onboarding
    case usageMeter = "usage_meter"
    case limit
    case recording
    case captureLimit = "capture_limit"
    case keyboard
    case widget
    case settings
    case restore
    case unknown
}
