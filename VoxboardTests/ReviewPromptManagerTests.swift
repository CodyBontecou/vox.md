import XCTest
@testable import Voxboard

final class ReviewPromptPolicyTests: XCTestCase {
    private let policy = ReviewPromptPolicy()
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func state(
        captures: Int = 5,
        days: Int = 2,
        lastRequestedAt: Date? = nil,
        lastRequestedVersion: String? = nil
    ) -> ReviewPromptPolicy.State {
        .init(
            deliveredCaptureCount: captures,
            deliveryDayCount: days,
            lastRequestedAt: lastRequestedAt,
            lastRequestedVersion: lastRequestedVersion
        )
    }

    private func moment(
        access: Bool = true,
        version: String = "3.1",
        clear: Bool = true
    ) -> ReviewPromptPolicy.Moment {
        .init(hasActiveAccess: access, appVersion: version, isPresentationClear: clear)
    }

    func testRequestsAtFiveDeliveredCapturesOnTwoDays() {
        XCTAssertEqual(policy.decide(state: state(), moment: moment(), now: now), .request)
    }

    func testFourDeliveredCapturesAreNotEnough() {
        XCTAssertEqual(
            policy.decide(state: state(captures: 4), moment: moment(), now: now),
            .skip(.tooFewDeliveredCaptures)
        )
    }

    func testCapturesOnASingleDayAreNotEnough() {
        XCTAssertEqual(
            policy.decide(state: state(captures: 40, days: 1), moment: moment(), now: now),
            .skip(.tooFewDeliveryDays)
        )
    }

    func testReadOnlyUsersAreNeverAsked() {
        XCTAssertEqual(
            policy.decide(state: state(), moment: moment(access: false), now: now),
            .skip(.noActiveAccess)
        )
    }

    func testAsksAtMostOncePerVersion() {
        let longAgo = now.addingTimeInterval(-ReviewPromptPolicy.cooldown * 3)
        XCTAssertEqual(
            policy.decide(
                state: state(lastRequestedAt: longAgo, lastRequestedVersion: "3.1"),
                moment: moment(version: "3.1"),
                now: now
            ),
            .skip(.alreadyRequestedThisVersion)
        )
        XCTAssertEqual(
            policy.decide(
                state: state(lastRequestedAt: longAgo, lastRequestedVersion: "3.1"),
                moment: moment(version: "3.2"),
                now: now
            ),
            .request
        )
    }

    func testNinetyDayCooldownAppliesAcrossVersions() {
        let eightyNineDaysAgo = now.addingTimeInterval(-60 * 60 * 24 * 89)
        XCTAssertEqual(
            policy.decide(
                state: state(lastRequestedAt: eightyNineDaysAgo, lastRequestedVersion: "3.0"),
                moment: moment(version: "3.1"),
                now: now
            ),
            .skip(.coolingDown)
        )
        let ninetyOneDaysAgo = now.addingTimeInterval(-60 * 60 * 24 * 91)
        XCTAssertEqual(
            policy.decide(
                state: state(lastRequestedAt: ninetyOneDaysAgo, lastRequestedVersion: "3.0"),
                moment: moment(version: "3.1"),
                now: now
            ),
            .request
        )
    }

    func testBlockedPresentationSkipsTheMoment() {
        XCTAssertEqual(
            policy.decide(state: state(), moment: moment(clear: false), now: now),
            .skip(.presentationBlocked)
        )
    }
}

