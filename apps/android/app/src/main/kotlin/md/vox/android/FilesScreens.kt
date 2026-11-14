package md.vox.android

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.NoteAdd
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOff
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CaptureRollingPeriod
import md.vox.android.capturedomain.LiveNoteLocation
import md.vox.android.capturedomain.VaultEntry
import md.vox.android.capturedomain.VaultListing
import md.vox.android.capturedomain.VaultTree
import md.vox.android.ui.GeistMonoFontFamily
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalSearchField
import md.vox.android.ui.SignalType
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** How many files a folder shows inline before "N more" opens the full folder. */
private const val INLINE_FILES = 3

/**
 * Files tab: the vault as a real folder tree over the SAF grant. Folders expand inline with
 * their first files and "N more"; each preset is a small badge on the folder or file it
 * writes to. Listings load off the main thread and refresh on resume (SAF has no change
 * notifications). Tapping a file opens it in the Capture editor.
 */
@Composable
internal fun FilesScreen(
    destination: CaptureDestination,
    presets: List<CapturePreset>,
    list: suspend (String) -> VaultListing,
    openFile: (VaultEntry, CapturePreset?) -> Unit,
    openFolder: (String) -> Unit,
    reconnect: () -> Unit,
    nowEpochMillis: Long = System.currentTimeMillis(),
    /** Phones: round back button to Capture (pushed screen, as on iOS). */
    navigateBack: (() -> Unit)? = null,
) {
    val c = Signal.colors
    val scope = rememberCoroutineScope()
    var query by rememberSaveable { mutableStateOf("") }
    val listings = remember { mutableStateMapOf<String, VaultListing>() }
    val targets = remember(presets, destination) { VaultTree.presetTargets(presets, destination) }
    val expanded = rememberSaveable(saver = expandedSaver) { mutableStateMapOf<String, Boolean>() }
    var refreshTick by remember { mutableStateOf(0) }
    fun load(folder: String) {
        scope.launch { listings[folder] = list(folder) }
    }
    // Preset folders start open, the way the design shows the folders presets write to.
    LaunchedEffect(targets) {
        targets.keys.filterNot { it.endsWith(".md", ignoreCase = true) }.map { it.substringBefore('/') }.forEach { folder ->
            if (folder !in expanded) expanded[folder] = true
        }
    }
    LaunchedEffect(refreshTick) {
        load("")
        expanded.filterValues { it }.keys.forEach(::load)
    }
    OnResumeEffect { refreshTick += 1 }

    val root = listings[""]
    Column(Modifier.fillMaxSize().background(c.bg).navigationBarsPadding()) {
        if (navigateBack != null) LargeTitleBackRow(navigateBack)
        Row(
            modifier = Modifier.fillMaxWidth().then(if (navigateBack == null) Modifier.statusBarsPadding() else Modifier).padding(start = 16.dp, end = 8.dp, top = if (navigateBack == null) 16.dp else 4.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            Column(Modifier.weight(1f)) {
                Text(destination.displayName, style = MaterialTheme.typography.headlineMedium.copy(fontSize = 30.sp, fontWeight = FontWeight.SemiBold), color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(vaultRootLine(destination.treeUri), style = SignalType.monoCaption, color = c.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
            }
            SignalCircleButton(icon = Icons.Outlined.Refresh, contentDescription = voxString("Refresh"), onClick = { refreshTick += 1 })
        }
        SignalSearchField(
            value = query,
            onValueChange = { query = it },
            placeholder = voxString("Filter files"),
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp).testTag("files-filter"),
        )
        when (root) {
            null -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.size(22.dp), color = c.tint, trackColor = c.well, strokeWidth = 2.dp)
            }
            is VaultListing.Unreachable, VaultListing.Missing -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                SignalEmptyState(
                    icon = Icons.Outlined.FolderOff,
                    title = voxFormat("Can't reach your %@ folder", destination.displayName),
                    message = voxString("Captures are kept on this phone until the folder is available again."),
                    action = {
                        md.vox.android.ui.SignalButton(voxString("Reconnect folder"), onClick = reconnect, size = md.vox.android.ui.SignalButtonSize.MEDIUM, fillWidth = false)
                    },
                )
            }
            is VaultListing.Listed -> {
                val rows = buildTreeRows(root.entries, listings, expanded, targets, query)
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .padding(horizontal = 16.dp)
                        .clip(RoundedCornerShape(SignalMetrics.CardRadius))
                        .background(c.card)
                        .border(1.dp, c.divider, RoundedCornerShape(SignalMetrics.CardRadius))
                        .testTag("files-tree"),
                    contentPadding = PaddingValues(vertical = 6.dp),
                ) {
                    if (rows.isEmpty()) item("empty") {
                        Text(
                            if (query.isBlank()) voxString("This folder is empty.") else voxString("No files match."),
                            style = SignalType.caption,
                            color = c.muted,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                    items(rows, key = { it.key }) { row ->
                        when (row) {
                            is TreeRow.Folder -> FolderTreeRow(
                                entry = row.entry,
                                depth = row.depth,
                                isExpanded = expanded[row.entry.relativePath] == true,
                                badges = targets[row.entry.relativePath].orEmpty(),
                                toggle = {
                                    val open = expanded[row.entry.relativePath] != true
                                    expanded[row.entry.relativePath] = open
                                    if (open) load(row.entry.relativePath)
                                },
                            )
                            is TreeRow.File -> FileTreeRow(
                                entry = row.entry,
                                depth = row.depth,
                                badges = targets[row.entry.relativePath].orEmpty(),
                                nowEpochMillis = nowEpochMillis,
                                open = { openFile(row.entry, targets[row.entry.relativePath]?.firstOrNull() ?: targets[row.entry.relativePath.substringBeforeLast('/', "")]?.firstOrNull()) },
                            )
                            is TreeRow.More -> MoreTreeRow(row.count, row.depth) { openFolder(row.folder) }
                            is TreeRow.Loading -> Text(
                                voxString("Loading…"),
                                style = SignalType.caption,
                                color = c.faint,
                                modifier = Modifier.padding(start = indent(row.depth) + 26.dp, top = 10.dp, bottom = 10.dp),
                            )
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
        }
    }
}

private sealed interface TreeRow {
    val key: String
    data class Folder(val entry: VaultEntry, val depth: Int) : TreeRow { override val key get() = "d:${entry.relativePath}" }
    data class File(val entry: VaultEntry, val depth: Int) : TreeRow { override val key get() = "f:${entry.relativePath}" }
    data class More(val folder: String, val count: Int, val depth: Int) : TreeRow { override val key get() = "m:$folder" }
    data class Loading(val folder: String, val depth: Int) : TreeRow { override val key get() = "l:$folder" }
}

private fun buildTreeRows(
    entries: List<VaultEntry>,
    listings: Map<String, VaultListing>,
    expanded: Map<String, Boolean>,
    targets: Map<String, List<CapturePreset>>,
    query: String,
    depth: Int = 0,
): List<TreeRow> = buildList {
    val sorted = VaultTree.sorted(entries).filter { it.isFolder || it.isMarkdown }
    val folders = sorted.filter(VaultEntry::isFolder)
    val files = sorted.filterNot(VaultEntry::isFolder)
    for (folder in folders) {
        val open = expanded[folder.relativePath] == true || (query.isNotBlank() && listings[folder.relativePath] != null)
        val children = (listings[folder.relativePath] as? VaultListing.Listed)?.entries
        val childRows = if (open && children != null) buildTreeRows(children, listings, expanded, targets, query, depth + 1) else emptyList()
        if (query.isNotBlank() && !VaultTree.matches(folder, query) && childRows.isEmpty()) continue
        add(TreeRow.Folder(folder, depth))
        if (!open) continue
        if (children == null) add(TreeRow.Loading(folder.relativePath, depth + 1)) else addAll(childRows)
    }
    val shownFiles = files.filter { VaultTree.matches(it, query) }
    // Top-level files are all shown; inside a folder only the newest few, then "N more".
    val limit = if (depth == 0 || query.isNotBlank()) shownFiles.size else INLINE_FILES
    shownFiles.take(limit).forEach { add(TreeRow.File(it, depth)) }
    if (shownFiles.size > limit) {
        val folder = shownFiles.first().relativePath.substringBeforeLast('/', "")
        add(TreeRow.More(folder, shownFiles.size - limit, depth))
    }
}

private fun indent(depth: Int): Dp = 10.dp + (depth * 24).dp

@Composable
private fun FolderTreeRow(entry: VaultEntry, depth: Int, isExpanded: Boolean, badges: List<CapturePreset>, toggle: () -> Unit) {
    val c = Signal.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .clickable(role = Role.Button, onClick = toggle)
            .padding(start = indent(depth), end = 12.dp)
            .testTag("files-folder-${entry.relativePath}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(if (isExpanded) Icons.Outlined.KeyboardArrowDown else Icons.Outlined.KeyboardArrowRight, contentDescription = null, tint = c.faint, modifier = Modifier.size(16.dp))
        Icon(Icons.Outlined.Folder, contentDescription = null, tint = c.muted, modifier = Modifier.size(18.dp))
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(entry.name, style = FileNameStyle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            badges.take(2).forEach { PresetBadge(it) }
        }
        entry.childCount?.let { Text(it.toString(), style = SignalType.monoCaption, color = c.faint) }
    }
}

@Composable
private fun FileTreeRow(entry: VaultEntry, depth: Int, badges: List<CapturePreset>, nowEpochMillis: Long, open: () -> Unit) {
    val c = Signal.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 40.dp)
            .clickable(role = Role.Button, onClick = open)
            .padding(start = indent(depth) + 24.dp, end = 12.dp)
            .testTag("files-file-${entry.relativePath}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (depth == 0) Icon(Icons.Outlined.Description, contentDescription = null, tint = c.muted, modifier = Modifier.size(16.dp))
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(entry.name, style = FileNameStyle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            if (isToday(entry.lastModifiedEpochMillis, nowEpochMillis)) TodayTag()
            badges.take(1).forEach { PresetBadge(it) }
        }
        entry.lastModifiedEpochMillis?.let { Text(fileTimeLabel(it, nowEpochMillis), style = SignalType.monoCaption, color = c.faint, maxLines = 1) }
    }
}

@Composable
private fun MoreTreeRow(count: Int, depth: Int, open: () -> Unit) {
    val c = Signal.colors
    Text(
        voxFormat("%@ more", count.toString()),
        style = FileNameStyle,
        color = c.muted,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = open)
            .padding(start = indent(depth) + 24.dp, top = 11.dp, bottom = 11.dp)
            .testTag("files-more"),
    )
}

/** Letter avatar plus preset name: indigo for the first (active) tone, ink for the rest. */
@Composable
internal fun PresetBadge(preset: CapturePreset, large: Boolean = false) {
    val c = Signal.colors
    val letter = preset.emoji ?: preset.name.trim().take(1).uppercase(Locale.getDefault())
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(c.accentSoft)
            .padding(start = 3.dp, end = if (large) 10.dp else 8.dp, top = 2.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            Modifier.size(if (large) 18.dp else 14.dp).clip(CircleShape).background(c.accent),
            contentAlignment = Alignment.Center,
        ) {
            Text(letter, color = c.onAccent, style = MaterialTheme.typography.labelSmall.copy(fontSize = if (large) 10.sp else 8.5.sp, fontWeight = FontWeight.SemiBold), maxLines = 1)
        }
        Text(preset.name, color = c.accentText, style = MaterialTheme.typography.labelSmall.copy(fontSize = if (large) 12.sp else 11.sp, fontWeight = FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun TodayTag() {
    val c = Signal.colors
    Text(
        voxString("today"),
        style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Medium),
        color = c.successText,
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(c.successSoft).padding(horizontal = 6.dp, vertical = 1.dp),
    )
}

/**
 * Full folder (from "N more"): files grouped by month with a one-line preview, a "today"
 * tag, and a bottom action for the preset that writes here ("Add to today", "New in …").
 */
@Composable
internal fun VaultFolderScreen(
    destination: CaptureDestination,
    relativeFolder: String,
    presets: List<CapturePreset>,
    list: suspend (String) -> VaultListing,
    preview: suspend (LiveNoteLocation) -> String?,
    openFile: (VaultEntry, CapturePreset?) -> Unit,
    startInPreset: (CapturePreset) -> Unit,
    navigateBack: () -> Unit,
    nowEpochMillis: Long = System.currentTimeMillis(),
) {
    val c = Signal.colors
    var query by rememberSaveable(relativeFolder) { mutableStateOf("") }
    var refreshTick by remember { mutableStateOf(0) }
    OnResumeEffect { refreshTick += 1 }
    val listing by produceState<VaultListing?>(null, relativeFolder, refreshTick) { value = list(relativeFolder) }
    val preset = remember(presets, destination, relativeFolder) { VaultTree.presetTargets(presets, destination)[relativeFolder]?.firstOrNull() }
    val folderName = relativeFolder.substringAfterLast('/').ifEmpty { destination.displayName }
    val files = (listing as? VaultListing.Listed)?.entries.orEmpty().filter(VaultEntry::isMarkdown)
        .let(VaultTree::sorted)
    val shown = files.filter { VaultTree.matches(it, query) }
    Box(Modifier.fillMaxSize().background(c.bg).navigationBarsPadding()) {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(start = 8.dp, end = 8.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(
                    Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(12.dp)).clickable(role = Role.Button, onClick = navigateBack).padding(horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, contentDescription = null, tint = c.tint)
                    Text(destination.displayName, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium), color = c.tint)
                }
            }
            Column(Modifier.padding(horizontal = 16.dp)) {
                val parent = relativeFolder.substringBeforeLast('/', "")
                Text(liveNoteBreadcrumb(destination.displayName, parent) + " /", style = SignalType.monoCaption, color = c.muted)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 2.dp)) {
                    Text(folderName + "/", style = androidx.compose.ui.text.TextStyle(fontFamily = GeistMonoFontFamily, fontSize = 28.sp, fontWeight = FontWeight.Medium), color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    preset?.let { PresetBadge(it, large = true) }
                }
                Text(
                    listOfNotNull(
                        preset?.let { folderRule(it) },
                        fileCountLabel(files.size),
                    ).joinToString(" · "),
                    style = SignalType.caption,
                    color = c.muted,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            SignalSearchField(
                value = query,
                onValueChange = { query = it },
                placeholder = voxFormat("Search %@", folderName),
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )
            if (listing == null) {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(22.dp), color = c.tint, trackColor = c.well, strokeWidth = 2.dp)
                }
            } else {
                val groups = shown.groupBy { monthKey(it.lastModifiedEpochMillis) }
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f).testTag("folder-list"),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 96.dp),
                ) {
                    groups.forEach { (month, monthFiles) ->
                        item(key = "h:$month") {
                            Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = 14.dp, bottom = 6.dp)) {
                                Text(monthLabel(monthFiles.first().lastModifiedEpochMillis).uppercase(Locale.getDefault()), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp), color = c.muted, modifier = Modifier.weight(1f))
                                Text(fileCountLabel(monthFiles.size), style = SignalType.monoCaption, color = c.muted)
                            }
                        }
                        item(key = "g:$month") {
                            Column(
                                Modifier.fillMaxWidth().clip(RoundedCornerShape(SignalMetrics.CardRadius)).background(c.card).border(1.dp, c.divider, RoundedCornerShape(SignalMetrics.CardRadius)),
                            ) {
                                monthFiles.forEachIndexed { index, entry ->
                                    if (index > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(c.divider))
                                    FolderFileRow(destination, entry, preview, nowEpochMillis) { openFile(entry, preset) }
                                }
                            }
                        }
                    }
                }
            }
        }
        if (preset != null) {
            val label = if (preset.noteTargetKind == CaptureNoteTargetKind.ROLLING_NOTE) {
                if (preset.rollingPeriod == CaptureRollingPeriod.DAILY) voxString("Add to today") else voxFormat("Add to %@", preset.name)
            } else voxFormat("New in %@", folderName)
            Row(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp)
                    .heightIn(min = 52.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(c.accent)
                    .clickable(role = Role.Button) { startInPreset(preset) }
                    .padding(horizontal = 18.dp)
                    .testTag("folder-primary-action"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.AutoMirrored.Outlined.NoteAdd, contentDescription = null, tint = c.onAccent, modifier = Modifier.size(20.dp))
                Text(label, style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold), color = c.onAccent)
            }
        }
    }
}

