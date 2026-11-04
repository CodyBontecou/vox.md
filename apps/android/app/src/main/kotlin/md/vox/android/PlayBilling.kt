package md.vox.android

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import md.vox.android.platformservices.UnlimitedAccessRegistry

enum class BillingConnectionPhase { CONNECTING, READY, UNAVAILABLE }

enum class VoxEntitlement { FREE, PENDING, UNLIMITED }

enum class BillingActionOutcome { PURCHASED, PENDING, CANCELLED, RESTORED, NOT_FOUND, UNAVAILABLE, ERROR }

/**
 * Privacy-safe Play evidence retained for restore support. The type cannot hold an account ID,
 * order ID, purchase token, signature, original purchase JSON, price, or purchase timestamp.
 */
data class BillingEntitlementObservation(
    val productID: String,
    val purchaseState: String,
    val isRecognized: Boolean,
    val isAcknowledged: Boolean,
)

data class BillingRestoreDiagnostics(
    val platform: String,
    val syncSucceeded: Boolean,
    val syncError: String?,
    val requestedProductIDs: List<String>,
    val loadedProductIDs: List<String>,
    val observations: List<BillingEntitlementObservation>,
) {
    val summary: String
        get() = buildList {
            add("platform=$platform")
            add("sync=${if (syncSucceeded) "success" else "failure"}")
            syncError?.let { add("syncError=$it") }
            add("storefront=unknown")
            add("requested=[${requestedProductIDs.joinToString(",")}]")
            add("loaded=[${loadedProductIDs.joinToString(",")}]")
            add(
                "entitlements=[${observations.joinToString(";") { observation ->
                    listOf(
                        observation.productID,
                        observation.purchaseState,
                        if (observation.isRecognized) "recognized" else "unknown",
                        if (observation.isAcknowledged) "acknowledged" else "unacknowledged",
                    ).joinToString(",")
                }}]",
            )
        }.joinToString(" ")
}

internal fun billingRestoreDiagnosticsFromPurchases(
    responseCode: Int,
    requestedProductIDs: Collection<String>,
    loadedProductIDs: Collection<String>,
    purchases: Collection<Purchase>,
): BillingRestoreDiagnostics {
    val requested = requestedProductIDs.distinct().sorted()
    val loaded = loadedProductIDs.filter { it in requested }.distinct().sorted()
    val observations = purchases
        .flatMap { purchase ->
            purchase.products.map { productID ->
                BillingEntitlementObservation(
                    productID = productID,
                    purchaseState = purchaseStateCode(purchase.purchaseState),
                    isRecognized = productID in requested,
                    isAcknowledged = purchase.isAcknowledged,
                )
            }
        }
        .sortedWith(compareBy(BillingEntitlementObservation::productID, BillingEntitlementObservation::purchaseState))
    val succeeded = responseCode == BillingClient.BillingResponseCode.OK
    return BillingRestoreDiagnostics(
        platform = "Android",
        syncSucceeded = succeeded,
        syncError = if (succeeded) null else billingResponseCode(responseCode),
        requestedProductIDs = requested,
        loadedProductIDs = loaded,
        observations = observations,
    )
}

private fun purchaseStateCode(state: Int): String = when (state) {
    Purchase.PurchaseState.PURCHASED -> "purchased"
    Purchase.PurchaseState.PENDING -> "pending"
    Purchase.PurchaseState.UNSPECIFIED_STATE -> "unspecified"
    else -> "unknown"
}

@Suppress("DEPRECATION")
private fun billingResponseCode(code: Int): String = when (code) {
    BillingClient.BillingResponseCode.OK -> "ok"
    BillingClient.BillingResponseCode.USER_CANCELED -> "userCanceled"
    BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE -> "serviceUnavailable"
    BillingClient.BillingResponseCode.BILLING_UNAVAILABLE -> "billingUnavailable"
    BillingClient.BillingResponseCode.ITEM_UNAVAILABLE -> "itemUnavailable"
    BillingClient.BillingResponseCode.DEVELOPER_ERROR -> "developerError"
    BillingClient.BillingResponseCode.ERROR -> "error"
    BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> "itemAlreadyOwned"
    BillingClient.BillingResponseCode.ITEM_NOT_OWNED -> "itemNotOwned"
    BillingClient.BillingResponseCode.SERVICE_DISCONNECTED -> "serviceDisconnected"
    BillingClient.BillingResponseCode.SERVICE_TIMEOUT -> "serviceTimeout"
    BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED -> "featureNotSupported"
    BillingClient.BillingResponseCode.NETWORK_ERROR -> "networkError"
    else -> "unknown"
}

