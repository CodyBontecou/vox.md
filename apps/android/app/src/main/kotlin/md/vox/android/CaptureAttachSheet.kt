package md.vox.android

import android.content.ClipDescription
import android.content.ClipboardManager
import android.os.Build
import android.view.textclassifier.TextClassifier
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material.icons.outlined.Draw
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.automirrored.outlined.InsertDriveFile
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Smartphone
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CaptureRouteOverride
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalType

/** What the clipboard holds, read from its description only (no paste toast). */
internal enum class CaptureClipboardKind { LINK, IMAGE }

/**
 * Classifies the primary clip without reading its content, so Android does not
 * show the "pasted from your clipboard" notice until the person taps Paste. Plain
 * text counts as a link only when the system classifier reports a URL (API 31+).
 */
internal fun detectCaptureClipboardKind(clipboard: ClipboardManager?): CaptureClipboardKind? {
    val description = runCatching { clipboard?.primaryClipDescription }.getOrNull() ?: return null
    if (description.hasMimeType("image/*")) return CaptureClipboardKind.IMAGE
    if (description.hasMimeType(ClipDescription.MIMETYPE_TEXT_URILIST)) return CaptureClipboardKind.LINK
    if (
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
        description.hasMimeType("text/*") &&
        description.classificationStatus == ClipDescription.CLASSIFICATION_COMPLETE &&
        description.getConfidenceScore(TextClassifier.TYPE_URL) >= 0.5f
    ) {
        return CaptureClipboardKind.LINK
    }
    return null
}

