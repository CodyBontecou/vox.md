package md.vox.android

import android.content.Context
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import java.util.Locale
import md.vox.android.ui.LocalSignalColors

/**
 * Signal redesign stories for the keyboard area. Story ids use the
 * "keyboard-" prefix; launch with
 * `adb shell am start -n md.vox.android/.VisualStoryActivity --es story <id> --ez dark <bool>`.
 * Returns false when [story] is not one of these.
 *
 * Each story hosts the production [VoxKeyboardPanel] (the exact view the IME returns from
 * onCreateInputView) under a host-app text field, driven into one state through the same
 * calls VoxInputMethodService makes.
 */
@Composable
internal fun KeyboardStories(story: String): Boolean {
    when (story) {
        "keyboard-idle" -> KeyboardStory { panel, t -> panel.showVoiceState(t("On-device voice"), false, KeyboardVoiceMode.IDLE) }
        "keyboard-shifted" -> KeyboardStory(shifted = true) { panel, t ->
            panel.showVoiceState(t("On-device voice"), false, KeyboardVoiceMode.IDLE)
        }
        "keyboard-symbols" -> KeyboardStory(symbols = true) { panel, t ->
            panel.showVoiceState(t("On-device voice"), false, KeyboardVoiceMode.IDLE)
        }
        "keyboard-recording" -> KeyboardStory(fieldText = "Follow up with Dana about") { panel, _ ->
            // Live preview text is shown verbatim (not localized), as in the service.
            panel.showVoiceState("…the Thursday launch checklist", true, KeyboardVoiceMode.LISTENING)
        }
        "keyboard-processing" -> KeyboardStory(fieldText = "Follow up with Dana about") { panel, t ->
            panel.showVoiceState(t("Transcribing on device…"), true, KeyboardVoiceMode.PROCESSING)
        }
        "keyboard-saving" -> KeyboardStory(fieldText = "Follow up with Dana about") { panel, t ->
            panel.showVoiceState(t("Saving voice recording…"), true, KeyboardVoiceMode.PROCESSING)
            panel.setVoiceEnabled(false)
        }
        "keyboard-permission-needed" -> KeyboardStory { panel, t ->
            panel.showVoiceState(t("Open Vox.md to allow microphone access"), false, KeyboardVoiceMode.ERROR)
        }
        "keyboard-no-model" -> KeyboardStory { panel, t ->
            panel.showVoiceState(t("Install and select a local model in Vox.md"), false, KeyboardVoiceMode.ERROR)
        }
        "keyboard-sensitive-field" -> KeyboardStory(fieldText = "••••••••") { panel, _ -> panel.showSensitiveField() }
        "keyboard-recovered-text" -> KeyboardStory { panel, _ -> panel.showRecoveredText() }
        else -> return false
    }
    return true
}

@Composable
private fun KeyboardStory(
    fieldText: String = "",
    shifted: Boolean = false,
    symbols: Boolean = false,
    configure: (panel: VoxKeyboardPanel, localize: (String) -> String) -> Unit,
) {
    val colors = LocalSignalColors.current
    Column(Modifier.fillMaxSize().background(colors.bg)) {
        // Host app: one focused text field above the docked keyboard.
        Box(
            Modifier
                .statusBarsPadding()
                .padding(16.dp)
                .fillMaxWidth()
                .height(96.dp)
                .background(colors.card, RoundedCornerShape(16.dp))
                .border(1.dp, colors.border, RoundedCornerShape(16.dp))
                .padding(16.dp),
        ) {
            Text(
                fieldText.ifEmpty { "Message" },
                color = if (fieldText.isEmpty()) colors.muted else colors.text,
                fontSize = 16.sp,
            )
        }
        Box(Modifier.weight(1f))
        AndroidView(
            modifier = Modifier.fillMaxWidth().background(colors.bg).navigationBarsPadding(),
            factory = { context ->
                val themed = nightContext(context, colors.isDark)
                val locale = themed.resources.configuration.locales[0] ?: Locale.ENGLISH
                val localize: (String) -> String = { RuntimeLocalization.translate(themed, locale, it) }
                VoxKeyboardPanel(
                    context = themed,
                    localize = localize,
                    onKey = {},
                    onDeleteLongPress = {},
                    onVoice = {},
                ).apply {
                    rebuildKeyRows(shifted, symbols)
                    configure(this, localize)
                }.root
            },
        )
    }
}

/** Views resolve `values-night` from their Context, so follow the story's dark flag explicitly. */
private fun nightContext(base: Context, dark: Boolean): Context {
    val configuration = Configuration(base.resources.configuration).apply {
        uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            (if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO)
    }
    return ContextThemeWrapper(base, android.R.style.Theme_DeviceDefault_DayNight).apply {
        applyOverrideConfiguration(configuration)
    }
}