internal fun recordBillingRestoreDiagnostics(context: Context, diagnostics: BillingRestoreDiagnostics) {
    PrivacySafeDebugLog.record(
        context,
        PrivacySafeDebugLog.Event.BILLING_RESTORE_CHECKED,
        mapOf(
            "sync" to if (diagnostics.syncSucceeded) "success" else "failure",
            "code" to (diagnostics.syncError ?: "ok"),
            "requested" to diagnostics.requestedProductIDs.joinToString(","),
            "loaded" to diagnostics.loadedProductIDs.joinToString(",").ifBlank { "none" },
            "states" to diagnostics.observations.joinToString(",") { it.purchaseState }.ifBlank { "none" },
        ),
    )
}

data class BillingUiState(
    val connectionPhase: BillingConnectionPhase = BillingConnectionPhase.CONNECTING,
    val entitlement: VoxEntitlement = VoxEntitlement.FREE,
    val formattedPrice: String? = null,
    val productAvailable: Boolean = false,
    val lastCheckedAtEpochMillis: Long? = null,
    val lastOutcome: BillingActionOutcome? = null,
    val statusCode: String? = null,
    val lastRestoreDiagnostics: BillingRestoreDiagnostics? = null,
    val isEntitlementStale: Boolean = false,
    val hasPendingPurchase: Boolean = false,
    val isPurchasing: Boolean = false,
    val isRestoring: Boolean = false,
    /** Plans priced from Play's offers; empty until product details load. */
    val plans: List<VoxPlanOption> = emptyList(),
    val ownsLifetime: Boolean = false,
    val hasActiveSubscription: Boolean = false,
    /** Product ID (not a token) of the active Weekly or Yearly subscription, if any. */
    val activeSubscriptionProductID: String? = null,
) {
    val hasUnlimitedAccess: Boolean get() = entitlement == VoxEntitlement.UNLIMITED

    /** Plans to offer; a hand-built state with only a Lifetime price still shows Lifetime. */
    val purchasablePlans: List<VoxPlanOption>
        get() = plans.ifEmpty {
            listOfNotNull(
                formattedPrice?.takeIf { productAvailable }?.let {
                    VoxPlanOption(VoxPlan.LIFETIME, it, 0L, "", null, null, "")
                },
            )
        }
}

internal fun entitlementForPurchaseStates(states: Collection<Int>): VoxEntitlement = when {
    Purchase.PurchaseState.PURCHASED in states -> VoxEntitlement.UNLIMITED
    Purchase.PurchaseState.PENDING in states -> VoxEntitlement.PENDING
    else -> VoxEntitlement.FREE
}

internal fun isVoxPurchase(purchase: Purchase): Boolean =
    PlayBillingManager.PRODUCT_ID in purchase.products ||
        purchase.products.any { it in PlayBillingManager.SUBSCRIPTION_PRODUCT_IDS }

internal data class VoxOwnership(
    val ownsLifetime: Boolean,
    val activeSubscriptionToken: String?,
    /** Which subscription product (Weekly or Yearly) is active, for plan switching and the manage link. */
    val activeSubscriptionProductID: String? = null,
)

/**
 * Unlimited = an active subscription OR Lifetime. Play's purchase query returns only
 * subscriptions that are currently entitled (active, grace period, or canceled but unexpired).
 */
internal fun voxOwnership(purchases: Collection<Purchase>): VoxOwnership = voxOwnershipFrom(
    purchases.map { purchase -> Triple(purchase.products, purchase.purchaseState, purchase.purchaseToken) },
)

internal fun voxOwnershipFrom(purchases: Collection<Triple<List<String>, Int, String>>): VoxOwnership {
    val purchased = purchases.filter { it.second == Purchase.PurchaseState.PURCHASED }
    val subscription = purchased.firstOrNull { purchase -> purchase.first.any { it in PlayBillingManager.SUBSCRIPTION_PRODUCT_IDS } }
    return VoxOwnership(
        ownsLifetime = purchased.any { PlayBillingManager.PRODUCT_ID in it.first },
        activeSubscriptionToken = subscription?.third,
        activeSubscriptionProductID = subscription?.first?.firstOrNull { it in PlayBillingManager.SUBSCRIPTION_PRODUCT_IDS },
    )
}

