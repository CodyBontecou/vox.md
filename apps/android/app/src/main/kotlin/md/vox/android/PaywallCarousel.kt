package md.vox.android

import android.text.format.DateFormat
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.launch
import md.vox.android.ui.GeistFontFamily
import md.vox.android.ui.GeistMonoFontFamily
import md.vox.android.ui.VoxColors

private enum class PaywallPage { BENEFIT, TRIAL, PLANS }

private const val PRIVACY_URL = "https://vox.isolated.tech/privacy.html"

/** Above this font scale the footer scrolls with the page instead of pinning, so it never covers content. */
private const val PINNED_FOOTER_MAX_FONT_SCALE = 1.3f

/** Mockup roles mapped onto the Vox theme so light and dark both work. */
private data class PaywallColors(
    val card: Color,
    val border: Color,
    val muted: Color,
    val primary: Color,
    val onPrimary: Color,
    val accentContainer: Color,
    val success: Color,
    val successContainer: Color,
    val record: Color,
    val inactive: Color,
    val strip: Color,
    val stripBorder: Color,
)

@Composable
private fun paywallColors(): PaywallColors {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.luminance() < 0.5f
    val success = if (dark) VoxColors.GreenDark else VoxColors.Green
    return PaywallColors(
        card = if (dark) VoxColors.CardDark else VoxColors.CardLight,
        border = scheme.outline,
        muted = scheme.onSurfaceVariant,
        primary = scheme.primary,
        onPrimary = scheme.onPrimary,
        accentContainer = scheme.primary.copy(alpha = if (dark) 0.22f else 0.14f),
        success = success,
        successContainer = success.copy(alpha = if (dark) 0.18f else 0.14f),
        record = scheme.error,
        inactive = scheme.onSurface.copy(alpha = 0.24f),
        strip = scheme.onSurface.copy(alpha = 0.04f),
        stripBorder = scheme.onSurface.copy(alpha = 0.10f),
    )
}

@Composable
internal fun PaywallCarousel(
    billingState: BillingUiState,
    purchase: (PaywallPlanKind) -> Unit,
    restore: () -> Unit,
    initialPage: Int,
    today: LocalDate,
    modifier: Modifier = Modifier,
) {
    val colors = paywallColors()
    val plans = billingState.plans
    var chosenKind by rememberSaveable { mutableStateOf<PaywallPlanKind?>(null) }
    val selectedKind = chosenKind?.takeIf { kind -> plans.any { it.kind == kind } } ?: defaultPaywallPlanKind(plans)
    val selectedPlan = billingState.plan(selectedKind)
    val trialPlan = trialTimelinePlan(plans, selectedKind)
    // The trial explainer only appears when Play actually offers an eligible free trial.
    val pages = remember(trialPlan != null) {
        buildList {
            add(PaywallPage.BENEFIT)
            if (trialPlan != null) add(PaywallPage.TRIAL)
            add(PaywallPage.PLANS)
        }
    }
    val pagerState = rememberPagerState(initialPage = initialPage.coerceIn(0, pages.lastIndex)) { pages.size }
    val pinFooter = LocalDensity.current.fontScale <= PINNED_FOOTER_MAX_FONT_SCALE
    val message = billingMessage(billingState)

    val pageContent: @Composable (Int) -> Unit = { index ->
        when (pages.getOrNull(index)) {
            PaywallPage.BENEFIT -> BenefitSlide(colors, today)
            PaywallPage.TRIAL -> trialPlan?.let { TrialSlide(colors, it, today) }
            PaywallPage.PLANS -> PlansSlide(colors, billingState, selectedKind) { chosenKind = it }
            null -> Unit
        }
    }
    val footer: @Composable () -> Unit = {
        PaywallFooter(
            colors = colors,
            billingState = billingState,
            pagerState = pagerState,
            plansPageIndex = pages.indexOf(PaywallPage.PLANS),
            selectedKind = selectedKind,
            selectedPlan = selectedPlan,
            purchase = purchase,
            restore = restore,
        )
    }

    if (pinFooter) {
        Column(modifier.fillMaxSize()) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f).fillMaxWidth(),
                verticalAlignment = Alignment.Top,
            ) { index ->
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(start = 24.dp, end = 24.dp, top = 8.dp, bottom = 16.dp),
                ) { pageContent(index) }
            }
            // The pinned footer scrolls on its own if it ever outgrows the space (e.g. landscape).
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
                message?.let {
                    BillingMessageCard(billingState, it, Modifier.padding(horizontal = 24.dp).padding(top = 8.dp))
                }
                footer()
            }
        }
    } else {
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
            ) { index ->
                Column(Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 8.dp, bottom = 16.dp)) {
                    pageContent(index)
                }
            }
            message?.let {
                BillingMessageCard(billingState, it, Modifier.padding(horizontal = 24.dp).padding(top = 8.dp))
            }
            footer()
        }
    }
}

