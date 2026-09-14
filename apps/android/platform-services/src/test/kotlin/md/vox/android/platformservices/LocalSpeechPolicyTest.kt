package md.vox.android.platformservices

import java.io.File
import java.io.ByteArrayInputStream
import kotlin.io.path.createTempDirectory
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalSpeechPolicyTest {
    @Test
    fun catalogUsesUniqueImmutableModelOnlyEndpointsAndExactRemoteManifests() {
        val models = SpeechModelCatalog.models

        assertTrue(models.isNotEmpty())
        assertEquals(models.size, models.map { it.id }.distinct().size)
        models.forEach { model ->
            assertTrue(model.approximateBytes >= 1_000_000)
            if (model.engine == SpeechModelEngine.VOSK) {
                assertTrue(model.downloadUrl.startsWith("https://alphacephei.com/vosk/models/"))
                assertTrue(model.downloadUrl.endsWith(".zip"))
                assertTrue(model.remoteFiles.isEmpty())
            } else {
                assertEquals(model.approximateBytes, model.remoteFiles.sumOf(SpeechModelRemoteFile::expectedBytes))
                assertEquals(model.remoteFiles.size, model.remoteFiles.map { it.relativePath }.distinct().size)
                assertTrue(model.remoteFiles.all { it.downloadUrl.matches(IMMUTABLE_HUGGING_FACE_URL) })
                assertTrue(remoteSpeechModelManifestSha256(model).matches(Regex("^[0-9a-f]{64}$")))
            }
        }
        assertEquals(
            setOf(
                "parakeet-v2",
                "parakeet-v3",
                "ggml-tiny",
                "ggml-base",
                "ggml-small",
                "ggml-medium",
                "ggml-large-v3-turbo",
            ),
            models.filter { it.engine != SpeechModelEngine.VOSK }.mapTo(mutableSetOf()) { it.id },
        )
    }

    @Test
    fun modelArchiveTargetRejectsTraversalAndAbsolutePaths() {
        val root = File(System.getProperty("java.io.tmpdir"), "vox-model-test").canonicalFile

        assertEquals(File(root, "conf/model.conf").canonicalFile, safeModelArchiveTarget(root, "conf/model.conf"))
        listOf("../outside", "conf/../../outside", "/tmp/outside", "").forEach { unsafe ->
            assertTrue(runCatching { safeModelArchiveTarget(root, unsafe) }.isFailure)
        }
    }

    @Test
    fun remoteInstallRequiresExactPrivateFilesAndManifestReceipt() {
        val root = createTempDirectory("vox-remote-model-").toFile()
        try {
            val descriptor = SpeechModelDescriptor(
                id = "fixture-model",
                displayName = "Fixture",
                languageTag = "English",
                archiveName = "fixture",
                approximateBytes = 3,
                engine = SpeechModelEngine.SHERPA_WHISPER,
                remoteFiles = listOf(
                    SpeechModelRemoteFile(
                        relativePath = "fixture.bin",
                        downloadUrl = "https://huggingface.co/owner/repo/resolve/0123456789abcdef0123456789abcdef01234567/fixture.bin",
                        expectedBytes = 3,
                        sha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                    ),
                ),
            )
            File(root, "fixture.bin").writeText("abc")
            File(root, "vox-model.properties").writeText(
                "version=2\nid=fixture-model\nengine=SHERPA_WHISPER\n" +
                    "manifestSha256=${remoteSpeechModelManifestSha256(descriptor)}\n",
            )
            assertTrue(isInstalledSpeechModelDirectory(descriptor, root))

            File(root, "fixture.bin").appendText("d")
            assertFalse(isInstalledSpeechModelDirectory(descriptor, root))
            File(root, "fixture.bin").writeText("abc")
            File(root, "vox-model.properties").writeText("version=2\nid=fixture-model\n")
            assertFalse(isInstalledSpeechModelDirectory(descriptor, root))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun bundledModelInstallVerifiesFilesAndWritesACompatibleReceipt() = runBlocking {
        val root = createTempDirectory("vox-bundled-model-").toFile()
        val bytes = "abc".toByteArray()
        val descriptor = SpeechModelDescriptor(
            id = "fixture-model",
            displayName = "Fixture",
            languageTag = "Multilingual",
            archiveName = "fixture",
            approximateBytes = bytes.size.toLong(),
            engine = SpeechModelEngine.SHERPA_WHISPER,
            remoteFiles = listOf(
                SpeechModelRemoteFile(
                    relativePath = "fixture.bin",
                    downloadUrl = "https://huggingface.co/owner/repo/resolve/0123456789abcdef0123456789abcdef01234567/fixture.bin",
                    expectedBytes = bytes.size.toLong(),
                    sha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                ),
            ),
            bundledByDefault = true,
        )
        try {
            installBundledSpeechModelFiles(
                descriptor = descriptor,
                staging = root,
                openAsset = { ByteArrayInputStream(bytes) },
            )

            assertTrue(isInstalledSpeechModelDirectory(descriptor, root))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun bundledModelInstallRejectsBytesThatDoNotMatchThePinnedDigest() = runBlocking {
        val root = createTempDirectory("vox-bundled-model-invalid-").toFile()
        val descriptor = SpeechModelDescriptor(
            id = "fixture-model",
            displayName = "Fixture",
            languageTag = "Multilingual",
            archiveName = "fixture",
            approximateBytes = 3,
            engine = SpeechModelEngine.SHERPA_WHISPER,
            remoteFiles = listOf(
                SpeechModelRemoteFile(
                    relativePath = "fixture.bin",
                    downloadUrl = "https://huggingface.co/owner/repo/resolve/0123456789abcdef0123456789abcdef01234567/fixture.bin",
                    expectedBytes = 3,
                    sha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                ),
            ),
            bundledByDefault = true,
        )
        try {
            assertTrue(
                runCatching {
                    installBundledSpeechModelFiles(
                        descriptor = descriptor,
                        staging = root,
                        openAsset = { ByteArrayInputStream("abd".toByteArray()) },
                    )
                }.isFailure,
            )
            assertFalse(isInstalledSpeechModelDirectory(descriptor, root))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun automaticSelectionPrefersExactLanguageThenLanguageThenEnglishThenFirstReady() {
        fun state(
            id: String,
            language: String,
            phase: SpeechModelInstallPhase = SpeechModelInstallPhase.READY,
            rank: Int = 100,
            multilingual: Boolean = false,
        ) =
            SpeechModelInstallState(
                SpeechModelDescriptor(
                    id,
                    id,
                    language,
                    "$id-archive",
                    1_000_000,
                    automaticRank = rank,
                    isMultilingual = multilingual,
                ),
                phase,
            )

        val models = listOf(
            state("english", "en-US"),
            state("french", "fr-FR"),
            state("canadian-french", "fr-CA"),
            state("german", "de-DE", SpeechModelInstallPhase.NOT_INSTALLED),
            state("multilingual", "Multilingual", rank = 500, multilingual = true),
        )
        assertEquals("canadian-french", automaticSpeechModelID(models, "fr_CA"))
        assertEquals("french", automaticSpeechModelID(models, "fr-BE"))
        assertEquals("multilingual", automaticSpeechModelID(models, "de-DE"))
        assertEquals("multilingual", automaticSpeechModelID(models.drop(1), "ja-JP"))
        assertNull(automaticSpeechModelID(models.map { it.copy(phase = SpeechModelInstallPhase.NOT_INSTALLED) }, "en-US"))
    }

    @Test
    fun highMemoryModelsAreRejectedBeforeDownloadOnUndersizedDevices() {
        val medium = requireNotNull(SpeechModelCatalog.find("ggml-medium"))
        val turbo = requireNotNull(SpeechModelCatalog.find("ggml-large-v3-turbo"))
        val tiny = requireNotNull(SpeechModelCatalog.find("ggml-tiny"))
        val small = requireNotNull(SpeechModelCatalog.find("ggml-small"))

        assertFalse(isSpeechModelSupportedByMemory(medium, 2_531_992_000))
        assertTrue(isSpeechModelSupportedByMemory(medium, 8_129_460_000))
        assertFalse(isSpeechModelSupportedByMemory(turbo, 4_000_000_000))
        assertTrue(isSpeechModelSupportedByMemory(turbo, 8_129_460_000))
        assertTrue(isSpeechModelSupportedByMemory(tiny, 2_531_992_000))
        assertTrue(small.bundledByDefault)
        assertEquals(listOf("ggml-small"), SpeechModelCatalog.models.filter { it.bundledByDefault }.map { it.id })
    }

    private companion object {
        val IMMUTABLE_HUGGING_FACE_URL = Regex(
            "^https://huggingface\\.co/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/resolve/[0-9a-f]{40}/[A-Za-z0-9._/-]+$",
        )
    }
}
