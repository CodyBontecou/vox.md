#!/usr/bin/env python3
"""Read-only ASC pricing proposal. This program can issue GET requests only.

Inputs: frozen purchasing-power inputs from the approved October 25 policy.
Outputs: proposed tables and raw GET evidence; never mutation request bodies.
Missing subscription products intentionally remain unresolved.
"""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import csv
from datetime import date, datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
import hashlib
import json
from pathlib import Path
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "docs/evidence/hard-paywall-regional-proposal-20261029"
APP = "6758967337"
TIERS = tuple(map(Decimal, ("4.99", "6.99", "7.99", "9.99", "12.99", "14.99", "17.99", "19.99")))
PRODUCTS = {
    "individual_lifetime": ("6761033996", "bontecou.Voxboard.unlock", Decimal("49.99")),
    "family_lifetime": ("6796785976", "bontecou.Voxboard.family", Decimal("89.99")),
    "family_lifetime_upgrade": ("6796786086", "bontecou.Voxboard.familyUpgrade", Decimal("39.99")),
    "individual_weekly": (None, "bontecou.Voxboard.individual.weekly", Decimal("0.99")),
    "individual_yearly": (None, "bontecou.Voxboard.individual.yearly", Decimal("29.99")),
    "family_weekly": (None, "bontecou.Voxboard.family.weekly", Decimal("1.99")),
    "family_yearly": (None, "bontecou.Voxboard.family.yearly", Decimal("49.99")),
}
LOCK = threading.Lock()


def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def utc():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def get(out, name, path, query=(), refresh=False):
    """No caller can supply a method, executable, or mutation flags."""
    assert path.startswith(("/v1/", "/v2/")) and "?" not in path
    destination = out / "raw" / f"{name}.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = ["asc", "api", "GET", path]
    if not path.endswith("/iapPriceSchedule"):
        command.append("--paginate")
    for key, value in query:
        command += ["--query", f"{key}={value}"]
    started = utc()
    cached = destination.exists() and not refresh
    if not cached:
        for attempt in range(3):
            result = subprocess.run(command, capture_output=True, text=True, timeout=240)
            if result.returncode == 0:
                parsed = json.loads(result.stdout)
                assert "data" in parsed and not parsed.get("errors"), (path, parsed)
                destination.write_text(result.stdout)
                break
            if attempt == 2:
                save(out / "errors" / f"{name}.json", {"command": command, "stderr": result.stderr})
                raise RuntimeError(f"GET failed: {path}: {result.stderr[:500]}")
            time.sleep(2 ** (attempt + 1))
    parsed = load(destination)
    assert "data" in parsed and not parsed.get("errors"), destination
    assert not parsed.get("links", {}).get("next"), f"Incomplete pagination: {destination}"
    total = parsed.get("meta", {}).get("paging", {}).get("total")
    if isinstance(parsed["data"], list) and total is not None:
        assert len(parsed["data"]) == total, f"Incomplete resource count: {destination}"
    record = {"command": command, "started_at": started, "finished_at": utc(),
              "cached": cached, "file": str(destination.relative_to(out)),
              "sha256": digest(destination), "resource_count": len(parsed["data"]) if isinstance(parsed["data"], list) else 1}
    with LOCK:
        with (out / "get-audit.jsonl").open("a") as handle:
            handle.write(json.dumps(record, sort_keys=True) + "\n")
    return parsed


def point_territory(point):
    relation = point.get("relationships", {}).get("territory", {}).get("data")
    if relation:
        return relation["id"]
    return decode_point(point["id"])["t"]


def decode_point(identifier):
    return json.loads(base64.b64decode(identifier + "=" * (-len(identifier) % 4)))


def nearest(points, target):
    paid = [p for p in points if Decimal(p["attributes"]["customerPrice"]) > 0]
    assert paid, "Missing paid price points"
    return min(paid, key=lambda p: (abs(Decimal(p["attributes"]["customerPrice"]) - target), Decimal(p["attributes"]["customerPrice"]), p["id"]))


