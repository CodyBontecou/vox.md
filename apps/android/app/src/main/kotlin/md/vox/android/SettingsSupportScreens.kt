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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.os.LocaleListCompat
import md.vox.android.ui.GeistMonoFontFamily

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
internal fun AppLanguageSettingsScreen(navigateBack: () -> Unit) {
    val context = LocalContext.current
    var selection by remember { mutableStateOf(AppLanguage.current()) }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { SupportTopBar(stringResource(R.string.app_language_title), navigateBack) },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            AppLanguage.entries.forEachIndexed { index, language ->
                ListItem(
                    headlineContent = {
                        Text(if (language == AppLanguage.SYSTEM) stringResource(R.string.app_language_system) else language.nativeDisplayName)
                    },
                    supportingContent = if (language == AppLanguage.SYSTEM) {
                        { Text(stringResource(R.string.app_language_follows_device)) }
                    } else {
                        null
                    },
                    trailingContent = {
                        if (language == selection) {
                            Icon(Icons.Outlined.Check, contentDescription = stringResource(R.string.selected))
                        }
                    },
                    colors = androidx.compose.material3.ListItemDefaults.colors(
                        containerColor = MaterialTheme.colorScheme.background,
                    ),
                    modifier = Modifier.clickable {
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
                    },
                )
                if (index < AppLanguage.entries.lastIndex) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                }
            }
            Text(
                stringResource(R.string.app_language_applies_immediately),
                modifier = Modifier.padding(20.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
internal fun DebugLogScreen(navigateBack: () -> Unit) {
    val context = LocalContext.current
    var logText by remember { mutableStateOf(PrivacySafeDebugLog.read(context)) }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            DebugLogTopBar(
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
        },
    ) { padding ->
        Text(
            logText.ifBlank { "(empty)" },
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            style = MaterialTheme.typography.bodySmall.copy(fontFamily = GeistMonoFontFamily),
            color = MaterialTheme.colorScheme.onBackground,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DebugLogTopBar(
    navigateBack: () -> Unit,
    refresh: () -> Unit,
    copy: () -> Unit,
    clear: () -> Unit,
) {
    TopAppBar(
        title = { Text(voxString("Debug Log"), style = MaterialTheme.typography.titleLarge) },
        navigationIcon = {
            IconButton(onClick = navigateBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = voxString("Back"))
            }
        },
        actions = {
            IconButton(onClick = refresh) { Icon(Icons.Outlined.Refresh, contentDescription = voxString("Refresh")) }
            IconButton(onClick = copy) { Icon(Icons.Outlined.ContentCopy, contentDescription = voxString("Copy")) }
            IconButton(onClick = clear) { Icon(Icons.Outlined.DeleteOutline, contentDescription = voxString("Clear")) }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SupportTopBar(title: String, navigateBack: () -> Unit) {
    TopAppBar(
        title = { Text(title, style = MaterialTheme.typography.titleLarge) },
        navigationIcon = {
            IconButton(onClick = navigateBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = voxString("Back"))
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
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
