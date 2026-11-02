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
import md.vox.android.capturedomain.CaptureURLDeliverySettings
import md.vox.android.capturedomain.normalizedTranscriptProperty
import md.vox.android.capturedomain.CaptureHeadingPosition
import md.vox.android.capturedomain.CaptureRailSide
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureAttachment
import md.vox.android.ui.GeistMonoFontFamily
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
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import java.time.ZoneId
import md.vox.android.capturedomain.CaptureTimestampFormat
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalActionRow
import md.vox.android.ui.SignalBadge
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalGroup
import md.vox.android.ui.SignalIconTile
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalRowDivider
import md.vox.android.ui.SignalSectionLabel
import md.vox.android.ui.SignalSwitch
import md.vox.android.ui.SignalToggleRow
import md.vox.android.ui.SignalType
import md.vox.android.ui.SignalValueRow
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

@Composable
internal fun SettingsScreen(
    destination: CaptureDestination,
    navigateBack: () -> Unit,
    chooseFolder: () -> Unit,
    openPresets: () -> Unit,
    openCaptureBar: () -> Unit,
    openStats: () -> Unit,
    openModels: () -> Unit,
    openRecordingQueue: () -> Unit,
    openAppLanguage: () -> Unit,
    openDebugLog: () -> Unit,
    openUpgrade: () -> Unit,
    billingState: BillingUiState,
) {
    val context = LocalContext.current
    val speechModels by remember(context) { SpeechModelManager.get(context) }.state.collectAsStateWithLifecycle()
    val keyboardPreferences = remember(context) { context.getSharedPreferences("vox-settings", android.content.Context.MODE_PRIVATE) }
    var keyboardHaptics by rememberSaveable {
        mutableStateOf(keyboardPreferences.getBoolean("keyboard-haptics", true))
    }
    Scaffold(
        containerColor = Signal.colors.bg,
        topBar = { VoxTopBar(VoxUiText(stringResource(R.string.settings_title)), navigateBack) },
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
            SettingsSignalGroup(voxUiText("Unlimited")) {
                SettingsNavigationRow(
                    title = if (billingState.hasUnlimitedAccess) voxUiText("Vox.md Unlimited") else voxUiText("Get Vox.md Unlimited"),
                    subtitle = if (billingState.hasUnlimitedAccess) {
                        voxUiText("Unlimited is unlocked on this device.")
                    } else {
                        voxUiText("Unlock unlimited local Capture and private, on-device transcription. Pay once with no subscription.")
                    },
                    value = billingState.formattedPrice,
                    icon = if (billingState.hasUnlimitedAccess) Icons.Outlined.CheckCircle else Icons.Outlined.LockOpen,
                    iconTone = if (billingState.hasUnlimitedAccess) SettingsIconTone.SUCCESS else SettingsIconTone.ACCENT,
                    onClick = openUpgrade,
                )
            }
            SettingsSignalGroup(voxUiText("Capture")) {
                SettingsSignalNavRow(
                    title = voxString("Capture Destination"),
                    subtitle = destination.displayName,
                    monoSubtitle = true,
                    subtitleMaxLines = 2,
                    icon = Icons.Outlined.FolderOpen,
                    onClick = chooseFolder,
                )
            }
            SettingsSignalGroup(voxUiText("Activity")) {
                SettingsNavigationRow(
                    title = voxUiText("Stats"),
                    subtitle = voxUiText("Recordings, recording time, and Capture activity"),
                    icon = Icons.Outlined.BarChart,
                    onClick = openStats,
                )
                SignalRowDivider()
                Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 4.dp), contentAlignment = Alignment.CenterStart) {
                    URLDeliveryRecoveryControl()
                }
            }
            SettingsSignalGroup(voxUiText("Recordings")) {
                SettingsNavigationRow(
                    title = voxUiText("Recordings"),
                    subtitle = voxUiText("Recover, export, and manage durable audio"),
                    icon = Icons.Outlined.GraphicEq,
                    onClick = openRecordingQueue,
                )
            }
            SettingsSignalGroup(voxUiText("Customization")) {
                SettingsNavigationRow(
                    title = voxUiText("Models"),
                    subtitle = voxUiText("Transcription engines, model downloads, and language"),
                    icon = Icons.Outlined.Memory,
                    onClick = openModels,
                )
                SignalRowDivider()
                SettingsNavigationRow(
                    title = voxUiText("Capture Presets"),
                    subtitle = voxUiText("Processing, formatting, metadata, and destinations"),
                    icon = Icons.Outlined.Tune,
                    onClick = openPresets,
                )
                SignalRowDivider()
                SettingsNavigationRow(
                    title = voxUiText("Capture Bar"),
                    subtitle = voxUiText("Choose, reorder, and hide quick actions"),
                    icon = Icons.Outlined.Dashboard,
                    onClick = openCaptureBar,
                )
                SignalRowDivider()
                SettingsNavigationRow(
                    title = VoxUiText(stringResource(R.string.app_language_title)),
                    subtitle = VoxUiText(stringResource(R.string.app_language_choose)),
                    icon = Icons.Outlined.Language,
                    value = AppLanguage.current().let { language ->
                        if (language == AppLanguage.SYSTEM) stringResource(R.string.system_language_short) else language.nativeDisplayName
                    },
                    onClick = openAppLanguage,
                )
            }
            SettingsSignalGroup(voxUiText("Keyboard")) {
                SettingsActionRow(voxUiText("Set Up Vox.md Keyboard")) { openInputMethodSettings(context) }
                SignalRowDivider()
                SignalToggleRow(
                    title = voxString("Haptic Feedback"),
                    description = voxString("Vibrate on key press"),
                    checked = keyboardHaptics,
                    onCheckedChange = { enabled ->
                        keyboardHaptics = enabled
                        keyboardPreferences.edit().putBoolean("keyboard-haptics", enabled).apply()
                    },
                )
            }
            SettingsSignalGroup(voxUiText("About")) {
                SettingsValueRow(
                    voxUiText("Default transcription"),
                    speechModels.selectedReadyModel?.descriptor?.let {
                        if (speechModels.selectionMode == SpeechModelSelectionMode.AUTOMATIC) {
                            voxFormat("%@ · %@ · local %@", voxString("Automatic"), it.displayName, it.engine.displayName)
                        } else {
                            voxFormat("%@ · local %@", it.displayName, it.engine.displayName)
                        }
                    }
                        ?: voxString("Android Speech when explicitly on-device"),
                )
                SignalRowDivider()
                SettingsValueRow(voxUiText("Audio capture"), voxString("On-device"))
                SignalRowDivider()
                SettingsValueRow(voxUiText("Processing"), voxString("On-device"))
                SignalRowDivider()
                SettingsValueRow(voxUiText("Privacy"), voxString("Local processing; optional URL delivery"))
                SignalRowDivider()
                SettingsValueRow(voxUiText("Version"), appVersionString(context))
            }
            SettingsPrivacyFooter(
                voxString("Capture contents stay on this device until Vox.md writes them to your selected folder or sends text to an endpoint you explicitly enabled. Audio and attachments are not uploaded. Android backup is disabled for content-bearing storage."),
            )
            SettingsSignalGroup(voxUiText("Feedback")) {
                SettingsActionRow(voxUiText("Join Our Discord")) { openDiscord(context) }
                SignalRowDivider()
                SettingsActionRow(voxUiText("Send Feedback")) { sendFeedback(context) }
            }
            SettingsSignalGroup(voxUiText("Debug")) {
                SettingsNavigationRow(
                    title = voxUiText("View Debug Log"),
                    subtitle = voxUiText("Content-free operational events stored only on this device"),
                    onClick = openDebugLog,
                )
            }
        }
    }
}

