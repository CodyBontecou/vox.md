package md.vox.android

import java.nio.file.Files
import java.nio.file.Path
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Document
import org.w3c.dom.Element

class BackupAndPermissionContractTest {
    private val expectedDomains = setOf(
        "root",
        "file",
        "database",
        "sharedpref",
        "external",
        "device_root",
        "device_file",
        "device_database",
        "device_sharedpref",
    )

    @Test
    fun manifestDisablesBackupAndReferencesBothDefenseInDepthRules() {
        val document = parse(mainSource.resolve("AndroidManifest.xml"))
        val application = document.getElementsByTagName("application").item(0) as Element

        assertEquals("false", application.androidAttribute("allowBackup"))
        assertEquals("@xml/backup_rules", application.androidAttribute("fullBackupContent"))
        assertEquals("@xml/data_extraction_rules", application.androidAttribute("dataExtractionRules"))
    }

    @Test
    fun legacyRulesExcludeEveryStorageDomainAtItsRoot() {
        val document = parse(mainSource.resolve("res/xml/backup_rules.xml"))
        assertEquals("full-backup-content", document.documentElement.tagName)
        assertEquals(expectedDomains, excludedDomains(document.documentElement))
    }

    @Test
    fun modernRulesExcludeEveryStorageDomainFromCloudAndTransfer() {
        val document = parse(mainSource.resolve("res/xml/data_extraction_rules.xml"))
        val cloud = document.getElementsByTagName("cloud-backup").item(0) as? Element
        val transfer = document.getElementsByTagName("device-transfer").item(0) as? Element

        assertNotNull(cloud)
        assertNotNull(transfer)
        assertEquals(expectedDomains, excludedDomains(requireNotNull(cloud)))
        assertEquals(expectedDomains, excludedDomains(requireNotNull(transfer)))
    }

    @Test
    fun manifestDeclaresOnlyReviewedCapturePermissions() {
        val document = parse(mainSource.resolve("AndroidManifest.xml"))
        val permissionNodes = document.getElementsByTagName("uses-permission")
        val declared = (0 until permissionNodes.length).map { index ->
            (permissionNodes.item(index) as Element).androidAttribute("name")
        }.toSet()
        val forbidden = setOf(
            "android.permission.MANAGE_EXTERNAL_STORAGE",
            "android.permission.READ_EXTERNAL_STORAGE",
            "android.permission.WRITE_EXTERNAL_STORAGE",
            "android.permission.READ_MEDIA_AUDIO",
            "android.permission.READ_MEDIA_IMAGES",
            "android.permission.READ_MEDIA_VIDEO",
        )

        assertEquals(
            setOf(
                "android.permission.INTERNET",
                "android.permission.RECORD_AUDIO",
                "android.permission.FOREGROUND_SERVICE",
                "android.permission.FOREGROUND_SERVICE_MICROPHONE",
                "android.permission.POST_NOTIFICATIONS",
                "android.permission.ACCESS_COARSE_LOCATION",
                "android.permission.ACCESS_FINE_LOCATION",
            ),
            declared,
        )
        assertFalse("Forbidden permissions present: ${declared.intersect(forbidden)}", declared.any(forbidden::contains))
    }

    @Test
    fun manifestUsesInjectedWorkManagerAndScopedCaptureFileProvider() {
        val document = parse(mainSource.resolve("AndroidManifest.xml"))
        val providers = document.getElementsByTagName("provider")
        val all = (0 until providers.length).map { providers.item(it) as Element }
        val startup = all.single { it.androidAttribute("name") == "androidx.startup.InitializationProvider" }
        val metadata = startup.getElementsByTagName("meta-data")
        val work = (0 until metadata.length).map { metadata.item(it) as Element }
            .single { it.androidAttribute("name") == "androidx.work.WorkManagerInitializer" }
        assertEquals("remove", work.getAttributeNS("http://schemas.android.com/tools", "node"))

        val files = all.single { it.androidAttribute("name") == "androidx.core.content.FileProvider" }
        assertEquals("${'$'}{applicationId}.files", files.androidAttribute("authorities"))
        assertEquals("false", files.androidAttribute("exported"))
        assertEquals("true", files.androidAttribute("grantUriPermissions"))
    }

