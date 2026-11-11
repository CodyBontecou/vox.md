package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalGroup
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalNavRow
import md.vox.android.ui.SignalRowDivider
import md.vox.android.ui.SignalSectionLabel
import md.vox.android.ui.SignalType

/**
 * Settings > Subscription (Retention Flow board 1): the plan, its status and the one-tap path
 * to cancel. A renewing plan opens the "Before you go" sheet (boards 2 and 2b) before Play;
 * Lifetime has no cancel path. After a lapse the screen becomes "Subscription ended" (board 9).
 */
@Composable
internal fun SubscriptionScreen(
    billingState: BillingUiState,
    navigateBack: () -> Unit,
    openPlans: () -> Unit,
    restore: () -> Unit,
    /** Opens Play's subscription center for the active product (sku + package). */
    continueToCancel: () -> Unit,
    switchToYearly: () -> Unit,
    /** Opens Play's subscription center after a lapse. */
    openPlaySubscriptions: () -> Unit = continueToCancel,
    initialShowsBeforeYouGo: Boolean = false,
) {
    val c = Signal.colors
    val status = subscriptionStatus(billingState)
    var showsBeforeYouGo by rememberSaveable { mutableStateOf(initialShowsBeforeYouGo) }
    Scaffold(
        containerColor = c.bg,
        topBar = { VoxTopBar(voxUiText("Subscription"), navigateBack) },
        bottomBar = {
            if (status is SubscriptionStatus.Ended) {
                SubscriptionEndedFooter(openPlans = openPlans, openPlaySubscriptions = openPlaySubscriptions)
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SignalMetrics.PageGutter)
                .padding(top = 8.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (status) {
                is SubscriptionStatus.Active -> {
                    SubscriptionPlanCard(status)
                    SubscriptionBillingNotice(billingState)
                    if (status.weeklyScheduled) {
                        SubscriptionNote(Icons.Outlined.Schedule, voxString("Weekly starts at your next renewal."))
                    }
                    SignalGroup(title = null) {
                        SignalNavRow(
                            title = voxString("Manage or cancel"),
                            subtitle = voxString("Cancel, payment method and billing in Google Play"),
                            icon = Icons.Outlined.CreditCard,
                            monoSubtitle = false,
                            onClick = { showsBeforeYouGo = true },
                            modifier = Modifier.testTag("subscription-manage"),
                        )
                        SignalRowDivider()
                        SignalNavRow(
                            title = voxString("Change plan"),
                            subtitle = voxString("Weekly, Yearly or Lifetime"),
                            icon = Icons.Outlined.SwapHoriz,
                            monoSubtitle = false,
                            onClick = openPlans,
                        )
                        SignalRowDivider()
                        SubscriptionRestoreRow(billingState, restore)
                    }
                    Text(
                        voxString("Cancel anytime in Google Play › Payments & subscriptions. Cancelling stops the next renewal; Unlimited stays on until the period you’ve paid for ends."),
                        style = SignalType.caption,
                        color = c.muted,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    )
                }
                is SubscriptionStatus.Lifetime -> {
                    SubscriptionPlanCard(status)
                    SubscriptionBillingNotice(billingState)
                    SignalGroup(title = null) { SubscriptionRestoreRow(billingState, restore) }
                    Text(
                        voxString("Your one-time purchase is active for this Google Play account."),
                        style = SignalType.caption,
                        color = c.muted,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    )
                }
                is SubscriptionStatus.Ended -> SubscriptionEndedContent(status)
                SubscriptionStatus.Free -> {
                    SignalCard(modifier = Modifier.fillMaxWidth(), color = c.accentSoft, radius = 24.dp, padding = PaddingValues(20.dp)) {
                        Text(voxString("Get Vox.md Unlimited"), style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), color = c.accentText)
                        Text(voxString("Unlock unlimited local Capture and private, on-device transcription."), style = MaterialTheme.typography.bodyMedium, color = c.accentText)
                    }
                    SubscriptionBillingNotice(billingState)
                    SignalButton(text = voxString("See plans"), onClick = openPlans)
                    SignalGroup(title = null) { SubscriptionRestoreRow(billingState, restore) }
                }
            }
        }
    }
    val active = status as? SubscriptionStatus.Active
    val copy = active?.let { beforeYouGoCopy(it.plan, billingState.eligibleYearlySwitchOffer()) }
    if (showsBeforeYouGo && copy != null) {
        BeforeYouGoSheet(
            copy = copy,
            onDismiss = { showsBeforeYouGo = false },
            continueToCancel = {
                showsBeforeYouGo = false
                continueToCancel()
            },
            switchToYearly = {
                showsBeforeYouGo = false
                switchToYearly()
            },
        )
    }
}

