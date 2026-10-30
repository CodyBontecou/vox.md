import AVFoundation
import StoreKit
import StoreKitTest
import SwiftUI
import UIKit
import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class HardPaywallStoreKitTests: XCTestCase {
    private func makeSession(usesCurrentLifetimePrices: Bool = false) async throws -> SKTestSession {
        var url = try XCTUnwrap(Bundle.main.url(forResource: "Voxboard", withExtension: "storekit"))
        if usesCurrentLifetimePrices {
            // Visual previews must reflect the still-frozen production lifetime
            // prices. The checked-in catalog uses the same held prices.
            var catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            var products = try XCTUnwrap(catalog["products"] as? [[String: Any]])
            for index in products.indices {
                let id = products[index]["productID"] as? String
                products[index]["displayPrice"] = id == VoxboardPurchaseProduct.family.rawValue ? "39.99" : "19.99"
            }
            catalog["products"] = products
            url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).storekit")
            try JSONSerialization.data(withJSONObject: catalog).write(to: url)
            let temporaryURL = url
            addTeardownBlock { try? FileManager.default.removeItem(at: temporaryURL) }
        }
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.timeRate = .realTime
        session.clearTransactions()
        addTeardownBlock { session.clearTransactions() }
        // Fail fast if app startup bound StoreKit to Sandbox before the fixture.
        // Matching live prices alone cannot prove this is a local test session.
        switch try await AppTransaction.shared {
        case .verified(let transaction):
            _ = try XCTUnwrap(transaction.environment == .xcode ? transaction : nil,
                "Run the StoreKit suite with the isolated VoxboardStoreKit test plan.")
        case .unverified(_, let error):
            throw error
        }
        return session
    }

    /// The CLI installs the local catalog/trust material for a fresh simulator
    /// during this separate setup invocation. Purchase tests then run in a new
    /// host process and still require verified Xcode transactions.
    func testStoreKitFixtureActivation() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Voxboard", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [VoxboardPurchaseProduct.individualWeekly.rawValue])
        let product = try XCTUnwrap(products.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: product.jsonRepresentation) as? [String: Any])
        // This is the local fixture ID, not Apple's numeric storefront ID.
        XCTAssertEqual(json["id"] as? String, "individual-weekly")
    }

    private func makeTracker() -> UsageTracker {
        let suite = "HardPaywallStoreKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return UsageTracker(defaults: defaults)
    }

    func testCatalogPricesTrialsAndFamilyOptions() async throws {
        let session = try await makeSession()
        defer { withExtendedLifetime(session) {} }
        let tracker = makeTracker()
        let store = StoreManager(usageTracker: tracker)
        await store.loadProducts()
        // Parse exact decimal prices rather than round-tripping binary floats.
        let prices: [VoxboardPurchaseProduct: String] = [
            .individualWeekly: "0.99", .individualYearly: "29.99", .individual: "19.99",
            .familyWeekly: "1.99", .familyYearly: "49.99", .family: "39.99",
            .familyUpgrade: "19.99",
        ]
        for (id, price) in prices {
            let product = try XCTUnwrap(store.product(for: id))
            XCTAssertEqual(product.price, try XCTUnwrap(Decimal(string: price, locale: Locale(identifier: "en_US_POSIX"))))
            XCTAssertEqual(product.isFamilyShareable, id.grantedAccessLevel == .family)
            XCTAssertEqual(store.offersFreeTrial(id), id.isSubscription)
        }
        XCTAssertTrue(tracker.isAtLimit)
        XCTAssertTrue(tracker.isCaptureAtLimit)
    }

    func testCancelPendingAndOfflineRestoreKeepFreshUserLocked() async throws {
        let session = try await makeSession()
        let tracker = makeTracker()
        let store = StoreManager(usageTracker: tracker)
        await store.prepareForPurchases()
        XCTAssertTrue(store.isEntitlementStateReady)
        XCTAssertFalse(tracker.hasUnlocked)
        try await session.setSimulatedError(SKTestFailures.Purchase.generic(.userCancelled), forAPI: .purchase)
        await store.purchase(.individualWeekly)
        XCTAssertFalse(tracker.hasUnlocked)
        try await session.setSimulatedError(nil, forAPI: .purchase)
        session.askToBuyEnabled = true
        await store.purchase(.individualWeekly)
        XCTAssertFalse(tracker.hasUnlocked)
        session.askToBuyEnabled = false
        try await session.setSimulatedError(SKTestFailures.AppStoreSync.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync)
        await store.restorePurchases()
        XCTAssertFalse(tracker.hasUnlocked)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.lastRestoreDiagnostics?.syncSucceeded, false)
    }

    func testRestoreRecoversFamilyLifetimeIntoFreshLocalState() async throws {
        let session = try await makeSession()
        try await session.buyProduct(identifier: VoxboardPurchaseProduct.family.rawValue)
        let tracker = makeTracker()
        XCTAssertFalse(tracker.hasUnlocked)
        let store = StoreManager(usageTracker: tracker)
        await store.restorePurchases()
        XCTAssertTrue(tracker.hasFamilyAccess, store.errorMessage ?? "Family Lifetime must restore")
        XCTAssertEqual(store.lastRestoreDiagnostics?.syncSucceeded, true)
    }

    func testTrialPurchaseAndRefundThroughStoreManager() async throws {
        let session = try await makeSession()
        let tracker = makeTracker()
        let store = StoreManager(usageTracker: tracker)
        await store.prepareForPurchases()
        XCTAssertFalse(tracker.hasUnlocked)
        await store.purchase(.familyYearly)
        XCTAssertTrue(tracker.hasFamilyAccess, store.errorMessage ?? "Family trial must unlock access")
        let transaction = try XCTUnwrap(session.allTransactions().last)
        try session.refundTransaction(identifier: transaction.identifier)
        for _ in 0..<50 {
            await store.syncCurrentEntitlements()
            if !tracker.hasUnlocked { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(tracker.hasUnlocked)
    }

    func testPaywallLayoutLightDarkAndLargeType() async throws {
        let session = try await makeSession(usesCurrentLifetimePrices: true)
        defer { withExtendedLifetime(session) {} }
        let tracker = makeTracker()
        let store = StoreManager(usageTracker: tracker)
        await store.prepareForPurchases()
        XCTAssertTrue(store.isEntitlementStateReady)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let model = QuickCaptureViewModel(captureRootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let controller = UIHostingController(rootView: AnyView(PaywallView(isAccessGate: true, historyViewModel: model)
            .environment(tracker).environment(store)))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for (name, style, category, family) in [
            ("paywall-individual-review", UIUserInterfaceStyle.light, UIContentSizeCategory.large, false),
            ("paywall-family-review", .light, .large, true),
            ("paywall-dark", .dark, .large, false),
            ("paywall-large-type", .light, .accessibilityExtraExtraExtraLarge, false),
        ] {
            controller.rootView = AnyView(PaywallView(isAccessGate: true, historyViewModel: model, initialFamily: family)
                .environment(tracker).environment(store).id(name))
            window.overrideUserInterfaceStyle = style
            controller.traitOverrides.preferredContentSizeCategory = category
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testUnpaidHistoryCanExportExistingTranscriptWithoutUnlocking() async throws {
        let tracker = makeTracker()
        let transcript = Transcript(text: "Existing history remains available without a subscription.", duration: 12, modelUsed: "fixture", language: "en")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try TranscriptFileExporter.export(transcript, format: .md, mode: .newFile, folderURL: root)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains(transcript.text))
        XCTAssertTrue(tracker.isAtLimit)
        XCTAssertTrue(tracker.isCaptureAtLimit)
        let model = QuickCaptureViewModel(captureRootURL: root)
        let view = HistoryView(viewModel: model, isReadOnly: true)
        XCTAssertTrue(view.isReadOnly)
        let historyStore = TranscriptStore()
        historyStore.add(transcript)
        defer { historyStore.delete(ids: [transcript.id]) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view.environment(historyStore))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(historyStore.transcripts.contains { $0.id == transcript.id })
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "unpaid-existing-history"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(tracker.isAtLimit)
    }

    func testOnboardingPresentationLightDarkAndLargeType() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: ThoughtfulOnboarding(onFinish: {}))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for (name, page, style, size) in [
            ("welcome-light", 0, UIUserInterfaceStyle.light, UIContentSizeCategory.large),
            ("privacy-light", 2, .light, .large),
            ("voice-light", 1, .light, .large),
            ("voice-large-type", 1, .light, .accessibilityExtraExtraExtraLarge),
            ("welcome-dark", 0, .dark, .large),
            ("privacy-dark", 2, .dark, .large),
            ("welcome-large-type", 0, .light, .accessibilityExtraExtraExtraLarge),
            ("privacy-large-type", 2, .light, .accessibilityExtraExtraExtraLarge),
            ("welcome-dark-large-type", 0, .dark, .accessibilityExtraExtraExtraLarge),
        ] {
            controller.rootView = ThoughtfulOnboarding(onFinish: {}, initialPage: page)
            window.overrideUserInterfaceStyle = style
            controller.traitOverrides.preferredContentSizeCategory = size
            try await Task.sleep(for: .milliseconds(400))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testOnboardingTransparentFooterOverScrolledContent() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true }
        for (name, style, highContrast) in [
            ("transparent-footer-light", UIUserInterfaceStyle.light, false),
            ("transparent-footer-dark", .dark, false),
            ("transparent-footer-increased-contrast", .light, true),
        ] {
            let controller = UIHostingController(rootView: ThoughtfulOnboarding(onFinish: {}))
            controller.traitOverrides.accessibilityContrast = highContrast ? .high : .normal
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = style
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            let scroll = try XCTUnwrap(firstScrollView(in: try XCTUnwrap(window.rootViewController).view))
            XCTAssertGreaterThan(scroll.bounds.height, window.bounds.height * 0.7,
                                 "The transparent footer must preserve the scrolling canvas")
            scroll.setContentOffset(CGPoint(x: 0, y: 180), animated: false)
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testOnboardingOnSmallPhoneAtLargestTextSize() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        defer { window.isHidden = true }
        for page in [0, 1, 2] {
            window.rootViewController = UIHostingController(rootView:
                ThoughtfulOnboarding(onFinish: {}, initialPage: page)
                    .environment(\.dynamicTypeSize, .accessibility5))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            let scroll = try XCTUnwrap(firstScrollView(in: try XCTUnwrap(window.rootViewController).view))
            XCTAssertGreaterThan(scroll.bounds.height, window.bounds.height * 0.6,
                                 "Large-text footer must not consume the reading area")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "onboarding-small-largest-page-\(page)"
            attachment.lifetime = .keepAlways
            add(attachment)
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
            try await Task.sleep(for: .milliseconds(200))
            let bottom = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let bottomAttachment = XCTAttachment(image: bottom)
            bottomAttachment.name = "onboarding-small-largest-actions-page-\(page)"
            bottomAttachment.lifetime = .keepAlways
            add(bottomAttachment)
        }
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.firstScrollView(in: $0) }.first
    }

    /// Opt-in, simulator-only manual motion pass. The sentinel is outside the
    /// repository; ordinary test runs skip instead of pausing for interaction.
    func testInteractiveDesignPreview() async throws {
        #if targetEnvironment(simulator)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/vox-thoughtful-design-preview"))
        let session = try await makeSession(usesCurrentLifetimePrices: true)
        defer { withExtendedLifetime(session) {} }
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Thoughtful.introductionKey)
        defaults.set(false, forKey: Thoughtful.introductionKey)
        defer {
            if let previous { defaults.set(previous, forKey: Thoughtful.introductionKey) }
            else { defaults.removeObject(forKey: Thoughtful.introductionKey) }
        }
        let tracker = makeTracker()
        let store = StoreManager(usageTracker: tracker)
        await store.prepareForPurchases()
        let model = QuickCaptureViewModel(captureRootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        let previewMode = (try? String(contentsOfFile: "/tmp/vox-thoughtful-design-preview", encoding: .utf8)) ?? ""
        window.rootViewController = UIHostingController(rootView: PaywallView(isAccessGate: true, historyViewModel: model, includesOnboarding: true)
            .environment(tracker).environment(store).environment(TranscriptStore())
            .environment(\.dynamicTypeSize, previewMode.contains("large-type") ? .accessibility5 : .large))
        window.rootViewController?.view.accessibilityViewIsModal = true
        window.accessibilityViewIsModal = true
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        print("[ThoughtfulPreview] READY FOR NATIVE INTERACTION")
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline && FileManager.default.fileExists(atPath: "/tmp/vox-thoughtful-design-preview") {
            try await Task.sleep(for: .seconds(1))
        }
        XCTAssertTrue(tracker.isAtLimit, "Preview must not buy anything")
        #else
        throw XCTSkip("Simulator-only preview")
        #endif
    }

    /// Opt-in local UI exercise. No production purchase, notes, or account is
    /// used. The writer is isolated/unmetered; paid access is supplied by StoreKitTest.
    func testInteractiveFirstNotePreview() async throws {
        #if targetEnvironment(simulator)
        let sentinel = "/tmp/vox-first-note-preview"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sentinel))
        let session = try await makeSession()
        defer { withExtendedLifetime(session) {} }
        let tracker = makeTracker()
        let store = StoreManager(usageTracker: tracker)
        try await session.buyProduct(identifier: VoxboardPurchaseProduct.individual.rawValue)
        await store.prepareForPurchases()
        XCTAssertTrue(tracker.hasUnlocked)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FirstNotePreview-\(UUID().uuidString)")
        let suite = "FirstNotePreview-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let sharedDefaults = try XCTUnwrap(AppConstants.sharedDefaults)
        let previous = sharedDefaults.object(forKey: CapturePreferenceKeys.firstNoteSaved)
        sharedDefaults.set(false, forKey: CapturePreferenceKeys.firstNoteSaved)
        defer {
            if let previous { sharedDefaults.set(previous, forKey: CapturePreferenceKeys.firstNoteSaved) }
            else { sharedDefaults.removeObject(forKey: CapturePreferenceKeys.firstNoteSaved) }
        }
        let initialPermission = AVAudioApplication.shared.recordPermission
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline())
        let previewMode = (try? String(contentsOfFile: sentinel, encoding: .utf8)) ?? ""
        if previewMode.contains("ready-to-send") {
            let folder = root.appendingPathComponent("Preview Notes")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            await model.load()
            try await model.setUpFirstNoteFolder(folder)
            model.draft.text = "My first onboarding note"
        }
        let transcripts = TranscriptStore()
        let recorder = PersistentRecorder(transcriptStore: transcripts, usageTracker: tracker,
            transcriptionService: AppTranscriptionServices.shared,
            recordingJobStore: RecordingJobStore(rootDirectoryURL: root.appendingPathComponent("jobs")))
        let watch = WatchRecordingPipeline(transcriptStore: transcripts, usageTracker: tracker,
            transcriptionService: AppTranscriptionServices.shared, transcriptEnricher: nil)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .normal + 1
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            QuickCaptureView(viewModel: model, persistentRecorder: recorder,
                pendingKeyboardLaunch: .constant(false), pendingWidgetRecord: .constant(false),
                captureToolbarPreferences: CaptureToolbarPreferences(defaults: defaults), openSettings: {})
        }.environment(tracker).environment(store).environment(transcripts)
            .environment(watch).environment(ModelManager()))
        window.rootViewController?.view.accessibilityViewIsModal = true
        window.accessibilityViewIsModal = true
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        print("[FirstNotePreview] READY FOR NATIVE INTERACTION")
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline && FileManager.default.fileExists(atPath: sentinel) {
            try await Task.sleep(for: .seconds(1))
        }
        let receipt = try XCTUnwrap(model.lastReceipt, "Exercise folder selection, typing and Send before ending the preview")
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.noteURL.path))
        XCTAssertTrue(try String(contentsOf: receipt.noteURL, encoding: .utf8).contains("My first onboarding note"))
        XCTAssertEqual(AVAudioApplication.shared.recordPermission, initialPermission, "Typing must not request microphone access")
        let attachment = XCTAttachment(contentsOfFile: receipt.noteURL)
        attachment.name = "first-note-written-by-real-capture-ui.md"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? FileManager.default.removeItem(at: receipt.noteURL)
        #else
        throw XCTSkip("Simulator-only preview")
        #endif
    }

    func testSubscriptionExpirationRelocksButLifetimeSurvives() async throws {
        let session = try await makeSession()
        let tracker = makeTracker()
        let store = StoreManager(usageTracker: tracker)
        try await session.buyProduct(identifier: VoxboardPurchaseProduct.individualWeekly.rawValue)
        await store.syncCurrentEntitlements()
        XCTAssertTrue(tracker.hasUnlocked)
        XCTAssertFalse(tracker.isEligibleForFamilyUpgrade)

        for transaction in session.allTransactions() {
            try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        }
        try session.expireSubscription(productIdentifier: VoxboardPurchaseProduct.individualWeekly.rawValue)
        // StoreKit publishes subscription expiration asynchronously.
        for _ in 0..<50 {
            await store.syncCurrentEntitlements()
            if !tracker.hasUnlocked { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if tracker.hasUnlocked {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    print("[HardPaywallTest] current=\(transaction.productID) expiration=\(String(describing: transaction.expirationDate)) now=\(Date())")
                }
            }
        }
        XCTAssertFalse(tracker.hasUnlocked)
        XCTAssertTrue(tracker.isCaptureAtLimit)

        try await session.buyProduct(identifier: VoxboardPurchaseProduct.individual.rawValue)
        // StoreKit also publishes a new lifetime entitlement asynchronously.
        // Wait for that delivery, just as above for subscription expiration.
        for _ in 0..<50 {
            await store.syncCurrentEntitlements()
            if tracker.hasUnlocked && tracker.isEligibleForFamilyUpgrade { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(tracker.hasUnlocked)
        XCTAssertTrue(tracker.isEligibleForFamilyUpgrade)
    }
}
