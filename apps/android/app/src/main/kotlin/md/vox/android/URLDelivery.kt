package md.vox.android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import androidx.work.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import md.vox.android.capturedomain.CaptureURLDeliverySettings
import md.vox.android.data.AndroidDurableFileOps

internal data class URLDeliveryCredentials(val endpoint: String, val bearer: String = "", val headers: Map<String, String> = emptyMap())

/** A full endpoint is a secret. Snapshots and receipts expose only the scheme/host/port. */
internal object URLDeliveryPolicy {
    fun validate(credentials: URLDeliveryCredentials): URI {
        val uri = URI(credentials.endpoint.trim())
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.rawUserInfo == null && uri.rawFragment == null) { "httpsEndpointRequired" }
        require(credentials.endpoint.length <= 8_192 && uri.rawQuery == null) { "endpointQueryNotSupported" }
        require(credentials.bearer.length <= 8_192 && credentials.bearer.none(Char::isISOControl)) { "invalidBearer" }
        require(credentials.headers.size <= 16)
        credentials.headers.forEach { (key, value) ->
            require(key.matches(Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")) && key.lowercase() !in RESERVED_HEADERS) { "reservedHeader" }
            require(value.length <= 8_192 && value.none(Char::isISOControl)) { "invalidHeader" }
        }
        return uri
    }
    fun origin(uri: URI): String = URI(uri.scheme, null, uri.host, uri.port, null, null, null).toString()
    private val RESERVED_HEADERS = setOf("authorization", "host", "content-length", "content-type", "connection", "transfer-encoding", "idempotency-key", "cookie", "proxy-authorization")
}

/** AES-GCM binds every encrypted file to its opaque ID; files and keys are excluded from backup. */
internal class URLDeliverySecretStore(context: Context) {
    private val directory = File(context.noBackupFilesDir, "url-delivery-secrets")
    @Synchronized private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun write(id: String, bytes: ByteArray) {
        require(ID.matches(id)); require(bytes.size <= MAX_BYTES)
        directory.mkdirs()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()); updateAAD(id.toByteArray()) }
        val file = AtomicFile(File(directory, id))
        val output = file.startWrite()
        try {
            output.write(cipher.iv + cipher.doFinal(bytes)); file.finishWrite(output)
            AndroidDurableFileOps().syncDirectory(directory)
            AndroidDurableFileOps().syncDirectory(directory.parentFile!!)
        }
        catch (error: Throwable) { file.failWrite(output); throw error }
    }
    fun read(id: String): ByteArray {
        require(ID.matches(id))
        val file = AtomicFile(File(directory, id))
        require(file.baseFile.length() <= MAX_BYTES + 64)
        val bytes = file.readFully(); require(bytes.size >= 28)
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            updateAAD(id.toByteArray()); doFinal(bytes.copyOfRange(12, bytes.size))
        }
    }
    fun delete(id: String) { require(ID.matches(id)); AtomicFile(File(directory, id)).delete() }
    companion object {
        private const val ALIAS = "md.vox.url-delivery.v1"
        private const val MAX_BYTES = 1_048_576
        val ID = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    }
}

internal enum class URLDeliveryPhase { QUEUED, SENDING, DELIVERED, FAILED, UNKNOWN, DISCARDED }
internal data class URLDeliveryReceipt(val id: String, val origin: String, val phase: URLDeliveryPhase, val attempts: Int, val maxAttempts: Int, val code: Int? = null, val admitted: Boolean = false)

internal class URLDeliveryOutbox(context: Context, private val openConnection: (URI) -> HttpURLConnection = { it.toURL().openConnection() as HttpURLConnection }) {
    private val appContext = context.applicationContext
    private val secrets = URLDeliverySecretStore(appContext)
    private val directory = File(appContext.noBackupFilesDir, "url-delivery-receipts")

    fun saveCredentials(credentials: URLDeliveryCredentials): CaptureURLDeliverySettings {
        val uri = URLDeliveryPolicy.validate(credentials)
        val id = UUID.randomUUID().toString()
        secrets.write(id, buildJsonObject {
            put("endpoint", uri.toString()); put("bearer", credentials.bearer)
            put("headers", JsonObject(credentials.headers.mapValues { JsonPrimitive(it.value) }))
        }.toString().toByteArray())
        return CaptureURLDeliverySettings(true, id, URLDeliveryPolicy.origin(uri))
    }

