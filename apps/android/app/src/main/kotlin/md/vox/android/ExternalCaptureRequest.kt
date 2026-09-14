package md.vox.android

import android.content.Intent
import android.net.Uri
import java.net.URI
import java.util.UUID

internal enum class ExternalCaptureAction {
    REVIEW,
    RECORD,
}

internal data class ExternalCaptureRequest(
    val correlationID: String,
    val text: String,
    val url: String?,
    val presetID: String?,
    val action: ExternalCaptureAction,
    val sourceLabel: String,
    val captureSource: String,
    val attachmentUris: List<String> = emptyList(),
)

internal object ExternalCaptureRequestParser {
    fun parse(intent: Intent?): ExternalCaptureRequest? {
        intent ?: return null
        return when (intent.action) {
            Intent.ACTION_SEND -> parseSharedValues(
                textValues = listOfNotNull(intent.charSequenceExtra(Intent.EXTRA_TEXT)),
                title = intent.charSequenceExtra(Intent.EXTRA_TITLE),
                attachmentUris = listOfNotNull(intent.uriExtra(Intent.EXTRA_STREAM)),
            )
            Intent.ACTION_SEND_MULTIPLE -> parseSharedValues(
                textValues = intent.charSequenceArrayListExtra(Intent.EXTRA_TEXT),
                title = intent.charSequenceExtra(Intent.EXTRA_TITLE),
                attachmentUris = intent.uriArrayListExtra(Intent.EXTRA_STREAM),
            )
            Intent.ACTION_PROCESS_TEXT -> normalize(
                textValues = listOfNotNull(intent.charSequenceExtra(Intent.EXTRA_PROCESS_TEXT)),
                title = null,
                presetID = null,
                action = ExternalCaptureAction.REVIEW,
                sourceLabel = "Selected text",
                captureSource = "share",
                attachmentUris = emptyList(),
            )
            Intent.ACTION_VIEW -> parseDeepLink(intent.data)
            else -> null
        }
    }

    private fun parseSharedValues(
        textValues: List<CharSequence>,
        title: CharSequence?,
        attachmentUris: List<Uri>,
    ): ExternalCaptureRequest? = normalize(
        textValues = textValues,
        title = title,
        presetID = null,
        action = ExternalCaptureAction.REVIEW,
        sourceLabel = "Shared content",
        captureSource = "share",
        attachmentUris = attachmentUris.map(Uri::toString),
    )

    private fun parseDeepLink(uri: Uri?): ExternalCaptureRequest? {
        if (uri?.scheme?.lowercase() != "voxboard") return null
        val host = uri.host?.lowercase() ?: return null
        if (host !in SUPPORTED_HOSTS) return null
        val text = uri.getQueryParameter("text").orEmpty()
        val url = uri.getQueryParameter("url")?.takeIf(::isHttpURL)
        val preset = uri.getQueryParameter("preset")?.takeIf(::isValidPresetID)
        val action = if (host in RECORDING_HOSTS || uri.getQueryParameter("action") == "voice") {
            ExternalCaptureAction.RECORD
        } else {
            ExternalCaptureAction.REVIEW
        }
        val requestedSource = uri.getQueryParameter("source")?.lowercase()
        val captureSource = when (requestedSource) {
            "widget" -> "widget"
            "keyboard" -> "keyboard"
            else -> "shortcut"
        }
        val sourceLabel = when (requestedSource) {
            "widget" -> "Widget"
            "quick-settings" -> "Quick Settings"
            "keyboard" -> "Keyboard"
            else -> "Shortcut"
        }
        return ExternalCaptureRequest(
            correlationID = UUID.randomUUID().toString().lowercase(),
            text = text.take(MAX_TEXT_CHARACTERS),
            url = url,
            presetID = preset,
            action = action,
            sourceLabel = sourceLabel,
            captureSource = captureSource,
        )
    }

    internal fun normalize(
        textValues: List<CharSequence>,
        title: CharSequence?,
        presetID: String?,
        action: ExternalCaptureAction,
        sourceLabel: String,
        captureSource: String = "share",
        attachmentUris: List<String>,
    ): ExternalCaptureRequest? {
        val parts = textValues.map { it.toString().trim() }.filter(String::isNotEmpty)
        val singleURL = parts.singleOrNull()?.takeIf(::isHttpURL)
        val normalizedTitle = title?.toString()?.trim().orEmpty()
        val text = when {
            singleURL != null -> normalizedTitle
            else -> parts.joinToString("\n\n")
        }.take(MAX_TEXT_CHARACTERS)
        if (text.isBlank() && singleURL == null && attachmentUris.isEmpty() && action != ExternalCaptureAction.RECORD) return null
        return ExternalCaptureRequest(
            correlationID = UUID.randomUUID().toString().lowercase(),
            text = text,
            url = singleURL,
            presetID = presetID?.takeIf(::isValidPresetID),
            action = action,
            sourceLabel = sourceLabel,
            captureSource = captureSource.takeIf(SUPPORTED_CAPTURE_SOURCES::contains) ?: "share",
            attachmentUris = attachmentUris.take(MAX_ATTACHMENTS),
        )
    }

    private fun Intent.charSequenceExtra(name: String): CharSequence? = getCharSequenceExtra(name)

    private fun Intent.uriExtra(name: String): Uri? =
        if (android.os.Build.VERSION.SDK_INT >= 33) getParcelableExtra(name, Uri::class.java)
        else @Suppress("DEPRECATION") getParcelableExtra(name)

    private fun Intent.uriArrayListExtra(name: String): List<Uri> =
        if (android.os.Build.VERSION.SDK_INT >= 33) getParcelableArrayListExtra(name, Uri::class.java).orEmpty()
        else @Suppress("DEPRECATION") getParcelableArrayListExtra<Uri>(name).orEmpty()

    private fun Intent.charSequenceArrayListExtra(name: String): List<CharSequence> =
        @Suppress("DEPRECATION") (getCharSequenceArrayListExtra(name).orEmpty())

    private fun isHttpURL(value: String): Boolean = runCatching {
        val uri = URI(value.trim())
        uri.scheme?.lowercase() in setOf("http", "https") && !uri.host.isNullOrBlank()
    }.getOrDefault(false)

    private fun isValidPresetID(value: String): Boolean = runCatching { UUID.fromString(value); true }.getOrDefault(false)

    private val SUPPORTED_HOSTS = setOf("capture", "capture-request", "listen", "record", "widget-record")
    private val RECORDING_HOSTS = setOf("listen", "record", "widget-record")
    private val SUPPORTED_CAPTURE_SOURCES = setOf("app", "share", "keyboard", "widget", "shortcut")
    private const val MAX_TEXT_CHARACTERS = 65_536
    private const val MAX_ATTACHMENTS = 32
}
