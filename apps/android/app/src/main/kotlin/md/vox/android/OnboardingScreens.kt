package md.vox.android

import android.app.Activity
import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import java.util.UUID
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureHeadingPosition
import md.vox.android.capturedomain.CaptureMissingHeadingBehavior
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureRollingPeriod
import md.vox.android.ui.GeistFontFamily
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalBanner
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalDivider
import md.vox.android.ui.SignalIconTile
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalRouteTile
import md.vox.android.ui.SignalRouteTone
import md.vox.android.ui.SignalStatus
import md.vox.android.ui.SignalType
import md.vox.android.ui.SignalWordmark
import md.vox.android.ui.VoxTheme

/**
 * One-time first-run state. Stored with the app's other local settings ("vox-settings"), which
 * the backup rules already exclude, so a restored or transferred install never skips setup for a
 * vault grant it does not hold.
 */
internal object OnboardingPreferences {
    private const val FILE = "vox-settings"
    private const val COMPLETED_KEY = "onboarding.completed.v1"

    fun isCompleted(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(COMPLETED_KEY, false)

    fun markCompleted(context: Context) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean(COMPLETED_KEY, true).apply()
    }
}

/**
 * The four routes offered during setup (iOS `StarterRoute`). Each becomes an ordinary, editable
 * capture preset that writes into the chosen vault. Declaration order is the Setup board's row
 * order; [installOrder] is the Routes board's order.
 */
internal enum class StarterRoute(
    val nameSource: String,
    /** Path label on the setup row; matches what the preset below writes on Android. */
    val pathLabel: String,
    val isOnByDefault: Boolean,
) {
    INBOX("Inbox", "Inbox/{timestamp}.md", true),
    MEETING_NOTES("Meeting Notes", "Meetings/{date}.md", true),
    TASKS("Tasks", "Tasks/Tasks.md › ## Today", true),
    JOURNAL("Journal", "Journal/{week}.md", false);

    val promptSource: String
        get() = when (this) {
            INBOX -> "What’s on your mind?"
            MEETING_NOTES -> "What was decided?"
            TASKS -> "What needs doing?"
            JOURNAL -> "How was today?"
        }

    /** Builds the preset with localized [name] and [prompt] (resolved by the caller's locale). */
    fun preset(name: String, prompt: String): CapturePreset {
        val base = CapturePreset(
            id = UUID.randomUUID().toString().lowercase(),
            name = name,
            symbol = "description",
            revision = 1,
            logicalFolder = "Inbox",
            noteNameTemplate = "capture-{id}.md",
            metadataFields = emptyList(),
            capturePrompt = prompt,
        )
        return when (this) {
            INBOX -> base.copy(
                noteNameTemplate = "{timestamp}.md",
                processingEnabled = true,
                processingMode = CaptureProcessingMode.CLEAN,
            )
            MEETING_NOTES -> base.copy(
                symbol = "work",
                noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE,
                rollingPeriod = CaptureRollingPeriod.DAILY,
                logicalFolder = "Meetings",
                noteNameTemplate = "{date}.md",
                placement = CapturePlacementKind.BENEATH_HEADING,
                headingTitle = "Notes",
                headingLevel = 2,
                missingHeadingBehavior = CaptureMissingHeadingBehavior.CREATE,
                headingPosition = CaptureHeadingPosition.BOTTOM,
                entryPrefix = "### {hour}:{minute}\n",
                processingEnabled = true,
                processingMode = CaptureProcessingMode.MEETING_NOTES,
            )
            // A rolling note (not an existing note) so the first capture creates the file.
            TASKS -> base.copy(
                symbol = "checklist",
                noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE,
                logicalFolder = "Tasks",
                noteNameTemplate = "Tasks.md",
                placement = CapturePlacementKind.BENEATH_HEADING,
                headingTitle = "Today",
                headingLevel = 2,
                missingHeadingBehavior = CaptureMissingHeadingBehavior.CREATE,
                headingPosition = CaptureHeadingPosition.TOP,
                processingEnabled = true,
                processingMode = CaptureProcessingMode.TODO_LIST,
            )
            JOURNAL -> base.copy(
                noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE,
                rollingPeriod = CaptureRollingPeriod.WEEKLY,
                logicalFolder = "Journal",
                noteNameTemplate = "{week}.md",
                placement = CapturePlacementKind.PREPEND,
                processingEnabled = false,
                processingMode = CaptureProcessingMode.NONE,
            )
        }
    }

    companion object {
        val installOrder = listOf(MEETING_NOTES, INBOX, JOURNAL, TASKS)
        val defaultSelection: Set<StarterRoute> = entries.filter { it.isOnByDefault }.toSet()
    }
}

