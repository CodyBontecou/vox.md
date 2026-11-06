package md.vox.android

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import md.vox.android.capturedomain.CaptureDestination

/**
 * Signal redesign stories for first run. Story ids use the "onboarding-" prefix; launch with
 * `adb shell am start -n md.vox.android/.VisualStoryActivity --es story <id> --ez dark <bool>`.
 * Returns false when [story] is not one of these.
 */
@Composable
internal fun OnboardingStories(story: String): Boolean {
    when (story) {
        // Welcome renders the always-dark artboard in either appearance.
        "onboarding-welcome" -> OnboardingWelcomeScreen(onGetStarted = {})
        // Setup before a folder is chosen: Choose card and the folder hint under the routes.
        "onboarding-setup" -> SetupStory(destination = null)
        // Setup board state: folder chosen, default starter routes (Journal off).
        "onboarding-setup-folder" -> SetupStory(destination = STORY_DESTINATION)
        "onboarding-setup-installing" -> SetupStory(destination = STORY_DESTINATION, isBusy = true)
        "onboarding-setup-error" -> SetupStory(
            destination = STORY_DESTINATION,
            notice = "That folder could not be used. Choose another folder.",
        )
        "onboarding-repair" -> VaultSetupScreen(
            notice = "Folder access changed. Your capture is saved locally; choose the folder again to continue.",
            onChooseFolder = {},
        )
        "onboarding-folder-missing" -> VaultSetupScreen(notice = null, onChooseFolder = {})
        "onboarding-loading" -> LoadingScreen()
        else -> return false
    }
    return true
}

private val STORY_DESTINATION = CaptureDestination(
    id = "6f0d7c1e-2b9a-4c1e-9d3f-5a7b8c9d0e1f",
    displayName = "Vox Notes",
    treeUri = "content://md.vox.android.test.documents/tree/vault",
)

@Composable
private fun SetupStory(destination: CaptureDestination?, isBusy: Boolean = false, notice: String? = null) {
    var selection by remember { mutableStateOf(StarterRoute.defaultSelection) }
    OnboardingSetupScreen(
        destination = destination,
        notice = notice,
        selection = selection,
        isBusy = isBusy,
        onToggle = { route -> selection = if (route in selection) selection - route else selection + route },
        onChooseFolder = {},
        onStartCapturing = {},
    )
}
