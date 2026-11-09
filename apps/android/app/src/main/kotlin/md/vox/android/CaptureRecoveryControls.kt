package md.vox.android

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import md.vox.android.capturedomain.*
import md.vox.android.ui.*
import java.util.UUID

/** Recovery has explicit confirmation; dismissal and editing never call the repository. */
@Composable
internal fun CaptureRecoveryControls(
    requestID: String,
    updatedAt: Long,
    isBusy: Boolean,
    presets: List<CapturePreset>,
    destination: CaptureDestination?,
    loadContext: suspend (String) -> CaptureRecoveryContext?,
    replace: (CaptureRecoveryCommand) -> Unit,
) {
    val context by produceState<CaptureRecoveryContext?>(null, requestID, updatedAt, isBusy) {
        value = runCatching { loadContext(requestID) }.getOrNull()
    }
    var form by rememberSaveable(requestID, stateSaver = listSaver(
        save = { it.encode() }, restore = { CaptureRecoveryForm.decode(it) },
    )) { mutableStateOf(CaptureRecoveryForm(UUID.randomUUID().toString().lowercase())) }
    val current = context ?: return
    if (current.replacementRequestID != null) {
        Text(voxString("A recovery decision is saved. Retry delivery to continue it."), color = Signal.colors.muted)
        return
    }
    current.missingHeading?.let { heading ->
        Text(voxFormat("Heading not found: %@", "#".repeat(heading.level) + " " + heading.title), color = Signal.colors.error)
        SignalButton(text = voxString("Create Heading"), enabled = current.canReplace && !isBusy && current.sourceDestinationID != null,
            onClick = { form = form.review(current, CaptureRecoveryTarget.Heading(heading.title, heading.level, true)) })
        SignalButton(text = voxString("Use another heading"), enabled = current.canReplace && !isBusy && current.sourceDestinationID != null,
            variant = SignalButtonVariant.SECONDARY,
            onClick = { form = form.copy(stage = "heading", title = heading.title, level = heading.level, create = false) })
    }
    SignalButton(text = voxString("Send to Inbox"), enabled = current.canReplace && !isBusy && destination != null,
        variant = SignalButtonVariant.SECONDARY,
        onClick = { destination?.let { form = form.review(current, CaptureRecoveryTarget.Inbox(it.id)).copy(destinationName = it.displayName) } })
    SignalButton(text = voxString("Send to another route"), enabled = current.canReplace && !isBusy,
        variant = SignalButtonVariant.SECONDARY, onClick = { form = form.copy(stage = "routes") })
    if (!current.canReplace) Text(voxString("This capture cannot be replaced safely right now."), color = Signal.colors.muted)

    if (form.stage == "routes") AlertDialog(
        onDismissRequest = { form = form.cancel() }, title = { Text(voxString("Send to another route")) },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) {
            presets.forEach { preset ->
                val vault = preset.destination ?: destination
                TextButton(enabled = preset.isEnabled && !preset.urlDelivery.enabled && vault != null && !isBusy,
                    onClick = { vault?.let { form = form.review(current, CaptureRecoveryTarget.Route(preset.id, preset.revision, it.id)).copy(destinationName = it.displayName, targetName = preset.name) } }) {
                    Text(preset.name + if (!preset.isEnabled || preset.urlDelivery.enabled || vault == null) " · " + voxString("Unavailable — choose another route") else " · " + vault.displayName)
                }
            }
        } }, confirmButton = {}, dismissButton = { TextButton(onClick = { form = form.cancel() }) { Text(voxString("Cancel")) } },
    )
    if (form.stage == "heading") AlertDialog(
        onDismissRequest = { form = form.cancel() }, title = { Text(voxString("Use another heading")) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(value = form.title, onValueChange = { form = form.copy(title = it.take(256)) }, label = { Text(voxString("Heading")) }, singleLine = true)
            Row(Modifier.horizontalScroll(rememberScrollState())) { (1..6).forEach { level -> TextButton(onClick = { form = form.copy(level = level) }) { Text(if (level == form.level) "[$level]" else "$level") } } }
            Text(voxString("The heading must already exist at this level. Nothing will be appended if it is missing."))
        } },
        confirmButton = { TextButton(enabled = form.title.isNotBlank() && !isBusy, onClick = {
            form = form.review(current, CaptureRecoveryTarget.Heading(form.title, form.level, false))
        }) { Text(voxString("Continue")) } }, dismissButton = { TextButton(onClick = { form = form.cancel() }) { Text(voxString("Cancel")) } },
    )
    if (form.stage == "confirm") AlertDialog(
        onDismissRequest = { if (!isBusy) form = form.cancel() }, title = { Text(voxString("Confirm recovery")) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val targetLabel = when (form.kind) {
                "inbox" -> voxString("Inbox")
                "route" -> form.targetName.ifBlank { voxString("Unavailable — choose another route") }
                else -> "#".repeat(form.level.coerceIn(1, 6)) + " " + form.title
            }
            Text(targetLabel, style = MaterialTheme.typography.titleMedium)
            Text(voxFormat("Vault: %@", form.destinationName.ifBlank { voxString("Unavailable — choose another route") }))
            Text(voxString("The saved text, attachments and formatting are kept. Only this capture’s destination or heading changes. The original stays in Library."))
        } },
        confirmButton = { TextButton(enabled = !isBusy && form.commandOrNull() != null, onClick = { form.commandOrNull()?.let(replace) }) { Text(voxString("Send")) } },
        dismissButton = { TextButton(enabled = !isBusy, onClick = { form = form.cancel() }) { Text(voxString("Cancel")) } },
    )
}
