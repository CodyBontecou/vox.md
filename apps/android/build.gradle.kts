plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.android.ai.pack) apply false
    alias(libs.plugins.android.legacy.kapt) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.hilt) apply false
}

allprojects {
    dependencyLocking {
        lockAllConfigurations()
    }
}

val repositoryRoot = projectDir.parentFile.parentFile
val androidSbom = repositoryRoot.resolve("artifacts/android-release/vox-android-sbom.cdx.json")
val visualParityManifest = repositoryRoot.resolve("artifacts/android-parity/visual-parity-manifest.json")
val sbomInputs = files(
    listOf("app", "capture-domain", "core-bridge", "data", "platform-services", "wear")
        .map { projectDir.resolve("$it/gradle.lockfile") } +
        repositoryRoot.resolve("Packages/vox-core-rust/Cargo.lock"),
)

tasks.register<Exec>("generateAndroidSbom") {
    group = "build setup"
    description = "Generates a deterministic CycloneDX inventory from release dependency locks."
    inputs.files(sbomInputs)
    inputs.file("scripts/generate-android-sbom.py")
    outputs.file(androidSbom)
    commandLine("python3", "scripts/generate-android-sbom.py")
}

tasks.register<Exec>("validateAndroidSbom") {
    group = "verification"
    description = "Fails when the committed Android CycloneDX inventory is missing or stale."
    inputs.files(sbomInputs)
    inputs.file("scripts/generate-android-sbom.py")
    inputs.file(androidSbom)
    commandLine("python3", "scripts/generate-android-sbom.py", "--check")
}

tasks.register<Exec>("validateVisualParityEvidence") {
    group = "verification"
    description = "Validates the captured, explicitly unreviewed Android visual-story evidence."
    inputs.file("scripts/validate-visual-parity.py")
    inputs.file(visualParityManifest)
    inputs.files(repositoryRoot.resolve("artifacts/android-parity").walkTopDown().filter { it.isFile() }.toList())
    inputs.files(
        listOf("01-quick-capture.png", "03-settings.png", "04-models.png", "05-capture-presets.png")
            .map { repositoryRoot.resolve("artifacts/app-store-raw-latest/$it") },
    ).withPropertyName("canonicalIosVisualReferences")
    commandLine("python3", "scripts/validate-visual-parity.py")
}

tasks.register("releaseReadiness") {
    group = "verification"
    description = "Builds and validates optimized phone/Wear bundles and the locked dependency inventory."
    dependsOn(
        ":app:validateReleaseBundle",
        ":wear:validateWearReleaseBundle",
        "validateAndroidSbom",
        "validateVisualParityEvidence",
    )
}

tasks.register("signedReleaseReadiness") {
    group = "verification"
    description = "Builds and verifies production-signed phone and Wear release bundles."
    dependsOn("releaseReadiness", ":app:validateSignedReleaseBundle", ":wear:validateSignedWearReleaseBundle")
}

tasks.register<Exec>("connectedDebugAndroidTestReinstall") {
    group = "verification"
    description = "Proves the adjusted free-quota policy across a real app uninstall and reinstall."
    dependsOn(":data:assembleDebugAndroidTest")
    outputs.upToDateWhen { false }
    commandLine("python3", "scripts/validate-reinstall-quota.py")
}

tasks.register<Exec>("connectedDebugAndroidTestLocalSpeech") {
    group = "verification"
    description = "Runs exact-hash real-speech inference through the production client with connectivity disabled."
    dependsOn(":app:assembleDebug", ":app:assembleDebugAndroidTest")
    outputs.upToDateWhen { false }
    commandLine("python3", "scripts/validate-local-speech.py")
}

tasks.register<Exec>("connectedDebugAndroidTestNamedModel") {
    group = "verification"
    description = "Qualifies one integrity-pinned Whisper/Parakeet model with real offline inference."
    dependsOn(":app:assembleDebug", ":app:assembleDebugAndroidTest")
    inputs.files(
        "scripts/validate-named-speech-model.py",
        "app/src/androidTest/kotlin/md/vox/android/NamedModelInferenceInstrumentationTest.kt",
    )
    commandLine("python3", "scripts/validate-named-speech-model.py")
}
