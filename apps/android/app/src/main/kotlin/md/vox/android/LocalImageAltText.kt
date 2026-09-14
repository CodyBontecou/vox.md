package md.vox.android

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabel
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * Best-effort image descriptions backed by ML Kit's model bundled in the APK.
 *
 * No image bytes or labels leave the process. Callers must retain the original attachment and
 * fall back to its filename whenever this optional enrichment cannot produce useful evidence.
 */
class LocalImageAltTextGenerator private constructor() {
    private val labeler by lazy {
        ImageLabeling.getClient(
            ImageLabelerOptions.Builder()
                .setConfidenceThreshold(MINIMUM_CONFIDENCE)
                .build(),
        )
    }

    suspend fun describe(encodedImage: ByteArray, mediaType: String): String? {
        if (!mediaType.startsWith("image/") || encodedImage.isEmpty() || encodedImage.size > MAX_INPUT_BYTES) return null
        val bitmap = withContext(Dispatchers.Default) { decodeBounded(encodedImage) } ?: return null
        return try {
            val labels = suspendCancellableCoroutine<List<ImageLabel>> { continuation ->
                labeler.process(InputImage.fromBitmap(bitmap, 0))
                    .addOnSuccessListener { if (continuation.isActive) continuation.resume(it) }
                    .addOnFailureListener { if (continuation.isActive) continuation.resumeWithException(it) }
            }
            formatImageAltText(labels.map { it.text to it.confidence })
        } finally {
            bitmap.recycle()
        }
    }

    private fun decodeBounded(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / sample > MAX_BITMAP_EDGE || bounds.outHeight / sample > MAX_BITMAP_EDGE) {
            sample *= 2
        }
        return BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        )
    }

    companion object {
        private const val MINIMUM_CONFIDENCE = 0.65f
        private const val MAX_BITMAP_EDGE = 1_280
        private const val MAX_INPUT_BYTES = 100 * 1024 * 1024

        @Volatile private var instance: LocalImageAltTextGenerator? = null

        fun get(): LocalImageAltTextGenerator = instance ?: synchronized(this) {
            instance ?: LocalImageAltTextGenerator().also { instance = it }
        }
    }
}

internal fun formatImageAltText(labels: List<Pair<String, Float>>): String? {
    val useful = labels.asSequence()
        .filter { (_, confidence) -> confidence >= 0.65f }
        .sortedByDescending { (_, confidence) -> confidence }
        .map { (label, _) ->
            label.trim()
                .replace('|', ' ')
                .replace(']', ' ')
                .replace(Regex("\\s+"), " ")
                .trim()
                .take(48)
        }
        .filter(String::isNotBlank)
        .distinctBy(String::lowercase)
        .take(5)
        .toList()
    return useful.takeIf(List<String>::isNotEmpty)?.joinToString(
        prefix = "Image may contain: ",
        separator = ", ",
        postfix = ".",
    )
}