/** Localized presets for [selection] in [StarterRoute.installOrder]; Meeting Notes is the default route. */
@Composable
internal fun starterPresets(selection: Set<StarterRoute>): List<Pair<StarterRoute, CapturePreset>> =
    StarterRoute.installOrder.filter { it in selection }.map { route ->
        route to route.preset(voxString(route.nameSource), voxString(route.promptSource))
    }

/**
 * Signal first run: the always-dark Welcome page, then Setup ("Where should notes land?" with the
 * vault card and the "Start with these routes" checklist). Folder picking reuses the app's SAF tree
 * picker through [onChooseFolder]; [onStartCapturing] receives the chosen starter routes once a
 * destination exists.
 */
@Composable
internal fun FirstRunFlow(
    destination: CaptureDestination?,
    notice: String?,
    isBusy: Boolean,
    onChooseFolder: () -> Unit,
    onStartCapturing: (Set<StarterRoute>) -> Unit,
) {
    var page by rememberSaveable { mutableStateOf(0) }
    var selectedNames by rememberSaveable { mutableStateOf(StarterRoute.defaultSelection.map { it.name }) }
    val selection = selectedNames.mapNotNull { name -> StarterRoute.entries.firstOrNull { it.name == name } }.toSet()
    if (page == 0) {
        OnboardingWelcomeScreen(onGetStarted = { page = 1 })
    } else {
        BackHandler { page = 0 }
        OnboardingSetupScreen(
            destination = destination,
            notice = notice,
            selection = selection,
            isBusy = isBusy,
            onToggle = { route ->
                selectedNames = if (route in selection) selectedNames - route.name else selectedNames + route.name
            },
            onChooseFolder = onChooseFolder,
            onStartCapturing = { onStartCapturing(selection) },
        )
    }
}

/** Shared scrolling page frame: content fills the screen at default sizes and scrolls when larger. */
@Composable
private fun OnboardingPage(
    horizontalPadding: androidx.compose.ui.unit.Dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(modifier = Modifier.fillMaxSize(), color = Signal.colors.bg) {
        BoxWithConstraints(
            Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding(),
            contentAlignment = Alignment.TopCenter,
        ) {
            val minHeight = maxHeight
            Column(
                modifier = Modifier
                    .widthIn(max = 520.dp)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .heightIn(min = minHeight)
                    .padding(horizontal = horizontalPadding)
                    .padding(top = 16.dp, bottom = 24.dp),
                content = content,
            )
        }
    }
}

/** Project license identifier shown under Welcome; kept verbatim like the license name itself. */
private const val WELCOME_LICENSE_LINE = "Open source · AGPL-3.0"

/** Welcome board: wordmark, hero line, the Tasks example, local-first bullets and Get started. */
@Composable
internal fun OnboardingWelcomeScreen(onGetStarted: () -> Unit) {
    WelcomeSystemBars()
    VoxTheme(darkTheme = true) {
        val c = Signal.colors
        OnboardingPage(horizontalPadding = 24.dp) {
            SignalWordmark(extensionColor = c.tint)
            Spacer(Modifier.height(48.dp))
            Text(
                voxString("Say it.\nIt lands in\nMarkdown."),
                style = MaterialTheme.typography.displayMedium.copy(
                    fontFamily = GeistFontFamily,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 46.sp,
                    lineHeight = 47.sp,
                    letterSpacing = (-0.035).em,
                ),
                color = c.text,
                modifier = Modifier.semantics { heading() },
            )
            Spacer(Modifier.height(36.dp))
            WelcomeExample()
            Spacer(Modifier.weight(1f).heightIn(min = 40.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                WelcomeBullet(voxString("Transcribed on this device"))
                WelcomeBullet(voxString("Written to your Obsidian vault or Files"))
                WelcomeBullet(voxString("Your words are never sent to us"))
            }
            Spacer(Modifier.height(28.dp))
            SignalButton(
                text = voxString("Get started"),
                onClick = onGetStarted,
                modifier = Modifier.testTag("onboarding.continue"),
            )
            Spacer(Modifier.height(14.dp))
            Text(
                WELCOME_LICENSE_LINE,
                style = SignalType.caption.copy(fontSize = 13.sp),
                color = c.faint,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun WelcomeExample() {
    val c = Signal.colors
    val description = voxString("Example: say “Remind me to book flights for Lisbon” and it lands in Tasks.md under Today as a task.")
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.clearAndSetSemantics { contentDescription = description },
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(
                Modifier.size(28.dp).background(c.recording, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.Mic, contentDescription = null, tint = c.onRecording, modifier = Modifier.size(14.dp))
            }
            Text(
                voxString("“Remind me to book flights for Lisbon”"),
                style = MaterialTheme.typography.bodyLarge,
                color = c.text.copy(alpha = 0.72f),
                modifier = Modifier.weight(1f),
            )
        }
        Box(Modifier.padding(start = 13.dp).width(2.dp).height(18.dp).background(c.borderHi))
        SignalCard(
            modifier = Modifier.fillMaxWidth(),
            radius = 14.dp,
            padding = PaddingValues(14.dp),
        ) {
            Text("Tasks.md › ## Today", style = SignalType.mono, color = c.faint)
            Text(voxString("- [ ] Book flights for Lisbon"), style = SignalType.mono, color = c.text)
        }
    }
}

@Composable
private fun WelcomeBullet(text: String) {
    val c = Signal.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(6.dp).background(c.tint, CircleShape))
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp),
            color = c.text.copy(alpha = 0.8f),
        )
    }
}

