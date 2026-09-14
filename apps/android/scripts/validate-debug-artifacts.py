#!/usr/bin/env python3
"""Validate the assembled Android app manifest, backup defenses, and native artifacts."""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

ANDROID = "{http://schemas.android.com/apk/res/android}"
EXPECTED_DOMAINS = {
    "root",
    "file",
    "database",
    "sharedpref",
    "external",
    "device_root",
    "device_file",
    "device_database",
    "device_sharedpref",
}
COMPONENT_TAGS = {"activity", "activity-alias", "service", "receiver", "provider"}
WORKMANAGER_MARKERS = {"androidx.work.WorkManagerInitializer"}
REVIEWED_PLATFORM_PERMISSIONS = {
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MICROPHONE",
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.RECORD_AUDIO",
    "android.permission.WAKE_LOCK",
}
REVIEWED_NON_PLATFORM_PERMISSIONS = {
    # Added by the official Play Billing client. It is normal-protection and carries no
    # storage, microphone, location, or cross-app data access.
    "com.android.vending.BILLING",
}
REVIEWED_EXPORTED = {
    "md.vox.android.PhoneWearDataListenerService",
    "md.vox.android.VoxCaptureWidgetProvider",
}
REVIEWED_DEBUG_ONLY_EXPORTED = {
    "androidx.activity.ComponentActivity",
    "androidx.compose.ui.tooling.PreviewActivity",
    "md.vox.android.VisualStoryActivity",
}
REVIEWED_PLATFORM_COMPONENT_PERMISSIONS = {
    "android.permission.BIND_INPUT_METHOD",
    "android.permission.BIND_JOB_SERVICE",
    "android.permission.BIND_QUICK_SETTINGS_TILE",
    "android.permission.DUMP",
    "android.permission.MANAGE_DOCUMENTS",
}
VOX_ELF_TARGETS = {
    "arm64-v8a": (2, 183),
    "armeabi-v7a": (1, 40),
    "x86_64": (2, 62),
    "x86": (1, 3),
}
VOX_LIBRARY = "libvox_core_uniffi.so"
JNA_LIBRARY = "libjnidispatch.so"
SHERPA_LIBRARIES = (
    "libonnxruntime.so",
    "libsherpa-onnx-c-api.so",
    "libsherpa-onnx-cxx-api.so",
    "libsherpa-onnx-jni.so",
)
GEIST_FONTS = {
    "geist_regular.ttf": ("Geist-Regular.ttf", "5c8968eafb98a4c4f47033daf29e38e284a6f2a82eb017d171ab040fe7c4b615"),
    "geist_medium.ttf": ("Geist-Medium.ttf", "0090e004725f6f64b841715b4167920580f883fcf9b67fc6d744089103fec101"),
    "geist_semibold.ttf": ("Geist-SemiBold.ttf", "612ec98df33935354f39e81e54101656961ab6e5549f64b63eb57868ba7bab8d"),
    "geist_mono_regular.ttf": ("GeistMono-Regular.ttf", "42d8ad2e610238e64e8abfcde3037c63f7850a73928742b7ab7229d897bcb155"),
    "geist_mono_medium.ttf": ("GeistMono-Medium.ttf", "90b15711dc3779b2e64e8aff5228154dd019a90bce4947549c4a8a8a43f2ac25"),
}


class ValidationError(Exception):
    pass


def parse_xml(path: Path) -> ET.Element:
    if not path.is_file():
        raise ValidationError(f"missing XML input: {path}")
    data = path.read_bytes()
    if b"<!DOCTYPE" in data.upper():
        raise ValidationError(f"DOCTYPE is forbidden: {path}")
    try:
        return ET.fromstring(data)
    except ET.ParseError as error:
        raise ValidationError(f"invalid XML {path}: {error}") from error


def android(element: ET.Element, name: str) -> str:
    return element.get(ANDROID + name, "")


def signature_permissions(manifest: ET.Element) -> set[str]:
    result = set()
    for declaration in manifest.findall("permission"):
        name = android(declaration, "name")
        levels = android(declaration, "protectionLevel").split("|")
        if name and "signature" in levels:
            result.add(name)
    return result


