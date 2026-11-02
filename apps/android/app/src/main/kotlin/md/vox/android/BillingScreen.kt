package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.platformservices.TranscriptionUsageState
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalRowDivider
import md.vox.android.ui.SignalStatus
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalStatusColors

@Composable
internal fun UpgradeScreen(
    billingState: BillingUiState,
    stats: ActivityStats,
    transcriptionUsage: TranscriptionUsageState,
    navigateBack: () -> Unit,
    purchase: () -> Unit,
    restore: () -> Unit,
) {
    val c = Signal.colors
    Scaffold(
        containerColor = c.bg,
        topBar = { VoxTopBar(voxUiText("Vox.md Unlimited"), navigateBack) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SignalMetrics.PageGutter)
                .padding(top = 4.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(horizontal = 4.dp)) {
                Text(
                    voxString(if (billingState.hasUnlimitedAccess) "Unlimited is active" else "Capture without limits"),
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                    style = MaterialTheme.typography.displaySmall,
                    color = c.text,
                )
                Text(
                    voxString(if (billingState.hasUnlimitedAccess) {
                        "Your one-time purchase is active for this Google Play account."
                    } else {
                        "The free tier includes 10 delivered captures and 15 minutes of on-device transcription. A single purchase unlocks both for the lifetime of this app."
                    }),
                    style = MaterialTheme.typography.bodyLarge,
                    color = c.muted,
                )
            }

            SignalCard(modifier = Modifier.fillMaxWidth(), radius = SignalMetrics.GroupRadius) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    BenefitRow(1, voxUiText("Unlimited Markdown captures"), billingState.hasUnlimitedAccess)
                    BenefitRow(2, voxUiText("Unlimited local transcription"), billingState.hasUnlimitedAccess)
                    BenefitRow(3, voxUiText("All capture presets and entry points"), billingState.hasUnlimitedAccess)
                    BenefitRow(4, voxUiText("No subscription"), billingState.hasUnlimitedAccess)
                }
            }

            if (!billingState.hasUnlimitedAccess) {
                SignalCard(
                    modifier = Modifier.fillMaxWidth(),
                    radius = SignalMetrics.GroupRadius,
                    padding = androidx.compose.foundation.layout.PaddingValues(0.dp),
                ) {
                    Box(Modifier.padding(14.dp)) {
                        UsageMeter(
                            voxUiText("Free captures"),
                            stats.captureCount.toLong(),
                            FREE_CAPTURE_LIMIT.toLong(),
                            voxFormat(
                                "%lld of %lld used",
                                stats.captureCount.coerceAtMost(FREE_CAPTURE_LIMIT),
                                FREE_CAPTURE_LIMIT,
                            ),
                        )
                    }
                    SignalRowDivider()
                    Box(Modifier.padding(14.dp)) {
                        UsageMeter(
                            voxUiText("Local transcription"),
                            transcriptionUsage.usedMillis,
                            transcriptionUsage.limitMillis,
                            voxFormat("%@ of 15 min used", formatQuotaMinutes(transcriptionUsage.usedMillis)),
                        )
                    }
                }
            }

            billingMessage(billingState)?.let { message ->
                BillingNotice(message.localized(), billingNoticeStatus(billingState))
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val purchaseLabel = if (billingState.isPurchasing) voxString("Waiting for Google Play…") else when (billingState.entitlement) {
                    VoxEntitlement.UNLIMITED -> voxString("Unlimited Active")
                    VoxEntitlement.PENDING -> voxString("Purchase Pending")
                    VoxEntitlement.FREE -> billingState.formattedPrice?.let {
                        voxFormat("Unlock for %@", it)
                    } ?: voxString("Unlock Unlimited")
                }
                SignalButton(
                    text = purchaseLabel,
                    onClick = purchase,
                    enabled = billingState.canPurchase(),
                    loading = billingState.isPurchasing,
                    variant = SignalButtonVariant.PRIMARY,
                )
                SignalButton(
                    text = if (billingState.isRestoring) voxString("Restoring purchase…") else voxString("Restore Purchase"),
                    onClick = restore,
                    enabled = billingState.connectionPhase != BillingConnectionPhase.CONNECTING && !billingState.isRestoring && !billingState.isPurchasing,
                    loading = billingState.isRestoring,
                    variant = SignalButtonVariant.SECONDARY,
                )
            }

            Row(
                modifier = Modifier.padding(horizontal = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Outlined.Lock, contentDescription = null, tint = c.muted, modifier = Modifier.padding(top = 2.dp).size(14.dp))
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(voxString("On Android, Unlimited applies only to the Google Play account that purchased it. Google Play does not share in-app purchases through Family Library, and Apple purchases do not transfer."),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                    Text(voxString("Purchases are processed by Google Play. Purchase checks contain only the Play product and account transaction state; capture text, audio, files, destinations, and transcripts are never sent with billing traffic."),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                    Text(voxString("If Play is temporarily unavailable, Vox.md keeps the last successfully confirmed paid entitlement on this device. A successful later query applies pending, refund, or cancellation changes."),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                }
            }
        }
    }
}

