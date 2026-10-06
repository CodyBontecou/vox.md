import Foundation

/// Resolves an explicit queue retry without changing a recording's frozen
/// processing or destination policy during ordinary background execution.
public enum RecordingJobRetryDelivery {
    public static func resolve(
        for job: RecordingJob,
        override: RecordingJobDelivery? = nil,
        presetLookup: (String) -> CapturePreset? = { CapturePresetStore.flow(id: $0) }
    ) -> RecordingJobDelivery? {
        if let override { return override }
        guard job.phase == .failed,
              case .preset(var snapshot) = job.delivery,
              snapshot.deliveryTarget == .http,
              (try? URLDeliveryValidator.validate(
                snapshot.exportSettings.urlDelivery.urlString,
                allowingInsecureLocal: snapshot.exportSettings.urlDelivery.allowingInsecureLocal
              )) == nil,
              let current = presetLookup(snapshot.id),
              current.id == snapshot.id,
              current.isEnabled,
              current.deliveryTarget == .http,
              (try? URLDeliveryValidator.validate(
                current.exportSettings.urlDelivery.urlString,
                allowingInsecureLocal: current.exportSettings.urlDelivery.allowingInsecureLocal
              )) != nil else { return nil }

        // An invalid URL cannot have produced a prepared HTTP handoff. Only an
        // explicit retry may repair it, and only using the same preset's HTTP
        // settings. Never change a valid frozen endpoint, switch to Directory,
        // or adopt later edits to enrichment/audio/location policy implicitly.
        snapshot.exportSettings.urlDelivery = current.exportSettings.urlDelivery
        return .preset(snapshot)
    }
}
