# Vox.md regional pricing proposal — October 29, 2026

**Historical read-only proposal: no mutations were performed while generating this snapshot.** Subsequent owner-authorized subscription preparation is recorded in [subscription-transition-20261029.md](subscription-transition-20261029.md). That later work resolves subscription prices using the newly created products; existing lifetime/upgrade prices remain unchanged.

App: `6758967337`. The live before/after reads still show three approved lifetime IAPs and no subscription groups. Current effective lifetime prices and full price-point IDs matched across the two live snapshots. No future price changes were found.

## Results and limits

- **175 storefronts; 1,225 proposal rows** covering six plans plus the lifetime Family upgrade.
- **525 verified lifetime/upgrade candidates**: actual product-specific Apple price points, with current local prices and exact proposed IDs.
- **700 blocked subscription rows**: policy USD benchmarks are calculated, but local prices, local minimums, and subscription price-point IDs cannot be resolved before the four subscriptions exist. Blank local-price cells mean *unresolved*, not free or zero.
- **41 small upgrade rounding differences** are flagged; none exceeds the existing 1% review tolerance. The US $89.98 upgrade path versus $89.99 direct Family is one of these.
- **No resolved lifetime upgrade is forced above its target gap by a minimum paid-price floor.** No direct lifetime USD benchmark falls below its verified positive US IAP floor.
- **35 Individual weekly benchmarks need extra minimum-price review**: the policy yields approximately USD $0.247129, below the observed $0.29 IAP reference floor. This is an early warning only, not a verified subscription minimum. All subscription minimums remain unverified.

The subscription limitation is a boundary of the requested no-creation scope, not a reason to substitute lifetime price-point IDs. The saved API schema requires `/v1/subscriptions/{id}/pricePoints`, and the live app has no subscription IDs to query.

## US before → proposed

| Purchase option | Live before | Proposed US target | Resolution |
| --- | ---: | ---: | --- |
| Individual weekly | Not created/sold | $0.99/week | Subscription ladder pending |
| Individual yearly | Not created/sold | $29.99/year | Subscription ladder pending |
| Individual lifetime | $19.99 | $49.99 | Apple IAP point verified |
| Family weekly | Not created/sold | $1.99/week | Subscription ladder pending |
| Family yearly | Not created/sold | $49.99/year | Subscription ladder pending |
| Family lifetime | $39.99 | $89.99 | Apple IAP point verified |
| Individual → Family lifetime upgrade | $19.99 | $39.99 | Apple IAP point verified |

The four subscriptions still require a seven-day eligible introductory trial, one shared subscription group, Family Sharing on Family subscriptions, and product availability/review configuration. Those are not price-point changes and were not performed here.

## Regional lifetime examples

All figures below are local currency. Full price-point IDs and per-product source responses are in the CSVs.

| Storefront | Currency | Individual before → proposed | Family before → proposed | Upgrade before → proposed |
| --- | --- | ---: | ---: | ---: |
| United States | USD | 19.99 → 49.99 | 39.99 → 89.99 | 19.99 → 39.99 |
| India | INR | 699 → 1,799 | 1,399 → 2,999 | 699 → 1,200 |
| Brazil | BRL | 59.90 → 149.90 | 119.90 → 299.90 | 59.90 → 150.00 |
| United Kingdom | GBP | 17.99 → 44.99 | 34.99 → 79.99 | 17.99 → 35.00 |
| Japan | JPY | 2,500 → 6,000 | 5,000 → 11,000 | 2,500 → 5,000 |
| Pakistan | PKR | 1,300 → 3,500 | 2,600 → 5,900 | 1,300 → 2,400 |
| Nigeria | NGN | 9,900 → 29,900 | 19,800 → 49,900 | 9,900 → 20,000 |

Some upgrade endings are not `.99` because the priority is matching the **local** Family–Individual gap using a valid upgrade-product price point. Do not replace these with attractive endings without rechecking the comparison table.

## Purchasing-power policy

The proposal reuses the exact World Bank inputs and reference tiers retained for the October 25 policy. It does not silently refresh income data or change country classifications:

1. Compute `19.99 × sqrt(country GNI PPP / US GNI PPP)`, clamp to 4.99–19.99, and select the nearest original benchmark tier (lower on ties).
2. Preserve the prior income-group fallbacks and Kosovo mapping.
3. Extend the policy proportionally to each new base: `new US base × selected tier / 19.99`. A fixed $4.99 floor would be inappropriate for a $0.99 weekly plan; the previous relative discount bands are preserved instead.
4. For direct lifetime products, select the nearest supported positive US benchmark **on that product's own ladder**, then use Apple's current equalization for each territory. This incorporates Apple's local pricing/tax/currency choices; it is not an exchange-rate conversion.
5. For the lifetime upgrade, select the nearest supported positive local upgrade point to `local Family − local Individual`. Pin the US to the approved $39.99. Report every nonzero difference and escalate discrepancies above 1%.

These are proposed regional prices, not proven demand optima or authorization to apply them. Tax/exchange-rate changes can require maintenance of custom overrides.

## Saved tables and verification evidence

Directory: [`docs/evidence/hard-paywall-regional-proposal-20261029/`](evidence/hard-paywall-regional-proposal-20261029/).

Start with:

- [`all-plans-before-after.csv`](evidence/hard-paywall-regional-proposal-20261029/all-plans-before-after.csv)
- [`lifetime-upgrade-comparison.csv`](evidence/hard-paywall-regional-proposal-20261029/lifetime-upgrade-comparison.csv)
- [`exceptions.csv`](evidence/hard-paywall-regional-proposal-20261029/exceptions.csv)
- [`summary.json`](evidence/hard-paywall-regional-proposal-20261029/summary.json)
- [`README.md`](evidence/hard-paywall-regional-proposal-20261029/README.md) for column semantics, provenance, and reproduction.

Each of the seven options also has its own CSV. `raw/` preserves complete paginated Apple responses; `get-audit.jsonl` records GET-only retrievals; `sha256-manifest.json` verifies the saved artifacts. Current prices are resolved by matching included raw Apple objects by **complete price-point ID**, avoiding the incorrect resolved-amount display previously observed in the CLI.

Rebuild offline and validate:

```sh
python3 scripts/plan-hard-paywall-regional-pricing.py
python3 -m unittest discover -s scripts/tests -p test_hard_paywall_regional_pricing.py -v
```

Thirteen offline checks cover the frozen policy, positive-tier selection, pagination, US targets, product/territory ownership of IDs, raw point evidence, local-gap selection, exception flags, unresolved-subscription honesty, unchanged live prices, GET-only command construction, and evidence hashes.

## Live pricing freeze and next approval boundary

**Owner-required sequencing:** keep every existing lifetime and upgrade price unchanged, in every territory, until the subscription-capable update is publicly released and verified in production. Do not apply or pre-schedule the proposed increases, replace schedules, or remove existing regional overrides early. App Review approval or TestFlight availability alone is insufficient. After production verification, obtain a separate owner go-ahead before repricing. The detailed [release gate](hard-paywall-pricing.md#release-gate-freeze-existing-live-prices) defines required platform/storefront checks and evidence. No automatic pricing cutover is authorized.

At the time of this proposal, the lifetime candidates could be reviewed, but completing numeric local subscription proposals required separate permission to create the four subscriptions (not to apply their prices or submit them), followed by fetching their real ladders/equalizations and checking minimums. No such permission is assumed here. Do not import these proposal CSVs as live price schedules: they intentionally use descriptive columns and contain unresolved rows, not mutation request bodies.
