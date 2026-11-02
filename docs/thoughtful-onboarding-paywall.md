# Thoughtful onboarding and paywall — local design iteration

## Status and boundaries

Implemented locally for design review. **Not uploaded, submitted, published or released.** The existing 2.14 (58) review submissions were not withdrawn or replaced. Manual release, existing-purchase preservation and the lifetime/upgrade price freeze remain unchanged. The in-app What's New slider and deployable website were not edited for this redesign.

This is a visual/interaction first pass, not a claim of completed production/device QA.

## Direction

Reference: https://kevintngo.com/ — observed its paper-like neutral canvas, blue pen drawings, editorial serif headings, quiet spacing and unhurried presentation. Borrowed that sensibility, not its illustrations/assets, bird animation, navigation or page layout.

Additional research: twelve public App Store presentation screens from Bear, Day One and Apple Journal. Their product/UI examples informed clear writing surfaces, compact hierarchy and privacy/ownership language. These are marketing/listing references, not a claim of access to their private onboarding/paywall flows. Sources and a contact sheet are in `docs/evidence/thoughtful-design-20261029/research/`.

### Visual rules

- Existing charcoal/blue identity, with a slightly warmer local neutral family: light canvas `#e8e6e2`, paper `#f5f3ef`; dark canvas `#1d1c1b`, paper `#282725`.
- Geist body/control fonts retained; native system serif for complete editorial headings, not isolated decorative words.
- Original SwiftUI vector note/branch illustration; no copied site artwork or raster assets. Existing adaptive blue900 supplies the ink.
- Native navigation, segmented control and sheet behavior. Paper groups use 16-point continuous corners; existing Geist action style remains consistent.
- No gradients, fake social proof, invented savings/popularity badges, confetti, new accent family or decorative continuous animation.

## Flow

1. **Catch a thought. Keep it close.** A small, explicitly labeled example note introduces the product without pretending to be user content.
2. **Your words. Your own space.** Explains local transcription, user-selected folders/Markdown and continued history access.
3. **A home for every thought.** Individual/Family selector, three compact plan rows and one purchase action for the selected plan. At standard type sizes the action stays anchored above the home indicator; at accessibility type sizes the checkout moves into the scrollable document so a giant fixed footer cannot obscure the plan choices.

Onboarding has native Back between its two pages, a persistent Continue action, and View plans to skip the introduction without bypassing the paid-access gate. The completion flag is local UI state, separate from entitlements; completing or skipping never unlocks Capture. Completing the introduction replaces its navigation stack with the paywall, so edge-back cannot re-enter it. Existing unlocked users bypass the root gate as before; settings paywalls do not force onboarding.

History remains available from the real gated onboarding/paywall when its view model is supplied. Restore stays prominent on the plan screen. The read-only history route preserves search/read/copy/export/delete while new work and edits/retries remain gated.

## Purchasing safeguards

- Product IDs, entitlement logic, trial eligibility, expiry/refund handling and legacy ownership migration were not rewritten.
- Prices come from StoreManager/Apple, not production hardcoded amounts.
- Weekly/yearly/lifetime remain explicit. Selection carries the same duration across Individual/Family. Lifetime-upgrade eligibility still reduces the offers to the legacy upgrade only.
- One selected-plan CTA; honest eligibility-aware trial vs Subscribe vs Buy Lifetime labels.
- Selected-plan price and billing period are adjacent to the CTA, including automatic renewal or one-time/no-subscription wording. Lifetime has no trial. Legal/subscription-management disclosures remain available; buying Lifetime or deleting the app does not cancel an existing subscription.
- Selection is disabled during purchase/restore so the visible selected plan cannot change under an in-flight checkout. Purchase identity is captured before scheduling the task.
- Unavailable products cannot be bought; loading/error/retry and restore states remain supported.
- Paywall analytics moved to the actual plans presentation, rather than counting the introductory pages as paywall views.

The visual StoreKit fixture intentionally uses the **still-frozen US lifetime prices** ($19.99 Individual, $39.99 Family, $19.99 upgrade). The separate future-target catalog assertions remain intact. This temporary test fixture is removed during teardown and does not change live pricing or the bundled catalog.