@Composable
internal fun StatsScreen(stats: ActivityStats, navigateBack: () -> Unit) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.ENGLISH
    val c = Signal.colors
    Scaffold(
        containerColor = c.bg,
        topBar = {
            VoxTopBar(
                voxUiText("Stats"),
                navigateBack,
                subtitle = voxUiText("Lifetime on-device activity calculated from a content-free local ledger."),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SignalMetrics.PageGutter)
                .padding(top = 4.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatCard(voxUiText("Recordings"), stats.recordingCount.toString(), Modifier.weight(1f).fillMaxHeight(), Icons.Outlined.GraphicEq)
                StatCard(voxUiText("Captures"), stats.captureCount.toString(), Modifier.weight(1f).fillMaxHeight(), Icons.Outlined.Description)
            }
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatCard(voxUiText("Recorded duration"), formatActivityDuration(stats.recordedDurationMillis), Modifier.weight(1f).fillMaxHeight(), Icons.Outlined.Schedule)
                StatCard(voxUiText("Attachments"), stats.attachmentCount.toString(), Modifier.weight(1f).fillMaxHeight(), Icons.Outlined.AttachFile)
            }
            SettingsSignalGroup(voxUiText("Last 7 Days")) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (stats.lastSevenDays.isEmpty()) {
                        Text(voxString("No activity yet"), style = MaterialTheme.typography.bodyMedium, color = c.muted)
                    } else {
                        val maximum = stats.lastSevenDays.maxOf { it.captureCount + it.recordingCount }.coerceAtLeast(1)
                        stats.lastSevenDays.forEach { day ->
                            val localDate = java.time.LocalDate.ofEpochDay(day.epochDay)
                            val dayName = localDate.dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, locale)
                            val abbreviatedDayName = localDate.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, locale)
                            val dayDescription = voxFormat(
                                "%@: %@",
                                dayName,
                                voxFormat("%@ · %@", voxFormat("%lld recordings", day.recordingCount), voxFormat("%lld captures", day.captureCount)),
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth().semantics {
                                    contentDescription = dayDescription
                                },
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Text(
                                    abbreviatedDayName,
                                    modifier = Modifier.width(40.dp),
                                    style = SignalType.monoCaption,
                                    color = c.muted,
                                )
                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    StatsBar(day.recordingCount.toFloat() / maximum, c.accent)
                                    StatsBar(day.captureCount.toFloat() / maximum, c.faint)
                                }
                                Text(
                                    voxFormat("%@ · %@", voxFormat("%lld recordings", day.recordingCount), voxFormat("%lld captures", day.captureCount)),
                                    modifier = Modifier.widthIn(min = 48.dp, max = 140.dp),
                                    style = SignalType.monoCaption,
                                    color = c.muted,
                                )
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.padding(top = 2.dp)) {
                        Text(voxString("● Recordings"), color = c.accentText, style = SignalType.caption)
                        Text(voxString("● Captures"), color = c.muted, style = SignalType.caption)
                    }
                }
            }
            SettingsSignalGroup(voxUiText("Capture Sources")) {
                if (stats.captureSources.isEmpty()) {
                    Text(
                        voxString("No delivered captures yet"),
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = c.muted,
                    )
                }
                stats.captureSources.entries.forEachIndexed { index, (source, count) ->
                    if (index > 0) SignalRowDivider()
                    Row(
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(statsSourceUiText(source).localized(), modifier = Modifier.weight(1f), style = SignalType.rowTitle, color = c.text)
                        Text(count.toString(), style = SignalType.mono.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium), color = c.muted)
                    }
                }
            }
            SettingsPrivacyFooter(voxString("No captured content, filenames, or destinations are stored with stats."))
        }
    }
}

