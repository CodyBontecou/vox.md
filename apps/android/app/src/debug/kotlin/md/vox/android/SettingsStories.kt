package md.vox.android

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import md.vox.android.capturedomain.ActivityDay
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.CaptureRailSide
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.platformservices.TranscriptionUsageState

/**
 * Signal redesign stories for the settings area. Story ids use the
 * "settings-" prefix; launch with
 * `adb shell am start -n md.vox.android/.VisualStoryActivity --es story <id> --ez dark <bool>`.
 * Returns false when [story] is not one of these.
 */
@Composable
internal fun SettingsStories(story: String): Boolean {
    when (story) {
        // Settings
        "settings-free" -> SettingsStateStory(BillingUiState(BillingConnectionPhase.READY, VoxEntitlement.FREE, "$9.99", true))
        "settings-unlimited" -> SettingsStateStory(BillingUiState(BillingConnectionPhase.READY, VoxEntitlement.UNLIMITED, "$9.99", true))
        "settings-price-loading" -> SettingsStateStory(BillingUiState(BillingConnectionPhase.CONNECTING, VoxEntitlement.FREE, null, false))

        // Stats
        "settings-stats-empty" -> StatsScreen(stats = ActivityStats.Empty, navigateBack = {})
        "settings-stats-populated" -> StatsScreen(stats = settingsStoryStats, navigateBack = {})

        // Capture Bar
        "settings-capture-bar" -> CaptureBarStory(CaptureBarConfiguration())
        "settings-capture-bar-customized" -> CaptureBarStory(
            CaptureBarConfiguration(
                orderedActions = listOf(CaptureBarAction.CHECKLIST, CaptureBarAction.ADD_MEDIA) +
                    CaptureBarAction.entries.filterNot { it == CaptureBarAction.CHECKLIST || it == CaptureBarAction.ADD_MEDIA },
                hiddenActions = setOf(CaptureBarAction.SKETCH, CaptureBarAction.TEXT_CASE, CaptureBarAction.INTERNAL_LINK, CaptureBarAction.UNDO),
                usesTwentyFourHourTimestamps = true,
                railSide = CaptureRailSide.RIGHT,
                confirmsVoiceNotesBeforeAdding = true,
                voiceRecordingResult = VoiceRecordingResult.SEND_IMMEDIATELY,
            ),
        )
        "settings-capture-bar-busy" -> CaptureBarStory(
            CaptureBarConfiguration(hiddenActions = setOf(CaptureBarAction.SKETCH)),
            isBusy = true,
        )

        // Debug Log
        "settings-debug-log-empty" -> DebugLogContent(logText = "", navigateBack = {}, refresh = {}, copy = {}, clear = {})
        "settings-debug-log-populated" -> DebugLogContent(logText = settingsStoryLog, navigateBack = {}, refresh = {}, copy = {}, clear = {})

        // App Language
        "settings-app-language" -> AppLanguageSettingsScreen(navigateBack = {}, initialSelection = AppLanguage.SYSTEM)
        "settings-app-language-selected" -> AppLanguageSettingsScreen(navigateBack = {}, initialSelection = AppLanguage.JAPANESE)

        // Upgrade (paywall)
        "settings-upgrade-free" -> UpgradeStateStory(storyBilling())
        "settings-upgrade-plans" -> UpgradeStateStory(storyBilling().copy(plans = storySubscriptionPlans(trial = true)))
        "settings-upgrade-plans-no-trial" -> UpgradeStateStory(storyBilling().copy(plans = storySubscriptionPlans(trial = false)))
        "settings-upgrade-subscribed" -> UpgradeStateStory(
            storyBilling(entitlement = VoxEntitlement.UNLIMITED).copy(
                plans = storySubscriptionPlans(trial = false),
                hasActiveSubscription = true,
                activeSubscriptionProductID = VoxPlayCatalog.WEEKLY_PRODUCT_ID,
            ),
        )
        "settings-upgrade-connecting" -> UpgradeStateStory(
            storyBilling(connectionPhase = BillingConnectionPhase.CONNECTING, productAvailable = false, formattedPrice = null),
        )
        "settings-upgrade-purchasing" -> UpgradeStateStory(storyBilling(isPurchasing = true))
        "settings-upgrade-restoring" -> UpgradeStateStory(storyBilling(isRestoring = true))
        "settings-upgrade-error" -> UpgradeStateStory(storyBilling(lastOutcome = BillingActionOutcome.ERROR))
        "settings-upgrade-not-found" -> UpgradeStateStory(storyBilling(lastOutcome = BillingActionOutcome.NOT_FOUND))
        "settings-upgrade-cancelled" -> UpgradeStateStory(storyBilling(lastOutcome = BillingActionOutcome.CANCELLED))
        "settings-upgrade-not-configured" -> UpgradeStateStory(
            storyBilling(statusCode = "productNotConfigured", productAvailable = false, formattedPrice = null),
        )
        "settings-upgrade-purchased" -> UpgradeStateStory(
            storyBilling(entitlement = VoxEntitlement.UNLIMITED, lastOutcome = BillingActionOutcome.PURCHASED),
        )
        "settings-upgrade-unacknowledged" -> UpgradeStateStory(
            storyBilling(entitlement = VoxEntitlement.UNLIMITED, lastOutcome = BillingActionOutcome.PURCHASED, statusCode = "acknowledge:2"),
        )
        "settings-upgrade-stale" -> UpgradeStateStory(
            storyBilling(entitlement = VoxEntitlement.UNLIMITED, connectionPhase = BillingConnectionPhase.UNAVAILABLE, isEntitlementStale = true),
        )

        // Retention flow: Settings > Subscription, Before you go, Subscription ended.
        // Fake Play state only; "Continue to cancel" and "Open Google Play subscriptions" fire
        // the production subscription-center intent, and "Switch to Yearly" is a no-op.
        "settings-subscription-weekly-offer" -> SubscriptionStateStory(storySubscriber(VoxPlayCatalog.WEEKLY_PRODUCT_ID, storySwitchOffer))
        "settings-subscription-weekly" -> SubscriptionStateStory(storySubscriber(VoxPlayCatalog.WEEKLY_PRODUCT_ID, offer = null))
        "settings-subscription-yearly" -> SubscriptionStateStory(storySubscriber(VoxPlayCatalog.YEARLY_PRODUCT_ID, storySwitchOffer))
        "settings-subscription-lifetime" -> SubscriptionStateStory(
            storyBilling(entitlement = VoxEntitlement.UNLIMITED).copy(plans = storySubscriptionPlans(trial = false), ownsLifetime = true),
        )
        "settings-subscription-ended" -> SubscriptionStateStory(
            storyBilling().copy(
                plans = storySubscriptionPlans(trial = false),
                hasSubscriptionAccessEnded = true,
                endedSubscriptionProductID = VoxPlayCatalog.YEARLY_PRODUCT_ID,
            ),
        )
        "settings-before-you-go-weekly" -> SubscriptionStateStory(
            storySubscriber(VoxPlayCatalog.WEEKLY_PRODUCT_ID, storySwitchOffer),
            showsBeforeYouGo = true,
        )
        "settings-before-you-go-yearly" -> SubscriptionStateStory(
            storySubscriber(VoxPlayCatalog.YEARLY_PRODUCT_ID, storySwitchOffer),
            showsBeforeYouGo = true,
        )
        // Walkable: tap the Unlimited card to open Settings > Subscription, Back returns.
        "settings-retention-walk" -> RetentionWalkStory(storySubscriber(VoxPlayCatalog.WEEKLY_PRODUCT_ID, storySwitchOffer))
        else -> return false
    }
    return true
}

