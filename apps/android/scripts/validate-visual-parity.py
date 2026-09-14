#!/usr/bin/env python3
"""Validate the integrity and honest review status of Android visual-parity evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import struct
import sys


EXPECTED_ANDROID_STORIES = {
    story: f"artifacts/android-parity/goldens/phone/phone-{story}-dark.png"
    for story in (
        "01-quick-capture",
        "02-history",
        "03-settings",
        "04-models",
        "05-capture-presets",
        "06-app-language",
        "07-live-recording",
    )
}
IOS_REFERENCES = {
    "01-quick-capture": "artifacts/app-store-raw-latest/01-quick-capture.png",
    "03-settings": "artifacts/app-store-raw-latest/03-settings.png",
    "04-models": "artifacts/app-store-raw-latest/04-models.png",
    "05-capture-presets": "artifacts/app-store-raw-latest/05-capture-presets.png",
}
PIXEL_MISMATCH_PERCENT = {
    "01-quick-capture": 4.53,
    "03-settings": 13.53,
    "04-models": 56.46,
    "05-capture-presets": 7.38,
}
ALL_STORY_IDS = tuple(EXPECTED_ANDROID_STORIES)
STATE_STORY_IDS = (
    "08-vault-repair",
    "09-history-empty",
    "10-history-folder-repair",
    "11-recording-paused",
    "12-recording-failed",
    "13-upgrade-pending",
    "14-upgrade-active",
)
RESILIENCE_STORY_IDS = (
    "15-loading",
    "16-upgrade-quota-reached",
    "17-upgrade-offline",
    "18-recording-quota-reached",
    "19-recording-interrupted",
    "20-history-unknown-outcome",
    "21-history-permanent-failure",
)
STATE_CAPTURE_SETS = {
    "phone-state-dark-default-en": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "storyIDs": STATE_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/states/phone-{story}-dark.png",
        "dimensions": (1080, 2400),
        "contactSheet": (
            "artifacts/android-parity/goldens/states/phone-state-dark-contact-sheet.png",
            (1152, 2472),
        ),
    },
    "phone-state-light-default-en": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "light",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "storyIDs": STATE_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/states/phone-{story}-light.png",
        "dimensions": (1080, 2400),
        "contactSheet": (
            "artifacts/android-parity/goldens/states/phone-state-light-contact-sheet.png",
            (1152, 2472),
        ),
    },
    "phone-state-dark-large-text-en": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 2.0,
            "layoutDirection": "LTR",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "storyIDs": STATE_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/states/phone-{story}-dark-large-text.png",
        "dimensions": (1080, 2400),
        "contactSheet": (
            "artifacts/android-parity/goldens/states/phone-state-large-text-contact-sheet.png",
            (1152, 2472),
        ),
    },
    "phone-state-dark-rtl-ar": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "dark",
            "locale": "ar",
            "fontScale": 1.0,
            "layoutDirection": "RTL",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "storyIDs": STATE_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/states/phone-{story}-dark-rtl-ar.png",
        "dimensions": (1080, 2400),
        "contactSheet": (
            "artifacts/android-parity/goldens/states/phone-state-rtl-ar-contact-sheet.png",
            (1152, 2472),
        ),
    },
}
RESILIENCE_CAPTURE_SETS = {
    "phone-resilience-dark-default-en": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "storyIDs": RESILIENCE_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/resilience/phone-{story}-dark.png",
        "dimensions": (1080, 2400),
        "contactSheet": (
            "artifacts/android-parity/goldens/resilience/phone-resilience-dark-contact-sheet.png",
            (1152, 2472),
        ),
    },
    "phone-resilience-light-default-en": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "light",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "storyIDs": RESILIENCE_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/resilience/phone-{story}-light.png",
        "dimensions": (1080, 2400),
        "contactSheet": (
            "artifacts/android-parity/goldens/resilience/phone-resilience-light-contact-sheet.png",
            (1152, 2472),
        ),
    },
    "phone-resilience-dark-large-text-en": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 2.0,
            "layoutDirection": "LTR",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "storyIDs": RESILIENCE_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/resilience/phone-{story}-dark-large-text.png",
        "dimensions": (1080, 2400),
        "contactSheet": (
            "artifacts/android-parity/goldens/resilience/phone-resilience-large-text-contact-sheet.png",
            (1152, 2472),
        ),
    },
    "phone-resilience-dark-rtl-ar": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "dark",
            "locale": "ar",
            "fontScale": 1.0,
            "layoutDirection": "RTL",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "storyIDs": RESILIENCE_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/resilience/phone-{story}-dark-rtl-ar.png",
        "dimensions": (1080, 2400),
        "contactSheet": (
            "artifacts/android-parity/goldens/resilience/phone-resilience-rtl-ar-contact-sheet.png",
            (1152, 2472),
        ),
    },
}
MOTION_CAPTURE = {
    "deviceName": "healthmd_phone_api35",
    "serial": "emulator-5556",
    "apiLevel": 35,
    "resolutionPx": [1080, 2400],
    "appearance": "dark",
    "locale": "en-US",
    "fontScale": 1.0,
    "captureMethod": "Argent screen recording",
    "sourceActivity": "md.vox.android.MainActivity",
    "showTouches": True,
    "trimStaticFrames": True,
}
MOTION_CLIPS = {
    "android-vault-setup-flow-api35": {
        "path": "artifacts/android-parity/motion/android-vault-setup-flow-api35.mp4",
        "bytes": 396732,
        "width": 1080,
        "height": 2400,
        "frameRate": "30/1",
        "codec": "h264",
        "durationMs": 21967,
        "wallClockMs": 54086,
        "trimmedMs": 32119,
        "flow": [
            "vault setup",
            "system document-tree picker",
            "persisted folder grant",
            "loading",
            "composer",
        ],
    },
    "android-primary-navigation-flow-api35": {
        "path": "artifacts/android-parity/motion/android-primary-navigation-flow-api35.mp4",
        "bytes": 1154600,
        "width": 1080,
        "height": 2400,
        "frameRate": "30/1",
        "codec": "h264",
        "durationMs": 23967,
        "wallClockMs": 90004,
        "trimmedMs": 66037,
        "flow": [
            "composer",
            "settings",
            "models",
            "settings",
            "composer",
            "history",
        ],
    },
}
ADDITIONAL_CAPTURE_SETS = {
    "phone-light-default-en": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "light",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
        },
        "storyIDs": ALL_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/phone/phone-{story}-light.png",
        "dimensions": (1080, 2400),
    },
    "phone-dark-large-text-en": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 2.0,
            "layoutDirection": "LTR",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
        },
        "storyIDs": ALL_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/phone/phone-{story}-dark-large-text.png",
        "dimensions": (1080, 2400),
    },
    "phone-dark-rtl-ar": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "dark",
            "locale": "ar",
            "fontScale": 1.0,
            "layoutDirection": "RTL",
            "posture": "standard",
            "captureMethod": "Argent screenshot",
        },
        "storyIDs": ALL_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/phone/phone-{story}-dark-rtl-ar.png",
        "dimensions": (1080, 2400),
    },
    "tablet-dark-landscape-en": {
        "capture": {
            "deviceName": "vox_tablet_api35",
            "serial": "emulator-5558",
            "apiLevel": 35,
            "resolutionPx": [2560, 1600],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "posture": "landscape",
            "captureMethod": "Android adb screencap fallback",
        },
        "storyIDs": ALL_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/tablet/tablet-{story}-dark-landscape.png",
        "dimensions": (2560, 1600),
    },
    "foldable-dark-opened-en": {
        "capture": {
            "deviceName": "vox_foldable_api35",
            "serial": "emulator-5558",
            "apiLevel": 35,
            "resolutionPx": [1768, 2208],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "posture": "OPENED",
            "captureMethod": "Android adb screencap fallback",
        },
        "storyIDs": ALL_STORY_IDS,
        "pathTemplate": "artifacts/android-parity/goldens/foldable/foldable-{story}-dark-opened.png",
        "dimensions": (1768, 2208),
    },
    "foldable-dark-half-opened-en": {
        "capture": {
            "deviceName": "vox_foldable_api35",
            "serial": "emulator-5558",
            "apiLevel": 35,
            "resolutionPx": [1768, 2208],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "posture": "HALF_OPENED",
            "captureMethod": "Android adb screencap fallback",
        },
        "storyIDs": ("01-quick-capture", "07-live-recording"),
        "pathTemplate": "artifacts/android-parity/goldens/foldable/foldable-{story}-dark-half-opened.png",
        "dimensions": (1768, 2208),
    },
    "foldable-dark-closed-en": {
        "capture": {
            "deviceName": "vox_foldable_api35",
            "serial": "emulator-5558",
            "apiLevel": 35,
            "resolutionPx": [1768, 2208],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "posture": "CLOSED",
            "captureMethod": "Android adb screencap fallback",
        },
        "storyIDs": ("01-quick-capture",),
        "pathTemplate": "artifacts/android-parity/goldens/foldable/foldable-{story}-dark-closed.png",
        "dimensions": (1768, 2208),
    },
}
ADDITIONAL_CONTACT_SHEETS = {
    "phone-light-default-en": (
        "artifacts/android-parity/goldens/phone/phone-light-story-contact-sheet.png",
        (1152, 2472),
    ),
    "phone-dark-large-text-en": (
        "artifacts/android-parity/goldens/phone/phone-large-text-story-contact-sheet.png",
        (1152, 2472),
    ),
    "phone-dark-rtl-ar": (
        "artifacts/android-parity/goldens/phone/phone-rtl-ar-story-contact-sheet.png",
        (1152, 2472),
    ),
    "tablet-dark-landscape-en": (
        "artifacts/android-parity/goldens/tablet/tablet-story-contact-sheet.png",
        (1328, 1696),
    ),
    "foldable-dark-postures-en": (
        "artifacts/android-parity/goldens/foldable/foldable-story-contact-sheet.png",
        (1272, 2096),
    ),
}
SUPPLEMENTAL_SCREENSHOTS = {
    "phone-onboarding-en-dark-200": (
        "artifacts/android-parity/goldens/phone-onboarding-en-dark-200.png",
        (1080, 2250),
    ),
    "phone-onboarding-ar-dark-200": (
        "artifacts/android-parity/goldens/phone-onboarding-ar-dark-200.png",
        (1080, 2400),
    ),
}
WINDOWING_CAPTURE_SETS = {
    "phone-dark-split-horizontal-en": {
        "capture": {
            "deviceName": "healthmd_phone_api35",
            "serial": "emulator-5556",
            "apiLevel": 35,
            "resolutionPx": [1080, 2400],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "windowingMode": "split-screen-horizontal",
            "appTaskBoundsPx": [0, 0, 1080, 1187],
            "companionTask": "com.android.settings/.Settings",
            "companionTaskBoundsPx": [0, 1213, 1080, 2400],
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "screenshots": {
            "01-quick-capture": {
                "path": "artifacts/android-parity/goldens/windowing/phone-01-quick-capture-dark-split-horizontal.png",
                "dimensions": (1080, 2400),
            },
        },
    },
    "tablet-dark-freeform-en": {
        "capture": {
            "deviceName": "vox_tablet_api35",
            "serial": "emulator-5554",
            "apiLevel": 35,
            "resolutionPx": [2560, 1600],
            "appearance": "dark",
            "locale": "en-US",
            "fontScale": 1.0,
            "layoutDirection": "LTR",
            "windowingMode": "freeform",
            "captureMethod": "Argent screenshot",
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        },
        "screenshots": {
            "01-quick-capture-narrow": {
                "storyID": "01-quick-capture",
                "appTaskBoundsPx": [892, 102, 1668, 1482],
                "path": "artifacts/android-parity/goldens/windowing/tablet-01-quick-capture-dark-freeform.png",
                "dimensions": (2560, 1600),
            },
            "03-settings-narrow": {
                "storyID": "03-settings",
                "appTaskBoundsPx": [892, 102, 1668, 1482],
                "path": "artifacts/android-parity/goldens/windowing/tablet-03-settings-dark-freeform.png",
                "dimensions": (2560, 1600),
            },
            "03-settings-wide": {
                "storyID": "03-settings",
                "appTaskBoundsPx": [400, 250, 2160, 1300],
                "path": "artifacts/android-parity/goldens/windowing/tablet-03-settings-dark-freeform-wide.png",
                "dimensions": (2560, 1600),
            },
            "07-live-recording-narrow": {
                "storyID": "07-live-recording",
                "appTaskBoundsPx": [892, 102, 1668, 1482],
                "path": "artifacts/android-parity/goldens/windowing/tablet-07-live-recording-dark-freeform.png",
                "dimensions": (2560, 1600),
            },
        },
        "contactSheet": {
            "path": "artifacts/android-parity/goldens/windowing/windowing-story-contact-sheet.png",
            "dimensions": (1504, 1596),
        },
    },
}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class ValidationError(Exception):
    pass


def digest(path: Path) -> str:
    if not path.is_file():
        raise ValidationError(f"missing visual evidence file: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_dimensions(path: Path) -> tuple[int, int]:
    if not path.is_file():
        raise ValidationError(f"missing visual evidence PNG: {path}")
    header = path.read_bytes()[:24]
    if len(header) != 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValidationError(f"invalid PNG header: {path}")
    return struct.unpack(">II", header[16:24])


def checked_relative_path(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValidationError(f"{label} path is missing")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.as_posix() != value:
        raise ValidationError(f"{label} path is not a canonical repository-relative path: {value}")
    return value


def validate_asset(
    repository_root: Path,
    payload: object,
    expected_path: str,
    expected_dimensions: tuple[int, int],
    label: str,
) -> None:
    if not isinstance(payload, dict):
        raise ValidationError(f"{label} metadata is missing")
    path_value = checked_relative_path(payload.get("path"), label)
    if path_value != expected_path:
        raise ValidationError(f"{label} path differs: expected {expected_path}, found {path_value}")
    path = repository_root / path_value
    actual_dimensions = png_dimensions(path)
    declared_dimensions = (payload.get("width"), payload.get("height"))
    if actual_dimensions != expected_dimensions or declared_dimensions != expected_dimensions:
        raise ValidationError(
            f"{label} dimensions differ: expected {expected_dimensions}, "
            f"declared {declared_dimensions}, actual {actual_dimensions}"
        )
    expected_digest = payload.get("sha256")
    if not isinstance(expected_digest, str) or len(expected_digest) != 64:
        raise ValidationError(f"{label} SHA-256 is malformed")
    actual_digest = digest(path)
    if actual_digest != expected_digest:
        raise ValidationError(f"{label} SHA-256 differs: {actual_digest}")


def validate_motion_asset(
    repository_root: Path,
    payload: object,
    specification: dict,
    label: str,
) -> None:
    if not isinstance(payload, dict):
        raise ValidationError(f"{label} metadata is missing")
    expected_fields = {"id", "sha256", *specification}
    if set(payload) != expected_fields:
        raise ValidationError(f"{label} metadata fields differ")
    path_value = checked_relative_path(payload.get("path"), label)
    if path_value != specification["path"]:
        raise ValidationError(
            f"{label} path differs: expected {specification['path']}, found {path_value}"
        )
    for key, expected in specification.items():
        if payload.get(key) != expected:
            raise ValidationError(f"{label} metadata differs for {key}")
    path = repository_root / path_value
    if not path.is_file():
        raise ValidationError(f"missing motion evidence file: {path}")
    header = path.read_bytes()[:12]
    if len(header) != 12 or header[4:8] != b"ftyp":
        raise ValidationError(f"invalid MP4 header: {path}")
    if path.stat().st_size != specification["bytes"]:
        raise ValidationError(f"{label} byte count differs: {path.stat().st_size}")
    expected_digest = payload.get("sha256")
    if not isinstance(expected_digest, str) or len(expected_digest) != 64:
        raise ValidationError(f"{label} SHA-256 is malformed")
    actual_digest = digest(path)
    if actual_digest != expected_digest:
        raise ValidationError(f"{label} SHA-256 differs: {actual_digest}")


def validate_manifest(manifest_path: Path, repository_root: Path) -> None:
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(f"cannot read visual parity manifest: {error}") from error
    if not isinstance(manifest, dict) or manifest.get("schemaVersion") != 1:
        raise ValidationError("visual parity manifest schema version differs")
    if manifest.get("status") != "captured-unreviewed":
        raise ValidationError("visual evidence must remain captured-unreviewed until human approval")

    capture = manifest.get("capture")
    expected_capture = {
        "deviceName": "healthmd_phone_api35",
        "serial": "emulator-5556",
        "apiLevel": 35,
        "resolutionPx": [1080, 2400],
        "appearance": "dark",
        "locale": "en-US",
        "fontScale": 1.0,
        "sourceActivity": "md.vox.android.VisualStoryActivity",
    }
    if not isinstance(capture, dict):
        raise ValidationError("visual capture metadata is missing")
    for key, expected in expected_capture.items():
        if capture.get(key) != expected:
            raise ValidationError(f"visual capture metadata differs for {key}")

    stories = manifest.get("stories")
    if not isinstance(stories, list):
        raise ValidationError("visual story inventory is missing")
    by_id: dict[str, dict] = {}
    for story in stories:
        if not isinstance(story, dict) or not isinstance(story.get("id"), str):
            raise ValidationError("visual story entry is malformed")
        story_id = story["id"]
        if story_id in by_id:
            raise ValidationError(f"duplicate visual story: {story_id}")
        by_id[story_id] = story
    if set(by_id) != set(EXPECTED_ANDROID_STORIES):
        raise ValidationError("visual story inventory differs")

    for story_id, android_path in EXPECTED_ANDROID_STORIES.items():
        story = by_id[story_id]
        validate_asset(repository_root, story.get("android"), android_path, (1080, 2400), story_id)
        ios_path = IOS_REFERENCES.get(story_id)
        if ios_path is None:
            if story.get("iosReference") is not None or story.get("comparison") is not None:
                raise ValidationError(f"{story_id} invents an unavailable canonical iOS comparison")
            continue

        validate_asset(
            repository_root,
            story.get("iosReference"),
            ios_path,
            (1206, 2622),
            f"{story_id} iOS reference",
        )
        comparison = story.get("comparison")
        if not isinstance(comparison, dict):
            raise ValidationError(f"{story_id} comparison metadata is missing")
        if comparison.get("tool") != "Argent screenshot-diff":
            raise ValidationError(f"{story_id} comparison tool differs")
        if comparison.get("directComparison") != "dimension-mismatch-expected":
            raise ValidationError(f"{story_id} direct dimension-mismatch result was lost")
        if comparison.get("status") != "changed" or comparison.get("reviewStatus") != "unreviewed":
            raise ValidationError(f"{story_id} comparison overstates visual approval")
        if comparison.get("pixelMismatchPercent") != PIXEL_MISMATCH_PERCENT[story_id]:
            raise ValidationError(f"{story_id} normalized mismatch metric differs")
        normalized_path = f"artifacts/android-parity/normalized-ios/{story_id}-1080x2400.png"
        diff_root = f"artifacts/android-parity/diffs/{story_id}-normalized"
        validate_asset(
            repository_root,
            comparison.get("normalizedReference"),
            normalized_path,
            (1080, 2400),
            f"{story_id} normalized iOS reference",
        )
        validate_asset(
            repository_root,
            comparison.get("diff"),
            f"{diff_root}/phone-{story_id}-dark-diff.png",
            (1080, 2400),
            f"{story_id} full-resolution diff",
        )
        context = comparison.get("contextDiff")
        if not isinstance(context, dict):
            raise ValidationError(f"{story_id} context diff metadata is missing")
        context_path = checked_relative_path(context.get("path"), f"{story_id} context diff")
        expected_context = f"{diff_root}/phone-{story_id}-dark-context-diff.png"
        if context_path != expected_context or digest(repository_root / context_path) != context.get("sha256"):
            raise ValidationError(f"{story_id} context diff differs")

    state_capture_sets = manifest.get("stateCaptureSets")
    if not isinstance(state_capture_sets, list):
        raise ValidationError("state visual capture-set inventory is missing")
    state_capture_sets_by_id = {
        item.get("id"): item
        for item in state_capture_sets
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    if (
        len(state_capture_sets_by_id) != len(state_capture_sets)
        or set(state_capture_sets_by_id) != set(STATE_CAPTURE_SETS)
    ):
        raise ValidationError("state visual capture-set inventory differs")
    for capture_set_id, specification in STATE_CAPTURE_SETS.items():
        capture_set = state_capture_sets_by_id[capture_set_id]
        if capture_set.get("reviewStatus") != "unreviewed":
            raise ValidationError(f"{capture_set_id} overstates visual approval")
        if capture_set.get("capture") != specification["capture"]:
            raise ValidationError(f"{capture_set_id} capture metadata differs")
        screenshots = capture_set.get("screenshots")
        if not isinstance(screenshots, list):
            raise ValidationError(f"{capture_set_id} screenshot inventory is missing")
        screenshots_by_id = {
            item.get("id"): item
            for item in screenshots
            if isinstance(item, dict) and isinstance(item.get("id"), str)
        }
        expected_story_ids = tuple(specification["storyIDs"])
        if len(screenshots_by_id) != len(screenshots) or set(screenshots_by_id) != set(expected_story_ids):
            raise ValidationError(f"{capture_set_id} screenshot inventory differs")
        for story_id in expected_story_ids:
            expected_path = specification["pathTemplate"].format(story=story_id)
            validate_asset(
                repository_root,
                screenshots_by_id[story_id],
                expected_path,
                specification["dimensions"],
                f"{capture_set_id}/{story_id}",
            )
        contact_path, contact_dimensions = specification["contactSheet"]
        validate_asset(
            repository_root,
            capture_set.get("contactSheet"),
            contact_path,
            contact_dimensions,
            f"{capture_set_id} contact sheet",
        )

    resilience_capture_sets = manifest.get("resilienceCaptureSets")
    if not isinstance(resilience_capture_sets, list):
        raise ValidationError("resilience visual capture-set inventory is missing")
    resilience_capture_sets_by_id = {
        item.get("id"): item
        for item in resilience_capture_sets
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    if (
        len(resilience_capture_sets_by_id) != len(resilience_capture_sets)
        or set(resilience_capture_sets_by_id) != set(RESILIENCE_CAPTURE_SETS)
    ):
        raise ValidationError("resilience visual capture-set inventory differs")
    for capture_set_id, specification in RESILIENCE_CAPTURE_SETS.items():
        capture_set = resilience_capture_sets_by_id[capture_set_id]
        if capture_set.get("reviewStatus") != "unreviewed":
            raise ValidationError(f"{capture_set_id} overstates visual approval")
        if capture_set.get("capture") != specification["capture"]:
            raise ValidationError(f"{capture_set_id} capture metadata differs")
        screenshots = capture_set.get("screenshots")
        if not isinstance(screenshots, list):
            raise ValidationError(f"{capture_set_id} screenshot inventory is missing")
        screenshots_by_id = {
            item.get("id"): item
            for item in screenshots
            if isinstance(item, dict) and isinstance(item.get("id"), str)
        }
        expected_story_ids = tuple(specification["storyIDs"])
        if len(screenshots_by_id) != len(screenshots) or set(screenshots_by_id) != set(expected_story_ids):
            raise ValidationError(f"{capture_set_id} screenshot inventory differs")
        for story_id in expected_story_ids:
            expected_path = specification["pathTemplate"].format(story=story_id)
            validate_asset(
                repository_root,
                screenshots_by_id[story_id],
                expected_path,
                specification["dimensions"],
                f"{capture_set_id}/{story_id}",
            )
        contact_path, contact_dimensions = specification["contactSheet"]
        validate_asset(
            repository_root,
            capture_set.get("contactSheet"),
            contact_path,
            contact_dimensions,
            f"{capture_set_id} contact sheet",
        )

    windowing_sets = manifest.get("windowingCaptureSets")
    if not isinstance(windowing_sets, list):
        raise ValidationError("windowing visual capture-set inventory is missing")
    windowing_sets_by_id = {
        item.get("id"): item
        for item in windowing_sets
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    if len(windowing_sets_by_id) != len(windowing_sets) or set(windowing_sets_by_id) != set(WINDOWING_CAPTURE_SETS):
        raise ValidationError("windowing visual capture-set inventory differs")
    for capture_set_id, specification in WINDOWING_CAPTURE_SETS.items():
        capture_set = windowing_sets_by_id[capture_set_id]
        if capture_set.get("reviewStatus") != "unreviewed":
            raise ValidationError(f"{capture_set_id} overstates visual approval")
        if capture_set.get("capture") != specification["capture"]:
            raise ValidationError(f"{capture_set_id} capture metadata differs")
        screenshots = capture_set.get("screenshots")
        if not isinstance(screenshots, list):
            raise ValidationError(f"{capture_set_id} screenshot inventory is missing")
        screenshots_by_id = {
            item.get("id"): item
            for item in screenshots
            if isinstance(item, dict) and isinstance(item.get("id"), str)
        }
        expected_screenshots = specification["screenshots"]
        if len(screenshots_by_id) != len(screenshots) or set(screenshots_by_id) != set(expected_screenshots):
            raise ValidationError(f"{capture_set_id} screenshot inventory differs")
        for screenshot_id, expected in expected_screenshots.items():
            payload = screenshots_by_id[screenshot_id]
            expected_auxiliary = {
                key: value
                for key, value in expected.items()
                if key not in {"path", "dimensions"}
            }
            for key, value in expected_auxiliary.items():
                if payload.get(key) != value:
                    raise ValidationError(f"{capture_set_id}/{screenshot_id} metadata differs for {key}")
            expected_keys = {"id", "path", "sha256", "width", "height", *expected_auxiliary}
            if set(payload) != expected_keys:
                raise ValidationError(f"{capture_set_id}/{screenshot_id} metadata fields differ")
            validate_asset(
                repository_root,
                payload,
                expected["path"],
                expected["dimensions"],
                f"{capture_set_id}/{screenshot_id}",
            )
        contact_sheet = specification.get("contactSheet")
        if contact_sheet is None:
            if capture_set.get("contactSheet") is not None:
                raise ValidationError(f"{capture_set_id} invents a contact sheet")
        else:
            validate_asset(
                repository_root,
                capture_set.get("contactSheet"),
                contact_sheet["path"],
                contact_sheet["dimensions"],
                f"{capture_set_id} contact sheet",
            )

    capture_sets = manifest.get("additionalCaptureSets")
    if not isinstance(capture_sets, list):
        raise ValidationError("additional visual capture-set inventory is missing")
    capture_sets_by_id: dict[str, dict] = {}
    for capture_set in capture_sets:
        if not isinstance(capture_set, dict) or not isinstance(capture_set.get("id"), str):
            raise ValidationError("additional visual capture-set entry is malformed")
        capture_set_id = capture_set["id"]
        if capture_set_id in capture_sets_by_id:
            raise ValidationError(f"duplicate visual capture set: {capture_set_id}")
        capture_sets_by_id[capture_set_id] = capture_set
    if set(capture_sets_by_id) != set(ADDITIONAL_CAPTURE_SETS):
        raise ValidationError("additional visual capture-set inventory differs")
    for capture_set_id, specification in ADDITIONAL_CAPTURE_SETS.items():
        capture_set = capture_sets_by_id[capture_set_id]
        if capture_set.get("reviewStatus") != "unreviewed":
            raise ValidationError(f"{capture_set_id} overstates visual approval")
        expected_metadata = {
            **specification["capture"],
            "sourceActivity": "md.vox.android.VisualStoryActivity",
        }
        if capture_set.get("capture") != expected_metadata:
            raise ValidationError(f"{capture_set_id} capture metadata differs")
        screenshots = capture_set.get("screenshots")
        if not isinstance(screenshots, list):
            raise ValidationError(f"{capture_set_id} screenshot inventory is missing")
        screenshots_by_id = {
            item.get("id"): item
            for item in screenshots
            if isinstance(item, dict) and isinstance(item.get("id"), str)
        }
        expected_story_ids = tuple(specification["storyIDs"])
        if len(screenshots_by_id) != len(screenshots) or set(screenshots_by_id) != set(expected_story_ids):
            raise ValidationError(f"{capture_set_id} screenshot inventory differs")
        for story_id in expected_story_ids:
            expected_path = specification["pathTemplate"].format(story=story_id)
            validate_asset(
                repository_root,
                screenshots_by_id[story_id],
                expected_path,
                specification["dimensions"],
                f"{capture_set_id}/{story_id}",
            )

    validate_asset(
        repository_root,
        manifest.get("contactSheet"),
        "artifacts/android-parity/goldens/phone/phone-story-contact-sheet.png",
        (1152, 2472),
        "phone story contact sheet",
    )
    contact_sheets = manifest.get("additionalContactSheets")
    if not isinstance(contact_sheets, list):
        raise ValidationError("additional visual contact-sheet inventory is missing")
    contact_sheets_by_id = {
        item.get("id"): item
        for item in contact_sheets
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    if len(contact_sheets_by_id) != len(contact_sheets) or set(contact_sheets_by_id) != set(ADDITIONAL_CONTACT_SHEETS):
        raise ValidationError("additional visual contact-sheet inventory differs")
    for contact_sheet_id, (path, dimensions) in ADDITIONAL_CONTACT_SHEETS.items():
        payload = dict(contact_sheets_by_id[contact_sheet_id])
        payload.pop("id", None)
        validate_asset(repository_root, payload, path, dimensions, contact_sheet_id)
    supplemental = manifest.get("supplementalScreenshots")
    if not isinstance(supplemental, list):
        raise ValidationError("supplemental visual screenshot inventory is missing")
    supplemental_by_id = {
        item.get("id"): item
        for item in supplemental
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    if len(supplemental_by_id) != len(supplemental) or set(supplemental_by_id) != set(SUPPLEMENTAL_SCREENSHOTS):
        raise ValidationError("supplemental visual screenshot inventory differs")
    for screenshot_id, (path, dimensions) in SUPPLEMENTAL_SCREENSHOTS.items():
        payload = dict(supplemental_by_id[screenshot_id])
        payload.pop("id", None)
        review_status = payload.pop("reviewStatus", None)
        if review_status != "unreviewed":
            raise ValidationError(f"{screenshot_id} overstates visual approval")
        validate_asset(repository_root, payload, path, dimensions, screenshot_id)

    motion_evidence = manifest.get("motionEvidence")
    if not isinstance(motion_evidence, dict):
        raise ValidationError("motion evidence inventory is missing")
    if motion_evidence.get("reviewStatus") != "unreviewed":
        raise ValidationError("motion evidence overstates motion approval")
    if motion_evidence.get("capture") != MOTION_CAPTURE:
        raise ValidationError("motion capture metadata differs")
    clips = motion_evidence.get("clips")
    if not isinstance(clips, list):
        raise ValidationError("motion clip inventory is missing")
    clips_by_id = {
        item.get("id"): item
        for item in clips
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    if len(clips_by_id) != len(clips) or set(clips_by_id) != set(MOTION_CLIPS):
        raise ValidationError("motion clip inventory differs")
    for clip_id, specification in MOTION_CLIPS.items():
        validate_motion_asset(repository_root, clips_by_id[clip_id], specification, clip_id)

    expected_png_paths = set(EXPECTED_ANDROID_STORIES.values())
    for story_id in IOS_REFERENCES:
        expected_png_paths.add(f"artifacts/android-parity/normalized-ios/{story_id}-1080x2400.png")
        diff_root = f"artifacts/android-parity/diffs/{story_id}-normalized"
        expected_png_paths.add(f"{diff_root}/phone-{story_id}-dark-diff.png")
        expected_png_paths.add(f"{diff_root}/phone-{story_id}-dark-context-diff.png")
    for specification in ADDITIONAL_CAPTURE_SETS.values():
        expected_png_paths.update(
            specification["pathTemplate"].format(story=story_id)
            for story_id in specification["storyIDs"]
        )
    for specification in STATE_CAPTURE_SETS.values():
        expected_png_paths.update(
            specification["pathTemplate"].format(story=story_id)
            for story_id in specification["storyIDs"]
        )
        expected_png_paths.add(specification["contactSheet"][0])
    for specification in RESILIENCE_CAPTURE_SETS.values():
        expected_png_paths.update(
            specification["pathTemplate"].format(story=story_id)
            for story_id in specification["storyIDs"]
        )
        expected_png_paths.add(specification["contactSheet"][0])
    for specification in WINDOWING_CAPTURE_SETS.values():
        expected_png_paths.update(
            screenshot["path"]
            for screenshot in specification["screenshots"].values()
        )
        contact_sheet = specification.get("contactSheet")
        if contact_sheet is not None:
            expected_png_paths.add(contact_sheet["path"])
    expected_png_paths.add("artifacts/android-parity/goldens/phone/phone-story-contact-sheet.png")
    expected_png_paths.update(path for path, _ in ADDITIONAL_CONTACT_SHEETS.values())
    expected_png_paths.update(path for path, _ in SUPPLEMENTAL_SCREENSHOTS.values())
    evidence_root = repository_root / "artifacts/android-parity"
    actual_png_paths = {
        path.relative_to(repository_root).as_posix()
        for path in evidence_root.rglob("*.png")
    }
    if actual_png_paths != expected_png_paths:
        missing = sorted(expected_png_paths - actual_png_paths)
        unexpected = sorted(actual_png_paths - expected_png_paths)
        raise ValidationError(f"visual PNG inventory differs: missing={missing}, unexpected={unexpected}")
    expected_mp4_paths = {specification["path"] for specification in MOTION_CLIPS.values()}
    motion_root = repository_root / "artifacts/android-parity/motion"
    actual_mp4_paths = {
        path.relative_to(repository_root).as_posix()
        for path in motion_root.rglob("*.mp4")
    }
    if actual_mp4_paths != expected_mp4_paths:
        missing = sorted(expected_mp4_paths - actual_mp4_paths)
        unexpected = sorted(actual_mp4_paths - expected_mp4_paths)
        raise ValidationError(f"motion MP4 inventory differs: missing={missing}, unexpected={unexpected}")
    limitations = manifest.get("limitations")
    if not isinstance(limitations, list) or len(limitations) < 3:
        raise ValidationError("visual evidence limitations are incomplete")
    limitations_text = "\n".join(str(item) for item in limitations).lower()
    for required in (
        "not visual approval",
        "physical-device",
        "argent simulator-server",
        "english fallback",
    ):
        if required not in limitations_text:
            raise ValidationError(f"visual evidence limitation is missing: {required}")


def main(argv: list[str] | None = None) -> int:
    repository_root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        type=Path,
        default=repository_root / "artifacts/android-parity/visual-parity-manifest.json",
    )
    args = parser.parse_args(argv)
    try:
        validate_manifest(args.manifest, repository_root)
    except ValidationError as error:
        print(f"Android visual parity evidence validation failed: {error}", file=sys.stderr)
        return 1
    print(
        "Android visual parity evidence validation passed: 45 deterministic phone/tablet/foldable "
        "captures, 28 recovery/empty/recording/purchase state captures, 28 loading/offline/quota/"
        "interruption/terminal-failure resilience captures, five split-screen/freeform "
        "captures, two onboarding captures, four canonical iOS references, and four unreviewed "
        "diagnostic diffs are hash-bound with a closed PNG inventory; two unreviewed production "
        "motion clips are hash-bound with a closed MP4 inventory."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
