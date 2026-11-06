package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.CaptureHeadingPosition
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureProcessingScope
import md.vox.android.capturedomain.CaptureRollingPeriod
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.ui.GeistMonoFontFamily
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalType
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

// region Route wording (Routes and Route editor boards; mirrors iOS FlowSettingsView)

/** The four numbered steps of the route editor rail. */
internal enum class RouteEditorStep(val number: Int, val kindSource: String) {
    CAPTURE(1, "Capture"),
    PROCESS(2, "Process"),
    SHAPE(3, "Shape"),
    DELIVER(4, "Deliver");

    /** Localizable step name; literal sources keep the catalog audit static. */
    val kindText: VoxUiText
        get() = when (this) {
            CAPTURE -> voxUiText("Capture")
            PROCESS -> voxUiText("Process")
            SHAPE -> voxUiText("Shape")
            DELIVER -> voxUiText("Deliver")
        }
}

/** Processing mode as it reads on route chips and the PROCESS step ("Meeting summary"). */
internal fun routeProcessUiText(preset: CapturePreset): VoxUiText = when (preset.effectiveProcessingMode()) {
    CaptureProcessingMode.NONE -> voxUiText("Keep original")
    CaptureProcessingMode.CLEAN -> voxUiText("Clean prose")
    CaptureProcessingMode.TODO_LIST -> voxUiText("Checklist")
    CaptureProcessingMode.MEETING_NOTES -> voxUiText("Meeting summary")
    CaptureProcessingMode.CUSTOM -> voxUiText("Custom Instruction")
}

private fun CapturePreset.effectiveProcessingMode(): CaptureProcessingMode =
    if (processingEnabled) processingMode else CaptureProcessingMode.NONE

/**
 * Input chip, from the Routes board: a route that keeps the original is a voice
 * route ("Voice"); Clean prose tidies anything ("Anything"); structured modes
 * shape the modalities their scope covers ("Voice + text", "Voice", "Text").
 */
internal fun routeInputUiText(preset: CapturePreset): VoxUiText {
    val mode = preset.effectiveProcessingMode()
    return when {
        mode == CaptureProcessingMode.NONE -> voxUiText("Voice")
        mode == CaptureProcessingMode.CLEAN && preset.processingScope == CaptureProcessingScope.BOTH -> voxUiText("Anything")
        else -> when (preset.processingScope) {
            CaptureProcessingScope.BOTH -> voxUiText("Voice + text")
            CaptureProcessingScope.VOICE_ONLY -> voxUiText("Voice")
            CaptureProcessingScope.TEXT_ONLY -> voxUiText("Text")
        }
    }
}

/** "append" / "prepend": where in the note, or the heading's section, the entry lands. */
internal fun routePlacementWordUiText(preset: CapturePreset): VoxUiText = when (preset.placement) {
    CapturePlacementKind.APPEND -> voxUiText("append")
    CapturePlacementKind.PREPEND -> voxUiText("prepend")
    CapturePlacementKind.BENEATH_HEADING ->
        if (preset.headingPosition == CaptureHeadingPosition.BOTTOM) voxUiText("append") else voxUiText("prepend")
}

/** Deliver chip: "New note", "Daily · append", "Under heading"… */
@Composable
internal fun routeDeliverLabel(preset: CapturePreset): String = when (preset.noteTargetKind) {
    CaptureNoteTargetKind.NEW_NOTE -> voxString("New note")
    CaptureNoteTargetKind.ROLLING_NOTE -> voxFormat(
        "%@ · %@",
        captureRollingPeriodUiText(preset.rollingPeriod).localized(),
        routePlacementWordUiText(preset).localized(),
    )
    CaptureNoteTargetKind.EXISTING_NOTE -> when (preset.placement) {
        CapturePlacementKind.APPEND -> voxString("Append")
        CapturePlacementKind.PREPEND -> voxString("Prepend")
        CapturePlacementKind.BENEATH_HEADING -> voxString("Under heading")
    }
}

