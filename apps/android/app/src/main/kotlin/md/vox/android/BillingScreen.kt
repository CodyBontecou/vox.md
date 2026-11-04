package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.em
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import md.vox.android.ui.SignalButtonSize
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
    purchase: (VoxPlan) -> Unit,
    restore: () -> Unit,
    manageSubscriptions: () -> Unit = {},
) {
    val c = Signal.colors
    // Three pages, as in the paywall board: the core benefit, how the free trial works,
    // and the plans. The footer (page dots, summary, purchase, restore) stays put.
    val pager = rememberPagerState(pageCount = { 3 })
    val scope = rememberCoroutineScope()
    val plans = billingState.purchasablePlans
    var selectedName by rememberSaveable { mutableStateOf<String?>(null) }
    val selected = plans.firstOrNull { it.plan.name == selectedName } ?: plans.firstOrNull()
    val trialPlan = plans.firstOrNull { it.plan == VoxPlan.YEARLY && it.hasFreeTrial } ?: plans.firstOrNull { it.hasFreeTrial }
    Scaffold(
        containerColor = c.bg,
        topBar = { VoxTopBar(voxUiText("Vox.md Unlimited"), navigateBack) },
        bottomBar = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(c.bg)
                    .navigationBarsPadding()
                    .padding(start = 24.dp, end = 24.dp, top = 14.dp, bottom = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                PaywallPageDots(current = pager.currentPage, count = pager.pageCount)
                billingMessage(billingState)?.let { message ->
                    BillingNotice(message.localized(), billingNoticeStatus(billingState))
                }
                if (!billingState.ownsLifetime && selected != null) {
                    Text(
                        paywallSummary(selected),
                        style = MaterialTheme.typography.bodyMedium,
                        color = c.muted,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
                val purchaseLabel = when {
                    billingState.isPurchasing -> voxString("Waiting for Google Play…")
                    billingState.entitlement == VoxEntitlement.PENDING -> voxString("Purchase Pending")
                    billingState.entitlement == VoxEntitlement.UNLIMITED && !billingState.canPurchase() -> voxString("Unlimited Active")
                    selected != null && selected.plan.productID == billingState.activeSubscriptionProductID -> voxString("Unlimited Active")
                    selected == null -> voxString("Unlock Unlimited")
                    else -> paywallCallToAction(selected)
                }
                SignalButton(
                    text = purchaseLabel,
                    onClick = { selected?.let { purchase(it.plan) } },
                    enabled = billingState.canPurchase() && selected != null &&
                        selected.plan.productID != billingState.activeSubscriptionProductID,
                    loading = billingState.isPurchasing,
                    variant = SignalButtonVariant.PRIMARY,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (pager.currentPage != pager.pageCount - 1) {
                        SignalButton(
                            text = voxString("See all plans"),
                            onClick = { scope.launch { pager.animateScrollToPage(pager.pageCount - 1) } },
                            variant = SignalButtonVariant.TERTIARY,
                            size = SignalButtonSize.MEDIUM,
                            fillWidth = false,
                        )
                    }
                    if (billingState.hasActiveSubscription) {
                        SignalButton(
                            text = voxString("Manage Subscriptions"),
                            onClick = manageSubscriptions,
                            variant = SignalButtonVariant.TERTIARY,
                            size = SignalButtonSize.MEDIUM,
                            fillWidth = false,
                        )
                    }
                    SignalButton(
                        text = if (billingState.isRestoring) voxString("Restoring purchase…") else voxString("Restore Purchase"),
                        onClick = restore,
                        enabled = billingState.connectionPhase != BillingConnectionPhase.CONNECTING && !billingState.isRestoring && !billingState.isPurchasing,
                        loading = billingState.isRestoring,
                        variant = SignalButtonVariant.TERTIARY,
                        size = SignalButtonSize.MEDIUM,
                        fillWidth = false,
                    )
                }
            }
        },
    ) { padding ->
        HorizontalPager(
            state = pager,
            modifier = Modifier.fillMaxSize().padding(padding),
            verticalAlignment = Alignment.Top,
        ) { page ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp)
                    .padding(top = 8.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                when (page) {
                    0 -> {
                        Text(
                            voxString(if (billingState.hasUnlimitedAccess) "Unlimited is active" else "Speak it. It lands in your vault."),
                            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                            style = MaterialTheme.typography.displaySmall,
                            color = c.text,
                        )
                        PaywallExampleCard()
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            BenefitRow(1, voxUiText("Unlimited on-device transcription"), billingState.hasUnlimitedAccess)
                            BenefitRow(2, voxUiText("Keyboard, widget, Quick Settings, Wear OS"), billingState.hasUnlimitedAccess)
                            BenefitRow(3, voxUiText("Plain Markdown files you own"), billingState.hasUnlimitedAccess)
                        }
                        Text(
                            when {
                                billingState.ownsLifetime -> voxString("Your one-time purchase is active for this Google Play account.")
                                billingState.hasActiveSubscription -> voxString("Unlimited subscription is active.")
                                else -> voxString("The free tier includes 10 delivered captures and 15 minutes of on-device transcription. A single purchase unlocks both for the lifetime of this app.")
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = c.muted,
                        )
                    }
                    1 -> {
                        if (trialPlan != null && !billingState.hasUnlimitedAccess) {
                            PaywallTrialTimeline(trialPlan)
                        }
                        if (!billingState.hasUnlimitedAccess) {
                            SignalCard(
                                modifier = Modifier.fillMaxWidth(),
                                radius = SignalMetrics.GroupRadius,
                                color = c.cardLowest,
                                borderColor = c.border,
                                padding = androidx.compose.foundation.layout.PaddingValues(0.dp),
                            ) {
                                Box(Modifier.padding(16.dp)) {
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
                                Box(Modifier.padding(16.dp)) {
                                    UsageMeter(
                                        voxUiText("Local transcription"),
                                        transcriptionUsage.usedMillis,
                                        transcriptionUsage.limitMillis,
                                        voxFormat("%@ of 15 min used", formatQuotaMinutes(transcriptionUsage.usedMillis)),
                                    )
                                }
                            }
                        }
                        PaywallNote(Icons.Outlined.Lock, c.successSoft, c.successText,
                            voxString("No account to create. Google Play handles payment; your notes, audio and transcripts are never sent with billing checks."))
                        Text(voxString("Purchases are processed by Google Play. Purchase checks contain only the Play product and account transaction state; capture text, audio, files, destinations, and transcripts are never sent with billing traffic."),
                            style = SignalType.caption,
                            color = c.muted,
                        )
                        Text(voxString("If Play is temporarily unavailable, Vox.md keeps the last successfully confirmed paid entitlement on this device. A successful later query applies pending, refund, or cancellation changes."),
                            style = SignalType.caption,
                            color = c.muted,
                        )
                    }
                    else -> {
                        Text(
                            voxString("Choose your plan"),
                            style = MaterialTheme.typography.displaySmall,
                            color = c.text,
                        )
                        val savings = yearlySavingsPercent(
                            plans.firstOrNull { it.plan == VoxPlan.WEEKLY },
                            plans.firstOrNull { it.plan == VoxPlan.YEARLY },
                        )
                        val planLabel = voxString("Choose your plan")
                        Column(
                            Modifier.selectableGroup().semantics { contentDescription = planLabel },
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            plans.forEach { option ->
                                PaywallPlanRow(
                                    option = option,
                                    selected = option == selected,
                                    savingsPercent = savings.takeIf { option.plan == VoxPlan.YEARLY },
                                    enabled = !billingState.isPurchasing,
                                    onSelect = { selectedName = option.plan.name },
                                )
                            }
                        }
                        if (plans.any { it.plan.isSubscription }) {
                            Text(voxString("Cancel anytime in Google Play › Payments & subscriptions. Access belongs to the Google Play account that buys it; Apple purchases don’t transfer."),
                                style = SignalType.caption,
                                color = c.muted,
                            )
                        }
                        Text(voxString("On Android, Unlimited applies only to the Google Play account that purchased it. Google Play does not share in-app purchases through Family Library, and Apple purchases do not transfer."),
                            style = SignalType.caption,
                            color = c.muted,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun periodWord(option: VoxPlanOption): String =
    voxString(if (option.plan == VoxPlan.WEEKLY) "per week" else "per year")

/** Footer line under the page dots for the selected plan, priced from Play. */
@Composable
internal fun paywallSummary(option: VoxPlanOption): String = when {
    option.plan == VoxPlan.LIFETIME -> voxFormat("%@, once. No subscription.", option.formattedPrice)
    isoPeriodDays(option.freeTrialPeriod) == 7 -> voxFormat("7 days free, then %@ %@. Auto-renews.", option.formattedPrice, periodWord(option))
    option.hasFreeTrial -> voxFormat("Free trial, then %@ %@. Auto-renews.", option.formattedPrice, periodWord(option))
    else -> voxFormat("%@ %@. Auto-renews until canceled.", option.formattedPrice, periodWord(option))
}

@Composable
internal fun paywallCallToAction(option: VoxPlanOption): String = when {
    option.plan == VoxPlan.LIFETIME -> voxFormat("Unlock for %@", option.formattedPrice)
    isoPeriodDays(option.freeTrialPeriod) == 7 -> voxString("Start 7-Day Free Trial")
    option.hasFreeTrial -> voxString("Start Free Trial")
    else -> voxString("Subscribe")
}

/** End of a free trial that starts now, from the offer's own trial period. */
internal fun trialEndEpochMillis(option: VoxPlanOption, nowEpochMillis: Long): Long? =
    isoPeriodDays(option.freeTrialPeriod)?.let { nowEpochMillis + it * 86_400_000L }

/**
 * Page 2: how the free trial works. Two steps only, because Vox.md does not schedule a
 * reminder notification before the trial ends.
 */
@Composable
private fun PaywallTrialTimeline(option: VoxPlanOption) {
    val c = Signal.colors
    val end = trialEndEpochMillis(option, System.currentTimeMillis()) ?: return
    val endDate = java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date(end))
    Text(voxString("How your free trial works"), style = MaterialTheme.typography.displaySmall, color = c.text)
    Text(
        voxFormat("Use everything free until %@. Cancel before then and you pay nothing.", endDate),
        style = MaterialTheme.typography.bodyLarge,
        color = c.muted,
    )
    Column {
        PaywallTimelineStep(
            label = voxString("Today"),
            title = voxString("Everything unlocks"),
            detail = voxString("Unlimited captures and transcription on every entry point."),
            icon = Icons.Outlined.LockOpen,
            done = true,
            last = false,
        )
        PaywallTimelineStep(
            label = endDate,
            title = voxString("Trial ends"),
            detail = voxFormat("Your plan starts at %@ %@. Cancel anytime in Google Play.", option.formattedPrice, periodWord(option)),
            icon = Icons.Outlined.CheckCircle,
            done = false,
            last = true,
        )
    }
}

@Composable
private fun PaywallTimelineStep(
    label: String,
    title: String,
    detail: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    done: Boolean,
    last: Boolean,
) {
    val c = Signal.colors
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.height(IntrinsicSize.Min)) {
        Column(Modifier.width(40.dp).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                Modifier.size(40.dp).clip(CircleShape).background(if (done) c.accent else c.secondarySoft),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = if (done) c.onAccent else c.secondaryText, modifier = Modifier.size(20.dp))
            }
            if (!last) Box(Modifier.padding(vertical = 4.dp).width(2.dp).weight(1f).background(c.border))
        }
        Column(Modifier.padding(top = 6.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label.uppercase(), style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.04.em), color = c.tint)
            Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold, fontSize = 17.sp), color = c.text)
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = c.muted)
        }
    }
}