internal data class BillingEntitlementDecision(
    val entitlement: VoxEntitlement,
    val hasPendingPurchase: Boolean,
    /** Non-null only when the observation is authoritative enough to replace cached ownership. */
    val authoritativeOwned: Boolean?,
)

internal fun billingEntitlementDecision(
    priorEntitlement: VoxEntitlement,
    states: Collection<Int>,
    authoritativeOwnershipQuery: Boolean,
): BillingEntitlementDecision {
    val purchased = Purchase.PurchaseState.PURCHASED in states
    val pending = Purchase.PurchaseState.PENDING in states
    return when {
        purchased -> BillingEntitlementDecision(
            entitlement = VoxEntitlement.UNLIMITED,
            hasPendingPurchase = false,
            authoritativeOwned = true,
        )
        pending -> BillingEntitlementDecision(
            entitlement = if (priorEntitlement == VoxEntitlement.UNLIMITED) {
                VoxEntitlement.UNLIMITED
            } else {
                VoxEntitlement.PENDING
            },
            hasPendingPurchase = true,
            authoritativeOwned = null,
        )
        authoritativeOwnershipQuery -> BillingEntitlementDecision(
            entitlement = VoxEntitlement.FREE,
            hasPendingPurchase = false,
            authoritativeOwned = false,
        )
        else -> BillingEntitlementDecision(
            entitlement = priorEntitlement,
            hasPendingPurchase = false,
            authoritativeOwned = null,
        )
    }
}

internal fun billingStatusAfterProductQuery(
    existingStatus: String?,
    productStatus: String?,
): String? = existingStatus?.takeIf {
    it == "entitlementCacheUnavailable" || it == "unrecognizedPurchase" || it.startsWith("acknowledge:")
} ?: productStatus

