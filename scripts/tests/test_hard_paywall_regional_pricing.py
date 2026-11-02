"""Offline policy, safety and evidence checks for the read-only proposal."""
import csv
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "plan-hard-paywall-regional-pricing.py"
spec = importlib.util.spec_from_file_location("regional_proposal", SCRIPT)
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)


class PolicyTests(unittest.TestCase):
    def test_nearest_excludes_free_and_breaks_ties_downward(self):
        points = [{"id": str(n), "attributes": {"customerPrice": price}}
                  for n, price in enumerate(["0.00", "0.29", "0.49"])]
        self.assertEqual(planner.nearest(points, Decimal("0.01"))["attributes"]["customerPrice"], "0.29")
        self.assertEqual(planner.nearest(points, Decimal("0.39"))["attributes"]["customerPrice"], "0.29")

    def test_frozen_policy_reproduces_previous_reference_tiers(self):
        expected = {"USA": "19.99", "IND": "6.99", "BRA": "9.99", "GBR": "17.99",
                    "JPN": "14.99", "CHN": "9.99", "NGA": "6.99", "EGY": "9.99",
                    "PAK": "4.99", "UKR": "9.99", "XKS": "9.99"}
        rules = planner.policy(planner.DEFAULT_OUT, expected)
        self.assertEqual({k: v["reference_tier_usd"] for k, v in rules.items()}, expected)

    def test_fetch_wrapper_can_only_construct_get(self):
        with tempfile.TemporaryDirectory() as directory:
            result = type("Result", (), {"returncode": 0, "stdout": '{"data":[],"links":{}}', "stderr": ""})()
            with patch.object(planner.subprocess, "run", return_value=result) as run:
                planner.get(Path(directory), "sample", "/v1/territories")
            command = run.call_args.args[0]
            self.assertEqual(command[:3], ["asc", "api", "GET"])
            self.assertNotIn("--confirm", command)
            self.assertNotIn("--body", command)
            self.assertNotIn("--body-file", command)


class SavedProposalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = planner.DEFAULT_OUT
        path = cls.out / "all-plans-before-after.csv"
        if not path.exists():
            raise unittest.SkipTest("Fetch/build the proposal before validating saved evidence")
        with path.open() as handle:
            cls.rows = list(csv.DictReader(handle))

    def test_all_seven_options_have_same_territory_coverage(self):
        sets = [{r["territory"] for r in self.rows if r["plan"] == plan} for plan in planner.PRODUCTS]
        self.assertGreaterEqual(len(sets[0]), 175)
        self.assertTrue(all(s == sets[0] for s in sets))
        self.assertEqual(len(self.rows), len(sets[0]) * 7)

    def test_iap_points_are_product_and_territory_specific(self):
        for row in self.rows:
            if row["asc_product_id"]:
                decoded = planner.decode_point(row["proposed_point_id"])
                self.assertEqual(decoded["s"], row["asc_product_id"])
                self.assertEqual(decoded["t"], row["territory"])
                self.assertGreater(Decimal(row["proposed_local_price"]), 0)
                self.assertTrue(row["before_point_id"])
                for reference in row["verification_evidence"].split(";"):
                    points = json.loads((self.out / reference).read_text())["data"]
                    if any(p["id"] == row["proposed_point_id"] and
                           Decimal(p["attributes"]["customerPrice"]) == Decimal(row["proposed_local_price"])
                           for p in points):
                        break
                else:
                    self.fail(f"No raw point evidence for {row['plan']}/{row['territory']}")

    def test_missing_subscriptions_never_claim_resolved_local_prices(self):
        for row in self.rows:
            if not row["asc_product_id"]:
                self.assertEqual(row["status"], "BLOCKED_MISSING_SUBSCRIPTION")
                self.assertEqual(row["before_status"], "NOT_CREATED_NOT_SOLD")
                for key in ("proposed_point_id", "proposed_local_price", "before_local_price"):
                    self.assertEqual(row[key], "")
                self.assertIn("LOCAL_MINIMUM_UNVERIFIED", row["flags"])

    def test_us_prices_and_upgrade_eligibility_catalog_target(self):
        for row in self.rows:
            if row["territory"] == "USA" and row["asc_product_id"]:
                self.assertEqual(Decimal(row["proposed_local_price"]), planner.PRODUCTS[row["plan"]][2])

    def test_upgrade_is_nearest_valid_local_gap_with_us_exception(self):
        for row in self.rows:
            if row["plan"] == "family_lifetime_upgrade":
                points = json.loads((self.out / row["verification_evidence"]).read_text())["data"]
                target = Decimal("39.99") if row["territory"] == "USA" else Decimal(row["local_target_gap"])
                self.assertEqual(planner.nearest(points, target)["id"], row["proposed_point_id"])

    def test_all_raw_collections_are_fully_paginated(self):
        for path in (self.out / "raw").glob("*.json"):
            payload = json.loads(path.read_text())
            self.assertFalse(payload.get("links", {}).get("next"), path.name)
            total = payload.get("meta", {}).get("paging", {}).get("total")
            if isinstance(payload.get("data"), list) and total is not None:
                self.assertEqual(len(payload["data"]), total, path.name)

    def test_rounding_and_minimum_warnings_are_preserved(self):
        self.assertEqual(sum("UPGRADE_PATH_ROUNDING_DIFFERENCE" in r["flags"] for r in self.rows), 41)
        self.assertEqual(sum("USD_BENCHMARK_BELOW_REFERENCE_IAP_FLOOR_NOT_SUBSCRIPTION_VALIDATION" in r["flags"] for r in self.rows), 35)
        # A reference-IAP floor warning must never assert a subscription floor.
        for row in self.rows:
            if not row["asc_product_id"]:
                self.assertEqual(row["minimum_positive_local_price"], "")
                self.assertEqual(row["minimum_positive_us_benchmark"], "")

    def test_live_price_snapshots_are_unchanged(self):
        for iid, _, _ in list(planner.PRODUCTS.values())[:3]:
            self.assertEqual(planner.current_prices(self.out, iid),
                             planner.current_prices(self.out, iid, "-after-readonly"))

    def test_audit_contains_only_get_requests(self):
        for line in (self.out / "get-audit.jsonl").read_text().splitlines():
            command = json.loads(line)["command"]
            self.assertEqual(command[:3], ["asc", "api", "GET"])
            self.assertNotIn("--confirm", command)

    def test_manifest_matches_saved_evidence(self):
        manifest = json.loads((self.out / "sha256-manifest.json").read_text())
        for name, expected in manifest.items():
            self.assertEqual(planner.digest(self.out / name), expected, name)


if __name__ == "__main__":
    unittest.main()
