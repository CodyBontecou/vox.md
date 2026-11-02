# Subscription transition — October 29, 2026

## Current source policy

The current candidate removes custom in-app analytics and clears retired local analytics state on upgrade. Preserve essential services, disabled myself.md claims, and held live prices. Privacy changes and release wording remain unpublished for owner review. This source merge does not authorize any deployment, upload, submission, release, or purge of historical server records.

Deployment and metadata approvals recorded below belong to the earlier transition. They are historical evidence and are superseded by this candidate policy; do not reuse them to reactivate analytics collection. See the [current launch runbook](launch/hard-paywall/README.md).

## Current status

**Verified October 30, 2026 UTC: all four subscriptions are APPROVED. iOS 2.14/build 58 is DEVELOPER_REJECTED (developer-withdrawn); Mac 2.14/build 58 remains WAITING_FOR_REVIEW. Both retain MANUAL release. Neither candidate is publicly released. Existing Lifetime/upgrade prices remain frozen.**

Historical transition approvals (superseded for the current candidate): upload the drafted App Store descriptions/release notes, deploy analytics, prepare but do not publish website/support updates, and rely on existing Family Sharing behavior without a new second-account test. Keep this pricing transition out of the **in-app What's New slider**. App Store version notes are separate and were explicitly approved. Actual public app release and later lifetime repricing still require separate owner approval.

## Products and pricing

App: `6758967337`. Group: **Vox.md Unlimited**, `22526843`.

| Product ID | ASC ID | US price | Service level | Family Sharing |
| --- | --- | ---: | ---: | --- |
| `bontecou.Voxboard.individual.weekly` | `6828566827` | $0.99/week | 2 | No |
| `bontecou.Voxboard.individual.yearly` | `6828566769` | $29.99/year | 2 | No |
| `bontecou.Voxboard.family.weekly` | `6828566714` | $1.99/week | 1 | Yes |
| `bontecou.Voxboard.family.yearly` | `6828566853` | $49.99/year | 1 | Yes |

All four are now APPROVED. The provisioning readbacks verified **700 prices, 700 one-week introductory offers, 700 availability entries** across all 175 existing storefronts, with correct sharing and service levels. Apple controls introductory eligibility across the shared group. There is no monthly plan. Automatic availability in future territories is false pending a deliberate pricing review.

The October 25 PPP inputs/reference tiers were applied proportionally using each new subscription's own Apple ladder/equalizations. **35 Individual weekly benchmarks** hit the verified $0.29 subscription floor. Six Family weekly equalization collisions were corrected to the nearest legal local tier to `Individual weekly × (1.99 / 0.99)`:

| Territory | Currency | Individual weekly | Family weekly before | Family weekly configured |
| --- | --- | ---: | ---: | ---: |
| Bulgaria | EUR | 0.99 | 0.99 | 1.99 |
| Bahamas | USD | 0.99 | 0.99 | 1.99 |
| Chile | CLP | 990 | 990 | 1,990 |
| India | INR | 49 | 49 | 99 |
| Pakistan | PKR | 100 | 100 | 200 |
| Serbia | EUR | 0.99 | 0.99 | 1.99 |

Family now has a positive premium in every storefront/period. Reproducible price tables, actual point IDs, clamp flags and overrides are under `docs/evidence/subscription-transition-20261029/`: `subscription-regional-prices.csv`, `parity-overrides.json`, `pricing-plan-summary.json`, and `verification.json`.

## Builds, history, and review drafts

Both signed **2.14 (58)** builds processed VALID and remain attached with **MANUAL** release:

| Platform | Version ID | Build ID | Review draft |
| --- | --- | --- | --- |
| iOS | `805e71b5-fba0-4e6c-85e5-1df5373c51b1` | `5ce910e1-8d3f-4f6e-be5f-c133b6299c7e` | `a8b73b42-df07-4283-a32a-169ed629a741` |
| Mac | `045ffb94-b19a-4d5a-abc4-8c06f9947c51` | `b4a47e9b-01c9-4e46-b608-090d1e1b1672` | `cfc0848f-82ac-48f2-a502-0418c3ec720f` |

