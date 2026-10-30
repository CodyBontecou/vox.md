import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("subscription_prep", ROOT / "scripts/prepare-vox-subscriptions.py")
prep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prep)


class SubscriptionTransitionTests(unittest.TestCase):
    def test_mutator_rejects_existing_lifetime_ids(self):
        with patch.object(prep.subprocess, "run") as run:
            for iid in ("6761033996", "6796785976", "6796786086"):
                with self.assertRaises(AssertionError):
                    prep.run("forbidden", ["subscriptions", "update", "--id", iid])
            with self.assertRaises(AssertionError):
                prep.run("forbidden", ["iap", "pricing", "schedules", "create"])
            with self.assertRaises(AssertionError):
                prep.run("forbidden", ["api", "PATCH", "/v1/inAppPurchasePriceSchedules/6761033996"])
            run.assert_not_called()

    def test_seven_hundred_points_belong_to_new_subscription_products(self):
        import csv
        with (prep.OUT / "subscription-regional-prices.csv").open() as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(len(rows), 700)
        for key, (sid, _, base, _) in prep.PRODUCTS.items():
            selected = [r for r in rows if r["plan"] == key]
            self.assertEqual(len(selected), 175)
            for row in selected:
                point = prep.policy.decode_point(row["price_point_id"])
                self.assertEqual(point["s"], sid)
                self.assertEqual(point["t"], row["territory"])
                self.assertGreater(float(row["local_price"]), 0)
            us = next(r for r in selected if r["territory"] == "USA")
            self.assertEqual(float(us["local_price"]), float(base))
        self.assertEqual(sum("USD_POLICY_TARGET_CLAMPED_TO_SUBSCRIPTION_FLOOR" in r["flags"] for r in rows), 35)
        self.assertEqual(sum("LOCAL_FAMILY_PREMIUM_COLLISION_CORRECTED" in r["flags"] for r in rows), 6)
        indexed = {(r["plan"], r["territory"]): r for r in rows}
        for territory in {r["territory"] for r in rows}:
            for period in ("weekly", "yearly"):
                self.assertGreater(float(indexed[("family-" + period, territory)]["local_price"]),
                                   float(indexed[("individual-" + period, territory)]["local_price"]))

    def test_unpaid_gate_has_history_route_but_not_capture_retry(self):
        ios = (ROOT / "Voxboard/Views/PaywallView.swift").read_text()
        history = (ROOT / "Voxboard/Views/HistoryView.swift").read_text()
        mac = (ROOT / "Voxboard Mac/MacRootView.swift").read_text()
        self.assertIn('accessibilityIdentifier("paywall.existingHistory")', ios)
        self.assertIn("HistoryView(viewModel: historyViewModel, isReadOnly: true)", ios)
        self.assertIn("if !isReadOnly && viewModel.failedInboxCount > 0", history)
        self.assertIn('Button("Export", systemImage: "square.and.arrow.up")', history)
        self.assertIn("MacHistoryView(viewModel: historyViewModel, isReadOnly: true)", mac)
        self.assertIn("if !isReadOnly && viewModel.failedInboxCount > 0", mac)
        self.assertIn("exportExistingTranscript", mac)
        for path in ("Voxboard/VoxboardApp.swift", "Voxboard Mac/VoxboardMacApp.swift"):
            self.assertIn("historyViewModel: quickCaptureViewModel", (ROOT / path).read_text())

    def test_listing_proposals_are_bounded_truthful_and_unapproved(self):
        drafts = json.loads((prep.OUT / "listing-copy-proposed.json").read_text())
        self.assertEqual(len(drafts), 78)
        for platform in ("ios", "mac"):
            self.assertEqual(len([r for r in drafts if r["platform"] == platform]), 39)
        for row in drafts:
            self.assertEqual(row["approval_status"], "AWAITING_OWNER_APPROVAL_NOT_UPLOADED")
            self.assertLessEqual(len(row["description"]), 4000)
            self.assertLessEqual(len(row["whatsNew"]), 4000)
            self.assertIn("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/", row["description"])
            if row["locale"].startswith("en"):
                self.assertNotIn("15 minutes", row["description"])
                self.assertNotIn("no recurring subscription", row["description"].lower())
                self.assertIn("Viewing and exporting existing history require no new purchase", row["description"])


if __name__ == "__main__":
    unittest.main()