// region Slide 1 — core benefit

private val WaveformHeights = listOf(
    6, 10, 16, 9, 20, 24, 14, 8, 18, 22, 12, 6, 10, 19, 24, 15, 9, 13, 21, 17, 8, 11, 16, 7, 12, 9, 5, 4, 6, 4,
)
private const val WAVEFORM_PLAYED_BARS = 19

@Composable
private fun BenefitSlide(colors: PaywallColors, today: LocalDate) {
    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
        PaywallHeadline(voxString("Speak it.\nIt lands in your vault."))
        CaptureIllustration(colors, today)
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            PaywallBenefit(colors, voxUiText("Unlimited on-device transcription"))
            PaywallBenefit(colors, voxUiText("Keyboard, widget, Quick Settings, Wear OS"))
            PaywallBenefit(colors, voxUiText("Plain Markdown files you own"))
        }
    }
}

@Composable
private fun CaptureIllustration(colors: PaywallColors, today: LocalDate) {
    val mono = TextStyle(fontFamily = GeistMonoFontFamily, color = MaterialTheme.colorScheme.onSurface)
    val illustrationDescription = voxString("Example: a 12-second voice note, transcribed on-device into today’s Markdown note.")
    PaywallCard(colors, Modifier.clearAndSetSemantics { contentDescription = illustrationDescription }) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(colors.record))
            Text(voxString("0:12"), style = mono.copy(fontSize = 13.sp))
            Row(
                modifier = Modifier.weight(1f).height(24.dp).clipToBounds(),
                horizontalArrangement = Arrangement.spacedBy(3.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                WaveformHeights.forEachIndexed { index, height ->
                    Box(
                        Modifier
                            .width(3.dp)
                            .height(height.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(if (index < WAVEFORM_PLAYED_BARS) colors.primary else colors.inactive.copy(alpha = 0.2f)),
                    )
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.stripBorder))
        Row(
            modifier = Modifier.fillMaxWidth().background(colors.strip).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Outlined.ArrowDownward, contentDescription = null, tint = colors.muted, modifier = Modifier.size(14.dp))
            Text(
                voxString("TRANSCRIBED ON-DEVICE"),
                style = mono.copy(fontSize = 11.sp, letterSpacing = 0.4.sp, color = colors.muted),
            )
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.stripBorder))
        Column(
            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                voxFormat("Vault / Inbox / %@.md", today.toString()),
                style = mono.copy(fontSize = 12.sp, color = colors.muted),
            )
            val lineStyle = mono.copy(fontSize = 13.sp, lineHeight = 20.sp)
            Text(voxString("- [ ] Call Sam about the venue"), style = lineStyle)
            val draftFor = voxString("- Draft for ")
            val link = voxString("[[Weekly review]]")
            Text(
                buildAnnotatedString {
                    append(draftFor)
                    withStyle(SpanStyle(color = colors.primary, background = colors.accentContainer)) { append(link) }
                },
                style = lineStyle,
            )
        }
    }
}

@Composable
private fun PaywallBenefit(colors: PaywallColors, text: VoxUiText) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = colors.primary, modifier = Modifier.size(22.dp))
        Text(text.localized(), style = MaterialTheme.typography.bodyLarge)
    }
}

// endregion

// region Slide 2 — trial timeline