/** "→ Meeting Notes · Meetings/2026-11-03.md › ## Notes" under the sheet title. */
internal fun captureDestinationLine(preset: CapturePreset?, route: CaptureRouteOverride?): String? {
    val name = preset?.name?.takeIf(String::isNotBlank)
    val path = route?.relativeNotePath?.takeIf(String::isNotBlank) ?: preset?.let {
        if (it.noteTargetKind == CaptureNoteTargetKind.EXISTING_NOTE) {
            it.existingNotePath
        } else {
            listOf(it.logicalFolder, it.noteNameTemplate).filter(String::isNotBlank).joinToString("/")
        }
    }?.takeIf(String::isNotBlank)
    val heading = preset?.headingTitle?.takeIf { it.isNotBlank() && route?.relativeNotePath == null }
        ?.let { "${"#".repeat(preset.headingLevel.coerceIn(1, 6))} $it" }
    val target = listOfNotNull(path, heading).joinToString(" › ").takeIf(String::isNotEmpty)
    return when {
        name != null && target != null && name != target -> "→ $name · $target"
        name != null -> "→ $name"
        target != null -> "→ $target"
        else -> null
    }
}

/** Tools in the ATTACH grid (3 × 2), in the iOS order. */
internal enum class CaptureAttachTool(val title: VoxUiText, val icon: ImageVector, val tag: String) {
    CAMERA(voxUiText("Camera"), Icons.Outlined.CameraAlt, "camera"),
    FILE(voxUiText("File"), Icons.AutoMirrored.Outlined.InsertDriveFile, "file"),
    SKETCH(voxUiText("Sketch"), Icons.Outlined.Draw, "sketch"),
    LINK(voxUiText("Link"), Icons.Outlined.Link, "link"),
    LOCATION(voxUiText("Location"), Icons.Outlined.LocationOn, "location"),
    SCREENSHOT(voxUiText("Screenshot"), Icons.Outlined.Smartphone, "screenshot"),
}

/**
 * Attach sheet ("Add to note", AttachV2 board): where the note lands, a clipboard
 * shortcut, the system photo picker, the two tools that read text into Markdown,
 * then the remaining attachments.
 *
 * Android cannot list recent photos without READ_MEDIA_IMAGES, which this app
 * deliberately never requests; the permission-free system Photo Picker already
 * offers recents with numbered multi-select, so "All photos" opens it directly.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CaptureAttachSheet(
    destinationLine: String?,
    clipboard: CaptureClipboardKind?,
    isBusy: Boolean,
    onDismiss: () -> Unit,
    paste: () -> Unit,
    choosePhotos: () -> Unit,
    scanDocument: () -> Unit,
    captureJournalPages: () -> Unit,
    chooseJournalPhotos: () -> Unit,
    choose: (CaptureAttachTool) -> Unit,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
) {
    val c = Signal.colors
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = c.bg,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        modifier = Modifier.testTag("capture-attach-sheet"),
    ) {
        CaptureAttachSheetContent(
            destinationLine = destinationLine,
            clipboard = clipboard,
            isBusy = isBusy,
            paste = paste,
            choosePhotos = choosePhotos,
            scanDocument = scanDocument,
            captureJournalPages = captureJournalPages,
            chooseJournalPhotos = chooseJournalPhotos,
            choose = choose,
        )
    }
}

@Composable
internal fun CaptureAttachSheetContent(
    destinationLine: String?,
    clipboard: CaptureClipboardKind?,
    isBusy: Boolean,
    paste: () -> Unit,
    choosePhotos: () -> Unit,
    scanDocument: () -> Unit,
    captureJournalPages: () -> Unit,
    chooseJournalPhotos: () -> Unit,
    choose: (CaptureAttachTool) -> Unit,
) {
    val c = Signal.colors
    val largeText = LocalDensity.current.fontScale >= 1.5f
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
            .navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                voxString("Add to note"),
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold, fontSize = 20.sp),
                color = c.text,
                modifier = Modifier.semantics { heading() },
            )
            if (destinationLine != null) {
                Text(
                    destinationLine,
                    style = SignalType.monoCaption,
                    color = c.muted,
                    maxLines = if (largeText) 3 else 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        if (clipboard != null) CaptureClipboardCard(clipboard, enabled = !isBusy, paste = paste)

        CaptureReadTile(
            title = voxString("All photos"),
            subtitle = voxString("Tap to pick one or more"),
            icon = Icons.Outlined.PhotoLibrary,
            enabled = !isBusy,
            onClick = choosePhotos,
            modifier = Modifier.fillMaxWidth().testTag("capture-attach-photos"),
        )

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CaptureMonoSectionLabel(voxString("READ INTO MARKDOWN"))
            val scan: @Composable (Modifier) -> Unit = { modifier ->
                CaptureReadTile(
                    title = voxString("Scan"),
                    subtitle = voxString("Documents, whiteboards"),
                    icon = Icons.Outlined.DocumentScanner,
                    enabled = !isBusy,
                    onClick = scanDocument,
                    modifier = modifier.testTag("capture-attach-scan"),
                )
            }
            val journal: @Composable (Modifier) -> Unit = { modifier ->
                var expanded by remember { mutableStateOf(false) }
                Box(modifier) {
                    CaptureReadTile(
                        title = voxString("Journal page"),
                        subtitle = voxString("Camera or photos"),
                        icon = Icons.AutoMirrored.Outlined.MenuBook,
                        enabled = !isBusy,
                        onClick = { expanded = true },
                        modifier = Modifier.fillMaxWidth().testTag("capture-attach-journal"),
                    )
                    CaptureSignalMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        CaptureMenuItem(voxString("Capture Journal Pages"), Icons.Outlined.CameraAlt) {
                            expanded = false
                            captureJournalPages()
                        }
                        CaptureMenuItem(voxString("Choose Journal Photos"), Icons.Outlined.Image) {
                            expanded = false
                            chooseJournalPhotos()
                        }
                    }
                }
            }
            if (largeText) {
                scan(Modifier.fillMaxWidth())
                journal(Modifier.fillMaxWidth())
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    scan(Modifier.weight(1f))
                    journal(Modifier.weight(1f))
                }
            }
            Text(
                voxString("Read on this device. The original image is kept alongside."),
                style = SignalType.caption.copy(fontSize = 13.sp),
                color = c.muted,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CaptureMonoSectionLabel(voxString("ATTACH"))
            val columns = if (largeText) 2 else 3
            CaptureAttachTool.entries.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { tool ->
                        CaptureAttachToolButton(
                            tool = tool,
                            enabled = !isBusy,
                            onClick = { choose(tool) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun CaptureClipboardCard(kind: CaptureClipboardKind, enabled: Boolean, paste: () -> Unit) {
    val c = Signal.colors
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(shape)
            .background(c.accentSoft.copy(alpha = 0.55f))
            .border(1.dp, c.tint.copy(alpha = 0.25f), shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = paste)
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .alpha(if (enabled) 1f else 0.45f)
            .testTag("capture-attach-clipboard"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(36.dp).clip(RoundedCornerShape(10.dp)).background(c.accent),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (kind == CaptureClipboardKind.LINK) Icons.Outlined.Link else Icons.Outlined.Image,
                contentDescription = null,
                tint = c.onAccent,
                modifier = Modifier.size(18.dp),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                voxString(if (kind == CaptureClipboardKind.LINK) "Paste copied link" else "Paste copied image"),
                style = SignalType.caption.copy(fontWeight = FontWeight.SemiBold),
                color = c.text,
            )
            Text(voxString("From your clipboard"), style = SignalType.caption.copy(fontSize = 12.sp), color = c.muted)
        }
        Text(voxString("Paste"), style = MaterialTheme.typography.labelMedium, color = c.tint)
    }
}

@Composable
private fun CaptureReadTile(
    title: String,
    subtitle: String,
    icon: ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    Row(
        modifier = modifier
            .heightIn(min = 64.dp)
            .clip(CaptureReadTileShape)
            .background(c.card)
            .border(1.dp, c.border, CaptureReadTileShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .alpha(if (enabled) 1f else 0.4f),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, contentDescription = null, tint = c.text, modifier = Modifier.size(22.dp))
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = SignalType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.text)
            Text(subtitle, style = SignalType.caption.copy(fontSize = 12.sp), color = c.muted)
        }
    }
}

@Composable
private fun CaptureAttachToolButton(
    tool: CaptureAttachTool,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    Row(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clip(CaptureTileShape)
            .background(c.card)
            .border(1.dp, c.border, CaptureTileShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .testTag("capture-attach-${tool.tag}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(tool.icon, contentDescription = null, tint = c.text, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(
            tool.title.localized(),
            style = SignalType.caption.copy(fontSize = 13.sp, fontWeight = FontWeight.Medium),
            color = c.text,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun CaptureMenuItem(label: String, icon: ImageVector, onClick: () -> Unit) {
    androidx.compose.material3.DropdownMenuItem(
        text = { Text(label, style = MaterialTheme.typography.bodyLarge) },
        leadingIcon = { Icon(icon, contentDescription = null, tint = Signal.colors.text) },
        onClick = onClick,
        colors = androidx.compose.material3.MenuDefaults.itemColors(textColor = Signal.colors.text),
        modifier = Modifier.heightIn(min = 48.dp),
    )
}