    fun credentials(settings: CaptureURLDeliverySettings): URLDeliveryCredentials {
        val value = Json.parseToJsonElement(secrets.read(requireNotNull(settings.credentialID)).toString(Charsets.UTF_8)).jsonObject
        return URLDeliveryCredentials(value.getValue("endpoint").jsonPrimitive.content, value.getValue("bearer").jsonPrimitive.content,
            value.getValue("headers").jsonObject.mapValues { it.value.jsonPrimitive.content }).also(URLDeliveryPolicy::validate)
    }

    /** Staged before local capture admission. The worker checks the durable capture before sending. */
    fun prepare(id: String, text: String, createdAt: Long, settings: CaptureURLDeliverySettings) = synchronized(LOCK) {
        if (!settings.enabled || text.isEmpty()) return@synchronized
        require(URLDeliverySecretStore.ID.matches(id) && settings.maxAttempts in 1..10)
        if (receiptFile(id).baseFile.exists()) return@synchronized
        val credentials = credentials(settings)
        val origin = URLDeliveryPolicy.origin(URLDeliveryPolicy.validate(credentials))
        val body = buildJsonObject { put("id", id); put("text", text); put("date", java.time.Instant.ofEpochMilli(createdAt).toString()) }.toString()
        secrets.write(id, buildJsonObject {
            put("body", body); put("credentialID", requireNotNull(settings.credentialID))
        }.toString().toByteArray())
        save(URLDeliveryReceipt(id, origin, URLDeliveryPhase.QUEUED, 0, settings.maxAttempts))
    }

    fun receipts(): List<URLDeliveryReceipt> = synchronized(LOCK) {
        directory.listFiles().orEmpty().filter { it.extension == "json" }.mapNotNull { file ->
            runCatching { load(file.nameWithoutExtension) }.getOrNull()
        }.sortedBy { it.id }
    }
    fun admit(id: String) = synchronized(LOCK) {
        if (receiptFile(id).baseFile.exists()) save(load(id).copy(admitted = true))
    }
    fun pendingCredentials(id: String): URLDeliveryCredentials = synchronized(LOCK) {
        val envelope = Json.parseToJsonElement(secrets.read(id).toString(Charsets.UTF_8)).jsonObject
        credentials(CaptureURLDeliverySettings(credentialID = envelope.getValue("credentialID").jsonPrimitive.content))
    }
    fun reauthorize(id: String, replacement: URLDeliveryCredentials) = synchronized(LOCK) {
        val receipt = load(id)
        require(receipt.phase in setOf(URLDeliveryPhase.FAILED, URLDeliveryPhase.UNKNOWN))
        val original = pendingCredentials(id)
        // Updating authentication never grants permission to retarget retained capture content.
        require(URLDeliveryPolicy.validate(original) == URLDeliveryPolicy.validate(replacement)) { "endpointChanged" }
        val settings = saveCredentials(replacement)
        val envelope = Json.parseToJsonElement(secrets.read(id).toString(Charsets.UTF_8)).jsonObject.toMutableMap()
        envelope["credentialID"] = JsonPrimitive(requireNotNull(settings.credentialID))
        secrets.write(id, JsonObject(envelope).toString().toByteArray())
        save(receipt.copy(maxAttempts = maxOf(receipt.maxAttempts, receipt.attempts + 5)))
    }
    fun retry(id: String) = synchronized(LOCK) {
        val receipt = load(id)
        require(receipt.phase in setOf(URLDeliveryPhase.FAILED, URLDeliveryPhase.UNKNOWN) && receipt.attempts < receipt.maxAttempts)
        save(receipt.copy(phase = URLDeliveryPhase.QUEUED, code = null))
        URLDeliveryWorker.schedule(appContext)
    }
    fun discard(id: String) = synchronized(LOCK) {
        val receipt = load(id); require(receipt.phase != URLDeliveryPhase.SENDING)
        save(receipt.copy(phase = URLDeliveryPhase.DISCARDED)); secrets.delete(id)
    }

    /** WorkManager serializes senders; SENDING survives crashes and is never blindly replayed. */
    suspend fun drain(isAdmitted: suspend (String) -> Boolean) = withContext(Dispatchers.IO) {
        for (item in receipts()) {
            if (item.phase == URLDeliveryPhase.SENDING) {
                synchronized(LOCK) { save(load(item.id).copy(phase = URLDeliveryPhase.UNKNOWN)) }
                continue
            }
            if (item.phase != URLDeliveryPhase.QUEUED || (!item.admitted && !isAdmitted(item.id))) continue
            admit(item.id)
            send(item.id)
        }
    }

