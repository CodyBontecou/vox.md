import Foundation
import OSLog
import VoxboardShared
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// When Vox.md may ask the system for an App Store review.
///
/// - At least 5 delivered captures, on at least 2 different local days.
/// - Active access: a subscription, trial or lifetime purchase. Read-only
///   users whose access ended are never asked.
/// - At most once per app version, and never within 90 days of the last
///   request.
/// - Only right after an in-app success the user saw, once nothing else is on
///   screen (no sheet, celebration, paywall, onboarding, release notes or
///   recording). Otherwise the moment is skipped; the next success can try.
///
/// There is no custom pre-prompt: the system decides whether its sheet shows.
struct ReviewPromptPolicy {
    static let deliveredCaptureThreshold = 5
    static let deliveryDayThreshold = 2
    static let cooldown: TimeInterval = 60 * 60 * 24 * 90

    struct State: Equatable {
        var deliveredCaptureCount: Int
        var deliveryDayCount: Int
        var lastRequestedAt: Date?
        var lastRequestedVersion: String?
    }

    /// What is true at the moment a prompt would be shown.
    struct Moment: Equatable {
        var hasActiveAccess: Bool
        var appVersion: String
        /// Nothing else is on screen and the user just saw an in-app success.
        var isPresentationClear: Bool
    }

    enum SkipReason: Equatable {
        case tooFewDeliveredCaptures
        case tooFewDeliveryDays
        case noActiveAccess
        case alreadyRequestedThisVersion
        case coolingDown
        case presentationBlocked
    }

    enum Decision: Equatable {
        case request
        case skip(SkipReason)
    }

    func decide(state: State, moment: Moment, now: Date) -> Decision {
        guard state.deliveredCaptureCount >= Self.deliveredCaptureThreshold else {
            return .skip(.tooFewDeliveredCaptures)
        }
        guard state.deliveryDayCount >= Self.deliveryDayThreshold else {
            return .skip(.tooFewDeliveryDays)
        }
        guard moment.hasActiveAccess else { return .skip(.noActiveAccess) }
        if let lastRequestedVersion = state.lastRequestedVersion,
           lastRequestedVersion == moment.appVersion {
            return .skip(.alreadyRequestedThisVersion)
        }
        if let lastRequestedAt = state.lastRequestedAt,
           now.timeIntervalSince(lastRequestedAt) < Self.cooldown {
            return .skip(.coolingDown)
        }
        guard moment.isPresentationClear else { return .skip(.presentationBlocked) }
        return .request
    }
}

/// Persists review-prompt eligibility in the App Group defaults.
///
/// Every delivery (in-app, keyboard, Share Sheet, widget, Watch, Shortcut)
/// may call `recordDeliveredCapture()`; that only counts. Asking is a separate
/// step the foreground capture screen takes after a success the user saw, via
/// `decision(...)`, SwiftUI's `requestReview`, then `recordReviewRequested()`.
/// Nothing is queued for a later launch.
@MainActor
final class ReviewPromptManager {
    static let shared = ReviewPromptManager()

    enum Keys {
        static let deliveredCaptureCount = "reviewPrompt.deliveredCaptureCount.v2"
        static let deliveryDayIdentifiers = "reviewPrompt.deliveryDayIdentifiers.v2"
        /// Shared with v1 so a prompt made by an earlier version still counts
        /// toward the 90-day cooldown.
        static let lastRequestedAt = "reviewPrompt.lastPromptAttemptAt.v1"
        static let lastRequestedVersion = "reviewPrompt.lastRequestedVersion.v2"

        /// v1 keys, removed on first use of v2.
        static let legacySuccessfulCaptureCount = "reviewPrompt.successfulCaptureCount.v1"
        static let legacySuccessfulTranscriptionCount = "reviewPrompt.successfulTranscriptionCount.v1"
        static let legacyUsageDayIdentifiers = "reviewPrompt.usageDayIdentifiers.v1"
        static let legacyPendingPrompt = "reviewPrompt.pendingPrompt.v1"
    }

    /// Only the most recent days are kept; the policy needs two.
    static let maximumStoredDeliveryDays = 14

    /// How long a success moment waits before it may ask.
    struct Timing: Equatable {
        /// Lets the success feedback land first (the Mac "Sent" toast lasts 2 s).
        var initialDelay: Duration = .seconds(2)
        /// Longest wait for success feedback (Sent toast with Undo, export
        /// toast, closed-note toast) to go away before the moment is skipped.
        var maximumFeedbackWait: Duration = .seconds(8)
        var pollInterval: Duration = .milliseconds(250)
        /// Lets the toast's exit animation finish.
        var settleDelay: Duration = .milliseconds(600)

        static let standard = Timing()
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let appVersion: () -> String
    private let timing: Timing
    private let policy = ReviewPromptPolicy()
    private static let log = Logger(subsystem: "bontecou.Voxboard", category: "ReviewPrompt")

    init(
        defaults: UserDefaults = AppConstants.sharedDefaults ?? .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        appVersion: @escaping () -> String = ReviewPromptManager.bundleAppVersion,
        timing: Timing = .standard
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.appVersion = appVersion
        self.timing = timing
        removeLegacyState()
    }

    nonisolated static func bundleAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var state: ReviewPromptPolicy.State {
        let lastRequestedTime = defaults.double(forKey: Keys.lastRequestedAt)
        return ReviewPromptPolicy.State(
            deliveredCaptureCount: max(0, defaults.integer(forKey: Keys.deliveredCaptureCount)),
            deliveryDayCount: Set(defaults.stringArray(forKey: Keys.deliveryDayIdentifiers) ?? []).count,
            lastRequestedAt: lastRequestedTime > 0 ? Date(timeIntervalSince1970: lastRequestedTime) : nil,
            lastRequestedVersion: defaults.string(forKey: Keys.lastRequestedVersion)
        )
    }

