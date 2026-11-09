package md.vox.android

import androidx.compose.material.icons.outlined.Sync

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalFieldShape
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalRowDivider
import md.vox.android.ui.SignalSwitch
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalTextFieldColors
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import md.vox.android.capturedomain.*

@Composable internal fun PresetVaultControl(destination: CaptureDestination?, onChanged: (CaptureDestination?) -> Unit) {
    val context = LocalContext.current
    var error by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                val document = android.provider.DocumentsContract.buildDocumentUriUsingTree(uri, android.provider.DocumentsContract.getTreeDocumentId(uri))
                val name = runCatching { context.contentResolver.query(document, arrayOf(android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                } }.getOrNull() ?: "Markdown folder"
                onChanged(CaptureDestination(UUID.randomUUID().toString(), name.take(128), uri.toString()))
            }.onFailure { error = true }
        }
    }
    val c = Signal.colors
    Text(voxString("Preset Vault"), style = MaterialTheme.typography.titleMedium, color = c.text)
    Text(destination?.displayName ?: voxString("Use the default Capture Destination"), style = SignalType.mono, color = c.muted)
    SignalButton(voxString("Choose vault for this preset"), onClick = { picker.launch(null) },
        variant = SignalButtonVariant.SECONDARY, size = SignalButtonSize.MEDIUM, icon = Icons.Outlined.FolderOpen)
    if (destination != null) TextButton(onClick = { onChanged(null) }) { Text(voxString("Use default destination")) }
    if (error) Text(voxString("Folder access could not be saved. Choose the folder again."), style = SignalType.caption, color = c.error)
}

@Composable internal fun TranscriptPropertyControls(name: String, includeBody: Boolean, changeName: (String) -> Unit, changeBody: (Boolean) -> Unit) {
    OutlinedTextField(name, { changeName(it.take(128)) }, modifier = Modifier.fillMaxWidth(),
        label = { Text(voxString("Transcript Property")) }, singleLine = true,
        shape = SignalFieldShape, colors = signalTextFieldColors(),
        isError = name.isNotBlank() && normalizedTranscriptProperty(name) == null,
        supportingText = { Text(voxString("Voice transcripts replace this note property. Leave empty to keep the normal note body.")) })
    if (name.isNotBlank()) Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(voxString("Also include transcript in body"), style = SignalType.rowTitle, color = Signal.colors.text, modifier = Modifier.weight(1f))
        SignalSwitch(includeBody, changeBody)
    }
}

/**
 * Signal route line under the capture selector: a mono muted "Route: …" line
 * (iOS shows the destination path there) that opens the per-draft route sheet.
 */
@Stable
internal class CaptureRouteEditorState {
    var showsDialog by mutableStateOf(false)
    var path by mutableStateOf("")
    var placement by mutableStateOf<CapturePlacementKind?>(null)

    fun open(route: CaptureRouteOverride?) {
        path = route?.relativeNotePath.orEmpty()
        placement = route?.placement
        showsDialog = true
    }

    companion object {
        val Saver = listSaver<CaptureRouteEditorState, Any>(
            save = { listOf(it.showsDialog, it.path, it.placement?.name.orEmpty()) },
            restore = { saved -> CaptureRouteEditorState().apply {
                showsDialog = saved[0] as Boolean
                path = saved[1] as String
                placement = (saved[2] as String).takeIf(String::isNotEmpty)?.let(CapturePlacementKind::valueOf)
            } },
        )
    }
}

@Composable internal fun rememberCaptureRouteEditorState() =
    rememberSaveable(saver = CaptureRouteEditorState.Saver) { CaptureRouteEditorState() }

