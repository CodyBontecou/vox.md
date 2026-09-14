package md.vox.android.platformservices

enum class SpeechModelEngine(val displayName: String) {
    VOSK("Vosk"),
    SHERPA_WHISPER("Whisper"),
    SHERPA_PARAKEET("Parakeet"),
}

data class SpeechModelRemoteFile(
    val relativePath: String,
    val downloadUrl: String,
    val expectedBytes: Long,
    val sha256: String,
) {
    init {
        require(relativePath.matches(Regex("^[A-Za-z0-9][A-Za-z0-9._/-]{0,159}$")))
        require(!relativePath.contains("..") && !relativePath.startsWith('/'))
        require(downloadUrl.startsWith("https://huggingface.co/"))
        require(expectedBytes > 0)
        require(sha256.matches(Regex("^[0-9a-f]{64}$")))
    }
}

/**
 * Immutable, integrity-pinned Android equivalents for the local model rows exposed by iOS.
 * Only model artifacts are downloaded. Audio, transcripts, and capture metadata never enter
 * these requests. ONNX INT8 variants keep the phone footprint materially below the FP32 packs.
 */
internal object SherpaSpeechModelCatalog {
    private const val WHISPER_TOKEN_BYTES = 816_730L
    private const val WHISPER_TOKEN_SHA256 = "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126"

    private fun remoteFile(
        repository: String,
        revision: String,
        name: String,
        bytes: Long,
        sha256: String,
    ) = SpeechModelRemoteFile(
        relativePath = name,
        downloadUrl = "https://huggingface.co/$repository/resolve/$revision/$name",
        expectedBytes = bytes,
        sha256 = sha256,
    )

    private fun whisper(
        id: String,
        name: String,
        repository: String,
        revision: String,
        modelStem: String,
        encoderBytes: Long,
        encoderSha256: String,
        decoderBytes: Long,
        decoderSha256: String,
        extraFiles: List<SpeechModelRemoteFile> = emptyList(),
        automaticRank: Int,
        minimumMemoryBytes: Long = 0,
        bundledByDefault: Boolean = false,
    ): SpeechModelDescriptor {
        val files = listOf(
            remoteFile(repository, revision, "$modelStem-encoder.int8.onnx", encoderBytes, encoderSha256),
            remoteFile(repository, revision, "$modelStem-decoder.int8.onnx", decoderBytes, decoderSha256),
            remoteFile(repository, revision, "$modelStem-tokens.txt", WHISPER_TOKEN_BYTES, WHISPER_TOKEN_SHA256),
        ) + extraFiles
        return SpeechModelDescriptor(
            id = id,
            displayName = name,
            languageTag = "Multilingual",
            archiveName = modelStem,
            approximateBytes = files.sumOf(SpeechModelRemoteFile::expectedBytes),
            engine = SpeechModelEngine.SHERPA_WHISPER,
            remoteFiles = files,
            modelStem = modelStem,
            modelDescription = "Private multilingual transcription on this device.",
            isMultilingual = true,
            automaticRank = automaticRank,
            minimumMemoryBytes = minimumMemoryBytes,
            bundledByDefault = bundledByDefault,
            licenseName = "MIT",
            licenseUrl = "https://github.com/openai/whisper/blob/main/LICENSE",
        )
    }

    private fun parakeet(
        id: String,
        name: String,
        repository: String,
        revision: String,
        encoderBytes: Long,
        encoderSha256: String,
        decoderBytes: Long,
        decoderSha256: String,
        joinerBytes: Long,
        joinerSha256: String,
        tokenBytes: Long,
        tokenSha256: String,
        isMultilingual: Boolean,
        description: String,
        automaticRank: Int,
    ): SpeechModelDescriptor {
        val files = listOf(
            remoteFile(repository, revision, "encoder.int8.onnx", encoderBytes, encoderSha256),
            remoteFile(repository, revision, "decoder.int8.onnx", decoderBytes, decoderSha256),
            remoteFile(repository, revision, "joiner.int8.onnx", joinerBytes, joinerSha256),
            remoteFile(repository, revision, "tokens.txt", tokenBytes, tokenSha256),
        )
        return SpeechModelDescriptor(
            id = id,
            displayName = name,
            languageTag = if (isMultilingual) "25 languages" else "English",
            archiveName = id,
            approximateBytes = files.sumOf(SpeechModelRemoteFile::expectedBytes),
            engine = SpeechModelEngine.SHERPA_PARAKEET,
            remoteFiles = files,
            modelStem = null,
            modelDescription = description,
            isMultilingual = isMultilingual,
            automaticRank = automaticRank,
            licenseName = "CC BY 4.0",
            licenseUrl = "https://creativecommons.org/licenses/by/4.0/",
        )
    }