/** Board 1 plan card: product, plan and status, price, renewal and who bills it. */
@Composable
private fun SubscriptionPlanCard(status: SubscriptionStatus) {
    val c = Signal.colors
    val plan = when (status) {
        is SubscriptionStatus.Active -> status.plan
        is SubscriptionStatus.Lifetime -> VoxPlan.LIFETIME
        else -> return
    }
    val price = when (status) {
        is SubscriptionStatus.Active -> status.formattedPrice
        is SubscriptionStatus.Lifetime -> status.formattedPrice
        else -> null
    }
    SignalCard(
        modifier = Modifier.fillMaxWidth().testTag("subscription-plan"),
        color = c.accentSoft,
        radius = 24.dp,
        padding = PaddingValues(20.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(
                Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(c.accent),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.MicNone, contentDescription = null, tint = c.onAccent, modifier = Modifier.size(22.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(
                    voxString("Vox.md Unlimited"),
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold),
                    color = c.accentText,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    voxFormat("%@ · Active", planNameText(plan).localized()),
                    style = MaterialTheme.typography.bodyMedium,
                    color = c.accentText,
                )
            }
        }
        Column(Modifier.padding(top = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            price?.let { PlanDetailRow(voxString("Price"), planPriceText(plan, it).localized(), mono = plan != VoxPlan.LIFETIME) }
            PlanDetailRow(
                voxString("Renewal"),
                voxString(if (plan == VoxPlan.LIFETIME) "One purchase, no renewals" else "Renews automatically. Google Play shows your next billing date."),
            )
            PlanDetailRow(voxString("Billed by"), voxString("Google Play, on the account that bought it"))
        }
    }
}

@Composable
private fun PlanDetailRow(label: String, value: String, mono: Boolean = false) {
    val c = Signal.colors
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
            color = c.accentText,
            modifier = Modifier.width(88.dp),
        )
        Text(
            value,
            style = if (mono) SignalType.mono else MaterialTheme.typography.bodyMedium,
            color = c.accentText,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun SubscriptionRestoreRow(billingState: BillingUiState, restore: () -> Unit) {
    SignalNavRow(
        title = voxString(if (billingState.isRestoring) "Restoring purchase…" else "Restore Purchase"),
        subtitle = voxString("Check Google Play again"),
        icon = Icons.Outlined.Refresh,
        monoSubtitle = false,
        showChevron = false,
        enabled = billingState.connectionPhase != BillingConnectionPhase.CONNECTING && !billingState.isRestoring && !billingState.isPurchasing,
        onClick = restore,
    )
}

@Composable
private fun SubscriptionBillingNotice(billingState: BillingUiState) {
    billingMessage(billingState)?.let { BillingNotice(it.localized(), billingNoticeStatus(billingState)) }
}

@Composable
private fun SubscriptionNote(icon: ImageVector, text: String) {
    val c = Signal.colors
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(c.secondarySoft).padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, tint = c.secondaryText, modifier = Modifier.padding(top = 1.dp).size(18.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = c.secondaryText)
    }
}

/**
 * The "Before you go" sheet. Keep Unlimited and Continue to cancel are the same size; Continue
 * to cancel opens Play in one tap; Back or a tap outside closes the sheet. No questions, no timer.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BeforeYouGoSheet(
    copy: BeforeYouGoCopy,
    onDismiss: () -> Unit,
    continueToCancel: () -> Unit,
    switchToYearly: () -> Unit,
) {
    val c = Signal.colors
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = c.bg,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        tonalElevation = 0.dp,
    ) {
        BeforeYouGoContent(copy, onDismiss, continueToCancel, switchToYearly)
    }
}

/**
 * Only the lists and the offer card scroll; the action row and its footnote are a pinned footer
 * that clears the navigation bar, so both buttons are visible at first open in any locale or
 * font scale.
 */
@Composable
internal fun BeforeYouGoContent(
    copy: BeforeYouGoCopy,
    onDismiss: () -> Unit,
    continueToCancel: () -> Unit,
    switchToYearly: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    Column(modifier.fillMaxWidth().testTag("before-you-go")) {
        Column(
            modifier = Modifier
                .weight(1f, fill = false)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 4.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    voxString("Before you go"),
                    style = MaterialTheme.typography.headlineSmall,
                    color = c.text,
                    modifier = Modifier.semantics { heading() },
                )
                Text(copy.lead.localized(), style = MaterialTheme.typography.bodyMedium, color = c.muted)
            }
            RetentionListCard(voxString("What stops"), copy.stops, keeps = false)
            RetentionListCard(voxString("What you keep"), copy.keeps, keeps = true)
            copy.switchOffer?.let { offer -> SwitchToYearlyCard(offer, switchToYearly) }
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(c.bg)
                .navigationBarsPadding()
                .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 16.dp)
                .testTag("before-you-go-actions"),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(Modifier.height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SignalButton(
                    text = voxString("Keep Unlimited"),
                    onClick = onDismiss,
                    variant = SignalButtonVariant.TONAL,
                    modifier = Modifier.weight(1f).fillMaxHeight().testTag("keep-unlimited"),
                )
                SignalButton(
                    text = voxString("Continue to cancel"),
                    onClick = continueToCancel,
                    variant = SignalButtonVariant.PRIMARY,
                    icon = Icons.AutoMirrored.Outlined.OpenInNew,
                    modifier = Modifier.weight(1f).fillMaxHeight().testTag("continue-to-cancel"),
                )
            }
            Text(
                voxString("Continue to cancel opens your Vox.md subscription in Google Play."),
                style = MaterialTheme.typography.bodySmall,
                color = c.muted,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/** Board 2 offer card; prices are the ProductDetails phases of `switch-yearly-1y`. */
@Composable
private fun SwitchToYearlyCard(offer: VoxYearlySwitchOffer, switchToYearly: () -> Unit) {
    val c = Signal.colors
    SignalCard(
        modifier = Modifier.fillMaxWidth().testTag("switch-yearly-offer"),
        color = c.secondarySoft,
        radius = 16.dp,
        padding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
    ) {
        Text(
            voxString("Offer for Weekly subscribers"),
            style = SignalType.sectionLabel,
            color = c.secondaryText,
        )
        Text(
            switchOfferTitle(offer).localized(),
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
            color = c.secondaryText,
            modifier = Modifier.padding(top = 6.dp),
        )
        Text(
            switchOfferDetail(offer).localized(),
            style = MaterialTheme.typography.bodySmall,
            color = c.secondaryText,
            modifier = Modifier.padding(top = 4.dp, bottom = 10.dp),
        )
        SignalButton(
            text = voxString("Switch to Yearly"),
            onClick = switchToYearly,
            variant = SignalButtonVariant.SECONDARY,
            size = SignalButtonSize.MEDIUM,
            modifier = Modifier.testTag("switch-to-yearly"),
        )
    }
}

@Composable
private fun RetentionListCard(title: String, items: List<VoxUiText>, keeps: Boolean) {
    val c = Signal.colors
    SignalCard(
        modifier = Modifier.fillMaxWidth(),
        color = c.cardLowest,
        radius = 16.dp,
        padding = PaddingValues(horizontal = 14.dp, vertical = 12.dp),
    ) {
        SignalSectionLabel(title, color = c.muted)
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items.forEach { item -> RetentionListItem(item.localized(), keeps) }
        }
    }
}

@Composable
private fun RetentionListItem(text: String, keeps: Boolean) {
    val c = Signal.colors
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(
            if (keeps) Icons.Outlined.Check else Icons.Outlined.Remove,
            contentDescription = null,
            tint = if (keeps) c.accent else c.muted,
            modifier = Modifier.padding(top = 1.dp).size(18.dp),
        )
        Text(text, style = MaterialTheme.typography.bodyMedium, color = c.text, modifier = Modifier.weight(1f))
    }
}

