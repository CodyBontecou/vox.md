package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine

class LiveNotesTest {
    private val inbox = LiveNoteLocation("22222222-2222-4222-8222-222222222222", "content://vault/tree", "Inbox/Radiator follow-up.md")

    @Test fun savingWritesTheWholeFileWhenTheVersionStillMatches() {
        val store = FakeStore().apply { put(inbox, "# Radiator\n") }
        val binding = bindingFor(store, inbox)
        val outcome = blocking { LiveNoteSync.save(store, binding, "# Radiator\nCalled the office.\n") }
        outcome as LiveNoteSyncOutcome.Saved
        assertEquals("# Radiator\nCalled the office.\n", store.text(inbox))
        assertEquals("# Radiator\nCalled the office.\n", outcome.binding.savedText)
        assertTrue(outcome.binding.version.sameContentAs(store.version(inbox)))
        assertEquals(1, store.writes)
    }

    @Test fun versionMismatchWithoutLocalEditsReloadsSilently() {
        val store = FakeStore().apply { put(inbox, "# Radiator\n") }
        val binding = bindingFor(store, inbox)
        store.put(inbox, "# Radiator\n- [ ] Call landlord back Friday\n") // edited in Obsidian
        val outcome = blocking { LiveNoteSync.refresh(store, binding, localText = binding.savedText) }
        outcome as LiveNoteSyncOutcome.Reloaded
        assertEquals("# Radiator\n- [ ] Call landlord back Friday\n", outcome.text)
        assertEquals(outcome.text, outcome.binding.savedText)
        assertEquals(0, store.writes)
    }

    @Test fun versionMismatchWithLocalEditsPausesInAConflictAndWritesNothing() {
        val store = FakeStore().apply { put(inbox, "# Radiator\n- [ ] Move bookshelf\n") }
        val binding = bindingFor(store, inbox)
        store.put(inbox, "# Radiator\n- [ ] Move bookshelf\n- [ ] Call landlord back Friday\n")
        val mine = "# Radiator\n- [ ] Move bookshelf and the plant stand\n"
        val outcome = blocking { LiveNoteSync.save(store, binding, mine) }
        outcome as LiveNoteSyncOutcome.Conflicted
        assertEquals(mine, outcome.conflict.mine)
        assertEquals(LiveNoteDiffLine(LiveNoteDiffKind.ADDED, "- [ ] Call landlord back Friday"), outcome.conflict.summary.first())
        assertEquals("# Radiator\n- [ ] Move bookshelf\n- [ ] Call landlord back Friday\n", store.text(inbox))
        assertEquals(0, store.writes)
        val session = LiveNoteSession(binding = binding, localText = mine, conflict = outcome.conflict)
        assertEquals(LiveNoteStatus.CONFLICT, session.status)
    }

    @Test fun conflictResolutionsKeepTheirsMineOrACopy() {
        val store = FakeStore().apply { put(inbox, "base\n") }
        val binding = bindingFor(store, inbox)
        store.put(inbox, "theirs\n")
        val conflict = (blocking { LiveNoteSync.save(store, binding, "mine\n") } as LiveNoteSyncOutcome.Conflicted).conflict

        val theirs = LiveNoteSync.useTheirs(binding, conflict)
        assertEquals("theirs\n", theirs.text)

        val copy = blocking { LiveNoteSync.saveCopy(store, binding, conflict) } as LiveNoteSyncOutcome.Saved
        assertEquals("Inbox/Radiator follow-up (Vox).md", copy.binding.location.relativePath)
        assertEquals("mine\n", store.text(copy.binding.location))
        assertEquals("theirs\n", store.text(inbox))

        val kept = blocking { LiveNoteSync.keepMine(store, binding, conflict) } as LiveNoteSyncOutcome.Saved
        assertEquals("mine\n", store.text(inbox))
        assertEquals("mine\n", kept.binding.savedText)
    }

    @Test fun unreachableVaultKeepsEditsLocalAndReportsOffline() {
        val store = FakeStore().apply { put(inbox, "# Packing list\n") }
        val binding = bindingFor(store, inbox)
        store.reachable = false
        val edited = "# Packing list\nCharger, passport\n"
        assertEquals(LiveNoteSyncOutcome.Unreachable, blocking { LiveNoteSync.save(store, binding, edited) })
        assertEquals(LiveNoteSyncOutcome.Unreachable, blocking { LiveNoteSync.refresh(store, binding, edited) })
        val session = LiveNoteSession(binding = binding, localText = edited, isUnreachable = true)
        assertEquals(LiveNoteStatus.OFFLINE, session.status)
        assertTrue(session.hasUnsavedEdits)

        store.reachable = true
        val back = blocking { LiveNoteSync.refresh(store, binding, edited) } as LiveNoteSyncOutcome.Saved
        assertEquals(edited, store.text(inbox))
        assertEquals(edited, back.binding.savedText)
    }

