import Foundation

/// Upgrade migration only: removes retired analytics state without creating identifiers or sending requests.
public enum RetiredAnalyticsCleanup {
    public static func run(defaults: UserDefaults = .standard) {
        for key in [
            "onboarding.analytics.install_id.v1",
            "onboarding.analytics.queue.v1",
            "onboarding.experiment.assignment.v1",
            "onboarding.analytics.started.v1",
            "onboarding.analytics.model_setup_completed.v1",
            "onboarding.analytics.completed.v1",
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
