# Vox.md hard-paywall privacy review

**Unpublished candidate review. No deployment, submission, release, price change or remote data deletion.**

The iOS/Mac shared collectors and capture/model/permission/usage-bucket instrumentation are removed. Local capture delivery ledgers and recovery state are functional local data and remain. StoreKit, user-selected destinations, optional speech-model downloads and quote requests remain; providers may receive ordinary connection metadata. The submitted 2.14 build is unchanged and must not be described as this replacement candidate.

## Shared removal policy

The candidate contains no custom analytics client, event queue, upload job, persistent analytics identifier, pricing-experiment assignment or app advertising-attribution collector. Debug flags and bundle/environment endpoints cannot re-enable the removed implementation. Upgrade cleanup removes known analytics-only local state while preserving purchase entitlements, local content, export history, scheduling identities and app settings used by essential features.

The analytics-only Worker is replaced locally with a storage-free retirement responder: legacy uploads receive HTTP 204 and are discarded without reading the body. No D1/KV binding, analytics cron, aggregate generation or analytics retention mechanism remains in the candidate Worker. The abandoned opt-in/30-day event design is superseded and its unapplied migration is removed. Historical applied migrations remain as provenance. No migrations or remote deletions were executed.

## Older versions and existing records

This is an unpublished source change. Previously distributed binaries, submitted builds and deployed services remain unchanged and can still send/accept analytics. No claim that collection has stopped in production is approved here. Retained installation-linked events are pseudonymous, not anonymous. Updating or uninstalling does not erase previously received events, operator exports, provider logs or recovery copies.

After separate owner approval: deploy the discard responder first, confirm writes have stopped, erase the dedicated analytics database and analytics-only exports, review processor logs/recovery retention, and record actual deletion/expiry evidence. Inspect ownership before deleting resources. Do not reassign analytics identifiers to essential services. A new signed app candidate and an approved cutover are required before the replacement policy becomes effective.

## Essential services and review decisions

Purchase validation/restoration, scheduling, provider authorization, selected file/API destinations, local diagnostics and support remain governed by their actual purpose and existing implementation. They must not gain product-event logging. Removing analytics does not establish a new retention or deletion guarantee for those services. Do not claim universal “Data Not Collected,” “anonymous,” “no servers,” or deletion on uninstall.

Before submission, review App Privacy / Play Data Safety for the exact candidate and every essential processor. Remove analytics purposes only where no remaining collection supports them; retain App Functionality declarations for applicable identifiers, purchase verification and scheduling. Verify provider logs, account linkage, legal URLs and native-language text. No questionnaire or store metadata was changed remotely. Prices and product IDs are unchanged. Myself.md claim entry points remain disabled; earlier retained grants need their existing disclosure.

Website traffic measurement is separate from in-app collection and remains disclosed under the website policy. No website measurement exemptions are asserted by this change.

## Prepared candidate cutover

Candidate 2.14 (59) is prepared from committed current source. Physical-device, Apple sandbox-account and multi-account testing are deferred by the owner; simulation and compilation are not represented as those checks. Public policy/terms and App Privacy publication remain held. The staged policy applies to this candidate when released and preserves earlier-version and historical-record disclosures.

The candidate has no custom event collection. Prepared store copy and policy explicitly cover user-configured HTTP text/transcript delivery, Keychain-held endpoint credentials, local recovery, model downloads, quotes, and Apple reverse geocoding. These are distinct from developer analytics. The candidate questionnaire proposal removes the analytics-only User ID, Purchase History and Product Interaction declarations after retirement; it conservatively discloses ordinary provider connection metadata as Other Data Types for App Functionality, not linked and not used for tracking. Do not substitute a blanket Data Not Collected claim. Apple-only billing data is not developer collection.

The current published questionnaire remains accurate for older clients while their collector is live. Do not publish a reduced declaration or claim that historic data is erased before the coordinated service cutover. No Worker deployment, database deletion or questionnaire publication is included in candidate preparation.

The final App Store description and staged terms distinguish eligible seven-day trials, auto-renewal, immediate one-time Lifetime billing, cancellation in Apple Account settings, existing paid rights, and Family access versus private content. No live lifetime price or regional schedule is changed. New Mac listing translations are machine assisted and checked mechanically; native-language sign-off is not claimed.

Reference: [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
