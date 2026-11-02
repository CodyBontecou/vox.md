package md.vox.android

import androidx.compose.runtime.Composable

/**
 * Signal redesign stories for first run. Story ids use the "onboarding-" prefix; launch with
 * `adb shell am start -n md.vox.android/.VisualStoryActivity --es story <id> --ez dark <bool>`.
 * Returns false when [story] is not one of these.
 */
@Composable
internal fun OnboardingStories(story: String): Boolean {
    when (story) {
        // First run renders the always-dark Welcome artboard in either appearance.
        "onboarding-welcome" -> VaultSetupScreen(notice = null, onChooseFolder = {})
        "onboarding-repair" -> VaultSetupScreen(
            notice = "Folder access changed. Your capture is saved locally; choose the folder again to continue.",
            onChooseFolder = {},
        )
        "onboarding-loading" -> LoadingScreen()
        else -> return false
    }
    return true
}
