package md.vox.android.platformservices

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

internal sealed interface ImportedMediaDecodeResult {
    data class Success(val chunkCount: Int, val durationMillis: Long) : ImportedMediaDecodeResult
    data class Failure(val code: String) : ImportedMediaDecodeResult
}

/** Decodes a selected audio track to the recorder's canonical 16 kHz mono PCM format. */
internal object ImportedMediaDecoder {
    fun decode(context: Context, uri: Uri, stagingDirectory: File): ImportedMediaDecodeResult {
        if (uri.scheme != "content") return ImportedMediaDecodeResult.Failure("invalidMediaUri")
        if (stagingDirectory.exists() || !stagingDirectory.mkdir()) return ImportedMediaDecodeResult.Failure("mediaStaging")
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        var writer: ImportedPcmChunkWriter? = null
        return try {
            extractor = MediaExtractor().apply { setDataSource(context, uri, null) }
            val track = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return failure(stagingDirectory, "noAudioTrack")
            val inputFormat = extractor.getTrackFormat(track)
            val mime = inputFormat.getString(MediaFormat.KEY_MIME) ?: return failure(stagingDirectory, "unsupportedMedia")
            extractor.selectTrack(track)
            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(inputFormat, null, null, 0)
                start()
            }
            writer = ImportedPcmChunkWriter(stagingDirectory)
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            var outputEnded = false
            var idleIterations = 0
            var resampler: Pcm16MonoResampler? = null
            while (!outputEnded && idleIterations < MAX_IDLE_ITERATIONS) {
                var progressed = false
                if (!inputEnded) {
                    val inputIndex = codec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val buffer = requireNotNull(codec.getInputBuffer(inputIndex)).apply { clear() }
                        val count = extractor.readSampleData(buffer, 0)
                        if (count < 0) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            codec.queueInputBuffer(inputIndex, 0, count, extractor.sampleTime.coerceAtLeast(0), 0)
                            extractor.advance()
                        }
                        progressed = true
                    }
                }
                when (val outputIndex = codec.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        resampler = resamplerFor(codec.outputFormat)
                        progressed = true
                    }
                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    else -> if (outputIndex >= 0) {
                        if (info.size > 0) {
                            val output = requireNotNull(codec.getOutputBuffer(outputIndex))
                            output.position(info.offset)
                            output.limit(info.offset + info.size)
                            val decoded = ByteArray(info.size)
                            output.get(decoded)
                            val converter = resampler ?: resamplerFor(codec.outputFormat).also { resampler = it }
                            writer.write(converter.convert(decoded))
                        }
                        outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        codec.releaseOutputBuffer(outputIndex, false)
                        progressed = true
                    }
                }
                idleIterations = if (progressed) 0 else idleIterations + 1
            }
            if (!outputEnded) return failure(stagingDirectory, "mediaDecodeTimeout")
            val result = writer.finish()
            if (result.chunkCount == 0 || result.durationMillis == 0L) failure(stagingDirectory, "noDecodableAudio") else result
        } catch (_: SecurityException) {
            failure(stagingDirectory, "mediaPermission")
        } catch (error: Throwable) {
            failure(stagingDirectory, importedMediaFailureCode(error))
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { extractor?.release() }
            runCatching { writer?.closeAfterFailure() }
        }
    }

    private fun resamplerFor(format: MediaFormat): Pcm16MonoResampler {
        val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val encoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
            format.getInteger(MediaFormat.KEY_PCM_ENCODING)
        } else AudioFormat.ENCODING_PCM_16BIT
        require(sampleRate in 8_000..192_000 && channels in 1..8 && encoding == AudioFormat.ENCODING_PCM_16BIT)
        return Pcm16MonoResampler(sampleRate, channels)
    }

    private fun failure(directory: File, code: String): ImportedMediaDecodeResult.Failure {
        directory.deleteRecursively()
        return ImportedMediaDecodeResult.Failure(code)
    }

    private const val DEQUEUE_TIMEOUT_US = 10_000L
    private const val MAX_IDLE_ITERATIONS = 5_000
}

