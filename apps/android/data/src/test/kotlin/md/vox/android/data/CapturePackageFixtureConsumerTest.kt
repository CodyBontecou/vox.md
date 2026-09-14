package md.vox.android.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import md.vox.android.capturedomain.*

/** Named executable consumer for the governed Android contract mirror. */
class CapturePackageFixtureConsumerTest {
    @Test fun production_codec_consumes_governed_fixtures() {
        val base = "contracts/v1/fixtures/android-capture-package/"
        val assets = resource(base + "valid-assets.json")
        val request = resource("contracts/v1/fixtures/capture-preparation-input/valid-android-m3-text-link.json")
        assertEquals("11111111-1111-4111-8111-111111111111", CapturePackageCodec.decodeAssets(assets).requestID)
        val queuedBytes = resource(base + "valid-queued-journal.json")
        val queued = CapturePackageCodec.decodeJournal(queuedBytes)
        assertEquals(0, queued.snapshot.revision)
        assertEquals(queuedBytes.toList(), CapturePackageCodec.encodeJournal(queued.snapshot, request, assets).toList())
        val journal = CapturePackageCodec.decodeJournal(resource(base + "valid-journal.json"))
        assertEquals(5, journal.snapshot.revision)
        CapturePackageCodec.verifyBinding(journal, request, assets)
        assertEquals("11111111-1111-4111-8111-111111111111", CapturePackageCodec.admitRequest(request).requestID)
        for (name in listOf("invalid-transition.json", "invalid-terminal-successor.json", "invalid-materialized-self-transition.json", "invalid-version.json")) {
            try {
                val bytes = resource(base + name)
                if (name == "invalid-version.json") CapturePackageCodec.decodeAssets(bytes) else CapturePackageCodec.decodeJournal(bytes)
                fail("fixture must fail: $name")
            } catch (_: PackageCodecException) { }
        }
    }

    @Test fun strictCanonicalDecoderRejectsMutations() {
        val valid = resource("contracts/v1/fixtures/android-capture-package/valid-assets.json")
        val text = valid.toString(Charsets.UTF_8)
        val mutations = listOf(valid.copyOf(valid.size - 1), text.replace("  \"assets\"", " \"assets\"").toByteArray(), text.replace("\"assetCount\": 0,", "\"assetCount\": 0,\n  \"assetCount\": 0,").toByteArray(), text.replace("\"schemaVersion\": 1", "\"unknown\": 0,\n  \"schemaVersion\": 1").toByteArray())
        mutations.forEach { bytes -> try { CapturePackageCodec.decodeAssets(bytes); fail("mutation accepted") } catch (_: PackageCodecException) { } }
    }

    @Test fun journalEncodingReplaysAndRequiresSuppliedFrontier() {
        val event = JournalEvent(0, null, CaptureState.QUEUED, JournalCode.ENQUEUED, 1)
        val inconsistent = JournalSnapshot("11111111-1111-4111-8111-111111111111", 1, CaptureState.PREPARING, null, listOf(event))
        try {
            CapturePackageCodec.encodeJournal(inconsistent, byteArrayOf(1), byteArrayOf(2))
            fail("inconsistent snapshot accepted")
        } catch (_: PackageCodecException) { }
    }

    @Test fun completePreparationBoundsAndSnapshotFailClosed() {
        val request = resource("contracts/v1/fixtures/capture-preparation-input/valid-android-m3-text-link.json").toString(Charsets.UTF_8)
        val mutations = listOf(
            request.replace("America/Los_Angeles", "Not/A_Zone"),
            request.replace("\"sequence\": 1", "\"sequence\": -1"),
            request.replace("https://example.invalid/synthetic", "ftp://example.invalid/synthetic"),
            request.replace("\"expectedCaseSensitivity\": \"sensitive\"", "\"expectedCaseSensitivity\": \"unknown\""),
            request.replace("33333333-3333-4333-8333-333333333333", "55555555-5555-4555-8555-555555555555"),
            request.replace(Regex("\"snapshotHash\": \"[0-9a-f]{64}\""), "\"snapshotHash\": \"${"0".repeat(64)}\""),
        )
        mutations.forEach { text -> try { CapturePackageCodec.admitRequest(text.toByteArray()); fail("request mutation accepted") } catch (_: PackageCodecException) { } }
        try { CapturePackageCodec.parseCanonical(ByteArray(CONTROL_LIMIT_BYTES + 1) { ' '.code.toByte() }); fail("oversized control accepted") } catch (_: PackageCodecException) { }
    }

