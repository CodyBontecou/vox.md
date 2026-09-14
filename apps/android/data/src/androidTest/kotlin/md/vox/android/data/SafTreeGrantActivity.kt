package md.vox.android.data

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Instrumentation-only bridge that obtains a tree URI from the real system picker.
 * The provider grant therefore has the same origin and persisted semantics as production.
 */
class SafTreeGrantActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return
        @Suppress("DEPRECATION")
        val initialUri = intent.getParcelableExtra(EXTRA_INITIAL_URI) as? Uri
        startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                )
                initialUri?.let { putExtra(DocumentsContract.EXTRA_INITIAL_URI, it) }
            },
            REQUEST_TREE,
        )
    }

    @Deprecated("The test bridge mirrors the platform activity-result API used by ACTION_OPEN_DOCUMENT_TREE.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_TREE) return
        val uri = data?.data
        if (resultCode == RESULT_OK && uri != null) {
            val persistable = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            runCatching { contentResolver.takePersistableUriPermission(uri, persistable) }
                .onSuccess { complete(uri, null) }
                .onFailure { complete(null, it.javaClass.simpleName) }
        } else {
            complete(null, "pickerCancelled")
        }
        finish()
    }

    private fun complete(uri: Uri?, error: String?) {
        resultUri = uri
        resultError = error
        completion.countDown()
    }

    companion object {
        private const val REQUEST_TREE = 41
        private const val EXTRA_INITIAL_URI = "initialUri"

        @Volatile private var resultUri: Uri? = null
        @Volatile private var resultError: String? = null
        @Volatile private var completion = CountDownLatch(1)

        fun launchIntent(activityContext: android.content.Context, initialUri: Uri): Intent =
            Intent(activityContext, SafTreeGrantActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(EXTRA_INITIAL_URI, initialUri)

        fun reset() {
            resultUri = null
            resultError = null
            completion = CountDownLatch(1)
        }

        fun awaitResult(timeoutSeconds: Long): Result<Uri> {
            if (!completion.await(timeoutSeconds, TimeUnit.SECONDS)) {
                return Result.failure(IllegalStateException("pickerTimeout"))
            }
            return resultUri?.let(Result.Companion::success)
                ?: Result.failure(IllegalStateException(resultError ?: "pickerResultMissing"))
        }
    }
}
