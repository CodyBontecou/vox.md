package md.vox.android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.text.InputType
import android.util.AtomicFile
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.inputmethodservice.InputMethodService
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import java.util.Locale
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.LiveSpeechPhase
import md.vox.android.platformservices.LiveSpeechRegistry
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingStatusRegistry
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.SpeechModelManager

/** A local-first text keyboard with an on-device voice segment toolbar. */
class VoxInputMethodService : InputMethodService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var audioCapture: AudioCaptureClient
    private lateinit var transcription: RecordingTranscriptionClient
    private var statusView: TextView? = null
    private var voiceButton: Button? = null
    private var isListening = false
    private var shifted = false
    private var symbols = false
    private var root: LinearLayout? = null
    private var editorGeneration = 0L
    private var activeVoiceGeneration: Long? = null
    private var activeSessionID: String? = null
    private var waitingForSession = false
    private var transcriptionRequested = false
    private var sensitiveInput = false
    private var pendingText: String? = null

    override fun onCreate() {
        super.onCreate()
        audioCapture = AudioCaptureClient(this)
        transcription = RecordingTranscriptionClient.get(this)
        serviceScope.launch { RecordingStatusRegistry.status.collectLatest(::handleRecordingStatus) }
        serviceScope.launch { LiveSpeechRegistry.state.collectLatest { state ->
            if (state.sessionID != activeSessionID || !isListening) return@collectLatest
            val preview = state.displayText.takeLast(48).takeIf(String::isNotBlank)
            when (state.phase) {
                LiveSpeechPhase.STARTING -> updateVoiceState("Starting on-device voice…", listening = true)
                LiveSpeechPhase.LISTENING, LiveSpeechPhase.PAUSED ->
                    updateVoiceState(preview ?: "Listening…", listening = true, localizeStatus = preview == null)
                LiveSpeechPhase.FAILED, LiveSpeechPhase.UNAVAILABLE -> Unit
                LiveSpeechPhase.COMPLETED -> Unit
            }
        } }
        serviceScope.launch { transcription.states.collectLatest { states ->
            val sessionID = activeSessionID ?: return@collectLatest
            when (val state = states[sessionID]) {
                null -> Unit
                else -> when (state.phase) {
                    RecordingTranscriptionPhase.QUEUED,
                    RecordingTranscriptionPhase.PROCESSING,
                    RecordingTranscriptionPhase.FINALIZING ->
                        updateVoiceState("Transcribing on device…", listening = true)
                    RecordingTranscriptionPhase.COMPLETED -> completeVoiceResult(
                        sessionID,
                        state.preferredTranscript.orEmpty(),
                    )
                    RecordingTranscriptionPhase.FAILED -> retainFailedVoiceRecording(sessionID)
                    RecordingTranscriptionPhase.DISCARDED -> resetVoiceSession()
                }
            }
        } }
    }

    override fun onCreateInputView(): View {
        return buildKeyboard().also { root = it }
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        editorGeneration += 1
        activeVoiceGeneration = null
        sensitiveInput = isSensitiveEditorInput(info?.inputType ?: InputType.TYPE_NULL)
        pendingText = PendingVoiceTextStore.read(this)
        shifted = shouldStartShifted(info)
        symbols = false
        root?.let { rebuildKeyRows(it) }
        updateIdleVoiceState()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        editorGeneration += 1
        if (isListening) stopVoice()
        super.onFinishInputView(finishingInput)
    }

    override fun onDestroy() {
        if (isListening) audioCapture.stop()
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun buildKeyboard(): LinearLayout {
        val dark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val background = Color.parseColor(if (dark) "#1A1A1C" else "#E2E4E8")
        val foreground = Color.parseColor(if (dark) "#F2F1EE" else "#171614")
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(background)
            setPadding(dp(5), dp(5), dp(5), dp(6))
            tag = KEYBOARD_ROOT_TAG
        }
        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(5), 0, dp(5), dp(4))
        }
        statusView = TextView(this).apply {
            text = localize("On-device voice")
            setTextColor(foreground)
            textSize = 13f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            contentDescription = localize("Voice status")
        }
        toolbar.addView(statusView, LinearLayout.LayoutParams(0, dp(40), 1f))
        voiceButton = keyButton("Mic", wide = false).apply {
            text = "●"
            contentDescription = localize("Start voice typing")
            setOnClickListener {
                when {
                    isListening -> stopVoice()
                    pendingText != null && !sensitiveInput -> insertPendingText()
                    else -> startVoice()
                }
            }
        }
        toolbar.addView(voiceButton, LinearLayout.LayoutParams(dp(52), dp(40)))
        root.addView(toolbar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(44)))
        rebuildKeyRows(root)
        return root
    }

    private fun rebuildKeyRows(root: LinearLayout) {
        while (root.childCount > 1) root.removeViewAt(root.childCount - 1)
        val rows = if (symbols) SYMBOL_ROWS else LETTER_ROWS
        rows.forEach { row ->
            val rowView = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
            }
            row.forEach { key ->
                val label = when (key) {
                    SHIFT -> if (shifted) "⇧" else "↑"
                    DELETE -> "⌫"
                    SYMBOLS -> if (symbols) "ABC" else "123"
                    NEXT_IME -> "◎"
                    SPACE -> "space"
                    ENTER -> "↵"
                    else -> if (shifted && !symbols) key.uppercase(Locale.getDefault()) else key
                }
                val weight = when (key) {
                    SPACE -> 4.5f
                    SHIFT, DELETE, SYMBOLS, NEXT_IME, ENTER -> 1.45f
                    else -> 1f
                }
                val button = keyButton(label, wide = weight > 1f).apply {
                    contentDescription = keyDescription(key, label)
                    setOnClickListener { handleKey(key) }
                    if (key == DELETE) {
                        setOnLongClickListener {
                            currentInputConnection?.deleteSurroundingTextInCodePoints(1, 0)
                            performKeyboardHaptic(this)
                            true
                        }
                    }
                }
                rowView.addView(
                    button,
                    LinearLayout.LayoutParams(0, dp(48), weight).apply {
                        setMargins(dp(2), dp(2), dp(2), dp(2))
                    },
                )
            }
            root.addView(rowView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)))
        }
    }

    private fun keyButton(label: String, wide: Boolean): Button = Button(this).apply {
        text = label
        textSize = if (wide) 13f else 17f
        isAllCaps = false
        typeface = Typeface.create("sans", Typeface.NORMAL)
        minWidth = 0
        minHeight = 0
        setPadding(0, 0, 0, 0)
    }

    private fun handleKey(key: String) {
        performKeyboardHaptic(root)
        when (key) {
            SHIFT -> {
                shifted = !shifted
                root?.let(::rebuildKeyRows)
            }
            DELETE -> currentInputConnection?.deleteSurroundingTextInCodePoints(1, 0)
            SYMBOLS -> {
                symbols = !symbols
                shifted = false
                root?.let(::rebuildKeyRows)
            }
            NEXT_IME -> switchToNextInputMethod(false)
            SPACE -> currentInputConnection?.commitText(" ", 1)
            ENTER -> sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
            else -> {
                val text = if (shifted && !symbols) key.uppercase(Locale.getDefault()) else key
                currentInputConnection?.commitText(text, 1)
                if (shifted && !symbols) {
                    shifted = false
                    root?.let(::rebuildKeyRows)
                }
            }
        }
    }

    private fun startVoice() {
        if (sensitiveInput) {
            updateVoiceState("Voice typing is unavailable in sensitive fields", listening = false)
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            updateVoiceState("Open Vox.md to allow microphone access", listening = false)
            return
        }
        if (SpeechModelManager.get(this).selectedModelDirectory() == null) {
            updateVoiceState("Install and select a local model in Vox.md", listening = false)
            return
        }
        if (RecordingStatusRegistry.status.value.isActive) {
            updateVoiceState("Another Vox.md recording is active", listening = false)
            return
        }
        activeVoiceGeneration = editorGeneration
        activeSessionID = null
        waitingForSession = true
        transcriptionRequested = false
        isListening = true
        updateVoiceState("Starting on-device voice…", listening = true)
        audioCapture.start(keyboardPreset())
        performKeyboardHaptic(voiceButton)
    }

    private fun stopVoice() {
        if (!isListening) return
        audioCapture.stop()
        updateVoiceState("Saving voice recording…", listening = true)
        voiceButton?.isEnabled = false
    }

    private fun updateVoiceState(status: String, listening: Boolean, localizeStatus: Boolean = true) {
        statusView?.text = if (localizeStatus) localize(status) else status
        voiceButton?.apply {
            text = if (listening) "■" else "●"
            contentDescription = localize(if (listening) "Stop voice typing" else "Start voice typing")
        }
    }

    private fun handleRecordingStatus(status: RecordingStatus) {
        if (waitingForSession && status.phase == RecordingPhase.RECORDING && status.sessionID != null) {
            activeSessionID = status.sessionID
            waitingForSession = false
        }
        val sessionID = activeSessionID ?: return
        if (status.sessionID != sessionID) return
        when (status.phase) {
            RecordingPhase.RECORDING -> updateVoiceState("Recording…", listening = true)
            RecordingPhase.PAUSED -> updateVoiceState("Voice recording paused", listening = true)
            RecordingPhase.COMPLETED -> if (!transcriptionRequested) {
                transcriptionRequested = true
                updateVoiceState("Transcribing on device…", listening = true)
                transcription.process(sessionID)
            }
            RecordingPhase.FAILED, RecordingPhase.INTERRUPTED -> retainFailedVoiceRecording(sessionID)
            RecordingPhase.DISCARDED -> resetVoiceSession()
            RecordingPhase.IDLE -> Unit
        }
    }

    private fun completeVoiceResult(sessionID: String, text: String) {
        if (text.isBlank()) return retainFailedVoiceRecording(sessionID)
        val generation = activeVoiceGeneration
        val inserted = KeyboardVoiceCommitPolicy.commitOrPreserve(
            context = this,
            audioCapture = audioCapture,
            transcription = transcription,
            sessionID = sessionID,
            text = text,
        ) {
            generation == editorGeneration && currentInputConnection?.commitText(it, 1) == true
        }
        pendingText = if (inserted) null else text
        resetVoiceSession()
    }

    private fun retainFailedVoiceRecording(sessionID: String) {
        isListening = false
        waitingForSession = false
        transcriptionRequested = false
        activeVoiceGeneration = null
        activeSessionID = null
        updateVoiceState("Voice recording saved in Vox.md", listening = false)
    }

    private fun resetVoiceSession() {
        isListening = false
        waitingForSession = false
        transcriptionRequested = false
        activeVoiceGeneration = null
        activeSessionID = null
        audioCapture.dismissResult()
        updateIdleVoiceState()
    }

    private fun insertPendingText() {
        val text = pendingText ?: return
        if (sensitiveInput) return
        if (currentInputConnection?.commitText(text, 1) == true) {
            PendingVoiceTextStore.clear(this)
            pendingText = null
            updateIdleVoiceState()
        }
    }

    private fun updateIdleVoiceState() {
        when {
            sensitiveInput -> {
                statusView?.text = localize("Voice typing is unavailable in sensitive fields")
                voiceButton?.isEnabled = false
                voiceButton?.contentDescription = localize("Voice typing unavailable in sensitive field")
            }
            pendingText != null -> {
                statusView?.text = localize("Recovered voice text")
                voiceButton?.isEnabled = true
                voiceButton?.text = "+"
                voiceButton?.contentDescription = localize("Insert recovered voice text")
            }
            else -> {
                voiceButton?.isEnabled = true
                updateVoiceState("On-device voice", listening = false)
            }
        }
    }

    private fun shouldStartShifted(info: EditorInfo?): Boolean {
        val inputType = info?.inputType ?: return false
        return inputType and android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES != 0
    }

    private fun localize(source: String): String {
        val locale = resources.configuration.locales[0] ?: Locale.ENGLISH
        return RuntimeLocalization.translate(this, locale, source)
    }

    private fun performKeyboardHaptic(view: View?) {
        val enabled = getSharedPreferences(SETTINGS_FILE, MODE_PRIVATE).getBoolean(HAPTICS_KEY, true)
        if (enabled) view?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    }

    private fun keyDescription(key: String, label: String): String = when (key) {
        SHIFT -> "Shift"
        DELETE -> "Delete"
        SYMBOLS -> if (symbols) "Letters" else "Numbers and symbols"
        NEXT_IME -> "Next keyboard"
        SPACE -> "Space"
        ENTER -> "Enter"
        else -> label
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun keyboardPreset() = CapturePreset(
        id = KEYBOARD_PRESET_ID,
        name = "Keyboard Voice",
        symbol = "keyboard",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "keyboard-{id}",
        metadataFields = listOf(CaptureMetadataField("source", "keyboard")),
    )

    private companion object {
        const val SETTINGS_FILE = "vox-settings"
        const val HAPTICS_KEY = "keyboard-haptics"
        const val KEYBOARD_PRESET_ID = "6b65ab02-e77a-4a0c-bef7-b48813e95fbb"
        const val KEYBOARD_ROOT_TAG = "vox-keyboard"
        const val SHIFT = "{shift}"
        const val DELETE = "{delete}"
        const val SYMBOLS = "{symbols}"
        const val NEXT_IME = "{next-ime}"
        const val SPACE = "{space}"
        const val ENTER = "{enter}"

        val LETTER_ROWS = listOf(
            listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
            listOf("a", "s", "d", "f", "g", "h", "j", "k", "l"),
            listOf(SHIFT, "z", "x", "c", "v", "b", "n", "m", DELETE),
            listOf(SYMBOLS, NEXT_IME, ",", SPACE, ".", ENTER),
        )
        val SYMBOL_ROWS = listOf(
            listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
            listOf("@", "#", "$", "%", "&", "-", "+", "(", ")"),
            listOf("*", "\"", "'", ":", ";", "!", "?", "/", DELETE),
            listOf(SYMBOLS, NEXT_IME, ",", SPACE, ".", ENTER),
        )
    }
}

