# Authorized subscription preparation evidence

Current summary: `docs/subscription-transition-20261029.md` (repository root-relative).

Latest follow-up: the owner accepted Apple's agreement; its browser warning disappeared. After fresh readiness/price-freeze checks, five passing local StoreKit/history tests and corrections to 14 obsolete draft privacy links, **both 2.14 (58) submissions and all four subscriptions are WAITING_FOR_REVIEW**. iOS submitted October 29 at 22:26:23 UTC, Mac at 22:26:30 UTC. Both retain MANUAL release; no release occurred. See `review-submission/` for submit receipts, final state/build readbacks, QA log and link-fix evidence. The in-app What's New slider and deployable website remain unchanged; lifetime/upgrade prices remain frozen. Membership renewal is still due November 3.

This is the later, owner-authorized **write preparation** phase, distinct from the earlier read-only regional proposal. New subscriptions, their prices/trials/availability/metadata/assets, draft review items, draft app versions, and build uploads were prepared. Existing lifetime/upgrade pricing was not changed. The latest follow-up submitted the two existing review drafts; neither app version has been released.

Start with:

- `verification.json`: fresh raw readback checks for 700 subscription prices, 700 one-week free offers, 700 availability entries, access levels/Family Sharing, and 525 unchanged existing lifetime price records.
- `subscription-regional-prices.csv`, `*-prices.csv`, `pricing-plan-summary.json`: configured subscription prices and exact product-specific Apple point IDs.
- `parity-overrides.json` and `family-weekly-*-parity-*`: six rounding collisions corrected to preserve a positive Family weekly premium. The local ladder evidence and individual-price × US premium-ratio target are retained.
- `lifetime-freeze/`: before and after raw non-consumable price envelopes, matched by complete price-point IDs. No lifetime mutation request bodies exist.
- `*-prices-verified.json`, `*-offers-verified.json`, `*-available-territories-verified.json`, `*-product-verified.json`: authoritative current subscription readbacks.
- `commands.jsonl`: subscription preparation helper command journal, including commands logged before execution. `.error.txt` files retain rejected/partial operations and rate-limit responses; per-territory trial receipts and final full-list readbacks show successful reconciliation without duplicate offers.
- `builds-final.json`, `versions-final.json`, `*-build-upload.json`, `build-artifact-checksums.json`: processed VALID 2.14 (58) builds, manual-release settings, build attachments, upload receipts, and local IPA/PKG hashes.
- `project-settings-verification.json`: version-tool formatting changed presentation, but parsed project settings match the baseline plus exactly the intended 2.14/58 changes across 14 configurations.
- `review-screenshots/`, `*-screenshot-final.json`, individual review screenshot receipts: inspected UI captures and COMPLETE App Review asset delivery. Consumed upload-operation capabilities were removed from saved screenshot GET responses; no browser cookies or auth headers are stored.
- `history-read-export-ui/`: inspected unpaid-history rendering from a passing XCTest that also exported an existing transcript without unlocking usage.
- `review-submission/*-submission-after.json` and `*-version-after-submit.json`: latest WAITING_FOR_REVIEW submissions/versions and preserved manual release. `ios-review-items-approved-copy.json`, `ios-review-items-included-approved-copy.json`, `mac-review-items-approved-copy.json` capture the earlier pre-submit drafts. iOS now has six items (app + group + four subscriptions), Mac has one app item; all READY_FOR_REVIEW. The older draft/failed-attachment files document the earlier missing-whatsNew error, now resolved.
- `listing-copy-proposed.json`, `listing-copy.diff`, `pricing-copy-translations.json`: original proposal snapshots. Their original approval-status labels are historical, not current. `listing-application/owner-approval.json` pins the subsequently approved proposal hash; `listing-application/verification.json` proves all 78 listings applied exactly and unrelated fields unchanged. No in-app release-note file was changed.
- `mac-readiness-approved-copy.json`: zero public-API errors after copy approval. Its web-session checks remain CLI-unverified because that cache is distinct from authenticated Pi Browser. `web-readiness-observations.json` records the actual browser findings (published privacy, six/one draft items, updated agreement requiring owner acceptance, renewal warning); `analytics-deployment/` records the authorized live deployment and zero-insertion smoke tests. Older `mac-readiness-deep.json` captures the earlier preparation state. iOS validator errors are retained separately; the editable age rating was read by explicit app-info ID.
- `sha256-manifest.json`: saved evidence hashes, excluding the manifest itself.

Empty stdout from failed/interrupted CLI commands is preserved as `.empty-stdout.txt`, not represented as valid API JSON. Current readbacks, not filenames implying an operation was attempted, determine completion. The Family yearly price-import coordinator was stopped after all 175 prices were independently reconciled; its receipt explicitly says it was reconstructed from that readback, not from a fabricated API response.

Safe read-only verification:

```sh
python3 scripts/prepare-vox-subscriptions.py --verify
python3 -m unittest discover -s scripts/tests -p test_subscription_transition.py -v
```

Re-verification refreshes local response files; regenerate the evidence hash manifest afterward. Mutation stages require explicit flags and are not needed to inspect this preparation. Never use the older proposed lifetime tables as an apply request: the existing-price freeze remains in force.