/** Input → Process → Deliver chips, or the single Watch recording-only chip. */
@Composable
internal fun routeStepChips(preset: CapturePreset): List<String> =
    if (preset.watchOutputMode == CaptureWatchOutputMode.RECORDING_ONLY) {
        listOf(voxString("Recording Only (Watch)"))
    } else {
        listOf(routeInputUiText(preset).localized(), routeProcessUiText(preset).localized(), routeDeliverLabel(preset))
    }

/** The note path a route writes, as a template: `Meetings/{date}.md`, `Tasks.md`. */
internal fun routeNotePath(preset: CapturePreset): String {
    var path = when (preset.noteTargetKind) {
        CaptureNoteTargetKind.EXISTING_NOTE -> preset.existingNotePath
        CaptureNoteTargetKind.NEW_NOTE, CaptureNoteTargetKind.ROLLING_NOTE ->
            listOf(preset.logicalFolder.trim('/'), preset.noteNameTemplate.trim('/')).filter(String::isNotBlank).joinToString("/")
    }.trim()
    if (path.isNotEmpty() && !path.substringAfterLast('/').contains('.')) path += ".md"
    return path
}

/** `## Today` for heading placements on rolling and existing notes. */
internal fun routeHeadingMarkdown(preset: CapturePreset): String? {
    if (preset.noteTargetKind == CaptureNoteTargetKind.NEW_NOTE) return null
    if (preset.placement != CapturePlacementKind.BENEATH_HEADING || preset.headingTitle.isBlank()) return null
    return "#".repeat(preset.headingLevel.coerceIn(1, 6)) + " " + preset.headingTitle.trim()
}

/**
 * Mono path line: `Vox Notes / Meetings / {date}.md`, or for an existing note with a
 * heading `Vox Notes / Tasks.md › ## Today`. [rootName] is the route's vault (its own
 * destination, else the app's) and is omitted when unknown.
 */
internal fun routeDisplayPath(preset: CapturePreset, rootName: String?, includesHeading: Boolean): String {
    val components = routeNotePath(preset).split('/').filter(String::isNotBlank).toMutableList()
    val root = (preset.destination?.displayName ?: rootName)?.trim().orEmpty()
    if (root.isNotEmpty()) components.add(0, root)
    val path = components.joinToString(" / ")
    val heading = routeHeadingMarkdown(preset)
    return if (includesHeading && heading != null) "$path › $heading" else path
}

/** The Routes list shows the heading in the path only for an existing note. */
internal fun routeListPath(preset: CapturePreset, rootName: String?): String =
    routeDisplayPath(preset, rootName, includesHeading = preset.noteTargetKind == CaptureNoteTargetKind.EXISTING_NOTE)

private fun periodNoteUiText(period: CaptureRollingPeriod): VoxUiText = when (period) {
    CaptureRollingPeriod.DAILY -> voxUiText("Daily note")
    CaptureRollingPeriod.WEEKLY -> voxUiText("Weekly note")
    CaptureRollingPeriod.MONTHLY -> voxUiText("Monthly note")
    CaptureRollingPeriod.QUARTERLY -> voxUiText("Quarterly note")
    CaptureRollingPeriod.YEARLY -> voxUiText("Yearly note")
}

/** One card on the CAPTURE → PROCESS → SHAPE → DELIVER rail. */
internal data class RouteStepSummary(
    val step: RouteEditorStep,
    val title: String,
    val detail: String?,
    val needsAttention: Boolean = false,
)