    @Test fun firstWriteForANewFilePresetBindsToTheRenderedFile() {
        val pending = LiveNotePendingWrite("33333333-3333-4333-8333-333333333333", "Called the building office", "p", "Inbox", isAppendTarget = false, prefersLastOccurrence = true, plannedPath = "Inbox/{title}.md")
        val file = file(inbox, "Called the building office\n")
        val bound = LiveNoteSync.bindFirstWrite(pending, file, currentText = "Called the building office")
        assertEquals("Called the building office\n", bound.editorText)
        assertFalse(bound.needsSave)
        assertFalse(bound.binding.isAppendTarget)
        assertEquals(inbox, bound.binding.location)
        assertEquals(pending.requestID, bound.binding.requestID)

        // Words typed while the first write was queued replace the entry in place.
        val later = LiveNoteSync.bindFirstWrite(pending, file, currentText = "Called the building office about the radiator")
        assertEquals("Called the building office about the radiator\n", later.editorText)
        assertTrue(later.needsSave)
        assertEquals(LiveNoteRange(0, "Called the building office about the radiator".length), later.entryRange)
    }

    @Test fun firstWriteForAnAppendPresetShowsTheWholeFileAndHighlightsTheEntry() {
        val daily = inbox.copy(relativePath = "Daily/2026-11-13.md")
        val existing = "---\ntags: [daily]\n---\n# Thursday\n## Log\n- 09:12 Standup moved\n"
        val rendered = existing + "- 14:05 Idea: the composer is the file\n"
        val pending = LiveNotePendingWrite("44444444-4444-4444-8444-444444444444", "Idea: the composer is the file", "d", "Daily log", isAppendTarget = true, prefersLastOccurrence = true, plannedPath = "Daily/{date}.md")
        val bound = LiveNoteSync.bindFirstWrite(pending, file(daily, rendered), currentText = "Idea: the composer is the file")
        assertEquals(rendered, bound.editorText)
        assertTrue(bound.binding.isAppendTarget)
        val range = requireNotNull(bound.entryRange)
        assertEquals("Idea: the composer is the file", bound.editorText.substring(range.start, range.end))
        assertEquals(rendered, bound.binding.savedText)
    }

    @Test fun newNoteReleasesTheBindingAndNamesTheFileForTheToast() {
        val store = FakeStore().apply { put(inbox, "# Radiator\n") }
        val session = LiveNoteSession(binding = bindingFor(store, inbox), localText = "# Radiator\n")
        assertEquals(LiveNoteStatus.SAVED, session.status)
        val release = session.released()
        assertEquals("Radiator follow-up", release.title)
        assertEquals("Inbox", release.presetName)
        assertEquals("Inbox/Radiator follow-up.md", release.relativePath)
        assertEquals(session.binding, release.binding)
        assertNull(release.next.binding)
        assertEquals(LiveNoteStatus.BLANK, release.next.status)
        assertFalse(release.next.isStarted)
        assertTrue(release.next.parked.isEmpty())
    }

    @Test fun releasingWithUnwrittenEditsParksThemInsteadOfDroppingThem() {
        val store = FakeStore().apply { put(inbox, "# Packing list\n") }
        val offline = LiveNoteSession(binding = bindingFor(store, inbox), localText = "# Packing list\nCharger\n", isUnreachable = true)
        val release = offline.released()
        assertEquals(LiveNoteStatus.BLANK, release.next.status)
        assertEquals("# Packing list\nCharger\n", release.next.parked.single().localText)
        assertEquals(inbox, release.next.parked.single().binding?.location)
    }

    @Test fun deletedElsewhereWhileEditingIsWrittenBack() {
        val store = FakeStore().apply { put(inbox, "a\n") }
        val binding = bindingFor(store, inbox)
        store.files.remove(inbox.relativePath)
        val saved = blocking { LiveNoteSync.save(store, binding, "a\nb\n") } as LiveNoteSyncOutcome.Saved
        assertEquals("a\nb\n", store.text(inbox))
        assertEquals("a\nb\n", saved.binding.savedText)
    }

