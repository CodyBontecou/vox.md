package md.vox.android.platformservices

import java.util.Locale

data class TranscriptMetadata(
    val title: String,
    val tags: List<String>,
    val category: String,
)

/** Grounded fallback metadata derived only from words already present in the transcript. */
object DeterministicTranscriptEnrichment {
    fun enrich(transcript: String): TranscriptMetadata {
        val normalized = transcript.trim()
        val title = normalized.lineSequence().firstOrNull(String::isNotBlank).orEmpty()
            .split(TITLE_END).firstOrNull().orEmpty().trim().take(MAX_TITLE_CHARACTERS)
            .ifBlank { "Voice Transcript" }
        val words = WORD.findAll(normalized.lowercase(Locale.ROOT)).map(MatchResult::value).toList()
        val firstPosition = mutableMapOf<String, Int>()
        val counts = mutableMapOf<String, Int>()
        words.forEachIndexed { index, word ->
            if (word.length >= 4 && word !in STOP_WORDS) {
                firstPosition.putIfAbsent(word, index)
                counts[word] = counts.getOrDefault(word, 0) + 1
            }
        }
        val tags = counts.keys.sortedWith(
            compareByDescending<String> { counts.getValue(it) }.thenBy { firstPosition.getValue(it) },
        ).take(MAX_TAGS)
        val category = when {
            words.any { it in TASK_WORDS } -> "Tasks"
            words.any { it in MEETING_WORDS } -> "Meetings"
            words.any { it in IDEA_WORDS } -> "Ideas"
            else -> "Notes"
        }
        return TranscriptMetadata(title, tags, category)
    }

    private const val MAX_TITLE_CHARACTERS = 96
    private const val MAX_TAGS = 5
    private val TITLE_END = Regex("(?<=[.!?])\\s+")
    private val WORD = Regex("[\\p{L}\\p{N}][\\p{L}\\p{N}'’-]*")
    private val TASK_WORDS = setOf("todo", "task", "deadline", "due", "must", "should")
    private val MEETING_WORDS = setOf("meeting", "agenda", "attendees", "minutes", "discussed")
    private val IDEA_WORDS = setOf("idea", "concept", "brainstorm", "hypothesis")
    private val STOP_WORDS = setOf(
        "about", "after", "again", "also", "because", "before", "being", "could", "from", "have",
        "into", "just", "more", "some", "that", "their", "there", "these", "they", "this", "those",
        "through", "very", "what", "when", "where", "which", "while", "with", "would", "your",
    )
}