@Composable
internal fun routeStepSummaries(
    preset: CapturePreset,
    entryTemplateName: String?,
    rootName: String?,
    invalidSteps: Set<RouteEditorStep>,
): List<RouteStepSummary> {
    val captureDetail = buildList {
        if (preset.watchOutputMode == CaptureWatchOutputMode.RECORDING_ONLY) add(voxString("Recording Only (Watch)"))
        if (preset.speakerDiarizationEnabled) add(voxString("Speaker labels"))
        if (preset.locationPolicy.isEnabled) add(voxString("Attach location"))
        if (preset.audioSaveMode != CaptureAudioSaveMode.OFF) add(voxString("Save original audio"))
    }.joinToString(" · ").ifBlank { null }

    val processDetail = if (!preset.processingEnabled) {
        voxString("Processing off · kept as captured")
    } else {
        buildList {
            add(voxString("On-device processing"))
            when (preset.processingScope) {
                CaptureProcessingScope.BOTH -> Unit
                CaptureProcessingScope.VOICE_ONLY -> add(voxString("Voice Only"))
                CaptureProcessingScope.TEXT_ONLY -> add(voxString("Text Only"))
            }
        }.joinToString(" · ")
    }

    val firstLine = preset.entryPrefix.lines().map(String::trim).firstOrNull(String::isNotEmpty)
    val derivedShapeTitle = when {
        firstLine == null -> voxString("Plain entry")
        listOf("{time}", "{timestamp}", "{hour}", "{minute}").any(firstLine::contains) -> voxString("Timestamped entry")
        firstLine.contains("{date}") -> voxString("Dated entry")
        else -> voxString("Formatted entry")
    }
    val shapeTitle = entryTemplateName?.trim()?.takeIf(String::isNotEmpty) ?: derivedShapeTitle
    val shapeDetail = if (firstLine != null) voxFormat("%@, then body and attachments", firstLine) else voxString("Body and attachments")

    val notePath = routeNotePath(preset)
    val heading = routeHeadingMarkdown(preset)
    val deliverBase = when (preset.noteTargetKind) {
        CaptureNoteTargetKind.NEW_NOTE -> voxString("New note")
        CaptureNoteTargetKind.ROLLING_NOTE -> periodNoteUiText(preset.rollingPeriod).localized()
        CaptureNoteTargetKind.EXISTING_NOTE -> notePath.substringAfterLast('/').ifBlank { voxString("Destination Not Configured") }
    }
    val deliverTitle = if (heading != null) voxFormat("%@, under “%@”", deliverBase, heading) else deliverBase
    val deliverDetail = if (notePath.isBlank()) {
        null
    } else {
        voxFormat("%@ · %@", routeDisplayPath(preset, rootName, includesHeading = false), routePlacementWordUiText(preset).localized())
    }

    return listOf(
        RouteStepSummary(RouteEditorStep.CAPTURE, voxString("Voice, text, photos, scans"), captureDetail, RouteEditorStep.CAPTURE in invalidSteps),
        RouteStepSummary(RouteEditorStep.PROCESS, routeProcessUiText(preset).localized(), processDetail, RouteEditorStep.PROCESS in invalidSteps),
        RouteStepSummary(RouteEditorStep.SHAPE, shapeTitle, shapeDetail, RouteEditorStep.SHAPE in invalidSteps),
        RouteStepSummary(RouteEditorStep.DELIVER, deliverTitle, deliverDetail, RouteEditorStep.DELIVER in invalidSteps),
    )
}

// endregion

// region Route editor overview components

/** Numbered step rail: a 28dp ink badge per step joined by a 2dp line, each card opening its settings. */
@Composable
internal fun RouteStepRail(steps: List<RouteStepSummary>, openStep: (RouteEditorStep) -> Unit, enabled: Boolean = true) {
    val c = Signal.colors
    Column(Modifier.fillMaxWidth()) {
        steps.forEachIndexed { index, summary ->
            val last = index == steps.lastIndex
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(
                    modifier = Modifier.width(28.dp).fillMaxHeight().clearAndSetSemantics {},
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(
                        modifier = Modifier.padding(top = 14.dp).size(28.dp).clip(CircleShape).background(c.text),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            summary.step.number.toString(),
                            style = SignalType.monoCaption.copy(fontWeight = FontWeight.Medium),
                            color = c.bg,
                        )
                    }
                    Box(
                        Modifier
                            .padding(top = 4.dp)
                            .width(2.dp)
                            .weight(1f)
                            .background(if (last) Color.Transparent else c.borderHi),
                    )
                }
                RouteStepCard(
                    summary = summary,
                    onClick = { openStep(summary.step) },
                    enabled = enabled,
                    modifier = Modifier.weight(1f).padding(bottom = 12.dp),
                )
            }
        }
    }
}

