#!/usr/bin/env python3
"""Stdlib-only strict M2 native and M3 Android application toolchain validator."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import xml.etree.ElementTree as ET

DEFAULT_ROOT = Path(__file__).resolve().parents[3]


def fail(message):
    raise SystemExit("Toolchain validation failed: " + message)


def load(path):
    try:
        return json.loads(path.read_text())
    except Exception as error:
        fail(f"{path}: {error}")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exact(value, keys, label):
    if set(value) != set(keys):
        fail(f"{label} fields differ")


def version_catalog(text):
    section = None
    versions = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if section == "versions":
            match = re.fullmatch(r'([a-z0-9-]+)\s*=\s*"([^"]+)"', line)
            if not match:
                fail("version catalog contains non-canonical version declaration")
            versions[match.group(1)] = match.group(2)
    return versions


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    arguments = parser.parse_args(argv)
    root = (arguments.root or DEFAULT_ROOT).resolve()
    manifest = load(root / "toolchains/android-wear-shared-core.json")
    schema = load(root / "toolchains/android-wear-shared-core.schema.json")
    exact(
        manifest,
        [
            "$schema", "schemaVersion", "status", "rust", "uniffi",
            "androidNative", "androidApplication", "apple",
            "bindingGeneration",
        ],
        "manifest",
    )
    if (manifest["$schema"], manifest["schemaVersion"], manifest["status"]) != (
        "android-wear-shared-core.schema.json", 2,
        "m3-android-application-toolchain-pinned",
    ):
        fail("manifest identity/status")
    if schema.get("properties", {}).get("schemaVersion", {}).get("const") != 2:
        fail("schema identity/version")

    expected_rust = {
        "toolchain": "1.97.1", "msrv": "1.87.0", "edition": "2024",
        "cargoResolver": "3", "profile": "minimal",
        "components": ["clippy", "rustfmt"],
        "targets": [
            "aarch64-apple-ios", "aarch64-apple-ios-sim", "x86_64-apple-ios",
            "aarch64-linux-android", "armv7-linux-androideabi",
            "x86_64-linux-android", "i686-linux-android",
        ],
        "rustToolchainPath": "Packages/vox-core-rust/rust-toolchain.toml",
    }
    if manifest["rust"] != expected_rust:
        fail("Rust pins differ")
    if manifest["uniffi"] != {
        "bindgenVersion": "0.32.0", "cliVersion": "0.32.0",
        "libraryVersion": "0.32.0",
    }:
        fail("UniFFI pins differ")
    targets = [
        {"abi": "arm64-v8a", "apiLevel": 28, "rustTarget": "aarch64-linux-android"},
        {"abi": "armeabi-v7a", "apiLevel": 28, "rustTarget": "armv7-linux-androideabi"},
        {"abi": "x86_64", "apiLevel": 28, "rustTarget": "x86_64-linux-android"},
        {"abi": "x86", "apiLevel": 28, "rustTarget": "i686-linux-android"},
    ]
    if manifest["androidNative"] != {
        "cargoNdkVersion": "4.1.2", "ndkRevision": "27.1.12297006",
        "targets": targets,
    }:
        fail("Android native pins differ")

    expected_android = {
        "namespace": "md.vox.android",
        "applicationID": "md.vox.android",
        "jdk": {
            "distribution": "temurin", "version": "21",
            "languageLevel": 17, "jvmTarget": "17",
        },
        "gradle": {
            "version": "9.3.1",
            "distributionURL": "https://services.gradle.org/distributions/gradle-9.3.1-bin.zip",
            "distributionSha256": "b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06",
            "wrapperJarPath": "apps/android/gradle/wrapper/gradle-wrapper.jar",
            "wrapperJarSha256": "b3a875ddc1f044746e1b1a55f645584505f4a10438c1afea9f15e92a7c42ec13",
        },
        "androidGradlePluginVersion": "9.1.1",
        "kotlin": {
            "version": "2.4.10", "builtIn": True,
            "composeCompilerPluginVersion": "2.4.10",
            "annotationProcessingPlugin": "com.android.legacy-kapt",
            "annotationProcessingPluginVersion": "9.1.1",
        },
        "sdk": {
            "compileSdk": 37, "buildToolsVersion": "36.0.0",
            "phoneMinSdk": 28, "phoneTargetSdk": 36,
            "wearMinSdk": 30, "wearTargetSdk": 35,
        },
        "androidCommandLineTools": {
            "archiveVersion": "15859902",
            "toolsVersion": "22.0",
            "linuxURL": "https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip",
            "linuxSha256": "4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583",
        },
        "compose": {"bomVersion": "2026.08.00"},
        "dependencies": {
            "activityCompose": "1.13.0", "androidxAnnotation": "1.7.0",
            "androidxHilt": "1.4.0",
            "androidxTest": "1.7.0", "androidxTestExtJunit": "1.3.0",
            "appcompat": "1.8.0", "billing": "9.1.0",
            "composeBom": "2026.08.00", "concurrent": "1.3.0", "coreKtx": "1.19.0",
            "coroutines": "1.11.0", "dataStore": "1.2.1",
            "daggerHilt": "2.60.1", "espresso": "3.7.0", "jna": "5.17.0",
            "junit4": "4.13.2", "lifecycle": "2.11.0",
            "mlkitDocumentScanner": "16.0.0", "mlkitImageLabeling": "17.0.9",
            "mlkitTextRecognition": "16.0.1",
            "navigationCompose": "2.9.8", "room": "2.8.4",
            "serialization": "1.11.0", "sherpaOnnx": "1.13.4", "vosk": "0.3.75",
            "wearCompose": "1.6.2", "wearOngoing": "1.1.0", "wearProtoLayout": "1.4.2",
            "wearTiles": "1.6.2", "wearWatchface": "1.3.0",
            "wearable": "20.0.1", "workManager": "2.11.2",
        },
        "configurationPaths": {
            "rootBuild": "apps/android/build.gradle.kts",
            "settings": "apps/android/settings.gradle.kts",
            "versionCatalog": "apps/android/gradle/libs.versions.toml",
            "gradleProperties": "apps/android/gradle.properties",
            "wrapperProperties": "apps/android/gradle/wrapper/gradle-wrapper.properties",
            "wrapperScript": "apps/android/gradlew",
            "wrapperBatchScript": "apps/android/gradlew.bat",
            "androidCI": ".github/workflows/android-ci.yml",
            "buildLogicBuild": "apps/android/build-logic/build.gradle.kts",
            "buildLogicSettings": "apps/android/build-logic/settings.gradle.kts",
            "artifactValidator": "apps/android/scripts/validate-debug-artifacts.py",
            "moduleBuilds": [
                "apps/android/app/build.gradle.kts",
                "apps/android/core-bridge/build.gradle.kts",
                "apps/android/capture-domain/build.gradle.kts",
                "apps/android/data/build.gradle.kts",
                "apps/android/platform-services/build.gradle.kts",
                "apps/android/wear/build.gradle.kts",
            ],
        },
        "dependencyMetadataPaths": {
            "verificationMetadata": "apps/android/gradle/verification-metadata.xml",
            "settingsLock": "apps/android/settings-gradle.lockfile",
            "buildLogicLock": "apps/android/build-logic/gradle.lockfile",
            "moduleLocks": [
                "apps/android/app/gradle.lockfile",
                "apps/android/core-bridge/gradle.lockfile",
                "apps/android/capture-domain/gradle.lockfile",
                "apps/android/data/gradle.lockfile",
                "apps/android/platform-services/gradle.lockfile",
                "apps/android/wear/gradle.lockfile",
            ],
        },
    }
    if manifest["androidApplication"] != expected_android:
        fail("Android application pins differ")

    if manifest["apple"] != {
        "deploymentTarget": "17.6", "packagingTool": "xcodebuild -create-xcframework",
        "swiftVersion": "6.3.3",
        "targets": ["aarch64-apple-ios", "aarch64-apple-ios-sim", "x86_64-apple-ios"],
        "xcodeBuild": "17F113", "xcodeVersion": "26.6",
    }:
        fail("Apple pins differ")
    binding = manifest["bindingGeneration"]
    exact(
        binding,
        [
            "swiftConfigPath", "kotlinConfigPath", "swiftScriptPath",
            "kotlinScriptPath", "swiftOutputPaths", "kotlinOutputPaths", "hashStatus",
        ],
        "bindingGeneration",
    )
    if binding["hashStatus"] != "governed-implemented":
        fail("binding hash status")
    expected_swift = [
        "Packages/vox-core-rust/generated/swift/VoxCore.swift",
        "Packages/vox-core-rust/generated/swift/VoxCoreFFI.h",
        "Packages/vox-core-rust/generated/swift/VoxCoreFFI.modulemap",
    ]
    expected_kotlin = [
        "Packages/vox-core-rust/generated/kotlin/md/vox/core/vox_core_uniffi.kt",
    ]
    if binding["swiftOutputPaths"] != expected_swift or binding["kotlinOutputPaths"] != expected_kotlin:
        fail("generated output inventory")

    for path in expected_swift + expected_kotlin:
        if not (root / path).is_file():
            fail(f"generated binding missing: {path}")

    for config_path in (
        "Packages/vox-core-rust/uniffi.toml",
        "Packages/vox-core-rust/uniffi-bindgen.toml",
        "Packages/vox-core-rust/crates/vox-core-uniffi/uniffi.toml",
    ):
        config = (root / config_path).read_text()
        if "[bindings.kotlin]" not in config or "android_cleaner = true" not in config:
            fail(f"Android-safe UniFFI cleaner configuration drift: {config_path}")
    kotlin_binding = (root / "Packages/vox-core-rust/generated/kotlin/md/vox/core/vox_core_uniffi.kt").read_text()
    for declaration in (
        "internal open class CoreMaterializationSession",
        "internal data class CoreBuildInfo",
        "internal sealed class VoxCoreException",
        "internal fun `corePrepare`",
    ):
        if declaration not in kotlin_binding:
            fail(f"generated Kotlin module-internal surface drift: {declaration}")
    kotlin_declaration = (
        r"(?:(?:open|abstract|data|enum|sealed|value|annotation|inline|const|lateinit|suspend)\s+)*"
        r"(?:class|interface|object|fun|typealias|val|var)"
    )
    if re.search(rf"(?m)^(?:public\s+)?{kotlin_declaration}\b", kotlin_binding) or re.search(
        r"(?m)^\s+(?:@Throws\([^\n)]+::class\) )?(?:public )?fun `core[A-Za-z0-9]+`",
        kotlin_binding,
    ):
        fail("generated Kotlin exposes a public top-level declaration")

    cargo = (root / "Packages/vox-core-rust/Cargo.toml").read_text()
    lock = (root / "Packages/vox-core-rust/Cargo.lock").read_text()
    rust_toolchain = (root / expected_rust["rustToolchainPath"]).read_text()
    for needle in [
        'channel = "1.97.1"', 'profile = "minimal"',
        'components = ["clippy", "rustfmt"]',
    ]:
        if needle not in rust_toolchain:
            fail(f"rust-toolchain drift: {needle}")
    for needle in [
        'resolver = "3"', 'edition = "2024"', 'rust-version = "1.87.0"',
        'version = "=0.32.0"',
    ]:
        if needle not in cargo:
            fail(f"Cargo drift: {needle}")
    if 'name = "uniffi_bindgen"\nversion = "0.32.0"' not in lock:
        fail("UniFFI bindgen 0.32.0 absent from lock")

    android = expected_android["configurationPaths"]
    wrapper = (root / android["wrapperProperties"]).read_text()
    expected_wrapper = (
        "distributionBase=GRADLE_USER_HOME\n"
        "distributionPath=wrapper/dists\n"
        "distributionSha256Sum=b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06\n"
        "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.3.1-bin.zip\n"
        "networkTimeout=10000\n"
        "validateDistributionUrl=true\n"
        "zipStoreBase=GRADLE_USER_HOME\n"
        "zipStorePath=wrapper/dists\n"
    )
    if wrapper != expected_wrapper:
        fail("Gradle wrapper properties drift")
    wrapper_jar = root / expected_android["gradle"]["wrapperJarPath"]
    if digest(wrapper_jar) != expected_android["gradle"]["wrapperJarSha256"]:
        fail("Gradle wrapper JAR drift")
    if not os.access(root / android["wrapperScript"], os.X_OK):
        fail("Gradle wrapper script is not executable")

    catalog_text = (root / android["versionCatalog"]).read_text()
    expected_versions = {
        "agp": "9.1.1", "kotlin": "2.4.10", "compose-bom": "2026.08.00",
        "core": "1.19.0", "activity": "1.13.0", "appcompat": "1.8.0",
        "lifecycle": "2.11.0",
        "navigation": "2.9.8", "room": "2.8.4", "datastore": "1.2.1",
        "work": "2.11.2", "concurrent": "1.3.0", "wear-compose": "1.6.2",
        "wearable": "20.0.1", "wear-ongoing": "1.1.0", "wear-tiles": "1.6.2", "wear-protolayout": "1.4.2",
        "wear-watchface": "1.3.0", "hilt": "2.60.1", "androidx-hilt": "1.4.0",
        "coroutines": "1.11.0", "serialization": "1.11.0", "jna": "5.17.0",
        "mlkit-text-recognition": "16.0.1", "mlkit-document-scanner": "16.0.0",
        "mlkit-image-labeling": "17.0.9", "sherpa-onnx": "1.13.4", "vosk": "0.3.75", "billing": "9.1.0",
        "androidx-annotation": "1.7.0", "androidx-test": "1.7.0", "androidx-test-ext-junit": "1.3.0",
        "espresso": "3.7.0", "junit4": "4.13.2",
    }
    if version_catalog(catalog_text) != expected_versions:
        fail("Android version catalog pins differ")
    forbidden = ("org.jetbrains.kotlin.android", "com.google.devtools.ksp", "+", "latest")
    lower_catalog = catalog_text.lower()
    if any(value.lower() in lower_catalog for value in forbidden):
        fail("Android version catalog contains forbidden floating or incompatible tooling")
    root_build = (root / android["rootBuild"]).read_text()
    for alias in (
        "android.application", "android.library", "android.legacy.kapt",
        "kotlin.compose", "kotlin.serialization", "hilt",
    ):
        if f"alias(libs.plugins.{alias}) apply false" not in root_build:
            fail(f"Android root plugin alias missing: {alias}")
    settings = (root / android["settings"]).read_text()
    if "RepositoriesMode.FAIL_ON_PROJECT_REPOS" not in settings:
        fail("Android repository policy drift")
    for token in (
        'maven("https://jitpack.io")',
        'includeModule("com.github.k2-fsa", "sherpa-onnx")',
    ):
        if token not in settings:
            fail(f"Pinned Sherpa repository policy drift: {token}")
    expected_modules = {
        'include(":app")', 'include(":core-bridge")',
        'include(":capture-domain")', 'include(":data")',
        'include(":platform-services")', 'include(":wear")',
    }
    if not expected_modules.issubset(set(settings.splitlines())):
        fail("Android module inventory drift")
    if 'includeBuild("build-logic")' not in settings or "lockAllConfigurations()" not in root_build:
        fail("Android build logic or dependency locking drift")
    gradle_properties = (root / android["gradleProperties"]).read_text()
    if "android.suppressUnsupportedCompileSdk" in gradle_properties:
        fail("Android compile SDK compatibility warning is suppressed")

    build_logic = (root / android["buildLogicBuild"]).read_text()
    for needle in (
        'compileOnly("com.android.tools.build:gradle:9.1.1")',
        'id = "vox.android.application"', 'id = "vox.android.library"',
        'id = "vox.android.compose"', 'id = "vox.android.test"',
        "lockAllConfigurations()",
    ):
        if needle not in build_logic:
            fail(f"Android build logic drift: {needle}")
    convention_tokens = {
        "AndroidApplicationConventionPlugin.kt": (
            'pluginManager.apply("com.android.application")', "compileSdk = 37",
            'buildToolsVersion = "36.0.0"', "minSdk = 28", "targetSdk = 36",
        ),
        "AndroidLibraryConventionPlugin.kt": (
            'pluginManager.apply("com.android.library")', "compileSdk = 37",
            'buildToolsVersion = "36.0.0"', "minSdk = 28",
        ),
        "AndroidComposeConventionPlugin.kt": (
            'pluginManager.apply("org.jetbrains.kotlin.plugin.compose")',
            "buildFeatures.compose = true",
        ),
        "AndroidTestConventionPlugin.kt": (
            'add("testImplementation", "junit:junit:4.13.2")', "useJUnit()",
        ),
    }
    convention_root = root / "apps/android/build-logic/src/main/kotlin"
    for name, tokens in convention_tokens.items():
        text = (convention_root / name).read_text()
        if any(token not in text for token in tokens):
            fail(f"Android convention plugin drift: {name}")

    module_builds = {Path(path).parent.name: (root / path).read_text() for path in android["moduleBuilds"]}
    if "implementation(libs.wear.ongoing)" not in module_builds["wear"]:
        fail("Wear Ongoing Activity runtime dependency drift")
    expected_graph = {
        "app": {"capture-domain", "core-bridge", "data", "platform-services"},
        "capture-domain": set(),
        "data": {"capture-domain", "core-bridge"},
        "platform-services": {"capture-domain"},
        "core-bridge": set(),
        "wear": {"capture-domain", "platform-services"},
    }
    actual_graph = {}
    project_pattern = re.compile(r'project\s*\(\s*(?:path\s*=\s*)?"(:[a-z0-9-]+)"\s*\)')
    for module, text in module_builds.items():
        matches = project_pattern.findall(text)
        if len(matches) != len(re.findall(r"\bproject\s*\(", text)):
            fail(f"Android module graph has an unparsed project dependency: {module}")
        if len(matches) != len(set(matches)):
            fail(f"Android module graph has a duplicate project dependency: {module}")
        actual_graph[module] = {path.removeprefix(":") for path in matches}
    if actual_graph != expected_graph:
        fail(f"Android module graph differs: {actual_graph}")
    visiting = set()
    visited = set()
    def visit(module):
        if module in visiting:
            fail(f"Android module graph contains a cycle at {module}")
        if module in visited:
            return
        visiting.add(module)
        for dependency in actual_graph[module]:
            if dependency not in actual_graph:
                fail(f"Android module graph references unknown module: {dependency}")
            visit(dependency)
        visiting.remove(module)
        visited.add(module)
    for module in actual_graph:
        visit(module)
    app_build = module_builds["app"]
    if "implementation(libs.sherpa.onnx)" not in app_build:
        fail("Phone Sherpa runtime dependency drift")
    if "compileOnly(libs.sherpa.onnx)" not in module_builds["platform-services"]:
        fail("Platform-services Sherpa compile boundary drift")
    if "libs.sherpa.onnx" in module_builds["wear"]:
        fail("Wear must not depend on the phone-only Sherpa runtime")
    verification_metadata = (root / expected_android["dependencyMetadataPaths"]["verificationMetadata"]).read_text()
    for token in (
        '<component group="com.github.k2-fsa" name="sherpa-onnx" version="1.13.4">',
        '<sha256 value="03f9c4df965f21c71269365a7951a7f23b5696fddd093fa318c80d65550ab780"',
    ):
        if token not in verification_metadata:
            fail(f"Sherpa dependency verification drift: {token}")
    for token in (
        "validateDebugArtifacts", "validateReleaseBundle", "validateSignedReleaseBundle",
        'dependsOn("processDebugManifest", "assembleDebug")', '"--apk"', 'tasks.named("check")',
    ):
        if token not in app_build:
            fail(f"Android artifact validation task wiring drift: {token}")
    data_build = module_builds["data"]
    for dependency in ("libs.room.runtime", "libs.room.ktx"):
        if f"implementation({dependency})" not in data_build or f"compileOnly({dependency})" in data_build:
            fail(f"Android M3 Room runtime activation drift: {dependency}")
    if "implementation(libs.datastore.preferences)" not in data_build or "compileOnly(libs.datastore.preferences)" in data_build:
        fail("Android M3 DataStore runtime activation drift")
    if "compileOnly(libs.work.runtime.ktx)" not in data_build:
        fail("Inactive Android framework must remain compileOnly: libs.work.runtime.ktx")
    for token in ("libs.plugins.android.legacy.kapt", "kapt(libs.room.compiler)", "room.schemaLocation"):
        if token not in data_build:
            fail(f"Android Room compiler/schema governance drift: {token}")
    if any("org.jetbrains.kotlin.android" in text for text in module_builds.values()):
        fail("Android modules bypass AGP built-in Kotlin")
    domain_source = (root / "apps/android/capture-domain/src/main/kotlin/md/vox/android/capturedomain/DurableCapture.kt").read_text()
    if re.search(r"^import\s+(android|androidx)\.", domain_source, flags=re.MULTILINE):
        fail("capture-domain imports an Android framework type")
    store_source = (root / "apps/android/data/src/main/kotlin/md/vox/android/data/DurableCaptureStore.kt").read_text()
    for forbidden in ("renameTo(", ".writeText(", ".writeBytes(", "ContentResolver", "WorkManager", "DataStore"):
        if forbidden in store_source:
            fail(f"durable package store contains forbidden API/fallback: {forbidden}")
    database_source = "\n".join((root / path).read_text() for path in (
        "apps/android/data/src/main/java/md/vox/android/data/CaptureProjectionEntity.java",
        "apps/android/data/src/main/java/md/vox/android/data/CaptureProjectionDao.java",
        "apps/android/data/src/main/java/md/vox/android/data/CaptureDatabase.java",
        "apps/android/data/src/main/kotlin/md/vox/android/data/RoomCaptureIndex.kt",
    ))
    for forbidden in ("content", "url", "filename", "path", "uri", "document", "provider", "sha256"):
        if re.search(rf"(?:\bval\s+{forbidden}\w*\s*:|\b(?:String|long|int)\s+{forbidden}\w*\s*[;,)])", database_source, flags=re.IGNORECASE):
            fail(f"Room projection contains forbidden content/authority field: {forbidden}")
    for forbidden in ("fallbackToDestructiveMigration", "allowMainThreadQueries"):
        if forbidden in database_source:
            fail(f"Room database contains forbidden policy: {forbidden}")
    room_schema = load(root / "apps/android/data/schemas/md.vox.android.data.CaptureDatabase/1.json")
    entities = room_schema.get("database", {}).get("entities", [])
    expected_columns = ["requestID", "packageVersion", "journalVersion", "journalRevision", "state", "createdAtEpochMillis", "updatedAtEpochMillis"]
    if len(entities) != 1 or entities[0].get("tableName") != "capture_projection" or [field.get("columnName") for field in entities[0].get("fields", [])] != expected_columns:
        fail("Room content-free schema inventory drift")

    metadata = expected_android["dependencyMetadataPaths"]
    verification = (root / metadata["verificationMetadata"]).read_text()
    if "<verify-metadata>true</verify-metadata>" not in verification or "Generated by Gradle" not in verification:
        fail("Gradle dependency verification metadata drift")
    if (
        'name="gradle" version="9.1.1"' not in verification
        or '<component group="com.android.tools.build" name="gradle" version="9.1.0">' in verification
    ):
        fail("Gradle verification metadata has missing/stale AGP resolution")
    try:
        verification_root = ET.fromstring(verification)
    except ET.ParseError as error:
        fail(f"Gradle verification metadata XML is invalid: {error}")
    namespace = {"v": "https://schema.gradle.org/dependency-verification"}
    aapt_components = [
        component for component in verification_root.findall(".//v:component", namespace)
        if component.attrib == {
            "group": "com.android.tools.build",
            "name": "aapt2",
            "version": "9.1.1-14792394",
        }
    ]
    if len(aapt_components) != 1:
        fail("Gradle verification metadata has missing/duplicate pinned AAPT2 component")
    aapt_artifacts = {}
    for artifact in aapt_components[0].findall("v:artifact", namespace):
        checksums = artifact.findall("v:sha256", namespace)
        if len(checksums) != 1 or artifact.get("name") in aapt_artifacts:
            fail("Gradle verification metadata AAPT2 artifact checksum shape drift")
        aapt_artifacts[artifact.get("name")] = checksums[0].attrib
    expected_aapt = {
        "aapt2-9.1.1-14792394-osx.jar": {
            "value": "b58cb80ac24aa343d02316fa50a662e2710b2f9ea14fc7da6d08d9cd801cafa3",
            "origin": "Generated by Gradle",
        },
        "aapt2-9.1.1-14792394-linux.jar": {
            "value": "e7ae17af6e4093c771243e82d66462353de87befaac206bfb43e557ac1c34440",
            "origin": "Manually verified from pinned Google Maven URL",
        },
    }
    for artifact, expected_checksum in expected_aapt.items():
        if aapt_artifacts.get(artifact) != expected_checksum:
            fail(f"Gradle verification metadata AAPT2 artifact missing/drifted: {artifact}")
    linux_origin = "Downloaded from Maven Central and independently SHA-256 verified for Linux CI"
    expected_linux_metadata = (
        ("org.jetbrains.kotlinx", "kotlinx-coroutines-bom", "1.8.0", "kotlinx-coroutines-bom-1.8.0.pom", "1239e9dbe1397cd5971342956b2511bc3ace7b641842e4372a088dcfa8b9ad55"),
        ("com.google.guava", "guava-parent", "33.3.1-jre", "guava-parent-33.3.1-jre.pom", "55441db27e8869dfefe053059bdf478bdc7e95585642bf391f0023345fd56287"),
        ("org.junit", "junit-bom", "5.10.2", "junit-bom-5.10.2.module", "de23b114b3e4119a8fe6eb17bed5a3852816698bace67071579d6d927ebb080a"),
        ("org.junit", "junit-bom", "5.11.0-M2", "junit-bom-5.11.0-M2.module", "86477abcf490d6ca059aa9973cb108d22a506f49d1a5569bb32cc6cbf43c2cce"),
        ("org.junit", "junit-bom", "5.9.2", "junit-bom-5.9.2.module", "ab137ba5a8e32c9b066bf9126a1c76dd5614b724ba5c0b02549772b5e9f4cf1f"),
    )
    all_components = verification_root.findall(".//v:component", namespace)
    for group, name, version, artifact_name, checksum in expected_linux_metadata:
        components = [
            component for component in all_components
            if component.attrib == {"group": group, "name": name, "version": version}
        ]
        if len(components) != 1:
            fail(f"Gradle verification metadata lacks Linux-resolved component: {group}:{name}:{version}")
        artifacts = [
            artifact for artifact in components[0].findall("v:artifact", namespace)
            if artifact.attrib == {"name": artifact_name}
        ]
        if len(artifacts) != 1:
            fail(f"Gradle verification metadata lacks Linux-resolved artifact: {artifact_name}")
        checksums = artifacts[0].findall("v:sha256", namespace)
        if len(checksums) != 1 or checksums[0].attrib != {"value": checksum, "origin": linux_origin}:
            fail(f"Gradle verification metadata Linux-resolved checksum drift: {artifact_name}")
    for lock_path in [metadata["settingsLock"], metadata["buildLogicLock"], *metadata["moduleLocks"]]:
        lock = root / lock_path
        if not lock.is_file() or "empty=" not in lock.read_text():
            fail(f"Gradle dependency lock missing or malformed: {lock_path}")
        if re.search(r"^com\.android\.tools\.build:[^:]+:9\.1\.0=", lock.read_text(), re.MULTILINE):
            fail(f"Gradle dependency lock retains AGP 9.1.0: {lock_path}")
    if "com.android.tools.build:gradle:9.1.1=" not in (root / metadata["buildLogicLock"]).read_text():
        fail("Gradle build logic lock lacks AGP 9.1.1")

    workflow = (root / android["androidCI"]).read_text()
    command_line_tools = expected_android["androidCommandLineTools"]
    for needle in (
        "runs-on: ubuntu-24.04",
        "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd",
        "actions/setup-java@be666c2fcd27ec809703dec50e508c2fdc7f6654",
        "dtolnay/rust-toolchain@6c977a6ca4077a0ceb28ffbe03f59d46e9ac8772",
        "toolchain: 1.97.1",
        "targets: aarch64-linux-android,armv7-linux-androideabi,x86_64-linux-android,i686-linux-android",
        "cargo +1.97.1 install cargo-ndk --version 4.1.2 --locked",
        "java-version: '21'", "'platforms;android-37.0'",
        "'build-tools;36.0.0'", "'ndk;27.1.12297006'",
        'ndk_path="$ANDROID_SDK_ROOT/ndk/27.1.12297006"',
        'echo "ANDROID_NDK_HOME=$ndk_path" >> "$GITHUB_ENV"',
        'echo "ANDROID_NDK_ROOT=$ndk_path" >> "$GITHUB_ENV"',
        command_line_tools["linuxURL"], command_line_tools["linuxSha256"],
        'cmdline-tools/22.0/bin/sdkmanager', "sha256sum --check --strict",
        "validate_toolchain.py", "generate-runtime-localizations.py --check", "test-project-contracts.sh",
        "'Packages/vox-core-rust/**'",
        ":app:validateDebugArtifacts", ":wear:validateWearDebugArtifacts", "releaseReadiness",
    ):
        if needle not in workflow:
            fail(f"Android CI drift: {needle}")
    if "ubuntu-latest" in workflow or "cmdline-tools/latest" in workflow:
        fail("Android CI contains a floating runner or command-line tools path")
    for workflow_label, workflow_text in (
        ("Android CI", workflow),
        ("Contracts CI", (root / ".github/workflows/contracts-ci.yml").read_text()),
    ):
        actions = re.findall(r"^\s*uses:\s*[^@\s]+@([^\s#]+)", workflow_text, flags=re.MULTILINE)
        if not actions:
            fail(f"{workflow_label} has no action references")
        for action in actions:
            if re.fullmatch(r"[0-9a-f]{40}", action) is None:
                fail(f"{workflow_label} action is not immutable: {action}")
    phase4_build = (root / "apps/android/core-bridge/build.gradle.kts").read_text()
    phase4_generated = (root / "apps/android/core-bridge/src/main/kotlin/md/vox/android/corebridge/GeneratedNativeCoreAdapter.kt").read_text()
    phase4_app = (root / "apps/android/app/src/main/kotlin/md/vox/android/VoxApplication.kt").read_text()
    for needle in (
        "Packages/vox-core-rust/generated/kotlin",
        "generated/vox-native/debug/jniLibs",
        "generated/vox-native/release/jniLibs",
        "build-android-cdylibs.sh",
        'repositoryRoot.resolve("toolchains/android-wear-shared-core.json")',
        "inputs.file(toolchainManifest)",
    ):
        if needle not in phase4_build:
            fail(f"Android Phase 4 native packaging drift: {needle}")
    if "ByteBuffer.wrap" in phase4_generated:
        fail("Android generated core adapter wraps caller-owned heap buffers")
    if "unwiredCoreBridge()" in phase4_app:
        fail("Android application wires the unwired core bridge")
    adapter_path = root / "apps/android/core-bridge/src/main/kotlin/md/vox/android/corebridge/GeneratedNativeCoreAdapter.kt"
    android_root = root / "apps/android"
    for source_path in sorted(android_root.glob("*/src/*/**/*")):
        if not source_path.is_file() or source_path.suffix not in {".kt", ".java"}:
            continue
        relative_parts = source_path.relative_to(android_root).parts
        source_set = relative_parts[2].lower()
        if source_set.startswith("test") or "androidtest" in source_set or "unittest" in source_set:
            continue
        if source_path != adapter_path and re.search(r"\bmd\.vox\.core\b", source_path.read_text()):
            fail(f"Android production source bypasses the handwritten core bridge: {source_path.relative_to(root)}")

    phase3_store = (root / "apps/android/data/src/main/kotlin/md/vox/android/data/DurableCaptureStore.kt").read_text()
    if phase3_store.count("StandardCopyOption.REPLACE_EXISTING") > 1:
        fail("Android replacement option must be journal-only")
    tombstone = (root / "apps/android/data/src/main/java/md/vox/android/data/CaptureTombstoneEntity.java").read_text()
    for forbidden in ("text", "url", "filename", "logicalPath", "uri", "documentID", "artifactHash", "noteHash"):
        if re.search(rf"\b{re.escape(forbidden)}\b", tombstone, flags=re.IGNORECASE):
            fail(f"Android tombstone contains forbidden field: {forbidden}")

    artifact_validator = root / android["artifactValidator"]
    if not artifact_validator.is_file() or not os.access(artifact_validator, os.X_OK):
        fail("Android artifact validator is missing or not executable")

    geist_fonts = {
        "Geist-Regular.ttf": "5c8968eafb98a4c4f47033daf29e38e284a6f2a82eb017d171ab040fe7c4b615",
        "Geist-Medium.ttf": "0090e004725f6f64b841715b4167920580f883fcf9b67fc6d744089103fec101",
        "Geist-SemiBold.ttf": "612ec98df33935354f39e81e54101656961ab6e5549f64b63eb57868ba7bab8d",
        "GeistMono-Regular.ttf": "42d8ad2e610238e64e8abfcde3037c63f7850a73928742b7ab7229d897bcb155",
        "GeistMono-Medium.ttf": "90b15711dc3779b2e64e8aff5228154dd019a90bce4947549c4a8a8a43f2ac25",
    }
    for name, expected_hash in geist_fonts.items():
        if digest(root / "Voxboard/Fonts" / name) != expected_hash:
            fail(f"shared Geist source font hash drift: {name}")
    app_build_text = (root / "apps/android/app/build.gradle.kts").read_text()
    wear_build_text = (root / "apps/android/wear/build.gradle.kts").read_text()
    if 'outputs.file(rootProject.file("localization-review.json"))' not in app_build_text:
        fail("Android localization review audit is not a generated Gradle output")
    for source_tree in ("capture-domain", "data", "platform-services"):
        needle = f'rootProject.fileTree("{source_tree}/src/main/kotlin")'
        if needle not in app_build_text:
            fail(f"Android runtime localization Gradle input drift: {needle}")
    localization_audit = load(root / "apps/android/localization-review.json")
    exact(localization_audit, (
        "schemaVersion", "reviewStatus", "formatArgumentContractStatus", "pluralReviewStatus",
        "androidCatalog", "androidCatalogBackedSourceCount", "translationCoverageStatus",
        "pluralImplementationStatus", "pluralSourceCount", "catalog", "runtimeSourceScanRoots", "runtimeSourceLiteralCount", "supportedLocales",
        "literalRuntimeSourceCount", "catalogBackedSourceCount", "aliasBackedSourceCount",
        "incompleteCatalogSourceCount", "missingCatalogSourceCount", "fallbackSourceCount",
        "dynamicRuntimeCallSiteCount", "dynamicRuntimeExpressionCount",
        "integerFormatSourceCount",
        "aliases", "missingCatalogSources", "incompleteCatalogSources", "dynamicRuntimeCalls",
        "integerFormatSources", "limitations",
    ), "Android localization review audit")
    if localization_audit["schemaVersion"] != 1:
        fail("Android localization review audit schema version drift")
    if localization_audit["reviewStatus"] != "requires-human-review":
        fail("Android localization review audit overclaims translation approval")
    if localization_audit["formatArgumentContractStatus"] != "validated":
        fail("Android localization format argument contracts are not validated")
    if localization_audit["pluralReviewStatus"] != "requires-human-review":
        fail("Android localization audit overclaims plural approval")
    if localization_audit["catalog"] != "Voxboard/Localizable.xcstrings":
        fail("Android localization review audit catalog drift")
    if (localization_audit["androidCatalog"] != "apps/android/localization/android-strings.json"
        or localization_audit["translationCoverageStatus"] != "complete"
        or localization_audit["pluralImplementationStatus"] != "cldr-aware"
        or not isinstance(localization_audit["pluralSourceCount"], int)
        or localization_audit["pluralSourceCount"] < 0):
        fail("Android translation and quantity coverage drift")
    expected_source_roots = [
        "apps/android/app/src/main/kotlin",
        "apps/android/capture-domain/src/main/kotlin",
        "apps/android/data/src/main/kotlin",
        "apps/android/platform-services/src/main/kotlin",
    ]
    if localization_audit["runtimeSourceScanRoots"] != expected_source_roots:
        fail("Android runtime localization source-root inventory drift")
    expected_locales = [
        "ar", "bn", "de", "es", "fr", "hi", "id", "it", "ja", "ko", "nl", "pl",
        "pt-BR", "ru", "ta", "th", "tr", "uk", "ur", "vi", "zh-Hans", "zh-Hant",
    ]
    if localization_audit["supportedLocales"] != expected_locales:
        fail("Android localization review locale inventory drift")
    aliases = localization_audit["aliases"]
    for alias in aliases:
        exact(alias, ("source", "catalogSource"), "Android localization alias")
        if alias["source"] == alias["catalogSource"] or alias["source"].lower() != alias["catalogSource"].lower():
            fail("Android localization alias is not a case-only catalog variant")
    if [alias["source"] for alias in aliases] != sorted(alias["source"] for alias in aliases):
        fail("Android localization review alias inventory is not canonical")
    counts = (
        localization_audit["literalRuntimeSourceCount"],
        localization_audit["catalogBackedSourceCount"],
        localization_audit["aliasBackedSourceCount"],
        localization_audit["androidCatalogBackedSourceCount"],
        localization_audit["incompleteCatalogSourceCount"],
        localization_audit["missingCatalogSourceCount"],
    )
    if any(not isinstance(count, int) or count < 0 for count in counts) or counts[0] != sum(counts[1:]):
        fail("Android localization review source counts are inconsistent")
    if counts[4] or counts[5]:
        fail("Android runtime UI copy lacks complete localization catalog coverage")
    if not isinstance(localization_audit["runtimeSourceLiteralCount"], int):
        fail("Android runtime localization lookup-source count is malformed")
    if localization_audit["fallbackSourceCount"] != counts[4] + counts[5]:
        fail("Android localization fallback count differs from incomplete and absent sources")
    missing_sources = localization_audit["missingCatalogSources"]
    if len(missing_sources) != counts[5]:
        fail("Android localization review missing-source inventory differs from count")
    if localization_audit["incompleteCatalogSources"]:
        fail("Android localized runtime source has incomplete locale coverage")
    if [item.get("source") for item in missing_sources] != sorted(item.get("source") for item in missing_sources):
        fail("Android localization review missing-source inventory is not canonical")
    for item in missing_sources:
        exact(item, ("source", "locations"), "Android missing localization source")
        locations = item["locations"]
        if not locations or locations != sorted(set(locations)):
            fail("Android localization review source locations are missing or non-canonical")
        for location in locations:
            path, separator, line = location.rpartition(":")
            if not separator or not line.isdigit() or not (root / path).is_file():
                fail(f"Android localization review source location is invalid: {location}")
    dynamic_calls = localization_audit["dynamicRuntimeCalls"]
    if (
        localization_audit["dynamicRuntimeCallSiteCount"] != 0
        or localization_audit["dynamicRuntimeExpressionCount"] != 0
        or dynamic_calls
    ):
        fail("Android localization dynamic-source call inventory drift")
    if [item.get("expression") for item in dynamic_calls] != sorted(item.get("expression") for item in dynamic_calls):
        fail("Android localization dynamic-source call inventory is not canonical")
    if any("source: String" == item.get("expression") for item in dynamic_calls):
        fail("Android localization dynamic-source audit includes function declarations")
    integer_sources = localization_audit["integerFormatSources"]
    if localization_audit["integerFormatSourceCount"] != len(integer_sources):
        fail("Android localization integer-format source inventory drift")
    configured_export = (root / "apps/android/app/src/main/kotlin/md/vox/android/ConfiguredTranscriptExporter.kt").read_text()
    if "error.message" in configured_export:
        fail("Android configured-export exception text can reach visible UI")
    for label, build_text, task_name in (
        ("phone", app_build_text, "syncGeistFonts"),
        ("Wear", wear_build_text, "syncWearGeistFonts"),
    ):
        for needle in (
            task_name,
            "Voxboard/Fonts",
            'res.directories.add("build/generated/res/geistFonts")',
            'rename { "geist_regular.ttf" }',
            'rename { "geist_medium.ttf" }',
            'rename { "geist_semibold.ttf" }',
            'rename { "geist_mono_regular.ttf" }',
            'rename { "geist_mono_medium.ttf" }',
        ):
            if needle not in build_text:
                fail(f"Android {label} Geist packaging drift: {needle}")
    compose_sources = "\n".join(
        path.read_text() for path in (root / "apps/android/app/src/main/kotlin").rglob("*.kt")
    )
    if re.search(r"FontFamily\.(?:SansSerif|Monospace)", compose_sources):
        fail("Android Compose source bypasses the shared Geist font families")
    phone_artifact_validator = artifact_validator.read_text()
    wear_artifact_validator = (root / "apps/android/scripts/validate-wear-artifacts.py").read_text()
    for name, expected_hash in geist_fonts.items():
        packaged = (
            re.sub(r"(?<=[a-z])(?=[A-Z])", "_", name)
            .lower()
            .replace("-", "_")
            .replace("semi_bold", "semibold")
        )
        for label, validator_text in (
            ("phone", phone_artifact_validator),
            ("Wear", wear_artifact_validator),
        ):
            if packaged not in validator_text or expected_hash not in validator_text:
                fail(f"Android {label} artifact validator does not pin {name}")

    visual_validator = root / "apps/android/scripts/validate-visual-parity.py"
    if not visual_validator.is_file() or not os.access(visual_validator, os.X_OK):
        fail("Android visual parity evidence validator is missing or not executable")
    for needle in (
        'tasks.register<Exec>("validateVisualParityEvidence")',
        '"scripts/validate-visual-parity.py"',
        '"validateVisualParityEvidence"',
    ):
        if needle not in root_build:
            fail(f"Android visual evidence release gate drift: {needle}")
    print(
        "Toolchain validation passed: "
        "UniFFI 0.32.0 bindings, "
        "Gradle 9.3.1/AGP 9.1.1/Kotlin 2.4.10/API 37 application pins, "
        "4 Android API-28 native and 3 iOS-17.6 targets."
    )


if __name__ == "__main__":
    main()
