# Android monetization parity — November 1, 2026

## Lifetime purchase and restore

The native individual lifetime product remains `vox_unlimited_lifetime`, a Google Play
non-consumable. This update hardens its existing purchase/restore path:

- Checkout uses the exact eligible Play offer token paired with the displayed price.
  Rental and preorder options are excluded from the lifetime product presentation.
- Already-owned, pending, restoring and in-flight states cannot launch another checkout.
  Busy states are visible and disable conflicting purchase/restore actions.
- Query generations reject late ownership/product callbacks. Explicit restore intent
  survives overlapping foreground refresh and purchase callbacks; a response applies once.
- Immediate cancellation preserves access; `ITEM_ALREADY_OWNED` performs ownership
  reconciliation instead of reporting a failed purchase or opening another checkout.
- Acknowledgement requests are coalesced in memory. Failures retain verified access,
  expose a restore/retry message, and can be retried on the next ownership query.
- Existing installation/product-bound HMAC cache, pending/refund rules, privacy-safe
  diagnostics and separation from capture content remain in force.

## Family access and discounted family upgrade

The accepted decision is **individual-only Android access**. Family access and
discounted family upgrades are intentional platform differences, excluded from the
Android parity objective. The user selected this direction on November 1, 2026;
[ADR-0024](architecture/adr-0024-android-individual-only-monetization.md) records it.

Google Play Family Library does not share in-app purchases. The existing Android
purchase screen already explains that Unlimited belongs to the purchasing Google Play
account and that Apple purchases do not transfer. No family or discounted-family
product, app-account system or family entitlement backend is introduced.

The two family capability IDs remain in the ledger for iPhone and iPad; Android is
removed from their platform lists. Their Apple statuses are unchanged. This resolves
the Android scope decision without claiming an implemented or verified family feature.
Apple purchases and grandfathering remain governed by the separate existing policy.

Sources: [Play Family Library](https://support.google.com/googleplay/answer/7007852),
[one-time product offers](https://developer.android.com/google/play/billing/one-time-product-multi-purchase-options-offers),
[Play purchase lifecycle](https://developer.android.com/google/play/billing/lifecycle/one-time),
and `docs/architecture/adr-0008-play-billing-network-isolation.md`.

## Validation

Client-side implementation commit: `1c0fa09`. Oracle fixture commit: `c0b8b79`.
The oracle was regenerated from clean source
`1c0fa095bcec8ab507cb8432c11ff267d69ed8d0`; all 14 cases are unchanged and clean-tree
provenance reproduction passes.

- Full Android CI gate passed: `check assembleDebugAndroidTest
  :app:validateDebugArtifacts :wear:validateWearDebugArtifacts releaseReadiness`.
  Includes lint, 272 JVM tests, four-ABI native packaging, phone/Wear debug and
  optimized release artifacts, SBOM and readiness validation.
- Phone instrumentation: 83 discovered, 79 passed, four existing separately provisioned
  model-fixture cases skipped, zero failures. All four new billing UI tests execute.
  Both matching app/test APKs were installed, and the dedicated API-36 Vox emulator
  app sandbox was reset before the full run.
- Routine data instrumentation: all 22 tests passed, including Room, quota and eight
  real-provider recovery campaigns. The separate quota driver passed both phases
  across an actual uninstall/reinstall of the isolated data-test application.
- Rust: all 49 workspace tests passed, plus formatting, strict Clippy and byte-identical
  Swift/Kotlin bindings. Swift: 655 shared XCTest, 381 core XCTest and 10 Swift Testing
  tests passed using the isolated shared-container override.
- Project contracts: 65 script tests and 136 contract tests passed, with 281 capability
  rows, 200 implementation hashes and four schema/resource mirrors. Localization
  freshness, 347-feature inventory coverage and whitespace checks pass.

Lifetime and restore rows are now `implemented` with account acceptance planned.
The ledger contains 262 verified, 12 implemented and seven inventoried capabilities;
of 246 Android/Wear-applicable rows, 233 are verified, 12 implemented and one
inventoried. Family and family-upgrade scope is resolved by ADR-0024; the separate
Apple-grandfathering row remains inventoried.
Android translation review remains open (557 catalog-missing English fallbacks).
These checks qualify the completed individual-client implementation; they do not
claim an implemented family service or actual store-account transactions.

Actual Play license-account purchase, pending payment, acknowledgement, refund and
reinstall/restore campaigns remain account qualification; fixture/UI checks do not
claim real store transactions.

## Individual-only scope follow-up

ADR-0024 confirms the user's decision and updates the base/derived parity ledger,
feature inventory and execution plan. Runtime purchase behavior and product IDs are
unchanged; the existing individual-only disclosure already matches the decision.
The full project-contract gate passed: 65 script tests and 136 contract tests, with
193 governed files, 281 capabilities, 200 implementation hashes and four resource
mirrors. Localization freshness, 347-feature inventory coverage and whitespace checks
also passed. The full implementation checks above remain the evidence for unchanged
application code; this follow-up changes policy, documentation and ledger applicability.