@Composable internal fun CaptureRouteControl(
    route: CaptureRouteOverride?,
    destination: CaptureDestination?,
    enabled: Boolean = true,
    editor: CaptureRouteEditorState = rememberCaptureRouteEditorState(),
    onChanged: (CaptureRouteOverride?) -> Unit,
) {
    val c = Signal.colors
    Row(
        modifier = Modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(10.dp))
            .clickable(enabled = enabled, role = Role.Button) { editor.open(route) }
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            voxFormat("Route: %@", route?.relativeNotePath ?: destination?.displayName ?: voxString("Preset destination")),
            style = SignalType.monoCaption,
            color = if (!enabled) c.faint else if (route != null) c.accentText else c.muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null, tint = c.faint, modifier = Modifier.size(16.dp))
    }
    if (editor.showsDialog) {
        val value = CaptureRouteOverride(editor.path.trim().ifEmpty { null }, editor.placement)
        val valid = runCatching { value.validated() }.isSuccess
        AlertDialog(
            onDismissRequest = { editor.showsDialog = false },
            containerColor = c.card,
            shape = RoundedCornerShape(SignalMetrics.CardRadius + 4.dp),
            title = { Text(voxString("Route this capture"), style = MaterialTheme.typography.titleLarge, color = c.text) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        voxFormat("Vault: %@", destination?.displayName ?: voxString("Default destination")),
                        style = SignalType.mono,
                        color = c.muted,
                    )
                    OutlinedTextField(editor.path, { editor.path = it }, label = { Text(voxString("Note path in this vault")) },
                        placeholder = { Text(voxString("Journal/Inbox.md")) }, isError = !valid, singleLine = true,
                        shape = SignalFieldShape, colors = signalTextFieldColors(), modifier = Modifier.fillMaxWidth())
                    Text(voxString("Leave empty to use the preset note. This change applies only to the current draft."),
                        style = SignalType.caption, color = c.muted)
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(SignalMetrics.GroupRadius))
                            .border(1.dp, c.border, RoundedCornerShape(SignalMetrics.GroupRadius)),
                    ) {
                        val choices = listOf(null to voxString("Preset placement"), CapturePlacementKind.PREPEND to voxString("Top"), CapturePlacementKind.APPEND to voxString("Bottom"))
                        choices.forEachIndexed { index, (choice, label) ->
                            if (index > 0) SignalRowDivider()
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = 48.dp)
                                    .selectable(selected = editor.placement == choice, role = Role.RadioButton) { editor.placement = choice }
                                    .padding(horizontal = 14.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(label, style = SignalType.rowTitle, color = c.text, modifier = Modifier.weight(1f))
                                if (editor.placement == choice) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.tint, modifier = Modifier.size(20.dp))
                            }
                        }
                    }
                }
            },
            confirmButton = {
                SignalButton(voxString("Apply"), onClick = { onChanged(value.takeUnless { it.relativeNotePath == null && it.placement == null }); editor.showsDialog = false },
                    enabled = valid && enabled, size = SignalButtonSize.MEDIUM)
            },
            dismissButton = {
                SignalButton(voxString("Reset route"), onClick = { onChanged(null); editor.showsDialog = false },
                    variant = SignalButtonVariant.TERTIARY, enabled = enabled, size = SignalButtonSize.MEDIUM)
            },
        )
    }
}

@Composable internal fun URLDeliverySettingsControl(settings: CaptureURLDeliverySettings, onChanged: (CaptureURLDeliverySettings) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf(false) }
    var initial by remember { mutableStateOf<URLDeliveryCredentials?>(null) }
    Text(voxString("URL Delivery"), style = MaterialTheme.typography.titleMedium, color = Signal.colors.text)
    Text(if (settings.enabled) settings.origin else voxString("Off"), style = SignalType.mono, color = Signal.colors.muted)
    SignalButton(voxString("Configure URL delivery"), onClick = { scope.launch {
        initial = withContext(Dispatchers.IO) { runCatching { URLDeliveryOutbox(context).credentials(settings) }.getOrNull() }
        editing = true
    } }, variant = SignalButtonVariant.SECONDARY, size = SignalButtonSize.MEDIUM)
    if (settings.enabled) TextButton(onClick = { onChanged(settings.copy(enabled = false)) }) { Text(voxString("Disable URL delivery")) }
    if (editing) URLDeliveryCredentialsDialog(initial, onDismiss = { editing = false }) { credentials ->
        val saved = withContext(Dispatchers.IO) { URLDeliveryOutbox(context).saveCredentials(credentials) }
        onChanged(saved); editing = false
    }
}

@Composable private fun URLDeliveryCredentialsDialog(initial: URLDeliveryCredentials?, onDismiss: () -> Unit, save: suspend (URLDeliveryCredentials) -> Unit) {
    var endpoint by remember { mutableStateOf(initial?.endpoint.orEmpty()) }
    var bearer by remember { mutableStateOf(initial?.bearer.orEmpty()) }
    var headers by remember { mutableStateOf(initial?.headers?.entries?.joinToString("\n") { "${it.key}: ${it.value}" }.orEmpty()) }
    var consent by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    AlertDialog(onDismissRequest = { if (!saving) onDismiss() }, title = { Text(voxString("URL delivery")) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(voxString("When enabled, capture text and voice transcripts are sent to this endpoint. Local notes are still saved. Audio and attachments are not uploaded."))
            OutlinedTextField(endpoint, { endpoint = it }, label = { Text(voxString("HTTPS endpoint")) }, singleLine = true,
                shape = SignalFieldShape, colors = signalTextFieldColors())
            OutlinedTextField(bearer, { bearer = it }, label = { Text(voxString("Bearer token")) }, singleLine = true, visualTransformation = PasswordVisualTransformation(),
                shape = SignalFieldShape, colors = signalTextFieldColors())
            OutlinedTextField(headers, { headers = it }, label = { Text(voxString("Custom headers, one per line")) },
                shape = SignalFieldShape, colors = signalTextFieldColors())
            Text(voxString("Use HTTPS without URL query parameters. Store API secrets in the bearer token or custom headers."))
            Row { Checkbox(consent, { consent = it }); Text(voxString("Allow sending my capture text to this endpoint"), modifier = Modifier.weight(1f)) }
            if (error) Text(voxString("Check the endpoint and headers, then try again. Credentials could not be saved."), color = MaterialTheme.colorScheme.error)
        }
    }, confirmButton = { TextButton(enabled = consent && !saving, onClick = { scope.launch {
        saving = true
        runCatching {
            val parsed = headers.lines().filter(String::isNotBlank).associate { line ->
                require(':' in line); line.substringBefore(':').trim() to line.substringAfter(':').trim()
            }
            save(URLDeliveryCredentials(endpoint.trim(), bearer, parsed))
        }.onFailure { error = true }
        saving = false
    } }) { Text(voxString("Enable delivery")) } }, dismissButton = { TextButton(enabled = !saving, onClick = onDismiss) { Text(voxString("Cancel")) } })
}

