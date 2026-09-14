package md.vox.android.platformservices

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class OnDeviceSpeechTest {
    @Test fun apiAndExplicitAvailabilityAreBothRequired() {
        assertEquals(OnDeviceSpeechAvailability.REQUIRES_ANDROID_12, resolveOnDeviceSpeechCapability(30, true).availability)
        assertEquals(OnDeviceSpeechAvailability.NOT_AVAILABLE, resolveOnDeviceSpeechCapability(31, false).availability)
        assertEquals(OnDeviceSpeechAvailability.CHECK_FAILED, resolveOnDeviceSpeechCapability(36, null).availability)
        assertTrue(resolveOnDeviceSpeechCapability(36, true).canCreateExplicitOnDeviceRecognizer)
        assertFalse(resolveOnDeviceSpeechCapability(36, false).canCreateExplicitOnDeviceRecognizer)
    }
}
