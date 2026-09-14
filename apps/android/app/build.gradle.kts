plugins {
    id("vox.android.application")
    id("vox.android.compose")
    id("vox.android.test")
}

val releaseSigningEnvironment = mapOf(
    "storeFile" to providers.environmentVariable("VOX_ANDROID_STORE_FILE").orNull,
    "storePassword" to providers.environmentVariable("VOX_ANDROID_STORE_PASSWORD").orNull,
    "keyAlias" to providers.environmentVariable("VOX_ANDROID_KEY_ALIAS").orNull,
    "keyPassword" to providers.environmentVariable("VOX_ANDROID_KEY_PASSWORD").orNull,
)
val hasCompleteReleaseSigning = releaseSigningEnvironment.values.all { !it.isNullOrBlank() }

android {
    namespace = "md.vox.android"
    assetPacks += listOf(":whisper_small")

    defaultConfig {
        applicationId = "md.vox.android"
        versionCode = 1
        versionName = "0.1.0-foundation"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    packaging.jniLibs.excludes += setOf(
        "**/armeabi/libjnidispatch.so",
        "**/mips/libjnidispatch.so",
        "**/mips64/libjnidispatch.so",
    )
    if (hasCompleteReleaseSigning) {
        signingConfigs {
            create("voxRelease") {
                storeFile = file(requireNotNull(releaseSigningEnvironment["storeFile"]))
                storePassword = requireNotNull(releaseSigningEnvironment["storePassword"])
                keyAlias = requireNotNull(releaseSigningEnvironment["keyAlias"])
                keyPassword = requireNotNull(releaseSigningEnvironment["keyPassword"])
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            ndk.debugSymbolLevel = "FULL"
            signingConfigs.findByName("voxRelease")?.let { signingConfig = it }
        }
    }
    sourceSets.getByName("main").res.directories.add("build/generated/res/geistFonts")
}

val syncGeistFonts by tasks.registering(Sync::class) {
    group = "build setup"
    description = "Packages the exact Geist font binaries shared with the iOS app."
    val fontRoot = rootProject.projectDir.parentFile.parentFile.resolve("Voxboard/Fonts")
    from(fontRoot.resolve("Geist-Regular.ttf")) { rename { "geist_regular.ttf" } }
    from(fontRoot.resolve("Geist-Medium.ttf")) { rename { "geist_medium.ttf" } }
    from(fontRoot.resolve("Geist-SemiBold.ttf")) { rename { "geist_semibold.ttf" } }
    from(fontRoot.resolve("GeistMono-Regular.ttf")) { rename { "geist_mono_regular.ttf" } }
    from(fontRoot.resolve("GeistMono-Medium.ttf")) { rename { "geist_mono_medium.ttf" } }
    into(layout.buildDirectory.dir("generated/res/geistFonts/font"))
}

dependencies {
    implementation(project(":capture-domain"))
    implementation(project(":core-bridge"))
    implementation(project(":data"))
    implementation(project(":platform-services"))

    implementation(platform(libs.compose.bom))
    implementation(libs.core.ktx)
    implementation(libs.activity.compose)
    implementation(libs.appcompat)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.navigation.compose)
    implementation(libs.work.runtime.ktx)
    implementation(libs.play.services.wearable)
    implementation(libs.play.billing)
    implementation(libs.mlkit.document.scanner)
    implementation(libs.mlkit.text.recognition)
    implementation(libs.mlkit.image.labeling)
    implementation(libs.vosk.android)
    implementation(libs.sherpa.onnx)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)

    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.compose.ui.test.junit4)
}

val generateRuntimeLocalizations by tasks.registering(Exec::class) {
    group = "build setup"
    description = "Generates Android's bounded runtime phrase table from the reviewed iOS catalog."
    val generator = rootProject.file("scripts/generate-runtime-localizations.py")
    val catalog = rootProject.projectDir.parentFile.parentFile.resolve("Voxboard/Localizable.xcstrings")
    inputs.file(generator)
    inputs.file(catalog)
    inputs.files(fileTree("src/main/kotlin") { include("**/*.kt") })
    inputs.files(rootProject.fileTree("capture-domain/src/main/kotlin") { include("**/*.kt") })
    inputs.files(rootProject.fileTree("data/src/main/kotlin") { include("**/*.kt") })
    inputs.files(rootProject.fileTree("platform-services/src/main/kotlin") { include("**/*.kt") })
    outputs.file("src/main/res/raw/vox_runtime_localizations.json")
    outputs.file(rootProject.file("localization-review.json"))
    val localeQualifiers = listOf(
        "ar", "bn", "de", "es", "fr", "hi", "b+id", "it", "ja", "ko", "nl", "pl",
        "pt-rBR", "ru", "ta", "th", "tr", "uk", "ur", "vi", "b+zh+Hans", "b+zh+Hant",
    )
    outputs.files(localeQualifiers.map { file("src/main/res/values-$it/platform_localizations.xml") })
    outputs.files(localeQualifiers.map {
        rootProject.file("wear/src/main/res/values-$it/platform_localizations.xml")
    })
    commandLine("python3", generator)
}

