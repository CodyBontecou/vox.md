package md.vox.android

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class URLDeliveryInstrumentationTest {
    private val context: Context by lazy {
        val base: Context = ApplicationProvider.getApplicationContext()
        val directory = File(base.noBackupFilesDir, "url-parity-test-${UUID.randomUUID()}").apply { mkdirs() }
        object : android.content.ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getNoBackupFilesDir(): File = directory
        }
    }
    @org.junit.After fun cleanup() { context.noBackupFilesDir.deleteRecursively() }
    private class Connection(private val code: Int = 204, private val failWrite: Boolean = false) : HttpURLConnection(URL("https://example.invalid")) {
        val sent = ByteArrayOutputStream()
        override fun disconnect() {}
        override fun usingProxy() = false
        override fun connect() {}
        override fun getOutputStream(): OutputStream {
            if (failWrite) throw java.io.IOException("synthetic interrupted send")
            return sent
        }
        override fun getResponseCode() = code
    }

    @Test fun encryptedBodyCredentialsAndFrozenEndpointDeliverOnlyAfterAdmission() = runBlocking {
        val id = UUID.randomUUID().toString()
        val connection = Connection()
        var opened = 0
        val outbox = URLDeliveryOutbox(context) { uri ->
            assertEquals("https://example.invalid/private-original", uri.toString()); opened++; connection
        }
        val original = outbox.saveCredentials(URLDeliveryCredentials("https://example.invalid/private-original", "sensitive-token", mapOf("X-API-Key" to "header-secret")))
        outbox.prepare(id, "private capture", 1_234, original)
        outbox.saveCredentials(URLDeliveryCredentials("https://other.invalid/new-preset"))
        val files = File(context.noBackupFilesDir, "url-delivery-secrets").listFiles().orEmpty()
        for (file in files) {
            val raw = file.readBytes().toString(Charsets.ISO_8859_1)
            for (secret in listOf("private capture", "sensitive-token", "private-original", "header-secret")) assertFalse(raw.contains(secret))
        }
        outbox.drain { false }; assertEquals(0, opened)
        outbox.admit(id)
        outbox.drain { false }; assertEquals(1, opened)
        assertFalse(connection.instanceFollowRedirects)
        assertEquals(id, connection.getRequestProperty("Idempotency-Key"))
        assertEquals("Bearer sensitive-token", connection.getRequestProperty("Authorization"))
        assertTrue(connection.sent.toString("UTF-8").contains("private capture"))
        assertEquals(URLDeliveryPhase.DELIVERED, outbox.receipts().single { it.id == id }.phase)
        assertFalse(File(context.noBackupFilesDir, "url-delivery-secrets/$id").exists())
        outbox.drain { true }; assertEquals(1, opened)
    }

    @Test fun interruptedSendIsUnknownAndNeverAutomaticallyReplayed() = runBlocking {
        val id = UUID.randomUUID().toString(); var sends = 0
        val outbox = URLDeliveryOutbox(context) { sends++; Connection(failWrite = true) }
        val settings = outbox.saveCredentials(URLDeliveryCredentials("https://example.invalid/hook"))
        outbox.prepare(id, "retained payload", 123L, settings); outbox.admit(id)
        outbox.drain { true }
        assertEquals(URLDeliveryPhase.UNKNOWN, outbox.receipts().single { it.id == id }.phase)
        URLDeliveryOutbox(context) { error("must not replay") }.drain { true }
        assertEquals(1, sends)
        assertTrue(File(context.noBackupFilesDir, "url-delivery-secrets/$id").exists())
        outbox.discard(id)
        assertFalse(File(context.noBackupFilesDir, "url-delivery-secrets/$id").exists())
    }

    @Test fun explicitRetryReusesKeyAndCredentialRepairCannotRetargetPayload() = runBlocking {
        val id = UUID.randomUUID().toString()
        val connections = mutableListOf<Connection>()
        val outbox = URLDeliveryOutbox(context) {
            Connection(if (connections.isEmpty()) 401 else 204).also(connections::add)
        }
        outbox.prepare(id, "retained payload", 123L, outbox.saveCredentials(URLDeliveryCredentials("https://example.invalid/hook", "expired")))
        outbox.admit(id); outbox.drain { true }
        assertTrue(runCatching { outbox.reauthorize(id, URLDeliveryCredentials("https://other.invalid/hook", "fresh")) }.isFailure)
        outbox.reauthorize(id, URLDeliveryCredentials("https://example.invalid/hook", "fresh"))
        outbox.retry(id); outbox.drain { true }
        assertEquals(2, connections.size)
        assertEquals(id, connections[0].getRequestProperty("Idempotency-Key"))
        assertEquals(id, connections[1].getRequestProperty("Idempotency-Key"))
        assertEquals("Bearer fresh", connections[1].getRequestProperty("Authorization"))
        assertEquals(URLDeliveryPhase.DELIVERED, outbox.receipts().single { it.id == id }.phase)
    }

    @Test fun redirectIsRetainedAsFailureWithoutFollowingIt() = runBlocking {
        val id = UUID.randomUUID().toString(); val connection = Connection(302)
        val outbox = URLDeliveryOutbox(context) { connection }
        outbox.prepare(id, "retained payload", 123L, outbox.saveCredentials(URLDeliveryCredentials("https://example.invalid/hook")))
        outbox.admit(id); outbox.drain { true }
        val receipt = outbox.receipts().single { it.id == id }
        assertEquals(URLDeliveryPhase.FAILED, receipt.phase); assertEquals(302, receipt.code)
        assertFalse(connection.instanceFollowRedirects)
        outbox.discard(id)
    }
}
