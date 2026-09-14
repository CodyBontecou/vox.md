package md.vox.android

import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.UUID

internal data class DocumentScanAssetSpec(
    val sourceUri: String,
    val displayName: String,
    val mediaType: String,
    val includeInMarkdown: Boolean = true,
)

internal data class ScanOcrPayload(
    val bytes: ByteArray,
    val displayName: String = "Scanned document OCR.txt",
    val mediaType: String = "text/plain; charset=utf-8",
    val includeInMarkdown: Boolean = false,
)

/**
 * Freezes every scanner source in deterministic order: all page images first, then the generated
 * PDF. OCR is assembled separately so recognized text can never replace or masquerade as source.
 */
internal fun documentScanAssetSpecs(
    pageUris: List<String>,
    pdfUri: String?,
): List<DocumentScanAssetSpec> {
    val pages = pageUris
        .map(String::trim)
        .filter(String::isNotEmpty)
        .distinct()
        .take(MAX_SCAN_PAGES)
    val result = pages.mapIndexed { index, uri ->
        DocumentScanAssetSpec(
            sourceUri = uri,
            displayName = "Scanned page ${(index + 1).toString().padStart(2, '0')}.jpg",
            mediaType = "image/jpeg",
        )
    }.toMutableList()
    pdfUri?.trim()?.takeIf(String::isNotEmpty)?.let { uri ->
        result += DocumentScanAssetSpec(uri, "Scanned document.pdf", "application/pdf")
    }
    return result
}

internal fun scanOcrPayload(recognizedText: String): ScanOcrPayload? {
    val normalized = recognizedText.trim().take(MAX_OCR_CHARACTERS)
    if (normalized.isEmpty()) return null
    return ScanOcrPayload((normalized + "\n").toByteArray(StandardCharsets.UTF_8))
}

internal fun createScanOcrAsset(context: Context, recognizedText: String): GeneratedCaptureAsset? {
    val payload = scanOcrPayload(recognizedText) ?: return null
    val token = UUID.randomUUID().toString().lowercase(Locale.ROOT)
    val file = createCaptureImportFile(context, "$token-scan-ocr.txt") { it.write(payload.bytes) }
    return GeneratedCaptureAsset(
        uri = captureImportUri(context, file),
        displayName = payload.displayName,
        mediaType = payload.mediaType,
        includeInMarkdown = payload.includeInMarkdown,
    )
}

/** Android has no Photo Picker subtype for screenshots, so the app filters granted selections. */
internal fun screenshotMetadataMatches(
    displayName: String?,
    relativePath: String?,
    bucketName: String?,
): Boolean {
    val joined = listOfNotNull(displayName, relativePath, bucketName)
        .joinToString("/")
        .lowercase(Locale.ROOT)
        .replace('-', ' ')
        .replace('_', ' ')
    return Regex("(^|[/\\s])screen ?shots?([/\\s.]|$)|(^|[/\\s])screen ?captures?([/\\s.]|$)")
        .containsMatchIn(joined)
}

internal fun isScreenshotUri(context: Context, uri: Uri): Boolean {
    if (uri.scheme != "content") return false
    fun value(column: String): String? = runCatching {
        context.contentResolver.query(uri, arrayOf(column), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
        }
    }.getOrNull()
    return screenshotMetadataMatches(
        displayName = value(OpenableColumns.DISPLAY_NAME),
        relativePath = value(MediaStore.MediaColumns.RELATIVE_PATH),
        bucketName = value(MediaStore.Images.Media.BUCKET_DISPLAY_NAME),
    )
}

private const val MAX_SCAN_PAGES = 20
private const val MAX_OCR_CHARACTERS = 65_536
