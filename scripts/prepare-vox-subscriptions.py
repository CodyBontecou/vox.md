#!/usr/bin/env python3
"""Authorized subscription-only preparation; never changes lifetime IAPs or releases apps.

Default is offline plan generation. Explicit --fetch / --metadata / --apply-prices /
--apply-offers switches select stages. Receipts are cached; uncertain writes stop.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
from datetime import datetime, timezone
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/evidence/subscription-transition-20261029"
PRIOR = ROOT / "docs/evidence/hard-paywall-regional-proposal-20261029"
GROUP = "22526843"
PRODUCTS = {
    "individual-weekly": ("6828566827", "bontecou.Voxboard.individual.weekly", "0.99", "Individual Weekly"),
    "individual-yearly": ("6828566769", "bontecou.Voxboard.individual.yearly", "29.99", "Individual Yearly"),
    "family-weekly": ("6828566714", "bontecou.Voxboard.family.weekly", "1.99", "Family Weekly"),
    "family-yearly": ("6828566853", "bontecou.Voxboard.family.yearly", "49.99", "Family Yearly"),
}
spec = importlib.util.spec_from_file_location("regional_policy", ROOT / "scripts/plan-hard-paywall-regional-pricing.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
LOCK = threading.Lock()


def run(name, args, refresh=False):
    """Only subscription CLI mutations; raw API is restricted to GET."""
    assert args[0] in ("subscriptions", "api", "validate")
    if args[0] == "api":
        if args[1] == "POST":
            assert args[2] == "/v1/subscriptionPlanAvailabilities"
            body = json.loads(Path(args[args.index("--body-file") + 1]).read_text())["data"]
            assert body["type"] == "subscriptionPlanAvailabilities"
            assert body["relationships"]["subscription"]["data"]["id"] in [v[0] for v in PRODUCTS.values()]
            assert body["attributes"] == {"planType": "UPFRONT", "availableInNewTerritories": False}
            assert {v["id"] for v in body["relationships"]["availableTerritories"]["data"]} == set(territories())
        else:
            assert args[1] == "GET" and args[2].startswith(("/v1/subscriptions/", "/v1/subscriptionPricePoints/", "/v1/subscriptionPlanAvailabilities/"))
    if args[0] == "subscriptions":
        ids = [v[0] for v in PRODUCTS.values()]
        for flag in ("--subscription-id", "--id"):
            if flag in args:
                assert args[args.index(flag) + 1] in ids
        if "--group-id" in args:
            assert args[args.index("--group-id") + 1] == GROUP
    path = OUT / (name + ".json")
    if path.exists() and not refresh:
        return json.loads(path.read_text())
    record = {"time": datetime.now(timezone.utc).isoformat(), "command": ["asc", *args], "receipt": path.name}
    # Record before executing, so interruption does not hide an uncertain mutation.
    with LOCK:
        with (OUT / "commands.jsonl").open("a") as f:
            f.write(json.dumps(record) + "\n")
    result = subprocess.run(["asc", *args], capture_output=True, text=True, timeout=1200)
    if result.returncode:
        (OUT / (name + ".error.txt")).write_text(result.stderr + "\n" + result.stdout)
        raise RuntimeError(f"Command failed; reconcile receipt/state before retry: {name}: {result.stderr[:600]}")
    parsed = json.loads(result.stdout) if result.stdout.strip() else {}
    policy.save(path, parsed)
    return parsed


def territories():
    return sorted(policy.current_prices(OUT / "lifetime-freeze", "6761033996")[0])


def fetch():
    codes = territories()
    rules = policy.policy(PRIOR, codes)
    def product_job(item):
        key, (sid, _, base, _) = item
        us = run(key + "-USA-points", ["api", "GET", f"/v1/subscriptions/{sid}/pricePoints", "--query", "filter[territory]=USA", "--query", "filter[planType]=UPFRONT", "--query", "fields[subscriptionPricePoints]=customerPrice,territory", "--query", "include=territory", "--query", "limit=200", "--paginate"])
        for tier in sorted({r["reference_tier_usd"] for r in rules.values()}, key=Decimal):
            point = policy.nearest(us["data"], Decimal(base) * Decimal(tier) / Decimal("19.99"))
            run(f"{key}-tier-{tier}-equalizations", ["api", "GET", f"/v1/subscriptionPricePoints/{point['id']}/equalizations", "--query", f"filter[subscription]={sid}", "--query", "filter[planType]=UPFRONT", "--query", "include=territory", "--query", "limit=200", "--paginate"])
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(product_job, PRODUCTS.items()))


def plan():
    rules = policy.policy(PRIOR, territories())
    overrides_path = OUT / "parity-overrides.json"
    overrides = json.loads(overrides_path.read_text()) if overrides_path.exists() else {}
    rows = []
    for key, (sid, product_id, base, _) in PRODUCTS.items():
        us = json.loads((OUT / f"{key}-USA-points.json").read_text())["data"]
        minimum = min(Decimal(p["attributes"]["customerPrice"]) for p in us if Decimal(p["attributes"]["customerPrice"]) > 0)
        product_rows = []
        for code, rule in rules.items():
            target = Decimal(base) * Decimal(rule["reference_tier_usd"]) / Decimal("19.99")
            point = policy.nearest(us, target)
            if code == "USA":
                assert Decimal(point["attributes"]["customerPrice"]) == Decimal(base)
                local = point
                currency = "USD"
            else:
                payload = json.loads((OUT / f"{key}-tier-{rule['reference_tier_usd']}-equalizations.json").read_text())
                local = next(p for p in payload["data"] if policy.point_territory(p) == code)
                currencies = {p["id"]: p["attributes"]["currency"] for p in payload.get("included", []) if p["type"] == "territories"}
                currency = currencies[code]
            override = overrides.get(key + ":" + code)
            if override:
                candidates = json.loads((OUT / override["evidence"]).read_text())["data"]
                local = next(p for p in candidates if p["id"] == override["price_point_id"])
                assert Decimal(local["attributes"]["customerPrice"]) == Decimal(override["price"])
            decoded = policy.decode_point(local["id"])
            assert decoded["s"] == sid and decoded["t"] == code
            price = Decimal(local["attributes"]["customerPrice"])
            assert price > 0
            product_rows.append({"territory": code, "price": str(price), "currency_code": currency,
                                 "price_point_id": local["id"], "preserved": "false"})
            rows.append({"plan": key, "subscription_id": sid, "product_id": product_id, "territory": code,
                         "currency": currency, "reference_tier_usd": rule["reference_tier_usd"],
                         "usd_policy_target": str(target), "usd_selected_price": point["attributes"]["customerPrice"],
                         "usd_minimum": str(minimum), "local_price": str(price), "price_point_id": local["id"],
                         "parity_original_local_price": override["before_price"] if override else "",
                         "parity_evidence": override["evidence"] if override else "",
                         "flags": ";".join(filter(None, ["USD_POLICY_TARGET_CLAMPED_TO_SUBSCRIPTION_FLOOR" if target < minimum else "",
                                                            "LOCAL_FAMILY_PREMIUM_COLLISION_CORRECTED" if override else ""]))})
        policy.csv_write(OUT / (key + "-prices.csv"), product_rows)
    policy.csv_write(OUT / "subscription-regional-prices.csv", rows)
    policy.csv_write(OUT / "introductory-offers.csv", [{"territory": t} for t in territories()])
    policy.save(OUT / "pricing-plan-summary.json", {"subscription_rows": len(rows), "territories": len(territories()),
                 "floor_clamped_rows": sum("USD_POLICY_TARGET_CLAMPED_TO_SUBSCRIPTION_FLOOR" in r["flags"] for r in rows),
                 "family_premium_collision_overrides": len(overrides), "lifetime_price_mutations": 0})


def metadata():
    for key, (sid, _, _, title) in PRODUCTS.items():
        versions = run(key + "-versions-before", ["subscriptions", "versions", "list", "--subscription-id", sid])
        version = versions["data"][0] if versions["data"] else run(key + "-version-create", ["subscriptions", "versions", "create", "--subscription-id", sid])["data"]
        run(key + "-en-US", ["subscriptions", "versions", "localizations", "create", "--version-id", version["id"], "--locale", "en-US", "--name", title,
                            "--description", "Unlimited Capture and on-device transcription." if key.startswith("individual") else "Unlimited Capture and transcription for your family."])
        run(key + "-review-note", ["subscriptions", "update", "--id", sid, "--review-note",
            "Seven-day introductory free trial for eligible accounts, then auto-renews at the displayed localized price. Individual is for one Apple Account; Family supports Apple Family Sharing. Existing lifetime purchases remain valid. Unpaid users may view/export existing history but cannot create new recordings or Capture deliveries. First subscriptions will be reviewed with the updated iOS and macOS paywall builds; existing lifetime prices remain unchanged. No release before owner approval."])


def apply_prices():
    # New subscriptions only. No API or CLI route here can mutate an IAP schedule.
    for key, (sid, _, base, _) in PRODUCTS.items():
        run(key + "-prices-dry-run", ["subscriptions", "pricing", "prices", "import", "--subscription-id", sid, "--input", str(OUT / (key + "-prices.csv")), "--dry-run", "--continue-on-error=false"])
        run(key + "-initial-us-price", ["subscriptions", "pricing", "prices", "set", "--subscription-id", sid, "--price", base, "--territory", "USA"])
        availability = OUT / (key + "-availability-request.json")
        policy.save(availability, {"data": {"type": "subscriptionPlanAvailabilities",
            "attributes": {"planType": "UPFRONT", "availableInNewTerritories": False},
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories()]}}}})
        run(key + "-availability", ["api", "POST", "/v1/subscriptionPlanAvailabilities", "--body-file", str(availability), "--confirm"])
        run(key + "-regional-prices-applied", ["subscriptions", "pricing", "prices", "import", "--subscription-id", sid, "--input", str(OUT / (key + "-prices.csv")), "--confirm", "--continue-on-error=false"])
        run(key + "-prices-readback", ["api", "GET", f"/v1/subscriptions/{sid}/prices", "--query", "include=subscriptionPricePoint,territory", "--query", "limit=200", "--paginate"], refresh=True)


def offers_snapshot(key, sid, suffix):
    return run(key + suffix, ["api", "GET", f"/v1/subscriptions/{sid}/introductoryOffers",
        "--query", "include=territory", "--query", "limit=200", "--paginate"], refresh=True)


def apply_offers():
    # Reconcile partial imports first; never create a second trial for a territory.
    # One paced writer avoids the observed Apple 429 limit on concurrent imports.
    for key, (sid, _, _, _) in PRODUCTS.items():
        payload = offers_snapshot(key, sid, "-offers-resume-before")
        existing = {r["relationships"]["territory"]["data"]["id"] for r in payload["data"]}
        for code in territories():
            if code in existing:
                continue
            for attempt in range(3):
                try:
                    run(key + "-trial-" + code, ["subscriptions", "offers", "introductory", "create", "--subscription-id", sid,
                        "--territory", code, "--offer-duration", "ONE_WEEK", "--offer-mode", "FREE_TRIAL", "--number-of-periods", "1"])
                    break
                except RuntimeError:
                    if attempt == 2:
                        raise
                    time.sleep(60)
                    current = offers_snapshot(key, sid, "-offers-reconcile-" + code)
                    if any(r["relationships"]["territory"]["data"]["id"] == code for r in current["data"]):
                        break
            time.sleep(1)
        final = offers_snapshot(key, sid, "-offers-readback")
        codes = {r["relationships"]["territory"]["data"]["id"] for r in final["data"]}
        assert codes == set(territories()) and len(final["data"]) == len(codes)
        policy.save(OUT / (key + "-offers-applied.json"), {"subscription_id": sid, "verified_offers": len(codes), "reconciled_partial_import": True})


def verify():
    results = []
    for key, (sid, product_id, _, _) in PRODUCTS.items():
        payload = run(key + "-prices-verified", ["api", "GET", f"/v1/subscriptions/{sid}/prices", "--query", "include=subscriptionPricePoint,territory", "--query", "limit=200", "--paginate"], refresh=True)
        with (OUT / (key + "-prices.csv")).open() as handle:
            expected = {r["territory"]: r for r in csv.DictReader(handle)}
        included = {(r["type"], r["id"]): r for r in payload.get("included", [])}
        seen = {}
        for row in payload["data"]:
            assert row["attributes"]["planType"] == "UPFRONT"
            ref = row["relationships"]["subscriptionPricePoint"]["data"]
            point = included[(ref["type"], ref["id"])]
            code = row["relationships"]["territory"]["data"]["id"]
            assert code not in seen
            assert point["id"] == expected[code]["price_point_id"]
            assert Decimal(point["attributes"]["customerPrice"]) == Decimal(expected[code]["price"])
            seen[code] = point["id"]
        assert set(seen) == set(territories())
        offers = offers_snapshot(key, sid, "-offers-verified")
        offer_codes = set()
        for row in offers["data"]:
            attrs = row["attributes"]
            assert attrs["offerMode"] == "FREE_TRIAL" and attrs["duration"] == "ONE_WEEK" and attrs["numberOfPeriods"] == 1, attrs
            assert attrs["targetSubscriptionPlanType"] == "UPFRONT", attrs
            offer_codes.add(row["relationships"]["territory"]["data"]["id"])
        assert offer_codes == set(territories()) and len(offers["data"]) == 175
        availability = json.loads((OUT / (key + "-availability.json")).read_text())["data"]
        available = run(key + "-available-territories-verified", ["api", "GET", f"/v1/subscriptionPlanAvailabilities/{availability['id']}/availableTerritories", "--paginate"], refresh=True)
        assert {r["id"] for r in available["data"]} == set(territories())
        product = run(key + "-product-verified", ["api", "GET", f"/v1/subscriptions/{sid}"], refresh=True)["data"]
        attrs = product["attributes"]
        assert attrs["productId"] == product_id
        assert bool(attrs.get("familySharable", False)) == key.startswith("family")
        assert attrs["groupLevel"] == (1 if key.startswith("family") else 2)
        results.append({"subscription_id": sid, "product_id": product_id, "prices": len(seen), "trials": len(offer_codes), "availability": len(available["data"]), "state": attrs["state"]})
    freeze = OUT / "lifetime-freeze"
    for iid, _, _ in list(policy.PRODUCTS.values())[:3]:
        for kind in ("manualPrices", "automaticPrices"):
            policy.get(freeze, f"{iid}-{kind}-after-subscriptions", f"/v1/inAppPurchasePriceSchedules/{iid}/{kind}", (("include", "inAppPurchasePricePoint,territory"), ("limit", "200")), refresh=True)
        assert policy.current_prices(freeze, iid) == policy.current_prices(freeze, iid, "-after-subscriptions"), f"LIFETIME PRICE DRIFT: {iid}"
    policy.save(OUT / "verification.json", {"verified_at": datetime.now(timezone.utc).isoformat(),
                 "subscriptions": results, "verified_subscription_prices": 700, "verified_trial_offers": 700,
                 "existing_lifetime_prices_unchanged": True, "existing_lifetime_price_records_verified": 525})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ("fetch", "metadata", "apply-prices", "apply-offers", "verify"):
        parser.add_argument("--" + flag, action="store_true")
    args = parser.parse_args()
    if args.metadata:
        metadata()
    if args.fetch:
        fetch()
    if args.fetch or not any(vars(args).values()):
        plan()
    if args.apply_prices:
        apply_prices()
    if args.apply_offers:
        apply_offers()
    if args.verify:
        verify()


if __name__ == "__main__":
    main()