The editable old Mac 2.9 draft was renamed 2.14, not a released version. Public released versions remain unchanged.

Unpaid users can open history from the iOS paywall's clock button or Mac's View and Export Existing History button. Read/search/copy/export/explicit deletion work without purchasing; new recordings, transcription, Capture deliveries, editing, and queued Capture retries remain gated. Mac has a native Markdown save-panel export. No content or usage ledger was deleted.

After fresh checks, the two existing drafts were submitted successfully: **iOS at 22:26:23 UTC** (app version + group + four subscription versions, six items), then **Mac at 22:26:30 UTC** (one app-version item). At the time of submission, both app versions and all four subscription products read back **WAITING_FOR_REVIEW**; the current states are recorded above. Both app versions retain MANUAL release. Exact submit receipts and post-submit readbacks are in `review-submission/`. No duplicate drafts were created and no release command was sent.

All four subscription review screenshots are COMPLETE and reviewer instructions are attached. Optional promotional images remain absent/advisory; no promoted-purchase setup was enabled.

## App Store copy — applied and verified

Owner approved the drafted descriptions and release notes after clarifying that the **in-app slider must not discuss this strategy**. All **78 version-localization records (39/platform)** were patched by exact ID and read back. Descriptions and `whatsNew` match the approved proposal exactly; keywords, support/marketing URLs and promotional text are unchanged. Missing-release-note errors are resolved.

The historical proposal files retain their original awaiting-approval labels as provenance; current truth is in `listing-application/owner-approval.json` and `listing-application/verification.json`. The approval receipt pins the exact proposal SHA-256. `scripts/apply-approved-subscription-listing-copy.py` defaults to read-only preflight, scopes writes to these two exact drafts, rejects concurrent field changes and proposal drift, and does not touch Notelet.

## Authenticated web checks — agreement resolved

The owner was correct: **Pi Browser is signed in**. The earlier `/appPrivacy` URL returned only an empty app shell; the current observed route is `/apps/6758967337/distribution/privacy`.

- App Privacy is **Published**, showing User ID, Purchase History and Product Interaction for analytics, not linked to identity. No unpublished declaration was published or changed.
- Pre-submission draft contents were verified with included public API relationships: iOS 2.14 + the group/four subscriptions, and Mac 2.14.
- The owner reviewed/accepted the updated Developer Program License Agreement. A fresh authenticated Apps page no longer showed its warning. Both subsequent submit requests succeeded; the agent did not accept the agreement on the owner's behalf.
- A separate banner says membership renewal is due **November 3, 2026**. Automatic-renewal status is not verified; do not infer expiration or buy another membership without checking.

No agreement action remains for this submission. Membership renewal remains an owner follow-up. The CLI's separate cached Apple web session remains unavailable, so its deep checks can report unverified even while Pi Browser is authenticated. Never copy cookies between them.

The Mac and subscription canonical readiness rechecks had zero errors. The URL check caught **14 obsolete privacy-policy URLs returning 404**. Only those privacyPolicyUrl fields in the editable app-info draft were corrected to the existing working `https://vox.isolated.tech/privacy.html`; all 39 rows were compared before/after to verify unrelated attributes unchanged. The website and privacy policy contents were not changed or published. Other transient HTTP warnings were rechecked with successful direct GETs.

The iOS validator still has a two-app-info resolver bug (published + editable). Its editable age rating was retrieved explicitly. A separate iOS audit confirmed the attached VALID build 58, no non-exempt encryption, iPad support in the IPA and a populated required iPad screenshot set, localized fields and review information. Do not delete app infos to work around a CLI issue. Apple's final submit validation accepted both prepared submissions.

## Historical analytics deployment and unpublished launch materials

The approved production analytics update was deployed: Worker version **`892fd12f-eda2-4539-bae2-4bb3fa82a596`**, preserving existing configuration and D1 binding. Seven Worker tests passed. Production health passed; validation-only batches proved all seven legacy/new product IDs accepted and unknown IDs rejected. The batches intentionally fail before database insertion, so no synthetic purchase events polluted the real funnel. No database migration or new data collection fields were introduced.