def policy(out, territories):
    latest = {}
    for row in load(out / "worldbank-gni-ppp.json")[1]:
        code = row["countryiso3code"]
        if row["value"] is not None and (code not in latest or row["date"] > latest[code]["date"]):
            latest[code] = row
    countries = {r["id"]: r for r in load(out / "worldbank-countries.json")[1]}
    result = {}
    for code in territories:
        wb = {"XKS": "XKX"}.get(code, code)
        country, datum = countries.get(wb, {}), latest.get(wb)
        if datum and int(datum["date"]) >= 2023:
            # Same reference baseline, clamp, tiers and tie-break as October 25.
            raw = Decimal("19.99") * (Decimal(str(datum["value"])) / Decimal(str(latest["USA"]["value"]))).sqrt()
            target = max(Decimal("4.99"), min(Decimal("19.99"), raw))
            tier = min(TIERS, key=lambda p: (abs(p - target), p))
            basis = "World Bank GNI per capita PPP; square-root scaling vs US"
        else:
            group = country.get("incomeLevel", {}).get("id")
            tier = {"LIC": Decimal("4.99"), "LMC": Decimal("6.99"), "UMC": Decimal("9.99")}.get(group, Decimal("19.99"))
            basis = f"Income-group fallback ({group})" if group else "No comparable data; full US benchmark equalization"
        if code == "USA":
            tier, basis = Decimal("19.99"), "Owner-approved US price"
        result[code] = {"territory": code, "country": country.get("name", code),
                        "reference_tier_usd": str(tier), "multiplier": str(tier / Decimal("19.99")),
                        "gni_ppp": datum["value"] if datum else "", "data_year": datum["date"] if datum else "", "basis": basis}
    return result


def catalog(out, iid, territory):
    return get(out, f"{iid}-{territory}-points", f"/v2/inAppPurchases/{iid}/pricePoints", (
        ("filter[territory]", territory), ("limit", "200"),
        ("fields[inAppPurchasePricePoints]", "customerPrice,territory"), ("include", "territory")))


def snapshot(out, suffix="", refresh=False):
    groups = get(out, "subscription-groups" + suffix, f"/v1/apps/{APP}/subscriptionGroups", refresh=refresh)
    assert not groups["data"], "Subscriptions now exist: stop and add product-specific subscription resolution"
    get(out, "iap-products" + suffix, f"/v1/apps/{APP}/inAppPurchasesV2", refresh=refresh)
    for iid, _, _ in list(PRODUCTS.values())[:3]:
        schedule = get(out, f"{iid}-schedule{suffix}", f"/v2/inAppPurchases/{iid}/iapPriceSchedule", refresh=refresh)
        sid = schedule["data"]["id"]
        for kind in ("manualPrices", "automaticPrices"):
            get(out, f"{iid}-{kind}{suffix}", f"/v1/inAppPurchasePriceSchedules/{sid}/{kind}", (
                ("include", "inAppPurchasePricePoint,territory"), ("limit", "200")), refresh=refresh)


def current_prices(out, iid, suffix=""):
    result, scheduled = {}, []
    today = date.today().isoformat()
    for kind in ("automaticPrices", "manualPrices"):
        payload = load(out / "raw" / f"{iid}-{kind}{suffix}.json")
        included = {(r["type"], r["id"]): r for r in payload.get("included", [])}
        for row in payload["data"]:
            attrs, rel = row["attributes"], row["relationships"]
            point_ref = rel["inAppPurchasePricePoint"]["data"]
            point = included[(point_ref["type"], point_ref["id"])]
            code = rel["territory"]["data"]["id"]
            currency = included[("territories", code)]["attributes"]["currency"]
            assert decode_point(point["id"])["s"] == iid
            item = {"territory": code, "currency": currency, "price": point["attributes"]["customerPrice"],
                    "point_id": point["id"], "manual": attrs["manual"],
                    "start_date": attrs.get("startDate"), "end_date": attrs.get("endDate")}
            if (attrs.get("startDate") or "0000") > today:
                scheduled.append(item)
                continue
            if attrs.get("endDate") and attrs["endDate"] <= today:
                continue
            if code in result and result[code]["manual"] == item["manual"]:
                raise AssertionError(f"Ambiguous current price: {iid}/{code}")
            result[code] = item
    return result, scheduled