@Composable
private fun RouteStepCard(summary: RouteStepSummary, onClick: () -> Unit, enabled: Boolean, modifier: Modifier = Modifier) {
    val c = Signal.colors
    val shape = RoundedCornerShape(16.dp)
    val kind = summary.step.kindText.localized()
    val hint = voxString("Shows the settings for this step")
    Column(
        modifier = modifier
            .clip(shape)
            .background(c.card)
            .border(1.dp, if (summary.needsAttention) c.error else c.border, shape)
            .clickable(enabled = enabled, role = Role.Button, onClickLabel = hint, onClick = onClick)
            .testTag("route_step_${summary.step.number}")
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                kind.uppercase(),
                style = SignalType.monoCaption.copy(fontSize = 11.sp, letterSpacing = 0.06.em),
                color = c.muted,
                modifier = Modifier.weight(1f),
            )
            if (summary.needsAttention) {
                Icon(
                    Icons.Outlined.ErrorOutline,
                    contentDescription = voxString("Needs attention"),
                    tint = c.error,
                    modifier = Modifier.size(16.dp).padding(end = 2.dp),
                )
            }
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = c.faint,
                modifier = Modifier.size(18.dp),
            )
        }
        Text(
            summary.title,
            style = SignalType.rowTitle.copy(fontWeight = FontWeight.SemiBold, fontSize = 17.sp),
            color = c.text,
        )
        summary.detail?.let { Text(it, style = SignalType.caption, color = c.muted) }
    }
}

/** Sample note this route would write, rendered from its own path, formatting and mode. */
internal data class RoutePreview(val path: String, val markdown: String)

internal fun routeSamplePreview(preset: CapturePreset, now: Date = Date()): RoutePreview {
    val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now)
    val time = "10:42"
    val calendar = Calendar.getInstance(Locale.US).apply { this.time = now }
    val week = "%d-W%02d".format(Locale.US, calendar.get(Calendar.YEAR), calendar.get(Calendar.WEEK_OF_YEAR))
    val month = SimpleDateFormat("yyyy-MM", Locale.US).format(now)
    val year = SimpleDateFormat("yyyy", Locale.US).format(now)
    val quarter = (calendar.get(Calendar.MONTH) / 3) + 1
    val period = when (preset.rollingPeriod) {
        CaptureRollingPeriod.DAILY -> date
        CaptureRollingPeriod.WEEKLY -> week
        CaptureRollingPeriod.MONTHLY -> month
        CaptureRollingPeriod.QUARTERLY -> "$year-Q$quarter"
        CaptureRollingPeriod.YEARLY -> year
    }
    val title = "Project sync"
    fun render(template: String): String = template
        .replace("{timestamp}", "$date $time")
        .replace("{date}", date)
        .replace("{time}", time)
        .replace("{hour}", "10")
        .replace("{minute}", "42")
        .replace("{title}", title)
        .replace("{period}", period)
        .replace("{week}", week)
        .replace("{month}", calendar.get(Calendar.MONTH).plus(1).toString().padStart(2, '0'))
        .replace("{year}", year)
        .replace("{quarter}", quarter.toString())
        .replace("{id}", "3f2a9c1e")
        .replace("{uuid}", "3f2a9c1e-7b4d-4c1a-9e2f-5a6b7c8d9e0f")
        .replace("{model}", "Whisper")
        .replace("{language}", "en")
        .replace("{location}", "")
    val body = when (preset.effectiveProcessingMode()) {
        // The route's own entry prefix supplies the heading when it has one.
        CaptureProcessingMode.MEETING_NOTES ->
            (if (preset.entryPrefix.isBlank()) "### $time · $title\n" else "") +
                "- [ ] Review final designs\n- [ ] Loop in design before Friday\nDecision: ship routing first."
        CaptureProcessingMode.TODO_LIST -> "- [ ] Book flights for Lisbon"
        CaptureProcessingMode.NONE -> "Walked along the river after lunch. Felt clearer about the plan."
        else -> "Remind me to book flights for Lisbon before Friday."
    }
    val audio = if (preset.embedAudioInMarkdown && preset.audioSaveMode != CaptureAudioSaveMode.OFF) "![[$date-1042.m4a]]" else null
    val entry = buildString {
        if (audio != null && preset.audioEmbedPlacement == CaptureAudioEmbedPlacement.BEFORE_TEXT) append(audio).append('\n')
        append(render(preset.entryPrefix))
        append(body)
        append(render(preset.entrySuffix))
        if (audio != null && preset.audioEmbedPlacement == CaptureAudioEmbedPlacement.AFTER_TEXT) append('\n').append(audio)
    }
    val markdown = routeHeadingMarkdown(preset)?.let { "$it\n\n$entry" } ?: entry
    return RoutePreview(path = render(routeNotePath(preset)), markdown = markdown.trim())
}