/**
 * Page 1 example: a 12-second voice note, transcribed on-device into today's Inbox note,
 * as a `surfaceContainerLowest` card with a level strip, a mono band and the Markdown.
 */
@Composable
private fun PaywallExampleCard() {
    val c = Signal.colors
    val description = voxString("Transcribed on-device")
    val heights = listOf(6, 10, 16, 9, 20, 24, 14, 8, 18, 22, 12, 6, 10, 19, 24, 15, 9, 13, 21, 17, 8, 11, 16, 7, 12, 9, 5, 4, 6, 4)
    val notePath = voxString("Inbox") + "/" + java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date()) + ".md"
    val task = "- [ ] " + voxString("Call Sam about the venue")
    val link = voxString("Weekly review")
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(c.cardLowest)
            .semantics(mergeDescendants = true) { contentDescription = description },
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(c.recording))
            Text(formatRecordingElapsed(12_000), style = SignalType.mono, color = c.text)
            Row(Modifier.weight(1f).height(24.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                heights.forEachIndexed { index, h ->
                    Box(Modifier.size(width = 3.dp, height = h.dp).clip(RoundedCornerShape(2.dp)).background(if (index < 19) c.accent else c.border))
                }
            }
        }
        Text(
            description.uppercase(),
            style = SignalType.monoCaption.copy(fontSize = 11.sp, letterSpacing = 0.04.em),
            color = c.muted,
            modifier = Modifier.fillMaxWidth().background(c.container).padding(horizontal = 16.dp, vertical = 8.dp),
        )
        Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(notePath, style = SignalType.monoCaption, color = c.muted)
            Text(
                buildAnnotatedString {
                    append(task)
                    append("\n- ")
                    withStyle(SpanStyle(background = c.accentSoft, color = c.accentText)) { append("[[" + link + "]]") }
                },
                style = SignalType.mono,
                color = c.text,
            )
        }
    }
}

