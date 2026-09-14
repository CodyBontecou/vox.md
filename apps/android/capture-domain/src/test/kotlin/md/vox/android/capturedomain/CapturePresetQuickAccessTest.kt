package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CapturePresetQuickAccessTest {
    private fun preset(
        id: String,
        name: String = id,
        isPinned: Boolean = false,
        isEnabled: Boolean = true,
    ) = CapturePreset(
        id = id,
        name = name,
        symbol = "tray",
        revision = 1,
        logicalFolder = "Notes",
        noteNameTemplate = "{date}.md",
        metadataFields = emptyList(),
        isEnabled = isEnabled,
        isPinned = isPinned,
    )

    private fun collection(vararg presets: CapturePreset, activePresetID: String = "active") =
        CapturePresetCollection(activePresetID = activePresetID, presets = presets.toList())

    @Test fun alternatesKeepEnabledPinsOnlyAndHideThePresetTheSelectorAlreadyShows() {
        val pinnedWork = preset("work", "Work", isPinned = true)
        val pinnedInbox = preset("inbox", "Inbox", isPinned = true)
        val pinnedJournal = preset("journal", "Journal", isPinned = true)
        val plain = preset("tasks")
        val disabledPin = preset("travel", isPinned = true, isEnabled = false)
        val current = preset("active", "Daily", isPinned = true)

        val alternates = CapturePresetQuickAccess.alternatePresets(
            collection(pinnedWork, plain, pinnedInbox, disabledPin, pinnedJournal, current, activePresetID = "active"),
        )

        assertEquals(listOf("inbox", "journal", "work"), alternates.map(CapturePreset::id))
    }

    @Test fun alternatesUseCaseInsensitiveSettingsOrderSoBothSurfacesAgree() {
        val alternates = CapturePresetQuickAccess.alternatePresets(
            collection(
                preset("current", "Daily"),
                preset("zeta", "zebra", isPinned = true),
                preset("Alpha", "Apple", isPinned = true),
                preset("beta", "apple pie", isPinned = true),
            ),
        )
        assertEquals(listOf("Alpha", "beta", "zeta"), alternates.map(CapturePreset::id))
    }

    @Test fun activationRevalidatesSelectionDisabledAndRouteLockState() {
        val collection = collection(
            preset("active", "Daily"),
            preset("inbox", "Inbox"),
            preset("travel", "Travel", isEnabled = false),
        )

        assertTrue(CapturePresetQuickAccess.canActivatePreset(collection, "inbox", routeLocked = false))
        assertFalse(CapturePresetQuickAccess.canActivatePreset(collection, "inbox", routeLocked = true))
        assertFalse(CapturePresetQuickAccess.canActivatePreset(collection, "active", routeLocked = false))
        assertFalse(CapturePresetQuickAccess.canActivatePreset(collection, "travel", routeLocked = false))
        assertFalse(CapturePresetQuickAccess.canActivatePreset(collection, "missing", routeLocked = false))
    }
}