tasks.named("preBuild") {
    dependsOn(generateRuntimeLocalizations, syncGeistFonts)
}

val validateDebugArtifacts by tasks.registering(Exec::class) {
    group = "verification"
    description = "Validates the merged debug manifest and backup exclusion artifacts."
    dependsOn("processDebugManifest", "assembleDebug")
    val mergedManifest = layout.buildDirectory.file(
        "intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml",
    )
    inputs.file(mergedManifest)
    val debugApk = layout.buildDirectory.file("outputs/apk/debug/app-debug.apk")
    inputs.files(
        "src/main/res/xml/backup_rules.xml",
        "src/main/res/xml/data_extraction_rules.xml",
        debugApk,
    )
    commandLine(
        "python3",
        rootProject.file("scripts/validate-debug-artifacts.py"),
        "--manifest",
        mergedManifest.get().asFile,
        "--backup-rules",
        file("src/main/res/xml/backup_rules.xml"),
        "--data-extraction-rules",
        file("src/main/res/xml/data_extraction_rules.xml"),
        "--apk",
        debugApk.get().asFile,
    )
}

val validateReleaseBundle by tasks.registering(Exec::class) {
    group = "verification"
    description = "Validates the optimized release manifest, backup exclusions, and four-ABI app bundle."
    dependsOn("processReleaseManifest", "bundleRelease")
    val mergedManifest = layout.buildDirectory.file(
        "intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml",
    )
    val releaseBundle = layout.buildDirectory.file("outputs/bundle/release/app-release.aab")
    inputs.files(
        mergedManifest,
        "src/main/res/xml/backup_rules.xml",
        "src/main/res/xml/data_extraction_rules.xml",
        releaseBundle,
    )
    commandLine(
        "python3",
        rootProject.file("scripts/validate-debug-artifacts.py"),
        "--manifest",
        mergedManifest.get().asFile,
        "--backup-rules",
        file("src/main/res/xml/backup_rules.xml"),
        "--data-extraction-rules",
        file("src/main/res/xml/data_extraction_rules.xml"),
        "--apk",
        releaseBundle.get().asFile,
    )
}

val validateBundledWhisperSmall by tasks.registering(Exec::class) {
    group = "verification"
    description = "Verifies the exact Whisper Small files in the Android release AI pack."
    dependsOn("bundleRelease")
    val validator = rootProject.file("scripts/validate-bundled-whisper-small.py")
    val modelDirectory = rootProject.file("whisper_small/src/main/assets/speech-models/ggml-small")
    val releaseBundle = layout.buildDirectory.file("outputs/bundle/release/app-release.aab")
    inputs.file(validator)
    inputs.dir(modelDirectory)
    inputs.file(releaseBundle)
    commandLine(
        "python3",
        validator,
        "--assets",
        modelDirectory,
        "--bundle",
        releaseBundle.get().asFile,
    )
}

validateReleaseBundle {
    dependsOn(validateBundledWhisperSmall)
}

val validateReleaseSigningInputs by tasks.registering(Exec::class) {
    group = "verification"
    description = "Requires the complete environment-only production signing configuration."
    commandLine("python3", rootProject.file("scripts/validate-signing-environment.py"))
}

val validateSignedReleaseBundle by tasks.registering(Exec::class) {
    group = "verification"
    description = "Cryptographically verifies the production-signed phone bundle."
    dependsOn(validateReleaseBundle, validateReleaseSigningInputs)
    val releaseBundle = layout.buildDirectory.file("outputs/bundle/release/app-release.aab")
    inputs.file(releaseBundle)
    commandLine(
        "python3",
        rootProject.file("scripts/validate-release-signature.py"),
        releaseBundle.get().asFile,
    )
}

tasks.named("check") {
    dependsOn(validateDebugArtifacts)
}
