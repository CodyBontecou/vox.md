# Hard paywall and subscription pricing

> Unpublished candidate update: custom in-app analytics and attribution have been removed. Historical analytics below describe earlier builds/services. Essential services remain. Prices are unchanged; nothing is deployed, submitted, or released.

## Approved policy

New and existing free installations must purchase or start a verified StoreKit subscription trial before Capture or transcription. There is no local free-minute or free-Capture allowance. Existing lifetime purchases, Family Sharing entitlements, and verified original paid-app owners keep access. Existing content and usage ledgers are not deleted. Unpaid users can view, search, copy, export, and delete existing history without purchasing; new Capture, transcription, history editing, and queued Capture retries remain gated.

US price targets (USD):

| Access | Weekly | Yearly | Lifetime |
| --- | ---: | ---: | ---: |
| Individual | $0.99 | $29.99 | $49.99 |
| Apple Family Sharing | $1.99 | $49.99 | $89.99 |

Weekly and yearly subscriptions have a seven-day introductory free trial for eligible Apple Accounts. Lifetime has no subscription trial. No monthly product is introduced. UI prices always come from StoreKit, not hard-coded US values.

## Catalog

| Product ID | Type | Family Sharing |
| --- | --- | --- |
| `bontecou.Voxboard.individual.weekly` | Auto-renewable, one week | No |
| `bontecou.Voxboard.individual.yearly` | Auto-renewable, one year | No |
| `bontecou.Voxboard.unlock` | Existing non-consumable, lifetime | No |
| `bontecou.Voxboard.family.weekly` | Auto-renewable, one week | Yes |
| `bontecou.Voxboard.family.yearly` | Auto-renewable, one year | Yes |
| `bontecou.Voxboard.family` | Existing non-consumable, lifetime | Yes |
| `bontecou.Voxboard.familyUpgrade` | Legacy non-consumable upgrade | Yes |

Use **one subscription group** for all four subscriptions so changing billing period/access does not create concurrent subscriptions or reset introductory eligibility. Family is subscription level 1; Individual is level 2; weekly and yearly are equivalent within their access level. Enable Family Sharing on the two Family subscriptions. Configure one period of a free one-week introductory offer for each subscription.

The owner approved a **$39.99 US Family lifetime upgrade**, replacing the previous $19.99 target. It remains available only to lifetime Individual owners; subscribers do not qualify. Individual lifetime ($49.99) plus the upgrade ($39.99) totals $89.98, one cent below direct Family lifetime ($89.99). Existing upgrade entitlements are unchanged. The development catalog reflects this price; the live App Store Connect price has not yet been changed.

## Implementation

- `PurchaseAccess.swift`: stable existing product IDs plus four subscription IDs.
- `UsageTracker.swift`: zero free allowances; shared subscription expiry and lifetime fallback; expired subscription caches cannot indefinitely unlock keyboard/Capture extensions.
- `CaptureDeliveryUsageStore.swift`: default zero-free Capture policy, retaining ledger idempotence.
- iOS and Mac Store managers: eligibility-aware seven-day trial messaging, expiration/revocation/upgraded-transaction filtering, restore and transaction updates.
- iOS and Mac app roots: paywall replaces core UI for unpurchased users; entitlement refresh on a 30-second cadence while running. iOS foreground and existing Mac lifecycle paths also refresh access.
- iOS release notes are presented only after access is unlocked.
- `TranscriptionServer.swift`: legacy keyboard IPC also checks access.
- Paywalls: localized recurring/one-time prices, Individual/Family selection, restore, renewal disclosures, Terms/Privacy links, and subscription-management links. Buying lifetime does not cancel an existing subscription.
- `worker/onboarding-analytics/src/index.ts`: the strict product-ID allowlist now accepts subscriptions and existing Family products; unknown/monthly IDs remain rejected. Deploy this Worker update before the app release so purchase events are not rejected.
- `Voxboard/Voxboard.storekit`: development catalog only. The `VoxboardTests` scheme selects it for StoreKit tests; ordinary launch/release schemes do not substitute local products for live products.

## Initial App Store Connect audit — October 29, 2026

Before the later authorized preparation, app `6758967337` had **no subscription groups**. Existing approved IAP records:

- Individual lifetime: `6761033996`
- Family lifetime: `6796785976` (Family Sharing enabled)
- Legacy Family upgrade: `6796786086` (Family Sharing enabled)

This implementation does **not** create or change live App Store Connect products, prices, offers, availability, or submissions. `Voxboard.storekit` is not production configuration. Existing regional lifetime pricing is described in `pricing-20261025.md` and must not be assumed updated.

