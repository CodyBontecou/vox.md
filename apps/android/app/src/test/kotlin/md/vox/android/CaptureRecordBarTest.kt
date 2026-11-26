package md.vox.android

import androidx.compose.ui.AbsoluteAlignment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tester feedback on iOS 3.0.5 (2026-11-26), ported to Android: with the route rail on the
 * header stops repeating every route, and Speak's options chevron replaces a separate
 * "record new note" button. These cover the decisions behind both.
 */
class CaptureRecordBarTest {
    private val routes = listOf(
        CaptureRoutePill("inbox", "Inbox", null),
        CaptureRoutePill("work", "Work", null),
        CaptureRoutePill("journal", "Journal", "📓"),
    )

    @Test
    fun railIsOffByDefaultAndReadsOnlyKnownPlacements() {
        assertEquals(CaptureRouteRailPlacement.OFF, CaptureRouteRailPlacement.fromPersistedName(null))
        assertEquals(CaptureRouteRailPlacement.OFF, CaptureRouteRailPlacement.fromPersistedName("top"))
        assertEquals(CaptureRouteRailPlacement.LEFT, CaptureRouteRailPlacement.fromPersistedName("left"))
        assertEquals(CaptureRouteRailPlacement.RIGHT, CaptureRouteRailPlacement.fromPersistedName("right"))
        // Same raw values as iOS CaptureRouteRailPlacement.
        assertEquals(listOf("off", "left", "right"), CaptureRouteRailPlacement.entries.map { it.persistedName })
    }

    @Test
    fun railKeepsItsPhysicalEdgeInEveryLayoutDirection() {
        assertEquals(AbsoluteAlignment.BottomLeft, CaptureRouteRailPlacement.LEFT.alignment)
        assertEquals(AbsoluteAlignment.BottomRight, CaptureRouteRailPlacement.RIGHT.alignment)
    }

    @Test
    fun railIsDrawnOnPhonesWithTheSettingOnAndTwoOrMoreRoutes() {
        assertTrue(showsRouteRail(CaptureRouteRailPlacement.LEFT, isPhone = true, routeCount = 3))
        assertTrue(showsRouteRail(CaptureRouteRailPlacement.RIGHT, isPhone = true, routeCount = 2))
        assertFalse(showsRouteRail(CaptureRouteRailPlacement.OFF, isPhone = true, routeCount = 3))
        assertFalse(showsRouteRail(CaptureRouteRailPlacement.LEFT, isPhone = false, routeCount = 3))
        assertFalse(showsRouteRail(CaptureRouteRailPlacement.LEFT, isPhone = true, routeCount = 1))
    }

    @Test
    fun railReplacesHeaderPillsOnlyWhenItIsDrawn() {
        assertTrue(routeRailReplacesHeaderPills(railShown = true, routeCount = 3))
        // The rail draws nothing for a single route, so the header keeps it.
        assertFalse(routeRailReplacesHeaderPills(railShown = true, routeCount = 1))
        assertFalse(routeRailReplacesHeaderPills(railShown = false, routeCount = 3))
    }

    @Test
    fun headerKeepsOnlySelectedPillWithItsRouteTone() {
        val only = visibleRoutePills(routes, selectedID = "work", showsOnlySelected = true)
        assertEquals(listOf("work"), only.map { it.value.id })
        // Same position as in the rail, so the tile keeps the rail's tone.
        assertEquals(listOf(1), only.map { it.index })

        val all = visibleRoutePills(routes, selectedID = "work", showsOnlySelected = false)
        assertEquals(listOf("inbox", "work", "journal"), all.map { it.value.id })
        assertEquals(listOf(0, 1, 2), all.map { it.index })

        // An unknown selection still leaves the header one pill to show.
        assertEquals(listOf("inbox"), visibleRoutePills(routes, selectedID = "gone", showsOnlySelected = true).map { it.value.id })
    }

    @Test
    fun railTapSelectsOnlyAnotherListedRouteWhileEnabled() {
        assertTrue(routeRailSelects("work", selectedID = "inbox", enabled = true, routes = routes))
        assertFalse("Current route is a no-op", routeRailSelects("inbox", selectedID = "inbox", enabled = true, routes = routes))
        assertFalse(routeRailSelects("missing", selectedID = "inbox", enabled = true, routes = routes))
        assertFalse("Busy or recording", routeRailSelects("work", selectedID = "inbox", enabled = false, routes = routes))
    }

    @Test
    fun speakOptionsShowOnlyWhenThereIsANoteToLeave() {
        // A note is open: record into this note or a new one.
        assertTrue(speakOptionsMenuOffers(voiceIdle = true, speakEnabled = true, canRecordNewNote = true))
        // A blank note: Speak already records into a new note.
        assertFalse(speakOptionsMenuOffers(voiceIdle = true, speakEnabled = true, canRecordNewNote = false))
        // Recording, transcribing or needing attention: Speak is the stop/status control.
        assertFalse(speakOptionsMenuOffers(voiceIdle = false, speakEnabled = true, canRecordNewNote = true))
        // Microphone off or sending.
        assertFalse(speakOptionsMenuOffers(voiceIdle = true, speakEnabled = false, canRecordNewNote = true))
    }

    @Test
    fun aNoteIsOpenToLeaveWhenNewIsOfferedAndEnabled() {
        assertTrue(canRecordIntoNewNote(offersNewNote = true, hasContent = true, isSending = false))
        assertFalse(canRecordIntoNewNote(offersNewNote = true, hasContent = false, isSending = false))
        assertFalse(canRecordIntoNewNote(offersNewNote = true, hasContent = true, isSending = true))
        assertFalse(canRecordIntoNewNote(offersNewNote = false, hasContent = true, isSending = false))
    }

    @Test
    fun headerPillsAlwaysIncludeTheSelectedRoute() {
        assertEquals(listOf("default"), captureRoutePills(null, emptyList()).map { it.id })
    }
}