    val models: List<SpeechModelDescriptor> = listOf(
        parakeet(
            id = "parakeet-v3",
            name = "Parakeet v3",
            repository = "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
            revision = "2bda32ec70b097a55adaa07d9a7173915b43cc78",
            encoderBytes = 652_184_281,
            encoderSha256 = "acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247",
            decoderBytes = 11_845_275,
            decoderSha256 = "179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e",
            joinerBytes = 6_355_277,
            joinerSha256 = "3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3",
            tokenBytes = 93_939,
            tokenSha256 = "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d",
            isMultilingual = true,
            description = "Fast, punctuation-aware transcription in 25 languages.",
            automaticRank = 700,
        ),
        parakeet(
            id = "parakeet-v2",
            name = "Parakeet v2",
            repository = "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8",
            revision = "1ab9323565ddb038682214b292f588070a538ce2",
            encoderBytes = 652_184_296,
            encoderSha256 = "a32b12d17bbbc309d0686fbbcc2987b5e9b8333a7da83fa6b089f0a2acd651ab",
            decoderBytes = 7_257_753,
            decoderSha256 = "b6bb64963457237b900e496ee9994b59294526439fbcc1fecf705b31a15c6b4e",
            joinerBytes = 1_739_080,
            joinerSha256 = "7946164367946e7f9f29a122407c3252b680dbae9a51343eb2488d057c3c43d2",
            tokenBytes = 9_384,
            tokenSha256 = "ec182b70dd42113aff6c5372c75cac58c952443eb22322f57bbd7f53977d497d",
            isMultilingual = false,
            description = "Fast, punctuation-aware transcription optimized for English.",
            automaticRank = 650,
        ),
        whisper(
            id = "ggml-large-v3-turbo",
            name = "Whisper Large v3 Turbo",
            repository = "csukuangfj/sherpa-onnx-whisper-turbo",
            revision = "2ca6ff69fc878651b770880507669577ac41c2ff",
            modelStem = "turbo",
            encoderBytes = 674_716_297,
            encoderSha256 = "b02dcdf54f348741e93fe732b67d933c8dcb6735655f710640143081db38878b",
            decoderBytes = 361_080_764,
            decoderSha256 = "20accd02388482eb3a46bd615631adfdc85e1eb2c7db9ea3f02a40ffe6b81547",
            extraFiles = listOf(
                remoteFile(
                    "csukuangfj/sherpa-onnx-whisper-turbo",
                    "2ca6ff69fc878651b770880507669577ac41c2ff",
                    "turbo-encoder.weights",
                    2_600_325_120,
                    "746f879ecf066450ab0cdecc05383380b85157270ff6c0a9fb7cfdd917036e12",
                ),
            ),
            automaticRank = 600,
            minimumMemoryBytes = 6_500_000_000,
        ),
        whisper(
            id = "ggml-medium",
            name = "Whisper Medium",
            repository = "csukuangfj/sherpa-onnx-whisper-medium",
            revision = "8c31d28503847560985df21f90e14f0c736e075e",
            modelStem = "medium",
            encoderBytes = 374_196_283,
            encoderSha256 = "1c54582b4d829de0089f6cb63bbbdb3bf7555398bacaf855fbecf1a84dfd193e",
            decoderBytes = 571_059_257,
            decoderSha256 = "595d00a338a365a7bfa0ca7f296cabc639583bef770ab6130df90f49a6412747",
            automaticRank = 500,
            minimumMemoryBytes = 3_500_000_000,
        ),
        whisper(
            id = "ggml-small",
            name = "Whisper Small",
            repository = "csukuangfj/sherpa-onnx-whisper-small",
            revision = "8f3c18b358db4d1f2fc1eae49d75cd20989e4309",
            modelStem = "small",
            encoderBytes = 112_442_483,
            encoderSha256 = "4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9",
            decoderBytes = 262_226_114,
            decoderSha256 = "acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee",
            automaticRank = 400,
            bundledByDefault = true,
        ),
        whisper(
            id = "ggml-base",
            name = "Whisper Base",
            repository = "csukuangfj/sherpa-onnx-whisper-base",
            revision = "bb53ee204431c90d314c1cc08d28d23e5b7927cc",
            modelStem = "base",
            encoderBytes = 29_120_534,
            encoderSha256 = "0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11",
            decoderBytes = 130_672_026,
            decoderSha256 = "9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d",
            automaticRank = 300,
        ),
        whisper(
            id = "ggml-tiny",
            name = "Whisper Tiny",
            repository = "csukuangfj/sherpa-onnx-whisper-tiny",
            revision = "65176e2deb88badc814a94058666cadccc29b61c",
            modelStem = "tiny",
            encoderBytes = 12_937_772,
            encoderSha256 = "d24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434",
            decoderBytes = 89_855_401,
            decoderSha256 = "d2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925",
            automaticRank = 200,
        ),
    )
}
