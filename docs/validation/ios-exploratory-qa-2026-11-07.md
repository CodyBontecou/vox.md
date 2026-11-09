# iOS exploratory QA November 7 2026

Argent exploratory testing found two usability failures and incomplete Turkish localization in Vox.md 3.0 (59). The installed app ran on the iPhone 18 Pro Max simulator, iOS 27.0, with existing Turkish sample routes and library entries. No app source was changed. Findings below are live observations supported by screenshots and targeted source inspection.

## Findings

### Destination validation errors appear offscreen

Priority: P2. Reproduced twice.

1. Open Settings → Routes, add a temporary route, and open Deliver → Set Up Destination.
2. Leave the folder unselected. Tap Save while the form is at its initial scroll position.
3. Observe that the sheet remains open with no visible error or movement.
4. Scroll to the bottom: the Error section now says to select a vault or folder.

Expected: make the validation failure visible immediately, such as an alert or scrolling to the invalid folder control. Actual: Save looks unresponsive until the user discovers the error at the bottom of the long form. The same behavior occurred after entering `../../outside/{unknown}.md`; missing-folder validation runs first, so this does **not** establish a path-validation bypass.

Source: `Voxboard/Views/CaptureDestinationLibraryView.swift`, error section near line 525 and `save()` near line 685. The error section is appended after Delivery; Save only assigns `errorMessage`.

Evidence: [after Save](../../artifacts/validation/ios-exploratory-2026-11-07/destination-save-no-feedback.png), [error revealed by scrolling](../../artifacts/validation/ios-exploratory-2026-11-07/destination-error-offscreen.png).

### Search in Obsidian silently fails when Obsidian is unavailable

Priority: P2. Two taps on the stable empty-search screen produced no navigation, explanation, or fallback.

1. Open Activity → Library and search for `QA_NO_MATCH_927`.
2. In the empty state, tap Search in Obsidian on a simulator without an available Obsidian handler.
3. The screen stays unchanged.

Expected: explain that Obsidian cannot be opened, or offer an actionable fallback. `HistoryView.swift:363` calls `openURL(url)` without inspecting whether it was accepted. In comparison, `CaptureDetailView.swift:582` checks acceptance and falls back to sharing the delivered Markdown file. That detail-screen fallback opened successfully in this run.

Evidence: [search with no feedback](../../artifacts/validation/ios-exploratory-2026-11-07/obsidian-search-no-feedback.png), [working detail fallback](../../artifacts/validation/ios-exploratory-2026-11-07/obsidian-open-fallback.png).

### Turkish UI contains untranslated and incorrect text

Priority: P3. Observed across route setup, attachment, and recovery screens.

- Invalid URL delivery endpoint `javascript:alert(1)` is correctly rejected, but the error is English: “That does not look like a valid URL.” The literal originates in `Packages/VoxboardShared/Sources/VoxboardShared/CapturePresetURLDeliverySettings.swift:126`.
- The Turkish attachment sheet still displays “RECENT”, “Tap to pick one or more”, “READ INTO MARKDOWN”, “Journal page”, “Camera or photos”, and the Photos-denied explanation in English.
- Queue settings show “Failed recordings stay here until you retry or delete them.” in English.
- Route-editor Done displays “Dona”; destination Save displays “kurtarma”. These labels need Turkish language review as well as extraction coverage.

Evidence: [URL validation](../../artifacts/validation/ios-exploratory-2026-11-07/url-error-english.png), [attachment sheet](../../artifacts/validation/ios-exploratory-2026-11-07/photo-denied-localization.png), [destination toolbar](../../artifacts/validation/ios-exploratory-2026-11-07/destination-save-no-feedback.png).

## Checks that passed