    private fun send(id: String) {
        val receipt = synchronized(LOCK) {
            val current = load(id)
            if (current.phase != URLDeliveryPhase.QUEUED || current.attempts >= current.maxAttempts) return
            current.copy(phase = URLDeliveryPhase.SENDING, attempts = current.attempts + 1).also(::save)
        }
        var connection: HttpURLConnection? = null
        var requestMayHaveBeenSent = false
        val outcome = try {
            val envelope = Json.parseToJsonElement(secrets.read(id).toString(Charsets.UTF_8)).jsonObject
            val credentials = credentials(CaptureURLDeliverySettings(credentialID = envelope.getValue("credentialID").jsonPrimitive.content))
            val endpoint = URLDeliveryPolicy.validate(credentials)
            check(URLDeliveryPolicy.origin(endpoint) == receipt.origin)
            val body = envelope.getValue("body").jsonPrimitive.content.toByteArray()
            connection = openConnection(endpoint)
            connection.apply {
                requestMethod = "POST"; instanceFollowRedirects = false; connectTimeout = 15_000; readTimeout = 30_000
                doOutput = true; useCaches = false
                setFixedLengthStreamingMode(body.size)
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Idempotency-Key", id)
                if (credentials.bearer.isNotEmpty()) setRequestProperty("Authorization", "Bearer ${credentials.bearer}")
                credentials.headers.forEach { (key, value) -> setRequestProperty(key, value) }
            }
            requestMayHaveBeenSent = true
            connection.outputStream.use { it.write(body) }
            val code = connection.responseCode
            receipt.copy(phase = if (code in 200..299) URLDeliveryPhase.DELIVERED else URLDeliveryPhase.FAILED, code = code)
        } catch (_: Exception) {
            receipt.copy(phase = if (requestMayHaveBeenSent) URLDeliveryPhase.UNKNOWN else URLDeliveryPhase.FAILED)
        } finally { connection?.disconnect() }
        synchronized(LOCK) {
            save(outcome)
            if (outcome.phase == URLDeliveryPhase.DELIVERED) secrets.delete(id)
        }
    }
    private fun receiptFile(id: String): AtomicFile {
        require(URLDeliverySecretStore.ID.matches(id)); directory.mkdirs()
        return AtomicFile(File(directory, "$id.json"))
    }
    private fun load(id: String): URLDeliveryReceipt {
        val value = Json.parseToJsonElement(receiptFile(id).readFully().toString(Charsets.UTF_8)).jsonObject
        return URLDeliveryReceipt(id, value.getValue("origin").jsonPrimitive.content, URLDeliveryPhase.valueOf(value.getValue("phase").jsonPrimitive.content),
            value.getValue("attempts").jsonPrimitive.int, value.getValue("maxAttempts").jsonPrimitive.int, value["code"]?.jsonPrimitive?.intOrNull, value["admitted"]?.jsonPrimitive?.booleanOrNull ?: false)
    }
    private fun save(receipt: URLDeliveryReceipt) {
        val bytes = buildJsonObject {
            put("admitted", receipt.admitted); put("origin", receipt.origin); put("phase", receipt.phase.name); put("attempts", receipt.attempts); put("maxAttempts", receipt.maxAttempts)
            receipt.code?.let { put("code", it) }
        }.toString().toByteArray()
        val file = receiptFile(receipt.id); val output = file.startWrite()
        try {
            output.write(bytes); file.finishWrite(output)
            AndroidDurableFileOps().syncDirectory(directory)
            AndroidDurableFileOps().syncDirectory(directory.parentFile!!)
        } catch (error: Throwable) { file.failWrite(output); throw error }
    }
    companion object { private val LOCK = Any() }
}

class URLDeliveryWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = try {
        val repository = (applicationContext as VoxApplication).compositionRoot.captureRepository
        URLDeliveryOutbox(applicationContext).drain(repository::hasDurableCapture)
        Result.success()
    } catch (_: Exception) { Result.retry() }
    companion object {
        fun schedule(context: Context) {
            val work = OneTimeWorkRequestBuilder<URLDeliveryWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build()
            WorkManager.getInstance(context).enqueueUniqueWork("url-delivery-v1", ExistingWorkPolicy.APPEND_OR_REPLACE, work)
        }
    }
}
