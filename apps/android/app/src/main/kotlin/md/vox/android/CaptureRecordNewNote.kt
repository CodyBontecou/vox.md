package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.NoteAdd
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** Width of the record-new-note segment at Speak's trailing end; the label centres in the rest. */
internal val RecordNewNoteWidth = 52.dp

/**
 * Whether Speak shows its record-new-note segment. Android Live Notes is always on, so
 * the one thing Speak can't do on its own is leave the open note: it shows only while a
 * note is open to leave (on a blank note Speak already records into a new note), and is
 * hidden while a recording runs, is being transcribed or needs attention, and while Speak
 * is unavailable.
 */
internal fun showsRecordNewNoteButton(voiceIdle: Boolean, speakEnabled: Boolean, canRecordNewNote: Boolean): Boolean =
    voiceIdle && speakEnabled && canRecordNewNote

/**
 * A note is open to leave when the footer offers New (or Done) and it is enabled: the
 * note has words, a link or an attachment and nothing is being sent.
 */
internal fun canRecordIntoNewNote(offersNewNote: Boolean, hasContent: Boolean, isSending: Boolean): Boolean =
    offersNewNote && hasContent && !isSending

/**
 * One tap: close the open note like New, open a blank note and record into it. It sits
 * inside Speak's capsule behind a divider, as part of Speak rather than a second Speak
 * button, and is its own button outside Speak's press area. Tapping the rest of Speak
 * still records into the open note. There are no other choices and no menu.
 */
@Composable
internal fun RecordNewNoteButton(
    contentColor: Color,
    recordIntoNewNote: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val label = voxString("Record into a new note")
    Row(
        modifier = modifier
            .width(RecordNewNoteWidth)
            .fillMaxHeight()
            .clickable(role = Role.Button, onClickLabel = label, onClick = recordIntoNewNote)
            .semantics { contentDescription = label }
            .testTag("capture-speak-record-new-note"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(1.dp).height(22.dp).background(contentColor.copy(alpha = 0.25f)))
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            // iOS: SF Symbol note.text.badge.plus; NoteAdd is the Material equivalent.
            Icon(Icons.AutoMirrored.Outlined.NoteAdd, contentDescription = null, tint = contentColor, modifier = Modifier.size(22.dp))
        }
    }
}
