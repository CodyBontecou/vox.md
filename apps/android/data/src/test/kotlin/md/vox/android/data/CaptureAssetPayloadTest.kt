package md.vox.android.data

import kotlinx.serialization.json.jsonPrimitive
import md.vox.android.capturedomain.CaptureAttachment
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CapturePreset
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class CaptureAssetPayloadTest {
    @Test
    fun arbitraryFilesAndImagesBecomeOrderedHashBoundAssetDescriptors() {
        val attachments = listOf(
            attachment(
                id = "11111111-1111-4111-8111-111111111111",
                name = "Camera Photo.JPEG",
                mediaType = "image/jpeg",
                length = 4_096,
                hash = "a".repeat(64),
            ),
            attachment(
                id = "22222222-2222-4222-8222-222222222222",
                name = "Quarterly archive.tar.gz",
                mediaType = "application/gzip",
                length = 9_001,
                hash = "b".repeat(64),
            ),
        )

        val payloads = captureAssetPayloads(attachments)

        assertEquals(attachments.map(CaptureAttachment::id), payloads.map { it.getValue("id").jsonPrimitive.content })
        assertEquals(attachments.map(CaptureAttachment::id), payloads.map { it.getValue("sourceID").jsonPrimitive.content })
        assertEquals(listOf("image/jpeg", "application/gzip"), payloads.map { it.getValue("mediaType").jsonPrimitive.content })
        assertEquals(listOf("jpeg", "gz"), payloads.map { it.getValue("safeExtension").jsonPrimitive.content })
        assertEquals(listOf("a".repeat(64), "b".repeat(64)), payloads.map { it.getValue("sha256").jsonPrimitive.content })
        assertEquals(listOf("4096", "9001"), payloads.map { it.getValue("length").jsonPrimitive.content })
        assertEquals(listOf("safeStem", "safeStem"), payloads.map { it.getValue("originalNamePolicy").jsonPrimitive.content })
    }

    @Test
    fun unsafeOrOversizedExtensionsAreDiscardedFromTheControlPlane() {
        val payloads = captureAssetPayloads(
            listOf(
                attachment("33333333-3333-4333-8333-333333333333", "payload.bad-ext", "application/octet-stream", 1, "c".repeat(64)),
                attachment("44444444-4444-4444-8444-444444444444", "payload.abcdefghijklmnopq", "application/octet-stream", 1, "d".repeat(64)),
            ),
        )

        assertEquals(listOf("", ""), payloads.map { it.getValue("safeExtension").jsonPrimitive.content })
    }

    @Test
    fun scanAndSketchSourcesStayInThePackageWhileHiddenDerivativesStayOutOfMarkdown() {
        val attachments = listOf(
            attachment("11111111-1111-4111-8111-111111111111", "Scanned page 01.jpg", "image/jpeg", 100, "a".repeat(64)),
            attachment("22222222-2222-4222-8222-222222222222", "Scanned document.pdf", "application/pdf", 200, "b".repeat(64)),
            attachment("33333333-3333-4333-8333-333333333333", "Scanned document OCR.txt", "text/plain; charset=utf-8", 30, "c".repeat(64), false),
            attachment("44444444-4444-4444-8444-444444444444", "Sketch.png", "image/png", 400, "d".repeat(64)),
            attachment("55555555-5555-4555-8555-555555555555", "Sketch.voxsketch.json", "application/vnd.vox.sketch+json", 90, "e".repeat(64), false),
        )

        assertEquals(attachments.map(CaptureAttachment::id), captureAssetPayloads(attachments).map { it.getValue("id").jsonPrimitive.content })
        val markdown = composeCaptureRequestText(
            body = "Captured text",
            attachments = attachments,
            preset = CapturePreset(
                id = "66666666-6666-4666-8666-666666666666",
                name = "Media",
                symbol = "paperclip",
                revision = 1,
                logicalFolder = "Inbox",
                noteNameTemplate = "media-{id}",
                metadataFields = listOf(CaptureMetadataField("source", "media-test")),
            ),
            imageDescriptions = mapOf("44444444-4444-4444-8444-444444444444" to "Handwritten diagram"),
        )
        assertTrue(markdown.contains("Scanned page 01.jpg"))
        assertTrue(markdown.contains("Scanned document.pdf"))
        assertTrue(markdown.contains("Sketch.png|Handwritten diagram"))
        assertFalse(markdown.contains("Scanned document OCR.txt"))
        assertFalse(markdown.contains("Sketch.voxsketch.json"))
    }

    private fun attachment(
        id: String,
        name: String,
        mediaType: String,
        length: Long,
        hash: String,
        includeInMarkdown: Boolean = true,
    ) = CaptureAttachment(
        id = id,
        displayName = name,
        vaultFileName = "$id-$name",
        mediaType = mediaType,
        byteCount = length,
        sha256 = hash,
        includeInMarkdown = includeInMarkdown,
    )
}
