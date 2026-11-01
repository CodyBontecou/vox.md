package md.vox.android

import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.platformservices.TranscriptionUsageState
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** Exercises checkout affordances without launching a store flow or charging an account. */
class BillingUiInstrumentationTest {
    @get:Rule val compose = createComposeRule()
    private val available = BillingUiState(connectionPhase=BillingConnectionPhase.READY,productAvailable=true,formattedPrice="$4.99")

    @Test fun checkoutAndRestoreStayDisabledWhilePurchaseFlowIsOpen() {
        var state by mutableStateOf(available)
        var launches = 0
        compose.setContent { VoxTheme { UpgradeScreen(state,ActivityStats.Empty,TranscriptionUsageState(0),{},
            purchase={ launches++;state=state.copy(isPurchasing=true) },restore={}) } }
        compose.onNodeWithText("Unlock for $4.99").performScrollTo().performClick()
        compose.onNodeWithText("Waiting for Google Play…").assertIsNotEnabled()
        compose.onNodeWithText("Restore Purchase").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1,launches) }
        compose.runOnIdle { state=state.copy(isPurchasing=false,lastOutcome=BillingActionOutcome.CANCELLED) }
        compose.onNodeWithText("Unlock for $4.99").assertIsEnabled()
    }
    @Test fun restoreHasExplicitBusyAndNoPurchaseFoundStates() {
        var state by mutableStateOf(available)
        var restores = 0
        compose.setContent { VoxTheme { UpgradeScreen(state,ActivityStats.Empty,TranscriptionUsageState(0),{},
            purchase={},restore={ restores++;state=state.copy(isRestoring=true) }) } }
        compose.onNodeWithText("Restore Purchase").performScrollTo().performClick()
        compose.onNodeWithText("Restoring purchase…").assertIsNotEnabled()
        compose.onNodeWithText("Unlock for $4.99").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1,restores);state=state.copy(isRestoring=false,lastOutcome=BillingActionOutcome.NOT_FOUND) }
        compose.onNodeWithText("No Vox.md Unlimited purchase was found for this Google Play account.").assertExists()
        compose.onNodeWithText("Restore Purchase").assertIsEnabled()
    }
    @Test fun unacknowledgedPurchaseKeepsAccessAndExposesRestoreRecovery() {
        val state=available.copy(entitlement=VoxEntitlement.UNLIMITED,lastOutcome=BillingActionOutcome.PURCHASED,statusCode="acknowledge:2")
        compose.setContent { VoxTheme { UpgradeScreen(state,ActivityStats.Empty,TranscriptionUsageState(0),{},purchase={},restore={}) } }
        compose.onNodeWithText("Your purchase is active, but Google Play has not acknowledged it yet. Restore while connected to retry confirmation.").assertExists()
        compose.onNodeWithText("Restore Purchase").performScrollTo().assertIsEnabled()
        compose.onNodeWithText("Unlimited Active").assertIsNotEnabled()
    }
    @Test fun pendingAndOwnedStatesPreventRepurchaseAndPreserveRestore() {
        var state by mutableStateOf(available.copy(entitlement=VoxEntitlement.PENDING,hasPendingPurchase=true))
        compose.setContent { VoxTheme { UpgradeScreen(state,ActivityStats.Empty,TranscriptionUsageState(0),{},purchase={},restore={}) } }
        compose.onNodeWithText("Purchase Pending").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("Restore Purchase").assertIsEnabled()
        compose.runOnIdle { state=available.copy(entitlement=VoxEntitlement.UNLIMITED,isEntitlementStale=true) }
        compose.onNodeWithText("Unlimited Active").assertIsNotEnabled()
        compose.onNodeWithText("Unlimited is active from this installation’s last verified Google Play purchase. Connect to Play to refresh its status.").assertExists()
    }
}
