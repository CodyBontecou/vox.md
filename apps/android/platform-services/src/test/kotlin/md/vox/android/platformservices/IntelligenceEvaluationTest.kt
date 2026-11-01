package md.vox.android.platformservices

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class IntelligenceEvaluationTest {
    private val corpus = Json.parseToJsonElement(File("../../../evaluations/local-intelligence/v1/corpus.json").readText()).jsonObject
    @Test fun commonCorpusHasTheSameRequiredCasesAndMutationsOnBothPlatforms() {
        val cases = IntelligenceEvaluation.instructionCases(corpus.toString()).associateBy { it.id }
        assertEquals(setOf("sorted-people", "formal-request", "spanish-extraction", "factual-summary", "link-preservation", "speaker-ownership"), cases.keys)
        for (element in corpus.getValue("scorerExamples").jsonArray) {
            val row=element.jsonObject
            assertEquals(row.toString(),row.getValue("passed").jsonPrimitive.boolean,
                IntelligenceEvaluation.passes(cases.getValue(row.getValue("caseID").jsonPrimitive.content),row.getValue("response").jsonPrimitive.content))
        }
    }
    @Test fun speakerScoringIsPermutationInvariantAndPenalizesCollapseSplitsAndMissingTurns() {
        for (element in corpus.getValue("speakerScorerExamples").jsonArray) {
            val row=element.jsonObject
            fun strings(key:String)=row.getValue(key).jsonArray.map { it.jsonPrimitive.content }
            assertEquals(row.getValue("error").jsonPrimitive.double,
                IntelligenceEvaluation.speakerAttributionError(strings("reference"),strings("predicted"),row.getValue("durations").jsonArray.map { it.jsonPrimitive.double }),0.000001)
        }
        assertEquals(1.0,IntelligenceEvaluation.speakerAttributionError(listOf("a"),listOf("1"),listOf(Double.NaN)),0.0)
    }
}