    @Test fun planPreviewAndCopyNames() {
        val preset = CapturePreset("p", "Inbox", "tray", revision = 1, logicalFolder = "Inbox", noteNameTemplate = "{title}", metadataFields = emptyList())
        assertEquals("Inbox/{title}.md", LiveNotePlan.plannedPath(preset, null))
        assertFalse(LiveNotePlan.isAppendTarget(preset, null))
        assertTrue(LiveNotePlan.isAppendTarget(preset.copy(noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE), null))
        assertEquals("Journal/Today.md", LiveNotePlan.plannedPath(preset, CaptureRouteOverride("Journal/Today.md")))
        assertTrue(LiveNotePlan.isAppendTarget(preset, CaptureRouteOverride("Journal/Today.md")))
        assertEquals("Note (Vox).md", LiveNotePlan.copyName("Note.md", emptySet()))
        assertEquals("Note (Vox 3).md", LiveNotePlan.copyName("Note.md", setOf("Note (Vox).md", "Note (Vox 2).md")))
    }

    @Test fun vaultTreeSortsFoldersFirstAndBadgesPresetTargets() {
        val entries = listOf(
            VaultEntry("b.md", "b.md", false, lastModifiedEpochMillis = 1),
            VaultEntry("Inbox", "Inbox", true),
            VaultEntry(".obsidian", ".obsidian", true),
            VaultEntry("a.md", "a.md", false, lastModifiedEpochMillis = 5),
            VaultEntry("Daily", "Daily", true),
        )
        assertEquals(listOf("Daily", "Inbox", "a.md", "b.md"), VaultTree.sorted(entries).map(VaultEntry::name))
        val inboxPreset = CapturePreset("p", "Inbox", "tray", revision = 1, logicalFolder = "Inbox", noteNameTemplate = "{title}", metadataFields = emptyList())
        val tasks = inboxPreset.copy(id = "t", name = "Tasks", noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE, existingNotePath = "Tasks.md")
        val targets = VaultTree.presetTargets(listOf(inboxPreset, tasks), null)
        assertEquals(listOf("Inbox"), targets["Inbox"]?.map(CapturePreset::name))
        assertEquals(listOf("Tasks"), targets["Tasks.md"]?.map(CapturePreset::name))
    }

    private fun bindingFor(store: FakeStore, location: LiveNoteLocation) = LiveNoteBinding(
        location = location,
        presetID = "p",
        presetName = "Inbox",
        requestID = null,
        isAppendTarget = false,
        version = store.version(location),
        savedText = store.text(location)!!,
    )

    private fun file(location: LiveNoteLocation, text: String) = LiveNoteFile(location, text, versionOf(text))

    private class FakeStore : LiveNoteFileStore {
        val files = linkedMapOf<String, String>()
        var reachable = true
        var writes = 0

        fun put(location: LiveNoteLocation, text: String) { files[location.relativePath] = text }
        fun text(location: LiveNoteLocation): String? = files[location.relativePath]
        fun version(location: LiveNoteLocation): LiveNoteVersion = versionOf(files.getValue(location.relativePath))

        override suspend fun read(location: LiveNoteLocation): LiveNoteReadResult {
            if (!reachable) return LiveNoteReadResult.Unreachable("permissionLost")
            val text = files[location.relativePath] ?: return LiveNoteReadResult.Missing
            return LiveNoteReadResult.Found(LiveNoteFile(location, text, versionOf(text)))
        }

        override suspend fun replace(location: LiveNoteLocation, text: String, expected: LiveNoteVersion?): LiveNoteWriteResult {
            if (!reachable) return LiveNoteWriteResult.Unreachable("permissionLost")
            val current = files[location.relativePath]
            if (current == null && expected != null) return LiveNoteWriteResult.Missing
            if (current != null && (expected == null || !versionOf(current).sameContentAs(expected))) {
                return LiveNoteWriteResult.Changed(LiveNoteFile(location, current, versionOf(current)))
            }
            files[location.relativePath] = text
            writes += 1
            return LiveNoteWriteResult.Written(versionOf(text))
        }

        override suspend fun createCopy(location: LiveNoteLocation, text: String): LiveNoteCopyResult {
            if (!reachable) return LiveNoteCopyResult.Unreachable("permissionLost")
            val occupied = files.keys.filter { it.substringBeforeLast('/', "") == location.folderSegments.joinToString("/") }
                .map { it.substringAfterLast('/') }.toSet()
            val target = location.sibling(LiveNotePlan.copyName(location.fileName, occupied))
            files[target.relativePath] = text
            return LiveNoteCopyResult.Created(target, versionOf(text))
        }
    }

    private companion object {
        fun versionOf(text: String): LiveNoteVersion {
            val bytes = text.toByteArray(Charsets.UTF_8)
            val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            return LiveNoteVersion(hash, bytes.size.toLong())
        }

        /** The fake store never suspends, so the coroutine finishes before this returns. */
        fun <T> blocking(block: suspend () -> T): T {
            var outcome: Result<T>? = null
            block.startCoroutine(Continuation(EmptyCoroutineContext) { outcome = it })
            return requireNotNull(outcome) { "suspended unexpectedly" }.getOrThrow()
        }
    }
}