/** Dark Markdown preview card from the Route editor board. */
@Composable
internal fun RoutePreviewCard(preview: RoutePreview, modifier: Modifier = Modifier) {
    val c = Signal.colors
    val fill = if (c.isDark) c.cardLowest else Color(0xFF121212)
    val ink = Color(0xFFE9E9E4)
    val muted = Color(0xFF9A9A95)
    val description = voxFormat("Preview of %@", preview.path)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(fill)
            .then(if (c.isDark) Modifier.border(1.dp, c.border, RoundedCornerShape(18.dp)) else Modifier)
            .semantics(mergeDescendants = true) { contentDescription = description }
            .testTag("route_preview")
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        FlowRowHeader(
            title = voxString("Preview").uppercase() + " · " + preview.path,
            source = voxString("from a sample capture"),
            muted = muted,
        )
        Text(
            preview.markdown,
            style = SignalType.mono.copy(fontSize = 12.5.sp, lineHeight = 20.sp),
            color = ink,
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FlowRowHeader(title: String, source: String, muted: Color) {
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            title,
            style = SignalType.monoCaption.copy(fontSize = 11.sp, letterSpacing = 0.06.em),
            color = muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(end = 8.dp),
        )
        Text(source, style = MaterialTheme.typography.labelSmall, color = muted)
    }
}

/** "Quick actions while typing" card: the first four pins and a "+N" overflow count. */
@Composable
internal fun RouteQuickActionsCard(actions: List<CaptureBarAction>, onClick: () -> Unit, enabled: Boolean, modifier: Modifier = Modifier) {
    val c = Signal.colors
    val shape = RoundedCornerShape(16.dp)
    val description = voxFormat("Quick actions while typing, %@ pinned", actions.size.toString())
    val open = onClick
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.card)
            .border(1.dp, c.border, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .clearAndSetSemantics {
                contentDescription = description
                role = Role.Button
                if (enabled) this.onClick(label = null, action = { open(); true })
            }
            .testTag("route_quick_actions")
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                voxString("Quick actions while typing").uppercase(),
                style = SignalType.monoCaption.copy(fontSize = 11.sp, letterSpacing = 0.06.em),
                color = c.muted,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (actions.isEmpty()) {
                    Text(voxString("None pinned"), style = SignalType.caption, color = c.muted)
                }
                actions.take(4).forEach { RouteActionGlyph(it, height = 30.dp) }
                if (actions.size > 4) {
                    Text(overflowCountLabel(actions.size - 4), style = SignalType.caption, color = c.muted)
                }
            }
        }
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = c.faint, modifier = Modifier.size(18.dp))
    }
}

// endregion

// region Quick actions (RouteQuickActions board)

