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
    namespace = "md.vox.android.wear"

    defaultConfig {
        applicationId = "md.vox.android"
        minSdk = 30
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
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
            signingConfigs.findByName("voxRelease")?.let { signingConfig = it }
        }
    }
    sourceSets.getByName("main").res.directories.add("build/generated/res/geistFonts")
    sourceSets.getByName("main").res.directories.add("build/generated/res/launcherIcons")
}

val generateLauncherIcons by tasks.registering(Exec::class) {
    group = "build setup"
    description = "Derives every launcher icon variant from the canonical iOS app icon."
    val generator = rootProject.file("scripts/generate-launcher-icons.py")
    val icon = rootProject.projectDir.parentFile.parentFile
        .resolve("Voxboard/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
    inputs.file(generator)
    inputs.file(icon)
    outputs.dir(layout.buildDirectory.dir("generated/res/launcherIcons"))
    commandLine(
        "python3",
        generator,
        "--icon",
        icon,
        "--out",
        layout.buildDirectory.dir("generated/res/launcherIcons").get().asFile,
    )
}

val syncWearGeistFonts by tasks.registering(Sync::class) {
    group = "build setup"
    description = "Packages the exact Geist font binaries shared with the iOS and Android apps."
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
    implementation(project(":platform-services"))

    implementation(platform(libs.compose.bom))
    implementation(libs.core.ktx)
    implementation(libs.concurrent.futures)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.compose.ui)
    implementation(libs.wear.compose.foundation)
    implementation(libs.wear.compose.material)
    implementation(libs.play.services.wearable)
    implementation(libs.wear.tiles)
    implementation(libs.wear.protolayout)
    implementation(libs.wear.protolayout.material)
    implementation(libs.wear.watchface.complications.data.source)
    implementation(libs.wear.ongoing)

    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.wear.compose.tooling)
    debugImplementation(libs.compose.ui.test.manifest)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.rules)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.compose.ui.test.junit4)
}

tasks.named("preBuild") {
    dependsOn(":app:generateRuntimeLocalizations", syncWearGeistFonts, generateLauncherIcons)
}

val validateWearDebugArtifacts by tasks.registering(Exec::class) {
    group = "verification"
    description = "Ensures phone-only inference and Markdown runtimes are absent from Wear."
    dependsOn("assembleDebug")
    val debugApk = layout.buildDirectory.file("outputs/apk/debug/wear-debug.apk")
    inputs.file(debugApk)
    commandLine(
        "python3",
        rootProject.file("scripts/validate-wear-artifacts.py"),
        "--apk",
        debugApk.get().asFile,
    )
}

val validateWearReleaseBundle by tasks.registering(Exec::class) {
    group = "verification"
    description = "Ensures phone-only inference and Markdown runtimes are absent from the optimized Wear bundle."
    dependsOn("bundleRelease")
    val releaseBundle = layout.buildDirectory.file("outputs/bundle/release/wear-release.aab")
    inputs.file(releaseBundle)
    commandLine(
        "python3",
        rootProject.file("scripts/validate-wear-artifacts.py"),
        "--apk",
        releaseBundle.get().asFile,
        "--scan-dex",
    )
}

val validateSignedWearReleaseBundle by tasks.registering(Exec::class) {
    group = "verification"
    description = "Cryptographically verifies the production-signed Wear bundle."
    dependsOn(validateWearReleaseBundle, ":app:validateReleaseSigningInputs")
    val releaseBundle = layout.buildDirectory.file("outputs/bundle/release/wear-release.aab")
    inputs.file(releaseBundle)
    commandLine(
        "python3",
        rootProject.file("scripts/validate-release-signature.py"),
        releaseBundle.get().asFile,
    )
}

tasks.named("check") {
    dependsOn(validateWearDebugArtifacts)
}
