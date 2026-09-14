package md.vox.android.platformservices

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/** Bundled, on-device Latin-script OCR. No capture bytes are sent to a hosted service. */
class LocalTextRecognition(private val context: Context) {
    suspend fun recognize(uris: List<Uri>): String = withContext(Dispatchers.IO) {
        require(uris.isNotEmpty() && uris.size <= MAX_IMAGES) { "invalidImageCount" }
        uris.mapIndexedNotNull { index, uri ->
            recognizeOne(uri).trim().takeIf(String::isNotEmpty)?.let { "<!-- Page ${index + 1} -->\n$it" }
        }.joinToString("\n\n")
    }

    private suspend fun recognizeOne(uri: Uri): String {
        require(uri.scheme == "content") { "invalidImageUri" }
        val image = withContext(Dispatchers.IO) { InputImage.fromFilePath(context, uri) }
        return suspendCancellableCoroutine { continuation ->
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            val task = recognizer.process(image)
            task.addOnSuccessListener { result ->
                recognizer.close()
                if (continuation.isActive) continuation.resume(result.text)
            }
            task.addOnFailureListener { error ->
                recognizer.close()
                if (continuation.isActive) continuation.resume("")
            }
            task.addOnCanceledListener {
                recognizer.close()
                if (continuation.isActive) continuation.cancel()
            }
            continuation.invokeOnCancellation { recognizer.close() }
        }
    }

    private companion object {
        const val MAX_IMAGES = 20
    }
}
