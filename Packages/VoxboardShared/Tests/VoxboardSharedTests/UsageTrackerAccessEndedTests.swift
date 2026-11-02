import XCTest
@testable import VoxboardShared

/// "Expired" (read-only app) vs "never had access" (onboarding paywall).
final class UsageTrackerAccessEndedTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "UsageTrackerAccessEndedTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNewUserHasNeverHadAccess() {
        let tracker = UsageTracker(defaults: defaults)
        XCTAssertFalse(tracker.hasHadUnlimitedAccess)
        XCTAssertFalse(tracker.hasAccessEnded)
    }

    func testEndedSubscriptionIsReadOnlyNotFirstRun() {
        let tracker = UsageTracker(defaults: defaults)
        tracker.reconcileStoreEntitlements([.individualYearly], expirationDate: Date().addingTimeInterval(3_600))
        XCTAssertTrue(tracker.hasUnlocked)
        XCTAssertFalse(tracker.hasAccessEnded)

        // Expired: StoreKit no longer lists the subscription at all.
        tracker.reconcileStoreEntitlements([], expirationDate: nil)
        XCTAssertFalse(tracker.hasUnlocked)
        XCTAssertTrue(tracker.hasAccessEnded)
        XCTAssertTrue(UsageTracker(defaults: defaults).hasAccessEnded)
    }

    func testPreviousBuildEvidenceMigrates() {
        defaults.set(Date().addingTimeInterval(-60), forKey: "storeAccessExpirationV1")
        defaults.set("individual", forKey: UsageTracker.accessLevelKey)
        let tracker = UsageTracker(defaults: defaults)
        XCTAssertTrue(tracker.hasHadUnlimitedAccess)
        XCTAssertTrue(tracker.hasAccessEnded)
    }

    func testStoreKitEvidenceAfterReinstall() {
        let tracker = UsageTracker(defaults: defaults)
        tracker.recordPreviousUnlimitedAccess()
        XCTAssertTrue(tracker.hasAccessEnded)
        XCTAssertTrue(UsageTracker(defaults: defaults).hasHadUnlimitedAccess)
    }

    func testRestoredAccessIsNotEnded() {
        let tracker = UsageTracker(defaults: defaults)
        tracker.recordPreviousUnlimitedAccess()
        tracker.applyVerifiedPurchase(.individual)
        XCTAssertTrue(tracker.hasUnlocked)
        XCTAssertFalse(tracker.hasAccessEnded)
    }
}