/** Rounded well track with a filled portion, used by the Stats week chart. */
@Composable
private fun StatsBar(fraction: Float, color: Color) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(6.dp)
            .clip(CircleShape)
            .background(Signal.colors.well),
    ) {
        val clamped = fraction.coerceIn(0f, 1f)
        if (clamped > 0f) {
            Box(Modifier.fillMaxWidth(clamped).fillMaxHeight().clip(CircleShape).background(color))
        }
    }
}

internal fun formatActivityDuration(milliseconds: Long): String {
    val minutes = milliseconds.coerceAtLeast(0) / 60_000
    return if (minutes < 60) "${minutes}m" else "${minutes / 60}h ${minutes % 60}m"
}

internal fun statsSourceUiText(source: String): VoxUiText = captureSourceUiText(source)

@Composable
internal fun StatCard(title: VoxUiText, value: String, modifier: Modifier = Modifier, icon: ImageVector? = null) {
    val c = Signal.colors
    SignalCard(modifier = modifier, padding = PaddingValues(16.dp)) {
        if (icon != null) {
            SignalIconTile(icon, size = 30.dp)
            Spacer(Modifier.height(14.dp))
        }
        Text(
            value,
            style = MaterialTheme.typography.headlineMedium.copy(fontSize = 28.sp, lineHeight = 32.sp),
            color = c.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(2.dp))
        Text(title.localized(), style = SignalType.caption, color = c.muted)
    }
}

