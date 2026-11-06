package md.vox.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.os.LocaleListCompat
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalGroup
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalRowDivider
import md.vox.android.ui.SignalTopBar
import md.vox.android.ui.SignalType

internal enum class AppLanguage(val languageTag: String?, val nativeDisplayName: String) {
    SYSTEM(null, "System"),
    ARABIC("ar", "العربية"),
    BENGALI("bn", "বাংলা"),
    CHINESE_SIMPLIFIED("zh-Hans", "简体中文"),
    CHINESE_TRADITIONAL("zh-Hant", "繁體中文"),
    DUTCH("nl", "Nederlands"),
    ENGLISH("en", "English"),
    FRENCH("fr", "Français"),
    GERMAN("de", "Deutsch"),
    HINDI("hi", "हिन्दी"),
    INDONESIAN("id", "Bahasa Indonesia"),
    ITALIAN("it", "Italiano"),
    JAPANESE("ja", "日本語"),
    KOREAN("ko", "한국어"),
    POLISH("pl", "Polski"),
    PORTUGUESE_BRAZIL("pt-BR", "Português (Brasil)"),
    RUSSIAN("ru", "Русский"),
    SPANISH("es", "Español"),
    TAMIL("ta", "தமிழ்"),
    THAI("th", "ไทย"),
    TURKISH("tr", "Türkçe"),
    UKRAINIAN("uk", "Українська"),
    URDU("ur", "اردو"),
    VIETNAMESE("vi", "Tiếng Việt");

    companion object {
        fun current(): AppLanguage {
            val tag = AppCompatDelegate.getApplicationLocales().get(0)?.toLanguageTag()
                ?: return SYSTEM
            return entries.firstOrNull { language ->
                language.languageTag.equals(tag, ignoreCase = true)
            } ?: entries
                .filter { it.languageTag != null }
                .maxByOrNull { language ->
                    if (tag.startsWith(requireNotNull(language.languageTag), ignoreCase = true)) {
                        language.languageTag.length
                    } else {
                        -1
                    }
                }
                ?.takeIf { tag.startsWith(requireNotNull(it.languageTag), ignoreCase = true) }
                ?: SYSTEM
        }
    }
}

