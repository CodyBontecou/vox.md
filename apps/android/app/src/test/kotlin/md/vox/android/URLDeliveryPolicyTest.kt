package md.vox.android

import org.junit.Assert.*
import org.junit.Test

class URLDeliveryPolicyTest {
    @Test fun fullEndpointRemainsSecretWhileOriginIsSafeToDisplay() {
        val uri = URLDeliveryPolicy.validate(URLDeliveryCredentials("https://example.com:8443/private/secret-hook", "token", mapOf("X-Api-Key" to "secret")))
        assertEquals("https://example.com:8443", URLDeliveryPolicy.origin(uri))
    }
    @Test fun unsafeEndpointsAndHeaderInjectionFailClosed() {
        for (endpoint in listOf("http://example.com", "file:///tmp/note", "https://u:p@example.com/hook", "https://example.com/hook?token=secret", "https://example.com/#fragment")) {
            assertTrue(endpoint, runCatching { URLDeliveryPolicy.validate(URLDeliveryCredentials(endpoint)) }.isFailure)
        }
        for (header in listOf("Authorization", "Host", "Idempotency-Key", "Content-Length", "Cookie")) {
            assertTrue(runCatching { URLDeliveryPolicy.validate(URLDeliveryCredentials("https://example.com", headers = mapOf(header to "value"))) }.isFailure)
        }
        assertTrue(runCatching { URLDeliveryPolicy.validate(URLDeliveryCredentials("https://example.com", "token\r\nInjected: header")) }.isFailure)
    }
}
