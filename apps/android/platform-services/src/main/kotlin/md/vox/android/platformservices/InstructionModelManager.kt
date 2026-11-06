package md.vox.android.platformservices

import android.app.ActivityManager
import android.content.Context
import android.os.StatFs
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.URL
import java.security.MessageDigest
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

object InstructionModel {
    const val SOURCE_LABEL = "huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF"
    const val VERIFICATION_DISCLOSURE = "Apache-2.0 · SHA-256"
    const val ID = "qwen2.5-1.5b-instruct-q4_k_m"
    const val REVISION = "91cad51170dc346986eccefdc2dd33a9da36ead9"
    const val BYTES = 1_117_320_736L
    const val SHA256 = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
    const val URL = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/$REVISION/qwen2.5-1.5b-instruct-q4_k_m.gguf"
}

enum class InstructionModelPhase { ABSENT, INSTALLING, READY, FAILED }
data class InstructionModelState(val phase: InstructionModelPhase, val progress: Float = 0f, val failureCode: String? = null)

/** Only public model bytes cross this network boundary; it never accepts capture text. */
class InstructionModelManager private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val directory = File(appContext.noBackupFilesDir, "instruction-model-v1").apply { mkdirs() }
    private val model = File(directory, "${InstructionModel.ID}.gguf")
    private val partial = File(directory, "model.installing")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var installation: Job? = null
    private val storage = Mutex()
    private val mutableState = MutableStateFlow(InstructionModelState(InstructionModelPhase.ABSENT))
    val state = mutableState.asStateFlow()

    init {
        partial.delete()
        scope.launch { storage.withLock {
            try { if (verifyOnWorker() != null) mutableState.value = InstructionModelState(InstructionModelPhase.READY, 1f) }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { mutableState.value = InstructionModelState(InstructionModelPhase.FAILED, failureCode = "invalidModelChecksum") }
        } }
    }

    suspend fun verifiedModel(): File? = withContext(Dispatchers.IO) { storage.withLock {
        val verified = try { verifyOnWorker() }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { null }
        if (verified == null && mutableState.value.phase == InstructionModelPhase.READY) {
            mutableState.value = InstructionModelState(InstructionModelPhase.FAILED, failureCode = "invalidModelChecksum")
        }
        verified
    } }

    private suspend fun verifyOnWorker(): File? {
        if (model.length() != InstructionModel.BYTES) return null
        val digest = MessageDigest.getInstance("SHA-256")
        model.inputStream().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                currentCoroutineContext().ensureActive()
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return model.takeIf { digest.digest().joinToString("") { "%02x".format(it) } == InstructionModel.SHA256 }
    }

    @Synchronized fun install() {
        if (installation?.isActive == true || mutableState.value.phase == InstructionModelPhase.READY) return
        installation = scope.launch { storage.withLock {
            if (mutableState.value.phase == InstructionModelPhase.READY) return@withLock
            installStream { URL(InstructionModel.URL).openConnection().apply {
            connectTimeout = 30_000; readTimeout = 30_000
        }.getInputStream() } } }
    }

    /** Exact public-model imports use the same verification and atomic publication as downloads. */
    suspend fun installImported(input: InputStream) = withContext(Dispatchers.IO) { input.use { storage.withLock { installStream { it } } } }

    private suspend fun installStream(open: () -> InputStream) {
        val hadReadyModel = mutableState.value.phase == InstructionModelPhase.READY
        mutableState.value = InstructionModelState(InstructionModelPhase.INSTALLING)
        try {
            val info = ActivityManager.MemoryInfo()
            (appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
            check(info.totalMem >= 3_000_000_000L && !info.lowMemory) { "instructionDeviceMemory" }
            check(StatFs(directory.path).availableBytes > InstructionModel.BYTES + 128_000_000L) { "instructionDeviceStorage" }
            val digest = MessageDigest.getInstance("SHA-256")
            var copied = 0L
            open().use { source -> FileOutputStream(partial).use { destination ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    currentCoroutineContext().ensureActive()
                    val count = source.read(buffer)
                    if (count < 0) break
                    copied += count
                    check(copied <= InstructionModel.BYTES) { "instructionModelSize" }
                    digest.update(buffer, 0, count)
                    destination.write(buffer, 0, count)
                    mutableState.value = InstructionModelState(InstructionModelPhase.INSTALLING, copied.toFloat() / InstructionModel.BYTES)
                }
                destination.fd.sync()
            } }
            check(copied == InstructionModel.BYTES && digest.digest().joinToString("") { "%02x".format(it) } == InstructionModel.SHA256) { "instructionModelDigest" }
            check(partial.renameTo(model)) { "instructionModelPublish" }
            mutableState.value = InstructionModelState(InstructionModelPhase.READY, 1f)
        } catch (cancelled: CancellationException) {
            mutableState.value = InstructionModelState(if (hadReadyModel) InstructionModelPhase.READY else InstructionModelPhase.ABSENT, if (hadReadyModel) 1f else 0f)
            throw cancelled
        } catch (error: Exception) {
            val code = when (error.message) {
                "instructionDeviceMemory" -> "insufficientDeviceMemory"
                "instructionDeviceStorage" -> "insufficientStorage"
                else -> "invalidModelChecksum"
            }
            mutableState.value = InstructionModelState(if (hadReadyModel) InstructionModelPhase.READY else InstructionModelPhase.FAILED, if (hadReadyModel) 1f else 0f, code)
        } finally { partial.delete() }
    }

    @Synchronized fun cancel() { installation?.cancel() }
    @Synchronized fun delete() {
        if (installation?.isActive == true) return
        scope.launch { storage.withLock {
            model.delete()
            mutableState.value = InstructionModelState(InstructionModelPhase.ABSENT)
        } }
    }
    companion object {
        @Volatile private var instance: InstructionModelManager? = null
        fun get(context: Context): InstructionModelManager = instance ?: synchronized(this) {
            instance ?: InstructionModelManager(context.applicationContext).also { instance = it }
        }
    }
}