internal fun importedMediaFailureCode(error: Throwable): String =
    if (generateSequence(error) { it.cause }.any { it.message == "importedMediaTooLong" }) {
        "importedMediaTooLong"
    } else {
        "mediaDecode"
    }

internal class Pcm16MonoResampler(
    private val sourceSampleRate: Int,
    private val channelCount: Int,
) {
    private var phase = 0L
    private var remainder = byteArrayOf()

    fun convert(input: ByteArray): ByteArray {
        val combined = remainder + input
        val frameBytes = channelCount * 2
        val frameCount = combined.size / frameBytes
        remainder = combined.copyOfRange(frameCount * frameBytes, combined.size)
        val output = ByteArrayOutputStream((frameCount * TARGET_SAMPLE_RATE / sourceSampleRate + 1) * 2)
        repeat(frameCount) { frame ->
            var sum = 0
            repeat(channelCount) { channel ->
                val offset = frame * frameBytes + channel * 2
                val sample = ((combined[offset].toInt() and 0xff) or (combined[offset + 1].toInt() shl 8)).toShort().toInt()
                sum += sample
            }
            val mono = (sum / channelCount).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            phase += TARGET_SAMPLE_RATE
            while (phase >= sourceSampleRate) {
                output.write(mono and 0xff)
                output.write((mono shr 8) and 0xff)
                phase -= sourceSampleRate
            }
        }
        return output.toByteArray()
    }

    companion object { private const val TARGET_SAMPLE_RATE = 16_000 }
}

private class ImportedPcmChunkWriter(private val directory: File) {
    private var index = 0
    private var stream: FileOutputStream? = null
    private var temporary: File? = null
    private var currentBytes = 0
    private var totalBytes = 0L
    private var finished = false

    fun write(bytes: ByteArray) {
        var offset = 0
        while (offset < bytes.size) {
            if (stream == null) openChunk()
            val count = minOf(bytes.size - offset, CHUNK_BYTES - currentBytes)
            stream?.write(bytes, offset, count)
            offset += count
            currentBytes += count
            totalBytes += count
            require(totalBytes <= MAX_IMPORTED_PCM_BYTES) { "importedMediaTooLong" }
            if (currentBytes == CHUNK_BYTES) finishChunk()
        }
    }

    fun finish(): ImportedMediaDecodeResult.Success {
        if (currentBytes > 0) finishChunk() else closeEmptyChunk()
        finished = true
        return ImportedMediaDecodeResult.Success(index, totalBytes * 1_000L / PCM_BYTES_PER_SECOND)
    }

    fun closeAfterFailure() {
        if (!finished) {
            runCatching { stream?.close() }
            temporary?.delete()
        }
    }

    private fun openChunk() {
        temporary = File(directory, ".chunk-${index.toString().padStart(6, '0')}.part")
        stream = FileOutputStream(requireNotNull(temporary))
        currentBytes = 0
    }

    private fun finishChunk() {
        val source = requireNotNull(temporary)
        val output = requireNotNull(stream)
        output.flush()
        output.fd.sync()
        output.close()
        val target = File(directory, "chunk-${index.toString().padStart(6, '0')}.pcm")
        require(source.renameTo(target))
        FileOutputStream(target, true).use { it.fd.sync() }
        index += 1
        currentBytes = 0
        stream = null
        temporary = null
    }

    private fun closeEmptyChunk() {
        runCatching { stream?.close() }
        temporary?.delete()
        stream = null
        temporary = null
    }

    companion object {
        private const val CHUNK_BYTES = 64_000
        private const val PCM_BYTES_PER_SECOND = 32_000L
        private const val MAX_IMPORTED_PCM_BYTES = 512L * 1_024 * 1_024
    }
}
