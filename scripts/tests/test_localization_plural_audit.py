"""The String Catalog audit validates plural variations per CLDR category."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIT = ROOT / "scripts/localization/audit_runtime_catalogs.py"
sys.path.insert(0, str(AUDIT.parent))
import audit_runtime_catalogs as audit  # noqa: E402

KEY = "Keep for %lld days"


def plural_entry() -> dict:
    localizations = {}
    for locale, categories in audit.PLURAL_CATEGORIES.items():
        localizations[locale] = {
            "variations": {
                "plural": {
                    category: {
                        "stringUnit": {
                            "state": "translated",
                            "value": f"{locale}-{category} %lld",
                        }
                    }
                    for category in categories
                }
            }
        }
    return {"localizations": localizations}


class PluralAuditTests(unittest.TestCase):
    def run_audit(self, entry: dict | None) -> list[dict]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in audit.CATALOGS:
                strings = {KEY: entry} if entry is not None and relative == audit.CATALOGS[0] else {}
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"}))
            result = subprocess.run(
                [sys.executable, str(AUDIT), "--root", str(root), "--json"],
                capture_output=True,
                text=True,
            )
            report = json.loads(result.stdout)
            self.assertEqual(result.returncode, 1 if report["errors"] else 0, result.stderr)
            return report["errors"]

    def test_complete_plural_variations_pass(self):
        self.assertEqual(self.run_audit(plural_entry()), [])

    def test_missing_cldr_category_is_rejected(self):
        entry = plural_entry()
        del entry["localizations"]["ru"]["variations"]["plural"]["few"]
        errors = self.run_audit(entry)
        self.assertEqual(
            [(e["kind"], e["locale"], e.get("categories")) for e in errors],
            [("plural-category-missing", "ru", ["few"])],
        )

    def test_unexpected_category_is_rejected(self):
        entry = plural_entry()
        plural = entry["localizations"]["ja"]["variations"]["plural"]
        plural["one"] = copy.deepcopy(plural["other"])
        errors = self.run_audit(entry)
        self.assertEqual(
            [(e["kind"], e["locale"], e.get("categories")) for e in errors],
            [("plural-category-unexpected", "ja", ["one"])],
        )

    def test_each_variant_is_state_and_token_checked(self):
        entry = plural_entry()
        plural = entry["localizations"]["ar"]["variations"]["plural"]
        plural["two"]["stringUnit"]["state"] = "needs_review"
        plural["few"]["stringUnit"]["value"] = "missing the number"
        errors = self.run_audit(entry)
        self.assertEqual(
            sorted((e["kind"], e["locale"], e.get("plural")) for e in errors),
            [("protected-token-mismatch", "ar", "few"), ("state", "ar", "two")],
        )

    def test_mixed_and_argumentless_plurals_are_rejected(self):
        entry = plural_entry()
        entry["localizations"]["de"]["stringUnit"] = {"state": "translated", "value": "%lld Tage"}
        errors = self.run_audit(entry)
        self.assertIn(("mixed-string-unit-and-variations", "de"), [(e["kind"], e["locale"]) for e in errors])

        entry = plural_entry()
        for localization in entry["localizations"].values():
            for unit in localization["variations"]["plural"].values():
                unit["stringUnit"]["value"] = unit["stringUnit"]["value"].replace(" %lld", "")
        errors = [
            e for e in self.run_audit(entry)
            if e["kind"] == "plural-without-integer-argument"
        ]
        # The English "other" form is the audited source; without an integer
        # argument there is nothing to select a category, so every locale fails.
        self.assertEqual(len(errors), len(audit.RUNTIME_LOCALES))

    def test_plain_string_units_are_unchanged(self):
        entry = {
            "localizations": {
                locale: {"stringUnit": {"state": "translated", "value": f"{locale} %lld"}}
                for locale in audit.RUNTIME_LOCALES
            }
        }
        self.assertEqual(self.run_audit(entry), [])

    def test_shipped_catalogs_have_no_errors(self):
        result = subprocess.run([sys.executable, str(AUDIT), "--json"], capture_output=True, text=True)
        self.assertEqual(json.loads(result.stdout)["errors"], [])
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