@Composable internal fun URLDeliveryRecoveryControl() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var open by remember { mutableStateOf(false) }
    var receipts by remember { mutableStateOf(emptyList<URLDeliveryReceipt>()) }
    var revision by remember { mutableIntStateOf(0) }
    var confirming by remember { mutableStateOf<URLDeliveryReceipt?>(null) }
    var authorizing by remember { mutableStateOf<Pair<String, URLDeliveryCredentials>?>(null) }
    var error by remember { mutableStateOf(false) }
    LaunchedEffect(open, revision) { if (open) receipts = withContext(Dispatchers.IO) { URLDeliveryOutbox(context).receipts() } }
    md.vox.android.ui.SignalNavRow(
        title = voxString("URL delivery recovery"),
        icon = Icons.Outlined.Sync,
        onClick = { open = true },
    )
    if (open) AlertDialog(onDismissRequest = { open = false }, title = { Text(voxString("URL Deliveries")) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (receipts.isEmpty()) Text(voxString("No URL deliveries"))
            if (error) Text(voxString("The delivery could not be updated. Try again."), color = MaterialTheme.colorScheme.error)
            receipts.forEach { item ->
                Text(item.origin, style = md.vox.android.ui.SignalType.rowTitle)
                Text(
                    voxFormat("%@ · %lld attempts", urlDeliveryPhaseText(item.phase).localized(), item.attempts),
                    style = md.vox.android.ui.SignalType.monoCaption,
                    color = md.vox.android.ui.Signal.colors.muted,
                )
                if (item.code != null) Text(voxFormat("HTTP %lld", item.code), style = md.vox.android.ui.SignalType.monoCaption, color = md.vox.android.ui.Signal.colors.error)
                if (item.phase in setOf(URLDeliveryPhase.FAILED, URLDeliveryPhase.UNKNOWN)) {
                    TextButton(onClick = { scope.launch {
                        runCatching { withContext(Dispatchers.IO) { URLDeliveryOutbox(context).pendingCredentials(item.id) } }
                            .onSuccess { authorizing = item.id to it }.onFailure { error = true }
                    } }) { Text(voxString("Update delivery credentials")) }
                }
                if (item.phase in setOf(URLDeliveryPhase.FAILED, URLDeliveryPhase.UNKNOWN) && item.attempts < item.maxAttempts) {
                    TextButton(onClick = { confirming = item }) { Text(voxString("Retry delivery")) }
                }
                if (item.phase !in setOf(URLDeliveryPhase.SENDING, URLDeliveryPhase.DELIVERED, URLDeliveryPhase.DISCARDED)) {
                    TextButton(onClick = { scope.launch {
                        runCatching { withContext(Dispatchers.IO) { URLDeliveryOutbox(context).discard(item.id) } }.onFailure { error = true }
                        revision++
                    } }) { Text(voxString("Discard delivery")) }
                }
                md.vox.android.ui.SignalDivider()
            }
        }
    }, confirmButton = { TextButton(onClick = { revision++ }) { Text(voxString("Refresh")) } }, dismissButton = { TextButton(onClick = { open = false }) { Text(voxString("Close")) } })
    authorizing?.let { (id, initial) ->
        URLDeliveryCredentialsDialog(initial, onDismiss = { authorizing = null }) { credentials ->
            withContext(Dispatchers.IO) { URLDeliveryOutbox(context).reauthorize(id, credentials) }
            authorizing = null; revision++
        }
    }
    confirming?.let { item -> AlertDialog(onDismissRequest = { confirming = null }, title = { Text(voxString("Retry URL delivery?")) },
        text = { Text(voxString("The endpoint may already have received this capture. Check it before retrying. The same idempotency key will be reused, but duplicate prevention depends on the endpoint.")) },
        confirmButton = { TextButton(onClick = { scope.launch {
            runCatching { withContext(Dispatchers.IO) { URLDeliveryOutbox(context).retry(item.id) } }.onFailure { error = true }
            confirming = null; revision++
        } }) { Text(voxString("Retry delivery")) } }, dismissButton = { TextButton(onClick = { confirming = null }) { Text(voxString("Cancel")) } }) }
}

private fun urlDeliveryPhaseText(phase: URLDeliveryPhase): VoxUiText = when (phase) {
    URLDeliveryPhase.QUEUED -> voxUiText("Queued")
    URLDeliveryPhase.SENDING -> voxUiText("Sending")
    URLDeliveryPhase.DELIVERED -> voxUiText("Delivered")
    URLDeliveryPhase.FAILED -> voxUiText("Failed")
    URLDeliveryPhase.UNKNOWN -> voxUiText("Outcome unknown")
    URLDeliveryPhase.DISCARDED -> voxUiText("Discarded")
}
