package md.vox.android

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import java.util.IllegalFormatException
import java.util.Locale
import org.json.JSONObject

internal data class VoxUiText(
    val source: String,
    val arguments: List<Any> = emptyList(),
)

internal fun voxUiText(source: String, vararg arguments: Any): VoxUiText =
    VoxUiText(source, arguments.toList())

@Composable
internal fun VoxUiText.localized(): String {
    val localizedArguments = arguments.map { argument ->
        if (argument is VoxUiText) argument.localized() else argument
    }
    return if (localizedArguments.isEmpty()) {
        voxString(source)
    } else {
        voxFormat(source, *localizedArguments.toTypedArray())
    }
}

@Composable
internal fun voxString(source: String): String {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val locale = configuration.locales[0] ?: Locale.ENGLISH
    return remember(source, locale.toLanguageTag()) {
        RuntimeLocalization.translate(context, locale, source)
    }
}

@Composable
internal fun voxFormat(source: String, vararg arguments: Any): String {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val locale = configuration.locales[0] ?: Locale.ENGLISH
    return remember(source, locale.toLanguageTag(), arguments.toList()) {
        RuntimeLocalization.format(context, locale, source, *arguments)
    }
}

internal fun appleFormatToJava(format: String): String = format
    .replace(Regex("%((?:\\d+\\$)?)(?:lld|ld)"), "%$1d")
    .replace(Regex("%((?:\\d+\\$)?)@"), "%$1s")

internal fun formatLocalized(format: String, locale: Locale, vararg arguments: Any): String =
    formatLocalized(format, format, locale, *arguments)

internal fun formatLocalized(
    format: String,
    fallbackFormat: String,
    locale: Locale,
    vararg arguments: Any,
): String =
    try {
        String.format(locale, appleFormatToJava(format), *arguments)
    } catch (_: IllegalFormatException) {
        String.format(Locale.ENGLISH, appleFormatToJava(fallbackFormat), *arguments)
    }

internal object RuntimeLocalization {
    @Volatile private var cached: Map<String, Map<String, String>>? = null

    fun translate(context: Context, locale: Locale, source: String): String {
        val localeTable = load(context)
        val candidates = listOf(
            locale.toLanguageTag(),
            locale.language + locale.script.takeIf(String::isNotBlank)?.let { "-$it" }.orEmpty(),
            locale.language,
        ).distinct()
        return candidates.firstNotNullOfOrNull { localeTable[it]?.get(source) } ?: source
    }

    fun format(context: Context, locale: Locale, source: String, vararg arguments: Any): String =
        formatLocalized(translate(context, locale, source), source, locale, *arguments)

    private fun load(context: Context): Map<String, Map<String, String>> = cached ?: synchronized(this) {
        cached ?: runCatching {
            val root = context.resources.openRawResource(R.raw.vox_runtime_localizations)
                .bufferedReader(Charsets.UTF_8)
                .use { JSONObject(it.readText()) }
            root.keys().asSequence().associateWith { locale ->
                val translations = root.getJSONObject(locale)
                translations.keys().asSequence().associateWith(translations::getString)
            }
        }.getOrDefault(emptyMap()).also { cached = it }
    }
}