/** The Welcome artboard is always dark, so the system bars use light icons while it shows. */
@Composable
private fun WelcomeSystemBars() {
    val view = LocalView.current
    if (view.isInEditMode) return
    DisposableEffect(view) {
        val window = (view.context as? Activity)?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        val lightStatus = controller?.isAppearanceLightStatusBars
        val lightNavigation = controller?.isAppearanceLightNavigationBars
        controller?.isAppearanceLightStatusBars = false
        controller?.isAppearanceLightNavigationBars = false
        onDispose {
            if (lightStatus != null) controller.isAppearanceLightStatusBars = lightStatus
            if (lightNavigation != null) controller.isAppearanceLightNavigationBars = lightNavigation
        }
    }
}

/** Setup board, in the system appearance: step bar, vault card, starter-route checklist, Start capturing. */
@Composable
internal fun OnboardingSetupScreen(
    destination: CaptureDestination?,
    notice: String?,
    selection: Set<StarterRoute>,
    isBusy: Boolean,
    onToggle: (StarterRoute) -> Unit,
    onChooseFolder: () -> Unit,
    onStartCapturing: () -> Unit,
) {
    val c = Signal.colors
    val stepLabel = voxString("Step 2 of 2")
    OnboardingPage(horizontalPadding = 20.dp) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
                .clearAndSetSemantics { contentDescription = stepLabel },
        ) {
            repeat(2) { Box(Modifier.weight(1f).height(4.dp).background(c.text, CircleShape)) }
        }
        Spacer(Modifier.height(28.dp))
        Text(
            voxString("Where should\nnotes land?"),
            style = MaterialTheme.typography.headlineLarge.copy(
                fontFamily = GeistFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 32.sp,
                lineHeight = 35.sp,
                letterSpacing = (-0.025).em,
            ),
            color = c.text,
            modifier = Modifier.semantics { heading() },
        )
        Spacer(Modifier.height(20.dp))
        VaultFolderCard(destination = destination, enabled = !isBusy, onChooseFolder = onChooseFolder)
        Spacer(Modifier.height(28.dp))
        Text(
            voxString("Start with these routes"),
            style = SignalType.sectionLabel.copy(fontSize = 15.sp),
            color = c.text,
            modifier = Modifier.semantics { heading() },
        )
        Spacer(Modifier.height(4.dp))
        Text(voxString("You can edit or add more any time."), style = SignalType.caption, color = c.muted)
        Spacer(Modifier.height(12.dp))
        SignalCard(
            modifier = Modifier.fillMaxWidth(),
            radius = SignalMetrics.GroupRadius,
            borderColor = c.border,
            padding = PaddingValues(horizontal = 14.dp),
        ) {
            StarterRoute.entries.forEachIndexed { index, route ->
                if (index > 0) SignalDivider()
                StarterRouteRow(route, isOn = route in selection, enabled = !isBusy, onToggle = { onToggle(route) })
            }
        }
        if (notice != null) {
            Spacer(Modifier.height(12.dp))
            SignalBanner(message = notice, status = SignalStatus.WARNING, icon = Icons.Outlined.FolderOpen, liveRegion = true)
        } else if (destination == null && selection.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Text(voxString("Choose a folder so these routes know where to write."), style = SignalType.caption, color = c.muted)
        }
        Spacer(Modifier.weight(1f).heightIn(min = 32.dp))
        SignalButton(
            text = voxString("Start capturing"),
            onClick = if (destination == null) onChooseFolder else onStartCapturing,
            loading = isBusy,
            modifier = Modifier.testTag("onboarding.start"),
        )
    }
}