@Composable
internal fun CaptureBarSettingsScreen(
    configuration: CaptureBarConfiguration,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    setVisible: (CaptureBarAction, Boolean) -> Unit,
    move: (CaptureBarAction, Int) -> Unit,
    setTwentyFourHour: (Boolean) -> Unit,
    setRailSide: (CaptureRailSide) -> Unit = {},
    setVoiceConfirmation: (Boolean) -> Unit,
    setVoiceRecordingResult: (VoiceRecordingResult) -> Unit = {},
    reset: () -> Unit,
) {
    val c = Signal.colors
    Scaffold(
        containerColor = c.bg,
        topBar = { VoxTopBar(voxUiText("Capture Bar"), navigateBack) },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(start = SignalMetrics.PageGutter, end = SignalMetrics.PageGutter, bottom = 32.dp),
        ) {
            item {
                Text(voxString("Choose which actions appear below Capture. Move actions into the order that works for you."),
                    modifier = Modifier.padding(start = 4.dp, end = 4.dp, top = 2.dp, bottom = 14.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = c.muted,
                )
            }
            items(configuration.orderedActions, key = CaptureBarAction::persistedName) { action ->
                val index = configuration.orderedActions.indexOf(action)
                val actionLabel = captureBarActionUiText(action).localized()
                val showDescription = voxFormat("%@: %@", voxString("Show"), actionLabel)
                val isVisible = action !in configuration.hiddenActions
                Column(
                    Modifier
                        .fillMaxWidth()
                        .captureBarCardSegment(
                            first = index == 0,
                            last = index == configuration.orderedActions.lastIndex,
                            card = c.card,
                            border = c.border,
                        ),
                ) {
                    if (index > 0) SignalRowDivider()
                    Row(
                        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = 14.dp, end = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            actionLabel,
                            modifier = Modifier.weight(1f).padding(vertical = 12.dp),
                            style = SignalType.rowTitle,
                            color = if (isVisible) c.text else c.faint,
                        )
                        val arrowColors = IconButtonDefaults.iconButtonColors(contentColor = c.text, disabledContentColor = c.borderHi)
                        IconButton(onClick = { move(action, -1) }, enabled = !isBusy && index > 0, colors = arrowColors) {
                            Icon(Icons.Outlined.KeyboardArrowUp, contentDescription = voxFormat("%@: %@", voxString("Move Up"), actionLabel))
                        }
                        IconButton(
                            onClick = { move(action, 1) },
                            enabled = !isBusy && index < configuration.orderedActions.lastIndex,
                            colors = arrowColors,
                        ) {
                            Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = voxFormat("%@: %@", voxString("Move Down"), actionLabel))
                        }
                        Spacer(Modifier.width(6.dp))
                        SignalSwitch(
                            checked = isVisible,
                            onCheckedChange = { setVisible(action, it) },
                            enabled = !isBusy,
                            modifier = Modifier.semantics {
                                contentDescription = showDescription
                            },
                        )
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                    CaptureBarAppearanceGroups(configuration, isBusy, setTwentyFourHour, setRailSide)
                    SettingsSignalGroup(title = null, modifier = Modifier.padding(top = 14.dp)) {
                        CaptureBarSwitchRow(
                            title = voxString("Review Before Adding"),
                            description = voxString("Off adds a finished voice transcript to the draft automatically. Turn this on to review it first."),
                            checked = configuration.confirmsVoiceNotesBeforeAdding,
                            enabled = !isBusy,
                            onCheckedChange = setVoiceConfirmation,
                        )
                    }
                    SettingsSignalGroup(voxUiText("Recording Result")) {
                        CaptureBarRadioRow(
                            title = voxString("Add to Draft"),
                            description = voxString("A finished voice transcript lands in the composer, ready to review before sending."),
                            selected = configuration.voiceRecordingResult == VoiceRecordingResult.ADD_TO_DRAFT,
                            enabled = !isBusy,
                            onSelect = { setVoiceRecordingResult(VoiceRecordingResult.ADD_TO_DRAFT) },
                        )
                        SignalRowDivider()
                        CaptureBarRadioRow(
                            title = voxString("Send Immediately"),
                            description = voxString("A finished voice transcript is sent straight to the active preset without stopping in the composer."),
                            selected = configuration.voiceRecordingResult == VoiceRecordingResult.SEND_IMMEDIATELY,
                            enabled = !isBusy,
                            onSelect = { setVoiceRecordingResult(VoiceRecordingResult.SEND_IMMEDIATELY) },
                        )
                    }
                    SignalButton(
                        text = voxString("Reset Capture Bar"),
                        onClick = reset,
                        enabled = !isBusy,
                        variant = SignalButtonVariant.SECONDARY,
                        size = SignalButtonSize.MEDIUM,
                        fillWidth = true,
                        modifier = Modifier.padding(top = 16.dp),
                    )
                }
            }
        }
    }
}

