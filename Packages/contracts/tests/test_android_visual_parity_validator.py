import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "android_visual_parity",
    ROOT / "apps/android/scripts/validate-visual-parity.py",
)
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class AndroidVisualParityValidatorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.manifest_path = self.root / "artifacts/android-parity/visual-parity-manifest.json"
        self.manifest_path.parent.mkdir(parents=True)
        self.payload = self.valid_payload()
        self.write_manifest()

    def tearDown(self):
        self.temporary.cleanup()

    def fake_png(self, relative_path: str, width: int, height: int) -> dict:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        header = (
            VALIDATOR.PNG_SIGNATURE
            + struct.pack(">I", 13)
            + b"IHDR"
            + struct.pack(">II", width, height)
            + b"\x08\x06\x00\x00\x00"
        )
        path.write_bytes(header + relative_path.encode())
        return {
            "path": relative_path,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "width": width,
            "height": height,
        }

    def fake_mp4(self, specification: dict) -> dict:
        relative_path = specification["path"]
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        header = struct.pack(">I", 24) + b"ftyp" + b"isom" + b"\x00\x00\x02\x00" + b"isomiso2"
        path.write_bytes(header + b"\x00" * (specification["bytes"] - len(header)))
        return {
            **specification,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }

    def valid_payload(self) -> dict:
        stories = []
        for story_id, android_path in VALIDATOR.EXPECTED_ANDROID_STORIES.items():
            story = {
                "id": story_id,
                "android": self.fake_png(android_path, 1080, 2400),
                "iosReference": None,
                "comparison": None,
            }
            ios_path = VALIDATOR.IOS_REFERENCES.get(story_id)
            if ios_path is not None:
                diff_root = f"artifacts/android-parity/diffs/{story_id}-normalized"
                context_path = f"{diff_root}/phone-{story_id}-dark-context-diff.png"
                context = self.fake_png(context_path, 324, 720)
                story["iosReference"] = self.fake_png(ios_path, 1206, 2622)
                story["comparison"] = {
                    "tool": "Argent screenshot-diff",
                    "directComparison": "dimension-mismatch-expected",
                    "normalization": "diagnostic only",
                    "status": "changed",
                    "reviewStatus": "unreviewed",
                    "pixelMismatchPercent": VALIDATOR.PIXEL_MISMATCH_PERCENT[story_id],
                    "normalizedReference": self.fake_png(
                        f"artifacts/android-parity/normalized-ios/{story_id}-1080x2400.png",
                        1080,
                        2400,
                    ),
                    "diff": self.fake_png(
                        f"{diff_root}/phone-{story_id}-dark-diff.png",
                        1080,
                        2400,
                    ),
                    "contextDiff": {"path": context["path"], "sha256": context["sha256"]},
                }
            stories.append(story)
        capture_sets = []
        for capture_set_id, specification in VALIDATOR.ADDITIONAL_CAPTURE_SETS.items():
            width, height = specification["dimensions"]
            capture_sets.append({
                "id": capture_set_id,
                "reviewStatus": "unreviewed",
                "capture": {
                    **specification["capture"],
                    "sourceActivity": "md.vox.android.VisualStoryActivity",
                },
                "screenshots": [
                    {
                        "id": story_id,
                        **self.fake_png(
                            specification["pathTemplate"].format(story=story_id),
                            width,
                            height,
                        ),
                    }
                    for story_id in specification["storyIDs"]
                ],
            })
        contact_sheets = []
        for contact_sheet_id, (path, dimensions) in VALIDATOR.ADDITIONAL_CONTACT_SHEETS.items():
            contact_sheets.append({
                "id": contact_sheet_id,
                **self.fake_png(path, *dimensions),
            })
        supplemental = []
        for screenshot_id, (path, dimensions) in VALIDATOR.SUPPLEMENTAL_SCREENSHOTS.items():
            supplemental.append({
                "id": screenshot_id,
                "reviewStatus": "unreviewed",
                **self.fake_png(path, *dimensions),
            })
        windowing_sets = []
        for capture_set_id, specification in VALIDATOR.WINDOWING_CAPTURE_SETS.items():
            screenshots = []
            for screenshot_id, expected in specification["screenshots"].items():
                screenshots.append({
                    "id": screenshot_id,
                    **{
                        key: value
                        for key, value in expected.items()
                        if key not in {"path", "dimensions"}
                    },
                    **self.fake_png(expected["path"], *expected["dimensions"]),
                })
            capture_set = {
                "id": capture_set_id,
                "reviewStatus": "unreviewed",
                "capture": specification["capture"],
                "screenshots": screenshots,
            }
            contact_sheet = specification.get("contactSheet")
            if contact_sheet is not None:
                capture_set["contactSheet"] = self.fake_png(
                    contact_sheet["path"],
                    *contact_sheet["dimensions"],
                )
            windowing_sets.append(capture_set)
        state_capture_sets = []
        for capture_set_id, specification in VALIDATOR.STATE_CAPTURE_SETS.items():
            width, height = specification["dimensions"]
            contact_path, contact_dimensions = specification["contactSheet"]
            state_capture_sets.append({
                "id": capture_set_id,
                "reviewStatus": "unreviewed",
                "capture": specification["capture"],
                "screenshots": [
                    {
                        "id": story_id,
                        **self.fake_png(
                            specification["pathTemplate"].format(story=story_id),
                            width,
                            height,
                        ),
                    }
                    for story_id in specification["storyIDs"]
                ],
                "contactSheet": self.fake_png(contact_path, *contact_dimensions),
            })
        resilience_capture_sets = []
        for capture_set_id, specification in VALIDATOR.RESILIENCE_CAPTURE_SETS.items():
            width, height = specification["dimensions"]
            contact_path, contact_dimensions = specification["contactSheet"]
            resilience_capture_sets.append({
                "id": capture_set_id,
                "reviewStatus": "unreviewed",
                "capture": specification["capture"],
                "screenshots": [
                    {
                        "id": story_id,
                        **self.fake_png(
                            specification["pathTemplate"].format(story=story_id),
                            width,
                            height,
                        ),
                    }
                    for story_id in specification["storyIDs"]
                ],
                "contactSheet": self.fake_png(contact_path, *contact_dimensions),
            })
        return {
            "schemaVersion": 1,
            "status": "captured-unreviewed",
            "capture": {
                "deviceName": "healthmd_phone_api35",
                "serial": "emulator-5556",
                "apiLevel": 35,
                "resolutionPx": [1080, 2400],
                "appearance": "dark",
                "locale": "en-US",
                "fontScale": 1.0,
                "sourceActivity": "md.vox.android.VisualStoryActivity",
            },
            "stories": stories,
            "stateCaptureSets": state_capture_sets,
            "resilienceCaptureSets": resilience_capture_sets,
            "windowingCaptureSets": windowing_sets,
            "additionalCaptureSets": capture_sets,
            "contactSheet": self.fake_png(
                "artifacts/android-parity/goldens/phone/phone-story-contact-sheet.png",
                1152,
                2472,
            ),
            "additionalContactSheets": contact_sheets,
            "supplementalScreenshots": supplemental,
            "motionEvidence": {
                "reviewStatus": "unreviewed",
                "capture": VALIDATOR.MOTION_CAPTURE,
                "clips": [
                    {
                        "id": clip_id,
                        **self.fake_mp4(specification),
                    }
                    for clip_id, specification in VALIDATOR.MOTION_CLIPS.items()
                ],
            },
            "limitations": [
                "not visual approval",
                "physical-device evidence remains open",
                "Argent simulator-server failed on headless form factors",
                "English fallback phrases remain in Arabic",
            ],
        }

    def write_manifest(self):
        self.manifest_path.write_text(json.dumps(self.payload))

    def validate(self):
        VALIDATOR.validate_manifest(self.manifest_path, self.root)

    def test_exact_unreviewed_evidence_passes(self):
        self.validate()

    def test_changed_screenshot_without_manifest_update_is_rejected(self):
        target = self.root / self.payload["stories"][0]["android"]["path"]
        target.write_bytes(target.read_bytes() + b"changed")
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "SHA-256 differs"):
            self.validate()

    def test_missing_story_is_rejected(self):
        self.payload["stories"].pop()
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "story inventory differs"):
            self.validate()

    def test_missing_additional_capture_set_is_rejected(self):
        self.payload["additionalCaptureSets"].pop()
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "capture-set inventory differs"):
            self.validate()

    def test_missing_windowing_capture_set_is_rejected(self):
        self.payload["windowingCaptureSets"].pop()
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "windowing visual capture-set inventory differs"):
            self.validate()

    def test_missing_state_capture_set_is_rejected(self):
        self.payload["stateCaptureSets"].pop()
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "state visual capture-set inventory differs"):
            self.validate()

    def test_state_capture_hash_drift_is_rejected(self):
        state_capture = self.payload["stateCaptureSets"][0]["screenshots"][0]
        target = self.root / state_capture["path"]
        target.write_bytes(target.read_bytes() + b"changed")
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "SHA-256 differs"):
            self.validate()

    def test_missing_resilience_capture_set_is_rejected(self):
        self.payload["resilienceCaptureSets"].pop()
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "resilience visual capture-set inventory differs"):
            self.validate()

    def test_resilience_capture_hash_drift_is_rejected(self):
        resilience_capture = self.payload["resilienceCaptureSets"][0]["screenshots"][0]
        target = self.root / resilience_capture["path"]
        target.write_bytes(target.read_bytes() + b"changed")
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "SHA-256 differs"):
            self.validate()

    def test_missing_motion_clip_is_rejected(self):
        self.payload["motionEvidence"]["clips"].pop()
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "motion clip inventory differs"):
            self.validate()

    def test_motion_clip_hash_drift_is_rejected(self):
        motion_clip = self.payload["motionEvidence"]["clips"][0]
        target = self.root / motion_clip["path"]
        content = bytearray(target.read_bytes())
        content[-1] ^= 1
        target.write_bytes(content)
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "SHA-256 differs"):
            self.validate()

    def test_motion_approval_cannot_be_claimed_by_manifest_only(self):
        self.payload["motionEvidence"]["reviewStatus"] = "approved"
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "overstates motion approval"):
            self.validate()

    def test_windowing_task_bounds_drift_is_rejected(self):
        freeform = next(
            item for item in self.payload["windowingCaptureSets"]
            if item["id"] == "tablet-dark-freeform-en"
        )
        freeform["screenshots"][0]["appTaskBoundsPx"] = [0, 0, 2560, 1600]
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "metadata differs for appTaskBoundsPx"):
            self.validate()

    def test_approval_cannot_be_claimed_by_manifest_only(self):
        self.payload["status"] = "approved"
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "captured-unreviewed"):
            self.validate()

    def test_declared_dimension_drift_is_rejected(self):
        self.payload["stories"][0]["android"]["height"] = 2399
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "dimensions differ"):
            self.validate()

    def test_iOS_comparison_cannot_be_added_without_a_reference(self):
        story = next(item for item in self.payload["stories"] if item["id"] == "02-history")
        story["comparison"] = copy.deepcopy(self.payload["stories"][0]["comparison"])
        self.write_manifest()
        with self.assertRaisesRegex(VALIDATOR.ValidationError, "invents an unavailable"):
            self.validate()


if __name__ == "__main__":
    unittest.main()
