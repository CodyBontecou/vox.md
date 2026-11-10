package md.vox.android

import md.vox.android.capturedomain.*
import org.junit.Assert.*
import org.junit.Test

class CaptureRecoveryFormTest {
    private val id = "11111111-1111-4111-8111-111111111111"
    private val intent = "22222222-2222-4222-8222-222222222222"
    private val vault = "33333333-3333-4333-8333-333333333333"
    private val context = CaptureRecoveryContext(id, "a".repeat(64), 5, vault, true, "Reviewed vault")

    @Test fun recreationRetainsExactlyReviewedIdentitySelectorAndSourceFrontier() {
        val form = CaptureRecoveryForm(intent).review(context, CaptureRecoveryTarget.Heading("Chosen heading", 3, false))
        val restored = CaptureRecoveryForm.decode(form.encode())!!
        assertEquals(form.commandOrNull(), restored.commandOrNull())
        assertEquals(intent, restored.commandOrNull()!!.intentID)
        assertEquals(5, restored.commandOrNull()!!.context.revision)
        assertEquals(CaptureRecoveryTarget.Heading("Chosen heading", 3, false), restored.commandOrNull()!!.target)
        assertEquals("Reviewed vault", restored.destinationName)
    }
    @Test fun inboxAndOtherRouteDecisionsKeepTheReviewedVaultAndRevision() {
        for (target in listOf(CaptureRecoveryTarget.Inbox(vault), CaptureRecoveryTarget.Route(id, 7, vault))) {
            val reviewed = CaptureRecoveryForm(intent).review(context, target)
            assertEquals(target, CaptureRecoveryForm.decode(reviewed.encode())!!.commandOrNull()!!.target)
            assertEquals(context.requestSHA256, reviewed.commandOrNull()!!.context.requestSHA256)
        }
    }
    @Test fun cancelAndIncompleteEditsNeverProduceARecoveryCommand() {
        val form = CaptureRecoveryForm(intent).review(context, CaptureRecoveryTarget.Inbox(vault))
        assertNull(form.cancel().commandOrNull())
        assertNull(CaptureRecoveryForm(intent, stage = "heading", title = "Draft only").commandOrNull())
        assertNull(CaptureRecoveryForm.decode(listOf("corrupt")))
        assertNull(form.copy(sourceHash = "bad").commandOrNull())
        assertNull(form.copy(kind = "heading", title = "Missing", level = 7).commandOrNull())
    }
    @Test fun nonDefaultSourceVaultNameSurvivesRecreationAndUnknownNamesDisableSend() {
        val sourceVault = "44444444-4444-4444-8444-444444444444"
        val reviewed = CaptureRecoveryForm(intent).review(context.copy(sourceDestinationID = sourceVault, sourceDestinationName = "Private work vault"),
            CaptureRecoveryTarget.Heading("Chosen heading", 2, true))
        val restored = CaptureRecoveryForm.decode(reviewed.encode())!!
        assertEquals("Private work vault", restored.destinationName)
        assertEquals(sourceVault, restored.commandOrNull()!!.context.sourceDestinationID)
        assertNotEquals(vault, restored.commandOrNull()!!.context.sourceDestinationID)
        assertNull(restored.copy(destinationName = "").commandOrNull())
        val route = CaptureRecoveryForm(intent).review(context, CaptureRecoveryTarget.Route(id, 7, vault))
            .copy(targetName = "Reviewed route", destinationName = "Reviewed target vault")
        val reopened = CaptureRecoveryForm.decode(route.encode())!!
        assertEquals("Reviewed route", reopened.targetName)
        assertEquals("Reviewed target vault", reopened.destinationName)
        assertEquals(7, (reopened.commandOrNull()!!.target as CaptureRecoveryTarget.Route).revision)
    }

    @Test fun refreshingLiveContextDoesNotRebindAnAlreadyReviewedDecision() {
        val form = CaptureRecoveryForm(intent).review(context, CaptureRecoveryTarget.Inbox(vault))
        val refreshed = context.copy(revision = 8, requestSHA256 = "b".repeat(64))
        assertNotEquals(refreshed.revision, form.commandOrNull()!!.context.revision)
        assertEquals(5, CaptureRecoveryForm.decode(form.encode())!!.commandOrNull()!!.context.revision)
    }
}