@Composable
private fun TrialSlide(colors: PaywallColors, plan: PaywallPlan, today: LocalDate) {
    val trialDays = plan.freeTrialDays ?: return
    val reminderDay = trialReminderDay(trialDays)
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val formatter = remember(locale) {
        DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "MMMd"), locale)
    }
    val endDate = today.plusDays(trialDays.toLong())
    val endLabel = formatter.format(endDate)
    Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            PaywallHeadline(voxString("How your free\ntrial works"))
            Text(
                voxFormat("Use everything for %lld days. Cancel before %@ and you pay nothing.", trialDays, endLabel),
                style = MaterialTheme.typography.bodyLarge,
                color = colors.muted,
            )
        }
        PaywallCard(colors) {
            Column(Modifier.padding(start = 18.dp, end = 18.dp, top = 20.dp, bottom = 6.dp)) {
                TimelineStep(
                    colors = colors,
                    icon = Icons.Outlined.Check,
                    filled = true,
                    label = voxString("TODAY"),
                    title = voxUiText("Everything unlocks"),
                    detail = voxUiText("Unlimited captures and transcription on every entry point."),
                    connector = colors.primary,
                )
                if (reminderDay != null) {
                    TimelineStep(
                        colors = colors,
                        icon = Icons.Outlined.NotificationsNone,
                        filled = false,
                        label = voxFormat("%@ · DAY %lld", formatter.format(today.plusDays(reminderDay.toLong())).uppercase(locale), reminderDay),
                        title = voxUiText("We remind you"),
                        detail = voxUiText("A notification two days before your trial ends."),
                        connector = colors.border,
                    )
                }
                TimelineStep(
                    colors = colors,
                    icon = Icons.Outlined.CalendarToday,
                    filled = false,
                    label = voxFormat("%@ · DAY %lld", endLabel.uppercase(locale), trialDays),
                    title = voxUiText("Trial ends"),
                    detail = if (plan.kind == PaywallPlanKind.WEEKLY) {
                        voxUiText("Your plan starts at %@/wk. Cancel anytime in Google Play.", plan.formattedPrice)
                    } else {
                        voxUiText("Your plan starts at %@/yr. Cancel anytime in Google Play.", plan.formattedPrice)
                    },
                    connector = null,
                )
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(colors.successContainer)
                .padding(horizontal = 16.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                Icons.Outlined.Lock,
                contentDescription = null,
                tint = colors.success,
                modifier = Modifier.padding(top = 1.dp).size(18.dp),
            )
            Text(
                voxString("No account to create. Google Play handles payment; your notes, audio and transcripts are never sent with billing checks."),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun TimelineStep(
    colors: PaywallColors,
    icon: ImageVector,
    filled: Boolean,
    label: String,
    title: VoxUiText,
    detail: VoxUiText,
    connector: Color?,
) {
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.width(36.dp).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(if (filled) colors.primary else colors.card)
                    .then(if (filled) Modifier else Modifier.border(2.dp, colors.inactive, CircleShape)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = if (filled) colors.onPrimary else MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(18.dp),
                )
            }
            if (connector != null) {
                Box(Modifier.width(2.dp).weight(1f).heightIn(min = 28.dp).background(connector))
            }
        }
        Column(
            modifier = Modifier.weight(1f).padding(top = 6.dp, bottom = if (connector != null) 22.dp else 16.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(
                label,
                style = TextStyle(
                    fontFamily = GeistMonoFontFamily,
                    fontSize = 11.sp,
                    letterSpacing = 0.4.sp,
                    color = if (filled) colors.primary else colors.muted,
                ),
            )
            Text(title.localized(), style = MaterialTheme.typography.titleMedium.copy(fontSize = 17.sp))
            Text(detail.localized(), style = MaterialTheme.typography.bodyMedium, color = colors.muted)
        }
    }
}

// endregion

// region Slide 3 — plans

@Composable
private fun PlansSlide(
    colors: PaywallColors,
    billingState: BillingUiState,
    selectedKind: PaywallPlanKind,
    select: (PaywallPlanKind) -> Unit,
) {
    val savings = yearlySavingsPercent(
        billingState.plan(PaywallPlanKind.YEARLY),
        billingState.plan(PaywallPlanKind.WEEKLY),
    )
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(
            voxString("Choose your plan"),
            modifier = Modifier.semantics { heading() },
            style = MaterialTheme.typography.headlineLarge.copy(fontSize = 28.sp, lineHeight = 34.sp, letterSpacing = (-0.5).sp),
        )
        Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            PaywallPlanKind.entries.forEach { kind ->
                PlanRow(
                    colors = colors,
                    kind = kind,
                    plan = billingState.plan(kind),
                    selected = kind == selectedKind && billingState.plan(kind) != null,
                    badge = if (kind == PaywallPlanKind.YEARLY) savings?.let { voxUiText("Save %lld%%", it) } else null,
                    onSelect = { select(kind) },
                )
            }
        }
        Text(
            voxString("Cancel anytime in Google Play › Payments & subscriptions. Access belongs to the Google Play account that buys it; Apple purchases don’t transfer."),
            style = MaterialTheme.typography.bodySmall.copy(lineHeight = 19.sp),
            color = colors.muted,
        )
    }
}

