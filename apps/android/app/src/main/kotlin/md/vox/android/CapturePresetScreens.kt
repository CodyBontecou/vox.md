package md.vox.android

import android.Manifest
import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.result.IntentSenderRequest
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.absolutePadding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.FormatListBulleted
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Alarm
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.CheckBox
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.WorkOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import md.vox.android.ui.SignalToggleRow
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions.RESULT_FORMAT_JPEG
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions.RESULT_FORMAT_PDF
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions.SCANNER_MODE_FULL
import md.vox.android.capturedomain.CaptureRouteOverride
import md.vox.android.capturedomain.CapturePresetPaths
import md.vox.android.capturedomain.CaptureURLDeliverySettings
import md.vox.android.capturedomain.normalizedTranscriptProperty
import md.vox.android.capturedomain.CaptureHeadingPosition
import md.vox.android.capturedomain.CaptureRailSide
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureAttachment
import md.vox.android.ui.GeistMonoFontFamily
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalBadge
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalFieldShape
import md.vox.android.ui.SignalGroup
import md.vox.android.ui.SignalIconTile
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalRouteTile
import md.vox.android.ui.SignalRouteTone
import md.vox.android.ui.SignalRowDivider
import md.vox.android.ui.SignalSectionLabel
import md.vox.android.ui.SignalSwitch
import md.vox.android.ui.SignalTopBar
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalTextFieldColors
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import md.vox.android.capturedomain.CaptureComposerCommand
import md.vox.android.capturedomain.CaptureInsertionFormatter
import md.vox.android.capturedomain.CaptureComposerTextEditor
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CapturePresetQuickAccess
import md.vox.android.capturedomain.CapturePresetEmoji
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CaptureMetadataScope
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CaptureRollingPeriod
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CaptureMissingHeadingBehavior
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureProcessingScope
import md.vox.android.capturedomain.CapturePresetLocationPolicy
import md.vox.android.capturedomain.CaptureLocationPrecision
import md.vox.android.capturedomain.CaptureLocationUnavailableBehavior
import md.vox.android.capturedomain.CaptureLocationUnavailableReason
import md.vox.android.capturedomain.CaptureLocationOutputMode
import md.vox.android.capturedomain.CaptureLocationField
import md.vox.android.capturedomain.CaptureLocationStructuredField
import md.vox.android.capturedomain.DEFAULT_CAPTURE_LOCATION_FIELDS
import md.vox.android.capturedomain.CaptureLocationOutcome
import md.vox.android.capturedomain.CaptureLocationLabel
import md.vox.android.capturedomain.CaptureLocationLabelLookupClass
import md.vox.android.capturedomain.CaptureLocationLabelObservation
import md.vox.android.capturedomain.CaptureLocationLabelOutcome
import md.vox.android.capturedomain.CaptureLocationSnapshot
import md.vox.android.capturedomain.CURRENT_LOCATION_LABEL_CONSENT_VERSION
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureExportFileFormat
import md.vox.android.capturedomain.CaptureExportFileMode
import md.vox.android.capturedomain.CaptureExportYAMLProperty
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.resolvingEntryTemplate
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureSubmitResult
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.capturedomain.WearRemoteRecordingPhase
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.capturedomain.CompletedRecordingActivity
import md.vox.android.ui.CaptureUiState
import md.vox.android.ui.CaptureViewModel
import md.vox.android.ui.VoxColors
import md.vox.android.ui.VoxTheme
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.CurrentLocationResolver
import md.vox.android.platformservices.CurrentLocationResult
import md.vox.android.platformservices.LocalTextRecognition
import md.vox.android.platformservices.LiveSpeechPhase
import md.vox.android.platformservices.LiveSpeechRegistry
import md.vox.android.platformservices.LiveSpeechState
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingJobPolicyStore
import md.vox.android.platformservices.RecordingProcessingPolicy
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingStatusRegistry
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.platformservices.SpeechModelManager
import md.vox.android.platformservices.SpeechModelSelectionMode
import md.vox.android.platformservices.TranscriptionUsageState
import md.vox.android.platformservices.shouldDeleteRecordingAudio
import md.vox.android.platformservices.shouldProcessRecordingAutomatically
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.io.File
import java.util.Date
import java.util.Calendar
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToLong

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CapturePresetsScreen(
    collection: CapturePresetCollection?,
    entryTemplates: List<CaptureEntryTemplate>,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    selectPreset: (String) -> Unit,
    editPreset: (String) -> Unit,
    createPreset: () -> Unit,
    saveEntryTemplate: (CaptureEntryTemplate) -> Unit,
    deleteEntryTemplate: (String) -> Unit,
    /** The app's vault name, shown as the root of route paths that use the app destination. */
    defaultDestinationName: String? = null,
    /** Pins or unpins a route on the capture bar from its long-press menu; hidden when null. */
    togglePinned: ((CapturePreset) -> Unit)? = null,
    templateEditor: EntryTemplateEditorState = rememberEntryTemplateEditorState(),
) {
    val c = Signal.colors
    Scaffold(
        containerColor = c.bg,
        topBar = {
            // Routes board header: a circular Back and a "New" pill; the page title sits below.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(c.bg)
                    .statusBarsPadding()
                    .heightIn(min = 64.dp)
                    .padding(start = 4.dp, end = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SignalCircleButton(Icons.AutoMirrored.Outlined.ArrowBack, voxString("Back"), navigateBack, contentColor = c.text)
                Spacer(Modifier.weight(1f))
                val addRoute = voxString("Add Route")
                SignalButton(
                    text = voxString("New"),
                    onClick = createPreset,
                    size = SignalButtonSize.MEDIUM,
                    icon = Icons.Outlined.Add,
                    enabled = !isBusy && collection != null,
                    modifier = Modifier.semantics { contentDescription = addRoute }.testTag("capture_presets_new"),
                )
            }
        },
    ) { padding ->
        if (collection == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(modifier = Modifier.size(28.dp), strokeWidth = 3.dp, color = c.tint)
            }
        } else {
            val defaultID = collection.activePreset.id
            val sortedPresets = collection.presets.sortedWith(
                compareByDescending<CapturePreset> { it.id == defaultID }
                    .thenByDescending { it.isPinned }
                    .thenBy { it.name.lowercase() },
            )
            val enabledOrder = sortedPresets.filter(CapturePreset::isEnabled).map(CapturePreset::id)
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(start = SignalMetrics.PageGutter, end = SignalMetrics.PageGutter, bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                item(key = "routes-header") {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = 4.dp, bottom = 6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            voxString("Routes"),
                            style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.SemiBold),
                            color = c.text,
                            modifier = Modifier.semantics { heading() },
                        )
                        Text(
                            voxString("Where a capture goes, and what happens on the way."),
                            style = MaterialTheme.typography.bodyMedium,
                            color = c.muted,
                        )
                    }
                }
                items(sortedPresets, key = CapturePreset::id) { preset ->
                    val orderIndex = enabledOrder.indexOf(preset.id).takeIf { it >= 0 }
                    PresetRouteCard(
                        preset = preset,
                        tone = if (preset.isEnabled) SignalRouteTone.forIndex(orderIndex) else SignalRouteTone.NEUTRAL,
                        isDefault = preset.id == defaultID,
                        path = routeListPath(preset, defaultDestinationName),
                        isBusy = isBusy,
                        select = { selectPreset(preset.id) },
                        edit = { editPreset(preset.id) },
                        togglePinned = togglePinned?.let { toggle -> { toggle(preset) } },
                    )
                }
                item(key = "routes-footer") {
                    Text(
                        voxString("Long-press a route to make it your default or pin it to the capture bar."),
                        modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 2.dp),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(top = 22.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(modifier = Modifier.weight(1f).padding(start = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            SignalSectionLabel(voxString("Entry Templates"))
                            Text(
                                voxString("Reusable prefix and suffix formatting. Linked routes receive edits automatically."),
                                style = SignalType.caption,
                                color = c.muted,
                            )
                        }
                        SignalCircleButton(
                            icon = Icons.Outlined.Add,
                            contentDescription = voxString("New Entry Template"),
                            onClick = { templateEditor.edit(null) },
                            enabled = !isBusy,
                        )
                    }
                }
                if (entryTemplates.isNotEmpty()) {
                    item(key = "entry-templates") {
                        SignalGroup(title = null) {
                            entryTemplates.sortedBy { it.name.lowercase() }.forEachIndexed { index, template ->
                                if (index > 0) SignalRowDivider()
                                PresetEntryTemplateRow(
                                    template = template,
                                    isBusy = isBusy,
                                    edit = { templateEditor.edit(template) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    templateEditor.templateID?.let { templateID ->
        val existing = entryTemplates.firstOrNull { it.id == templateID }
        EntryTemplateEditorDialog(
            template = existing,
            isBusy = isBusy,
            dismiss = templateEditor::dismiss,
            save = { template ->
                saveEntryTemplate(template)
                templateEditor.dismiss()
            },
            delete = existing?.let { template ->
                {
                    deleteEntryTemplate(template.id)
                    templateEditor.dismiss()
                }
            },
            editorState = templateEditor,
        )
    }
}

/**
 * Routes board card: a toned route tile, the name with DEFAULT / Pinned / Disabled
 * badges, the mono route path and a chevron, then Input → Process → Deliver chips.
 * Tapping opens the editor; long-press offers "Use as Capture Default" and capture
 * bar pinning (also exposed as accessibility actions).
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
private fun PresetRouteCard(
    preset: CapturePreset,
    tone: SignalRouteTone,
    isDefault: Boolean,
    path: String,
    isBusy: Boolean,
    select: () -> Unit,
    edit: () -> Unit,
    togglePinned: (() -> Unit)?,
) {
    val c = Signal.colors
    val shape = RoundedCornerShape(18.dp)
    var menuOpen by remember { mutableStateOf(false) }
    val canSelect = !isBusy && preset.isEnabled && !isDefault
    val useAsDefault = voxString("Use as Capture Default")
    val pinLabel = voxString(if (preset.isPinned) "Unpin from Capture Bar" else "Pin to Capture Bar")
    val editLabel = voxString("Edit")
    val optionsLabel = voxString("More options")
    Box {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(c.card)
                .border(1.dp, c.border, shape)
                .combinedClickable(
                    enabled = !isBusy,
                    role = Role.Button,
                    onClickLabel = editLabel,
                    onLongClickLabel = optionsLabel,
                    onLongClick = { menuOpen = true },
                    onClick = edit,
                )
                .semantics {
                    customActions = buildList {
                        if (canSelect) add(CustomAccessibilityAction(useAsDefault) { select(); true })
                        if (togglePinned != null && !isBusy) add(CustomAccessibilityAction(pinLabel) { togglePinned(); true })
                    }
                }
                .testTag("capture_preset_route_${preset.id}")
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                PresetRouteTile(
                    name = preset.name,
                    symbol = preset.symbol,
                    emoji = preset.emoji,
                    tone = tone,
                    modifier = Modifier.alpha(if (preset.isEnabled) 1f else 0.55f),
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                        itemVerticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            preset.name,
                            style = SignalType.rowTitle.copy(fontWeight = FontWeight.SemiBold, fontSize = 17.sp),
                            color = if (preset.isEnabled) c.text else c.muted,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (isDefault) {
                            Text(
                                voxString("Default").uppercase(),
                                style = SignalType.monoCaption.copy(fontSize = 10.5.sp),
                                color = c.accentText,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(5.dp))
                                    .background(c.accentSoft)
                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                            )
                        }
                        if (preset.isPinned) {
                            SignalBadge(voxString("Pinned"), color = c.well, contentColor = c.muted)
                        }
                        if (!preset.isEnabled) {
                            SignalBadge(voxString("Disabled"), color = c.warningSoft, contentColor = c.warningText)
                        }
                    }
                    if (path.isNotBlank()) {
                        Text(
                            path,
                            style = SignalType.monoCaption.copy(fontSize = 11.5.sp),
                            color = c.muted,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                Icon(
                    Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = null,
                    tint = c.faint,
                    modifier = Modifier.size(20.dp),
                )
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                routeStepChips(preset).forEachIndexed { index, chip ->
                    if (index > 0) {
                        Text(ROUTE_STEP_ARROW, style = SignalType.caption.copy(fontSize = 12.sp), color = c.faint, modifier = Modifier.clearAndSetSemantics {})
                    }
                    Text(
                        chip,
                        style = SignalType.caption.copy(fontSize = 12.5.sp, lineHeight = 16.sp),
                        color = c.secondaryText,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(c.well)
                            .padding(horizontal = 9.dp, vertical = 4.dp),
                    )
                }
            }
        }
        DropdownMenu(
            expanded = menuOpen,
            onDismissRequest = { menuOpen = false },
            containerColor = c.card,
        ) {
            DropdownMenuItem(
                text = { Text(editLabel) },
                leadingIcon = { Icon(Icons.Outlined.Edit, contentDescription = null) },
                onClick = { menuOpen = false; edit() },
            )
            DropdownMenuItem(
                text = { Text(useAsDefault) },
                leadingIcon = { Icon(Icons.Outlined.CheckCircle, contentDescription = null) },
                enabled = canSelect,
                onClick = { menuOpen = false; select() },
            )
            if (togglePinned != null) {
                DropdownMenuItem(
                    text = { Text(pinLabel) },
                    leadingIcon = { Icon(Icons.Outlined.Dashboard, contentDescription = null) },
                    enabled = !isBusy,
                    onClick = { menuOpen = false; togglePinned() },
                )
            }
        }
    }
}

@Composable
private fun PresetEntryTemplateRow(template: CaptureEntryTemplate, isBusy: Boolean, edit: () -> Unit) {
    val c = Signal.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 60.dp)
            .clickable(enabled = !isBusy, onClick = edit)
            .padding(start = 14.dp, end = 4.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SignalIconTile(Icons.Outlined.TextFields, size = 36.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(template.name, style = SignalType.rowTitle, color = c.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                entryTemplateDescription(template),
                style = SignalType.monoCaption,
                color = c.muted,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(onClick = edit, enabled = !isBusy) {
            Icon(
                Icons.Outlined.Edit,
                contentDescription = voxFormat("%@: %@", voxString("Edit"), template.name),
                tint = if (isBusy) c.faint else c.muted,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

/**
 * Route tile for a preset: a chosen emoji wins, otherwise the name's first letter,
 * otherwise the stored symbol (icon-only presets), matching iOS
 * `CapturePresetSettingsRouteTile`. Decorative; the row owns the label.
 */
@Composable
internal fun PresetRouteTile(
    name: String,
    symbol: String?,
    emoji: String?,
    tone: SignalRouteTone,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
) {
    val c = Signal.colors
    val normalizedEmoji = CapturePresetEmoji.normalized(emoji)
    if (normalizedEmoji == null && name.isNotBlank()) {
        SignalRouteTile(label = name, modifier = modifier, size = size, tone = tone)
        return
    }
    val (fill, ink) = when (tone) {
        SignalRouteTone.PRIMARY -> c.accent to c.onAccent
        SignalRouteTone.INK -> c.inverse to c.onInverse
        SignalRouteTone.NEUTRAL -> c.tertiarySoft to c.tertiaryText
    }
    Box(
        modifier = modifier
            .size(size)
            .clip(RoundedCornerShape(size * 0.3f))
            .background(fill),
        contentAlignment = Alignment.Center,
    ) {
        PresetIdentityIcon(
            symbol = symbol,
            emoji = normalizedEmoji,
            name = name,
            tint = ink,
            emojiStyle = TextStyle(fontSize = (size.value * 0.48f).sp),
        )
    }
}

@Composable
internal fun entryTemplateDescription(template: CaptureEntryTemplate): String = buildList {
    template.entryPrefix.takeIf(String::isNotBlank)?.let {
        add(voxFormat("%@: %@", voxString("Prefix"), it.replace('\n', ' ').take(80)))
    }
    template.entrySuffix.takeIf(String::isNotBlank)?.let {
        add(voxFormat("%@: %@", voxString("Suffix"), it.replace('\n', ' ').take(80)))
    }
}.joinToString(" · ").ifBlank { voxString("No prefix or suffix") }

@Composable
internal fun EntryTemplateEditorDialog(
    template: CaptureEntryTemplate?,
    isBusy: Boolean,
    dismiss: () -> Unit,
    save: (CaptureEntryTemplate) -> Unit,
    delete: (() -> Unit)?,
    editorState: EntryTemplateEditorState? = null,
) {
    val draft = editorState ?: rememberSaveable(template?.id, saver = EntryTemplateEditorState.Saver) {
        EntryTemplateEditorState().apply { edit(template) }
    }
    var name by draft::name
    var prefix by draft::prefix
    var suffix by draft::suffix
    val c = Signal.colors
    AlertDialog(
        onDismissRequest = dismiss,
        containerColor = c.bg,
        titleContentColor = c.text,
        textContentColor = c.text,
        shape = RoundedCornerShape(24.dp),
        title = {
            Text(
                voxString(if (template == null) "New Entry Template" else "Edit Entry Template"),
                style = MaterialTheme.typography.headlineSmall,
            )
        },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it.take(80) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Name")) },
                    singleLine = true,
                    shape = SignalFieldShape,
                    colors = signalTextFieldColors(),
                )
                OutlinedTextField(
                    value = prefix,
                    onValueChange = { prefix = it.take(16_384) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Prefix")) },
                    placeholder = { Text(voxString("- {time} "), style = SignalType.mono) },
                    textStyle = SignalType.mono.copy(color = c.text),
                    minLines = 2,
                    shape = SignalFieldShape,
                    colors = signalTextFieldColors(),
                )
                OutlinedTextField(
                    value = suffix,
                    onValueChange = { suffix = it.take(16_384) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Suffix")) },
                    textStyle = SignalType.mono.copy(color = c.text),
                    minLines = 2,
                    shape = SignalFieldShape,
                    colors = signalTextFieldColors(),
                )
                if (delete != null) {
                    TextButton(
                        onClick = delete,
                        enabled = !isBusy,
                        modifier = Modifier.heightIn(min = 48.dp),
                        colors = ButtonDefaults.textButtonColors(contentColor = c.error, disabledContentColor = c.faint),
                    ) {
                        Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(voxString("Delete Template"), style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        },
        confirmButton = {
            SignalButton(
                text = voxString("Save"),
                onClick = {
                    save(
                        CaptureEntryTemplate(
                            id = template?.id ?: UUID.randomUUID().toString().lowercase(),
                            name = name,
                            entryPrefix = prefix,
                            entrySuffix = suffix,
                        ),
                    )
                },
                enabled = name.trim().isNotEmpty() && !isBusy,
                size = SignalButtonSize.MEDIUM,
            )
        },
        dismissButton = {
            SignalButton(
                text = voxString("Cancel"),
                onClick = dismiss,
                variant = SignalButtonVariant.TERTIARY,
                size = SignalButtonSize.MEDIUM,
            )
        },
    )
}

@Composable
internal fun presetRouteDescription(preset: CapturePreset): String = when (preset.noteTargetKind) {
    CaptureNoteTargetKind.NEW_NOTE -> voxFormat("%@ · %@", preset.logicalFolder, preset.noteNameTemplate)
    CaptureNoteTargetKind.ROLLING_NOTE -> voxFormat(
        "%@ · %@/%@",
        captureRollingPeriodUiText(preset.rollingPeriod).localized(),
        preset.logicalFolder,
        preset.noteNameTemplate,
    )
    CaptureNoteTargetKind.EXISTING_NOTE -> voxFormat(
        "%@ · %@",
        preset.existingNotePath,
        capturePlacementUiText(preset.placement).localized(),
    )
}

internal fun captureRollingPeriodUiText(period: CaptureRollingPeriod): VoxUiText = when (period) {
    CaptureRollingPeriod.DAILY -> voxUiText("Daily")
    CaptureRollingPeriod.WEEKLY -> voxUiText("Weekly")
    CaptureRollingPeriod.MONTHLY -> voxUiText("Monthly")
    CaptureRollingPeriod.QUARTERLY -> voxUiText("Quarterly")
    CaptureRollingPeriod.YEARLY -> voxUiText("Yearly")
}

internal fun capturePlacementUiText(placement: CapturePlacementKind): VoxUiText = when (placement) {
    CapturePlacementKind.APPEND -> voxUiText("Append")
    CapturePlacementKind.PREPEND -> voxUiText("Prepend")
    CapturePlacementKind.BENEATH_HEADING -> voxUiText("Beneath Heading")
}

internal data class CapturePresetEditorDraft(
    val id: String,
    val name: String,
    val symbol: String,
    val emoji: String?,
    val isEnabled: Boolean,
    val isPinned: Boolean,
    val noteTargetKind: CaptureNoteTargetKind,
    val rollingPeriod: CaptureRollingPeriod,
    val logicalFolder: String,
    val noteNameTemplate: String,
    val existingNotePath: String,
    val placement: CapturePlacementKind,
    val headingTitle: String,
    val headingLevel: Int,
    val missingHeadingBehavior: CaptureMissingHeadingBehavior,
    val entryPrefix: String,
    val entrySuffix: String,
    val entryTemplateID: String?,
    val attachmentsFolder: String,
    val retryProtectionEnabled: Boolean,
    val metadataScope: CaptureMetadataScope,
    val metadataText: String,
    val speakerDiarizationEnabled: Boolean,
    val processingEnabled: Boolean,
    val processingMode: CaptureProcessingMode,
    val processingScope: CaptureProcessingScope,
    val customInstruction: String,
    val capturePrompt: String,
    val generateImageAltText: Boolean,
    val locationEnabled: Boolean,
    val locationPrecision: CaptureLocationPrecision,
    val locationUnavailableBehavior: CaptureLocationUnavailableBehavior,
    val locationMetadataEnabled: Boolean,
    val locationOutputMode: CaptureLocationOutputMode,
    val locationStructuredFields: List<CaptureLocationStructuredField>,
    val locationCollectionKey: String,
    val locationAdvancedTemplate: String,
    val locationLabelLookupClass: CaptureLocationLabelLookupClass,
    val locationLabelConsentVersion: Int?,
    val audioSaveMode: CaptureAudioSaveMode,
    val embedAudio: Boolean,
    val audioEmbedPlacement: CaptureAudioEmbedPlacement,
    val watchOutputMode: CaptureWatchOutputMode,
    val exportSettings: CapturePresetExportSettings,
    val destination: CaptureDestination? = null,
    val transcriptPropertyName: String = "",
    val includeTranscriptInBody: Boolean = true,
    val urlDelivery: CaptureURLDeliverySettings = CaptureURLDeliverySettings(),
    val headingPosition: CaptureHeadingPosition = CaptureHeadingPosition.TOP,
    val audioFilenameTemplate: String = "",
) {
    fun toPreset(revision: Int, metadataFields: List<CaptureMetadataField>) = CapturePreset(
        id = id,
        name = name,
        symbol = symbol,
        emoji = emoji,
        revision = revision,
        logicalFolder = logicalFolder,
        noteNameTemplate = noteNameTemplate,
        metadataFields = metadataFields,
        isEnabled = isEnabled,
        isPinned = isPinned,
        noteTargetKind = noteTargetKind,
        rollingPeriod = rollingPeriod,
        existingNotePath = existingNotePath,
        placement = placement,
        headingTitle = headingTitle,
        headingLevel = headingLevel,
        missingHeadingBehavior = missingHeadingBehavior,
        entryPrefix = entryPrefix,
        entrySuffix = entrySuffix,
        entryTemplateID = entryTemplateID,
        attachmentsFolder = attachmentsFolder,
        retryProtectionEnabled = retryProtectionEnabled,
        metadataScope = metadataScope,
        speakerDiarizationEnabled = speakerDiarizationEnabled,
        processingEnabled = processingEnabled,
        processingMode = processingMode,
        processingScope = processingScope,
        customProcessingInstruction = customInstruction,
        capturePrompt = capturePrompt,
        generateImageAltText = generateImageAltText,
        locationPolicy = CapturePresetLocationPolicy(
            isEnabled = locationEnabled,
            precision = locationPrecision,
            unavailableBehavior = locationUnavailableBehavior,
            metadataOutputEnabled = locationMetadataEnabled,
            outputMode = locationOutputMode,
            structuredFields = locationStructuredFields,
            collectionKey = locationCollectionKey,
            advancedTemplate = locationAdvancedTemplate,
            labelLookupClass = locationLabelLookupClass,
            labelConsentVersion = locationLabelConsentVersion,
        ),
        audioSaveMode = audioSaveMode,
        embedAudioInMarkdown = embedAudio,
        audioEmbedPlacement = audioEmbedPlacement,
        watchOutputMode = watchOutputMode,
        exportSettings = exportSettings,
        destination = destination,
        transcriptPropertyName = transcriptPropertyName,
        includeTranscriptInBody = includeTranscriptInBody,
        urlDelivery = urlDelivery,
        headingPosition = headingPosition,
        audioFilenameTemplate = audioFilenameTemplate,
    )

    companion object {
        fun from(preset: CapturePreset?): CapturePresetEditorDraft = if (preset == null) {
            CapturePresetEditorDraft(
                id = UUID.randomUUID().toString().lowercase(),
                name = "",
                symbol = "description",
                emoji = null,
                isEnabled = true,
                isPinned = false,
                noteTargetKind = CaptureNoteTargetKind.NEW_NOTE,
                rollingPeriod = CaptureRollingPeriod.DAILY,
                logicalFolder = "Inbox",
                noteNameTemplate = "capture-{id}.md",
                existingNotePath = "",
                placement = CapturePlacementKind.APPEND,
                headingTitle = "",
                headingLevel = 1,
                missingHeadingBehavior = CaptureMissingHeadingBehavior.FAIL,
                entryPrefix = "",
                entrySuffix = "",
                entryTemplateID = null,
                attachmentsFolder = "Attachments",
                retryProtectionEnabled = false,
                metadataScope = CaptureMetadataScope.DOCUMENT,
                metadataText = "",
                speakerDiarizationEnabled = false,
                processingEnabled = false,
                processingMode = CaptureProcessingMode.CLEAN,
                processingScope = CaptureProcessingScope.BOTH,
                customInstruction = "",
                capturePrompt = "",
                generateImageAltText = false,
                locationEnabled = false,
                locationPrecision = CaptureLocationPrecision.EXACT,
                locationUnavailableBehavior = CaptureLocationUnavailableBehavior.ASK,
                locationMetadataEnabled = false,
                locationOutputMode = CaptureLocationOutputMode.STRUCTURED_FIELDS,
                locationStructuredFields = DEFAULT_CAPTURE_LOCATION_FIELDS,
                locationCollectionKey = "locations",
                locationAdvancedTemplate = "",
                locationLabelLookupClass = CaptureLocationLabelLookupClass.NONE,
                locationLabelConsentVersion = null,
                audioSaveMode = CaptureAudioSaveMode.OFF,
                embedAudio = false,
                audioEmbedPlacement = CaptureAudioEmbedPlacement.AFTER_TEXT,
                watchOutputMode = CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE,
                exportSettings = CapturePresetExportSettings(
                    usesCustomExportSettings = true,
                    exportEnabled = false,
                ),
            )
        } else {
            CapturePresetEditorDraft(
                id = preset.id,
                name = preset.name,
                symbol = preset.symbol,
                emoji = preset.emoji,
                isEnabled = preset.isEnabled,
                isPinned = preset.isPinned,
                noteTargetKind = preset.noteTargetKind,
                rollingPeriod = preset.rollingPeriod,
                logicalFolder = preset.logicalFolder,
                noteNameTemplate = preset.noteNameTemplate,
                existingNotePath = preset.existingNotePath,
                placement = preset.placement,
                headingTitle = preset.headingTitle,
                headingLevel = preset.headingLevel,
                missingHeadingBehavior = preset.missingHeadingBehavior,
                entryPrefix = preset.entryPrefix,
                entrySuffix = preset.entrySuffix,
                entryTemplateID = preset.entryTemplateID,
                attachmentsFolder = preset.attachmentsFolder,
                retryProtectionEnabled = preset.retryProtectionEnabled,
                metadataScope = preset.metadataScope,
                metadataText = preset.metadataFields.joinToString("\n") { "${it.name}=${it.value}" },
                speakerDiarizationEnabled = preset.speakerDiarizationEnabled,
                processingEnabled = preset.processingEnabled,
                processingMode = preset.processingMode,
                processingScope = preset.processingScope,
                customInstruction = preset.customProcessingInstruction,
                capturePrompt = preset.capturePrompt,
                generateImageAltText = preset.generateImageAltText,
                locationEnabled = preset.locationPolicy.isEnabled,
                locationPrecision = preset.locationPolicy.precision,
                locationUnavailableBehavior = preset.locationPolicy.unavailableBehavior,
                locationMetadataEnabled = preset.locationPolicy.metadataOutputEnabled,
                locationOutputMode = preset.locationPolicy.outputMode,
                locationStructuredFields = preset.locationPolicy.structuredFields,
                locationCollectionKey = preset.locationPolicy.collectionKey,
                locationAdvancedTemplate = preset.locationPolicy.advancedTemplate,
                locationLabelLookupClass = preset.locationPolicy.labelLookupClass,
                locationLabelConsentVersion = preset.locationPolicy.labelConsentVersion,
                audioSaveMode = preset.audioSaveMode,
                embedAudio = preset.embedAudioInMarkdown,
                audioEmbedPlacement = preset.audioEmbedPlacement,
                watchOutputMode = preset.watchOutputMode,
                exportSettings = preset.exportSettings,
                destination = preset.destination,
                transcriptPropertyName = preset.transcriptPropertyName,
                includeTranscriptInBody = preset.includeTranscriptInBody,
                urlDelivery = preset.urlDelivery,
                headingPosition = preset.headingPosition,
                audioFilenameTemplate = preset.audioFilenameTemplate,
            )
        }
    }
}

/** What the route editor is showing: the step overview (null), one step's settings, or quick actions. */
internal enum class RouteEditorPage { CAPTURE, PROCESS, SHAPE, DELIVER, QUICK_ACTIONS }

private fun RouteEditorStep.page(): RouteEditorPage = when (this) {
    RouteEditorStep.CAPTURE -> RouteEditorPage.CAPTURE
    RouteEditorStep.PROCESS -> RouteEditorPage.PROCESS
    RouteEditorStep.SHAPE -> RouteEditorPage.SHAPE
    RouteEditorStep.DELIVER -> RouteEditorPage.DELIVER
}

/**
 * Route editor (Route editor board): a header, the CAPTURE → PROCESS → SHAPE → DELIVER
 * rail, a Markdown preview, the route's quick actions and two quick toggles. Each step
 * opens a sub-page holding that step's existing settings; nothing is saved until Done.
 *
 * - CAPTURE: voice and audio, Watch output, location, audio filename.
 * - PROCESS: on-device processing (mode, scope, custom instruction, prompt, alt text).
 * - SHAPE: entry formatting and template, attachments, retry marker, metadata, transcript property.
 * - DELIVER: vault, note target and placement, heading position, URL delivery, file export.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CapturePresetEditorScreen(
    preset: CapturePreset?,
    entryTemplates: List<CaptureEntryTemplate>,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    save: (CapturePreset) -> Unit,
    delete: (() -> Unit)?,
    /** True when this route is the app's default (active) route. */
    isDefault: Boolean = false,
    /** The app vault's name, used as the path root when the route has no vault of its own. */
    defaultDestinationName: String? = null,
    /** Capture bar configuration holding per-route quick actions; the card is hidden when null. */
    captureBar: CaptureBarConfiguration? = null,
    /** Applies a route's quick actions immediately (`null` = follow the global row). */
    setRouteQuickActions: ((String, List<CaptureBarAction>?) -> Unit)? = null,
    /** Opens directly on a sub-page; used by debug stories. */
    initialPage: RouteEditorPage? = null,
) {
    var draft by rememberSaveable(preset?.id, stateSaver = CapturePresetEditorDraftSaver) {
        mutableStateOf(CapturePresetEditorDraft.from(preset))
    }
    var pageName by rememberSaveable(preset?.id) { mutableStateOf(initialPage?.name) }
    val page = pageName?.let(RouteEditorPage::valueOf)
    BackHandler(enabled = page != null) { pageName = null }

    val metadata = parseMetadataFields(draft.metadataText)
    val routeIsValid = CapturePresetPaths.folder(draft.logicalFolder) != null &&
        CapturePresetPaths.filename(draft.noteNameTemplate) != null &&
        (draft.noteTargetKind != CaptureNoteTargetKind.EXISTING_NOTE || CapturePresetPaths.existingNote(draft.existingNotePath) != null)
    val attachmentsFolderIsValid = CapturePresetPaths.folder(draft.attachmentsFolder, allowEmpty = true) != null
    val headingIsValid = draft.placement != CapturePlacementKind.BENEATH_HEADING || draft.headingTitle.trim().isNotEmpty()
    val processingIsValid = draft.capturePrompt.length <= 512 && (!draft.processingEnabled ||
        draft.processingMode != CaptureProcessingMode.CUSTOM ||
        draft.customInstruction.trim().isNotEmpty())
    val configuredExportEnabled = draft.exportSettings.usesCustomExportSettings && draft.exportSettings.exportEnabled
    val exportIsValid = !configuredExportEnabled || (
        draft.exportSettings.destinationTreeUri != null &&
            draft.exportSettings.newFileNameTemplate.trim().isNotEmpty() &&
            draft.exportSettings.appendFileName.trim().isNotEmpty() &&
            (!draft.exportSettings.markdownTemplateEnabled || draft.exportSettings.markdownTemplateUri != null)
        )
    val locationIsValid = !draft.locationMetadataEnabled || (
        draft.locationCollectionKey.matches(Regex("^[A-Za-z_][A-Za-z0-9_-]{0,63}$")) &&
            when (draft.locationOutputMode) {
                CaptureLocationOutputMode.STRUCTURED_FIELDS -> structuredLocationFieldsAreValid(draft.locationStructuredFields)
                CaptureLocationOutputMode.ADVANCED_YAML ->
                    draft.metadataScope == CaptureMetadataScope.DOCUMENT && draft.locationAdvancedTemplate.isNotBlank()
            }
        )
    val locationLabelConsentIsValid = when (draft.locationLabelLookupClass) {
        CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK ->
            draft.locationLabelConsentVersion == CURRENT_LOCATION_LABEL_CONSENT_VERSION
        CaptureLocationLabelLookupClass.NONE,
        CaptureLocationLabelLookupClass.OFFLINE,
        -> draft.locationLabelConsentVersion == null
    }
    val transcriptPropertyIsValid =
        draft.transcriptPropertyName.isBlank() || normalizedTranscriptProperty(draft.transcriptPropertyName) != null
    val valid = draft.name.trim().isNotEmpty() && routeIsValid && headingIsValid && processingIsValid &&
        exportIsValid && locationIsValid && locationLabelConsentIsValid && metadata != null && transcriptPropertyIsValid && attachmentsFolderIsValid
    val invalidSteps = buildSet {
        if (!locationIsValid || !locationLabelConsentIsValid) add(RouteEditorStep.CAPTURE)
        if (!processingIsValid) add(RouteEditorStep.PROCESS)
        if (metadata == null || !transcriptPropertyIsValid || !attachmentsFolderIsValid) add(RouteEditorStep.SHAPE)
        if (!routeIsValid || !headingIsValid || !exportIsValid) add(RouteEditorStep.DELIVER)
    }
    val revision = preset?.revision ?: 1
    val livePreset = draft.toPreset(revision, metadata.orEmpty())
    val onDone = { save(draft.toPreset(revision, requireNotNull(metadata))) }
    val c = Signal.colors

    when (page) {
        RouteEditorPage.QUICK_ACTIONS -> if (captureBar != null && setRouteQuickActions != null) {
            RouteQuickActionsScreen(
                routeName = draft.name.ifBlank { voxString("this route") },
                routeID = draft.id,
                captureBar = captureBar,
                isBusy = isBusy,
                navigateBack = { pageName = null },
                setActions = { setRouteQuickActions(draft.id, it) },
            )
        } else {
            LaunchedEffect(Unit) { pageName = null }
        }
        RouteEditorPage.CAPTURE, RouteEditorPage.PROCESS, RouteEditorPage.SHAPE, RouteEditorPage.DELIVER -> {
            val step = RouteEditorStep.valueOf(page.name)
            RouteEditorStepPage(step = step, navigateBack = { pageName = null }) {
                when (step) {
                    RouteEditorStep.CAPTURE -> {
                        CapturePresetVoiceEditor(
                            speakerDiarizationEnabled = draft.speakerDiarizationEnabled,
                            watchOutputMode = draft.watchOutputMode,
                            audioSaveMode = draft.audioSaveMode,
                            embedAudio = draft.embedAudio,
                            audioEmbedPlacement = draft.audioEmbedPlacement,
                            setSpeakerDiarizationEnabled = { draft = draft.copy(speakerDiarizationEnabled = it) },
                            setWatchOutputMode = { draft = draft.copy(watchOutputMode = it) },
                            setAudioSaveMode = { draft = draft.copy(audioSaveMode = it) },
                            setEmbedAudio = { draft = draft.copy(embedAudio = it) },
                            setAudioEmbedPlacement = { draft = draft.copy(audioEmbedPlacement = it) },
                        )
                        if (draft.audioSaveMode != CaptureAudioSaveMode.OFF || draft.watchOutputMode == CaptureWatchOutputMode.RECORDING_ONLY) {
                            SignalGroup(title = null, modifier = Modifier.padding(top = 14.dp)) {
                                PresetBlock { AudioFilenameControls(draft.audioFilenameTemplate, draft.name) { draft = draft.copy(audioFilenameTemplate = it) } }
                            }
                        }
                        CapturePresetLocationEditor(
                            locationEnabled = draft.locationEnabled,
                            locationPrecision = draft.locationPrecision,
                            locationUnavailableBehavior = draft.locationUnavailableBehavior,
                            locationMetadataEnabled = draft.locationMetadataEnabled,
                            locationOutputMode = draft.locationOutputMode,
                            locationStructuredFields = draft.locationStructuredFields,
                            locationCollectionKey = draft.locationCollectionKey,
                            locationAdvancedTemplate = draft.locationAdvancedTemplate,
                            locationLabelLookupClass = draft.locationLabelLookupClass,
                            locationLabelConsentVersion = draft.locationLabelConsentVersion,
                            setLocationEnabled = { draft = draft.copy(locationEnabled = it) },
                            setLocationPrecision = { draft = draft.copy(locationPrecision = it) },
                            setLocationUnavailableBehavior = { draft = draft.copy(locationUnavailableBehavior = it) },
                            setLocationMetadataEnabled = { draft = draft.copy(locationMetadataEnabled = it) },
                            setLocationOutputMode = { draft = draft.copy(locationOutputMode = it) },
                            setLocationStructuredFields = { draft = draft.copy(locationStructuredFields = it) },
                            setLocationCollectionKey = { draft = draft.copy(locationCollectionKey = it) },
                            setLocationAdvancedTemplate = { draft = draft.copy(locationAdvancedTemplate = it) },
                            setLocationLabelConsent = { consented ->
                                draft = draft.copy(
                                    locationLabelLookupClass = if (consented) {
                                        CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK
                                    } else {
                                        CaptureLocationLabelLookupClass.NONE
                                    },
                                    locationLabelConsentVersion = if (consented) CURRENT_LOCATION_LABEL_CONSENT_VERSION else null,
                                )
                            },
                        )
                    }
                    RouteEditorStep.PROCESS -> CapturePresetProcessingEditor(
                        processingEnabled = draft.processingEnabled,
                        processingScope = draft.processingScope,
                        processingMode = draft.processingMode,
                        customInstruction = draft.customInstruction,
                        generateImageAltText = draft.generateImageAltText,
                        setProcessingEnabled = { draft = draft.copy(processingEnabled = it) },
                        setProcessingScope = { draft = draft.copy(processingScope = it) },
                        setProcessingMode = { draft = draft.copy(processingMode = it) },
                        setCustomInstruction = { draft = draft.copy(customInstruction = it) },
                        setGenerateImageAltText = { draft = draft.copy(generateImageAltText = it) },
                    )
                    RouteEditorStep.SHAPE -> {
                        CapturePresetDestinationEditorFor(draft, entryTemplates, showDestination = false, showEntry = true) { draft = it }
                        CapturePresetMetadataEditor(
                            metadataScope = draft.metadataScope,
                            metadataText = draft.metadataText,
                            metadataIsValid = metadata != null,
                            setMetadataScope = { draft = draft.copy(metadataScope = it) },
                            setMetadataText = { draft = draft.copy(metadataText = it) },
                        )
                        SignalGroup(title = null, modifier = Modifier.padding(top = 14.dp)) {
                            PresetBlock {
                                TranscriptPropertyControls(draft.transcriptPropertyName, draft.includeTranscriptInBody,
                                    { draft = draft.copy(transcriptPropertyName = it) }, { draft = draft.copy(includeTranscriptInBody = it) })
                            }
                        }
                    }
                    RouteEditorStep.DELIVER -> {
                        SignalGroup(title = null, modifier = Modifier.padding(top = 14.dp)) {
                            PresetBlock { PresetVaultControl(draft.destination) { draft = draft.copy(destination = it) } }
                        }
                        CapturePresetDestinationEditorFor(draft, entryTemplates, showDestination = true, showEntry = false) { draft = it }
                        SignalGroup(title = null, modifier = Modifier.padding(top = 14.dp)) {
                            if (draft.noteTargetKind != CaptureNoteTargetKind.NEW_NOTE && draft.placement == CapturePlacementKind.BENEATH_HEADING) {
                                PresetBlock {
                                    PresetChoiceRow(voxString("Position in heading"),
                                        listOf("TOP" to voxString("Top"), "BOTTOM" to voxString("Bottom")), draft.headingPosition.name,
                                        { draft = draft.copy(headingPosition = CaptureHeadingPosition.valueOf(it)) })
                                }
                                SignalRowDivider()
                            }
                            PresetBlock { URLDeliverySettingsControl(draft.urlDelivery) { draft = draft.copy(urlDelivery = it) } }
                        }
                        CapturePresetTranscriptExportEditor(
                            settings = draft.exportSettings,
                            audioSaveMode = draft.audioSaveMode,
                            attachmentsFolder = draft.attachmentsFolder,
                            onSettingsChanged = { draft = draft.copy(exportSettings = it) },
                        )
                    }
                }
            }
        }
        null -> Scaffold(
            containerColor = c.bg,
            topBar = {
                // Route editor board header: circular Back and a "Done" pill that saves.
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(c.bg)
                        .statusBarsPadding()
                        .heightIn(min = 64.dp)
                        .padding(start = 4.dp, end = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SignalCircleButton(Icons.AutoMirrored.Outlined.ArrowBack, voxString("Back"), navigateBack, contentColor = c.text)
                    Spacer(Modifier.weight(1f))
                    SignalButton(
                        text = voxString("Done"),
                        onClick = onDone,
                        size = SignalButtonSize.MEDIUM,
                        enabled = valid && !isBusy,
                        loading = isBusy,
                        modifier = Modifier.testTag("capture_preset_editor_done"),
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
                    .padding(top = 4.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                PresetEditorSummary(
                    name = draft.name,
                    symbol = draft.symbol,
                    emoji = draft.emoji,
                    isEnabled = draft.isEnabled,
                    subtitle = routeEditorSubtitle(isDefault = isDefault, isEnabled = draft.isEnabled, isPinned = draft.isPinned),
                )
                // A new route needs a name before anything else; existing routes keep identity below.
                if (preset == null) RouteIdentityEditor(draft) { draft = it }
                Spacer(Modifier.height(8.dp))
                RouteStepRail(
                    steps = routeStepSummaries(
                        preset = livePreset,
                        entryTemplateName = entryTemplates.firstOrNull { it.id == draft.entryTemplateID }?.name,
                        rootName = defaultDestinationName,
                        invalidSteps = invalidSteps,
                    ),
                    openStep = { pageName = it.page().name },
                )
                RoutePreviewCard(routeSamplePreview(livePreset))
                if (captureBar != null && setRouteQuickActions != null) {
                    RouteQuickActionsCard(
                        actions = captureBar.pinnedActions(draft.id),
                        onClick = { pageName = RouteEditorPage.QUICK_ACTIONS.name },
                        enabled = true,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
                // Quick toggles; the same settings as CAPTURE › Voice and Audio / Location.
                SignalGroup(title = null, modifier = Modifier.padding(top = 8.dp)) {
                    SignalToggleRow(
                        title = voxString("Speaker labels"),
                        checked = draft.speakerDiarizationEnabled,
                        onCheckedChange = { draft = draft.copy(speakerDiarizationEnabled = it) },
                    )
                    SignalRowDivider()
                    SignalToggleRow(
                        title = voxString("Attach location"),
                        checked = draft.locationEnabled,
                        onCheckedChange = { draft = draft.copy(locationEnabled = it) },
                    )
                }
                if (preset != null) RouteIdentityEditor(draft) { draft = it }
                SignalCard(
                    modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
                    color = c.well,
                    borderColor = null,
                    radius = SignalMetrics.GroupRadius,
                    padding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
                ) {
                    Text(voxString("Route changes only affect new captures. A pending capture keeps the exact route it started with."),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                }
                if (delete != null) {
                    // Deleting a route also retires its destination, so it is confirmed first.
                    var confirmingDelete by rememberSaveable { mutableStateOf(false) }
                    if (confirmingDelete) {
                        AlertDialog(
                            onDismissRequest = { confirmingDelete = false },
                            containerColor = c.bg,
                            titleContentColor = c.text,
                            textContentColor = c.text,
                            shape = RoundedCornerShape(24.dp),
                            title = { Text(voxString("Delete Route")) },
                            text = { Text(draft.name) },
                            confirmButton = {
                                TextButton(onClick = { confirmingDelete = false; delete() }) {
                                    Text(voxString("Delete Route"), color = c.error)
                                }
                            },
                            dismissButton = {
                                TextButton(onClick = { confirmingDelete = false }) { Text(voxString("Cancel")) }
                            },
                        )
                    }
                    SignalButton(
                        text = voxString("Delete Route"),
                        onClick = { confirmingDelete = true },
                        modifier = Modifier.padding(top = 12.dp),
                        variant = SignalButtonVariant.DESTRUCTIVE,
                        enabled = !isBusy,
                        icon = Icons.Outlined.Delete,
                    )
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

/** Header subtitle: "Default route · pinned to Capture Bar", "Disabled", or "Route". */
@Composable
private fun routeEditorSubtitle(isDefault: Boolean, isEnabled: Boolean, isPinned: Boolean): String {
    val parts = buildList {
        if (isDefault) add(voxString("Default route"))
        if (!isEnabled) add(voxString("Disabled"))
        if (isPinned) add(voxFormat("pinned to %@", voxString("Capture Bar")))
    }.ifEmpty { listOf(voxString("Route")) }
    val joined = parts.joinToString(" · ")
    val locale = LocalConfiguration.current.locales[0] ?: Locale.ENGLISH
    return joined.replaceFirstChar { it.titlecase(locale) }
}

@Composable
private fun RouteIdentityEditor(draft: CapturePresetEditorDraft, update: (CapturePresetEditorDraft) -> Unit) {
    CapturePresetIdentityEditor(
        name = draft.name,
        symbol = draft.symbol,
        emoji = draft.emoji,
        isEnabled = draft.isEnabled,
        isPinned = draft.isPinned,
        setName = { update(draft.copy(name = it)) },
        setSymbol = { update(draft.copy(symbol = it, emoji = null)) },
        setEmoji = { update(draft.copy(emoji = it)) },
        setEnabled = { update(draft.copy(isEnabled = it)) },
        setPinned = { update(draft.copy(isPinned = it)) },
    )
}

/** The destination editor bound to a draft, showing its Destination and/or Entry groups. */
@Composable
private fun CapturePresetDestinationEditorFor(
    draft: CapturePresetEditorDraft,
    entryTemplates: List<CaptureEntryTemplate>,
    showDestination: Boolean,
    showEntry: Boolean,
    update: (CapturePresetEditorDraft) -> Unit,
) {
    CapturePresetDestinationEditor(
        noteTargetKind = draft.noteTargetKind,
        rollingPeriod = draft.rollingPeriod,
        logicalFolder = draft.logicalFolder,
        noteNameTemplate = draft.noteNameTemplate,
        existingNotePath = draft.existingNotePath,
        placement = draft.placement,
        headingTitle = draft.headingTitle,
        headingLevel = draft.headingLevel,
        missingHeadingBehavior = draft.missingHeadingBehavior,
        entryPrefix = draft.entryPrefix,
        entrySuffix = draft.entrySuffix,
        entryTemplateID = draft.entryTemplateID,
        entryTemplates = entryTemplates,
        attachmentsFolder = draft.attachmentsFolder,
        retryProtectionEnabled = draft.retryProtectionEnabled,
        setNoteTargetKind = { kind ->
            update(
                draft.copy(
                    noteTargetKind = kind,
                    noteNameTemplate = when {
                        kind == CaptureNoteTargetKind.ROLLING_NOTE && draft.noteNameTemplate == "capture-{id}.md" -> "{period}.md"
                        kind == CaptureNoteTargetKind.NEW_NOTE && draft.noteNameTemplate == "{period}.md" -> "capture-{id}.md"
                        else -> draft.noteNameTemplate
                    },
                ),
            )
        },
        setRollingPeriod = { update(draft.copy(rollingPeriod = it)) },
        setLogicalFolder = { update(draft.copy(logicalFolder = it)) },
        setNoteNameTemplate = { update(draft.copy(noteNameTemplate = it)) },
        setExistingNotePath = { update(draft.copy(existingNotePath = it)) },
        setPlacement = { update(draft.copy(placement = it)) },
        setHeadingTitle = { update(draft.copy(headingTitle = it)) },
        setHeadingLevel = { update(draft.copy(headingLevel = it)) },
        setMissingHeadingBehavior = { update(draft.copy(missingHeadingBehavior = it)) },
        setEntryPrefix = { update(draft.copy(entryPrefix = it)) },
        setEntrySuffix = { update(draft.copy(entrySuffix = it)) },
        setEntryTemplateID = { templateID ->
            val template = entryTemplates.firstOrNull { it.id == templateID }
            update(
                if (template == null) {
                    draft.copy(entryTemplateID = null)
                } else {
                    draft.copy(
                        entryTemplateID = template.id,
                        entryPrefix = template.entryPrefix,
                        entrySuffix = template.entrySuffix,
                    )
                },
            )
        },
        setAttachmentsFolder = { update(draft.copy(attachmentsFolder = it)) },
        setRetryProtectionEnabled = { update(draft.copy(retryProtectionEnabled = it)) },
        showDestination = showDestination,
        showEntry = showEntry,
    )
}

/** One step's settings, on its own page with a back button to the step overview. */
@Composable
private fun RouteEditorStepPage(
    step: RouteEditorStep,
    navigateBack: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val c = Signal.colors
    Scaffold(
        containerColor = c.bg,
        topBar = {
            SignalTopBar(
                title = step.kindText.localized(),
                navigateBack = navigateBack,
                backDescription = voxString("Back"),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SignalMetrics.PageGutter)
                .padding(top = 4.dp, bottom = 32.dp)
                .testTag("route_step_page_${step.number}"),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content,
        )
    }
}

/** Route header: toned tile, live name and a status subtitle ("Default route · pinned to Capture Bar"). */
@Composable
private fun PresetEditorSummary(name: String, symbol: String, emoji: String?, isEnabled: Boolean, subtitle: String) {
    val c = Signal.colors
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PresetRouteTile(
            name = name,
            symbol = symbol,
            emoji = emoji,
            tone = if (isEnabled) SignalRouteTone.PRIMARY else SignalRouteTone.NEUTRAL,
            size = 52.dp,
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                name.ifBlank { voxString("Name") },
                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.SemiBold),
                color = if (name.isBlank()) c.faint else c.text,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.semantics { heading() },
            )
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = c.muted)
        }
    }
}

@Composable
internal fun CapturePresetIdentityEditor(
    name: String,
    symbol: String,
    emoji: String?,
    isEnabled: Boolean,
    isPinned: Boolean,
    setName: (String) -> Unit,
    setSymbol: (String) -> Unit,
    setEmoji: (String?) -> Unit,
    setEnabled: (Boolean) -> Unit,
    setPinned: (Boolean) -> Unit,
) {
    val c = Signal.colors
    SignalGroup(voxString("Identity")) {
        PresetBlock {
            OutlinedTextField(
                value = name,
                onValueChange = { setName(it.take(80)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(voxString("Name")) },
                singleLine = true,
                shape = SignalFieldShape,
                colors = signalTextFieldColors(),
            )
        }
        SignalRowDivider()
        PresetSwitchRow(voxString("Enabled"), voxString("Show this route in capture pickers."), isEnabled, setEnabled)
        SignalRowDivider()
        PresetSwitchRow(voxString("Pinned"), voxString("Pin this route to the capture bar and the top of the list."), isPinned, setPinned)
    }
    // One mode at a time: a symbol, an emoji, or no icon at all. The selection is
    // local state so an empty emoji field still shows Emoji mode; switching away
    // from Emoji commits immediately. Only the emoji field keeps uncommitted input.
    var selectedMode by remember { mutableStateOf(presetIconMode(symbol, emoji)) }
    val iconMode = selectedMode
    // Uncommitted native text input; validation never rewrites the field while a
    // multi-emoji paste is still visible. Only a normalized value reaches the draft.
    var emojiInput by remember(symbol, emoji) { mutableStateOf(emoji.orEmpty()) }
    val normalizedInput = CapturePresetEmoji.normalized(emojiInput)
    val previewEmoji = if (iconMode == PresetIconMode.EMOJI) normalizedInput ?: emoji else emoji
    SignalGroup(voxString("Icon")) {
        PresetBlock {
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                PresetIconMode.entries.forEachIndexed { index, mode ->
                    SegmentedButton(
                        selected = iconMode == mode,
                        onClick = {
                            selectedMode = mode
                            when (mode) {
                                PresetIconMode.SYMBOL -> {
                                    setEmoji(null)
                                    if (symbol.isBlank()) setSymbol(PRESET_SYMBOLS.first())
                                }
                                PresetIconMode.EMOJI -> Unit // The field below commits once input is valid.
                                PresetIconMode.NONE -> {
                                    setEmoji(null)
                                    setSymbol("")
                                }
                            }
                        },
                        shape = SegmentedButtonDefaults.itemShape(index = index, count = PresetIconMode.entries.size),
                        colors = presetSegmentedColors(),
                        icon = {},
                        label = {
                            Text(
                                when (mode) {
                                    PresetIconMode.SYMBOL -> voxString("Symbol")
                                    PresetIconMode.EMOJI -> voxString("Emoji")
                                    PresetIconMode.NONE -> voxString("None")
                                },
                                style = MaterialTheme.typography.labelMedium,
                            )
                        },
                    )
                }
            }
            when (iconMode) {
                PresetIconMode.SYMBOL -> LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(PRESET_SYMBOLS, key = { it }) { option ->
                        PresetChoiceChip(
                            selected = symbol == option,
                            label = presetSymbolLabel(option).localized(),
                            onClick = { setSymbol(option) },
                            leadingIcon = presetIcon(option),
                        )
                    }
                }
                PresetIconMode.EMOJI -> {
                    OutlinedTextField(
                        value = emojiInput,
                        onValueChange = { input ->
                            emojiInput = input
                            // Valid input applies immediately; blank clears back to the symbol;
                            // an invalid value never overwrites the committed emoji.
                            setEmoji(CapturePresetEmoji.normalized(input) ?: if (input.isBlank()) null else emoji)
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(voxString("Emoji")) },
                        singleLine = true,
                        isError = emojiInput.isNotBlank() && normalizedInput == null,
                        shape = SignalFieldShape,
                        colors = signalTextFieldColors(),
                        supportingText = {
                            Text(
                                if (normalizedInput == null) {
                                    if (emojiInput.isBlank()) voxString("Enter one emoji to preview it, or choose a symbol.")
                                    else voxString("Enter a single emoji, not text or multiple emoji. Your current icon has not changed.")
                                } else {
                                    voxString("Use the emoji keyboard or paste one emoji. Flags, skin tones, and family emoji are supported.")
                                },
                                color = if (emojiInput.isNotBlank() && normalizedInput == null) c.error else c.muted,
                            )
                        },
                    )
                    PresetHint(voxString("Your symbol is kept as a fallback for surfaces that cannot display emoji."))
                }
                PresetIconMode.NONE -> PresetHint(
                    voxString("Without an icon, the route's first letter is shown where an icon is required."),
                )
            }
        }
        SignalRowDivider()
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(13.dp))
                    .background(c.well),
                contentAlignment = Alignment.Center,
            ) {
                PresetIdentityIcon(
                    symbol = symbol,
                    emoji = previewEmoji,
                    name = name,
                    contentDescription = null,
                    tint = c.text,
                    emojiStyle = TextStyle(fontSize = 22.sp),
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    if (iconMode == PresetIconMode.EMOJI && normalizedInput != null) {
                        voxString("Preview")
                    } else {
                        voxString("Current Icon")
                    },
                    style = SignalType.sectionLabel,
                    color = c.muted,
                )
                Text(
                    name.ifBlank { voxString("Name") },
                    style = SignalType.rowTitle,
                    color = if (name.isBlank()) c.faint else c.text,
                )
            }
        }
    }
}

internal enum class PresetIconMode { SYMBOL, EMOJI, NONE }

internal fun presetIconMode(symbol: String, emoji: String?): PresetIconMode = when {
    emoji != null -> PresetIconMode.EMOJI
    symbol.isNotBlank() -> PresetIconMode.SYMBOL
    else -> PresetIconMode.NONE
}

/**
 * Decorative preset identity: a validated emoji wins over the stored symbol;
 * with neither, the preset's initial stands in so icon-only surfaces (the rail)
 * never render a blank target. The enclosing control owns the name label.
 */
@Composable
internal fun PresetIdentityIcon(
    symbol: String?,
    emoji: String?,
    name: String? = null,
    modifier: Modifier = Modifier,
    contentDescription: String? = null,
    tint: Color = LocalContentColor.current,
    emojiStyle: TextStyle = LocalTextStyle.current.copy(color = tint),
) {
    val normalized = CapturePresetEmoji.normalized(emoji)
    Box(modifier = modifier.wrapContentSize(Alignment.Center), contentAlignment = Alignment.Center) {
        when {
            normalized != null -> Text(normalized, style = emojiStyle, color = tint)
            !symbol.isNullOrBlank() -> Icon(presetIcon(symbol), contentDescription = contentDescription, tint = tint)
            else -> {
                val initial = name?.trim()?.takeIf(String::isNotEmpty)
                    ?.let { String(Character.toChars(it.codePointAt(0))) }
                    ?.uppercase()
                    .orEmpty()
                Text(initial, style = MaterialTheme.typography.labelLarge, color = tint)
            }
        }
    }
}

@Composable
internal fun CapturePresetDestinationEditor(
    noteTargetKind: CaptureNoteTargetKind,
    rollingPeriod: CaptureRollingPeriod,
    logicalFolder: String,
    noteNameTemplate: String,
    existingNotePath: String,
    placement: CapturePlacementKind,
    headingTitle: String,
    headingLevel: Int,
    missingHeadingBehavior: CaptureMissingHeadingBehavior,
    entryPrefix: String,
    entrySuffix: String,
    entryTemplateID: String?,
    entryTemplates: List<CaptureEntryTemplate>,
    attachmentsFolder: String,
    retryProtectionEnabled: Boolean,
    setNoteTargetKind: (CaptureNoteTargetKind) -> Unit,
    setRollingPeriod: (CaptureRollingPeriod) -> Unit,
    setLogicalFolder: (String) -> Unit,
    setNoteNameTemplate: (String) -> Unit,
    setExistingNotePath: (String) -> Unit,
    setPlacement: (CapturePlacementKind) -> Unit,
    setHeadingTitle: (String) -> Unit,
    setHeadingLevel: (Int) -> Unit,
    setMissingHeadingBehavior: (CaptureMissingHeadingBehavior) -> Unit,
    setEntryPrefix: (String) -> Unit,
    setEntrySuffix: (String) -> Unit,
    setEntryTemplateID: (String?) -> Unit,
    setAttachmentsFolder: (String) -> Unit,
    setRetryProtectionEnabled: (Boolean) -> Unit,
    /** The route editor shows the Destination group under DELIVER and the Entry group under SHAPE. */
    showDestination: Boolean = true,
    showEntry: Boolean = true,
) {
    if (showDestination) SignalGroup(voxString("Destination")) {
        PresetBlock {
            PresetChoiceRow(
                title = voxString("Note target"),
                options = listOf(
                    CaptureNoteTargetKind.NEW_NOTE.name to voxString("New Note"),
                    CaptureNoteTargetKind.ROLLING_NOTE.name to voxString("Rolling Note"),
                    CaptureNoteTargetKind.EXISTING_NOTE.name to voxString("Existing Note"),
                ),
                selected = noteTargetKind.name,
                onSelected = { setNoteTargetKind(CaptureNoteTargetKind.valueOf(it)) },
            )
        }
        if (noteTargetKind == CaptureNoteTargetKind.ROLLING_NOTE) {
            SignalRowDivider()
            PresetBlock {
                PresetChoiceRow(
                    title = voxString("Rolling period"),
                    options = CaptureRollingPeriod.entries.map { period ->
                        period.name to captureRollingPeriodUiText(period).localized()
                    },
                    selected = rollingPeriod.name,
                    onSelected = { setRollingPeriod(CaptureRollingPeriod.valueOf(it)) },
                )
            }
        }
        SignalRowDivider()
        PresetBlock {
            if (noteTargetKind == CaptureNoteTargetKind.EXISTING_NOTE) {
                OutlinedTextField(
                    value = existingNotePath,
                    onValueChange = { setExistingNotePath(it.take(512)) },
                    isError = CapturePresetPaths.existingNote(existingNotePath) == null,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Existing note path")) },
                    placeholder = { Text(voxString("Journal/Inbox.md"), style = SignalType.mono) },
                    textStyle = presetMonoFieldStyle(),
                    singleLine = true,
                    shape = SignalFieldShape,
                    colors = signalTextFieldColors(),
                )
            } else {
                OutlinedTextField(
                    value = logicalFolder,
                    onValueChange = { setLogicalFolder(it.take(256)) },
                    isError = CapturePresetPaths.folder(logicalFolder) == null,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Folder")) },
                    placeholder = { Text(voxString("Inbox"), style = SignalType.mono) },
                    textStyle = presetMonoFieldStyle(),
                    singleLine = true,
                    shape = SignalFieldShape,
                    colors = signalTextFieldColors(),
                )
                OutlinedTextField(
                    value = noteNameTemplate,
                    onValueChange = { setNoteNameTemplate(it.take(256)) },
                    isError = CapturePresetPaths.filename(noteNameTemplate) == null,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Note filename template")) },
                    placeholder = { Text(voxString("capture-{id}.md"), style = SignalType.mono) },
                    supportingText = { Text(voxString("Supports {id}, {date}, {time}, {year}, {month}, {week}, and {quarter}.")) },
                    textStyle = presetMonoFieldStyle(),
                    singleLine = true,
                    shape = SignalFieldShape,
                    colors = signalTextFieldColors(),
                )
            }
        }
        if (noteTargetKind != CaptureNoteTargetKind.NEW_NOTE) {
            SignalRowDivider()
            PresetBlock {
                PresetChoiceRow(
                    title = voxString("Placement"),
                    options = listOf(
                        CapturePlacementKind.APPEND.name to capturePlacementUiText(CapturePlacementKind.APPEND).localized(),
                        CapturePlacementKind.PREPEND.name to capturePlacementUiText(CapturePlacementKind.PREPEND).localized(),
                        CapturePlacementKind.BENEATH_HEADING.name to capturePlacementUiText(CapturePlacementKind.BENEATH_HEADING).localized(),
                    ),
                    selected = placement.name,
                    onSelected = { setPlacement(CapturePlacementKind.valueOf(it)) },
                )
                if (placement == CapturePlacementKind.BENEATH_HEADING) {
                    OutlinedTextField(
                        value = headingTitle,
                        onValueChange = { setHeadingTitle(it.take(256)) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(voxString("Heading title")) },
                        singleLine = true,
                        shape = SignalFieldShape,
                        colors = signalTextFieldColors(),
                    )
                }
            }
            if (placement == CapturePlacementKind.BENEATH_HEADING) {
                SignalRowDivider()
                PresetBlock {
                    PresetChoiceRow(
                        title = voxString("Heading level"),
                        options = (1..6).map { it.toString() to "H$it" },
                        selected = headingLevel.toString(),
                        onSelected = { setHeadingLevel(it.toInt()) },
                    )
                }
                SignalRowDivider()
                PresetBlock {
                    PresetChoiceRow(
                        title = voxString("If heading is missing"),
                        options = listOf(
                            CaptureMissingHeadingBehavior.FAIL.name to voxString("Keep Pending"),
                            CaptureMissingHeadingBehavior.CREATE.name to voxString("Create Heading"),
                        ),
                        selected = missingHeadingBehavior.name,
                        onSelected = { setMissingHeadingBehavior(CaptureMissingHeadingBehavior.valueOf(it)) },
                    )
                }
            }
        }
    }
    if (showEntry) SignalGroup(voxString("Entry")) {
        PresetBlock {
            PresetChoiceRow(
                title = voxString("Formatting"),
                options = listOf("" to voxString("Custom")) + entryTemplates.map { it.id to it.name },
                selected = entryTemplateID.orEmpty(),
                onSelected = { setEntryTemplateID(it.ifEmpty { null }) },
            )
        }
        SignalRowDivider()
        PresetBlock {
            if (entryTemplateID == null) {
                OutlinedTextField(
                    value = entryPrefix,
                    onValueChange = { setEntryPrefix(it.take(16_384)) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Prefix")) },
                    placeholder = { Text(voxString("- {time} "), style = SignalType.mono) },
                    textStyle = presetMonoFieldStyle(),
                    minLines = 2,
                    shape = SignalFieldShape,
                    colors = signalTextFieldColors(),
                )
                OutlinedTextField(
                    value = entrySuffix,
                    onValueChange = { setEntrySuffix(it.take(16_384)) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Suffix")) },
                    textStyle = presetMonoFieldStyle(),
                    minLines = 2,
                    shape = SignalFieldShape,
                    colors = signalTextFieldColors(),
                )
            } else {
                PresetHint(voxString("This route uses the linked template. Template edits apply automatically; the last formatting remains safe if the template is removed."))
                Text(
                    entryTemplateDescription(CaptureEntryTemplate(entryTemplateID, "", entryPrefix, entrySuffix)),
                    style = SignalType.mono,
                    color = Signal.colors.text,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(SignalFieldShape)
                        .background(Signal.colors.well)
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                )
            }
        }
        SignalRowDivider()
        PresetBlock {
            OutlinedTextField(
                value = attachmentsFolder,
                onValueChange = { setAttachmentsFolder(it.take(256)) },
                isError = CapturePresetPaths.folder(attachmentsFolder, allowEmpty = true) == null,
                modifier = Modifier.fillMaxWidth(),
                label = { Text(voxString("Attachments folder")) },
                supportingText = { Text(voxString("Leave empty to store files beside the note.")) },
                textStyle = presetMonoFieldStyle(),
                singleLine = true,
                shape = SignalFieldShape,
                colors = signalTextFieldColors(),
            )
        }
        SignalRowDivider()
        PresetSwitchRow(
            voxString("Retry protection marker"),
            voxString("Embed an invisible request marker so interrupted writes can be reconciled safely."),
            retryProtectionEnabled,
            setRetryProtectionEnabled,
        )
    }
}

@Composable
internal fun CapturePresetMetadataEditor(
    metadataScope: CaptureMetadataScope,
    metadataText: String,
    metadataIsValid: Boolean,
    setMetadataScope: (CaptureMetadataScope) -> Unit,
    setMetadataText: (String) -> Unit,
) {
    SignalGroup(voxString("Metadata")) {
        PresetBlock {
            PresetChoiceRow(
                title = voxString("Scope"),
                options = listOf(
                    CaptureMetadataScope.DOCUMENT.name to voxString("Document Frontmatter"),
                    CaptureMetadataScope.ENTRY.name to voxString("Inline Entry"),
                ),
                selected = metadataScope.name,
                onSelected = { setMetadataScope(CaptureMetadataScope.valueOf(it)) },
            )
        }
        SignalRowDivider()
        PresetBlock {
            OutlinedTextField(
                value = metadataText,
                onValueChange = { setMetadataText(it.take(9_216)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(voxString("Metadata fields")) },
                placeholder = { Text(voxString("source: android\ntags: inbox"), style = SignalType.mono) },
                supportingText = {
                    Text(voxString(if (metadataIsValid) "One key/value pair per line." else "Use unique letters, numbers, _ or - for each key."))
                },
                isError = !metadataIsValid,
                textStyle = presetMonoFieldStyle(),
                minLines = 3,
                shape = SignalFieldShape,
                colors = signalTextFieldColors(),
            )
        }
    }
}

@Composable
internal fun CapturePresetVoiceEditor(
    speakerDiarizationEnabled: Boolean,
    watchOutputMode: CaptureWatchOutputMode,
    audioSaveMode: CaptureAudioSaveMode,
    embedAudio: Boolean,
    audioEmbedPlacement: CaptureAudioEmbedPlacement,
    setSpeakerDiarizationEnabled: (Boolean) -> Unit,
    setWatchOutputMode: (CaptureWatchOutputMode) -> Unit,
    setAudioSaveMode: (CaptureAudioSaveMode) -> Unit,
    setEmbedAudio: (Boolean) -> Unit,
    setAudioEmbedPlacement: (CaptureAudioEmbedPlacement) -> Unit,
) {
    SignalGroup(voxString("Voice and Audio")) {
        PresetSwitchRow(
            voxString("Speaker diarization"),
            voxString("Label detected speakers when the installed transcription engine supports it."),
            speakerDiarizationEnabled,
            setSpeakerDiarizationEnabled,
        )
        SignalRowDivider()
        PresetBlock {
            PresetChoiceRow(
                title = voxString("Watch output"),
                options = listOf(
                    CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE.name to voxString("Transcribe & Capture"),
                    CaptureWatchOutputMode.RECORDING_ONLY.name to voxString("Recording Only"),
                ),
                selected = watchOutputMode.name,
                onSelected = { setWatchOutputMode(CaptureWatchOutputMode.valueOf(it)) },
            )
            if (watchOutputMode == CaptureWatchOutputMode.RECORDING_ONLY) {
                PresetHint(voxString("Recording Only writes verified WAV audio to this route's export folder using the new-file name template. It skips transcription and location."))
            }
        }
        SignalRowDivider()
        PresetBlock {
            PresetChoiceRow(
                title = voxString("Save original audio"),
                options = listOf(
                    CaptureAudioSaveMode.OFF.name to voxString("Off"),
                    CaptureAudioSaveMode.ALONGSIDE_NOTE.name to voxString("Beside Note"),
                    CaptureAudioSaveMode.ATTACHMENTS_FOLDER.name to voxString("Attachments"),
                ),
                selected = audioSaveMode.name,
                onSelected = { setAudioSaveMode(CaptureAudioSaveMode.valueOf(it)) },
            )
        }
        if (audioSaveMode != CaptureAudioSaveMode.OFF) {
            SignalRowDivider()
            PresetSwitchRow(voxString("Embed audio"), voxString("Add an audio link to the Markdown entry."), embedAudio, setEmbedAudio)
            if (embedAudio) {
                SignalRowDivider()
                PresetBlock {
                    PresetChoiceRow(
                        title = voxString("Audio link placement"),
                        options = listOf(
                            CaptureAudioEmbedPlacement.BEFORE_TEXT.name to voxString("Before Text"),
                            CaptureAudioEmbedPlacement.AFTER_TEXT.name to voxString("After Text"),
                        ),
                        selected = audioEmbedPlacement.name,
                        onSelected = { setAudioEmbedPlacement(CaptureAudioEmbedPlacement.valueOf(it)) },
                    )
                }
            }
        }
    }
}

@Composable
internal fun CapturePresetTranscriptExportEditor(
    settings: CapturePresetExportSettings,
    audioSaveMode: CaptureAudioSaveMode,
    attachmentsFolder: String,
    onSettingsChanged: (CapturePresetExportSettings) -> Unit,
) {
    val context = LocalContext.current
    val exportEnabled = settings.usesCustomExportSettings && settings.exportEnabled
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
            onSettingsChanged(
                settings.copy(
                    usesCustomExportSettings = true,
                    destinationTreeUri = uri.toString(),
                    destinationName = queryTreeDisplayName(context, uri),
                ),
            )
        }
    }
    val templatePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            onSettingsChanged(
                settings.copy(
                    usesCustomExportSettings = true,
                    markdownTemplateUri = uri.toString(),
                    markdownTemplateName = queryDocumentDisplayName(context, uri),
                ),
            )
        }
    }

    SignalGroup(voxString("Transcript File Export")) {
        PresetSwitchRow(
            voxString("Export completed transcripts"),
            voxString("Write completed recordings to a separate document folder using this route's format."),
            exportEnabled,
        ) { enabled ->
            onSettingsChanged(settings.copy(usesCustomExportSettings = true, exportEnabled = enabled))
        }
        if (exportEnabled) {
            SignalRowDivider()
            PresetPickedDocumentBlock(
                buttonLabel = voxString(if (settings.destinationTreeUri == null) "Choose Export Folder" else "Change Export Folder"),
                icon = Icons.Outlined.FolderOpen,
                pickedName = settings.destinationName.takeIf(String::isNotBlank) ?: voxString("No export folder selected"),
                missing = settings.destinationTreeUri == null,
                onPick = { folderPicker.launch(null) },
            )
            SignalRowDivider()
            PresetBlock {
                PresetChoiceRow(
                    title = voxString("File mode"),
                    options = listOf(
                        CaptureExportFileMode.NEW_FILE.name to voxString("New File"),
                        CaptureExportFileMode.APPEND.name to voxString("Append"),
                    ),
                    selected = settings.mode.name,
                    onSelected = { onSettingsChanged(settings.copy(mode = CaptureExportFileMode.valueOf(it))) },
                )
            }
            SignalRowDivider()
            PresetBlock {
                PresetChoiceRow(
                    title = voxString("Format"),
                    options = listOf(
                        CaptureExportFileFormat.MARKDOWN.name to voxString("Markdown"),
                        CaptureExportFileFormat.TEXT.name to voxString("Plain Text"),
                        CaptureExportFileFormat.JSON.name to voxString("JSON"),
                        CaptureExportFileFormat.YAML.name to voxString("YAML"),
                    ),
                    selected = settings.format.name,
                    onSelected = {
                        val format = CaptureExportFileFormat.valueOf(it)
                        onSettingsChanged(
                            settings.copy(
                                format = format,
                                markdownTemplateEnabled = settings.markdownTemplateEnabled && format == CaptureExportFileFormat.MARKDOWN,
                            ),
                        )
                    },
                )
            }
            SignalRowDivider()
            PresetBlock {
                if (settings.mode == CaptureExportFileMode.NEW_FILE) {
                    OutlinedTextField(
                        value = settings.newFileNameTemplate,
                        onValueChange = { onSettingsChanged(settings.copy(newFileNameTemplate = it.take(256))) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(voxString("New filename template")) },
                        supportingText = { Text(voxString("Supports {timestamp}, {date}, {YR}, {time}, {id}, {id8}, {model}, and {language}.")) },
                        textStyle = presetMonoFieldStyle(),
                        singleLine = true,
                        shape = SignalFieldShape,
                        colors = signalTextFieldColors(),
                    )
                } else {
                    OutlinedTextField(
                        value = settings.appendFileName,
                        onValueChange = { onSettingsChanged(settings.copy(appendFileName = it.take(256))) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(voxString("Append filename")) },
                        textStyle = presetMonoFieldStyle(),
                        singleLine = true,
                        shape = SignalFieldShape,
                        colors = signalTextFieldColors(),
                    )
                }
            }
            if (settings.format == CaptureExportFileFormat.MARKDOWN) {
                SignalRowDivider()
                PresetSwitchRow(
                    voxString("Obsidian frontmatter"),
                    voxString("Export Markdown as YAML frontmatter followed by the transcript metadata."),
                    settings.mdObsidianEnabled,
                ) { onSettingsChanged(settings.copy(mdObsidianEnabled = it)) }
                SignalRowDivider()
                PresetSwitchRow(
                    voxString("Use Markdown template"),
                    voxString("Render a selected Markdown template, fill its known frontmatter fields, then append the transcript."),
                    settings.markdownTemplateEnabled,
                ) { onSettingsChanged(settings.copy(markdownTemplateEnabled = it)) }
                if (settings.markdownTemplateEnabled) {
                    PresetPickedDocumentBlock(
                        buttonLabel = voxString(if (settings.markdownTemplateUri == null) "Choose Markdown Template" else "Change Markdown Template"),
                        icon = Icons.Outlined.Description,
                        pickedName = settings.markdownTemplateName.takeIf(String::isNotBlank) ?: voxString("No Markdown template selected"),
                        missing = settings.markdownTemplateUri == null,
                        onPick = { templatePicker.launch(arrayOf("text/markdown", "text/plain")) },
                        top = 0.dp,
                    )
                }
                if (audioSaveMode != CaptureAudioSaveMode.OFF) {
                    SignalRowDivider()
                    PresetSwitchRow(
                        voxString("Embed exported audio"),
                        if (audioSaveMode == CaptureAudioSaveMode.ATTACHMENTS_FOLDER) {
                            voxFormat(
                                "Copy retained audio into %@ and add an Obsidian audio embed.",
                                attachmentsFolder.takeIf(String::isNotBlank) ?: voxString("Attachments"),
                            )
                        } else {
                            voxString("Copy retained audio beside the transcript and add an Obsidian audio embed.")
                        },
                        settings.embedAudioInMarkdown,
                    ) { onSettingsChanged(settings.copy(embedAudioInMarkdown = it)) }
                    if (settings.embedAudioInMarkdown) {
                        SignalRowDivider()
                        PresetBlock {
                            PresetChoiceRow(
                                title = voxString("Exported audio placement"),
                                options = listOf(
                                    CaptureAudioEmbedPlacement.BEFORE_TEXT.name to voxString("Top"),
                                    CaptureAudioEmbedPlacement.AFTER_TEXT.name to voxString("Bottom"),
                                ),
                                selected = settings.audioEmbedPlacement.name,
                                onSelected = {
                                    onSettingsChanged(
                                        settings.copy(audioEmbedPlacement = CaptureAudioEmbedPlacement.valueOf(it)),
                                    )
                                },
                            )
                        }
                    }
                }
            }
            if (settings.format == CaptureExportFileFormat.YAML) {
                SignalRowDivider()
                PresetSwitchRow(
                    voxString("Use .md extension"),
                    voxString("Wrap YAML in Markdown frontmatter for Obsidian-compatible files."),
                    settings.yamlUsesMarkdownExtension,
                ) { onSettingsChanged(settings.copy(yamlUsesMarkdownExtension = it)) }
                SignalRowDivider()
                PresetBlock {
                    Text(voxString("YAML properties"), style = SignalType.rowTitle, color = Signal.colors.text)
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(CaptureExportYAMLProperty.entries, key = { it.name }) { property ->
                            val selected = property in settings.yamlProperties
                            PresetChoiceChip(
                                selected = selected,
                                label = exportYAMLPropertyUiText(property).localized(),
                                onClick = {
                                    val next = if (selected) settings.yamlProperties - property else settings.yamlProperties + property
                                    if (next.isNotEmpty()) onSettingsChanged(settings.copy(yamlProperties = next))
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Picker button plus the picked document name; the name turns red while nothing is chosen. */
@Composable
private fun PresetPickedDocumentBlock(
    buttonLabel: String,
    icon: ImageVector,
    pickedName: String,
    missing: Boolean,
    onPick: () -> Unit,
    top: Dp = 12.dp,
) {
    val c = Signal.colors
    PresetBlock(top = top) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (missing) Icons.Outlined.ErrorOutline else icon,
                contentDescription = null,
                tint = if (missing) c.error else c.muted,
                modifier = Modifier.size(18.dp),
            )
            Text(
                pickedName,
                color = if (missing) c.error else c.text,
                style = if (missing) MaterialTheme.typography.bodyMedium else SignalType.mono,
                modifier = Modifier.weight(1f),
            )
        }
        SignalButton(
            text = buttonLabel,
            onClick = onPick,
            variant = SignalButtonVariant.SECONDARY,
            size = SignalButtonSize.MEDIUM,
        )
    }
}

internal fun exportYAMLPropertyUiText(property: CaptureExportYAMLProperty): VoxUiText = when (property) {
    CaptureExportYAMLProperty.ID -> voxUiText("Identifier")
    CaptureExportYAMLProperty.TEXT -> voxUiText("Text")
    CaptureExportYAMLProperty.DATE -> voxUiText("Date")
    CaptureExportYAMLProperty.DURATION -> voxUiText("Duration")
    CaptureExportYAMLProperty.MODEL_USED -> voxUiText("Model")
    CaptureExportYAMLProperty.LANGUAGE -> voxUiText("Language")
}

@Composable
internal fun CapturePresetProcessingEditor(
    processingEnabled: Boolean,
    processingScope: CaptureProcessingScope,
    processingMode: CaptureProcessingMode,
    customInstruction: String,
    generateImageAltText: Boolean,
    setProcessingEnabled: (Boolean) -> Unit,
    setProcessingScope: (CaptureProcessingScope) -> Unit,
    setProcessingMode: (CaptureProcessingMode) -> Unit,
    setCustomInstruction: (String) -> Unit,
    setGenerateImageAltText: (Boolean) -> Unit,
) {
    SignalGroup(voxString("On-device Processing")) {
        PresetSwitchRow(
            voxString("Process before delivery"),
            voxString("Transform captured text locally after transcription and before Markdown rendering."),
            processingEnabled,
            setProcessingEnabled,
        )
        if (processingEnabled) {
            SignalRowDivider()
            PresetBlock {
                PresetChoiceRow(
                    title = voxString("Scope"),
                    options = listOf(
                        CaptureProcessingScope.BOTH.name to voxString("Voice & Text"),
                        CaptureProcessingScope.VOICE_ONLY.name to voxString("Voice Only"),
                        CaptureProcessingScope.TEXT_ONLY.name to voxString("Text Only"),
                    ),
                    selected = processingScope.name,
                    onSelected = { setProcessingScope(CaptureProcessingScope.valueOf(it)) },
                )
            }
            SignalRowDivider()
            PresetBlock {
                PresetChoiceRow(
                    title = voxString("Mode"),
                    options = listOf(
                        CaptureProcessingMode.NONE.name to voxString("None"),
                        CaptureProcessingMode.CLEAN.name to voxString("Clean"),
                        CaptureProcessingMode.TODO_LIST.name to voxString("To-do List"),
                        CaptureProcessingMode.MEETING_NOTES.name to voxString("Meeting Notes"),
                        CaptureProcessingMode.CUSTOM.name to voxString("Custom"),
                    ),
                    selected = processingMode.name,
                    onSelected = { setProcessingMode(CaptureProcessingMode.valueOf(it)) },
                )
                if (processingMode == CaptureProcessingMode.CUSTOM) {
                    InstructionModelCard()
                    OutlinedTextField(
                        value = customInstruction,
                        onValueChange = { setCustomInstruction(it.take(4_096)) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(voxString("Custom instruction")) },
                        minLines = 3,
                        shape = SignalFieldShape,
                        colors = signalTextFieldColors(),
                    )
                }
            }
            SignalRowDivider()
            PresetSwitchRow(
                voxString("Generate image alt text"),
                voxString("Describe attached images locally when a compatible model is installed."),
                generateImageAltText,
                setGenerateImageAltText,
            )
        }
    }
}

@Composable
internal fun CapturePresetLocationEditor(
    locationEnabled: Boolean,
    locationPrecision: CaptureLocationPrecision,
    locationUnavailableBehavior: CaptureLocationUnavailableBehavior,
    locationMetadataEnabled: Boolean,
    locationOutputMode: CaptureLocationOutputMode,
    locationStructuredFields: List<CaptureLocationStructuredField>,
    locationCollectionKey: String,
    locationAdvancedTemplate: String,
    locationLabelLookupClass: CaptureLocationLabelLookupClass,
    locationLabelConsentVersion: Int?,
    setLocationEnabled: (Boolean) -> Unit,
    setLocationPrecision: (CaptureLocationPrecision) -> Unit,
    setLocationUnavailableBehavior: (CaptureLocationUnavailableBehavior) -> Unit,
    setLocationMetadataEnabled: (Boolean) -> Unit,
    setLocationOutputMode: (CaptureLocationOutputMode) -> Unit,
    setLocationStructuredFields: (List<CaptureLocationStructuredField>) -> Unit,
    setLocationCollectionKey: (String) -> Unit,
    setLocationAdvancedTemplate: (String) -> Unit,
    setLocationLabelConsent: (Boolean) -> Unit,
) {
    val labelsNeeded = CapturePresetLocationPolicy(
        isEnabled = locationEnabled,
        precision = locationPrecision,
        unavailableBehavior = locationUnavailableBehavior,
        metadataOutputEnabled = locationMetadataEnabled,
        outputMode = locationOutputMode,
        structuredFields = locationStructuredFields,
        collectionKey = locationCollectionKey,
        advancedTemplate = locationAdvancedTemplate,
    ).requiresLabels
    val keyPattern = Regex("^[A-Za-z_][A-Za-z0-9_-]{0,63}$")
    SignalGroup(voxString("Location")) {
        PresetSwitchRow(
            voxString("Current location"),
            voxString("Request one location at send or recording stop; never track in the background."),
            locationEnabled,
            setLocationEnabled,
        )
        if (locationEnabled) {
            SignalRowDivider()
            PresetBlock {
                PresetChoiceRow(
                    title = voxString("Precision"),
                    options = listOf(
                        CaptureLocationPrecision.EXACT.name to voxString("Exact"),
                        CaptureLocationPrecision.CITY.name to voxString("City"),
                    ),
                    selected = locationPrecision.name,
                    onSelected = { setLocationPrecision(CaptureLocationPrecision.valueOf(it)) },
                )
            }
            SignalRowDivider()
            PresetBlock {
                PresetChoiceRow(
                    title = voxString("If unavailable"),
                    options = listOf(
                        CaptureLocationUnavailableBehavior.ASK.name to voxString("Ask Every Time"),
                        CaptureLocationUnavailableBehavior.SEND_WITHOUT_LOCATION.name to voxString("Send Without"),
                        CaptureLocationUnavailableBehavior.CANCEL.name to voxString("Cancel Capture"),
                    ),
                    selected = locationUnavailableBehavior.name,
                    onSelected = { setLocationUnavailableBehavior(CaptureLocationUnavailableBehavior.valueOf(it)) },
                )
            }
            SignalRowDivider()
            PresetSwitchRow(
                voxString("Write location metadata"),
                voxString("Add the frozen result to note frontmatter or inline entry fields."),
                locationMetadataEnabled,
                setLocationMetadataEnabled,
            )
            if (locationMetadataEnabled) {
                SignalRowDivider()
                PresetBlock {
                    PresetChoiceRow(
                        title = voxString("Output"),
                        options = listOf(
                            CaptureLocationOutputMode.STRUCTURED_FIELDS.name to voxString("Structured Fields"),
                            CaptureLocationOutputMode.ADVANCED_YAML.name to voxString("Advanced YAML"),
                        ),
                        selected = locationOutputMode.name,
                        onSelected = { setLocationOutputMode(CaptureLocationOutputMode.valueOf(it)) },
                    )
                    OutlinedTextField(
                        value = locationCollectionKey,
                        onValueChange = { setLocationCollectionKey(it.take(64)) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(voxString("Collection key")) },
                        isError = !locationCollectionKey.matches(keyPattern),
                        textStyle = presetMonoFieldStyle(),
                        singleLine = true,
                        shape = SignalFieldShape,
                        colors = signalTextFieldColors(),
                    )
                    if (locationOutputMode == CaptureLocationOutputMode.ADVANCED_YAML) {
                        OutlinedTextField(
                            value = locationAdvancedTemplate,
                            onValueChange = { setLocationAdvancedTemplate(it.take(8_192)) },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(voxString("Advanced YAML template")) },
                            placeholder = { Text(voxString("lat: {latitude}\nlon: {longitude}"), style = SignalType.mono) },
                            textStyle = presetMonoFieldStyle(),
                            minLines = 4,
                            shape = SignalFieldShape,
                            colors = signalTextFieldColors(),
                        )
                    } else {
                        PresetHint(voxString("Capture ID is always written as id. Choose other fields and rename their output keys below."))
                    }
                }
                if (locationOutputMode != CaptureLocationOutputMode.ADVANCED_YAML) {
                    CaptureLocationField.entries.filterNot { it == CaptureLocationField.ID }.forEach { field ->
                        val selected = locationStructuredFields.firstOrNull { it.field == field }
                        SignalRowDivider()
                        PresetSwitchRow(
                            captureLocationFieldUiText(field).localized(),
                            voxFormat("Write %@ when the frozen snapshot contains it.", field.wireName),
                            selected != null,
                        ) { enabled ->
                            setLocationStructuredFields(
                                if (enabled) {
                                    locationStructuredFields + CaptureLocationStructuredField(field)
                                } else {
                                    locationStructuredFields.filterNot { it.field == field }
                                },
                            )
                        }
                        if (selected != null) {
                            PresetBlock(top = 0.dp) {
                                OutlinedTextField(
                                    value = selected.outputKey,
                                    onValueChange = { outputKey ->
                                        setLocationStructuredFields(
                                            locationStructuredFields.map { item ->
                                                if (item.field == field) item.copy(outputKey = outputKey.take(64)) else item
                                            },
                                        )
                                    },
                                    modifier = Modifier.fillMaxWidth(),
                                    label = { Text(voxFormat("%@: %@", captureLocationFieldUiText(field).localized(), voxString("Output key"))) },
                                    isError = !selected.outputKey.matches(keyPattern) ||
                                        selected.outputKey == "id",
                                    textStyle = presetMonoFieldStyle(),
                                    singleLine = true,
                                    shape = SignalFieldShape,
                                    colors = signalTextFieldColors(),
                                )
                            }
                        }
                    }
                }
                if (labelsNeeded) {
                    SignalRowDivider()
                    PresetSwitchRow(
                        voxString("Use place labels"),
                        voxString("Android's system geocoder may contact a remote service and transmit the privacy-adjusted coordinates. This consent applies only to this route."),
                        locationLabelLookupClass == CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK &&
                            locationLabelConsentVersion == CURRENT_LOCATION_LABEL_CONSENT_VERSION,
                        setLocationLabelConsent,
                    )
                    PresetBlock(top = 0.dp) {
                        PresetHint(voxString("If you leave this off, capture still writes coordinates and map links; place, city, region, and country fields are omitted."))
                    }
                }
            }
        }
    }
}

internal fun captureLocationFieldUiText(field: CaptureLocationField): VoxUiText = when (field) {
    CaptureLocationField.COORDINATES -> voxUiText("Coordinates")
    CaptureLocationField.LATITUDE -> voxUiText("Latitude")
    CaptureLocationField.LONGITUDE -> voxUiText("Longitude")
    CaptureLocationField.PLACE -> voxUiText("Place")
    CaptureLocationField.CITY -> voxUiText("City")
    CaptureLocationField.REGION -> voxUiText("Region")
    CaptureLocationField.COUNTRY -> voxUiText("Country")
    CaptureLocationField.APPLE_MAPS_URL -> voxUiText("Apple Maps URL")
    CaptureLocationField.GOOGLE_MAPS_URL -> voxUiText("Google Maps URL")
    CaptureLocationField.OPEN_STREET_MAP_URL -> voxUiText("OpenStreetMap URL")
    CaptureLocationField.GEO_URI -> voxUiText("geo URI")
    CaptureLocationField.ACCURACY -> voxUiText("Accuracy")
    CaptureLocationField.TIMESTAMP -> voxUiText("Timestamp")
    CaptureLocationField.SOURCE -> voxUiText("Source")
    CaptureLocationField.ID -> voxUiText("Capture ID")
}

internal fun structuredLocationFieldsAreValid(fields: List<CaptureLocationStructuredField>): Boolean {
    if (fields.size > CaptureLocationField.entries.size) return false
    val fieldIDs = fields.map(CaptureLocationStructuredField::field)
    val outputKeys = fields.map(CaptureLocationStructuredField::outputKey)
    return fieldIDs.distinct().size == fieldIDs.size &&
        outputKeys.distinct().size == outputKeys.size &&
        fields.all { selection ->
            selection.outputKey.matches(Regex("^[A-Za-z_][A-Za-z0-9_-]{0,63}$")) &&
                if (selection.field == CaptureLocationField.ID) selection.outputKey == "id" else selection.outputKey != "id"
        }
}

@Composable
internal fun PresetSectionTitle(title: String) {
    SignalSectionLabel(title, Modifier.padding(start = 4.dp, top = 14.dp))
}

/** Padded content block inside a Signal group card (fields, choice rows, hints). */
@Composable
private fun PresetBlock(
    modifier: Modifier = Modifier,
    top: Dp = 12.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, top = top, bottom = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        content = content,
    )
}

@Composable
private fun PresetHint(text: String) {
    Text(text, style = SignalType.caption, color = Signal.colors.muted)
}

@Composable
private fun presetMonoFieldStyle(): TextStyle = SignalType.mono.copy(fontSize = 14.sp, color = Signal.colors.text)

@Composable
private fun presetSegmentedColors() = Signal.colors.let { c ->
    SegmentedButtonDefaults.colors(
        activeContainerColor = c.text,
        activeContentColor = c.bg,
        activeBorderColor = c.text,
        inactiveContainerColor = c.card,
        inactiveContentColor = c.text,
        inactiveBorderColor = c.border,
    )
}

/** Capsule choice chip: white bordered when idle, ink-filled when selected. */
@Composable
private fun PresetChoiceChip(
    selected: Boolean,
    label: String,
    onClick: () -> Unit,
    leadingIcon: ImageVector? = null,
) {
    val c = Signal.colors
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        leadingIcon = leadingIcon?.let { icon -> { Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp)) } },
        shape = RoundedCornerShape(8.dp),
        colors = FilterChipDefaults.filterChipColors(
            containerColor = androidx.compose.ui.graphics.Color.Transparent,
            labelColor = c.muted,
            iconColor = c.muted,
            selectedContainerColor = c.secondarySoft,
            selectedLabelColor = c.secondaryText,
            selectedLeadingIconColor = c.secondaryText,
        ),
        border = FilterChipDefaults.filterChipBorder(
            enabled = true,
            selected = selected,
            borderColor = c.border,
            selectedBorderColor = c.secondarySoft,
            borderWidth = 1.dp,
            selectedBorderWidth = 1.dp,
        ),
        modifier = Modifier.heightIn(min = 36.dp),
    )
}

/** Toggle row inside a Signal group card: title, muted explanation and an indigo switch. */
@Composable
internal fun PresetSwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val c = Signal.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SignalType.rowTitle, color = c.text)
            Text(subtitle, style = SignalType.caption, color = c.muted)
        }
        SignalSwitch(checked = checked, onCheckedChange = null)
    }
}

@Composable
internal fun PresetChoiceRow(
    title: String,
    options: List<Pair<String, String>>,
    selected: String,
    onSelected: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = SignalType.rowTitle, color = Signal.colors.text)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(options, key = { it.second }) { (value, label) ->
                PresetChoiceChip(
                    selected = value == selected,
                    label = label,
                    onClick = { onSelected(value) },
                )
            }
        }
    }
}

internal fun parseMetadataFields(value: String): List<CaptureMetadataField>? {
    val lines = value.lines().map(String::trim).filter(String::isNotEmpty)
    if (lines.size > 16) return null
    val fields = lines.map { line ->
        val split = line.indexOf('=').takeIf { it > 0 } ?: line.indexOf(':')
        if (split !in 1 until line.length) return null
        val name = line.substring(0, split).trim()
        val fieldValue = line.substring(split + 1)
        if (!name.matches(Regex("^[A-Za-z0-9_-]{1,64}$")) || fieldValue.length > 512) return null
        CaptureMetadataField(name, fieldValue)
    }
    return fields.takeIf { items -> items.map { it.name.lowercase() }.distinct().size == items.size }
}

internal val PRESET_SYMBOLS = listOf("description", "mic", "checklist", "lightbulb", "work", "favorite")

internal fun presetIcon(symbol: String?): ImageVector = when (symbol) {
    "mic" -> Icons.Outlined.MicNone
    "checklist" -> Icons.Outlined.CheckBox
    "lightbulb" -> Icons.Outlined.Lightbulb
    "work" -> Icons.Outlined.WorkOutline
    "favorite" -> Icons.Outlined.FavoriteBorder
    else -> Icons.Outlined.Description
}

internal fun presetSymbolLabel(symbol: String): VoxUiText = when (symbol) {
    "mic" -> voxUiText("Voice")
    "checklist" -> voxUiText("Checklist")
    "lightbulb" -> voxUiText("Idea")
    "work" -> voxUiText("Work")
    "favorite" -> voxUiText("Favorite")
    else -> voxUiText("Document")
}

/** Decorative arrow between route step chips; hidden from accessibility. */
private const val ROUTE_STEP_ARROW = "→"
