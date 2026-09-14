package md.vox.android.data

import md.vox.android.capturedomain.CaptureAttachment
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CapturePreset
import org.junit.Assert.assertEquals
import org.junit.Test

class ImageAttachmentMarkdownTest {
    private val attachment = CaptureAttachment(
        id = "9f7bb55f-1b2a-4bb0-8e8a-a727b983f747",
        displayName = "photo.jpg",
        vaultFileName = "9f7bb55f-photo.jpg",
        mediaType = "image/jpeg",
        byteCount = 42,
        sha256 = "0".repeat(64),
    )
    private val preset = CapturePreset(
        id = "33333333-3333-4333-8333-333333333333",
        name = "Default",
        symbol = "description",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "capture-{id}.md",
        metadataFields = emptyList(),
        attachmentsFolder = "Attachments",
    )
    private val audio = CaptureAttachment(
        id = "8e6aa44e-0a19-4976-9cb2-d909f8b6649e",
        displayName = "Recording.wav",
        vaultFileName = "8e6aa44e-Recording.wav",
        mediaType = "audio/wav",
        byteCount = 84,
        sha256 = "1".repeat(64),
    )

    @Test
    fun `local image description becomes the Obsidian embed alias`() {
        assertEquals(
            "![[Attachments/9f7bb55f-photo.jpg|Image may contain: Dog, grass.]]",
            renderAttachmentMarkdown(
                attachment,
                preset,
                "Image may contain: Dog, grass.",
            ),
        )
    }

    @Test
    fun `missing local evidence preserves the original filename alias`() {
        assertEquals(
            "![[Attachments/9f7bb55f-photo.jpg|photo.jpg]]",
            renderAttachmentMarkdown(attachment, preset, null),
        )
    }

    @Test
    fun `retained audio can be embedded above transcript text`() {
        assertEquals(
            "![[Attachments/8e6aa44e-Recording.wav|Recording.wav]]\n\nTranscript text",
            composeCaptureRequestText(
                body = "Transcript text",
                attachments = listOf(audio),
                preset = preset.copy(audioEmbedPlacement = CaptureAudioEmbedPlacement.BEFORE_TEXT),
            ),
        )
    }

    @Test
    fun `retained audio can be embedded below transcript text`() {
        assertEquals(
            "Transcript text\n\n![[Attachments/8e6aa44e-Recording.wav|Recording.wav]]",
            composeCaptureRequestText(
                body = "Transcript text",
                attachments = listOf(audio),
                preset = preset.copy(audioEmbedPlacement = CaptureAudioEmbedPlacement.AFTER_TEXT),
            ),
        )
    }

    @Test
    fun `audio payload remains capturable when no local transcript is available`() {
        assertEquals(
            "![[Attachments/8e6aa44e-Recording.wav|Recording.wav]]",
            composeCaptureRequestText(
                body = "",
                attachments = listOf(audio),
                preset = preset,
            ),
        )
    }

    @Test
    fun `retained audio without markdown embed preserves text and other attachments`() {
        assertEquals(
            "Transcript text\n\n![[Attachments/9f7bb55f-photo.jpg|photo.jpg]]",
            composeCaptureRequestText(
                body = "Transcript text",
                attachments = listOf(audio.copy(includeInMarkdown = false), attachment),
                preset = preset.copy(audioEmbedPlacement = CaptureAudioEmbedPlacement.BEFORE_TEXT),
            ),
        )
    }

    @Test
    fun `audio placement does not reorder non audio attachments`() {
        assertEquals(
            "![[Attachments/8e6aa44e-Recording.wav|Recording.wav]]\n\nTranscript text\n\n![[Attachments/9f7bb55f-photo.jpg|photo.jpg]]",
            composeCaptureRequestText(
                body = "Transcript text",
                attachments = listOf(attachment, audio),
                preset = preset.copy(audioEmbedPlacement = CaptureAudioEmbedPlacement.BEFORE_TEXT),
            ),
        )
    }
}