- Existing capture text and selected route survived settings, library, detail, and queue navigation, plus app restarts.
- Temporary route creation, rename, and deletion worked. Deletion removed its extra keyboard/Watch route from the Settings summaries.
- Cancelling the folder picker returned to the destination form. Cancelling destination edits discarded the invalid path.
- Selecting English transcription language and then returning to System Language restored the Turkish summary.
- Activity filters displayed appropriate empty states; switching back to All restored delivered entries.
- Library unmatched search, clearing search, route filtering, and pasted Turkish uppercase `İYİ` worked. The uppercase query matched the body `İyi uyudum.` while the Journal filter was active.
- Library detail showed the written note and route log. Open in Obsidian fell back to a share sheet when the handler was unavailable.
- Queue Manual mode updated its summary and survived restart. Restored Immediately afterward; permanent audio retention was unchanged.
- Denying Photos access showed a recent-photo explanation. All Photos still opened the system picker. Selecting a photo then cancelling added no attachment and preserved the original draft.
- Capture Link rejected a non-HTTP scheme with a visible localized error banner. No capture was submitted and no URL-delivery test request was sent.

## Final state and scope

The temporary `QA Edge Route` was deleted. Original routes, capture draft, System Language transcription choice, Immediately queue mode, and permanent audio retention were restored. Photos authorization was reset to its original not-yet-asked state through Argent. The app was left on Capture with the Turkish UI and the debug screenshot unlock used to reproduce its initial state.

A plain restart initially removed the previous process's language/unlock overrides, exposing English read-only capture. This was treated as debug-launch configuration, not an entitlement regression. Final launch arguments are recorded in [environment.json](../../artifacts/validation/ios-exploratory-2026-11-07/environment.json).

This was a one-off exploratory pass, not a saved regression suite. No crashes or draft loss were observed. Physical audio/model execution, successful file import, network delivery, and path validation with a selected folder were not established by this pass.

Final capture evidence: [restored draft](../../artifacts/validation/ios-exploratory-2026-11-07/restored-capture.png).

## Fix verification November 7 2026

All three findings were fixed and checked on the rebuilt iPhone 18 Pro Max simulator app.

- Destination errors now use a dismissible alert, visible at the initial form position. Save without a folder displayed the localized error immediately; dismissing and retrying displayed it again. The final Turkish alert uses “Hedef Hatası” and “Tamam”, and the form uses “Kaydet”. [Alert evidence](../../artifacts/validation/ios-exploratory-2026-11-07/fixes/destination-alert.png).
- Library search checks whether opening the Obsidian URL succeeded. When no handler accepts it, Library Error explains that Obsidian must be installed to search the vault. The query remains intact after dismissal. [Search evidence](../../artifacts/validation/ios-exploratory-2026-11-07/fixes/obsidian-search-alert.png).
- URL validation errors now use localized strings. Turkish translations were added for the affected attachment labels, Photos-denied explanation, queue retention explanation, and URL validation errors. Done, Save, OK, Dismiss Error, and the folder-required message were corrected. Existing translations in other locales were preserved. [Attachment evidence](../../artifacts/validation/ios-exploratory-2026-11-07/fixes/attachment-turkish.png), [queue evidence](../../artifacts/validation/ios-exploratory-2026-11-07/fixes/queue-turkish.png), [invalid URL evidence](../../artifacts/validation/ios-exploratory-2026-11-07/fixes/url-validation-turkish.png).

Validation: signed Debug iOS simulator build passed. Existing `URLDeliveryValidationTests` passed all 8 tests with zero failures. [Test output](../../artifacts/validation/ios-exploratory-2026-11-07/fixes/url-validation-tests.log). `git diff --check` passed. Catalog checks confirmed all 25 changed entries have Turkish translations and preserve existing other locales. UI behaviors were verified live with Argent; no new saved e2e suite was created.

The initial unsigned build lacked App Group access. Verification continued with a signed build using the app’s entitlements and re-seeded Turkish demo routes/library. Demo history therefore contains additional sample deliveries; this run is not a migration or upgrade-preservation test. The temporary route was deleted and Photos permission reset. Final app launch omits the seeding flags and leaves Capture open with the Turkish demo draft. [Final capture](../../artifacts/validation/ios-exploratory-2026-11-07/fixes/final-capture.png).
