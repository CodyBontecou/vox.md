import Foundation
import StoreKit
import VoxboardShared

/// StoreKit 2 manager for subscriptions and lifetime purchases.
@Observable
@MainActor
final class MacStoreManager {
    static let unlockProductID = VoxboardPurchaseProduct.individual.rawValue
    static let familyProductID = VoxboardPurchaseProduct.family.rawValue
    static let familyUpgradeProductID = VoxboardPurchaseProduct.familyUpgrade.rawValue

    private(set) var productsByID: [String: Product] = [:]
    private(set) var trialEligibleProductIDs: Set<String> = []

    func offersFreeTrial(_ product: VoxboardPurchaseProduct) -> Bool {
        trialEligibleProductIDs.contains(product.rawValue)
    }
    private(set) var isEntitlementStateReady = false
    var purchasingProductID: String?
    var isRestoring = false
    var errorMessage: String?
    private(set) var lastRestoreDiagnostics: PurchaseRestoreDiagnostics?

    var isPurchasing: Bool { purchasingProductID != nil }
    var product: Product? { product(for: .individual) }
    var familyProduct: Product? { product(for: .family) }
    var familyUpgradeProduct: Product? { product(for: .familyUpgrade) }

    private let usageTracker: UsageTracker
    @ObservationIgnored private var transactionListenerTask: Task<Void, Never>?
    @ObservationIgnored private var lastEntitlementObservations: [PurchaseEntitlementObservation] = []

    init(usageTracker: UsageTracker) {
        self.usageTracker = usageTracker
    }

