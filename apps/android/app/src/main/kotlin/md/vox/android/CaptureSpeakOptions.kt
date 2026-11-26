package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.NoteAdd
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import md.vox.android.ui.Signal

/** Width of Speak's trailing options chevron; the capsule's label centres in what is left. */
internal val SpeakOptionsWidth = 52.dp

/**
 * Speak's options chevron (port of iOS, tester feedback 2026-11-26: a separate "record new
 * note" button read as a second Speak button). Android Live Notes is always on, so the only
 * choice the menu holds is which note to record into. It shows only while a note is open to
 * leave: on a blank note Speak already records into a new note. It is hidden while a
 * recording runs, is being transcribed or needs attention, and while Speak is unavailable.
 */
internal fun speakOptionsMenuOffers(voiceIdle: Boolean, speakEnabled: Boolean, canRecordNewNote: Boolean): Boolean =
    voiceIdle && speakEnabled && canRecordNewNote

/**
 * A note is open to leave when the footer offers New (or Done) and it is enabled: the
 * note has words, a link or an attachment and nothing is being sent.
 */
internal fun canRecordIntoNewNote(offersNewNote: Boolean, hasContent: Boolean, isSending: Boolean): Boolean =
    offersNewNote && hasContent && !isSending

/**
 * The chevron at Speak's trailing end. It is its own button, outside Speak's press area,
 * so opening the menu never starts a recording. Both items are actions, not a mode.
 */
@Composable
internal fun SpeakOptionsButton(
    contentColor: Color,
    recordIntoThisNote: () -> Unit,
    recordIntoNewNote: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val label = voxString("Recording options")
    Box(modifier) {
        Row(
            modifier = Modifier
                .width(SpeakOptionsWidth)
                .fillMaxHeight()
                .clickable(role = Role.Button, onClickLabel = label) { expanded = true }
                .semantics { contentDescription = label }
                .testTag("capture-speak-options"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(1.dp).height(22.dp).background(contentColor.copy(alpha = 0.25f)))
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null, tint = contentColor, modifier = Modifier.size(22.dp))
            }
        }
        CaptureSignalMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            // The menu is its own popup window, which does not inherit the activity's
            // testTagsAsResourceId, so UI tests could not find the items by tag.
            Column(Modifier.semantics { testTagsAsResourceId = true }) {
            SpeakOptionsItem(
                text = voxString("Record into this note"),
                icon = { Icon(Icons.Outlined.MicNone, contentDescription = null, tint = Signal.colors.text) },
                tag = "capture-speak-record-this-note",
            ) {
                expanded = false
                recordIntoThisNote()
            }
            SpeakOptionsItem(
                text = voxString("Record into a new note"),
                icon = { Icon(Icons.AutoMirrored.Outlined.NoteAdd, contentDescription = null, tint = Signal.colors.text) },
                tag = "capture-speak-record-new-note",
            ) {
                expanded = false
                recordIntoNewNote()
            }
            }
        }
    }
}

@Composable
private fun SpeakOptionsItem(text: String, icon: @Composable () -> Unit, tag: String, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text, style = MaterialTheme.typography.bodyLarge) },
        leadingIcon = icon,
        onClick = onClick,
        colors = MenuDefaults.itemColors(textColor = Signal.colors.text),
        modifier = Modifier.testTag(tag),
    )
}