/** Timestamp format and pinned preset rail choices as Signal radio groups. */
@Composable
private fun CaptureBarAppearanceGroups(
    configuration: CaptureBarConfiguration,
    busy: Boolean,
    setTwentyFourHour: (Boolean) -> Unit,
    setRailSide: (CaptureRailSide) -> Unit,
) {
    SettingsSignalGroup(voxUiText("Timestamp Format")) {
        CaptureTimestampFormat.entries.forEachIndexed { index, format ->
            if (index > 0) SignalRowDivider()
            CaptureBarRadioRow(
                title = if (format == CaptureTimestampFormat.TWELVE_HOUR) voxString("12-hour") else voxString("24-hour"),
                description = format.render(1700000000000, ZoneId.of("UTC")),
                monoDescription = true,
                selected = configuration.timestampFormat == format,
                enabled = !busy,
                radioTag = "timestamp-${format.wireName}",
                onSelect = { setTwentyFourHour(format == CaptureTimestampFormat.TWENTY_FOUR_HOUR) },
            )
        }
    }
    SettingsSignalGroup(voxUiText("Pinned Preset Rail")) {
        CaptureRailSide.entries.forEachIndexed { index, side ->
            if (index > 0) SignalRowDivider()
            CaptureBarRadioRow(
                title = if (side == CaptureRailSide.LEFT) voxString("Left edge") else voxString("Right edge"),
                description = null,
                selected = configuration.railSide == side,
                enabled = !busy,
                radioTag = "rail-${side.name}",
                onSelect = { setRailSide(side) },
            )
        }
    }
}