@MainActor
final class ReviewPromptManagerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSince1970: 2_000_000_000)
    private var version = "3.1"
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let instant = ReviewPromptManager.Timing(
        initialDelay: .zero,
        maximumFeedbackWait: .milliseconds(50),
        pollInterval: .milliseconds(5),
        settleDelay: .zero
    )

    override func setUp() async throws {
        suiteName = "ReviewPromptManagerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeManager() -> ReviewPromptManager {
        ReviewPromptManager(
            defaults: defaults,
            calendar: calendar,
            now: { [unowned self] in self.now },
            appVersion: { [unowned self] in self.version },
            timing: instant
        )
    }

    private func deliver(_ count: Int, with manager: ReviewPromptManager) {
        for _ in 0..<count { manager.recordDeliveredCapture() }
    }

    func testCountingDeliveriesNeverAsks() {
        let manager = makeManager()
        deliver(3, with: manager)
        now = now.addingTimeInterval(60 * 60 * 24)
        deliver(10, with: manager)

        // Background sources (keyboard, Share Sheet, widget, Watch, Shortcut)
        // only count: nothing is pending and nothing was requested.
        XCTAssertEqual(manager.state.deliveredCaptureCount, 13)
        XCTAssertEqual(manager.state.deliveryDayCount, 2)
        XCTAssertNil(manager.state.lastRequestedAt)
        XCTAssertNil(defaults.object(forKey: ReviewPromptManager.Keys.legacyPendingPrompt))
    }

    func testDeliveryDaysUseLocalCalendarDays() {
        let manager = makeManager()
        deliver(5, with: manager)
        now = now.addingTimeInterval(60)
        deliver(1, with: manager)
        XCTAssertEqual(manager.decision(hasActiveAccess: true, isPresentationClear: true), .skip(.tooFewDeliveryDays))

        now = now.addingTimeInterval(60 * 60 * 24)
        deliver(1, with: manager)
        XCTAssertEqual(manager.decision(hasActiveAccess: true, isPresentationClear: true), .request)
    }

    func testStoredDeliveryDaysAreBounded() {
        let manager = makeManager()
        for _ in 0..<40 {
            deliver(1, with: manager)
            now = now.addingTimeInterval(60 * 60 * 24)
        }
        XCTAssertEqual(manager.state.deliveryDayCount, ReviewPromptManager.maximumStoredDeliveryDays)
    }

    func testVisibleSuccessAsksOnceThenNotAgainThisVersion() async {
        let manager = makeManager()
        deliver(4, with: manager)
        now = now.addingTimeInterval(60 * 60 * 24)
        deliver(1, with: manager)

        var requests = 0
        let first = await manager.offerAfterVisibleSuccess(
            isShowingSuccessFeedback: { false },
            hasActiveAccess: { true },
            isPresentationClear: { true },
            requestReview: { requests += 1 }
        )
        XCTAssertEqual(first, .request)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(manager.state.lastRequestedAt, now)
        XCTAssertEqual(manager.state.lastRequestedVersion, "3.1")

        deliver(1, with: manager)
        let second = await manager.offerAfterVisibleSuccess(
            isShowingSuccessFeedback: { false },
            hasActiveAccess: { true },
            isPresentationClear: { true },
            requestReview: { requests += 1 }
        )
        XCTAssertEqual(second, .skip(.alreadyRequestedThisVersion))
        XCTAssertEqual(requests, 1)
    }

    func testBlockedMomentIsSkippedAndNotRecorded() async {
        let manager = makeManager()
        deliver(4, with: manager)
        now = now.addingTimeInterval(60 * 60 * 24)
        deliver(1, with: manager)

        var requests = 0
        let blocked = await manager.offerAfterVisibleSuccess(
            isShowingSuccessFeedback: { false },
            hasActiveAccess: { true },
            isPresentationClear: { false },
            requestReview: { requests += 1 }
        )
        XCTAssertEqual(blocked, .skip(.presentationBlocked))
        XCTAssertEqual(requests, 0)
        XCTAssertNil(manager.state.lastRequestedAt)

        // The next success can still ask.
        let next = await manager.offerAfterVisibleSuccess(
            isShowingSuccessFeedback: { false },
            hasActiveAccess: { true },
            isPresentationClear: { true },
            requestReview: { requests += 1 }
        )
        XCTAssertEqual(next, .request)
        XCTAssertEqual(requests, 1)
    }

    func testToastThatNeverLeavesSkipsTheMoment() async {
        let manager = makeManager()
        deliver(4, with: manager)
        now = now.addingTimeInterval(60 * 60 * 24)
        deliver(1, with: manager)

        var requests = 0
        let decision = await manager.offerAfterVisibleSuccess(
            isShowingSuccessFeedback: { true },
            hasActiveAccess: { true },
            isPresentationClear: { true },
            requestReview: { requests += 1 }
        )
        XCTAssertEqual(decision, .skip(.presentationBlocked))
        XCTAssertEqual(requests, 0)
    }

    func testWaitsForTheToastToGoBeforeAsking() async {
        let manager = makeManager()
        deliver(4, with: manager)
        now = now.addingTimeInterval(60 * 60 * 24)
        deliver(1, with: manager)

        var polls = 0
        var toastVisibleWhenAsked: Bool?
        let decision = await manager.offerAfterVisibleSuccess(
            isShowingSuccessFeedback: {
                polls += 1
                return polls < 3
            },
            hasActiveAccess: { true },
            isPresentationClear: { true },
            requestReview: { toastVisibleWhenAsked = polls < 3 }
        )
        XCTAssertEqual(decision, .request)
        XCTAssertEqual(toastVisibleWhenAsked, false)
    }

    func testReadOnlyUserIsNotAsked() async {
        let manager = makeManager()
        deliver(4, with: manager)
        now = now.addingTimeInterval(60 * 60 * 24)
        deliver(1, with: manager)

        var requests = 0
        let decision = await manager.offerAfterVisibleSuccess(
            isShowingSuccessFeedback: { false },
            hasActiveAccess: { false },
            isPresentationClear: { true },
            requestReview: { requests += 1 }
        )
        XCTAssertEqual(decision, .skip(.noActiveAccess))
        XCTAssertEqual(requests, 0)
    }

    func testCancelledMomentDoesNotAsk() async {
        let manager = ReviewPromptManager(
            defaults: defaults,
            calendar: calendar,
            now: { [unowned self] in self.now },
            appVersion: { "3.1" },
            timing: .init(initialDelay: .seconds(30))
        )
        deliver(4, with: manager)
        now = now.addingTimeInterval(60 * 60 * 24)
        deliver(1, with: manager)

        var requests = 0
        let task = Task { @MainActor in
            await manager.offerAfterVisibleSuccess(
                isShowingSuccessFeedback: { false },
                hasActiveAccess: { true },
                isPresentationClear: { true },
                requestReview: { requests += 1 }
            )
        }
        task.cancel()
        let decision = await task.value
        XCTAssertNil(decision)
        XCTAssertEqual(requests, 0)
        XCTAssertNil(manager.state.lastRequestedAt)
    }

    func testLegacyStateIsRemovedButLastPromptKeepsTheCooldown() {
        let previousPrompt = now.addingTimeInterval(-60 * 60 * 24 * 10)
        defaults.set(7, forKey: ReviewPromptManager.Keys.legacySuccessfulCaptureCount)
        defaults.set(12, forKey: ReviewPromptManager.Keys.legacySuccessfulTranscriptionCount)
        defaults.set(["2033-5-17"], forKey: ReviewPromptManager.Keys.legacyUsageDayIdentifiers)
        defaults.set(true, forKey: ReviewPromptManager.Keys.legacyPendingPrompt)
        defaults.set(previousPrompt.timeIntervalSince1970, forKey: ReviewPromptManager.Keys.lastRequestedAt)

        let manager = makeManager()

        XCTAssertNil(defaults.object(forKey: ReviewPromptManager.Keys.legacySuccessfulCaptureCount))
        XCTAssertNil(defaults.object(forKey: ReviewPromptManager.Keys.legacySuccessfulTranscriptionCount))
        XCTAssertNil(defaults.object(forKey: ReviewPromptManager.Keys.legacyUsageDayIdentifiers))
        XCTAssertNil(defaults.object(forKey: ReviewPromptManager.Keys.legacyPendingPrompt))
        XCTAssertEqual(manager.state.deliveredCaptureCount, 0)

        deliver(4, with: manager)
        now = now.addingTimeInterval(60 * 60 * 24)
        deliver(1, with: manager)
        XCTAssertEqual(manager.decision(hasActiveAccess: true, isPresentationClear: true), .skip(.coolingDown))
    }

    func testMalformedPersistedValuesFallBackSafely() {
        defaults.set("not-an-int", forKey: ReviewPromptManager.Keys.deliveredCaptureCount)
        defaults.set([1, 2], forKey: ReviewPromptManager.Keys.deliveryDayIdentifiers)
        defaults.set("not-a-date", forKey: ReviewPromptManager.Keys.lastRequestedAt)

        let manager = makeManager()
        XCTAssertEqual(manager.state.deliveredCaptureCount, 0)
        XCTAssertEqual(manager.state.deliveryDayCount, 0)
        XCTAssertNil(manager.state.lastRequestedAt)

        manager.recordDeliveredCapture()
        XCTAssertEqual(manager.state.deliveredCaptureCount, 1)
        XCTAssertEqual(manager.state.deliveryDayCount, 1)
    }

    #if DEBUG
    func testDebugSeedLeavesOneDeliveryToGo() {
        let manager = makeManager()
        manager.recordReviewRequested()
        manager.applyDebugSeedIfRequested(arguments: [ReviewPromptManager.debugSeedArgument])

        XCTAssertEqual(manager.decision(hasActiveAccess: true, isPresentationClear: true), .skip(.tooFewDeliveredCaptures))
        manager.recordDeliveredCapture()
        XCTAssertEqual(manager.decision(hasActiveAccess: true, isPresentationClear: true), .request)
    }
    #endif
}