def validate_merged_manifest(path: Path) -> None:
    manifest = parse_xml(path)
    if manifest.tag != "manifest":
        raise ValidationError("merged manifest root must be <manifest>")
    application = manifest.find("application")
    if application is None:
        raise ValidationError("merged manifest has no application")
    if android(application, "allowBackup") != "false":
        raise ValidationError("merged application must set allowBackup=false")
    if android(application, "fullBackupContent") != "@xml/backup_rules":
        raise ValidationError("merged application legacy backup rule reference drift")
    if android(application, "dataExtractionRules") != "@xml/data_extraction_rules":
        raise ValidationError("merged application data extraction rule reference drift")
    is_debuggable = android(application, "debuggable") == "true"

    protected = signature_permissions(manifest)
    for request in manifest.findall("uses-permission") + manifest.findall("uses-permission-sdk-23"):
        name = android(request, "name")
        if name.startswith("android.permission.") and name not in REVIEWED_PLATFORM_PERMISSIONS:
            raise ValidationError(f"merged manifest requests unreviewed platform permission {name}")
        if name not in protected and not name.startswith("android.permission."):
            if name not in REVIEWED_NON_PLATFORM_PERMISSIONS:
                raise ValidationError(f"merged manifest requests unreviewed non-signature permission {name}")

    launcher_count = 0
    for component in application:
        tag = component.tag.rsplit("}", 1)[-1]
        if tag == "meta-data" and android(component, "value") in WORKMANAGER_MARKERS:
            raise ValidationError("WorkManager/startup initializer is packaged")
        if tag not in COMPONENT_TAGS:
            continue
        name = android(component, "name")
        exported = android(component, "exported")
        if exported not in {"", "true", "false"}:
            raise ValidationError(f"component has non-literal android:exported value: {name}={exported}")
        if name in WORKMANAGER_MARKERS:
            raise ValidationError(f"WorkManager initializer is packaged: {name}")
        for metadata in component.findall(".//meta-data"):
            if android(metadata, "name") in WORKMANAGER_MARKERS or android(metadata, "value") in WORKMANAGER_MARKERS:
                raise ValidationError("WorkManager initializer metadata is packaged")
        actions = {
            android(action, "name")
            for intent_filter in component.findall("intent-filter")
            for action in intent_filter.findall("action")
        }
        categories = {
            android(category, "name")
            for intent_filter in component.findall("intent-filter")
            for category in intent_filter.findall("category")
        }
        is_launcher = (
            tag in {"activity", "activity-alias"}
            and "android.intent.action.MAIN" in actions
            and "android.intent.category.LAUNCHER" in categories
        )
        if is_launcher:
            launcher_count += 1
            if name != "md.vox.android.MainActivity" or exported != "true":
                raise ValidationError(f"unexpected launcher component: {name}")
        if exported == "true" and not is_launcher:
            permission = android(component, "permission")
            explicitly_reviewed = (
                name in REVIEWED_EXPORTED
                or (is_debuggable and name in REVIEWED_DEBUG_ONLY_EXPORTED)
            )
            permission_protected = (
                permission in protected
                or permission in REVIEWED_PLATFORM_COMPONENT_PERMISSIONS
            )
            if not explicitly_reviewed and not permission_protected:
                raise ValidationError(f"unexpected unpermissioned exported component: {name}")
    if launcher_count != 1:
        raise ValidationError(f"expected one launcher, found {launcher_count}")


def validate_vox_native_libraries(apk_path: Path) -> None:
    if not apk_path.is_file():
        raise ValidationError(f"missing Android artifact input: {apk_path}")
    try:
        with zipfile.ZipFile(apk_path) as apk:
            names = apk.namelist()
            if len(names) != len(set(names)):
                raise ValidationError("Android artifact contains duplicate ZIP entries")
            prefix = "base/" if apk_path.suffix == ".aab" else ""
            native_libraries = (("Vox", VOX_LIBRARY), ("JNA", JNA_LIBRARY)) + tuple(
                ("sherpa-onnx", library) for library in SHERPA_LIBRARIES
            )
            for label, library in native_libraries:
                actual = {name for name in names if name.endswith("/" + library)}
                expected = {f"{prefix}lib/{abi}/{library}" for abi in VOX_ELF_TARGETS}
                if actual != expected:
                    raise ValidationError(
                        f"{label} native ABI set differs: expected {sorted(expected)}, found {sorted(actual)}"
                    )
                for abi, (expected_class, expected_machine) in VOX_ELF_TARGETS.items():
                    data = apk.read(f"{prefix}lib/{abi}/{library}")
                    if len(data) < 20 or data[:4] != b"\x7fELF":
                        raise ValidationError(f"{abi} {label} library is not ELF")
                    if data[4] != expected_class or data[5] != 1:
                        raise ValidationError(f"{abi} {label} ELF class/endianness differs")
                    machine = int.from_bytes(data[18:20], "little")
                    if machine != expected_machine:
                        raise ValidationError(f"{abi} {label} ELF machine differs: {machine}")
            for packaged_name, (_, expected_sha256) in GEIST_FONTS.items():
                entry = f"{prefix}res/font/{packaged_name}"
                if entry not in names:
                    raise ValidationError(f"missing packaged Geist font {entry}")
                actual_sha256 = hashlib.sha256(apk.read(entry)).hexdigest()
                if actual_sha256 != expected_sha256:
                    raise ValidationError(
                        f"packaged Geist font hash differs for {packaged_name}: {actual_sha256}"
                    )
    except zipfile.BadZipFile as error:
        raise ValidationError(f"invalid Android artifact ZIP: {error}") from error


def excluded_domains(parent: ET.Element) -> set[str]:
    domains = set()
    for exclude in parent.findall("exclude"):
        if exclude.get("path") != ".":
            raise ValidationError("backup exclusion must cover domain root path='.'")
        domains.add(exclude.get("domain", ""))
    return domains


def validate_backup_rules(legacy_path: Path, modern_path: Path) -> None:
    legacy = parse_xml(legacy_path)
    if legacy.tag != "full-backup-content" or excluded_domains(legacy) != EXPECTED_DOMAINS:
        raise ValidationError("legacy backup exclusions do not cover every governed domain")
    modern = parse_xml(modern_path)
    if modern.tag != "data-extraction-rules":
        raise ValidationError("modern backup rules root drift")
    for section_name in ("cloud-backup", "device-transfer"):
        section = modern.find(section_name)
        if section is None or excluded_domains(section) != EXPECTED_DOMAINS:
            raise ValidationError(f"{section_name} exclusions do not cover every governed domain")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--backup-rules", required=True, type=Path)
    parser.add_argument("--data-extraction-rules", required=True, type=Path)
    parser.add_argument("--apk", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        validate_merged_manifest(arguments.manifest)
        validate_backup_rules(arguments.backup_rules, arguments.data_extraction_rules)
        validate_vox_native_libraries(arguments.apk)
    except ValidationError as error:
        print(f"Android artifact validation failed: {error}", file=sys.stderr)
        return 1
    print("Android artifact validation passed: reviewed permissions/components, backup defenses, exact Geist fonts, and four-ABI Vox/JNA/sherpa-onnx ELF targets are closed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