internal fun isSensitiveEditorInput(inputType: Int): Boolean {
    val variation = inputType and InputType.TYPE_MASK_VARIATION
    return when (inputType and InputType.TYPE_MASK_CLASS) {
        InputType.TYPE_CLASS_TEXT -> variation in setOf(
            InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        )
        InputType.TYPE_CLASS_NUMBER -> variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        else -> false
    }
}

internal object KeyboardVoiceCommitPolicy {
    fun commitOrPreserve(
        context: Context,
        audioCapture: AudioCaptureClient,
        transcription: RecordingTranscriptionClient,
        sessionID: String,
        text: String,
        commit: (String) -> Boolean,
    ): Boolean {
        if (!commit(text)) {
            PendingVoiceTextStore.write(context, text)
            return false
        }
        PendingVoiceTextStore.clear(context)
        transcription.clear(sessionID)
        audioCapture.deleteRecording(sessionID)
        return true
    }
}

internal object PendingVoiceTextStore {
    private const val MAX_BYTES = 65_536

    fun write(context: Context, text: String) {
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (bytes.isEmpty() || bytes.size > MAX_BYTES) return
        val file = AtomicFile(File(context.noBackupFilesDir, "keyboard/pending-voice.txt"))
        file.baseFile.parentFile?.mkdirs()
        val output = file.startWrite()
        try {
            output.write(bytes)
            output.flush()
            output.fd.sync()
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
        }
    }

    fun read(context: Context): String? = runCatching {
        val bytes = AtomicFile(File(context.noBackupFilesDir, "keyboard/pending-voice.txt")).readFully()
        require(bytes.size <= MAX_BYTES)
        bytes.toString(Charsets.UTF_8).takeIf(String::isNotBlank)
    }.getOrNull()

    fun clear(context: Context) {
        AtomicFile(File(context.noBackupFilesDir, "keyboard/pending-voice.txt")).delete()
    }
}
