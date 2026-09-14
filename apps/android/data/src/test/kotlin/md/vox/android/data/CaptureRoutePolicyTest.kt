package md.vox.android.data

import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CaptureMetadataScope
import md.vox.android.capturedomain.CaptureLocationOutputMode
import md.vox.android.capturedomain.CaptureLocationPrecision
import md.vox.android.capturedomain.CaptureLocationField
import md.vox.android.capturedomain.CaptureLocationStructuredField
import md.vox.android.capturedomain.CaptureMissingHeadingBehavior
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetLocationPolicy
import md.vox.android.capturedomain.CaptureLocationLabelLookupClass
import md.vox.android.capturedomain.CURRENT_LOCATION_LABEL_CONSENT_VERSION
import md.vox.android.capturedomain.CaptureRollingPeriod
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.resolvingEntryTemplate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureRoutePolicyTest {
    @Test
    fun newAndRollingTargetsMapToExactCoreOperationsAndPolicies() {
        val fresh = preset()
        assertEquals("newNote", captureOperationFor(fresh))
        assertEquals("deterministicSuffix", captureRoutePolicyFor(fresh).getValue("collisionPolicy").jsonPrimitive.content)
        assertFalse("placement" in captureRoutePolicyFor(fresh))

        CaptureRollingPeriod.entries.forEach { period ->
            val rolling = preset(
                noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE,
                rollingPeriod = period,
                noteNameTemplate = "{period}.md",
            )
            val route = captureRoutePolicyFor(rolling)
            assertEquals("rollingNote", captureOperationFor(rolling))
            assertEquals("reuseIfHashMatches", route.getValue("collisionPolicy").jsonPrimitive.content)
            assertEquals("append", route.getValue("placement").jsonPrimitive.content)
            assertEquals(period.name.lowercase(), route.getValue("rollingPeriod").jsonPrimitive.content)
            assertEquals(listOf("Journal"), route.getValue("logicalFolder").jsonArray.map { it.jsonPrimitive.content })
            assertEquals("{period}.md", route.getValue("noteNameTemplate").jsonPrimitive.content)
        }
    }

    @Test
    fun existingTargetSplitsRelativeMarkdownPathAndMapsAllPlacements() {
        val expectedOperations = mapOf(
            CapturePlacementKind.APPEND to "existingNoteAppend",
            CapturePlacementKind.PREPEND to "existingNotePrepend",
            CapturePlacementKind.BENEATH_HEADING to "existingNoteHeading",
        )
        expectedOperations.forEach { (placement, operation) ->
            val existing = preset(
                noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE,
                existingNotePath = "Journal/Meetings/standup.md",
                placement = placement,
                headingTitle = "Inbox",
            )
            val route = captureRoutePolicyFor(existing)
            assertEquals(operation, captureOperationFor(existing))
            assertEquals("fail", route.getValue("collisionPolicy").jsonPrimitive.content)
            assertEquals(
                listOf("Journal", "Meetings"),
                route.getValue("logicalFolder").jsonArray.map { it.jsonPrimitive.content },
            )
            assertEquals("standup.md", route.getValue("noteNameTemplate").jsonPrimitive.content)
            assertEquals(
                placement.name.lowercase().replace("beneath_heading", "beneathHeading"),
                route.getValue("placement").jsonPrimitive.content,
            )
        }
    }

    @Test
    fun headingRouteCarriesExactCreateAndFailPolicies() {
        CaptureMissingHeadingBehavior.entries.forEach { behavior ->
            val existing = preset(
                noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE,
                existingNotePath = "Journal/inbox.md",
                placement = CapturePlacementKind.BENEATH_HEADING,
                headingTitle = "Inbox",
                headingLevel = 3,
                missingHeadingBehavior = behavior,
            )
            val route = captureRoutePolicyFor(existing)
            assertEquals("Inbox", route.getValue("headingTitle").jsonPrimitive.content)
            assertEquals(3, route.getValue("headingLevel").jsonPrimitive.content.toInt())
            assertEquals(behavior.name.lowercase(), route.getValue("missingHeadingBehavior").jsonPrimitive.content)
        }
    }

    @Test
    fun formattingPresetMapsFoldersPrefixesSuffixesMetadataAndRetryMarker() {
        val document = preset().copy(
            attachmentsFolder = "Media/Captures",
            entryPrefix = "- {date} ",
            entrySuffix = " #inbox",
            metadataFields = listOf(CaptureMetadataField("type", "capture")),
            metadataScope = CaptureMetadataScope.DOCUMENT,
            retryProtectionEnabled = true,
        )
        val route = captureRoutePolicyFor(document)
        val metadata = captureMetadataPolicyFor(document)
        assertEquals(
            listOf("Media", "Captures"),
            route.getValue("attachmentFolder").jsonArray.map { it.jsonPrimitive.content },
        )
        assertEquals("- {date} ", route.getValue("entryPrefix").jsonPrimitive.content)
        assertEquals(" #inbox", route.getValue("entrySuffix").jsonPrimitive.content)
        assertEquals("voxCaptureCommentV1", captureRetryMarkerPolicyFor(document))
        assertEquals("document", metadata.getValue("scope").jsonPrimitive.content)
        assertEquals("merge", metadata.getValue("frontmatterMode").jsonPrimitive.content)
        assertEquals(
            "type",
            metadata.getValue("orderedFields").jsonArray.single().jsonObject.getValue("name").jsonPrimitive.content,
        )

        val entry = document.copy(metadataScope = CaptureMetadataScope.ENTRY, retryProtectionEnabled = false)
        val entryMetadata = captureMetadataPolicyFor(entry)
        assertEquals("entry", entryMetadata.getValue("scope").jsonPrimitive.content)
        assertEquals("none", entryMetadata.getValue("frontmatterMode").jsonPrimitive.content)
        assertEquals("none", captureRetryMarkerPolicyFor(entry))
    }

    @Test
    fun reusableAndOneShotEntryTemplatesFreezeIntoTheExactCoreRoutePolicy() {
        val bound = CaptureEntryTemplate(
            id = "22222222-2222-4222-8222-222222222222",
            name = "Bound",
            entryPrefix = "bound-prefix",
            entrySuffix = "bound-suffix",
        )
        val oneShot = CaptureEntryTemplate(
            id = "33333333-3333-4333-8333-333333333333",
            name = "One shot",
            entryPrefix = "override-prefix",
            entrySuffix = "override-suffix",
        )
        val configured = preset().copy(
            entryPrefix = "safe-prefix",
            entrySuffix = "safe-suffix",
            entryTemplateID = bound.id,
        )

        val boundRoute = captureRoutePolicyFor(configured.resolvingEntryTemplate(listOf(bound, oneShot)))
        assertEquals("bound-prefix", boundRoute.getValue("entryPrefix").jsonPrimitive.content)
        assertEquals("bound-suffix", boundRoute.getValue("entrySuffix").jsonPrimitive.content)

        val overrideRoute = captureRoutePolicyFor(configured.resolvingEntryTemplate(listOf(bound, oneShot), oneShot.id))
        assertEquals("override-prefix", overrideRoute.getValue("entryPrefix").jsonPrimitive.content)
        assertEquals("override-suffix", overrideRoute.getValue("entrySuffix").jsonPrimitive.content)

        val missingRoute = captureRoutePolicyFor(configured.resolvingEntryTemplate(emptyList()))
        assertEquals("safe-prefix", missingRoute.getValue("entryPrefix").jsonPrimitive.content)
        assertEquals("safe-suffix", missingRoute.getValue("entrySuffix").jsonPrimitive.content)
    }

    @Test
    fun locationPolicyDefaultsDisabledAndMapsStructuredCityOrValidatedAdvancedOutputExactly() {
        val disabled = captureLocationPolicyFor(CapturePresetLocationPolicy())
        assertFalse(disabled.getValue("isEnabled").jsonPrimitive.content.toBoolean())
        assertFalse(disabled.getValue("metadataOutputEnabled").jsonPrimitive.content.toBoolean())
        assertEquals("exact", disabled.getValue("precision").jsonPrimitive.content)
        assertEquals("structured", disabled.getValue("outputMode").jsonPrimitive.content)
        assertEquals("locations", disabled.getValue("collectionKey").jsonPrimitive.content)
        assertEquals("none", disabled.getValue("labelLookupClass").jsonPrimitive.content)
        assertFalse(disabled.containsKey("labelConsentVersion"))

        val city = captureLocationPolicyFor(
            CapturePresetLocationPolicy(
                isEnabled = true,
                precision = CaptureLocationPrecision.CITY,
                metadataOutputEnabled = true,
            ),
        )
        assertEquals("city", city.getValue("precision").jsonPrimitive.content)
        assertEquals("structured", city.getValue("outputMode").jsonPrimitive.content)

        val renamed = captureLocationPolicyFor(
            CapturePresetLocationPolicy(
                isEnabled = true,
                metadataOutputEnabled = true,
                structuredFields = listOf(
                    CaptureLocationStructuredField(CaptureLocationField.LONGITUDE, "lng"),
                    CaptureLocationStructuredField(CaptureLocationField.COORDINATES, "point"),
                ),
            ),
        ).getValue("structuredFields").jsonArray
        assertEquals(listOf("longitude", "coordinates"), renamed.map { it.jsonObject.getValue("field").jsonPrimitive.content })
        assertEquals(listOf("lng", "point"), renamed.map { it.jsonObject.getValue("outputKey").jsonPrimitive.content })

        val advanced = captureLocationPolicyFor(
            CapturePresetLocationPolicy(
                isEnabled = true,
                metadataOutputEnabled = true,
                outputMode = CaptureLocationOutputMode.ADVANCED_YAML,
                collectionKey = "visits",
                advancedTemplate = "coordinates: \"{{coordinates}}\"",
            ),
        )
        assertEquals("advancedTemplate", advanced.getValue("outputMode").jsonPrimitive.content)
        assertEquals("visits", advanced.getValue("collectionKey").jsonPrimitive.content)
        assertEquals("coordinates: \"{{coordinates}}\"", advanced.getValue("advancedTemplate").jsonPrimitive.content)

        val consented = captureLocationPolicyFor(
            CapturePresetLocationPolicy(
                isEnabled = true,
                metadataOutputEnabled = true,
                labelLookupClass = CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK,
                labelConsentVersion = CURRENT_LOCATION_LABEL_CONSENT_VERSION,
            ),
        )
        assertEquals("systemMayUseNetwork", consented.getValue("labelLookupClass").jsonPrimitive.content)
        assertEquals(1, consented.getValue("labelConsentVersion").jsonPrimitive.content.toInt())
    }

    private fun preset(
        noteTargetKind: CaptureNoteTargetKind = CaptureNoteTargetKind.NEW_NOTE,
        rollingPeriod: CaptureRollingPeriod = CaptureRollingPeriod.DAILY,
        noteNameTemplate: String = "capture-{id}.md",
        existingNotePath: String = "",
        placement: CapturePlacementKind = CapturePlacementKind.APPEND,
        headingTitle: String = "",
        headingLevel: Int = 1,
        missingHeadingBehavior: CaptureMissingHeadingBehavior = CaptureMissingHeadingBehavior.FAIL,
    ) = CapturePreset(
        id = "33333333-3333-4333-8333-333333333333",
        name = "Route test",
        symbol = "description",
        revision = 1,
        logicalFolder = "Journal",
        noteNameTemplate = noteNameTemplate,
        metadataFields = emptyList(),
        noteTargetKind = noteTargetKind,
        rollingPeriod = rollingPeriod,
        existingNotePath = existingNotePath,
        placement = placement,
        headingTitle = headingTitle,
        headingLevel = headingLevel,
        missingHeadingBehavior = missingHeadingBehavior,
    )
}
