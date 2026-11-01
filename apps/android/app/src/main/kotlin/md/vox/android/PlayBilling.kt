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
) {
    val hasUnlimitedAccess: Boolean get() = entitlement == VoxEntitlement.UNLIMITED
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
                mutableState.update {
                    it.copy(
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

    fun launchPurchase(activity: Activity) {
        val current = mutableState.value
        if (!current.canPurchase() || !operations.beginPurchase(current.entitlement,current.hasPendingPurchase)) return
        val details = productDetails
        val offer = details?.oneTimePurchaseOfferDetails
        val offerToken = offer?.offerToken
        if (!billingClient.isReady || details == null || offer == null || offerToken.isNullOrBlank()) {
            operations.finishPurchase()
            mutableState.update { it.copy(lastOutcome = BillingActionOutcome.UNAVAILABLE, statusCode = "productUnavailable", isPurchasing = false) }
            refresh()
            return
        }
        mutableState.update { it.copy(isPurchasing = true, lastOutcome = null) }
        val result = runCatching {
            val params = BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(listOf(BillingFlowParams.ProductDetailsParams.newBuilder()
                    .setProductDetails(details).setOfferToken(offerToken).build()))
                .build()
            billingClient.launchBillingFlow(activity,params)
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
            mutableState.update { it.copy(productAvailable = false, formattedPrice = null) }
            operations.beginProductQuery()
        }
        val product = QueryProductDetailsParams.Product.newBuilder()
            .setProductId(PRODUCT_ID)
            .setProductType(BillingClient.ProductType.INAPP)
            .build()
        val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(product)).build()
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
                    return@queryProductDetailsAsync
                }
                val details = detailsResult.productDetailsList.firstOrNull {
                    it.productId == PRODUCT_ID && it.oneTimePurchaseOfferDetails?.let { offer ->
                        offer.rentalDetails == null && offer.preorderDetails == null && !offer.offerToken.isNullOrBlank()
                    } == true
                }
                productDetails = details
                mutableState.update {
                    it.copy(
                        productAvailable = details != null,
                        formattedPrice = details?.oneTimePurchaseOfferDetails?.formattedPrice,
                        statusCode = billingStatusAfterProductQuery(
                            existingStatus = it.statusCode,
                            productStatus = if (details == null) "productNotConfigured" else null,
                        ),
                    )
                }
            }
        }
    }

    private fun queryOwnership(restored: Boolean) {
        val generation = operations.beginOwnershipQuery(restored)
        mutableState.update { it.copy(isRestoring = operations.isRestoring()) }
        val params = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
        billingClient.queryPurchasesAsync(params) { result, purchasesResult ->
            synchronized(operations) {
                val wasRestoring = operations.finishOwnershipQuery(generation) ?: return@queryPurchasesAsync
                mutableState.update { it.copy(isRestoring = false) }
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    publishUnavailable("purchaseQuery:${result.responseCode}")
                    if (wasRestoring) recordRestoreDiagnostics(result.responseCode, purchasesResult)
                    return@queryPurchasesAsync
                }
                val relevant = purchasesResult.filter { PRODUCT_ID in it.products }
                val decision = billingEntitlementDecision(
                    priorEntitlement = mutableState.value.entitlement,
                    states = relevant.map(Purchase::getPurchaseState),
                    authoritativeOwnershipQuery = true,
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
                if (wasRestoring) recordRestoreDiagnostics(result.responseCode, purchasesResult)
            }
        }
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
            requestedProductIDs = listOf(PRODUCT_ID),
            loadedProductIDs = listOfNotNull(productDetails?.productId),
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
                val relevant = purchases.filter { PRODUCT_ID in it.products }
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
        const val PRODUCT_ID = "vox_unlimited_lifetime"

        @Volatile private var shared: PlayBillingManager? = null

        fun get(context: Context): PlayBillingManager = shared ?: synchronized(this) {
            shared ?: PlayBillingManager(context).also { shared = it }
        }
    }
}