The subsequent [subscription preparation status](subscription-transition-20261029.md) records the authorized group/product creation, regional subscription configuration, 2.14 (58) build uploads, history-access changes, and review blockers. Existing lifetime prices remain frozen.

The historical read-only [regional pricing proposal](regional-pricing-proposal-20261029.md) contains 525 verified lifetime/upgrade price-point candidates across 175 storefronts, plus policy benchmarks for the 700 subscription rows that remain blocked on product creation. Regional prices have not been applied.

## Release gate: freeze existing live prices

The owner requires **all existing live Individual lifetime, Family lifetime, and Family lifetime upgrade prices to remain unchanged in every territory until the subscription update is released and verified in production**. Do not apply or pre-schedule increases, replace schedules, change base territories, or remove regional overrides before this gate passes. Approved target amounts and proposal tables are not authorization to mutate live pricing.

Required order:

1. Keep existing lifetime/upgrade schedules frozen. Subscription creation/configuration, pricing, Family Sharing, availability, and review submission require separate explicit authorization; this freeze does not authorize them.
2. Once authorized, prepare one group and four subscriptions, resolve their actual regional ladders/minimums, obtain regional pricing approval, and configure seven-day offers, localizations, availability, and review screenshots. Do not alter existing lifetime/upgrade schedules.
3. Verify sandbox/TestFlight purchase, trial, restore, Family Sharing, expiration, refund, and subscription-switching paths. Existing lifetime purchasers must retain access at their original purchase terms. Keep paywall amounts sourced from StoreKit, including unchanged live lifetime prices during the transition.
4. Deploy the analytics allowlist update and prepare truthful website/App Store copy after the relevant approvals. Complete interactive full-motion QA and translation review. Do not ship a hard wall until its live products are available.
5. Release the subscription-capable update only after explicit release approval. The pricing gate remains closed until the update is publicly available on every platform in the intended rollout (iOS and Mac unless the owner explicitly narrows scope), all four subscriptions resolve at the approved local prices, eligible trial offers and Family Sharing configuration are present, and a production purchase/restore smoke test has evidence. Any real charge requires explicit authorization. App Review approval, TestFlight availability, or a phased-release start alone does not satisfy this gate.
6. Record release version/builds, storefront/platform checks, timestamps, and purchase/restore evidence. Ask the owner for a separate go-ahead to change existing lifetime/upgrade prices after reviewing that evidence. Do not treat gate completion as automatic permission.
7. Only then apply and verify approved US lifetime targets ($49.99 Individual, $89.99 Family, $39.99 upgrade) and separately approved regional overrides. Capture fresh before/after schedules and retain rollback evidence. If the subscription release is delayed, unavailable, or fails production verification, stop and leave all existing prices unchanged.

## Verification

- SwiftPM shared/core suites: 1,046 tests passed after policy changes (665 shared, 381 core).
- iOS simulator and Mac Debug builds passed. An initial build explicitly forcing `-sdk iphonesimulator` incorrectly built embedded Watch assets for iOS; use `-destination` without forcing `-sdk` so Xcode picks the proper Watch simulator SDK.
- iOS suite: 306 tests executed, three skipped, zero failures. Two native Keychain integration tests were excluded because the unsigned simulator host lacks Keychain entitlements (`-34018`). Skips are the App Group recording-container test and two opt-in on-device model evaluations. Paid-operation fixtures explicitly grant access instead of relying on the retired free allowance.
- Four `HardPaywallStoreKitTests` passed: real StoreKit local catalog checks for the six plans and the Family lifetime upgrade price, Family Sharing flags, seven-day trial eligibility; subscription purchase/expiry, lifetime preservation, refund, and layout attachments. Light, dark, and accessibility-largest screenshots were inspected from `.derived/hard-paywall/Logs/Test/Test-VoxboardTests-2026.10.29_13-00-49--0400.xcresult`; the later full-suite result is `Test-VoxboardTests-2026.10.29_13-05-50--0400.xcresult`.
- After the upgrade-price approval, `testCatalogPricesTrialsAndFamilyOptions` passed again with the $39.99 upgrade included. Expected prices are parsed from decimal strings to avoid binary floating-point rounding in monetary assertions.
- Analytics Worker: seven Node tests passed, including every product ID and rejection of a monthly product.
- Simulator UI control is not available on this host (no Simulator.app/Argent tools); screenshot/layout evidence is not a substitute for the interactive QA listed above.