@Composable
private fun CaptureBarRadioRow(
    title: String,
    description: String?,
    selected: Boolean,
    enabled: Boolean,
    onSelect: () -> Unit,
    monoDescription: Boolean = false,
    radioTag: String? = null,
) {
    val c = Signal.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .selectable(selected = selected, enabled = enabled, role = Role.RadioButton, onClick = onSelect)
            .padding(start = 6.dp, end = 14.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        RadioButton(
            selected = selected,
            onClick = null,
            enabled = enabled,
            colors = RadioButtonDefaults.colors(
                selectedColor = c.accent,
                unselectedColor = c.borderHi,
                disabledSelectedColor = c.faint,
                disabledUnselectedColor = c.border,
            ),
            modifier = Modifier.size(40.dp).then(if (radioTag != null) Modifier.testTag(radioTag) else Modifier),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SignalType.rowTitle, color = if (enabled) c.text else c.faint)
            if (description != null) {
                Text(description, style = if (monoDescription) SignalType.monoCaption else SignalType.caption, color = c.muted)
            }
        }
    }
}

@Composable
private fun CaptureBarSwitchRow(
    title: String,
    description: String,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val c = Signal.colors
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SignalType.rowTitle, color = if (enabled) c.text else c.faint)
            Text(description, style = SignalType.caption, color = c.muted)
        }
        SignalSwitch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled,
            modifier = Modifier.semantics { contentDescription = title },
        )
    }
}

/**
 * One row of a grouped card that is split across lazy items: rounds and borders only
 * the outer corners so consecutive items read as a single hairline card.
 */
private fun Modifier.captureBarCardSegment(first: Boolean, last: Boolean, card: Color, border: Color): Modifier {
    val radius = SignalMetrics.GroupRadius
    val shape = RoundedCornerShape(
        topStart = if (first) radius else 0.dp,
        topEnd = if (first) radius else 0.dp,
        bottomStart = if (last) radius else 0.dp,
        bottomEnd = if (last) radius else 0.dp,
    )
    return this
        .clip(shape)
        .background(card)
        .drawBehind {
            val stroke = 1.dp.toPx()
            val r = radius.toPx()
            val top = if (first) stroke / 2 else -r - stroke
            val bottom = if (last) size.height - stroke / 2 else size.height + r + stroke
            drawRoundRect(
                color = border,
                topLeft = Offset(stroke / 2, top),
                size = Size(size.width - stroke, bottom - top),
                cornerRadius = CornerRadius(r - stroke / 2),
                style = Stroke(stroke),
            )
        }
}

internal fun captureBarActionUiText(action: CaptureBarAction): VoxUiText = when (action) {
    CaptureBarAction.ADD_MEDIA -> voxUiText("Add Media")
    CaptureBarAction.ADD_FILES -> voxUiText("Add Files")
    CaptureBarAction.SCAN_DOCUMENT -> voxUiText("Scan Document")
    CaptureBarAction.EXTRACT_TEXT -> voxUiText("Extract Text")
    CaptureBarAction.UNDO -> voxUiText("Undo")
    CaptureBarAction.FORMAT_MARKDOWN -> voxUiText("Format Markdown")
    CaptureBarAction.MARKDOWN_LINK -> voxUiText("Markdown Link")
    CaptureBarAction.DUE_DATE -> voxUiText("Set Due Date")
    CaptureBarAction.CHECKLIST -> voxUiText("Checklist")
    CaptureBarAction.BULLET_LIST -> voxUiText("Bullet List")
    CaptureBarAction.PASTE -> voxUiText("Paste")
    CaptureBarAction.INTERNAL_LINK -> voxUiText("Internal Link")
    CaptureBarAction.SKETCH -> voxUiText("Sketch")
    CaptureBarAction.CURRENT_LOCATION -> voxUiText("Current Location")
    CaptureBarAction.TIMESTAMP -> voxUiText("Insert Timestamp")
    CaptureBarAction.DATE -> voxUiText("Insert Date")
    CaptureBarAction.TEXT_CASE -> voxUiText("Change Text Case")
}

// region Signal settings rows

internal enum class SettingsIconTone { NEUTRAL, ACCENT, SUCCESS }