/** Numbered indigo tile (or a green check once Unlimited is active) beside a benefit. */
@Composable
private fun BenefitRow(number: Int, text: VoxUiText, unlocked: Boolean) {
    val c = Signal.colors
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(24.dp)
                .clip(RoundedCornerShape(7.dp))
                .background(if (unlocked) c.successSoft else c.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            if (unlocked) {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = c.success, modifier = Modifier.size(15.dp))
            } else {
                Text(number.toString(), style = SignalType.monoCaption, color = c.accentText)
            }
        }
        Text(text.localized(), style = MaterialTheme.typography.bodyLarge, color = c.text)
    }
}

@Composable
internal fun UsageMeter(title: VoxUiText, used: Long, limit: Long, label: String) {
    val c = Signal.colors
    val fraction = if (limit <= 0) 0f else (used.toFloat() / limit).coerceIn(0f, 1f)
    val reached = limit > 0 && used >= limit
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title.localized(), style = SignalType.rowTitle, color = c.text, modifier = Modifier.weight(1f, fill = false))
            Text(label, style = SignalType.monoCaption, color = if (reached) c.warningText else c.muted, modifier = Modifier.padding(start = 12.dp))
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(CircleShape)
                .background(c.well),
        ) {
            if (fraction > 0f) {
                Box(
                    Modifier
                        .fillMaxWidth(fraction)
                        .fillMaxHeight()
                        .clip(CircleShape)
                        .background(if (reached) c.warning else c.accent),
                )
            }
        }
    }
}

/** Tinted notice whose text is announced politely when the billing state changes. */
@Composable
private fun BillingNotice(message: String, status: SignalStatus) {
    val c = Signal.colors
    val s = signalStatusColors(status)
    val icon = when (status) {
        SignalStatus.SUCCESS -> Icons.Outlined.CheckCircle
        SignalStatus.ERROR -> Icons.Outlined.ErrorOutline
        SignalStatus.WARNING -> Icons.Outlined.Schedule
        else -> Icons.Outlined.Info
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(SignalMetrics.FieldRadius))
            .background(s.fill)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, contentDescription = null, tint = s.ink, modifier = Modifier.padding(top = 1.dp).size(18.dp))
        Text(
            message,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            style = MaterialTheme.typography.bodyMedium,
            color = if (status == SignalStatus.NEUTRAL) c.text else s.ink,
        )
    }
}