    @Test fun currentAndroidProfileAcceptsFrozenCustomRoutingAndFrontmatter() {
        val original = Json.parseToJsonElement(
            resource("contracts/v1/fixtures/capture-preparation-input/valid-android-m3-text-link.json").toString(Charsets.UTF_8),
        ) as JsonObject
        val originalPreset = original.getValue("preset") as JsonObject
        val originalRoute = originalPreset.getValue("routePolicy") as JsonObject
        val customRoute = JsonObject(originalRoute.toMutableMap().apply {
            put("logicalFolder", JsonArray(listOf(JsonPrimitive("Journal"), JsonPrimitive("Daily"))))
            put("noteNameTemplate", JsonPrimitive("android-{id}.md"))
        })
        val customMetadata = JsonObject(
            mapOf(
                "finalNewline" to JsonPrimitive(true),
                "frontmatterMode" to JsonPrimitive("merge"),
                "lineEnding" to JsonPrimitive("lf"),
                "orderedFields" to JsonArray(
                    listOf(JsonObject(mapOf("name" to JsonPrimitive("source"), "value" to JsonPrimitive("android")))),
                ),
                "templatePolicy" to JsonPrimitive("none"),
            ),
        )
        val zeroedPreset = JsonObject(originalPreset.toMutableMap().apply {
            put("id", JsonPrimitive("55555555-5555-4555-8555-555555555555"))
            put("metadataPolicy", customMetadata)
            put("revision", JsonPrimitive(2))
            put("routePolicy", customRoute)
            put("snapshotHash", JsonPrimitive("0".repeat(64)))
        })
        val finalPreset = JsonObject(zeroedPreset.toMutableMap().apply {
            put("snapshotHash", JsonPrimitive(CapturePackageCodec.sha256(CapturePackageCodec.canonical(zeroedPreset))))
        })
        val customRequest = JsonObject(original.toMutableMap().apply { put("preset", finalPreset) })

        assertEquals(
            "11111111-1111-4111-8111-111111111111",
            CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(customRequest)).requestID,
        )
    }

    @Test fun currentAndroidTextLinkProfileAdmitsEveryGovernedEntrySource() {
        val original = Json.parseToJsonElement(
            resource("contracts/v1/fixtures/capture-preparation-input/valid-android-m3-text-link.json").toString(Charsets.UTF_8),
        ) as JsonObject
        for (source in listOf("app", "share", "keyboard", "widget", "shortcut", "watch", "wear")) {
            val request = JsonObject(original.toMutableMap().apply { put("captureSource", JsonPrimitive(source)) })
            assertEquals(source, CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(request)).captureSource)
        }
        val unsupported = JsonObject(original.toMutableMap().apply { put("captureSource", JsonPrimitive("voice")) })
        try {
            CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(unsupported))
            fail("unimplemented source accepted")
        } catch (_: PackageCodecException) { }
    }

    @Test fun currentAndroidProfileAdmitsHashBoundAssetsAndRecordingCorrelation() {
        val original = Json.parseToJsonElement(
            resource("contracts/v1/fixtures/capture-preparation-input/valid-android-m3-text-link.json").toString(Charsets.UTF_8),
        ) as JsonObject
        val assetID = "55555555-5555-4555-8555-555555555555"
        val asset = JsonObject(
            mapOf(
                "id" to JsonPrimitive(assetID),
                "kind" to JsonPrimitive("asset"),
                "sourceID" to JsonPrimitive(assetID),
                "mediaType" to JsonPrimitive("application/pdf"),
                "length" to JsonPrimitive(4_096),
                "sha256" to JsonPrimitive("a".repeat(64)),
                "safeExtension" to JsonPrimitive("pdf"),
                "originalNamePolicy" to JsonPrimitive("safeStem"),
            ),
        )
        val invocation = JsonObject((original.getValue("invocation") as JsonObject).toMutableMap().apply {
            put("originRecordingID", JsonPrimitive("66666666-6666-4666-8666-666666666666"))
        })
        val request = JsonObject(original.toMutableMap().apply {
            put("invocation", invocation)
            put("payloads", JsonArray((original.getValue("payloads") as JsonArray) + asset))
        })

        assertEquals(
            "11111111-1111-4111-8111-111111111111",
            CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(request)).requestID,
        )
    }

    @Test fun currentAndroidProfileAcceptsCoherentFrozenLocationAndRejectsPrecisionLeak() {
        val original = Json.parseToJsonElement(
            resource("contracts/v1/fixtures/capture-preparation-input/valid-android-m3-text-link.json").toString(Charsets.UTF_8),
        ) as JsonObject
        val originalPreset = original.getValue("preset") as JsonObject
        val locationPolicy = JsonObject(
            mapOf(
                "advancedTemplate" to JsonPrimitive(""),
                "collectionKey" to JsonPrimitive("locations"),
                "isEnabled" to JsonPrimitive(true),
                "metadataOutputEnabled" to JsonPrimitive(true),
                "outputMode" to JsonPrimitive("structured"),
                "precision" to JsonPrimitive("city"),
                "structuredFields" to JsonArray(
                    listOf(
                        JsonObject(mapOf("field" to JsonPrimitive("longitude"), "outputKey" to JsonPrimitive("lng"))),
                        JsonObject(mapOf("field" to JsonPrimitive("coordinates"), "outputKey" to JsonPrimitive("point"))),
                    ),
                ),
            ),
        )
        val zeroedPreset = JsonObject(originalPreset.toMutableMap().apply {
            put("locationPolicy", locationPolicy)
            put("snapshotHash", JsonPrimitive("0".repeat(64)))
        })
        val preset = JsonObject(zeroedPreset.toMutableMap().apply {
            put("snapshotHash", JsonPrimitive(CapturePackageCodec.sha256(CapturePackageCodec.canonical(zeroedPreset))))
        })
        val snapshot = JsonObject(
            mapOf(
                "accuracyMillimeters" to JsonPrimitive(4_250),
                "capturedAtEpochMilliseconds" to JsonPrimitive(1_700_000_000_123),
                "latitudeE6" to JsonPrimitive(18_470_000),
                "longitudeE6" to JsonPrimitive(-66_110_000),
                "precision" to JsonPrimitive("city"),
                "source" to JsonPrimitive("app"),
            ),
        )
        val invocation = JsonObject((original.getValue("invocation") as JsonObject).toMutableMap().apply {
            put("locationOutcome", JsonPrimitive("coordinatesFrozen"))
            put("locationSnapshot", snapshot)
        })
        val request = JsonObject(original.toMutableMap().apply {
            put("invocation", invocation)
            put("preset", preset)
        })
        assertEquals(
            "11111111-1111-4111-8111-111111111111",
            CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(request)).requestID,
        )

        val leaking = JsonObject(snapshot.toMutableMap().apply { put("latitudeE6", JsonPrimitive(18_465_500)) })
        val invalidInvocation = JsonObject(invocation.toMutableMap().apply { put("locationSnapshot", leaking) })
        val invalid = JsonObject(request.toMutableMap().apply { put("invocation", invalidInvocation) })
        try {
            CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(invalid))
            fail("city precision leak accepted")
        } catch (_: PackageCodecException) { }

        val unavailableInvocation = JsonObject((original.getValue("invocation") as JsonObject).toMutableMap().apply {
            put("locationOutcome", JsonPrimitive("unavailable"))
            put("locationAttemptedAtEpochMilliseconds", JsonPrimitive(1_700_000_000_123))
        })
        CaptureLocationUnavailableReason.entries.forEach { reason ->
            val reasonInvocation = JsonObject(unavailableInvocation.toMutableMap().apply {
                put("locationUnavailableReason", JsonPrimitive(reason.wireName))
            })
            val unavailable = JsonObject(request.toMutableMap().apply { put("invocation", reasonInvocation) })
            assertEquals(
                "11111111-1111-4111-8111-111111111111",
                CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(unavailable)).requestID,
            )
        }
        val invalidReason = JsonObject(unavailableInvocation.toMutableMap().apply {
            put("locationUnavailableReason", JsonPrimitive("network"))
        })
        try {
            CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(JsonObject(request.toMutableMap().apply {
                put("invocation", invalidReason)
            })))
            fail("unknown unavailable reason accepted")
        } catch (_: PackageCodecException) { }
    }

    @Test fun currentAndroidProfileFreezesDisclosedSystemLabelsAndRejectsConsentDrift() {
        val original = Json.parseToJsonElement(
            resource("contracts/v1/fixtures/capture-preparation-input/valid-android-m3-text-link.json").toString(Charsets.UTF_8),
        ) as JsonObject
        val originalPreset = original.getValue("preset") as JsonObject
        val locationPolicy = JsonObject(
            mapOf(
                "advancedTemplate" to JsonPrimitive(""),
                "collectionKey" to JsonPrimitive("locations"),
                "isEnabled" to JsonPrimitive(true),
                "labelConsentVersion" to JsonPrimitive(1),
                "labelLookupClass" to JsonPrimitive("systemMayUseNetwork"),
                "metadataOutputEnabled" to JsonPrimitive(true),
                "outputMode" to JsonPrimitive("structured"),
                "precision" to JsonPrimitive("exact"),
                "structuredFields" to JsonArray(
                    listOf("place", "city", "region", "country").map { field ->
                        JsonObject(mapOf("field" to JsonPrimitive(field), "outputKey" to JsonPrimitive(field)))
                    },
                ),
            ),
        )
        val zeroedPreset = JsonObject(originalPreset.toMutableMap().apply {
            put("locationPolicy", locationPolicy)
            put("snapshotHash", JsonPrimitive("0".repeat(64)))
        })
        val preset = JsonObject(zeroedPreset.toMutableMap().apply {
            put("snapshotHash", JsonPrimitive(CapturePackageCodec.sha256(CapturePackageCodec.canonical(zeroedPreset))))
        })
        val label = JsonObject(
            mapOf(
                "place" to JsonPrimitive("Café & Main"),
                "city" to JsonPrimitive("Montréal"),
                "region" to JsonPrimitive("Québec"),
                "country" to JsonPrimitive("Canada"),
            ),
        )
        val snapshot = JsonObject(
            mapOf(
                "accuracyMillimeters" to JsonPrimitive(12_300),
                "capturedAtEpochMilliseconds" to JsonPrimitive(1_700_000_000_123),
                "label" to label,
                "latitudeE6" to JsonPrimitive(45_501_235),
                "longitudeE6" to JsonPrimitive(-73_567_890),
                "precision" to JsonPrimitive("exact"),
                "source" to JsonPrimitive("app"),
            ),
        )
        val observation = JsonObject(
            mapOf(
                "consentVersion" to JsonPrimitive(1),
                "lookupClass" to JsonPrimitive("systemMayUseNetwork"),
                "outcome" to JsonPrimitive("frozen"),
                "requested" to JsonPrimitive(true),
            ),
        )
        val invocation = JsonObject((original.getValue("invocation") as JsonObject).toMutableMap().apply {
            put("locationLabelObservation", observation)
            put("locationOutcome", JsonPrimitive("labelFrozen"))
            put("locationSnapshot", snapshot)
        })
        val request = JsonObject(original.toMutableMap().apply {
            put("invocation", invocation)
            put("preset", preset)
        })
        assertEquals(
            "11111111-1111-4111-8111-111111111111",
            CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(request)).requestID,
        )

        val driftedObservation = JsonObject(observation.toMutableMap().apply {
            put("consentVersion", JsonPrimitive(2))
        })
        val driftedInvocation = JsonObject(invocation.toMutableMap().apply {
            put("locationLabelObservation", driftedObservation)
        })
        try {
            CapturePackageCodec.admitRequest(CapturePackageCodec.canonical(JsonObject(request.toMutableMap().apply {
                put("invocation", driftedInvocation)
            })))
            fail("label consent drift accepted")
        } catch (_: PackageCodecException) { }
    }

    private fun resource(path: String): ByteArray = checkNotNull(javaClass.classLoader!!.getResourceAsStream(path)) { path }.use { it.readBytes() }
}
