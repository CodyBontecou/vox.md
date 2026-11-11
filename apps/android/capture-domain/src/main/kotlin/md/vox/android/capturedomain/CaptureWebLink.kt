package md.vox.android.capturedomain

import java.net.URI
import java.util.Locale

/** The same admission rule for typed, pasted, shared, and persisted capture links. */
object CaptureWebLink {
    const val MAX_CHARACTERS = 8_192

    fun normalize(value: String?): String? {
        val text = value?.trim()?.takeIf { it.isNotEmpty() && it.length <= MAX_CHARACTERS } ?: return null
        return runCatching {
            val uri = URI(text)
            val scheme = uri.scheme?.lowercase(Locale.ROOT)
            if (scheme !in setOf("http", "https") || uri.host.isNullOrBlank()) return null
            // Preserve path case, escapes, query, and fragment exactly as supplied.
            scheme + text.substring(requireNotNull(uri.scheme).length)
        }.getOrNull()
    }
}