def fetch(out, workers):
    snapshot(out)
    territories = sorted(current_prices(out, "6761033996")[0])
    rules = policy(out, territories)
    assert len(territories) >= 175
    get(out, "territories", "/v1/territories")
    # Subscription list API requires a subscription ID. Save exact schema evidence.
    for query, name in (("GET /v1/subscriptions/{id}/pricePoints", "subscription-price-list-schema"),
                        ("GET /v2/inAppPurchases/{id}/pricePoints", "iap-price-list-schema")):
        result = subprocess.run(["asc", "schema", query], capture_output=True, text=True, check=True)
        (out / f"{name}.json").write_text(result.stdout)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(lambda iid: catalog(out, iid, "USA"), [v[0] for v in list(PRODUCTS.values())[:3]]))
    jobs = []
    for plan in ("individual_lifetime", "family_lifetime"):
        iid, _, base = PRODUCTS[plan]
        us_points = load(out / "raw" / f"{iid}-USA-points.json")["data"]
        for tier in sorted({r["reference_tier_usd"] for r in rules.values()}, key=Decimal):
            target = base * Decimal(tier) / Decimal("19.99")
            point = nearest(us_points, target)
            jobs.append((iid, tier, point))
    def equalization(job):
        iid, tier, point = job
        get(out, f"{iid}-tier-{tier}-equalizations", f"/v1/inAppPurchasePricePoints/{point['id']}/equalizations", (
            ("include", "territory"), ("limit", "200")))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(equalization, jobs))
        # Upgrade is chosen from its own full local ladder against the local gap.
        # These grids also establish actual positive price floors (free IAP tiers excluded).
        list(pool.map(lambda t: catalog(out, "6796786086", t), territories))
    snapshot(out, "-after-readonly", refresh=True)


