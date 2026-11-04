package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalRouteTile
import md.vox.android.ui.SignalRouteTone
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalTextFieldColors

/**
 * "Add to Capture" sheet shown when something is shared into Vox.md (the Share target
 * board): the shared item, an optional note, the Capture Preset choice and Send.
 * Cancel keeps the shared content in the composer draft so nothing is lost.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun ShareCaptureSheet(
    sharedText: String,
    sharedURL: String?,
    attachmentCount: Int,
    presets: List<CapturePreset>,
    activePresetID: String?,
    isSending: Boolean,
    selectPreset: (String) -> Unit,
    send: (note: String) -> Unit,
    dismiss: () -> Unit,
) {
    val c = Signal.colors
    var note by rememberSaveable { mutableStateOf("") }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = dismiss,
        sheetState = sheetState,
        containerColor = c.card,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        modifier = Modifier.testTag("share-capture-sheet"),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(start = 20.dp, end = 20.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = dismiss) {
                    Text(voxString("Cancel"), style = MaterialTheme.typography.labelMedium, color = c.tint)
                }
                Text(
                    voxString("Add to Capture"),
                    style = MaterialTheme.typography.titleMedium,
                    color = c.text,
                    modifier = Modifier.weight(1f).semantics { heading() },
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                TextButton(
                    onClick = { send(note.trim()) },
                    enabled = !isSending && (sharedText.isNotBlank() || sharedURL != null || attachmentCount > 0 || note.isNotBlank()),
                ) {
                    Text(voxString("Send"), style = MaterialTheme.typography.labelMedium)
                }
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(c.cardLowest)
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(
                    Modifier.size(48.dp).clip(RoundedCornerShape(12.dp)).background(c.wellHigh),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(if (sharedURL != null) Icons.Outlined.Link else Icons.Outlined.Description, contentDescription = null, tint = c.muted)
                }
                Column(Modifier.weight(1f)) {
                    val headline = sharedText.lineSequence().firstOrNull(String::isNotBlank)?.trim()
                    if (headline != null) {
                        Text(headline, style = MaterialTheme.typography.titleSmall, color = c.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    sharedURL?.let {
                        Text(it, style = SignalType.monoCaption, color = c.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (attachmentCount > 0) {
                        Text(voxFormat("%lld attachments", attachmentCount), style = SignalType.caption, color = c.muted)
                    }
                }
            }
            OutlinedTextField(
                value = note,
                onValueChange = { note = it.take(4_000) },
                label = { Text(voxString("Add a note")) },
                minLines = 2,
                maxLines = 5,
                shape = RoundedCornerShape(12.dp),
                colors = signalTextFieldColors(),
                modifier = Modifier.fillMaxWidth(),
            )
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(voxString("Capture Preset"), style = MaterialTheme.typography.labelMedium, color = c.muted)
                val presetLabel = voxString("Capture Preset")
                FlowRow(
                    modifier = Modifier.selectableGroup().semantics { contentDescription = presetLabel },
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    presets.filter(CapturePreset::isEnabled).forEachIndexed { index, preset ->
                        val selected = preset.id == activePresetID
                        val shape = RoundedCornerShape(8.dp)
                        Row(
                            modifier = Modifier
                                .heightIn(min = 40.dp)
                                .clip(shape)
                                .background(if (selected) c.secondarySoft else androidx.compose.ui.graphics.Color.Transparent)
                                .then(if (selected) Modifier else Modifier.border(1.dp, c.border, shape))
                                .selectable(selected = selected, enabled = !isSending, role = Role.RadioButton) { selectPreset(preset.id) }
                                .padding(start = 6.dp, end = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            SignalRouteTile(
                                label = preset.emoji ?: preset.name,
                                size = 26.dp,
                                tone = SignalRouteTone.forIndex(index),
                                circular = true,
                            )
                            Text(
                                preset.name,
                                style = MaterialTheme.typography.labelMedium,
                                color = if (selected) c.secondaryText else c.text,
                                maxLines = 1,
                            )
                        }
                    }
                }
                presets.firstOrNull { it.id == activePresetID }?.let { preset ->
                    val notePath = preset.logicalFolder + "/" + preset.noteNameTemplate
                    Text(
                        notePath,
                        style = SignalType.monoCaption,
                        color = c.muted,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}
