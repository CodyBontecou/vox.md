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
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
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
    /** Plans whose ProductDetails loaded from Play; unavailable plans are simply absent. */
    val plans: List<PaywallPlan> = emptyList(),
    /** Product that granted the current Unlimited entitlement, when known. */
    val activeProductID: String? = null,
    val lastCheckedAtEpochMillis: Long? = null,
    val lastOutcome: BillingActionOutcome? = null,
    val statusCode: String? = null,
    val lastRestoreDiagnostics: BillingRestoreDiagnostics? = null,
    val isEntitlementStale: Boolean = false,
    val hasPendingPurchase: Boolean = false,
    /** Set once when a free-trial purchase succeeds so the UI can ask for notification permission. */
    val trialReminderPromptPending: Boolean = false,
) {
    val hasUnlimitedAccess: Boolean get() = entitlement == VoxEntitlement.UNLIMITED
    val productAvailable: Boolean get() = plans.isNotEmpty()
    val isSubscriptionActive: Boolean
        get() = hasUnlimitedAccess && activeProductID?.let(PaywallPlanKind::forProductID)?.isSubscription == true

    fun plan(kind: PaywallPlanKind): PaywallPlan? = plans.firstOrNull { it.kind == kind }
}

internal fun entitlementForPurchaseStates(states: Collection<Int>): VoxEntitlement = when {
    Purchase.PurchaseState.PURCHASED in states -> VoxEntitlement.UNLIMITED
    Purchase.PurchaseState.PENDING in states -> VoxEntitlement.PENDING
    else -> VoxEntitlement.FREE
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

/**
 * Privacy-safe projection of a Play purchase used for entitlement decisions: product IDs and
 * transaction state only. No token, order ID, account ID, or capture data.
 */
internal data class PlayPurchaseSnapshot(
    val productIDs: List<String>,
    val purchaseState: Int,
    val isAcknowledged: Boolean,
    val isSuspended: Boolean = false,
    val isAutoRenewing: Boolean = false,
)

internal data class UnlimitedEntitlementDecision(
    val decision: BillingEntitlementDecision,
    /** Recognized product currently granting Unlimited (lifetime preferred), when any. */
    val grantingProductID: String?,
    val hasRecognizedPurchase: Boolean,
)

/**
 * Lifetime purchases grant Unlimited once PURCHASED (as before). Subscriptions grant only while
 * Play reports them PURCHASED, acknowledged, and not suspended (payment hold). Expired or revoked
 * subscriptions are absent from Play's query, so an authoritative query without them drops access.
 * A purchased-but-unacknowledged subscription is treated as pending until acknowledgement lands.
 */
internal fun unlimitedEntitlementDecision(
    priorEntitlement: VoxEntitlement,
    purchases: Collection<PlayPurchaseSnapshot>,
    authoritativeOwnershipQuery: Boolean,
): UnlimitedEntitlementDecision {
    val recognizedIDs = PlayBillingManager.ALL_PRODUCT_IDS
    val relevant = purchases.filter { purchase -> purchase.productIDs.any { it in recognizedIDs } }
    val effective = relevant.mapNotNull { purchase ->
        val isLifetime = PlayBillingManager.LIFETIME_PRODUCT_ID in purchase.productIDs
        val state = when {
            isLifetime -> purchase.purchaseState
            purchase.purchaseState != Purchase.PurchaseState.PURCHASED -> purchase.purchaseState
            purchase.isSuspended -> return@mapNotNull null
            !purchase.isAcknowledged -> Purchase.PurchaseState.PENDING
            else -> Purchase.PurchaseState.PURCHASED
        }
        purchase to state
    }
    val decision = billingEntitlementDecision(
        priorEntitlement = priorEntitlement,
        states = effective.map { it.second },
        authoritativeOwnershipQuery = authoritativeOwnershipQuery,
    )
    val grantingIDs = effective
        .filter { it.second == Purchase.PurchaseState.PURCHASED }
        .flatMap { it.first.productIDs }
        .filter { it in recognizedIDs }
    val granting = grantingIDs.firstOrNull { it == PlayBillingManager.LIFETIME_PRODUCT_ID } ?: grantingIDs.firstOrNull()
    return UnlimitedEntitlementDecision(decision, granting, relevant.isNotEmpty())
}

/** Whether a known subscription is still set to renew, so the trial reminder remains useful. */
internal fun hasRenewingSubscription(purchases: Collection<PlayPurchaseSnapshot>): Boolean = purchases.any { purchase ->
    purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
        purchase.isAutoRenewing &&
        purchase.productIDs.any { it in PlayBillingManager.SUBSCRIPTION_PRODUCT_IDS }
}

/**
 * Merges the two ProductDetails queries (one-time + subscriptions) into the status shown to users.
 * Missing products are only an error when nothing at all could be sold.
 */
internal fun productStatusAfterQueries(
    loadedPlanCount: Int,
    failedResponseCodes: List<Int>,
): String? = when {
    loadedPlanCount > 0 -> null
    failedResponseCodes.isNotEmpty() -> "productQuery:${failedResponseCodes.first()}"
    else -> "productNotConfigured"
}

internal fun billingStatusAfterProductQuery(
    existingStatus: String?,
    productStatus: String?,
): String? = existingStatus?.takeIf {
    it == "entitlementCacheUnavailable" || it == "unrecognizedPurchase"
} ?: productStatus

/** Phone-only Play Billing owner; no purchase data enters capture packages or the Wear app. */
class PlayBillingManager private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val entitlementCache = PlayEntitlementCache(
        context = appContext,
        productID = LIFETIME_PRODUCT_ID,
        recognizedProductIDs = ALL_PRODUCT_IDS,
    )
    private val cachedEvidence = entitlementCache.read()
    private val cachedEntitlement = if (cachedEvidence?.isOwned == true) {
        VoxEntitlement.UNLIMITED
    } else {
        VoxEntitlement.FREE
    }
    private val mutableState = MutableStateFlow(
        BillingUiState(
            entitlement = cachedEntitlement,
            activeProductID = cachedEvidence?.takeIf { it.isOwned }?.productID,
            lastCheckedAtEpochMillis = cachedEvidence?.checkedAtEpochMillis,
            isEntitlementStale = cachedEvidence?.isOwned == true,
        ),
    )
    val state: StateFlow<BillingUiState> = mutableState.asStateFlow()

    @Volatile private var productDetailsByID: Map<String, ProductDetails> = emptyMap()
    @Volatile private var connectionStarted = false
    @Volatile private var restoreRequested = false
    /** The free-trial plan whose billing flow is open, so a success can schedule the reminder. */
    @Volatile private var trialLaunch: PaywallPlan? = null
    /** Purchase tokens acknowledged in this process; kept in memory only, never logged or persisted. */
    private val acknowledgedTokens = Collections.synchronizedSet(mutableSetOf<String>())
    private val acknowledgingTokens = Collections.synchronizedSet(mutableSetOf<String>())

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
            queryProducts()
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
                    queryProducts()
                    queryOwnership(restored = consumeRestoreRequest())
                } else {
                    publishUnavailable("billingSetup:${result.responseCode}")
                    recordPendingRestoreIfNeeded(result.responseCode)
                }
            }

            override fun onBillingServiceDisconnected() {
                connectionStarted = false
                mutableState.update {
                    it.copy(
                        connectionPhase = BillingConnectionPhase.UNAVAILABLE,
                        lastOutcome = BillingActionOutcome.UNAVAILABLE,
                        statusCode = "billingDisconnected",
                        isEntitlementStale = it.entitlement == VoxEntitlement.UNLIMITED,
                    )
                }
            }
        })
    }

    fun refresh(restored: Boolean = false) {
        if (restored) restoreRequested = true
        mutableState.update { it.copy(lastOutcome = null, statusCode = null) }
        if (!billingClient.isReady) {
            start()
            return
        }
        queryProducts()
        queryOwnership(restored = consumeRestoreRequest())
    }

    fun restore() = refresh(restored = true)

    fun launchPurchase(activity: Activity, kind: PaywallPlanKind) {
        val details = productDetailsByID[kind.productID]
        val plan = mutableState.value.plan(kind)
        val offerMissing = kind.isSubscription && plan?.offerToken.isNullOrBlank()
        if (!billingClient.isReady || details == null || plan == null || offerMissing) {
            mutableState.update {
                it.copy(
                    lastOutcome = BillingActionOutcome.UNAVAILABLE,
                    statusCode = if (billingClient.isReady) "productUnavailable" else "billingUnavailable",
                )
            }
            refresh()
            return
        }
        val productParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(details)
            .apply { plan.offerToken?.takeIf { kind.isSubscription }?.let(::setOfferToken) }
            .build()
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productParams))
            .build()
        trialLaunch = plan.takeIf { it.kind.isSubscription && it.hasFreeTrial }
        val result = billingClient.launchBillingFlow(activity, params)
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            trialLaunch = null
            mutableState.update {
                it.copy(lastOutcome = BillingActionOutcome.ERROR, statusCode = "billingLaunch:${result.responseCode}")
            }
        }
    }

    fun consumeOutcome() {
        mutableState.update { it.copy(lastOutcome = null, statusCode = null) }
    }

    fun consumeTrialReminderPrompt() {
        mutableState.update { it.copy(trialReminderPromptPending = false) }
    }

    private fun queryProducts() {
        val remaining = AtomicInteger(2)
        val loaded = ConcurrentHashMap<String, ProductDetails>()
        val failures = Collections.synchronizedList(mutableListOf<Int>())
        val finish = {
            if (remaining.decrementAndGet() == 0) {
                val details = loaded.toMap()
                productDetailsByID = details
                val plans = PaywallPlanKind.entries.mapNotNull { kind ->
                    details[kind.productID]?.let { paywallPlanFrom(kind, it) }
                }
                mutableState.update {
                    it.copy(
                        plans = plans,
                        statusCode = billingStatusAfterProductQuery(
                            existingStatus = it.statusCode,
                            productStatus = productStatusAfterQueries(plans.size, failures.toList()),
                        ),
                    )
                }
            }
        }
        queryProductDetails(BillingClient.ProductType.INAPP, listOf(LIFETIME_PRODUCT_ID), loaded, failures, finish)
        queryProductDetails(BillingClient.ProductType.SUBS, SUBSCRIPTION_PRODUCT_IDS.toList(), loaded, failures, finish)
    }

    private fun queryProductDetails(
        productType: String,
        productIDs: List<String>,
        loaded: MutableMap<String, ProductDetails>,
        failures: MutableList<Int>,
        finish: () -> Unit,
    ) {
        val products = productIDs.map { productID ->
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(productID)
                .setProductType(productType)
                .build()
        }
        val params = QueryProductDetailsParams.newBuilder().setProductList(products).build()
        billingClient.queryProductDetailsAsync(params) { result, detailsResult ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                detailsResult.productDetailsList
                    .filter { it.productId in productIDs }
                    .forEach { loaded[it.productId] = it }
            } else {
                failures += result.responseCode
            }
            finish()
        }
    }

    private fun queryOwnership(restored: Boolean) {
        val remaining = AtomicInteger(2)
        val results = arrayOfNulls<Pair<BillingResult, List<Purchase>>>(2)
        listOf(BillingClient.ProductType.INAPP, BillingClient.ProductType.SUBS).forEachIndexed { index, productType ->
            val params = QueryPurchasesParams.newBuilder().setProductType(productType).build()
            billingClient.queryPurchasesAsync(params) { result, purchases ->
                results[index] = result to purchases
                if (remaining.decrementAndGet() == 0) {
                    onOwnershipQueried(requireNotNull(results[0]), requireNotNull(results[1]), restored)
                }
            }
        }
    }

    private fun onOwnershipQueried(
        oneTime: Pair<BillingResult, List<Purchase>>,
        subscriptions: Pair<BillingResult, List<Purchase>>,
        restored: Boolean,
    ) {
        val oneTimeOk = oneTime.first.responseCode == BillingClient.BillingResponseCode.OK
        val subscriptionsCode = subscriptions.first.responseCode
        val subscriptionsOk = subscriptionsCode == BillingClient.BillingResponseCode.OK
        // A device that cannot hold subscriptions has none; that is still an authoritative answer.
        val subscriptionsAuthoritative = subscriptionsOk ||
            subscriptionsCode == BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED
        val purchases = (if (oneTimeOk) oneTime.second else emptyList()) +
            (if (subscriptionsOk) subscriptions.second else emptyList())
        val failureCode = when {
            !oneTimeOk -> oneTime.first.responseCode
            !subscriptionsAuthoritative -> subscriptionsCode
            else -> BillingClient.BillingResponseCode.OK
        }
        if (!oneTimeOk && !subscriptionsAuthoritative) {
            publishUnavailable("purchaseQuery:$failureCode")
            if (restored) recordRestoreDiagnostics(failureCode, emptyList())
            return
        }
        applyPurchases(
            purchases = purchases,
            authoritative = oneTimeOk && subscriptionsAuthoritative,
            origin = if (restored) PurchaseOrigin.RESTORE else PurchaseOrigin.QUERY,
        )
        if (restored) recordRestoreDiagnostics(failureCode, purchases)
    }

    private fun consumeRestoreRequest(): Boolean = synchronized(this) {
        val pending = restoreRequested
        restoreRequested = false
        pending
    }

    private fun recordPendingRestoreIfNeeded(responseCode: Int) {
        if (!consumeRestoreRequest()) return
        recordRestoreDiagnostics(responseCode, emptyList())
    }

    private fun recordRestoreDiagnostics(responseCode: Int, purchases: Collection<Purchase>) {
        val diagnostics = billingRestoreDiagnosticsFromPurchases(
            responseCode = responseCode,
            requestedProductIDs = ALL_PRODUCT_IDS,
            loadedProductIDs = productDetailsByID.keys,
            purchases = purchases,
        )
        mutableState.update { it.copy(lastRestoreDiagnostics = diagnostics) }
        recordBillingRestoreDiagnostics(appContext, diagnostics)
    }

    private fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>) {
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> applyPurchases(
                purchases = purchases,
                authoritative = false,
                origin = PurchaseOrigin.FLOW,
            )
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                trialLaunch = null
                mutableState.update { it.copy(lastOutcome = BillingActionOutcome.CANCELLED, statusCode = null) }
            }
            else -> {
                trialLaunch = null
                mutableState.update {
                    it.copy(lastOutcome = BillingActionOutcome.ERROR, statusCode = "purchaseUpdate:${result.responseCode}")
                }
            }
        }
    }

    private fun snapshot(purchase: Purchase) = PlayPurchaseSnapshot(
        productIDs = purchase.products,
        purchaseState = purchase.purchaseState,
        isAcknowledged = purchase.isAcknowledged || purchase.purchaseToken in acknowledgedTokens,
        isSuspended = purchase.isSuspended,
        isAutoRenewing = purchase.isAutoRenewing,
    )

    private fun applyPurchases(purchases: List<Purchase>, authoritative: Boolean, origin: PurchaseOrigin) {
        val snapshots = purchases.map(::snapshot)
        val evaluation = unlimitedEntitlementDecision(
            priorEntitlement = mutableState.value.entitlement,
            purchases = snapshots,
            authoritativeOwnershipQuery = authoritative,
        )
        val decision = evaluation.decision
        val checkedAt = System.currentTimeMillis()
        val cachePersisted = decision.authoritativeOwned?.let { owned ->
            entitlementCache.write(
                isOwned = owned,
                checkedAtEpochMillis = checkedAt,
                ownedProductID = evaluation.grantingProductID ?: LIFETIME_PRODUCT_ID,
            )
        } ?: true
        UnlimitedAccessRegistry.update(decision.entitlement == VoxEntitlement.UNLIMITED)
        purchases
            .filter { purchase ->
                purchase.products.any { it in ALL_PRODUCT_IDS } &&
                    purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
                    !purchase.isAcknowledged &&
                    purchase.purchaseToken !in acknowledgedTokens
            }
            .forEach(::acknowledge)
        val trialStarted = origin == PurchaseOrigin.FLOW && scheduleTrialReminderIfStarted(purchases)
        if (authoritative && !hasRenewingSubscription(snapshots)) TrialReminderScheduler.cancel(appContext)
        mutableState.update {
            it.copy(
                connectionPhase = BillingConnectionPhase.READY,
                entitlement = decision.entitlement,
                activeProductID = when {
                    decision.entitlement != VoxEntitlement.UNLIMITED -> null
                    else -> evaluation.grantingProductID ?: it.activeProductID
                },
                lastCheckedAtEpochMillis = if (decision.authoritativeOwned != null) checkedAt else it.lastCheckedAtEpochMillis,
                lastOutcome = when {
                    decision.authoritativeOwned == true -> when (origin) {
                        PurchaseOrigin.FLOW, PurchaseOrigin.ACKNOWLEDGED -> BillingActionOutcome.PURCHASED
                        PurchaseOrigin.RESTORE -> BillingActionOutcome.RESTORED
                        PurchaseOrigin.QUERY -> if (it.lastOutcome == BillingActionOutcome.PENDING) {
                            BillingActionOutcome.PURCHASED
                        } else {
                            it.lastOutcome
                        }
                    }
                    decision.hasPendingPurchase -> BillingActionOutcome.PENDING
                    origin == PurchaseOrigin.RESTORE -> BillingActionOutcome.NOT_FOUND
                    else -> it.lastOutcome
                },
                statusCode = when {
                    !cachePersisted -> "entitlementCacheUnavailable"
                    origin == PurchaseOrigin.FLOW && purchases.isNotEmpty() && !evaluation.hasRecognizedPurchase ->
                        "unrecognizedPurchase"
                    else -> retainedProductStatus(it.statusCode)
                },
                isEntitlementStale = if (decision.authoritativeOwned != null) false else it.isEntitlementStale,
                hasPendingPurchase = decision.hasPendingPurchase,
                trialReminderPromptPending = it.trialReminderPromptPending || trialStarted,
            )
        }
    }

    /** Schedules the day-5 reminder when the open billing flow was a free trial and it succeeded. */
    private fun scheduleTrialReminderIfStarted(purchases: List<Purchase>): Boolean {
        val plan = trialLaunch ?: return false
        val purchase = purchases.firstOrNull { purchase ->
            plan.kind.productID in purchase.products && purchase.purchaseState == Purchase.PurchaseState.PURCHASED
        } ?: return false
        trialLaunch = null
        val trialDays = plan.freeTrialDays ?: return false
        val reminderDay = trialReminderDay(trialDays) ?: return false
        val startedAt = purchase.purchaseTime.takeIf { it > 0L } ?: System.currentTimeMillis()
        TrialReminderScheduler.schedule(
            context = appContext,
            triggerAtEpochMillis = startedAt + reminderDay * DAY_MILLIS,
        )
        return true
    }

    private fun acknowledge(purchase: Purchase) {
        val token = purchase.purchaseToken
        if (!acknowledgingTokens.add(token)) return
        val params = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(token).build()
        billingClient.acknowledgePurchase(params) { result ->
            acknowledgingTokens.remove(token)
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                acknowledgedTokens += token
                if (purchase.products.any { it in SUBSCRIPTION_PRODUCT_IDS }) {
                    applyPurchases(listOf(purchase), authoritative = false, origin = PurchaseOrigin.ACKNOWLEDGED)
                }
            } else {
                mutableState.update { it.copy(statusCode = "acknowledge:${result.responseCode}") }
            }
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

    private enum class PurchaseOrigin { QUERY, RESTORE, FLOW, ACKNOWLEDGED }

    companion object {
        const val LIFETIME_PRODUCT_ID = "vox_unlimited_lifetime"
        const val YEARLY_PRODUCT_ID = "vox_unlimited_yearly"
        const val WEEKLY_PRODUCT_ID = "vox_unlimited_weekly"
        val SUBSCRIPTION_PRODUCT_IDS: Set<String> = setOf(YEARLY_PRODUCT_ID, WEEKLY_PRODUCT_ID)
        val ALL_PRODUCT_IDS: Set<String> = setOf(LIFETIME_PRODUCT_ID) + SUBSCRIPTION_PRODUCT_IDS
        private const val DAY_MILLIS = 24L * 60L * 60L * 1000L

        @Volatile private var shared: PlayBillingManager? = null

        fun get(context: Context): PlayBillingManager = shared ?: synchronized(this) {
            shared ?: PlayBillingManager(context).also { shared = it }
        }
    }
}