/** Setup board vault card: ink-bordered, folder tile, folder name and a Choose / Change affordance. */
@Composable
private fun VaultFolderCard(destination: CaptureDestination?, enabled: Boolean, onChooseFolder: () -> Unit) {
    val c = Signal.colors
    val shape = RoundedCornerShape(SignalMetrics.GroupRadius)
    val action = if (destination == null) voxString("Choose") else voxString("Change")
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = SignalMetrics.ControlLarge)
            .background(c.card, shape)
            .border(1.5.dp, if (destination == null) c.borderHi else c.text, shape)
            .clickable(enabled = enabled, role = Role.Button, onClickLabel = action, onClick = onChooseFolder)
            .padding(14.dp)
            .testTag("onboarding.folder"),
    ) {
        Box(
            Modifier.size(40.dp).background(c.inverse, RoundedCornerShape(12.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Outlined.FolderOpen, contentDescription = null, tint = c.onInverse, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                destination?.displayName?.takeIf(String::isNotBlank) ?: voxString("Choose a folder"),
                style = SignalType.rowTitle.copy(fontWeight = FontWeight.SemiBold),
                color = c.text,
            )
            if (destination == null) {
                Text(
                    voxString("An Obsidian vault or any folder in Files"),
                    style = SignalType.monoCaption,
                    color = c.muted,
                )
            }
        }
        Text(action, style = MaterialTheme.typography.labelLarge, color = c.accentText)
    }
}

/** Setup board row: route tile (ink when chosen), name, mono path and a trailing checkbox. */
@Composable
private fun StarterRouteRow(route: StarterRoute, isOn: Boolean, enabled: Boolean, onToggle: () -> Unit) {
    val c = Signal.colors
    val name = voxString(route.nameSource)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 60.dp)
            .toggleable(value = isOn, enabled = enabled, role = Role.Checkbox, onValueChange = { onToggle() })
            .padding(vertical = 8.dp)
            .testTag("onboarding.starter.${route.name.lowercase()}"),
    ) {
        SignalRouteTile(label = name, size = 32.dp, tone = if (isOn) SignalRouteTone.INK else SignalRouteTone.NEUTRAL)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(name, style = SignalType.rowTitle, color = c.text)
            Text(route.pathLabel, style = SignalType.monoCaption.copy(fontSize = 11.sp), color = c.muted)
        }
        Checkbox(
            checked = isOn,
            onCheckedChange = null,
            enabled = enabled,
            colors = CheckboxDefaults.colors(checkedColor = c.tint, uncheckedColor = c.borderHi, checkmarkColor = c.onAccent),
        )
    }
}

/**
 * Folder repair (and the fallback for anyone past first run without a destination): follows the
 * system appearance, leads with the problem when [notice] is set, and keeps the folder action at
 * the end of the scrolling content so it stays reachable at large text sizes.
 */
@Composable
internal fun VaultSetupScreen(notice: String?, onChooseFolder: () -> Unit) {
    val c = Signal.colors
    OnboardingPage(horizontalPadding = 24.dp) {
        SignalWordmark(extensionColor = c.accentText)
        Spacer(Modifier.height(40.dp))
        Text(
            voxString("Where should\nnotes land?"),
            style = MaterialTheme.typography.headlineLarge,
            color = c.text,
            modifier = Modifier.semantics { heading() },
        )
        Spacer(Modifier.height(12.dp))
        Text(voxString("Choose a vault or folder."), style = MaterialTheme.typography.bodyLarge, color = c.muted)
        if (notice != null) {
            Spacer(Modifier.height(24.dp))
            SignalBanner(message = notice, status = SignalStatus.WARNING, icon = Icons.Outlined.FolderOpen, liveRegion = true)
        }
        Spacer(Modifier.height(28.dp))
        SignalCard(
            modifier = Modifier.fillMaxWidth(),
            radius = SignalMetrics.GroupRadius,
            padding = PaddingValues(horizontal = 14.dp, vertical = 14.dp),
            onClick = onChooseFolder,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SignalIconTile(Icons.Outlined.FolderOpen, primary = true, size = 40.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(voxString("Everything stays on this device."), style = SignalType.rowTitle, color = c.text)
                    Text(
                        voxString("Your captured text is processed locally and is not sent to a cloud AI service."),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                }
            }
        }
        Spacer(Modifier.weight(1f).heightIn(min = 32.dp))
        SignalButton(
            text = voxString("Choose vault or folder"),
            onClick = onChooseFolder,
            icon = Icons.Outlined.FolderOpen,
        )
    }
}