/** Phone-only Play Billing owner; no purchase data enters capture packages or the Wear app. */
class PlayBillingManager private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val entitlementCache = PlayEntitlementCache(appContext, PRODUCT_ID)
    private val cachedEvidence = entitlementCache.read()
    private val cachedEntitlement = if (cachedEvidence?.isOwned == true) {
        VoxEntitlement.UNLIMITED
    } else {
        VoxEntitlement.FREE
    }
    private val mutableState = MutableStateFlow(
        BillingUiState(
            entitlement = cachedEntitlement,
            lastCheckedAtEpochMillis = cachedEvidence?.checkedAtEpochMillis,
            isEntitlementStale = cachedEvidence?.isOwned == true,
        ),
    )
    val state: StateFlow<BillingUiState> = mutableState.asStateFlow()

    private val operations = BillingOperations()
    private val acknowledging = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    @Volatile private var productDetails: ProductDetails? = null
    /** Weekly and Yearly subscription products, keyed by product ID. */
    @Volatile private var subscriptionDetails: Map<String, ProductDetails> = emptyMap()
    /** Held only in memory to switch base plans; never logged, cached or put in UI state. */
    @Volatile private var activeSubscriptionToken: String? = null
    @Volatile private var connectionStarted = false
    @Volatile private var restoreRequested = false

    private val billingClient = BillingClient.newBuilder(appContext)
        .setListener { result, purchases -> onPurchasesUpdated(result, purchases.orEmpty()) }
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder()
                .enableOneTimeProducts()
                .build(),
        )
        .enableAutoServiceReconnection()
        .build()

    init {
        UnlimitedAccessRegistry.update(cachedEntitlement == VoxEntitlement.UNLIMITED)
    }

    fun start() {
        if (billingClient.isReady) {
            queryProduct()
            queryOwnership(restored = consumeRestoreRequest())
            return
        }
        synchronized(this) {
            if (connectionStarted) return
            connectionStarted = true
        }
        mutableState.update { it.copy(connectionPhase = BillingConnectionPhase.CONNECTING, statusCode = null) }
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                connectionStarted = false
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    mutableState.update { it.copy(connectionPhase = BillingConnectionPhase.READY, statusCode = null) }
                    queryProduct()
                    queryOwnership(restored = consumeRestoreRequest())
                } else {
                    publishUnavailable("billingSetup:${result.responseCode}")
                    recordPendingRestoreIfNeeded(result.responseCode)
                }
            }

            override fun onBillingServiceDisconnected() {
                connectionStarted = false
                synchronized(this@PlayBillingManager) {
                    restoreRequested = operations.disconnected() || restoreRequested
                }
                productDetails = null
                subscriptionDetails = emptyMap()
                mutableState.update {
                    it.copy(
                        plans = emptyList(),
                        connectionPhase = BillingConnectionPhase.UNAVAILABLE,
                        lastOutcome = BillingActionOutcome.UNAVAILABLE,
                        statusCode = "billingDisconnected",
                        productAvailable = false,
                        formattedPrice = null,
                        isPurchasing = false,
                        isRestoring = false,
                        isEntitlementStale = it.entitlement == VoxEntitlement.UNLIMITED,
                    )
                }
            }
        })
    }

    fun refresh(restored: Boolean = false) {
        if (restored) {
            synchronized(this) { restoreRequested = true }
            mutableState.update { it.copy(isRestoring = true) }
        }
        mutableState.update { it.copy(lastOutcome = null, statusCode = null) }
        if (!billingClient.isReady) {
            start()
            return
        }
        queryProduct()
        queryOwnership(restored = consumeRestoreRequest())
    }

    fun restore() = refresh(restored = true)

    /** Opens Play's subscription center for the Vox.md subscription. */
    fun manageSubscriptions(activity: Activity) {
        runCatching {
            activity.startActivity(
                android.content.Intent(
                    android.content.Intent.ACTION_VIEW,
                    android.net.Uri.parse(
                        VoxPlayCatalog.manageSubscriptionsUrl(appContext.packageName, mutableState.value.activeSubscriptionProductID),
                    ),
                ),
            )
        }
    }

    fun launchPurchase(activity: Activity, plan: VoxPlan = VoxPlan.LIFETIME) {
        val current = mutableState.value
        if (!current.canPurchase() || !operations.beginPurchase(
                current.entitlement,
                current.hasPendingPurchase,
                upgradeAllowed = current.hasActiveSubscription && !current.ownsLifetime,
            )
        ) return
        val option = current.plans.firstOrNull { it.plan == plan }
        val details = if (plan == VoxPlan.LIFETIME) productDetails else subscriptionDetails[plan.productID]
        val request = voxPurchaseRequest(
            option,
            current.ownsLifetime,
            activeSubscriptionToken,
            current.hasPendingPurchase,
            current.activeSubscriptionProductID,
        )
        val offerToken = when (request) {
            is VoxPurchaseRequest.Lifetime -> request.offerToken
            is VoxPurchaseRequest.NewSubscription -> request.offerToken
            is VoxPurchaseRequest.ReplaceSubscription -> request.offerToken
            is VoxPurchaseRequest.Blocked -> null
        }
        if (!billingClient.isReady || details == null || offerToken.isNullOrBlank()) {
            operations.finishPurchase()
            mutableState.update { it.copy(lastOutcome = BillingActionOutcome.UNAVAILABLE, statusCode = "productUnavailable", isPurchasing = false) }
            refresh()
            return
        }
        mutableState.update { it.copy(isPurchasing = true, lastOutcome = null) }
        val result = runCatching {
            val builder = BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(listOf(BillingFlowParams.ProductDetailsParams.newBuilder()
                    .setProductDetails(details).setOfferToken(offerToken).build()))
            if (request is VoxPurchaseRequest.ReplaceSubscription) {
                builder.setSubscriptionUpdateParams(
                    BillingFlowParams.SubscriptionUpdateParams.newBuilder()
                        .setOldPurchaseToken(request.oldPurchaseToken)
                        .setSubscriptionReplacementMode(
                            BillingFlowParams.SubscriptionUpdateParams.ReplacementMode.WITH_TIME_PRORATION,
                        )
                        .build(),
                )
            }
            billingClient.launchBillingFlow(activity, builder.build())
        }.getOrElse {
            operations.finishPurchase()
            mutableState.update { it.copy(lastOutcome = BillingActionOutcome.ERROR, statusCode = "billingLaunchFailed", isPurchasing = false) }
            return
        }
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            onPurchasesUpdated(result,emptyList())
        }
    }

    fun consumeOutcome() {
        mutableState.update { it.copy(lastOutcome = null, statusCode = null) }
    }

    private fun queryProduct() {
        val generation = synchronized(operations) {
            productDetails = null
            subscriptionDetails = emptyMap()
            mutableState.update { it.copy(productAvailable = false, formattedPrice = null, plans = emptyList()) }
            operations.beginProductQuery()
        }
        val lifetime = QueryProductDetailsParams.Product.newBuilder()
            .setProductId(PRODUCT_ID)
            .setProductType(BillingClient.ProductType.INAPP)
            .build()
        val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(lifetime)).build()
        billingClient.queryProductDetailsAsync(params) { result, detailsResult ->
            synchronized(operations) {
                if (!operations.isCurrentProductQuery(generation)) return@queryProductDetailsAsync
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    productDetails = null
                    mutableState.update {
                        it.copy(
                            productAvailable = false,
                            formattedPrice = null,
                            statusCode = billingStatusAfterProductQuery(
                                existingStatus = it.statusCode,
                                productStatus = "productQuery:${result.responseCode}",
                            ),
                        )
                    }
                } else {
                    productDetails = detailsResult.productDetailsList.firstOrNull {
                        it.productId == PRODUCT_ID && it.oneTimePurchaseOfferDetails?.let { offer ->
                            offer.rentalDetails == null && offer.preorderDetails == null && !offer.offerToken.isNullOrBlank()
                        } == true
                    }
                    publishPlans()
                }
            }
            querySubscriptionProduct(generation)
        }
    }

    /** Weekly and Yearly are separate subscription products; their offers carry prices and trials. */
    private fun querySubscriptionProduct(generation: Long) {
        val subscriptions = SUBSCRIPTION_PRODUCT_IDS.map { productID ->
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(productID)
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        }
        val params = QueryProductDetailsParams.newBuilder().setProductList(subscriptions).build()
        billingClient.queryProductDetailsAsync(params) { result, detailsResult ->
            synchronized(operations) {
                if (!operations.isCurrentProductQuery(generation)) return@queryProductDetailsAsync
                subscriptionDetails = if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    detailsResult.productDetailsList
                        .filter { it.productId in SUBSCRIPTION_PRODUCT_IDS }
                        .associateBy { it.productId }
                } else emptyMap()
                publishPlans()
            }
        }
    }

    private fun publishPlans() {
        val lifetime = productDetails?.oneTimePurchaseOfferDetails?.let { offer ->
            VoxPlanOption(
                plan = VoxPlan.LIFETIME,
                formattedPrice = offer.formattedPrice,
                priceAmountMicros = offer.priceAmountMicros,
                currencyCode = offer.priceCurrencyCode,
                billingPeriod = null,
                freeTrialPeriod = null,
                offerToken = offer.offerToken.orEmpty(),
            )
        }
        val subscriptions = subscriptionPlanOptions(
            subscriptionDetails.values.flatMap { details ->
                details.subscriptionOfferDetails.orEmpty().map { offer -> details.productId to offer }
            }.map { (productID, offer) ->
                PlaySubscriptionOffer(
                    productID = productID,
                    basePlanID = offer.basePlanId,
                    offerID = offer.offerId,
                    offerToken = offer.offerToken,
                    phases = offer.pricingPhases.pricingPhaseList.map { phase ->
                        PlayPricingPhase(
                            formattedPrice = phase.formattedPrice,
                            priceAmountMicros = phase.priceAmountMicros,
                            currencyCode = phase.priceCurrencyCode,
                            billingPeriod = phase.billingPeriod,
                            billingCycleCount = phase.billingCycleCount,
                            isInfiniteRecurring = phase.recurrenceMode == ProductDetails.RecurrenceMode.INFINITE_RECURRING,
                        )
                    },
                )
            },
        )
        val plans = subscriptions + listOfNotNull(lifetime)
        mutableState.update {
            it.copy(
                plans = plans,
                productAvailable = plans.isNotEmpty(),
                formattedPrice = lifetime?.formattedPrice,
                statusCode = billingStatusAfterProductQuery(
                    existingStatus = it.statusCode,
                    productStatus = if (plans.isEmpty()) "productNotConfigured" else null,
                ),
            )
        }
    }

    private fun queryOwnership(restored: Boolean) {
        val generation = operations.beginOwnershipQuery(restored)
        mutableState.update { it.copy(isRestoring = operations.isRestoring()) }
        val lifetimeParams = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
        billingClient.queryPurchasesAsync(lifetimeParams) { lifetimeResult, lifetimePurchases ->
            val subscriptionParams = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()
            billingClient.queryPurchasesAsync(subscriptionParams) { subscriptionResult, subscriptionPurchases ->
                finishOwnershipQuery(generation, lifetimeResult, lifetimePurchases, subscriptionResult, subscriptionPurchases)
            }
        }
    }

    /** Ownership is authoritative only when both the one-time and the subscription queries succeed. */
    private fun finishOwnershipQuery(
        generation: Long,
        lifetimeResult: BillingResult,
        lifetimePurchases: List<Purchase>,
        subscriptionResult: BillingResult,
        subscriptionPurchases: List<Purchase>,
    ) = synchronized(operations) {
        val wasRestoring = operations.finishOwnershipQuery(generation) ?: return@synchronized
        mutableState.update { it.copy(isRestoring = false) }
        val failed = listOf(lifetimeResult, subscriptionResult).firstOrNull { it.responseCode != BillingClient.BillingResponseCode.OK }
        val purchasesResult = lifetimePurchases + subscriptionPurchases
        if (failed != null) {
            publishUnavailable("purchaseQuery:${failed.responseCode}")
            if (wasRestoring) recordRestoreDiagnostics(failed.responseCode, purchasesResult)
            return@synchronized
        }
        val relevant = purchasesResult.filter(::isVoxPurchase)
        val ownership = voxOwnership(relevant)
        val decision = billingEntitlementDecision(
            priorEntitlement = mutableState.value.entitlement,
            states = relevant.map(Purchase::getPurchaseState),
            authoritativeOwnershipQuery = true,
        )
        activeSubscriptionToken = ownership.activeSubscriptionToken
        val checkedAt = System.currentTimeMillis()
        val cachePersisted = decision.authoritativeOwned?.let { owned ->
            entitlementCache.write(owned, checkedAt)
        } ?: true
        UnlimitedAccessRegistry.update(decision.entitlement == VoxEntitlement.UNLIMITED)
        mutableState.update {
            it.copy(
                connectionPhase = BillingConnectionPhase.READY,
                entitlement = decision.entitlement,
                ownsLifetime = ownership.ownsLifetime,
                hasActiveSubscription = ownership.activeSubscriptionToken != null,
                activeSubscriptionProductID = ownership.activeSubscriptionProductID,
                lastCheckedAtEpochMillis = if (decision.authoritativeOwned != null) checkedAt else it.lastCheckedAtEpochMillis,
                lastOutcome = when {
                    decision.hasPendingPurchase -> BillingActionOutcome.PENDING
                    wasRestoring && decision.authoritativeOwned == true -> BillingActionOutcome.RESTORED
                    wasRestoring -> BillingActionOutcome.NOT_FOUND
                    else -> it.lastOutcome
                },
                statusCode = if (cachePersisted) retainedProductStatus(it.statusCode) else "entitlementCacheUnavailable",
                isEntitlementStale = if (decision.authoritativeOwned != null) {
                    false
                } else {
                    it.isEntitlementStale
                },
                hasPendingPurchase = decision.hasPendingPurchase,
            )
        }
        relevant.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED && !it.isAcknowledged }
            .forEach(::acknowledge)
        if (wasRestoring) recordRestoreDiagnostics(BillingClient.BillingResponseCode.OK, purchasesResult)
    }

    private fun consumeRestoreRequest(): Boolean = synchronized(this) {
        val pending = restoreRequested
        restoreRequested = false
        pending
    }

    private fun recordPendingRestoreIfNeeded(responseCode: Int) {
        if (!consumeRestoreRequest()) return
        mutableState.update { it.copy(isRestoring = false) }
        recordRestoreDiagnostics(responseCode, emptyList())
    }

    private fun recordRestoreDiagnostics(responseCode: Int, purchases: Collection<Purchase>) {
        val diagnostics = billingRestoreDiagnosticsFromPurchases(
            responseCode = responseCode,
            requestedProductIDs = listOf(PRODUCT_ID) + SUBSCRIPTION_PRODUCT_IDS,
            loadedProductIDs = listOfNotNull(productDetails?.productId) + subscriptionDetails.keys,
            purchases = purchases,
        )
        mutableState.update { it.copy(lastRestoreDiagnostics = diagnostics) }
        recordBillingRestoreDiagnostics(appContext, diagnostics)
    }

    private fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>) = synchronized(operations) {
        operations.finishPurchase()
        operations.invalidateOwnershipQueries()
        mutableState.update { it.copy(isPurchasing = false) }
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val relevant = purchases.filter(::isVoxPurchase)
                val ownership = voxOwnership(relevant)
                ownership.activeSubscriptionToken?.let { activeSubscriptionToken = it }
                val decision = billingEntitlementDecision(
                    priorEntitlement = mutableState.value.entitlement,
                    states = relevant.map(Purchase::getPurchaseState),
                    authoritativeOwnershipQuery = false,
                )
                val checkedAt = System.currentTimeMillis()
                val cachePersisted = decision.authoritativeOwned?.let { owned ->
                    entitlementCache.write(owned, checkedAt)
                } ?: true
                UnlimitedAccessRegistry.update(decision.entitlement == VoxEntitlement.UNLIMITED)
                mutableState.update {
                    it.copy(
                        connectionPhase = BillingConnectionPhase.READY,
                        entitlement = decision.entitlement,
                        ownsLifetime = it.ownsLifetime || ownership.ownsLifetime,
                        hasActiveSubscription = it.hasActiveSubscription || ownership.activeSubscriptionToken != null,
                        activeSubscriptionProductID = ownership.activeSubscriptionProductID ?: it.activeSubscriptionProductID,
                        lastCheckedAtEpochMillis = if (decision.authoritativeOwned != null) checkedAt else it.lastCheckedAtEpochMillis,
                        lastOutcome = when {
                            decision.authoritativeOwned == true -> BillingActionOutcome.PURCHASED
                            decision.hasPendingPurchase -> BillingActionOutcome.PENDING
                            else -> it.lastOutcome
                        },
                        statusCode = when {
                            !cachePersisted -> "entitlementCacheUnavailable"
                            purchases.isNotEmpty() && relevant.isEmpty() -> "unrecognizedPurchase"
                            else -> retainedProductStatus(it.statusCode)
                        },
                        isEntitlementStale = if (decision.authoritativeOwned == true) false else it.isEntitlementStale,
                        hasPendingPurchase = decision.hasPendingPurchase,
                    )
                }
                relevant.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED && !it.isAcknowledged }
                    .forEach(::acknowledge)
            }
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> queryOwnership(restored = true)
            BillingClient.BillingResponseCode.USER_CANCELED -> mutableState.update {
                it.copy(lastOutcome = BillingActionOutcome.CANCELLED, statusCode = null)
            }
            else -> mutableState.update {
                it.copy(lastOutcome = BillingActionOutcome.ERROR, statusCode = "purchaseUpdate:${result.responseCode}")
            }
        }
        // A callback invalidates older ownership queries; finish any outstanding restore
        // with a new authoritative query instead of losing its diagnostics or busy state.
        if (operations.isRestoring() && result.responseCode != BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) queryOwnership(restored = false)
    }

    private fun acknowledge(purchase: Purchase) {
        if (!acknowledging.add(purchase.purchaseToken)) return
        val params = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
        try {
            billingClient.acknowledgePurchase(params) { result ->
                acknowledging.remove(purchase.purchaseToken)
                mutableState.update {
                    if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                        it.copy(statusCode = it.statusCode?.takeUnless { code -> code.startsWith("acknowledge:") })
                    } else it.copy(statusCode = "acknowledge:${result.responseCode}")
                }
            }
        } catch (_: Exception) {
            acknowledging.remove(purchase.purchaseToken)
            mutableState.update { it.copy(statusCode = "acknowledge:unavailable") }
        }
    }

    private fun publishUnavailable(code: String) {
        mutableState.update {
            it.copy(
                connectionPhase = BillingConnectionPhase.UNAVAILABLE,
                lastOutcome = BillingActionOutcome.UNAVAILABLE,
                statusCode = code,
                isEntitlementStale = it.entitlement == VoxEntitlement.UNLIMITED,
            )
        }
    }

    private fun retainedProductStatus(statusCode: String?): String? =
        statusCode?.takeIf { it == "productNotConfigured" || it.startsWith("productQuery:") }

    companion object {
        /** Lifetime one-time product; also the key that binds the signed entitlement cache. */
        const val PRODUCT_ID = VoxPlayCatalog.LIFETIME_PRODUCT_ID
        val SUBSCRIPTION_PRODUCT_IDS: List<String> = VoxPlayCatalog.SUBSCRIPTION_PRODUCT_IDS

        @Volatile private var shared: PlayBillingManager? = null

        fun get(context: Context): PlayBillingManager = shared ?: synchronized(this) {
            shared ?: PlayBillingManager(context).also { shared = it }
        }
    }
}
