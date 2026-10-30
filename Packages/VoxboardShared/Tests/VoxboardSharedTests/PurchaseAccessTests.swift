import XCTest
@testable import VoxboardShared

final class PurchaseAccessTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PurchaseAccessTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNewUserStartsFreeAndSeesIndividualAndFamilyProducts() {
        let tracker = UsageTracker(defaults: defaults)

        XCTAssertEqual(tracker.accessLevel, .free)
        XCTAssertFalse(tracker.hasUnlocked)
        XCTAssertEqual(
            VoxboardPurchaseProduct.purchaseOptions(for: tracker.accessLevel),
            [.individualWeekly, .individualYearly, .individual, .familyWeekly, .familyYearly, .family]
        )
    }

    func testNewAndExistingFreeUsersAreBlockedBeforeAnyUsage() {
        let tracker = UsageTracker(defaults: defaults)
        XCTAssertTrue(tracker.isAtLimit)
        XCTAssertTrue(tracker.isCaptureAtLimit)
        XCTAssertEqual(tracker.secondsRemaining, 0)
        XCTAssertEqual(tracker.capturesRemaining, 0)
        XCTAssertTrue(tracker.fractionUsed.isFinite)
        XCTAssertTrue(tracker.captureFractionUsed.isFinite)

        tracker.addUsage(seconds: 30)
        let relaunched = UsageTracker(defaults: defaults)
        XCTAssertTrue(relaunched.isAtLimit)
        XCTAssertTrue(relaunched.isCaptureAtLimit)
    }

    func testSubscriptionsUnlockButDoNotQualifyForLifetimeFamilyUpgrade() {
        for product in VoxboardPurchaseProduct.allCases where product.isSubscription {
            let tracker = UsageTracker(defaults: defaults)
            tracker.reconcileStoreEntitlements([product], expirationDate: Date().addingTimeInterval(3600))
            XCTAssertTrue(tracker.hasUnlocked)
            XCTAssertFalse(tracker.isAtLimit)
            XCTAssertFalse(tracker.isCaptureAtLimit)
            XCTAssertFalse(tracker.isEligibleForFamilyUpgrade)
            XCTAssertEqual(tracker.hasFamilyAccess, product.grantedAccessLevel == .family)

            tracker.reconcileStoreEntitlements([])
            XCTAssertFalse(tracker.hasUnlocked)
            XCTAssertTrue(tracker.isAtLimit)
        }
    }

    func testExpiredSubscriptionCacheCannotUnlockAfterRelaunch() {
        let tracker = UsageTracker(defaults: defaults)
        tracker.reconcileStoreEntitlements([.familyWeekly], expirationDate: Date().addingTimeInterval(3600))
        XCTAssertTrue(tracker.hasUnlocked)
        defaults.set(Date().addingTimeInterval(-1), forKey: "storeAccessExpirationV1")
        let relaunched = UsageTracker(defaults: defaults)
        XCTAssertFalse(relaunched.hasUnlocked)
        XCTAssertFalse(relaunched.hasFamilyAccess)
        XCTAssertTrue(relaunched.isAtLimit)
    }

    func testFamilySubscriptionExpirationPreservesIndividualLifetime() {
        let tracker = UsageTracker(defaults: defaults)
        tracker.reconcileStoreEntitlements([.individual, .familyYearly], expirationDate: Date().addingTimeInterval(-1))
        XCTAssertEqual(tracker.accessLevel, .individual)
        XCTAssertTrue(tracker.hasUnlocked)
        XCTAssertFalse(tracker.hasFamilyAccess)
        XCTAssertEqual(UsageTracker(defaults: defaults).accessLevel, .individual)
    }

    func testUnboundedSubscriptionGrantIsRejected() {
        let tracker = UsageTracker(defaults: defaults)
        tracker.applyVerifiedPurchase(.individualWeekly)
        XCTAssertFalse(tracker.hasUnlocked)
        tracker.reconcileStoreEntitlements([.individualYearly])
        XCTAssertFalse(tracker.hasUnlocked)
    }

    func testLegacyUnlockedBooleanRemainsProvisionalUntilClassified() {
        defaults.set(true, forKey: UsageTracker.hasUnlockedKey)

        let tracker = UsageTracker(defaults: defaults)
        tracker.reconcileStoreEntitlements([])

        XCTAssertEqual(tracker.accessLevel, .individual)
        XCTAssertTrue(tracker.isLegacyAccessClassificationPending)
        XCTAssertFalse(tracker.isEligibleForFamilyUpgrade)
        XCTAssertTrue(tracker.purchaseOptions.isEmpty)

        tracker.completeLegacyAccessClassification(isOriginalPaidAppOwner: false)
        tracker.reconcileStoreEntitlements([])

        XCTAssertEqual(tracker.accessLevel, .free)
        XCTAssertFalse(tracker.hasUnlocked)
    }

    func testConfirmedPaidAppOwnerKeepsPermanentIndividualAccess() {
        defaults.set(true, forKey: UsageTracker.hasUnlockedKey)
        let tracker = UsageTracker(defaults: defaults)

        tracker.completeLegacyAccessClassification(isOriginalPaidAppOwner: true)
        tracker.reconcileStoreEntitlements([])
        tracker.addUsage(seconds: UsageTracker.freeMinutesLimit * 60 + 1)

        XCTAssertEqual(tracker.accessLevel, .individual)
        XCTAssertFalse(tracker.isLegacyAccessClassificationPending)
        XCTAssertTrue(tracker.isEligibleForFamilyUpgrade)
        XCTAssertFalse(tracker.isAtLimit)
    }

    func testVerifiedIndividualEntitlementQualifiesWhileLegacyClassificationIsPending() {
        defaults.set(true, forKey: UsageTracker.hasUnlockedKey)
        let tracker = UsageTracker(defaults: defaults)

        tracker.reconcileStoreEntitlements([.individual])

        XCTAssertTrue(tracker.isLegacyAccessClassificationPending)
        XCTAssertTrue(tracker.hasCurrentIndividualStoreEntitlement)
        XCTAssertTrue(tracker.isEligibleForFamilyUpgrade)
        XCTAssertEqual(tracker.purchaseOptions, [.familyUpgrade])
    }

    func testLegacyStoreKitOwnerLosesAccessAfterEntitlementRevocation() {
        defaults.set(true, forKey: UsageTracker.hasUnlockedKey)
        let tracker = UsageTracker(defaults: defaults)

        tracker.completeLegacyAccessClassification(isOriginalPaidAppOwner: false)
        tracker.reconcileStoreEntitlements([.individual])
        XCTAssertEqual(tracker.accessLevel, .individual)

        tracker.reconcileStoreEntitlements([])
        XCTAssertEqual(tracker.accessLevel, .free)
        XCTAssertFalse(tracker.hasCurrentIndividualStoreEntitlement)
        XCTAssertFalse(tracker.isEligibleForFamilyUpgrade)
    }

    func testVerifiedFamilyPurchasePersistsAndCanBeReconciledAway() {
        var tracker: UsageTracker? = UsageTracker(defaults: defaults)
        tracker?.applyVerifiedPurchase(.family)

        tracker = UsageTracker(defaults: defaults)
        XCTAssertEqual(tracker?.accessLevel, .family)
        XCTAssertTrue(tracker?.hasFamilyAccess == true)

        tracker?.reconcileStoreEntitlements([])
        XCTAssertEqual(tracker?.accessLevel, .free)
        XCTAssertFalse(tracker?.hasUnlocked == true)
    }

    func testFamilyUpgradeAloneGrantsFamilyAccess() {
        let tracker = UsageTracker(defaults: defaults)

        tracker.reconcileStoreEntitlements([.familyUpgrade])

        XCTAssertEqual(tracker.accessLevel, .family)
        XCTAssertTrue(tracker.hasFamilyAccess)
        XCTAssertTrue(VoxboardPurchaseProduct.purchaseOptions(for: tracker.accessLevel).isEmpty)
    }

    func testFamilyEntitlementWinsThenDowngradesToIndividual() {
        let tracker = UsageTracker(defaults: defaults)

        tracker.reconcileStoreEntitlements([.individual, .family])
        XCTAssertEqual(tracker.accessLevel, .family)

        tracker.reconcileStoreEntitlements([.individual])
        XCTAssertEqual(tracker.accessLevel, .individual)
    }

    func testProductIdentifiersRemainUnchanged() {
        XCTAssertEqual(VoxboardPurchaseProduct.individual.rawValue, "bontecou.Voxboard.unlock")
        XCTAssertEqual(VoxboardPurchaseProduct.family.rawValue, "bontecou.Voxboard.family")
        XCTAssertEqual(VoxboardPurchaseProduct.familyUpgrade.rawValue, "bontecou.Voxboard.familyUpgrade")
    }

    func testStrongestProductSelectionIsDeterministic() {
        XCTAssertEqual(
            VoxboardPurchaseProduct.strongest(in: [.individual, .familyUpgrade]),
            .familyUpgrade
        )
        XCTAssertEqual(
            VoxboardPurchaseProduct.strongest(in: [.familyUpgrade, .family]),
            .family
        )
    }

    func testQueuedUsageReceiptIsExactlyOnceAndSurvivesRelaunch() {
        let deliveryID = UUID()
        var tracker: UsageTracker? = UsageTracker(defaults: defaults)

        tracker?.addUsage(seconds: 42, deliveryID: deliveryID)
        tracker?.addUsage(seconds: 42, deliveryID: deliveryID)
        XCTAssertEqual(tracker?.totalSecondsUsed, 42)

        tracker = UsageTracker(defaults: defaults)
        XCTAssertEqual(tracker?.totalSecondsUsed, 42)
        tracker?.addUsage(seconds: 42, deliveryID: deliveryID)
        XCTAssertEqual(tracker?.totalSecondsUsed, 42)

        tracker?.addUsage(seconds: 8, deliveryID: UUID())
        XCTAssertEqual(tracker?.totalSecondsUsed, 50)
    }

    func testInteractiveUsageAfterQueuedReceiptSurvivesRelaunch() {
        var tracker: UsageTracker? = UsageTracker(defaults: defaults)
        tracker?.addUsage(seconds: 30, deliveryID: UUID())
        tracker?.addUsage(seconds: 12)
        XCTAssertEqual(tracker?.totalSecondsUsed, 42)

        tracker = UsageTracker(defaults: defaults)
        XCTAssertEqual(tracker?.totalSecondsUsed, 42)
        tracker?.addUsage(seconds: 8, deliveryID: UUID())
        XCTAssertEqual(tracker?.totalSecondsUsed, 50)

        tracker = UsageTracker(defaults: defaults)
        XCTAssertEqual(tracker?.totalSecondsUsed, 50)
    }

    func testRestoreDiagnosticsExposeFamilyOwnershipWithoutAccountIdentifiers() {
        let diagnostics = PurchaseRestoreDiagnostics(
            platform: "macOS",
            syncSucceeded: true,
            requestedProductIDs: VoxboardPurchaseProduct.allCases.map(\.rawValue),
            loadedProductIDs: [VoxboardPurchaseProduct.family.rawValue],
            storefrontCountryCode: "US",
            observations: [
                PurchaseEntitlementObservation(
                    productID: VoxboardPurchaseProduct.family.rawValue,
                    isVerified: true,
                    isRecognized: true,
                    isRevoked: false,
                    isUpgraded: false,
                    ownershipType: "familyShared",
                    environment: "production"
                ),
            ]
        )

        XCTAssertTrue(diagnostics.summary.contains("bontecou.Voxboard.family"))
        XCTAssertTrue(diagnostics.summary.contains("familyShared"))
        XCTAssertTrue(diagnostics.summary.contains("storefront=US"))
        XCTAssertFalse(diagnostics.summary.localizedCaseInsensitiveContains("transactionID"))
        XCTAssertFalse(diagnostics.summary.localizedCaseInsensitiveContains("appleAccount"))
    }
}