@Composable
private fun FolderFileRow(destination: CaptureDestination, entry: VaultEntry, preview: suspend (LiveNoteLocation) -> String?, nowEpochMillis: Long, open: () -> Unit) {
    val c = Signal.colors
    val line by produceState<String?>(null, entry.relativePath, entry.lastModifiedEpochMillis) {
        value = preview(LiveNoteLocation(destination.id, destination.treeUri, entry.relativePath))
    }
    Column(
        Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = open).padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(entry.name, style = FileNameStyle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (isToday(entry.lastModifiedEpochMillis, nowEpochMillis)) TodayTag()
            }
            entry.lastModifiedEpochMillis?.let { Text(fileTimeLabel(it, nowEpochMillis), style = SignalType.monoCaption, color = c.faint) }
        }
        line?.let {
            Text(it, style = SignalType.caption, color = c.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

@Composable
private fun folderRule(preset: CapturePreset): String {
    val file = preset.noteNameTemplate.ifBlank { "{title}" }.let { if (it.endsWith(".md", true)) it else "$it.md" }
    val heading = preset.headingTitle.takeIf { it.isNotBlank() && preset.placement == md.vox.android.capturedomain.CapturePlacementKind.BENEATH_HEADING }
        ?.let { "#".repeat(preset.headingLevel.coerceIn(1, 6)) + " " + it }
    return if (heading != null) voxFormat("%1\$@ writes to %2\$@ under %3\$@", preset.name, file, heading)
    else voxFormat("%1\$@ writes to %2\$@", preset.name, file)
}

/** Runs [onResume] whenever the screen comes back to the foreground (SAF has no change notifications). */
@Composable
internal fun OnResumeEffect(onResume: () -> Unit) {
    val owner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    val latest by androidx.compose.runtime.rememberUpdatedState(onResume)
    DisposableEffect(owner) {
        var first = true
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                if (first) first = false else latest()
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
}

private val FileNameStyle = androidx.compose.ui.text.TextStyle(fontFamily = GeistMonoFontFamily, fontSize = 14.sp, lineHeight = 18.sp)

private val expandedSaver = androidx.compose.runtime.saveable.Saver<androidx.compose.runtime.snapshots.SnapshotStateMap<String, Boolean>, ArrayList<String>>(
    save = { map -> ArrayList(map.filterValues { it }.keys) },
    restore = { saved -> mutableStateMapOf<String, Boolean>().apply { saved.forEach { put(it, true) } } },
)

/** "Internal storage / Documents / Vox Notes" from a tree URI's document ID. */
internal fun vaultRootLine(treeUri: String): String {
    val id = runCatching { java.net.URLDecoder.decode(treeUri.substringAfterLast('/').replace("+", "%2B"), "UTF-8") }.getOrDefault("")
    val volume = id.substringBefore(':', "")
    val path = id.substringAfter(':', id)
    val head = when (volume) {
        "primary" -> "Internal storage"
        "" -> ""
        else -> volume
    }
    return (listOf(head) + path.split('/')).filter(String::isNotBlank).joinToString(" / ")
}

internal fun isToday(epochMillis: Long?, nowEpochMillis: Long): Boolean =
    epochMillis != null && libraryStartOfDay(epochMillis) == libraryStartOfDay(nowEpochMillis)

/** 14:05 today, a weekday within the week, else "Oct 31". */
internal fun fileTimeLabel(epochMillis: Long, nowEpochMillis: Long): String {
    val day = libraryStartOfDay(epochMillis)
    val today = libraryStartOfDay(nowEpochMillis)
    val pattern = when {
        day == today -> "HH:mm"
        today - day < 6L * 24 * 60 * 60 * 1000 && day <= today -> "EEE"
        else -> "MMM d"
    }
    return SimpleDateFormat(pattern, Locale.getDefault()).format(Date(epochMillis))
}

private fun monthKey(epochMillis: Long?): String {
    epochMillis ?: return "unknown"
    val calendar = Calendar.getInstance().apply { timeInMillis = epochMillis }
    return "${calendar.get(Calendar.YEAR)}-${calendar.get(Calendar.MONTH)}"
}

private fun monthLabel(epochMillis: Long?): String =
    epochMillis?.let { SimpleDateFormat("LLLL yyyy", Locale.getDefault()).format(Date(it)) } ?: "—"

@Composable
private fun fileCountLabel(count: Int): String =
    if (count == 1) voxString("1 file") else voxFormat("%@ files", count.toString())

/** Round back button over a large title (iOS pushed screens): returns to Capture. */
@Composable
internal fun LargeTitleBackRow(navigateBack: () -> Unit, trailing: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().padding(start = 12.dp, end = 12.dp, top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SignalCircleButton(
            icon = Icons.AutoMirrored.Outlined.ArrowBack,
            contentDescription = voxString("Back to Capture"),
            onClick = navigateBack,
            modifier = Modifier.testTag("back-to-capture"),
        )
        Spacer(Modifier.weight(1f))
        trailing()
    }
}