/** Board 9: what paused and what still works after a lapse, then "See plans". */
@Composable
private fun ColumnScope.SubscriptionEndedContent(status: SubscriptionStatus.Ended) {
    val c = Signal.colors
    SignalCard(
        modifier = Modifier.fillMaxWidth().testTag("subscription-ended"),
        color = c.well,
        radius = 24.dp,
        padding = PaddingValues(20.dp),
    ) {
        Text(
            voxString("Your subscription has ended"),
            style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold),
            color = c.text,
            modifier = Modifier.semantics { heading() },
        )
        Text(endedPlanText(status.plan).localized(), style = MaterialTheme.typography.bodyMedium, color = c.muted, modifier = Modifier.padding(top = 6.dp))
        Text(
            voxString("Your Library stays readable. New captures and recordings are paused."),
            style = MaterialTheme.typography.bodyMedium,
            color = c.muted,
        )
    }
    RetentionListCard(voxString("What’s paused"), lapseStops, keeps = false)
    RetentionListCard(voxString("Still works"), lapseKeeps, keeps = true)
}

@Composable
private fun SubscriptionEndedFooter(openPlans: () -> Unit, openPlaySubscriptions: () -> Unit) {
    val c = Signal.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(c.bg)
            .navigationBarsPadding()
            .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        SignalButton(text = voxString("See plans"), onClick = openPlans, modifier = Modifier.testTag("subscription-see-plans"))
        SignalButton(
            text = voxString("Open Google Play subscriptions"),
            onClick = openPlaySubscriptions,
            variant = SignalButtonVariant.TERTIARY,
            size = SignalButtonSize.MEDIUM,
        )
        Text(
            voxString("Plans and any offer you’re eligible for are priced by Google Play."),
            style = MaterialTheme.typography.bodySmall,
            color = c.muted,
            textAlign = TextAlign.Center,
        )
    }
}
