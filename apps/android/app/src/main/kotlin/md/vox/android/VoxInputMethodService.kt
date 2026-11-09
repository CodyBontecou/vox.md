package md.vox.android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
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
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.ColorRes
import androidx.annotation.DrawableRes
import androidx.core.content.ContextCompat
import androidx.core.content.res.ResourcesCompat
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
    private var panel: VoxKeyboardPanel? = null
    private val voiceButton: View? get() = panel?.voiceView
    private var isListening = false
    private var shifted = false
    private var symbols = false
    private val root: View? get() = panel?.root
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
                        updateVoiceState("Transcribing on device…", listening = true, mode = KeyboardVoiceMode.PROCESSING)
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
        val panel = VoxKeyboardPanel(
            context = this,
            localize = ::localize,
            onKey = ::handleKey,
            onDeleteLongPress = { view ->
                currentInputConnection?.deleteSurroundingTextInCodePoints(1, 0)
                performKeyboardHaptic(view)
            },
            onVoice = {
                when {
                    isListening -> stopVoice()
                    pendingText != null && !sensitiveInput -> insertPendingText()
                    else -> startVoice()
                }
            },
        )
        panel.rebuildKeyRows(shifted, symbols)
        this.panel = panel
        return panel.root
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        editorGeneration += 1
        activeVoiceGeneration = null
        sensitiveInput = isSensitiveEditorInput(info?.inputType ?: InputType.TYPE_NULL)
        pendingText = PendingVoiceTextStore.read(this)
        shifted = shouldStartShifted(info)
        symbols = false
        panel?.rebuildKeyRows(shifted, symbols)
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

    private fun handleKey(key: String) {
        performKeyboardHaptic(root)
        when (key) {
            SHIFT -> {
                shifted = !shifted
                panel?.rebuildKeyRows(shifted, symbols)
            }
            DELETE -> currentInputConnection?.deleteSurroundingTextInCodePoints(1, 0)
            SYMBOLS -> {
                symbols = !symbols
                shifted = false
                panel?.rebuildKeyRows(shifted, symbols)
            }
            NEXT_IME -> switchToNextInputMethod(false)
            SPACE -> currentInputConnection?.commitText(" ", 1)
            ENTER -> sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
            else -> {
                val text = if (shifted && !symbols) key.uppercase(Locale.getDefault()) else key
                currentInputConnection?.commitText(text, 1)
                if (shifted && !symbols) {
                    shifted = false
                    panel?.rebuildKeyRows(shifted, symbols)
                }
            }
        }
    }

    private fun startVoice() {
        if (PlayBillingManager.get(this).state.value.hasSubscriptionAccessEnded) {
            updateVoiceState("New captures and edits need Vox.md.", listening = false, mode = KeyboardVoiceMode.ERROR)
            return
        }
        if (sensitiveInput) {
            updateVoiceState("Voice typing is unavailable in sensitive fields", listening = false, mode = KeyboardVoiceMode.ERROR)
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            updateVoiceState("Open Vox.md to allow microphone access", listening = false, mode = KeyboardVoiceMode.ERROR)
            return
        }
        if (SpeechModelManager.get(this).selectedModelDirectory() == null) {
            updateVoiceState("Install and select a local model in Vox.md", listening = false, mode = KeyboardVoiceMode.ERROR)
            return
        }
        if (RecordingStatusRegistry.status.value.isActive) {
            updateVoiceState("Another Vox.md recording is active", listening = false, mode = KeyboardVoiceMode.ERROR)
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
        updateVoiceState("Saving voice recording…", listening = true, mode = KeyboardVoiceMode.PROCESSING)
        panel?.setVoiceEnabled(false)
    }

    private fun updateVoiceState(
        status: String,
        listening: Boolean,
        localizeStatus: Boolean = true,
        mode: KeyboardVoiceMode = if (listening) KeyboardVoiceMode.LISTENING else KeyboardVoiceMode.IDLE,
    ) {
        panel?.showVoiceState(if (localizeStatus) localize(status) else status, listening, mode)
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
                updateVoiceState("Transcribing on device…", listening = true, mode = KeyboardVoiceMode.PROCESSING)
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
        updateVoiceState("Voice recording saved in Vox.md", listening = false, mode = KeyboardVoiceMode.ERROR)
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
            sensitiveInput -> panel?.showSensitiveField()
            pendingText != null -> panel?.showRecoveredText()
            else -> {
                panel?.setVoiceEnabled(true)
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

    private fun keyboardPreset() = CapturePreset(
        id = KEYBOARD_PRESET_ID,
        name = "Keyboard Voice",
        symbol = "keyboard",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "keyboard-{id}",
        metadataFields = listOf(CaptureMetadataField("source", "keyboard")),
    )

    internal companion object {
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

/** Visual state of the keyboard voice control. Presentation only; behaviour lives in [VoxInputMethodService]. */
internal enum class KeyboardVoiceMode { IDLE, LISTENING, PROCESSING, ERROR, UNAVAILABLE, RECOVERED }

/**
 * The Material 3 keyboard view: a `surfaceContainer` ground, a toolbar with mono status
 * text and the voice control (primary when idle, a recording-red squircle while
 * listening), and raised `surfaceContainerLowest` keys with `secondaryContainer`
 * modifiers in Geist. It holds no editor or capture state: [VoxInputMethodService]
 * owns all behaviour and drives this view, which also lets debug stories host it directly.
 */
internal class VoxKeyboardPanel(
    private val context: Context,
    private val localize: (String) -> String,
    private val onKey: (String) -> Unit,
    private val onDeleteLongPress: (View) -> Unit,
    onVoice: () -> Unit,
) {
    private val density = context.resources.displayMetrics.density
    private val sans: Typeface? = font(R.font.geist_regular)
    private val sansMedium: Typeface? = font(R.font.geist_medium)
    private val mono: Typeface? = font(R.font.geist_mono_regular)
    private var symbols = false

    val root: LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(color(R.color.signal_bg))
        setPadding(dp(6), dp(6), dp(6), dp(8))
        tag = VoxInputMethodService.KEYBOARD_ROOT_TAG
    }

    private val statusView: TextView = TextView(context).apply {
        text = localize("On-device voice")
        setTextColor(color(R.color.signal_muted))
        typeface = mono
        textSize = 12.5f
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
        gravity = Gravity.CENTER_VERTICAL
        compoundDrawablePadding = dp(7)
        contentDescription = localize("Voice status")
    }

    /** The voice capsule. Exposed for haptics; click handling is wired to `onVoice`. */
    val voiceView: ImageButton = ImageButton(context).apply {
        contentDescription = localize("Start voice typing")
        scaleType = android.widget.ImageView.ScaleType.CENTER
        setPadding(0, 0, 0, 0)
        stateListAnimator = null
        setOnClickListener { onVoice() }
    }

    init {
        val toolbar = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), 0, dp(2), dp(6))
        }
        toolbar.addView(statusView, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
        toolbar.addView(voiceView, LinearLayout.LayoutParams(dp(88), dp(48)).apply { marginStart = dp(10) })
        root.addView(toolbar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(56)))
        applyVoiceMode(KeyboardVoiceMode.IDLE)
    }

    /** Status line plus the start/stop voice control. */
    fun showVoiceState(status: String, listening: Boolean, mode: KeyboardVoiceMode) {
        statusView.text = status
        voiceView.contentDescription = localize(if (listening) "Stop voice typing" else "Start voice typing")
        applyVoiceMode(mode)
    }

    /** Password-style fields: voice is disabled and the status explains why. */
    fun showSensitiveField() {
        statusView.text = localize("Voice typing is unavailable in sensitive fields")
        setVoiceEnabled(false)
        voiceView.contentDescription = localize("Voice typing unavailable in sensitive field")
        applyVoiceMode(KeyboardVoiceMode.UNAVAILABLE)
    }

    /** Recovered text from an earlier session can be inserted with the voice control. */
    fun showRecoveredText() {
        statusView.text = localize("Recovered voice text")
        setVoiceEnabled(true)
        voiceView.contentDescription = localize("Insert recovered voice text")
        applyVoiceMode(KeyboardVoiceMode.RECOVERED)
    }

    fun setVoiceEnabled(enabled: Boolean) {
        voiceView.isEnabled = enabled
        voiceView.alpha = if (enabled) 1f else 0.55f
    }

    private fun applyVoiceMode(mode: KeyboardVoiceMode) {
        val (background, icon, iconColor) = when (mode) {
            KeyboardVoiceMode.IDLE, KeyboardVoiceMode.ERROR ->
                Triple(R.drawable.keyboard_voice_idle, R.drawable.keyboard_ic_mic, R.color.signal_on_ink)
            KeyboardVoiceMode.LISTENING ->
                Triple(R.drawable.keyboard_voice_recording, R.drawable.keyboard_ic_stop, R.color.signal_on_accent)
            KeyboardVoiceMode.PROCESSING ->
                Triple(R.drawable.keyboard_voice_muted, R.drawable.keyboard_ic_stop, R.color.signal_text)
            KeyboardVoiceMode.UNAVAILABLE ->
                Triple(R.drawable.keyboard_voice_muted, R.drawable.keyboard_ic_mic, R.color.signal_faint)
            KeyboardVoiceMode.RECOVERED ->
                Triple(R.drawable.keyboard_voice_recovered, R.drawable.keyboard_ic_plus, R.color.signal_on_accent)
        }
        voiceView.background = drawable(background)
        voiceView.setImageDrawable(drawable(icon)?.mutate()?.apply { setTint(color(iconColor)) })
        statusView.setTextColor(color(when (mode) {
            KeyboardVoiceMode.LISTENING -> R.color.signal_recording
            KeyboardVoiceMode.PROCESSING -> R.color.signal_text
            KeyboardVoiceMode.ERROR -> R.color.signal_error
            KeyboardVoiceMode.RECOVERED -> R.color.signal_tint
            KeyboardVoiceMode.IDLE, KeyboardVoiceMode.UNAVAILABLE -> R.color.signal_muted
        }))
        val dot = if (mode == KeyboardVoiceMode.LISTENING) drawable(R.drawable.keyboard_status_dot) else null
        statusView.setCompoundDrawablesRelativeWithIntrinsicBounds(dot, null, null, null)
    }

    fun rebuildKeyRows(shifted: Boolean, symbols: Boolean) {
        this.symbols = symbols
        while (root.childCount > 1) root.removeViewAt(root.childCount - 1)
        val rows = if (symbols) VoxInputMethodService.SYMBOL_ROWS else VoxInputMethodService.LETTER_ROWS
        rows.forEach { row ->
            val rowView = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
            }
            row.forEach { key ->
                val label = when (key) {
                    VoxInputMethodService.SHIFT -> if (shifted) "⇧" else "↑"
                    VoxInputMethodService.DELETE -> "⌫"
                    VoxInputMethodService.SYMBOLS -> if (symbols) "ABC" else "123"
                    VoxInputMethodService.NEXT_IME -> "◎"
                    VoxInputMethodService.SPACE -> "space"
                    VoxInputMethodService.ENTER -> "↵"
                    else -> if (shifted && !symbols) key.uppercase(Locale.getDefault()) else key
                }
                val weight = when (key) {
                    VoxInputMethodService.SPACE -> 4.5f
                    VoxInputMethodService.SHIFT, VoxInputMethodService.DELETE, VoxInputMethodService.SYMBOLS,
                    VoxInputMethodService.NEXT_IME, VoxInputMethodService.ENTER -> 1.45f
                    else -> 1f
                }
                val modifier = weight > 1f && key != VoxInputMethodService.SPACE
                val button = keyButton(label, wide = weight > 1f, modifier = modifier).apply {
                    contentDescription = keyDescription(key, label)
                    setOnClickListener { onKey(key) }
                    if (key == VoxInputMethodService.SPACE) setTextColor(color(R.color.signal_muted))
                    if (key == VoxInputMethodService.DELETE) {
                        setOnLongClickListener {
                            onDeleteLongPress(it)
                            true
                        }
                    }
                }
                rowView.addView(
                    button,
                    LinearLayout.LayoutParams(0, dp(46), weight).apply {
                        setMargins(dp(3), dp(3), dp(3), dp(3))
                    },
                )
            }
            root.addView(rowView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)))
        }
    }

    private fun keyButton(label: String, wide: Boolean, modifier: Boolean): Button = Button(context).apply {
        text = label
        textSize = if (wide) 14f else 20f
        isAllCaps = false
        typeface = if (modifier) sansMedium else sans
        setTextColor(color(R.color.signal_text))
        background = drawable(if (modifier) R.drawable.keyboard_key_modifier_background else R.drawable.keyboard_key_background)
        stateListAnimator = null
        elevation = 0f
        minWidth = 0
        minHeight = 0
        minimumWidth = 0
        minimumHeight = 0
        setPadding(0, 0, 0, 0)
    }

    private fun keyDescription(key: String, label: String): String = when (key) {
        VoxInputMethodService.SHIFT -> "Shift"
        VoxInputMethodService.DELETE -> "Delete"
        VoxInputMethodService.SYMBOLS -> if (symbols) "Letters" else "Numbers and symbols"
        VoxInputMethodService.NEXT_IME -> "Next keyboard"
        VoxInputMethodService.SPACE -> "Space"
        VoxInputMethodService.ENTER -> "Enter"
        else -> label
    }

    private fun color(@ColorRes id: Int): Int = ContextCompat.getColor(context, id)
    private fun drawable(@DrawableRes id: Int) = ContextCompat.getDrawable(context, id)
    private fun font(id: Int): Typeface? = runCatching { ResourcesCompat.getFont(context, id) }.getOrNull()
        ?: Typeface.create("sans", Typeface.NORMAL)
    private fun dp(value: Int): Int = (value * density).toInt()
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
