# Hard-paywall launch and support runbook

## Current controls

- Both 2.14 (58) app submissions and all four subscriptions are WAITING_FOR_REVIEW following successful October 29 submissions. No app release has occurred.
- Owner approved the App Store descriptions/release notes; all 78 records (39/platform) were applied and verified. App Store notes are separate from the in-app Notelet slider. Do not add this pricing transition to that slider.
- Both 2.14 (58) builds remain attached with MANUAL release. The submitted iOS review contains the app, group, and four subscription versions (six items); the submitted Mac review contains the app (one item).
- Existing lifetime/upgrade prices remain frozen. Do not pre-schedule a later increase.
- Owner authorized analytics deployment; version `892fd12f-eda2-4539-bae2-4bb3fa82a596` is live. Seven tests and production validation smoke passed, preserving legacy products and rejecting unknown products. Smoke batches deliberately failed before DB insertion so no fake purchases entered the real funnel.
- Owner has no second Family Sharing tester and accepts existing Family Sharing behavior. Fresh cross-account subscription sharing is **waived, not newly tested**.

## Agreement resolved; membership renewal follow-up

The owner reviewed/accepted the updated Apple Developer Program License Agreement. Its warning disappeared in a fresh authenticated browser check and both subsequent submissions succeeded. No agent accepted it on the owner's behalf. Membership renewal is still due November 3, 2026; the banner does not prove whether automatic renewal is enabled. Owner should review this separately, not purchase a second membership without checking.

App Privacy was verified published in the authenticated browser, listing User ID, Purchase History, and Product Interaction for analytics, not linked to identity. There was no unpublished privacy draft to publish and no data-type change from the product allowlist update.

Agreement, review readiness and price-freeze checks were repeated before submitting. Fourteen dead draft privacy-policy links were corrected to the existing live policy URL; the website and policy contents were not changed. Five focused local StoreKit/history tests and twenty Python checks passed. The CLI's cached-web-session store is separate from Pi Browser; a CLI `sessionStatus: unavailable` does not mean the managed browser is signed out. Do not copy browser cookies into CLI storage.

## Remaining purchase QA before public release

Use signed sandbox/TestFlight builds, not real production charges. Record actual evidence and never label local StoreKit simulation as Apple sandbox/device testing.

- [ ] Fresh install: no new Capture/transcription without access; existing history button remains available offline.
- [ ] Eligible trial: accurate localized price/period, one-week trial, Apple confirmation, access granted.
- [ ] Intro-ineligible account: no misleading free-trial promise; Apple-confirmed purchase grants access.
- [ ] Cancel/expire/revoke subscription: entitlement loss gates new work while history stays readable/exportable.
- [ ] Restore and reinstall: Apple-account purchases restore; reinstall does not reset introductory eligibility.
- [ ] Existing Individual/Family lifetime and qualifying original paid-app ownership retain access.
- [ ] Lifetime fallback after subscription expiration; subscription-only users cannot buy the discounted lifetime Family upgrade.
- [ ] Individual → Family subscription change does not create concurrent subscriptions in different groups.
- [ ] Background/keyboard/Watch/Shortcuts entry points respect the same access state.
- [ ] iOS and Mac: native purchase-cancel/error paths, successful capture to a writable destination, history export, offline behavior.
- [waived by owner] Fresh second-account subscription Family Sharing. Existing Family Sharing is reported working; no new cross-account test was performed here.

Local automated evidence already covers core entitlement, expiration/fallback, paywall/history separation, and export cases; see transition status for counts, skips, and host restrictions.

## Review and release sequence

1. **Done:** agreement resolved and concrete readiness issues checked/fixed. Existing exact drafts retained; no duplicate products/groups/submissions.
2. **Done:** all 700 subscription prices/offers and availability, sharing, metadata/assets and 525 unchanged lifetime price records verified before submission, and pricing rechecked afterward.
3. **Done:** submitted iOS `a8b73b42-df07-4283-a32a-169ed629a741` at 22:26:23 UTC (six items) and Mac `cfc0848f-82ac-48f2-a502-0418c3ec720f` at 22:26:30 UTC (one app item). Both WAITING_FOR_REVIEW. Monitor these exact submissions; do not submit duplicates or release approved versions automatically.
4. After approval and release QA, ask the owner for the explicit public-release go-ahead. Coordinate both platforms; if only one is approved, wait unless the owner changes scope.
5. At public release, check the signed production builds, real StoreKit product loading/locale prices/trial eligibility, purchase/restore entitlement delivery and history access. Real charges require separate permission; do not make purchases merely to smoke-test production.
6. Publish the prepared website/support patch only at the owner-approved release point. The patch uses current Apple lifetime prices rather than prematurely advertising the later proposed lifetime increases.
7. Collect production evidence, then request a separate go-ahead before any lifetime/upgrade repricing. Approval of this runbook, product review, or app release is not repricing permission.