@Composable
private fun SettingsStateStory(billingState: BillingUiState) {
    SettingsScreen(
        destination = visualDestination,
        navigateBack = {},
        chooseFolder = {},
        openPresets = {},
        openCaptureBar = {},
        openStats = {},
        openModels = {},
        openRecordingQueue = {},
        openAppLanguage = {},
        openDebugLog = {},
        openUpgrade = {},
        billingState = billingState,
    )
}

@Composable
private fun CaptureBarStory(configuration: CaptureBarConfiguration, isBusy: Boolean = false) {
    CaptureBarSettingsScreen(
        configuration = configuration,
        isBusy = isBusy,
        navigateBack = {},
        setVisible = { _, _ -> },
        move = { _, _ -> },
        setTwentyFourHour = {},
        setVoiceConfirmation = {},
        setVoiceRecordingResult = {},
        reset = {},
    )
}

@Composable
private fun RetentionWalkStory(billingState: BillingUiState) {
    var showsSubscription by androidx.compose.runtime.saveable.rememberSaveable { androidx.compose.runtime.mutableStateOf(false) }
    if (showsSubscription) {
        androidx.activity.compose.BackHandler { showsSubscription = false }
        SubscriptionStateStory(billingState, navigateBack = { showsSubscription = false })
    } else {
        SettingsScreen(
            destination = visualDestination,
            navigateBack = null,
            chooseFolder = {},
            openPresets = {},
            openCaptureBar = {},
            openStats = {},
            openModels = {},
            openRecordingQueue = {},
            openAppLanguage = {},
            openDebugLog = {},
            openUpgrade = {},
            billingState = billingState,
            openSubscription = { showsSubscription = true },
        )
    }
}