    @Test
    fun artifactValidatorReviewsOnlyTheExpectedBillingPermission() {
        val validator = mainSource.parent.parent.parent.resolve("scripts/validate-debug-artifacts.py")
        assertTrue("Missing artifact validator: $validator", Files.isRegularFile(validator))
        val source = Files.readString(validator)

        assertTrue(source.contains("REVIEWED_NON_PLATFORM_PERMISSIONS"))
        assertTrue(source.contains("\"com.android.vending.BILLING\""))
    }

    @Test
    fun wearArtifactValidatorRejectsEveryPhoneOnlyRuntime() {
        val validator = mainSource.parent.parent.parent.resolve("scripts/validate-wear-artifacts.py")
        assertTrue("Missing Wear artifact validator: $validator", Files.isRegularFile(validator))
        val source = Files.readString(validator)

        listOf(
            "libvosk.so",
            "libvox_core_uniffi.so",
            "libmlkit_google_ocr_pipeline.so",
            "libmlkitcommonpipeline.so",
            "assets/mlkit-google-ocr-models/",
            "assets/mlkit_label_default_model/",
            "Lorg/vosk/",
            "LocalLiveSpeechSession",
            "SpeechModelManager",
            "Lcom/google/mlkit/vision/text/",
            "Lcom/google/mlkit/vision/label/",
        ).forEach { forbidden -> assertTrue("Validator must reject $forbidden", source.contains(forbidden)) }
    }

    @Test
    fun wearRecordingSurfaceCannotRequestLocation() {
        val androidRoot = mainSource.parent.parent.parent
        val manifestPath = androidRoot.resolve("wear/src/main/AndroidManifest.xml")
        val document = parse(manifestPath)
        val permissions = document.getElementsByTagName("uses-permission")
        val declared = (0 until permissions.length).map { index ->
            (permissions.item(index) as Element).androidAttribute("name")
        }.toSet()
        assertFalse("Wear must not declare coarse location", "android.permission.ACCESS_COARSE_LOCATION" in declared)
        assertFalse("Wear must not declare fine location", "android.permission.ACCESS_FINE_LOCATION" in declared)

        val wearSources = androidRoot.resolve("wear/src/main/kotlin")
        Files.walk(wearSources).use { paths ->
            paths.filter(Files::isRegularFile).forEach { path ->
                val source = Files.readString(path)
                listOf(
                    "Manifest.permission.ACCESS_COARSE_LOCATION",
                    "Manifest.permission.ACCESS_FINE_LOCATION",
                    "LocationManager",
                    "FusedLocationProviderClient",
                    "Geocoder(",
                ).forEach { forbidden ->
                    assertFalse("Wear source $path must not use $forbidden", source.contains(forbidden))
                }
            }
        }
    }

    private fun excludedDomains(parent: Element): Set<String> {
        val excludes = parent.getElementsByTagName("exclude")
        return (0 until excludes.length).map { index ->
            val element = excludes.item(index) as Element
            assertEquals(".", element.getAttribute("path"))
            element.getAttribute("domain")
        }.toSet()
    }

    private fun parse(path: Path): Document {
        assertTrue("Missing contract input: $path", Files.isRegularFile(path))
        val factory = DocumentBuilderFactory.newInstance()
        factory.isNamespaceAware = true
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        factory.setFeature("http://xml.org/sax/features/external-general-entities", false)
        factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        factory.setAttribute("http://javax.xml.XMLConstants/property/accessExternalDTD", "")
        factory.setAttribute("http://javax.xml.XMLConstants/property/accessExternalSchema", "")
        return factory.newDocumentBuilder().parse(path.toFile())
    }

    private fun Element.androidAttribute(name: String): String =
        getAttributeNS("http://schemas.android.com/apk/res/android", name)

    private val mainSource: Path
        get() {
            val working = Path.of(System.getProperty("user.dir"))
            val fromRoot = working.resolve("app/src/main")
            return if (Files.isDirectory(fromRoot)) fromRoot else working.resolve("src/main")
        }
}