/** Maps Play ProductDetails to a sellable plan; null when Play returned no usable offer. */
private fun paywallPlanFrom(kind: PaywallPlanKind, details: ProductDetails): PaywallPlan? {
    if (!kind.isSubscription) {
        val offer = details.oneTimePurchaseOfferDetails ?: return null
        return PaywallPlan(
            kind = kind,
            formattedPrice = offer.formattedPrice,
            priceAmountMicros = offer.priceAmountMicros,
            currencyCode = offer.priceCurrencyCode,
        )
    }
    val candidates = details.subscriptionOfferDetails.orEmpty().map { offer ->
        PaywallOfferCandidate(
            basePlanID = offer.basePlanId,
            offerID = offer.offerId,
            offerToken = offer.offerToken,
            phases = offer.pricingPhases.pricingPhaseList.map { phase ->
                PaywallPricingPhase(
                    priceAmountMicros = phase.priceAmountMicros,
                    formattedPrice = phase.formattedPrice,
                    currencyCode = phase.priceCurrencyCode,
                    billingPeriod = phase.billingPeriod,
                    billingCycleCount = phase.billingCycleCount,
                    recurrenceMode = phase.recurrenceMode,
                )
            },
        )
    }
    val selected = selectSubscriptionOffer(candidates) ?: return null
    return PaywallPlan(
        kind = kind,
        formattedPrice = selected.recurringPhase.formattedPrice,
        priceAmountMicros = selected.recurringPhase.priceAmountMicros,
        currencyCode = selected.recurringPhase.currencyCode,
        offerToken = selected.offerToken,
        freeTrialDays = selected.freeTrialDays,
    )
}