    /// Call once per capture that reached its destination, from any source.
    /// This never asks for a review.
    func recordDeliveredCapture() {
        defaults.set(state.deliveredCaptureCount + 1, forKey: Keys.deliveredCaptureCount)
        recordDeliveryDay(now())
        Self.log.debug("Delivered capture counted: \(self.state.deliveredCaptureCount) on \(self.state.deliveryDayCount) days")
    }

    func decision(hasActiveAccess: Bool, isPresentationClear: Bool) -> ReviewPromptPolicy.Decision {
        policy.decide(
            state: state,
            moment: ReviewPromptPolicy.Moment(
                hasActiveAccess: hasActiveAccess,
                appVersion: appVersion(),
                isPresentationClear: isPresentationClear
            ),
            now: now()
        )
    }

    /// Call right after the review request was actually made.
    func recordReviewRequested() {
        defaults.set(now().timeIntervalSince1970, forKey: Keys.lastRequestedAt)
        defaults.set(appVersion(), forKey: Keys.lastRequestedVersion)
    }

    /// Follows an in-app success the user saw. Waits for its feedback (the
    /// toast) to go, then asks once if the policy allows it and nothing else
    /// is on screen. A blocked moment is skipped, never queued; the next
    /// success can try. Returns `nil` when the task was cancelled first.
    @discardableResult
    func offerAfterVisibleSuccess(
        isShowingSuccessFeedback: @MainActor () -> Bool,
        hasActiveAccess: @MainActor () -> Bool,
        isPresentationClear: @MainActor () -> Bool,
        requestReview: @MainActor () -> Void
    ) async -> ReviewPromptPolicy.Decision? {
        // Nothing to wait for when this success can't lead to a prompt.
        let eligibility = decision(hasActiveAccess: hasActiveAccess(), isPresentationClear: true)
        guard eligibility == .request else {
            Self.log.debug("Review moment skipped: \(String(describing: eligibility))")
            return eligibility
        }
        do {
            try await Task.sleep(for: timing.initialDelay)
            var waited = Duration.zero
            while isShowingSuccessFeedback(), waited < timing.maximumFeedbackWait {
                try await Task.sleep(for: timing.pollInterval)
                waited += timing.pollInterval
            }
            try await Task.sleep(for: timing.settleDelay)
        } catch {
            Self.log.debug("Review moment cancelled")
            return nil
        }
        guard !Task.isCancelled else {
            Self.log.debug("Review moment cancelled")
            return nil
        }
        let decision = decision(
            hasActiveAccess: hasActiveAccess(),
            isPresentationClear: !isShowingSuccessFeedback() && isPresentationClear()
        )
        Self.log.debug("Review moment decided: \(String(describing: decision))")
        guard decision == .request else { return decision }
        requestReview()
        recordReviewRequested()
        return decision
    }

    private func recordDeliveryDay(_ date: Date) {
        var days = defaults.stringArray(forKey: Keys.deliveryDayIdentifiers) ?? []
        let day = dayIdentifier(for: date)
        guard !days.contains(day) else { return }
        days.append(day)
        defaults.set(
            Array(days.suffix(Self.maximumStoredDeliveryDays)),
            forKey: Keys.deliveryDayIdentifiers
        )
    }

    private func dayIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return [components.year, components.month, components.day]
            .map { String($0 ?? 0) }
            .joined(separator: "-")
    }

    /// v1 counted transcriptions before export and captures from the launch
    /// inbox drain, so its counts are not carried over; the counter restarts.
    private func removeLegacyState() {
        for key in [
            Keys.legacySuccessfulCaptureCount,
            Keys.legacySuccessfulTranscriptionCount,
            Keys.legacyUsageDayIdentifiers,
            Keys.legacyPendingPrompt,
        ] where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
    }

    #if DEBUG
    /// `-VoxReviewPromptSeed` (DEBUG only): one delivery short of eligible,
    /// with an earlier delivery day and no previous request, so the next
    /// in-app send can show the system review sheet. Used by the e2e test.
    static let debugSeedArgument = "-VoxReviewPromptSeed"

    func applyDebugSeedIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains(Self.debugSeedArgument) else { return }
        defaults.set(ReviewPromptPolicy.deliveredCaptureThreshold - 1, forKey: Keys.deliveredCaptureCount)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now()) ?? now()
        defaults.set([dayIdentifier(for: yesterday)], forKey: Keys.deliveryDayIdentifiers)
        defaults.removeObject(forKey: Keys.lastRequestedAt)
        defaults.removeObject(forKey: Keys.lastRequestedVersion)
    }
    #endif
}

/// The platform half of "nothing else is on screen": the app is frontmost and
/// its key window shows no sheet, alert, popover or modal.
enum ReviewPromptPresentation {
    @MainActor
    static var keyWindowIsUncovered: Bool {
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else { return false }
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard let window = scenes.lazy.flatMap(\.windows).first(where: \.isKeyWindow),
              let root = window.rootViewController else { return false }
        return root.presentedViewController == nil
        #elseif os(macOS)
        guard NSApp.isActive, NSApp.modalWindow == nil,
              let window = NSApp.keyWindow, !(window is NSPanel) else { return false }
        return window.attachedSheet == nil && window.sheets.isEmpty
        #else
        return false
        #endif
    }
}