Prior Worker version for an owner-approved rollback: `f41053e5-a1d7-4a92-87a2-1c559a8e32e5`. Deployment receipts, before/after versions and smoke evidence are in `analytics-deployment/`.

Website/support preparation is **not published**: `docs/launch/hard-paywall/README.md`, five staged files, `website.patch` and source/staged hashes. The generator does not edit the deployable `website/` tree. The patch removes obsolete allowances/no-subscription claims, explains current plans/trials, unpaid history and cancellation, and deliberately omits future numeric lifetime targets. `git apply --check` passes. The runbook includes support responses, remaining QA, manual release, aggregate monitoring and rollback constraints. Do not deploy website copy before the approved app release point.

## Verification and remaining risk

- Shared/core SwiftPM: **1,046 passed**.
- iOS suite: **307 tests, three skipped, zero failures**; two entitlement-dependent Keychain tests excluded on an unsigned host. Skips cover the signed App Group container and two opt-in model evaluations.
- Additional unpaid-history render/export test passed; inspected screenshot confirms old content visible with access still locked.
- Both signed archives exported/uploaded and VALID. Parsed project settings changed only intended 2.14/58 values across 14 configurations despite CLI formatting churn.
- Original regional proposal/scope tests pass, plus launch-staging checks protecting deployable source and the in-app slider.
- **525 existing lifetime price records/IDs remain unchanged** in before/after comparisons. No lifetime writes or future price changes were introduced.
- A fresh focused iOS run passed **all five HardPaywallStoreKitTests**, covering catalog/trial/Family settings, purchase/refund, expiration/lifetime access, paywall rendering and unpaid-history export. Its log is in `review-submission/focused-storekit-tests.log`. Twenty Python pricing/scope/staging checks also passed.
- Local StoreKit tests are not a substitute for signed real-device/sandbox purchase and full-motion QA. Those remaining checks are explicit in the launch runbook. Fresh second-account Family Sharing QA is **waived by the owner based on existing working Family Sharing**, not claimed newly verified.

Read-only verification:

```sh
python3 scripts/apply-approved-subscription-listing-copy.py --verify
python3 scripts/prepare-vox-subscriptions.py --verify
python3 -m unittest discover -s scripts/tests -p 'test_hard_paywall*.py' -v
python3 -m unittest discover -s scripts/tests -p test_subscription_transition.py -v
```

## Existing-price freeze

Current US lifetime prices remain **$19.99 Individual / $39.99 Family / $19.99 upgrade**, with their regional schedules preserved. The later $49.99/$89.99/$39.99 targets are not applied or scheduled. Follow `docs/hard-paywall-pricing.md`: public subscription release, production verification and a separate owner repricing go-ahead are required first. Review approval and manual app release do not themselves authorize repricing.

## Current working-checkout qualification — October 30 UTC

The owner confirmed weekly/yearly plans and deferred Vox Android. Eight current-candidate local StoreKit/history/render tests passed; the opt-in interaction host was skipped in that normal run. Added cases call the real Restore Purchases path into fresh local state and prove cancellation, pending approval and network-failed restore cannot unlock a fresh user. Local StoreKit is not Apple sandbox-account or cross-account Family Sharing evidence.

A separate opt-in preview host launched successfully, but Argent returned an empty accessibility tree and reported missing native instrumentation for the XCTest-owned process. No element coordinates were inferred from screenshots, no interaction was attempted and no new replay pass is claimed. The earlier search-focus failure remains unresolved until an instrumented, launchable fixture or equivalent UI-test path is available.

This checkout remains on `fix/remove-recording-duration-limits` with uncommitted candidate work, while local and remote main differ. Candidate checks do not certify a committed main release. Do not replace an uploaded binary or publish the staged website until the intended source is reconciled and the matching release is ready. Existing Lifetime/upgrade prices are unchanged.