/** One plan as a radio card from the plans board: Yearly carries the computed Save badge. */
@Composable
private fun PaywallPlanRow(
    option: VoxPlanOption,
    selected: Boolean,
    savingsPercent: Int?,
    enabled: Boolean,
    onSelect: () -> Unit,
) {
    val c = Signal.colors
    val shape = RoundedCornerShape(20.dp)
    val title = voxString(when (option.plan) {
        VoxPlan.YEARLY -> "Yearly"
        VoxPlan.WEEKLY -> "Weekly"
        VoxPlan.LIFETIME -> "Lifetime"
    })
    val note = when {
        option.plan == VoxPlan.LIFETIME -> voxString("One purchase, no renewals")
        isoPeriodDays(option.freeTrialPeriod) == 7 -> voxString("7-day free trial")
        option.hasFreeTrial -> voxString("Free trial")
        else -> listOf(option.formattedPrice, periodWord(option)).joinToString(" ")
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .clip(shape)
            .background(if (selected) c.secondarySoft else c.card)
            .border(if (selected) 2.dp else 1.dp, if (selected) c.accent else c.border, shape)
            .selectable(selected = selected, enabled = enabled, role = Role.RadioButton, onClick = onSelect)
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .testTag("plan-${option.plan.name.lowercase()}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier.size(20.dp).clip(CircleShape).border(2.dp, if (selected) c.accent else c.borderHi, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) Box(Modifier.size(10.dp).clip(CircleShape).background(c.accent))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = if (selected) c.secondaryText else c.text)
                savingsPercent?.let {
                    Text(
                        voxFormat("Save %@", formatSavingsPercent(it)),
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                        color = c.accentText,
                        modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(c.accentSoft).padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                }
            }
            Text(note, style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp, lineHeight = 18.sp), color = c.muted)
        }
        Text(option.formattedPrice, style = SignalType.mono.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium), color = if (selected) c.secondaryText else c.text)
    }
}

/** Three 8dp page dots (decorative; pages change by swiping); the current one is primary. */
@Composable
private fun PaywallPageDots(current: Int, count: Int) {
    val c = Signal.colors
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.height(20.dp)) {
        repeat(count) { page ->
            Box(
                Modifier
                    .size(width = if (page == current) 20.dp else 8.dp, height = 8.dp)
                    .clip(CircleShape)
                    .background(if (page == current) c.accent else c.border),
            )
        }
    }
}

@Composable
private fun PaywallNote(icon: androidx.compose.ui.graphics.vector.ImageVector, fill: androidx.compose.ui.graphics.Color, ink: androidx.compose.ui.graphics.Color, text: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(fill)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.padding(top = 1.dp).size(18.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = ink)
    }
}

/** Numbered indigo tile (or a green check once Unlimited is active) beside a benefit. */
@Composable
private fun BenefitRow(number: Int, text: VoxUiText, unlocked: Boolean) {
    val c = Signal.colors
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(24.dp),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = if (unlocked) c.success else c.tint, modifier = Modifier.size(22.dp))
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
