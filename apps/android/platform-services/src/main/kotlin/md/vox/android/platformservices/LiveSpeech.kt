package md.vox.android.platformservices

import android.content.Context
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer

enum class LiveSpeechPhase { UNAVAILABLE, STARTING, LISTENING, PAUSED, COMPLETED, FAILED }

data class LiveSpeechState(
    val sessionID: String? = null,
    val phase: LiveSpeechPhase = LiveSpeechPhase.UNAVAILABLE,
    val committedText: String = "",
    val partialText: String = "",
    val droppedBufferCount: Int = 0,
    val failureCode: String? = null,
) {
    val displayText: String get() = mergeLiveSpeechText(committedText, partialText)
}

object LiveSpeechRegistry {
    private val mutableState = MutableStateFlow(LiveSpeechState())
    val state: StateFlow<LiveSpeechState> = mutableState.asStateFlow()

    internal fun publish(value: LiveSpeechState) {
        mutableState.value = value
    }
}

internal fun mergeLiveSpeechText(committed: String, partial: String): String =
    listOf(committed.trim(), partial.trim()).filter(String::isNotEmpty).joinToString(" ")

internal interface RecorderLiveSpeechSession {
    fun offer(bytes: ByteArray, count: Int)
    fun pause()
    fun resume()
    fun finish(shouldDiscard: Boolean)
}

internal fun interface RecorderLiveSpeechFactory {
    fun create(context: Context, sessionID: String): RecorderLiveSpeechSession?
}

internal object RecorderLiveSpeechProvider {
    @Volatile private var factory: RecorderLiveSpeechFactory? = null

    fun install(value: RecorderLiveSpeechFactory) {
        factory = value
    }

    fun create(context: Context, sessionID: String): RecorderLiveSpeechSession? =
        factory?.create(context, sessionID)
}

/** Phone-only opt-in. Wear never references this function, so R8 removes the Vosk implementation. */
fun installLocalLiveSpeechProvider() {
    RecorderLiveSpeechProvider.install(LocalLiveSpeechSession::start)
}

/**
 * Best-effort local preview. PCM is offered only after the recorder writes it to its durable
 * chunk sink; the bounded queue may drop preview buffers but can never delay or alter the
 * authoritative recording used by final transcription.
 */
internal class LocalLiveSpeechSession private constructor(
    private val sessionID: String,
    private val modelDirectory: File,
) : RecorderLiveSpeechSession {
    private val accepting = AtomicBoolean(true)
    private val discarded = AtomicBoolean(false)
    private val paused = AtomicBoolean(false)
    private val droppedBuffers = AtomicInteger(0)
    private val queue = LinkedBlockingQueue<ByteArray>(MAX_QUEUED_BUFFERS)
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "vox-live-speech-${sessionID.take(8)}").apply { isDaemon = true }
    }

    init {
        LiveSpeechRegistry.publish(LiveSpeechState(sessionID, LiveSpeechPhase.STARTING))
        executor.execute(::runInference)
        executor.shutdown()
    }

    override fun offer(bytes: ByteArray, count: Int) {
        if (!accepting.get() || paused.get() || count <= 0) return
        val copy = bytes.copyOf(count)
        if (!queue.offer(copy)) {
            queue.poll()
            droppedBuffers.incrementAndGet()
            queue.offer(copy)
        }
    }

    override fun pause() {
        paused.set(true)
        currentState()?.let { LiveSpeechRegistry.publish(it.copy(phase = LiveSpeechPhase.PAUSED, partialText = "")) }
    }

    override fun resume() {
        paused.set(false)
        currentState()?.let { LiveSpeechRegistry.publish(it.copy(phase = LiveSpeechPhase.LISTENING)) }
    }

    override fun finish(shouldDiscard: Boolean) {
        discarded.set(shouldDiscard)
        accepting.set(false)
        // Final transcription always replays the durable recording. Do not make it compete with
        // stale best-effort preview buffers for a second Vosk model after capture has ended.
        queue.clear()
    }

    private fun runInference() {
        var committed = ""
        try {
            Model(modelDirectory.absolutePath).use { model ->
                Recognizer(model, SAMPLE_RATE.toFloat()).use { recognizer ->
                    LiveSpeechRegistry.publish(LiveSpeechState(sessionID, LiveSpeechPhase.LISTENING))
                    while (accepting.get() || queue.isNotEmpty()) {
                        val bytes = queue.poll(POLL_MILLIS, TimeUnit.MILLISECONDS) ?: continue
                        if (discarded.get()) break
                        if (recognizer.acceptWaveForm(bytes, bytes.size)) {
                            val result = speechText(recognizer.result)
                            if (result.isNotBlank()) committed = appendBounded(committed, result)
                            publish(committed, "")
                        } else {
                            publish(committed, partialSpeechText(recognizer.partialResult))
                        }
                    }
                    if (!discarded.get()) {
                        val final = speechText(recognizer.finalResult)
                        if (final.isNotBlank()) committed = appendBounded(committed, final)
                    }
                }
            }
            if (discarded.get()) {
                LiveSpeechRegistry.publish(LiveSpeechState())
            } else {
                LiveSpeechRegistry.publish(
                    LiveSpeechState(
                        sessionID = sessionID,
                        phase = LiveSpeechPhase.COMPLETED,
                        committedText = committed,
                        droppedBufferCount = droppedBuffers.get(),
                    ),
                )
            }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            publishFailure("previewInterrupted")
        } catch (_: Throwable) {
            publishFailure("previewUnavailable")
        }
    }

    private fun publish(committed: String, partial: String) {
        LiveSpeechRegistry.publish(
            LiveSpeechState(
                sessionID = sessionID,
                phase = if (paused.get()) LiveSpeechPhase.PAUSED else LiveSpeechPhase.LISTENING,
                committedText = committed,
                partialText = partial.take(MAX_PARTIAL_CHARACTERS),
                droppedBufferCount = droppedBuffers.get(),
            ),
        )
    }

    private fun publishFailure(code: String) {
        if (discarded.get()) LiveSpeechRegistry.publish(LiveSpeechState())
        else LiveSpeechRegistry.publish(
            LiveSpeechState(
                sessionID = sessionID,
                phase = LiveSpeechPhase.FAILED,
                droppedBufferCount = droppedBuffers.get(),
                failureCode = code,
            ),
        )
    }

    private fun currentState(): LiveSpeechState? = LiveSpeechRegistry.state.value.takeIf { it.sessionID == sessionID }

    private fun appendBounded(existing: String, next: String): String = mergeLiveSpeechText(existing, next)
        .takeLast(MAX_PREVIEW_CHARACTERS)

    companion object {
        fun start(context: Context, sessionID: String): LocalLiveSpeechSession? {
            val directory = SpeechModelManager.get(context).selectedModelDirectory()
            if (directory == null) {
                LiveSpeechRegistry.publish(
                    LiveSpeechState(sessionID, LiveSpeechPhase.UNAVAILABLE, failureCode = "modelNotInstalled"),
                )
                return null
            }
            return LocalLiveSpeechSession(sessionID, directory)
        }

        private const val SAMPLE_RATE = 16_000
        private const val MAX_QUEUED_BUFFERS = 64
        private const val POLL_MILLIS = 200L
        private const val MAX_PREVIEW_CHARACTERS = 16_000
        private const val MAX_PARTIAL_CHARACTERS = 1_000
    }
}

private fun speechText(json: String): String = runCatching {
    JSONObject(json).optString("text").trim()
}.getOrDefault("")

private fun partialSpeechText(json: String): String = runCatching {
    JSONObject(json).optString("partial").trim()
}.getOrDefault("")
