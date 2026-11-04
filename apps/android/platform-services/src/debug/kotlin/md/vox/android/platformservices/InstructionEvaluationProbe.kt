package md.vox.android.platformservices

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Debug-only access for the public fictional evaluation corpus. Never ships in release. */
object InstructionEvaluationProbe {
    suspend fun candidate(context: Context, source: String, instruction: String): String = withContext(Dispatchers.IO) {
        val model = requireNotNull(InstructionModelManager.get(context).verifiedModel())
        NativeInstructionRuntime.generate(model.absolutePath, LocalIntelligenceProcessor.SYSTEM.toByteArray(Charsets.UTF_8),
            instructionModelPrompt(source, instruction).toByteArray(Charsets.UTF_8), 1024, 90_000, Long.MAX_VALUE)
            .toString(Charsets.UTF_8)
    }
}