## Source

- `Voxboard/GeistTheme.swift`: isolated Thoughtful tokens, original vector artwork and shared native introduction. The shared file is already compiled by both app targets; the existing global Geist palette is untouched.
- `Voxboard/Views/PaywallView.swift`: iOS selected-plan screen, sticky CTA, real history/restore routes, optional introduction.
- `Voxboard/VoxboardApp.swift`: root gate opts into the introduction.
- `Voxboard Mac/MacRootView.swift`: corresponding Mac introduction and compact selected-plan purchase presentation, including responsive introductory sizing and retry support.
- `VoxboardTests/HardPaywallStoreKitTests.swift`: presentation coverage, frozen-price visual fixture and opt-in interactive simulator host.

Existing and concurrent copy/localization edits were preserved rather than reverted. No version/build bump or App Store mutation was made for this iteration.

## Evidence and verification

Final screenshots: `docs/evidence/thoughtful-design-20261029/final/` (welcome/privacy pages, Individual/Family plans, dark mode and accessibility-largest type). `manifest.json` retains exported XCTest attachment provenance. The normal onboarding-only render tests omit a history callback; the real gated flow's clock is verified in the live recording/accessibility checks.

- iOS: **six focused StoreKit/history/presentation tests passed**, zero failures. Covers catalog/pricing/trials/sharing, purchase/refund, expiration/lifetime access, unpaid history export and light/dark/large-type renders.
- Mac: full app Debug build passed. Both shared introduction pages were inspected in a separate, isolated native Mac preview at 620×812, without opening the real Mac app or reading its user data. This verifies the shared intro, not the full Mac StoreKit purchase flow. The temporary preview app was closed afterward.
- Existing pricing/scope/staging Python checks: **20 passed**.
- Native iOS walkthrough: recorded onboarding forward/back, completion, Family selection, weekly/lifetime billing summaries, unpaid history, search typing/keyboard dismissal, sheet close and post-onboarding edge-back. An earlier full replay completed **30 checks/actions**, zero failed/errored (11 echoes excluded), with coordinate warnings. A final-source replay then reached **20 passed and one failed**: search typing ran before the native search field had focus. Its failure capture shows the unmodified empty search field and no keyboard. The typed-value assertion correctly failed rather than silently accepting the missed focus. This is consistent with an automation presentation/focus race; live search and the earlier full replay worked, but the cause still needs a reliable readiness/instrumentation check before sign-off. **The latest replay is not green.** Its JSON is retained as `final-native-replay-result.json` and needs a stronger sheet-identity/keyboard-readiness gate before any CI/QA claim.
- Recording: `native-flow.mov`; sampled filmstrip: `motion-contact-sheet.jpg`. Earlier diagnostic takes are retained separately, not presented as passing final evidence.

### Important replay limitation

`native-walkthrough.yaml` is a **test-host-specific diagnostic fragment**, not a portable CI test or completed QA-e2e contract. XCTest owns the process and local StoreKit fixture, so restarting through Argent to inject native devtools would destroy the fixture. Accessibility checks work, but Argent's separate runner-native tree is unavailable. Consequently the earlier complete replay has **11 coordinate/settling warnings**, kept in `native-replay-result.json`, rather than silently treating taps as semantic selectors. The latest incomplete replay has nine such warnings before its search-focus failure; it is not a release sign-off. Each action was paired with live accessibility outcomes. No purchase was tapped in the interactive walkthrough; the tracker remained locked and the XCTest host passed.

To reproduce the fragment, explicitly run only `testInteractiveDesignPreview` with its documented temporary sentinel, confirm the first introduction page and absence of system dialogs, then run the saved fragment with an explicit simulator id and acknowledged prerequisite. Ordinary test runs skip the opt-in host. Remove the sentinel to finish it cleanly; its 300-second bound prevents an indefinite pause. Do not restart the app while that test owns its StoreKit fixture. No credentials were entered; a simulator-only startup microphone prompt was declined and an empty Apple sign-in prompt canceled during the first setup take. Cleanup reset only this simulator app's microphone permission to its original not-yet-asked state; no device-wide permissions were changed. The opt-in sentinels were removed and the isolated Mac preview was quit.