/** Short mono glyph for an action where the design has one; media actions use an icon. */
internal fun routeActionGlyph(action: CaptureBarAction): String? = when (action) {
    CaptureBarAction.CHECKLIST -> "- [ ]"
    CaptureBarAction.BULLET_LIST -> "•"
    CaptureBarAction.INTERNAL_LINK -> "[[ ]]"
    CaptureBarAction.MARKDOWN_LINK -> "[ ]( )"
    CaptureBarAction.FORMAT_MARKDOWN -> "B"
    CaptureBarAction.TIMESTAMP -> "10:42"
    CaptureBarAction.DATE -> "11-01"
    CaptureBarAction.DUE_DATE -> "due"
    CaptureBarAction.CURRENT_LOCATION -> "◎"
    CaptureBarAction.TEXT_CASE -> "Aa"
    CaptureBarAction.PASTE -> "⎘"
    CaptureBarAction.UNDO -> "↺"
    CaptureBarAction.ADD_MEDIA,
    CaptureBarAction.ADD_FILES,
    CaptureBarAction.SCAN_DOCUMENT,
    CaptureBarAction.EXTRACT_TEXT,
    CaptureBarAction.SKETCH,
    -> null
}

private fun routeActionIcon(action: CaptureBarAction): ImageVector = when (action) {
    CaptureBarAction.ADD_MEDIA -> Icons.Outlined.Image
    CaptureBarAction.ADD_FILES -> Icons.Outlined.AttachFile
    CaptureBarAction.SCAN_DOCUMENT -> Icons.Outlined.Description
    CaptureBarAction.EXTRACT_TEXT -> Icons.Outlined.DocumentScanner
    else -> Icons.Outlined.Edit
}

/** Short label under a glyph (iOS `CaptureQuickAction.shortTitle`: "Task", "Link note"…). */
internal fun routeActionShortUiText(action: CaptureBarAction): VoxUiText = when (action) {
    CaptureBarAction.CHECKLIST -> voxUiText("Task")
    CaptureBarAction.BULLET_LIST -> voxUiText("Bullet")
    CaptureBarAction.MARKDOWN_LINK -> voxUiText("Web link")
    CaptureBarAction.INTERNAL_LINK -> voxUiText("Link note")
    CaptureBarAction.FORMAT_MARKDOWN -> voxUiText("Format")
    CaptureBarAction.TIMESTAMP -> voxUiText("Time")
    CaptureBarAction.DATE -> voxUiText("Date")
    CaptureBarAction.DUE_DATE -> voxUiText("Due date")
    CaptureBarAction.CURRENT_LOCATION -> voxUiText("Location")
    CaptureBarAction.TEXT_CASE -> voxUiText("Text case")
    CaptureBarAction.PASTE -> voxUiText("Paste")
    CaptureBarAction.UNDO -> voxUiText("Undo")
    CaptureBarAction.ADD_MEDIA -> voxUiText("Media")
    CaptureBarAction.ADD_FILES -> voxUiText("Files")
    CaptureBarAction.SCAN_DOCUMENT -> voxUiText("Scan")
    CaptureBarAction.EXTRACT_TEXT -> voxUiText("Extract text")
    CaptureBarAction.SKETCH -> voxUiText("Sketch")
}