/** Tone for [billingMessage], evaluated in the same order. */
private fun billingNoticeStatus(state: BillingUiState): SignalStatus = when {
    state.hasPendingPurchase && state.hasUnlimitedAccess -> SignalStatus.WARNING
    state.entitlement == VoxEntitlement.PENDING -> SignalStatus.WARNING
    state.isEntitlementStale && state.hasUnlimitedAccess -> SignalStatus.NEUTRAL
    state.statusCode == "entitlementCacheUnavailable" -> SignalStatus.WARNING
    state.statusCode == "unrecognizedPurchase" -> SignalStatus.WARNING
    state.statusCode?.startsWith("acknowledge:") == true -> SignalStatus.WARNING
    state.lastOutcome == BillingActionOutcome.PURCHASED -> SignalStatus.SUCCESS
    state.lastOutcome == BillingActionOutcome.RESTORED -> SignalStatus.SUCCESS
    state.lastOutcome == BillingActionOutcome.NOT_FOUND -> SignalStatus.NEUTRAL
    state.lastOutcome == BillingActionOutcome.CANCELLED -> SignalStatus.NEUTRAL
    state.connectionPhase == BillingConnectionPhase.CONNECTING -> SignalStatus.NEUTRAL
    state.statusCode == "productNotConfigured" -> SignalStatus.WARNING
    state.lastOutcome == BillingActionOutcome.UNAVAILABLE -> SignalStatus.WARNING
    state.lastOutcome == BillingActionOutcome.ERROR -> SignalStatus.ERROR
    else -> SignalStatus.NEUTRAL
}

internal fun billingMessage(state: BillingUiState): VoxUiText? = when {
    state.hasPendingPurchase && state.hasUnlimitedAccess ->
        voxUiText("Your existing Unlimited access remains active while Google Play processes the pending purchase.")
    state.entitlement == VoxEntitlement.PENDING -> voxUiText("Your purchase is pending. Unlimited access starts after Google Play confirms payment.")
    state.isEntitlementStale && state.hasUnlimitedAccess ->
        voxUiText("Unlimited is active from this installation’s last verified Google Play purchase. Connect to Play to refresh its status.")
    state.statusCode == "entitlementCacheUnavailable" ->
        voxUiText("Google Play verified this purchase, but Vox.md could not protect offline proof on this device. Restore again before using Unlimited offline.")
    state.statusCode == "unrecognizedPurchase" ->
        voxUiText("Google Play returned a purchase that does not unlock this app. Your existing access remains unchanged.")
    state.statusCode?.startsWith("acknowledge:") == true ->
        voxUiText("Your purchase is active, but Google Play has not acknowledged it yet. Restore while connected to retry confirmation.")
    state.lastOutcome == BillingActionOutcome.PURCHASED -> voxUiText("Purchase complete. Unlimited access is active.")
    state.lastOutcome == BillingActionOutcome.RESTORED -> voxUiText("Purchase restored. Unlimited access is active.")
    state.lastOutcome == BillingActionOutcome.NOT_FOUND -> voxUiText("No Vox.md Unlimited purchase was found for this Google Play account.")
    state.lastOutcome == BillingActionOutcome.CANCELLED -> voxUiText("Purchase cancelled. Nothing was charged.")
    state.connectionPhase == BillingConnectionPhase.CONNECTING -> voxUiText("Connecting to Google Play…")
    state.statusCode == "productNotConfigured" -> voxUiText("This build is not connected to the Vox.md Play listing. Install a Play-distributed test or release build to purchase.")
    state.lastOutcome == BillingActionOutcome.UNAVAILABLE -> voxUiText("Google Play is unavailable. Your last confirmed access remains unchanged; try again when Play is connected.")
    state.lastOutcome == BillingActionOutcome.ERROR -> voxUiText("Google Play could not complete that request. No capture data was affected.")
    else -> null
}

private const val FREE_CAPTURE_LIMIT = 10

private fun formatQuotaMinutes(milliseconds: Long): String {
    val tenths = ((milliseconds.coerceAtLeast(0) / 6_000.0).toInt() / 10.0)
    return if (tenths == tenths.toLong().toDouble()) "${tenths.toLong()} min" else "$tenths min"
}