## Before replacing the reviewed build

- Owner design approval and explicit authorization to withdraw/replace the existing review submissions; then prepare a new build number, not an upload over 58.
- Complete small-phone/iPad and long-localized-currency/layout verification; ensure new copy/localizations are reviewed for fidelity and formatting.
- Full Mac paywall/purchase interaction QA (beyond the compiled app/shared native intro preview).
- Signed sandbox/TestFlight purchasing and restore checks; existing Family Sharing test waiver remains as previously recorded.
- Complete gesture interruption/sheet-drag/Reduce Motion cases and release-build performance measurement on supported hardware. A variable-frame-rate screen recording is **not** evidence of sustained 60fps performance.
- Preserve all existing purchase/history/price-freeze constraints. Design approval is not permission to publish the website, change prices or release apps.

## 2026-10-30 onboarding audit follow-up

The introduction uses three illustrated pages: “A place for the small things,”
“Say it. Keep the thought,” and “Your words. Your own home.” Its final primary
action is **View plans**. At accessibility text sizes, the actions scroll with
the document. Long action labels wrap without reducing the user's text size.

After unlocking, Capture guides the first note through folder selection, writing,
and an actual saved-file confirmation. The iOS shortcut uses the system folder
picker and creates a normal reusable preset destination with a new Markdown note
per Send. Choosing a folder preserves the draft and writes no note. The saved
note opens through native Quick Look while folder access is retained. Returning
users with delivered history bypass the guidance; its completion preference is
separate from purchase access and toolbar preferences. Mac retains its existing
folder setup and gains the same writing/saved guidance; a local transcription
model and microphone permission are optional for starting with typed notes.

Microphone permission is requested on the first explicit Record action, with an
Open Settings recovery action after denial. A suspended request rechecks the
active draft, preset, route and paid-access guards before recording; backgrounding
or leaving Capture cancels the pending start. Purchases, product IDs, pricing,
restore and the root paid-access gate are unchanged.

Verification: StoreKit/access/history checks, Capture rendering checks and two
isolated first-note routing/file-write tests pass. Compact 320×568 renders cover
all three introduction pages at the largest accessibility size, including their
scrolled actions. Layout assertions prevent the intro footer from consuming the
reading area and the editor from collapsing the first-note guide. Light/dark
introduction snapshots and all three first-note states are retained in XCTest.
The Capture structure checker and Mac Debug build pass.

Two opt-in simulator previews exercised folder creation/selection, typing, Send,
and opening the resulting Markdown file. Both checked the written file contents
and unchanged microphone permission. The writer was isolated/unmetered and access
came from StoreKitTest; this is not a production purchase or signed-device test.
The recorded Argent fragments are diagnostic only: XCTest owns the app process,
so native runner selectors were unavailable, and the live path needed coordinate
and keyboard-focus recovery. They are not portable CI tests or release sign-off.
No release, website deployment, price change or analytics collection was added.

### Approved illustrated onboarding refinement

The owner selected the illustrated design originally previewed from worktree
`f130`. Its shared theme and three onboarding pages are preserved here. The
notebook, window and botanical pen artwork continues behind the transparent
footer. Continue and View plans occupy the right half of the action row; Back
is plain text on the left after the first page. Accessibility sizes stack the
actions to preserve readable labels. The native top back button and
top-right View plans shortcut are hidden.

The account tagline and explanatory example captions were removed at the owner's
request, including the final folder card's post-plan instruction. The spoken
example remains interactive and does not record audio or save a file. The paid
access gate and first-note setup after unlocking are unchanged.

The preferred design and final copy were built and inspected live on the
“Vox Paper Ink QA” simulator. Forward and bottom-back navigation were exercised.
The separate staged QA launcher used for that simulator is not part of the app
source changes in this branch. No app release or website publication is included.

Final-source verification before push: 28 tests passed (26 XCTest cases and two
Swift Testing cases); two interactive preview hosts were skipped as intended.
The Mac Debug build and Capture structure checker (14 fixtures) passed. A final
small-phone screenshot exposed excessive wrapping in the half-width forward
button at the largest text size; accessibility actions now stack at full width.
