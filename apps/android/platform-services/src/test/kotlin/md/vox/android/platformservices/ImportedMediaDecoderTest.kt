package md.vox.android.platformservices

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ImportedMediaDecoderTest {
    @Test fun preservesSpecificImportedMediaLimitFailure() {
        assertEquals(
            "importedMediaTooLong",
            importedMediaFailureCode(IllegalStateException("wrapper", IllegalArgumentException("importedMediaTooLong"))),
        )
        assertEquals("mediaDecode", importedMediaFailureCode(IllegalStateException("other")))
    }

    @Test fun downmixesStereoAndResamplesWithoutInventingFrames() {
        val input = byteArrayOf(
            0x10, 0x00, 0x30, 0x00,
            0x20, 0x00, 0x40, 0x00,
        )
        val output = Pcm16MonoResampler(sourceSampleRate = 16_000, channelCount = 2).convert(input)
        assertArrayEquals(byteArrayOf(0x20, 0x00, 0x30, 0x00), output)
    }

    @Test fun upsamplesEightKilohertzPcmToSixteenKilohertz() {
        val input = byteArrayOf(0x12, 0x00)
        val output = Pcm16MonoResampler(sourceSampleRate = 8_000, channelCount = 1).convert(input)
        assertEquals(4, output.size)
        assertArrayEquals(byteArrayOf(0x12, 0x00, 0x12, 0x00), output)
    }
}
