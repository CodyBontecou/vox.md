package md.vox.android.capturedomain

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

enum class CaptureRailSide { LEFT, RIGHT }
enum class CaptureTimestampFormat(val wireName: String, val pattern: String) {
    TWELVE_HOUR("12-hour", "h:mm a yyyy-MM-dd"),
    TWENTY_FOUR_HOUR("24-hour", "HH:mm yyyy-MM-dd");
    fun render(epochMillis: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        DateTimeFormatter.ofPattern(pattern, Locale.US).withZone(zone).format(Instant.ofEpochMilli(epochMillis))
    companion object {
        fun fromWireName(value: String?): CaptureTimestampFormat = entries.firstOrNull { it.wireName == value } ?: TWELVE_HOUR
    }
}

/** One safe component. The actual encoded extension wins; token replacement is single-pass. */
object CaptureAudioFilename {
    fun render(template: String, id: String, epochMillis: Long, preset: String, original: String,
        sourceExtension: String = "wav", zone: ZoneId = ZoneId.systemDefault()): String? {
        if (template.isBlank()) return null
        val stamp = DateTimeFormatter.ofPattern("yyyy-MM-dd-HHmmss", Locale.US).withZone(zone).format(Instant.ofEpochMilli(epochMillis))
        val tokens = mapOf("timestamp" to stamp, "date" to stamp.take(10), "time" to stamp.takeLast(6),
            "YR" to stamp.substring(2,4), "id" to id.lowercase(Locale.ROOT), "id8" to id.take(8).lowercase(Locale.ROOT),
            "preset" to preset, "original" to original.substringBeforeLast('.', original))
        var rendered = Regex("\\{(timestamp|date|time|YR|id8|id|preset|original)\\}").replace(template.trim()) { tokens.getValue(it.groupValues[1]) }
        if ('.' in rendered) rendered = rendered.substringBeforeLast('.')
        val cleaned = buildString {
            rendered.codePoints().forEach { code ->
                val type = Character.getType(code)
                val unsafe = (code <= 0xFFFF && code.toChar() in "/\\?%*|\"<>:") || Character.isISOControl(code) ||
                    (type == Character.FORMAT.toInt() && code != 0x200D && code !in 0xE0020..0xE007F)
                if (unsafe || Character.isWhitespace(code)) append('-') else appendCodePoint(code)
            }
        }.trim('-', '.', '_')
        // Never split a Unicode code point, surrogate pair or an emoji joiner sequence.
        val iterator = java.text.BreakIterator.getCharacterInstance(Locale.ROOT).apply { setText(cleaned) }
        var end = 0; var boundary = iterator.next()
        while (boundary != java.text.BreakIterator.DONE && cleaned.substring(0,boundary).toByteArray(Charsets.UTF_8).size <= 180) {
            end = boundary; boundary = iterator.next()
        }
        var base = cleaned.substring(0,end).trim('-', '.', '_')
        while (base.endsWith("\u200D")) base = base.dropLast(1)
        if (base.isBlank()) base = "recording-$stamp-${id.take(8)}"
        val ext = sourceExtension.filter(Char::isLetterOrDigit).take(12).lowercase(Locale.ROOT)
        return if (ext.isEmpty()) base else "$base.$ext"
    }
}

enum class PresetWidgetSource { FOLLOW_CAPTURE_BAR, CUSTOM }
data class PresetWidgetSelection(val source: PresetWidgetSource = PresetWidgetSource.FOLLOW_CAPTURE_BAR,
    val slots: List<String?> = List(6) { null })
enum class PresetWidgetAvailability { AVAILABLE, DISABLED, MISSING, EMPTY }
data class PresetWidgetTile(val slot: Int, val presetID: String?, val name: String?, val emoji: String?, val availability: PresetWidgetAvailability)
object PresetWidgetResolver {
    fun resolve(selection: PresetWidgetSelection, presets: List<CapturePreset>, small: Boolean): List<PresetWidgetTile> {
        val ids = if (selection.source == PresetWidgetSource.CUSTOM) selection.slots.take(6) else
            presets.filter { it.isEnabled && it.isPinned }.sortedBy { it.name.lowercase(Locale.ROOT) }.take(6).map { it.id }
        return (if (small) ids.take(1) else ids).mapIndexed { index, id ->
            val preset = presets.firstOrNull { it.id == id }
            PresetWidgetTile(index,id,preset?.name,preset?.emoji,when {
                id == null -> PresetWidgetAvailability.EMPTY
                preset == null -> PresetWidgetAvailability.MISSING
                !preset.isEnabled -> PresetWidgetAvailability.DISABLED
                else -> PresetWidgetAvailability.AVAILABLE
            })
        }
    }
}
