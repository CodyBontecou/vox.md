package md.vox.android.platformservices

import java.text.Normalizer
import java.util.Locale
import kotlinx.serialization.json.*

data class InstructionEvaluationCase(
    val id: String, val instruction: String, val source: String,
    val containsAll: List<String>, val containsAny: List<List<String>>,
    val ordered: List<String>, val maximumWords: Int, val outputFormat: String, val forbiddenTerms: List<String>, val speakerOwnership: Map<String, List<String>>,
)

/** Shared corpus semantics: fail closed on missing, oversized or fact-losing output. */
object IntelligenceEvaluation {
    fun instructionCases(json: String): List<InstructionEvaluationCase> = Json.parseToJsonElement(json).jsonObject
        .getValue("instructionCases").jsonArray.map { element ->
            val row = element.jsonObject
            fun strings(key: String) = row.getValue(key).jsonArray.map { it.jsonPrimitive.content }
            InstructionEvaluationCase(row.getValue("id").jsonPrimitive.content,
                row.getValue("instruction").jsonPrimitive.content, row.getValue("source").jsonPrimitive.content,
                strings("containsAll"), row.getValue("containsAny").jsonArray.map { group -> group.jsonArray.map { it.jsonPrimitive.content } },
                strings("ordered"), row.getValue("maximumWords").jsonPrimitive.int, row.getValue("outputFormat").jsonPrimitive.content, strings("forbiddenTerms"),
                row.getValue("speakerOwnership").jsonObject.mapValues { (_, terms) -> terms.jsonArray.map { it.jsonPrimitive.content } })
        }

    fun passes(case: InstructionEvaluationCase, response: String): Boolean {
        val normalized = normalize(response)
        if (normalized.isBlank() || normalized.split(Regex("\\s+")).size > case.maximumWords) return false
        if (case.outputFormat == "one-term-per-line" && response.trim().lines().filter(String::isNotBlank).map(::normalize) != case.ordered.map(::normalize)) return false
        if (case.outputFormat == "comma-separated-terms" && response.split(',').map(::normalize) != case.containsAll.map(::normalize)) return false
        if (case.outputFormat !in setOf("free-form", "one-term-per-line", "comma-separated-terms")) return false
        if (case.containsAll.any { normalize(it) !in normalized }) return false
        if (case.containsAny.any { group -> group.none { normalize(it) in normalized } }) return false
        if (case.forbiddenTerms.any { Regex("\\b" + Regex.escape(normalize(it)) + "\\b").containsMatchIn(normalized) }) return false
        for ((label, terms) in case.speakerOwnership) {
            val start = response.indexOf(label)
            if (start < 0) return false
            val rest = response.substring(start + label.length)
            val next = Regex("Speaker \\d+:").find(rest)?.range?.first ?: rest.length
            val attributed = normalize(rest.substring(0, next))
            if (terms.any { normalize(it) !in attributed }) return false
        }
        var position = 0
        for (term in case.ordered) {
            val next = normalized.indexOf(normalize(term), position)
            if (next < 0) return false
            position = next + normalize(term).length
        }
        return true
    }

    /** Duration-weighted attribution error after the best one-to-one label permutation.
     * Missing/extra predicted turns, non-finite weights and >8 labels fail closed.
     */
    fun speakerAttributionError(reference: List<String>, predicted: List<String>, durations: List<Double>): Double {
        if (reference.isEmpty() || reference.size != predicted.size || durations.size != reference.size ||
            durations.any { !it.isFinite() || it <= 0 } || predicted.any(String::isBlank)) return 1.0
        val truth = reference.distinct()
        val labels = predicted.distinct()
        if (truth.size > 8 || labels.size > 8) return 1.0
        var best = 0.0
        fun assign(index: Int, mapping: Map<String, String>, used: Set<String>) {
            if (index == labels.size) {
                val correct = reference.indices.sumOf { if (mapping[predicted[it]] == reference[it]) durations[it] else 0.0 }
                best = maxOf(best, correct)
                return
            }
            for (speaker in truth.filterNot(used::contains)) assign(index + 1, mapping + (labels[index] to speaker), used + speaker)
            // Extra predicted labels are scored as errors, never merged to inflate quality.
            assign(index + 1, mapping, used)
        }
        assign(0, emptyMap(), emptySet())
        return 1.0 - best / durations.sum()
    }

    private fun normalize(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFKC).lowercase(Locale.ROOT).trim()
}