    func start() {
        if usageTracker.isLegacyAccessClassificationPending {
            // The original paid-app migration was iOS-only. Mac access must be
            // backed by a current StoreKit transaction.
            usageTracker.completeLegacyAccessClassification(isOriginalPaidAppOwner: false)
        }
        if transactionListenerTask == nil {
            transactionListenerTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self,
                          case .verified(let transaction) = result,
                          let product = VoxboardPurchaseProduct(rawValue: transaction.productID) else {
                        continue
                    }
                    await transaction.finish()
                    let additionalProducts = transaction.revocationDate == nil ? [product] : []
                    await self.syncCurrentEntitlements(including: additionalProducts)
                }
            }
        }
        Task { await prepareForPurchases() }
    }

    func prepareForPurchases() async {
        await syncCurrentEntitlements()
        await loadProducts()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(
                for: VoxboardPurchaseProduct.allCases.map(\.rawValue)
            )
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            trialEligibleProductIDs = []
            for product in products {
                if let subscription = product.subscription,
                   let offer = subscription.introductoryOffer,
                   offer.paymentMode == .freeTrial,
                   offer.periodCount == 1,
                   ((offer.period.unit == .day && offer.period.value == 7)
                    || (offer.period.unit == .week && offer.period.value == 1)),
                   await subscription.isEligibleForIntroOffer {
                    trialEligibleProductIDs.insert(product.id)
                }
            }
            let hasMissingOffer = usageTracker.purchaseOptions.contains {
                productsByID[$0.rawValue] == nil
            }
            errorMessage = hasMissingOffer
                ? "Some purchase options are temporarily unavailable."
                : nil
        } catch {
            errorMessage = String(localized: "Could not load purchases: \(error.localizedDescription)")
        }
    }

    func product(for purchaseProduct: VoxboardPurchaseProduct) -> Product? {
        productsByID[purchaseProduct.rawValue]
    }

    func displayPrice(for purchaseProduct: VoxboardPurchaseProduct) -> String? {
        product(for: purchaseProduct)?.displayPrice
    }

    var displayPrice: String? { displayPrice(for: .individual) }
    var familyDisplayPrice: String? { displayPrice(for: .family) }
    var familyUpgradeDisplayPrice: String? { displayPrice(for: .familyUpgrade) }

    func purchase(
        _ purchaseProduct: VoxboardPurchaseProduct,
        context: PaywallContext = .settings
    ) async {
        guard !isPurchasing, !isRestoring else { return }
        purchasingProductID = purchaseProduct.rawValue
        defer { purchasingProductID = nil }
        // Resolve reinstall, refund, and Family Sharing changes before applying
        // the discounted-upgrade eligibility rule.
        await syncCurrentEntitlements()

        guard usageTracker.purchaseOptions.contains(purchaseProduct) else {
            errorMessage = purchaseProduct == .familyUpgrade
                ? String(localized: "The Family upgrade is available to existing Unlimited owners.")
                : String(localized: "This purchase is not available for your current access level.")
            return
        }

        guard let product = product(for: purchaseProduct) else {
            errorMessage = String(localized: "Purchase is not available right now.")
            return
        }

        errorMessage = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                do {
                    let transaction = try checkVerified(verification)
                    guard let verifiedProduct = VoxboardPurchaseProduct(rawValue: transaction.productID) else {
                        throw MacStoreError.unrecognizedProduct
                    }
                    guard transaction.revocationDate == nil, !transaction.isUpgraded,
                          transaction.expirationDate.map({ $0 > Date() }) ?? true else {
                        throw MacStoreError.unrecognizedProduct
                    }
                    usageTracker.applyVerifiedPurchase(verifiedProduct)
                    await transaction.finish()
                    await syncCurrentEntitlements(including: [verifiedProduct])
                } catch {
                    errorMessage = String(localized: "Purchase verification failed.")
                }
            case .pending:
                errorMessage = String(localized: "Purchase pending approval.")
            case .userCancelled:
                break
            @unknown default:
                errorMessage = String(localized: "Unknown purchase result.")
            }
        } catch {
            errorMessage = String(localized: "Purchase failed: \(error.localizedDescription)")
        }
    }

    /// Backward-compatible entry point for the original individual unlock.
    func purchase() async {
        await purchase(.individual)
    }

    func restore() async {
        guard !isRestoring, !isPurchasing else { return }
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            let restoredProducts = await syncCurrentEntitlements()
            let restored = !restoredProducts.isEmpty || usageTracker.hasUnlocked

            if !restored {
                errorMessage = String(localized: "No Vox.md Unlimited purchase was found.")
            }
            await recordRestoreDiagnostics(syncSucceeded: true, syncError: nil)
        } catch {
            errorMessage = String(localized: "Restore failed: \(error.localizedDescription)")
            await recordRestoreDiagnostics(
                syncSucceeded: false,
                syncError: String(describing: type(of: error))
            )
        }
    }

    @discardableResult
    func syncCurrentEntitlements(
        including additionalProducts: [VoxboardPurchaseProduct] = []
    ) async -> [VoxboardPurchaseProduct] {
        var currentProducts = additionalProducts.filter { !$0.isSubscription }
        var expirationDates: [Date] = []
        var observations: [PurchaseEntitlementObservation] = []

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                let product = VoxboardPurchaseProduct(rawValue: transaction.productID)
                observations.append(PurchaseEntitlementObservation(
                    productID: transaction.productID,
                    isVerified: true,
                    isRecognized: product != nil,
                    isRevoked: transaction.revocationDate != nil,
                    isUpgraded: transaction.isUpgraded,
                    ownershipType: String(describing: transaction.ownershipType),
                    environment: String(describing: transaction.environment)
                ))
                guard transaction.revocationDate == nil, !transaction.isUpgraded,
                      transaction.expirationDate.map({ $0 > Date() }) ?? true,
                      let product else { continue }
                if let expiration = transaction.expirationDate { expirationDates.append(expiration) }
                if !currentProducts.contains(product) {
                    currentProducts.append(product)
                }
                await transaction.finish()
            case .unverified(let transaction, let error):
                observations.append(PurchaseEntitlementObservation(
                    productID: transaction.productID,
                    isVerified: false,
                    isRecognized: VoxboardPurchaseProduct(rawValue: transaction.productID) != nil,
                    isRevoked: transaction.revocationDate != nil,
                    isUpgraded: transaction.isUpgraded,
                    ownershipType: String(describing: transaction.ownershipType),
                    environment: String(describing: transaction.environment),
                    verificationError: String(describing: type(of: error))
                ))
            }
        }

        lastEntitlementObservations = observations
        usageTracker.reconcileStoreEntitlements(currentProducts, expirationDate: expirationDates.max())
        isEntitlementStateReady = true
        return currentProducts
    }

    private func recordRestoreDiagnostics(syncSucceeded: Bool, syncError: String?) async {
        let storefront = await Storefront.current
        var observations = lastEntitlementObservations
        for product in VoxboardPurchaseProduct.allCases
        where !observations.contains(where: { $0.productID == product.rawValue }) {
            guard let latest = await Transaction.latest(for: product.rawValue) else { continue }
            switch latest {
            case .verified(let transaction):
                observations.append(PurchaseEntitlementObservation(
                    productID: transaction.productID,
                    isVerified: true,
                    isRecognized: true,
                    isRevoked: transaction.revocationDate != nil,
                    isUpgraded: transaction.isUpgraded,
                    ownershipType: String(describing: transaction.ownershipType),
                    environment: String(describing: transaction.environment)
                ))
            case .unverified(let transaction, let error):
                observations.append(PurchaseEntitlementObservation(
                    productID: transaction.productID,
                    isVerified: false,
                    isRecognized: true,
                    isRevoked: transaction.revocationDate != nil,
                    isUpgraded: transaction.isUpgraded,
                    ownershipType: String(describing: transaction.ownershipType),
                    environment: String(describing: transaction.environment),
                    verificationError: String(describing: type(of: error))
                ))
            }
        }
        let diagnostics = PurchaseRestoreDiagnostics(
            platform: "macOS",
            syncSucceeded: syncSucceeded,
            syncError: syncError,
            requestedProductIDs: VoxboardPurchaseProduct.allCases.map(\.rawValue),
            loadedProductIDs: Array(productsByID.keys),
            storefrontCountryCode: storefront?.countryCode,
            observations: observations
        )
        lastRestoreDiagnostics = diagnostics
        KeyboardDebugLog.shared.log("[MacStoreManager] Restore diagnostics \(diagnostics.summary)")
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}

private enum MacStoreError: LocalizedError {
    case unrecognizedProduct

    var errorDescription: String? {
        String(localized: "The transaction did not match a Vox.md product")
    }
}
