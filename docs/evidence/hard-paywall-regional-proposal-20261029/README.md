# Read-only regional pricing evidence

This directory is a **proposal, not an applied price schedule**. No products were created, prices applied, or submissions made.

## Files

- `all-plans-before-after.csv`: 1,225 rows = seven purchase options × 175 storefronts. Current local prices/IDs, proposed local prices/IDs where resolvable, policy multipliers, USD benchmark targets, minimum-price checks, flags, and evidence paths.
- `individual_lifetime.csv`, `family_lifetime.csv`, `family_lifetime_upgrade.csv`: 525 resolved IAP candidates in total. These are product-specific points returned by Apple, not synthesized IDs.
- `individual_weekly.csv`, `individual_yearly.csv`, `family_weekly.csv`, `family_yearly.csv`: 700 explicitly blocked subscription rows. USD policy benchmarks are provided; local prices and IDs are blank because the subscription products do not exist.
- `lifetime-upgrade-comparison.csv`: local Individual + Upgrade versus direct Family, with exact differences and a 1% review threshold.
- `exceptions.csv`: all unresolved subscription rows and all nonzero lifetime upgrade rounding differences. A difference within 1% is still disclosed, not silently treated as exact.
- `policy-multipliers.csv`: the frozen purchasing-power classification for every storefront.
- `summary.json`: machine-readable counts, constraints, and before/after live-state verification.
- `raw/`: Apple's complete paginated response envelopes, including product catalogs, current schedules, full local upgrade ladders, US ladders, equalizations, and a second live-state readback.
- `get-audit.jsonl`: GET commands, timestamps, cache-use markers, resource counts, and response hashes. Cached records describe the retrieval command but do not represent another network request.
- `errors/`: retained read-only retrieval errors. The first attempt incorrectly used collection pagination on a singular schedule response; the request was corrected and successful snapshots were captured. No mutation was involved.
- `*schema.json`: CLI-embedded Apple API schema evidence. Subscription price-point listing requires an existing subscription ID.
- `worldbank-gni-ppp.json`, `worldbank-countries.json`: exact copies of the inputs retained for the approved October 25 policy, not newly downloaded or updated income data.
- `sha256-manifest.json`: SHA-256 hashes of the saved evidence and generated tables, excluding the manifest itself.

## Policy interpretation

Reuse the previous reference calculation: `19.99 × sqrt(country GNI PPP / US GNI PPP)`, clamped to 4.99–19.99, then select the nearest original tier: 4.99, 6.99, 7.99, 9.99, 12.99, 14.99, 17.99, 19.99. Lower wins ties. Preserve the original income-group fallbacks and Kosovo mapping.

To extend that policy to different US bases, use `new base × selected reference tier / 19.99`. This preserves the prior relative discount bands rather than imposing a $4.99 floor on a $0.99 weekly plan. For direct lifetime products, snap the USD benchmark to the nearest positive price on that product's actual US ladder, then use Apple's current equalizations for the local candidate. US owner-approved prices remain fixed.

For the lifetime upgrade, choose the nearest **upgrade-product-specific local** positive price to `local Family lifetime − local Individual lifetime`; US is explicitly pinned to $39.99. Thus its USD PPP benchmark is explanatory only, not the selection target. Regional gaps and Apple rounding can yield unfamiliar but valid endings such as INR 1,200 or GBP 35.00.

## Minimums and unresolved subscriptions

The verified positive US IAP ladder floor is $0.29. No direct-lifetime policy benchmark falls below it, and no local lifetime gap is below the upgrade's local positive floor. Free $0 IAP points are never selected.

In 35 storefronts the Individual weekly **USD policy benchmark** is approximately $0.247129, below the observed $0.29 **IAP reference floor**. These are flagged for subscription-ladder review. This is **not proof of a subscription minimum**: subscription ladders, equalizations, minimum local prices, and their product-specific IDs must be verified independently after product creation is authorized. All 700 subscription rows remain marked `LOCAL_MINIMUM_UNVERIFIED` regardless of this additional warning.

The seven options use the existing 175 lifetime schedule territories for planning. This does not create or assert future subscription availability.

## Reproduce without network

From the repository root:

```sh
python3 scripts/plan-hard-paywall-regional-pricing.py
python3 -m unittest discover -s scripts/tests -p test_hard_paywall_regional_pricing.py -v
```

The first command rebuilds the tables and manifest from saved evidence only. `--fetch` enables GET-only retrieval; cached response files are reused, and explicit `-after-readonly` snapshots are refreshed. For a later dated proposal, use a new output directory containing the frozen World Bank input files so earlier evidence is preserved.

Original input provenance: `/Users/codybontecou/dev/gitsync.md/docs/evidence/regional-pricing-20261025/worldbank-{gni-ppp,countries}.json`. Source input hashes are recorded in `summary.json` and the manifest. No credentials or authorization headers are saved.