/** Mono uppercase label above a white, hairline-bordered 16dp card (iOS `settingsGroup`). */
@Composable
private fun SettingsSignalGroup(
    title: VoxUiText?,
    modifier: Modifier = Modifier,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    SignalGroup(title = title?.localized(), modifier = modifier, content = content)
}

/** Lock-icon privacy note under a group, as at the foot of iOS Settings. */
@Composable
private fun SettingsPrivacyFooter(text: String) {
    val c = Signal.colors
    Row(
        modifier = Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp, top = 6.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Outlined.Lock, contentDescription = null, tint = c.muted, modifier = Modifier.padding(top = 2.dp).size(14.dp))
        Text(text, style = SignalType.caption, color = c.muted)
    }
}

/** Title + subtitle row with optional leading tile, trailing value and a faint chevron. */
@Composable
private fun SettingsSignalNavRow(
    title: String,
    subtitle: String?,
    onClick: () -> Unit,
    value: String? = null,
    icon: ImageVector? = null,
    iconTone: SettingsIconTone = SettingsIconTone.NEUTRAL,
    monoSubtitle: Boolean = true,
    subtitleMaxLines: Int = Int.MAX_VALUE,
) {
    val c = Signal.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (icon != null) {
            when (iconTone) {
                SettingsIconTone.NEUTRAL -> SignalIconTile(icon)
                SettingsIconTone.ACCENT -> SignalIconTile(icon, primary = true)
                SettingsIconTone.SUCCESS -> SignalIconTile(icon, fill = c.successSoft, tint = c.success)
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SignalType.rowTitle, color = c.text)
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = if (monoSubtitle) SignalType.monoCaption else SignalType.caption,
                    color = c.muted,
                    maxLines = subtitleMaxLines,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (value != null) {
            Text(
                value,
                style = MaterialTheme.typography.bodyMedium,
                color = c.muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = 140.dp),
            )
        }
        Icon(
            Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            contentDescription = null,
            tint = c.faint,
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
internal fun SettingsNavigationRow(
    title: VoxUiText,
    subtitle: VoxUiText,
    value: String? = null,
    icon: ImageVector? = null,
    iconTone: SettingsIconTone = SettingsIconTone.NEUTRAL,
    onClick: () -> Unit,
) {
    SettingsSignalNavRow(
        title = title.localized(),
        subtitle = subtitle.localized(),
        onClick = onClick,
        value = value,
        icon = icon,
        iconTone = iconTone,
    )
}

@Composable
internal fun SettingsValueRow(title: VoxUiText, value: String) {
    SignalValueRow(title.localized(), value)
}

@Composable
internal fun SettingsActionRow(title: VoxUiText, onClick: () -> Unit) {
    SignalActionRow(title.localized(), onClick)
}

@Composable
internal fun SettingsSection(title: VoxUiText) {
    SignalSectionLabel(title.localized(), Modifier.padding(start = 4.dp, end = 4.dp, top = 20.dp, bottom = 6.dp))
}

@Composable
internal fun PlaceholderSettingsRow(title: VoxUiText, subtitle: VoxUiText) {
    val c = Signal.colors
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title.localized(), style = SignalType.rowTitle, color = c.text)
            Text(subtitle.localized(), style = SignalType.monoCaption, color = c.muted)
        }
        SignalBadge(voxString("Planned"), color = c.well, contentColor = c.muted)
    }
}

// endregion

/** Keeps `VoxTopBar(title) { back() }` binding the trailing lambda to Back. */
@Composable
internal fun VoxTopBar(title: VoxUiText, navigateBack: () -> Unit) {
    VoxTopBar(title = title, navigateBack = navigateBack, subtitle = null)
}

@Composable
internal fun VoxTopBar(
    title: VoxUiText,
    navigateBack: () -> Unit,
    subtitle: VoxUiText? = null,
    actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {},
) {
    md.vox.android.ui.SignalTopBar(
        title = title.localized(),
        navigateBack = navigateBack,
        subtitle = subtitle?.localized(),
        backDescription = voxString("Back"),
        actions = actions,
    )
}