def csv_write(path, rows):
    assert rows
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def build(out):
    before = {name: current_prices(out, values[0]) for name, values in list(PRODUCTS.items())[:3]}
    territories = sorted(before["individual_lifetime"][0])
    rules = policy(out, territories)
    all_territories = {r["id"] for r in load(out / "raw/territories.json")["data"]}
    for name, (current, scheduled) in before.items():
        assert set(current) == set(territories), name
        assert not scheduled, f"Review scheduled price changes first: {name}"
        after, scheduled_after = current_prices(out, PRODUCTS[name][0], "-after-readonly")
        assert current == after and scheduled == scheduled_after, f"Live state drifted: {name}"
    assert not load(out / "raw/subscription-groups-after-readonly.json")["data"]
    rows, indexed = [], {}
    reference_us_floor = min(Decimal(p["attributes"]["customerPrice"]) for p in
                             load(out / "raw/6761033996-USA-points.json")["data"]
                             if Decimal(p["attributes"]["customerPrice"]) > 0)
    for plan, (iid, product_id, base) in PRODUCTS.items():
        us_points = load(out / "raw" / f"{iid}-USA-points.json")["data"] if iid else []
        for code in territories:
            rule = rules[code]
            target = base * Decimal(rule["reference_tier_usd"]) / Decimal("19.99")
            old = before[plan][0][code] if iid else None
            currency = before["individual_lifetime"][0][code]["currency"]
            flags, reference = [], ""
            local_target = minimum = selected = benchmark_price = None
            minimum_us = min((Decimal(p["attributes"]["customerPrice"]) for p in us_points
                              if Decimal(p["attributes"]["customerPrice"]) > 0), default=None)
            if plan in ("individual_lifetime", "family_lifetime"):
                us = nearest(us_points, target)
                benchmark_price = Decimal(us["attributes"]["customerPrice"])
                if code == "USA":
                    assert Decimal(us["attributes"]["customerPrice"]) == base
                    selected = us
                else:
                    eq_path = out / "raw" / f"{iid}-tier-{rule['reference_tier_usd']}-equalizations.json"
                    matches = [p for p in load(eq_path)["data"] if point_territory(p) == code]
                    assert len(matches) == 1, (plan, code)
                    selected = matches[0]
                reference = f"raw/{iid}-USA-points.json;raw/{iid}-tier-{rule['reference_tier_usd']}-equalizations.json" if code != "USA" else f"raw/{iid}-USA-points.json"
                if target < minimum_us:
                    flags.append("BELOW_US_PAID_LADDER_MINIMUM")
            elif iid:
                individual = Decimal(indexed[(code, "individual_lifetime")]["proposed_local_price"])
                family = Decimal(indexed[(code, "family_lifetime")]["proposed_local_price"])
                local_target = family - individual
                assert local_target > 0, (code, local_target)
                points = load(out / "raw" / f"{iid}-{code}-points.json")["data"]
                minimum = min(Decimal(p["attributes"]["customerPrice"]) for p in points if Decimal(p["attributes"]["customerPrice"]) > 0)
                selected = nearest(points, base if code == "USA" else local_target)
                if code == "USA":
                    assert Decimal(selected["attributes"]["customerPrice"]) == base
                if local_target < minimum:
                    flags.append("LOCAL_GAP_BELOW_MINIMUM_PAID_PRICE")
                reference = f"raw/{iid}-{code}-points.json"
            else:
                flags += ["SUBSCRIPTION_NOT_CREATED", "PRICE_POINT_UNRESOLVED", "LOCAL_MINIMUM_UNVERIFIED"]
                if target < reference_us_floor:
                    flags.append("USD_BENCHMARK_BELOW_REFERENCE_IAP_FLOOR_NOT_SUBSCRIPTION_VALIDATION")
            price = Decimal(selected["attributes"]["customerPrice"]) if selected else None
            if selected:
                decoded = decode_point(selected["id"])
                assert decoded["s"] == iid and decoded["t"] == code, (plan, code, decoded)
                assert price > 0
                status = "VERIFIED_IAP_CANDIDATE"
            else:
                status = "BLOCKED_MISSING_SUBSCRIPTION"
            row = {"territory": code, "country": rule["country"], "currency": currency, "plan": plan,
                   "product_id": product_id, "asc_product_id": iid or "", "status": status,
                   "before_local_price": old["price"] if old else "", "before_status": "CURRENTLY_SOLD" if old else "NOT_CREATED_NOT_SOLD",
                   "before_point_id": old["point_id"] if old else "", "before_manual": old["manual"] if old else "",
                   "approved_us_base": str(base), "policy_reference_tier_usd": rule["reference_tier_usd"],
                   "policy_multiplier": rule["multiplier"], "policy_usd_target_not_local_price": str(target.quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)),
                   "reference_iap_us_floor_not_subscription_floor": str(reference_us_floor),
                   "minimum_positive_us_benchmark": str(minimum_us) if minimum_us is not None else "",
                   "selected_us_benchmark": str(benchmark_price) if benchmark_price is not None else "",
                   "proposed_local_price": str(price) if price is not None else "", "proposed_point_id": selected["id"] if selected else "",
                   "local_target_gap": str(local_target) if local_target is not None else "",
                   "minimum_positive_local_price": str(minimum) if minimum is not None else "",
                   "change_percent": str(((price / Decimal(old["price"]) - 1) * 100).quantize(Decimal("0.01"))) if old and price is not None else "",
                   "gni_ppp": rule["gni_ppp"], "data_year": rule["data_year"], "policy_basis": rule["basis"],
                   "flags": ";".join(flags), "verification_evidence": reference}
            rows.append(row)
            indexed[(code, plan)] = row
    mismatches = []
    for code in territories:
        individual, family, upgrade = [indexed[(code, plan)] for plan in ("individual_lifetime", "family_lifetime", "family_lifetime_upgrade")]
        direct = Decimal(family["proposed_local_price"])
        combined = Decimal(individual["proposed_local_price"]) + Decimal(upgrade["proposed_local_price"])
        deviation = (combined - direct) / direct * 100
        flag = "UPGRADE_PATH_MORE_EXPENSIVE" if deviation > 1 else "UPGRADE_PATH_UNDERCUTS_FAMILY" if deviation < -1 else "WITHIN_1_PERCENT"
        if flag != "WITHIN_1_PERCENT":
            upgrade["flags"] = ";".join(filter(None, [upgrade["flags"], flag]))
        elif combined != direct:
            upgrade["flags"] = ";".join(filter(None, [upgrade["flags"], "UPGRADE_PATH_ROUNDING_DIFFERENCE"]))
        mismatches.append({"territory": code, "currency": family["currency"],
                           "individual_lifetime": individual["proposed_local_price"], "family_lifetime": family["proposed_local_price"],
                           "upgrade": upgrade["proposed_local_price"], "individual_plus_upgrade": str(combined),
                           "difference": str(combined - direct), "difference_percent": str(deviation.quantize(Decimal("0.01"))),
                           "status": flag, "is_exact_match": combined == direct,
                           "upgrade_floor": upgrade["minimum_positive_local_price"]})
    csv_write(out / "all-plans-before-after.csv", rows)
    for plan in PRODUCTS:
        csv_write(out / f"{plan}.csv", [r for r in rows if r["plan"] == plan])
    csv_write(out / "lifetime-upgrade-comparison.csv", mismatches)
    csv_write(out / "exceptions.csv", [r for r in rows if r["flags"]])
    csv_write(out / "policy-multipliers.csv", list(rules.values()))
    missing_territories = sorted(all_territories - set(territories))
    save(out / "summary.json", {"generated_at": utc(), "app_id": APP, "live_mutations": 0,
         "territories": len(territories), "apple_territories_outside_existing_schedules": missing_territories,
         "rows": len(rows), "verified_iap_candidates": sum(r["status"] == "VERIFIED_IAP_CANDIDATE" for r in rows),
         "blocked_subscription_rows": sum(r["status"] == "BLOCKED_MISSING_SUBSCRIPTION" for r in rows),
         "upgrade_mismatches_over_one_percent": sum(r["status"] != "WITHIN_1_PERCENT" for r in mismatches),
         "upgrade_rounding_differences_within_one_percent": sum(not r["is_exact_match"] and r["status"] == "WITHIN_1_PERCENT" for r in mismatches),
         "upgrade_floor_constraints": sum("LOCAL_GAP_BELOW_MINIMUM_PAID_PRICE" in r["flags"] for r in rows),
         "subscription_benchmarks_below_reference_iap_floor_not_subscription_validation": sum("USD_BENCHMARK_BELOW_REFERENCE_IAP_FLOOR_NOT_SUBSCRIPTION_VALIDATION" in r["flags"] for r in rows),
         "scheduled_changes": 0, "before_after_live_price_snapshots_equal": True,
         "product_price_scope": "Existing lifetime schedule territories only; subscription availability has not been created",
         "subscription_blocker": "Four subscription products do not exist; API price-point listing requires a subscription ID. No IAP IDs are substituted.",
         "policy_extension": "Preserve October 25 reference tiers/multipliers, scale each new base, snap lifetime benchmarks to nearest positive product-specific US point (lower on ties), use Apple equalizations; upgrade nearest positive local point to local Family minus Individual, with USA pinned to 39.99.",
         "worldbank_gni_sha256": digest(out / "worldbank-gni-ppp.json"), "worldbank_countries_sha256": digest(out / "worldbank-countries.json")})
    files = sorted(p for p in out.rglob("*") if p.is_file() and p.name != "sha256-manifest.json")
    save(out / "sha256-manifest.json", {str(p.relative_to(out)): digest(p) for p in files})
    print(json.dumps(load(out / "summary.json"), indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--fetch", action="store_true", help="Fetch read-only Apple GET evidence before building")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    assert 1 <= args.workers <= 6
    args.output.mkdir(parents=True, exist_ok=True)
    if args.fetch:
        fetch(args.output, args.workers)
    build(args.output)


if __name__ == "__main__":
    main()