@Composable
private fun PlanRow(
    colors: PaywallColors,
    kind: PaywallPlanKind,
    plan: PaywallPlan?,
    selected: Boolean,
    badge: VoxUiText?,
    onSelect: () -> Unit,
) {
    val available = plan != null
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 68.dp)
            .alpha(if (available) 1f else 0.5f)
            .clip(shape)
            .background(colors.card)
            .border(
                if (selected) BorderStroke(2.dp, colors.primary) else BorderStroke(1.dp, colors.border),
                shape,
            )
            .selectable(selected = selected, enabled = available, role = Role.RadioButton, onClick = onSelect)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier
                .size(20.dp)
                .border(2.dp, if (selected) colors.primary else colors.muted, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) Box(Modifier.size(10.dp).clip(CircleShape).background(colors.primary))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                Text(paywallPlanTitle(kind).localized(), style = MaterialTheme.typography.titleMedium)
                badge?.let {
                    Text(
                        it.localized(),
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(colors.accentContainer)
                            .padding(horizontal = 8.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.primary,
                    )
                }
            }
            Text(
                paywallPlanNote(kind, plan).localized(),
                style = MaterialTheme.typography.bodySmall,
                color = colors.muted,
            )
        }
        plan?.let {
            Text(
                it.formattedPrice,
                style = TextStyle(fontFamily = GeistMonoFontFamily, fontSize = 15.sp, fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

// endregion

// region Shared chrome

@Composable
private fun PaywallFooter(
    colors: PaywallColors,
    billingState: BillingUiState,
    pagerState: PagerState,
    plansPageIndex: Int,
    selectedKind: PaywallPlanKind,
    selectedPlan: PaywallPlan?,
    purchase: (PaywallPlanKind) -> Unit,
    restore: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current
    val onPlansPage = pagerState.currentPage == plansPageIndex
    Column(
        modifier = Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 14.dp, bottom = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        PageDots(colors, pagerState) { page -> scope.launch { pagerState.animateScrollToPage(page) } }
        paywallSummary(selectedPlan)?.let { summary ->
            Text(
                summary.localized(),
                style = MaterialTheme.typography.bodyMedium,
                color = colors.muted,
                textAlign = TextAlign.Center,
            )
        }
        Button(
            onClick = { purchase(selectedKind) },
            enabled = selectedPlan != null &&
                billingState.entitlement == VoxEntitlement.FREE &&
                billingState.connectionPhase == BillingConnectionPhase.READY,
            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
            shape = RoundedCornerShape(28.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.primary, contentColor = colors.onPrimary),
            contentPadding = PaddingValues(horizontal = 24.dp, vertical = 12.dp),
        ) {
            Text(
                paywallCallToAction(selectedPlan, billingState.entitlement).localized(),
                style = TextStyle(fontFamily = GeistFontFamily, fontSize = 16.sp, fontWeight = FontWeight.Medium),
                textAlign = TextAlign.Center,
            )
        }
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (!onPlansPage) {
                PaywallTextButton(voxUiText("See all plans"), colors.primary) {
                    scope.launch { pagerState.animateScrollToPage(plansPageIndex) }
                }
            }
            PaywallTextButton(
                voxUiText("Restore purchase"),
                colors.primary,
                enabled = billingState.connectionPhase != BillingConnectionPhase.CONNECTING,
                onClick = restore,
            )
            if (onPlansPage) {
                PaywallTextButton(voxUiText("Privacy"), colors.muted) {
                    runCatching { uriHandler.openUri(PRIVACY_URL) }
                }
            }
        }
    }
}

@Composable
private fun PageDots(colors: PaywallColors, pagerState: PagerState, onSelect: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(0.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(pagerState.pageCount) { page ->
            val current = page == pagerState.currentPage
            val description = if (current) {
                voxFormat("Page %lld of %lld, current", page + 1, pagerState.pageCount)
            } else {
                voxFormat("Page %lld of %lld", page + 1, pagerState.pageCount)
            }
            Box(
                modifier = Modifier
                    .size(width = 24.dp, height = 24.dp)
                    .clip(CircleShape)
                    .clickable(role = Role.Tab, onClick = { onSelect(page) })
                    .semantics {
                        contentDescription = description
                        selected = current
                    },
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(if (current) colors.primary else colors.inactive))
            }
        }
    }
}

@Composable
private fun PaywallTextButton(
    label: VoxUiText,
    color: Color,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.heightIn(min = 40.dp),
        shape = RoundedCornerShape(20.dp),
        contentPadding = PaddingValues(horizontal = 12.dp),
    ) {
        Text(
            label.localized(),
            style = TextStyle(fontFamily = GeistFontFamily, fontSize = 14.sp, fontWeight = FontWeight.Medium),
            color = if (enabled) color else color.copy(alpha = 0.38f),
        )
    }
}

@Composable
private fun PaywallHeadline(text: String) {
    Text(
        text,
        modifier = Modifier.semantics { heading() },
        style = MaterialTheme.typography.headlineLarge.copy(letterSpacing = (-0.6).sp),
    )
}

@Composable
private fun PaywallCard(
    colors: PaywallColors,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.card)
            .border(1.dp, colors.border, shape),
    ) { content() }
}

// endregion