@Composable
private fun SubscriptionStateStory(billingState: BillingUiState, showsBeforeYouGo: Boolean = false, navigateBack: () -> Unit = {}) {
    val activity = androidx.compose.ui.platform.LocalContext.current.findActivity()
    val productID = billingState.activeSubscriptionProductID ?: billingState.endedSubscriptionProductID
    SubscriptionScreen(
        billingState = billingState,
        navigateBack = navigateBack,
        openPlans = {},
        restore = {},
        continueToCancel = { activity?.let { openPlaySubscriptionCenter(it, productID) } },
        switchToYearly = {},
        initialShowsBeforeYouGo = showsBeforeYouGo,
    )
}

/** A Play-returned `switch-yearly-1y` offer as [yearlySwitchOffer] would select it. */
private val storySwitchOffer = VoxYearlySwitchOffer("story-switch-yearly", "$19.99", "$29.99")

private fun storySubscriber(productID: String, offer: VoxYearlySwitchOffer?) =
    storyBilling(entitlement = VoxEntitlement.UNLIMITED).copy(
        plans = storySubscriptionPlans(trial = false),
        hasActiveSubscription = true,
        activeSubscriptionProductID = productID,
        yearlySwitchOffer = offer,
    )

@Composable
private fun UpgradeStateStory(billingState: BillingUiState, captureCount: Int = 6, usedMillis: Long = 7 * 60_000L) {
    UpgradeScreen(
        billingState = billingState,
        stats = settingsStoryStats.copy(captureCount = captureCount),
        transcriptionUsage = TranscriptionUsageState(usedMillis = usedMillis),
        navigateBack = {},
        purchase = {},
        restore = {},
    )
}

private fun storyBilling(
    entitlement: VoxEntitlement = VoxEntitlement.FREE,
    connectionPhase: BillingConnectionPhase = BillingConnectionPhase.READY,
    formattedPrice: String? = "$9.99",
    productAvailable: Boolean = true,
    lastOutcome: BillingActionOutcome? = null,
    statusCode: String? = null,
    isEntitlementStale: Boolean = false,
    isPurchasing: Boolean = false,
    isRestoring: Boolean = false,
) = BillingUiState(
    connectionPhase = connectionPhase,
    entitlement = entitlement,
    formattedPrice = formattedPrice,
    productAvailable = productAvailable,
    lastOutcome = lastOutcome,
    statusCode = statusCode,
    isEntitlementStale = isEntitlementStale,
    isPurchasing = isPurchasing,
    isRestoring = isRestoring,
)

private val settingsStoryToday = FIXED_TIME / 86_400_000L

private val settingsStoryStats = ActivityStats(
    recordingCount = 42,
    captureCount = 128,
    recordedDurationMillis = 3 * 3_600_000L + 25 * 60_000L,
    attachmentCount = 17,
    lastSevenDays = listOf(
        ActivityDay(settingsStoryToday - 6, captureCount = 3, recordingCount = 1),
        ActivityDay(settingsStoryToday - 5, captureCount = 8, recordingCount = 2),
        ActivityDay(settingsStoryToday - 4, captureCount = 0, recordingCount = 0),
        ActivityDay(settingsStoryToday - 3, captureCount = 5, recordingCount = 4),
        ActivityDay(settingsStoryToday - 2, captureCount = 12, recordingCount = 3),
        ActivityDay(settingsStoryToday - 1, captureCount = 2, recordingCount = 0),
        ActivityDay(settingsStoryToday, captureCount = 6, recordingCount = 2),
    ),
    captureSources = linkedMapOf("app" to 74, "keyboard" to 31, "share" to 12, "widget" to 7, "wear" to 4),
)

private val settingsStoryLog = """
    2023-11-14T22:13:20Z app.launch version=1.8.0 build=180
    2023-11-14T22:13:21Z capture.queue.drain pending=0
    2023-11-14T22:14:02Z recording.start chunks=0
    2023-11-14T22:14:44Z recording.stop chunks=2 durationMs=42000
    2023-11-14T22:14:45Z transcription.start engine=whisper model=ggml-small
    2023-11-14T22:15:03Z transcription.complete durationMs=18000
    2023-11-14T22:15:04Z capture.delivered state=completed attempts=1
    2023-11-14T22:16:10Z app.language.changed language=system
""".trimIndent()

/** Story prices as Play would format them for a US account; only stories use fixed values. */
internal fun storySubscriptionPlans(trial: Boolean): List<VoxPlanOption> = listOf(
    VoxPlanOption(VoxPlan.YEARLY, "$29.99", 29_990_000L, "USD", "P1Y", if (trial) "P1W" else null, "story-yearly"),
    VoxPlanOption(VoxPlan.WEEKLY, "$0.99", 990_000L, "USD", "P1W", if (trial) "P1W" else null, "story-weekly"),
    VoxPlanOption(VoxPlan.LIFETIME, "$49.99", 49_990_000L, "USD", null, null, "story-lifetime"),
)
