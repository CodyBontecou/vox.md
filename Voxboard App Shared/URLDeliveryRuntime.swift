import VoxboardShared
#if os(iOS)
import UIKit
#endif

/// One task owner per host, shared by recording, the composer and recovery UI.
/// Constructing it never drains the HTTP journal.
@MainActor
enum URLDeliveryRuntime {
    static let coordinator = URLDeliveryCoordinator(deliverer: .appDefault(), beginExecution: { expiration in
        #if os(iOS)
        let lease = WatchRecordingBackgroundLease.begin(
            recordingID: nil,
            namePrefix: "URLDelivery",
            service: WatchRecordingBackgroundTaskClient.live(),
            onExpiration: { _ in expiration() }
        )
        guard WatchRecordingBackgroundExecutionPolicy.shouldStart(
            leaseIsActive: lease.isActive,
            applicationIsActive: UIApplication.shared.applicationState == .active
        ) else {
            lease.end(.unavailable)
            return nil
        }
        return URLDeliveryExecutionLease { lease.end(.completed) }
        #else
        return URLDeliveryExecutionLease()
        #endif
    })
}
