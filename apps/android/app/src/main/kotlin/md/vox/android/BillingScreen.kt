package md.vox.android

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.platformservices.TranscriptionUsageState

@Composable
internal fun UpgradeScreen(
    billingState: BillingUiState,
    stats: ActivityStats,
    transcriptionUsage: TranscriptionUsageState,
    navigateBack: () -> Unit,
    purchase: () -> Unit,
    restore: () -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { VoxTopBar(voxUiText("Vox.md Unlimited"), navigateBack) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                voxString(if (billingState.hasUnlimitedAccess) "Unlimited is active" else "Capture without limits"),
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                voxString(if (billingState.hasUnlimitedAccess) {
                    "Your one-time purchase is active for this Google Play account."
                } else {
                    "The free tier includes 10 delivered captures and 15 minutes of on-device transcription. A single purchase unlocks both for the lifetime of this app."
                }),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                shape = RoundedCornerShape(16.dp),
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    BenefitRow(voxUiText("Unlimited Markdown captures"))
                    BenefitRow(voxUiText("Unlimited local transcription"))
                    BenefitRow(voxUiText("All capture presets and entry points"))
                    BenefitRow(voxUiText("No subscription"))
                }
            }

            if (!billingState.hasUnlimitedAccess) {
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
                UsageMeter(
                    voxUiText("Local transcription"),
                    transcriptionUsage.usedMillis,
                    transcriptionUsage.limitMillis,
                    voxFormat("%@ of 15 min used", formatQuotaMinutes(transcriptionUsage.usedMillis)),
                )
            }

            billingMessage(billingState)?.let { message ->
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = if (billingState.lastOutcome == BillingActionOutcome.ERROR) {
                            MaterialTheme.colorScheme.errorContainer
                        } else {
                            MaterialTheme.colorScheme.surfaceVariant
                        },
                    ),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Text(
                        message.localized(),
                        modifier = Modifier
                            .padding(14.dp)
                            .semantics { liveRegion = LiveRegionMode.Polite },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }

            Button(
                onClick = purchase,
                enabled = billingState.productAvailable &&
                    billingState.entitlement == VoxEntitlement.FREE &&
                    billingState.connectionPhase == BillingConnectionPhase.READY,
                modifier = Modifier.fillMaxWidth().height(48.dp),
                shape = RoundedCornerShape(12.dp),
            ) {
                val purchaseLabel = when (billingState.entitlement) {
                    VoxEntitlement.UNLIMITED -> voxString("Unlimited Active")
                    VoxEntitlement.PENDING -> voxString("Purchase Pending")
                    VoxEntitlement.FREE -> billingState.formattedPrice?.let {
                        voxFormat("Unlock for %@", it)
                    } ?: voxString("Unlock Unlimited")
                }
                Text(purchaseLabel)
            }
            OutlinedButton(
                onClick = restore,
                enabled = billingState.connectionPhase != BillingConnectionPhase.CONNECTING,
                modifier = Modifier.fillMaxWidth().height(48.dp),
                shape = RoundedCornerShape(12.dp),
            ) {
                Text(voxString("Restore Purchase"))
            }
            Text(voxString("On Android, Unlimited applies only to the Google Play account that purchased it. Google Play does not share in-app purchases through Family Library, and Apple purchases do not transfer."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(voxString("Purchases are processed by Google Play. Purchase checks contain only the Play product and account transaction state; capture text, audio, files, destinations, and transcripts are never sent with billing traffic."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(voxString("If Play is temporarily unavailable, Vox.md keeps the last successfully confirmed paid entitlement on this device. A successful later query applies pending, refund, or cancellation changes."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun BenefitRow(text: VoxUiText) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        androidx.compose.material3.Icon(
            Icons.Outlined.CheckCircle,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(text.localized(), style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
internal fun UsageMeter(title: VoxUiText, used: Long, limit: Long, label: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(title.localized(), style = MaterialTheme.typography.titleSmall)
            Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        LinearProgressIndicator(
            progress = { if (limit <= 0) 0f else (used.toFloat() / limit).coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().height(8.dp),
        )
    }
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
