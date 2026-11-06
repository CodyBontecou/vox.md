import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("android_m0_status_validator", ROOT / "scripts/validate-android-wear-m0.py")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)

class AndroidImplementationStatusTests(unittest.TestCase):
    def validate_with(self, status, acceptance_status):
        ledger = json.loads(VALIDATOR.DEFAULT_LEDGER.read_text())
        row = next(item for item in ledger["capabilities"] if item["id"] == "cap.delivery.url")
        row["status"] = status
        for acceptance in row["acceptance"]:
            acceptance["status"] = acceptance_status
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ledger.json"
            path.write_text(json.dumps(ledger))
            return VALIDATOR.validate(path)

    def test_implemented_with_planned_acceptance_is_valid(self):
        self.assertEqual([], self.validate_with("implemented", "planned"))

    def test_implemented_cannot_claim_verified_acceptance(self):
        errors = self.validate_with("implemented", "verified")
        self.assertTrue(any("has verified acceptance but capability status is not verified" in error for error in errors), errors)

    def test_verified_requires_verified_acceptance(self):
        errors = self.validate_with("verified", "planned")
        self.assertTrue(any("status is verified without exclusively verified acceptance" in error for error in errors), errors)
