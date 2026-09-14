package md.vox.android.capturedomain

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureLocationLabelPolicyTest {
    @Test
    fun labelsAreRequestedOnlyForEnabledMetadataThatReferencesLabelFields() {
        assertFalse(CapturePresetLocationPolicy().requiresLabels)
        assertFalse(
            CapturePresetLocationPolicy(
                isEnabled = true,
                metadataOutputEnabled = true,
                structuredFields = listOf(CaptureLocationStructuredField(CaptureLocationField.COORDINATES)),
            ).requiresLabels,
        )
        assertTrue(
            CapturePresetLocationPolicy(
                isEnabled = true,
                metadataOutputEnabled = true,
                structuredFields = listOf(CaptureLocationStructuredField(CaptureLocationField.PLACE)),
            ).requiresLabels,
        )
        assertTrue(
            CapturePresetLocationPolicy(
                isEnabled = true,
                metadataOutputEnabled = true,
                outputMode = CaptureLocationOutputMode.ADVANCED_YAML,
                advancedTemplate = "city: {{ city }}",
            ).requiresLabels,
        )
    }

    @Test
    fun systemLookupRequiresTheCurrentExplicitConsentVersion() {
        assertFalse(CapturePresetLocationPolicy().hasValidSystemLabelConsent)
        assertFalse(
            CapturePresetLocationPolicy(
                labelLookupClass = CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK,
                labelConsentVersion = null,
            ).hasValidSystemLabelConsent,
        )
        assertTrue(
            CapturePresetLocationPolicy(
                labelLookupClass = CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK,
                labelConsentVersion = CURRENT_LOCATION_LABEL_CONSENT_VERSION,
            ).hasValidSystemLabelConsent,
        )
    }
}