@Composable
private fun RouteActionGlyph(action: CaptureBarAction, height: androidx.compose.ui.unit.Dp = 36.dp) {
    val c = Signal.colors
    val shape = RoundedCornerShape(8.dp)
    Box(
        modifier = Modifier
            .heightIn(min = height)
            .widthIn(min = height)
            .clip(shape)
            .background(c.cardLowest)
            .border(1.dp, c.border, shape)
            .padding(horizontal = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        val glyph = routeActionGlyph(action)
        if (glyph != null) {
            Text(glyph, style = SignalType.monoCaption.copy(fontFamily = GeistMonoFontFamily), color = c.text, maxLines = 1)
        } else {
            Icon(routeActionIcon(action), contentDescription = null, tint = c.text, modifier = Modifier.size(16.dp))
        }
    }
}

/**
 * Per-route quick actions: the pinned row in order (move up/down, unpin) and every
 * other action as a dashed "pin" chip. Changes apply immediately, as on iOS.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun RouteQuickActionsScreen(
    routeName: String,
    routeID: String,
    captureBar: CaptureBarConfiguration,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    setActions: (List<CaptureBarAction>?) -> Unit,
) {
    val c = Signal.colors
    val pinned = captureBar.pinnedActions(routeID)
    val rest = captureBar.unpinnedActions(routeID)
    Scaffold(
        containerColor = c.bg,
        topBar = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(c.bg)
                    .statusBarsPadding()
                    .heightIn(min = 64.dp)
                    .padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SignalCircleButton(Icons.AutoMirrored.Outlined.ArrowBack, voxString("Back"), navigateBack, contentColor = c.text)
                Spacer(Modifier.weight(1f))
                SignalButton(
                    text = voxString("Reset"),
                    onClick = { setActions(null) },
                    variant = SignalButtonVariant.SECONDARY,
                    size = SignalButtonSize.MEDIUM,
                    enabled = !isBusy && captureBar.hasCustomPins(routeID),
                    modifier = Modifier.testTag("route_quick_actions_reset"),
                )
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SignalMetrics.PageGutter)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    voxString("Quick actions"),
                    style = MaterialTheme.typography.headlineMedium,
                    color = c.text,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    voxFormat("Shown above the keyboard when you type into %@. Pin as many as you like — the row scrolls sideways.", routeName),
                    style = MaterialTheme.typography.bodyMedium,
                    color = c.muted,
                )
            }
            // Live strip of the row as it will appear while typing.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.well)
                    .border(1.dp, c.border, RoundedCornerShape(14.dp))
                    .horizontalScroll(rememberScrollState())
                    .clearAndSetSemantics {}
                    .padding(8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (pinned.isEmpty()) {
                    Text(voxString("None pinned"), style = SignalType.caption, color = c.muted, modifier = Modifier.padding(8.dp))
                }
                pinned.forEach { RouteActionGlyph(it) }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp)) {
                Text(
                    voxString("PINNED · IN ORDER"),
                    style = SignalType.monoCaption.copy(fontSize = 11.sp, letterSpacing = 0.06.em),
                    color = c.muted,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                Text(
                    voxFormat("%@ pinned · row scrolls", pinned.size.toString()),
                    style = SignalType.monoCaption.copy(fontSize = 11.sp),
                    color = c.muted,
                    modifier = Modifier.testTag("route_quick_actions_count"),
                )
            }
            if (pinned.isNotEmpty()) {
                val shape = RoundedCornerShape(16.dp)
                Column(Modifier.fillMaxWidth().clip(shape).background(c.card).border(1.dp, c.border, shape)) {
                    pinned.forEachIndexed { index, action ->
                        if (index > 0) androidx.compose.material3.HorizontalDivider(thickness = 1.dp, color = c.divider)
                        PinnedActionRow(
                            action = action,
                            canMoveUp = index > 0,
                            canMoveDown = index < pinned.lastIndex,
                            enabled = !isBusy,
                            move = { direction ->
                                val target = (index + direction).coerceIn(0, pinned.lastIndex)
                                setActions(pinned.toMutableList().apply { add(target, removeAt(index)) })
                            },
                            unpin = { setActions(pinned - action) },
                        )
                    }
                }
            }
            Text(
                voxString("MORE ACTIONS"),
                style = SignalType.monoCaption.copy(fontSize = 11.sp, letterSpacing = 0.06.em),
                color = c.muted,
                modifier = Modifier.padding(start = 4.dp, top = 10.dp, bottom = 2.dp).semantics { heading() },
            )
            if (rest.isEmpty()) {
                Text(voxString("Every action is pinned."), style = SignalType.caption, color = c.muted, modifier = Modifier.padding(horizontal = 4.dp))
            } else {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    rest.forEach { action ->
                        UnpinnedActionChip(action = action, enabled = !isBusy) { setActions(pinned + action) }
                    }
                }
            }
            Text(
                voxString(
                    if (captureBar.hasCustomPins(routeID)) {
                        "Reset makes this route follow the Capture Bar row in Settings again."
                    } else {
                        "Until you change it, this route uses the Capture Bar row in Settings."
                    },
                ),
                style = SignalType.caption,
                color = c.muted,
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 12.dp),
            )
        }
    }
}

@Composable
private fun PinnedActionRow(
    action: CaptureBarAction,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    enabled: Boolean,
    move: (Int) -> Unit,
    unpin: () -> Unit,
) {
    val c = Signal.colors
    val label = routeActionShortUiText(action).localized()
    val fullLabel = captureBarActionUiText(action).localized()
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = 14.dp, end = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.width(56.dp).clearAndSetSemantics {}) {
            val glyph = routeActionGlyph(action)
            if (glyph != null) {
                Text(glyph, style = SignalType.mono, color = c.text, maxLines = 1)
            } else {
                Icon(routeActionIcon(action), contentDescription = null, tint = c.text, modifier = Modifier.size(18.dp))
            }
        }
        Text(
            label,
            style = SignalType.rowTitle,
            color = c.text,
            modifier = Modifier.weight(1f).semantics { contentDescription = fullLabel },
        )
        val arrowColors = IconButtonDefaults.iconButtonColors(contentColor = c.text, disabledContentColor = c.borderHi)
        IconButton(onClick = { move(-1) }, enabled = enabled && canMoveUp, colors = arrowColors) {
            Icon(Icons.Outlined.KeyboardArrowUp, contentDescription = voxFormat("%@: %@", voxString("Move Up"), fullLabel))
        }
        IconButton(onClick = { move(1) }, enabled = enabled && canMoveDown, colors = arrowColors) {
            Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = voxFormat("%@: %@", voxString("Move Down"), fullLabel))
        }
        IconButton(
            onClick = unpin,
            enabled = enabled,
            colors = IconButtonDefaults.iconButtonColors(containerColor = c.well, contentColor = c.text, disabledContentColor = c.faint),
        ) {
            Icon(Icons.Outlined.Remove, contentDescription = voxFormat("Unpin %@", fullLabel), modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun UnpinnedActionChip(action: CaptureBarAction, enabled: Boolean, pin: () -> Unit) {
    val c = Signal.colors
    val fullLabel = captureBarActionUiText(action).localized()
    val description = voxFormat("Pin %@", fullLabel)
    Row(
        modifier = Modifier
            .heightIn(min = 40.dp)
            .clip(CircleShape)
            .dashedBorder(c.borderHi)
            .clickable(enabled = enabled, role = Role.Button, onClick = pin)
            .clearAndSetSemantics {
                contentDescription = description
                onClick { pin(); true }
            }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(Icons.Outlined.Add, contentDescription = null, tint = c.muted, modifier = Modifier.size(14.dp))
        val glyph = routeActionGlyph(action)
        if (glyph != null) {
            Text(glyph, style = SignalType.monoCaption, color = c.text)
        } else {
            Icon(routeActionIcon(action), contentDescription = null, tint = c.text, modifier = Modifier.size(14.dp))
        }
        Text(routeActionShortUiText(action).localized(), style = MaterialTheme.typography.labelMedium, color = c.text)
    }
}

private fun Modifier.dashedBorder(color: Color): Modifier = drawBehind {
    val stroke = 1.dp.toPx()
    drawRoundRect(
        color = color,
        topLeft = androidx.compose.ui.geometry.Offset(stroke / 2, stroke / 2),
        size = androidx.compose.ui.geometry.Size(size.width - stroke, size.height - stroke),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2),
        style = androidx.compose.ui.graphics.drawscope.Stroke(
            width = stroke,
            pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx())),
        ),
    )
}

// endregion

/** Numeric overflow badge (for example "+3"); contains no translatable words. */
private fun overflowCountLabel(count: Int): String = "+$count"