## Unpublished website bundle

`scripts/stage-hard-paywall-website.py` generates `website.patch`, four staged files, and source/staged hashes here. It never edits `website/` or invokes deployment. `git apply --check docs/launch/hard-paywall/website.patch` passes against the current source.

The staged copy removes obsolete free allowances/no-subscription claims, describes all plan types and eligible trials, adds billing/cancellation information, preserves old purchases, and explains unpaid history access. New numeric lifetime targets are deliberately absent. Support responses below are also drafts until release.

Before eventually applying/deploying, recheck the source hashes and patch, run website/link checks, ensure the public app is actually available, then use the existing website deployment process only with release authorization. Never deploy the `docs/launch` directory as a website.

## Support responses — release drafts

**Why am I seeing a paywall?**
New Capture and transcription now require paid access. You can choose Individual or Family, with weekly, yearly, or lifetime options. Eligible subscriptions offer a seven-day trial. You can still view and export your existing history without buying anything.

**I already bought Vox.md. Do I have to subscribe?**
No. Existing lifetime purchases remain valid, as does access for qualifying original paid-app owners. Use Restore Purchases with the Apple Account used for the purchase. If access is missing, contact support with the app version, platform, and purchase type; never send passwords, full receipts, payment-card information, audio, or private notes.

**Will canceling delete my history or exported files?**
No. Existing history can still be viewed and exported, and files already saved to your folders remain yours. New Capture and transcription require active paid access.

**How do I cancel a trial/subscription?**
Use Apple's subscription-management settings for your Apple Account. Cancel a trial at least 24 hours before it ends to avoid renewal. Apple displays the renewal terms before confirmation and handles billing/refund requests. Deleting the app does not cancel a subscription.

**I bought lifetime access while subscribed.**
Lifetime access does not automatically cancel an existing Apple subscription. Manage or cancel the subscription separately in Apple Account settings.

**Why don't I see a trial?**
Apple determines introductory eligibility across the shared subscription group. Changing plans or reinstalling does not necessarily make an account eligible again. Lifetime purchases do not include a trial.

**How does Family work?**
Family plans use Apple Family Sharing. Check that purchase/subscription sharing is enabled for the purchasing Apple Account's family group, then restore purchases on the receiving account. Do not ask a family member to share an Apple password.

## Monitoring and rollback

Monitor aggregated paywall views, purchase outcomes, restores, and coarse error categories by platform/build/product; never inspect/store note text or audio. Current onboarding telemetry is not a complete subscription-renewal/churn ledger: app-side purchase success is not proof of a later paid renewal or retained revenue. Use Apple subscription/sales reporting for those measures.

Example read-only aggregate query:

```sh
cd worker/onboarding-analytics
wrangler d1 execute voxboard-onboarding-analytics --remote --command "SELECT platform,app_version,product_id,purchase_outcome,error_category,COUNT(*) AS events FROM onboarding_events WHERE received_at >= '2026-10-29' GROUP BY platform,app_version,product_id,purchase_outcome,error_category;"
```

If product loading, entitlements, restores, or paid-user preservation fail, stop rollout/public promotion, keep lifetime prices frozen, gather coarse failure evidence, and prepare a tested fix. App Store releases cannot be instantly rolled back to an older binary. Do not delete products, purge user content, revoke legitimate purchases, or change lifetime prices as a rollback shortcut.

Previous analytics version: `f41053e5-a1d7-4a92-87a2-1c559a8e32e5`. A Worker rollback is possible with owner authorization, but reverting this product allowlist will reject new-plan analytics. Do not roll it back automatically in response to app purchase errors; the Worker is not the entitlement authority.

## StoreKit CI runtime

The complete `HardPaywallStoreKitTests` class runs in the `storekit-tests` job on released Xcode 27.1 with its matching iOS simulator. This includes catalog/trial/family, purchase/refund, expiration/lifetime, onboarding, and paywall layout assertions. Other app-hosted iOS regression tests retain the existing Xcode 26.6 / SDK-matched baseline. No tests are dropped from the overall workflow.

This isolates the iOS 26.5 CLI StoreKit configuration failure tracked in [Apple's FB22237318 discussion](https://developer.apple.com/forums/thread/826971). The 27.1 fixture uses the same unmodified prices and product IDs. CI builds are verification artifacts; they do not submit, release, deploy, or change App Store pricing.
