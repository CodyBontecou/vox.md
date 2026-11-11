package md.vox.android.capturedomain

/** Shared admission rules for route editor fields and repository writes. */
object CapturePresetPaths {
    fun folder(value: String, allowEmpty: Boolean = false): String? {
        val segments = segments(value)
        return segments.takeIf {
            it.size in (if (allowEmpty) 0 else 1)..31 && it.all(::safeSegment)
        }?.joinToString("/")
    }

    fun filename(value: String): String? = value.trim().takeIf {
        it.length in 1..128 && it.endsWith(".md", ignoreCase = true) &&
            it.none { c -> c == '/' || c == '\\' || c == '\u0000' }
    }

    fun existingNote(value: String): String? {
        val segments = segments(value)
        return segments.takeIf {
            it.size in 1..32 && it.all(::safeSegment) && it.last().endsWith(".md", ignoreCase = true)
        }?.joinToString("/")
    }

    private fun segments(value: String): List<String> =
        value.split('/').map(String::trim).filter(String::isNotEmpty)

    private fun safeSegment(value: String): Boolean =
        value.length in 1..255 && value !in setOf(".", "..") &&
            value.none { it == '/' || it == '\\' || it == '\u0000' }
}