@Composable
internal fun AppLanguageSettingsScreen(
    navigateBack: () -> Unit,
    initialSelection: AppLanguage = AppLanguage.current(),
) {
    val context = LocalContext.current
    val c = Signal.colors
    var selection by remember { mutableStateOf(initialSelection) }
    Scaffold(
        containerColor = c.bg,
        topBar = { SupportTopBar(stringResource(R.string.app_language_title), navigateBack) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SignalMetrics.PageGutter)
                .padding(top = 4.dp, bottom = 32.dp),
        ) {
            SignalGroup(title = null, footer = stringResource(R.string.app_language_applies_immediately)) {
                AppLanguage.entries.forEachIndexed { index, language ->
                    if (index > 0) SignalRowDivider()
                    val selected = language == selection
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 52.dp)
                            .clickable {
                                if (language == selection) return@clickable
                                selection = language
                                PrivacySafeDebugLog.record(
                                    context,
                                    PrivacySafeDebugLog.Event.APP_LANGUAGE_CHANGED,
                                    mapOf("language" to (language.languageTag ?: "system")),
                                )
                                val locales = language.languageTag?.let(LocaleListCompat::forLanguageTags)
                                    ?: LocaleListCompat.getEmptyLocaleList()
                                AppCompatDelegate.setApplicationLocales(locales)
                            }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                if (language == AppLanguage.SYSTEM) stringResource(R.string.app_language_system) else language.nativeDisplayName,
                                style = SignalType.rowTitle,
                                color = c.text,
                            )
                            if (language == AppLanguage.SYSTEM) {
                                Text(stringResource(R.string.app_language_follows_device), style = SignalType.caption, color = c.muted)
                            }
                        }
                        if (selected) {
                            Icon(
                                Icons.Outlined.Check,
                                contentDescription = stringResource(R.string.selected),
                                tint = c.accentText,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun DebugLogScreen(navigateBack: () -> Unit) {
    val context = LocalContext.current
    var logText by remember { mutableStateOf(PrivacySafeDebugLog.read(context)) }
    DebugLogContent(
        logText = logText,
        navigateBack = navigateBack,
        refresh = { logText = PrivacySafeDebugLog.read(context) },
        copy = {
            context.getSystemService(ClipboardManager::class.java)
                .setPrimaryClip(ClipData.newPlainText("Vox.md Debug Log", logText))
        },
        clear = {
            PrivacySafeDebugLog.clear(context)
            PrivacySafeDebugLog.record(context, PrivacySafeDebugLog.Event.DEBUG_LOG_CLEARED)
            logText = PrivacySafeDebugLog.read(context)
        },
    )
}

/** Stateless Debug Log page so previews and visual stories can supply fixed text. */
@Composable
internal fun DebugLogContent(
    logText: String,
    navigateBack: () -> Unit,
    refresh: () -> Unit,
    copy: () -> Unit,
    clear: () -> Unit,
) {
    val c = Signal.colors
    Scaffold(
        containerColor = c.bg,
        topBar = { DebugLogTopBar(navigateBack = navigateBack, refresh = refresh, copy = copy, clear = clear) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SignalMetrics.PageGutter)
                .padding(top = 4.dp, bottom = 32.dp),
        ) {
            SignalCard(modifier = Modifier.fillMaxWidth(), radius = SignalMetrics.GroupRadius, padding = PaddingValues(14.dp)) {
                Text(
                    logText.ifBlank { "(empty)" },
                    modifier = Modifier.fillMaxWidth(),
                    style = SignalType.mono.copy(fontSize = 12.sp, lineHeight = 18.sp),
                    color = if (logText.isBlank()) c.faint else c.text,
                )
            }
        }
    }
}

@Composable
private fun DebugLogTopBar(
    navigateBack: () -> Unit,
    refresh: () -> Unit,
    copy: () -> Unit,
    clear: () -> Unit,
) {
    SignalTopBar(
        title = voxString("Debug Log"),
        navigateBack = navigateBack,
        backDescription = voxString("Back"),
    ) {
        SignalCircleButton(Icons.Outlined.Refresh, voxString("Refresh"), refresh)
        SignalCircleButton(Icons.Outlined.ContentCopy, voxString("Copy"), copy)
        SignalCircleButton(Icons.Outlined.DeleteOutline, voxString("Clear"), clear, contentColor = Signal.colors.error)
    }
}

@Composable
private fun SupportTopBar(title: String, navigateBack: () -> Unit) {
    SignalTopBar(
        title = title,
        navigateBack = navigateBack,
        backDescription = voxString("Back"),
    )
}

internal fun openDiscord(context: Context) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://discord.gg/RaQYS4t6gn")))
    }
}

internal fun sendFeedback(context: Context) {
    val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
    val versionName = packageInfo.versionName ?: "?"
    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        packageInfo.longVersionCode.toString()
    } else {
        @Suppress("DEPRECATION")
        packageInfo.versionCode.toString()
    }
    val body = """


        ---
        App: Vox.md $versionName ($versionCode)
        Platform: Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})
        Device: ${Build.MANUFACTURER} ${Build.MODEL}
        ---
    """.trimIndent()
    val uri = Uri.parse("mailto:cody@isolated.tech").buildUpon()
        .appendQueryParameter("subject", "Vox.md Feedback")
        .appendQueryParameter("body", body)
        .build()
    runCatching { context.startActivity(Intent(Intent.ACTION_SENDTO, uri)) }
}

internal fun openInputMethodSettings(context: Context) {
    context.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
}

internal fun appVersionString(context: Context): String {
    val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        packageInfo.longVersionCode
    } else {
        @Suppress("DEPRECATION")
        packageInfo.versionCode.toLong()
    }
    return "${packageInfo.versionName ?: "—"} ($versionCode)"
}
