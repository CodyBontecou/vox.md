# Android Application: iOS Functionality and UI Parity Plan

Status: **Proposed execution plan**

Planning date: **2026-09-12**

Current repository baseline: `4dba398` plus the present working tree. The working tree is not clean, so implementation must record a clean, reviewed baseline before changing persisted contracts or claiming milestone completion.

Related authorities:

- `docs/featureset/featureset.md` — consolidated shipped-product registry
- `docs/featureset/inventory/ios-ui.md` — iPhone/iPad UI inventory
- `docs/featureset/inventory/keyboard-widget-share.md` — keyboard, share, widget, control, and Live Activity inventory
- `docs/featureset/inventory/watch.md` — Apple Watch behavior inventory
- `Packages/contracts/product-capabilities.json` — machine-readable parity ledger
- `docs/android-wear-shared-core-implementation-plan.md` — shared-core, durability, Android, and Wear architecture program
- `docs/architecture/android-wear-m3-scope-and-entry-audit.md` — current Android implementation status

## 1. Goal

Ship a production Android phone/tablet app, Android system entry points, Android IME, and Wear OS companion that provide the same user outcomes, capture fidelity, privacy guarantees, recovery behavior, monetization model, and recognizable Vox.md visual language as the shipped iPhone/iPad product.

“Match” has two parts:

1. **Functional parity:** every applicable shipped iPhone/iPad, keyboard, widget/share, and Watch capability has an Android implementation and direct acceptance evidence.
2. **Experience parity:** the Android product keeps the same capture-first hierarchy, information architecture, content density, typography, color system, terminology, state model, and interaction intent while using native Android controls and system surfaces.

The goal is not to reproduce Apple chrome, gestures, or APIs literally. Android back, permissions, pickers, notifications, widgets, predictive back, large-screen behavior, and accessibility must feel native to Android.

macOS-only features such as menu-bar operation, global desktop hotkeys, ScreenCaptureKit meeting capture, and desktop window modes are outside this plan. They are not iOS parity requirements.

## 2. Current state

The repository is not starting from zero:

- The feature inventory is complete and evidence-backed.
- The capability ledger contains **271 rows**: **29 verified** and **242 inventoried** at this planning point. “Verified” does not mean the Android product is shipped; it mostly represents completed cross-platform contract/core work.
- M0 baseline stabilization, M1 contracts, and M2 Rust/UniFFI proof are complete.
- M3 has working durable-package, Room, quota, Rust bridge, prepared-plan, and SAF executor foundations, including one Pixel 7 local-provider end-to-end instrumentation pass.
- The Android app UI is currently a deliberate placeholder. `MainActivity.kt` exposes unavailable screens and a bottom navigation scaffold; there is no end-to-end user capture flow.
- Voice, multimodal capture, presets UI, history/stats UI, Android entry points, IME, Wear, Billing, localization, and advanced local intelligence remain unshipped.

This plan continues M3. It does not replace the existing ADRs, contracts, durability rules, or shared Rust strategy.

## 3. Product parity rules

### 3.1 One source of truth

`Packages/contracts/product-capabilities.json` is the completion ledger. Each applicable row must include:

- Android owner and milestone
- parity class: `exact`, `native-equivalent`, or `approved-adjustment`
- implementation location
- automated acceptance test
- required physical-device/provider evidence
- visual reference and Android screenshot/golden when user-visible
- status: `inventoried`, `implemented`, `verified`, or `released`

No broad ticket such as “build settings” or “add voice” can close multiple rows without row-level evidence. A deferred or unavailable row is not parity.

### 3.2 UI parity standard

Preserve:

- capture as the root screen; no persistent tab bar
- secondary destinations pushed from Capture: History, Settings, Models, Capture Presets, and App Language
- the editor-first layout and bottom-aligned preset, route, primary action, microphone, keyboard, and capture-tool controls
- Geist and Geist Mono typography
- the existing 4-point spacing scale, radii, control heights, neutral surfaces, blue focus/accent, red error/recording, amber warning, and green success roles
- compact, text-forward cards and rows; the same labels and hierarchy wherever translation permits
- light and dark appearance, large text, RTL, loading, empty, permission-denied, quota, retry, and failure states

Translate natively:

| Apple surface | Android implementation |
| --- | --- |
| SwiftUI `NavigationStack` | Compose navigation with predictive-back support |
| Sheet / popover / alert | Material 3 bottom sheet, dialog, or full-screen task according to interaction intent |
| SF Symbols | One consistent Material Symbols family with matched semantics and optical weight |
| Photos picker | Android Photo Picker |
| Files/folder pickers and security-scoped bookmarks | Storage Access Framework documents/tree picker with persisted URI grants |
| VisionKit document scanner | On-device Android scanner flow; ML Kit document scanner where available, with an explicit unsupported/fallback state |
| Vision OCR | Bundled or pre-provisioned on-device text recognition; never an implicit network path |
| PencilKit | Compose/Android drawing canvas with pressure/stylus support where available and deterministic PNG/source export |
| Live Activity / Dynamic Island | Ongoing recording notification plus lock-screen actions and app status surface |
| Control Center controls | Quick Settings tile and app shortcuts |
| App Intents / Shortcuts | explicit intents, deep links, static/dynamic shortcuts, and Assistant-compatible surfaces where policy permits |
| Share Extension | exported receive activity for `ACTION_SEND`, `ACTION_SEND_MULTIPLE`, and supported text/process intents |
| iOS custom keyboard | `InputMethodService`, with the approved visible capture activity fallback |
| StoreKit lifetime purchase | Google Play one-time non-consumable purchase |
| WatchConnectivity | Wear OS Data Layer with the versioned wearable protocol |
| Watch widget/complication | Wear Tile and complication |
| Apple Speech | explicitly on-device Android recognizer when available; app-owned local ASR remains the dependable baseline |
| Apple Foundation Models | app-owned local enrichment and diarization models, gated by device capability |

Platform translation must never alter the produced Markdown, lose a supported payload, weaken durability, or introduce undisclosed cloud processing.

## 4. Target product structure

Keep the existing module direction and add feature packages without moving the Apple project:

```text
apps/android/
  app/                Compose UI, navigation, Android entry activities
  capture-domain/     use cases, repositories, state machines, domain models
  data/               Room, DataStore, app-private packages, SAF, WorkManager
  platform-services/  recorder, local ASR, camera, OCR, location, billing, share/IME helpers
  core-bridge/        generated UniFFI binding plus fail-closed Kotlin adapter
  wear/               Wear Compose app, recorder, Tile, complication, Data Layer
```

Within `app`, organize UI by feature (`capture`, `presets`, `history`, `models`, `settings`, `billing`, `recovery`) with one state holder/ViewModel per screen or cohesive flow. UI consumes immutable state and emits events. It must not know SAF URIs, Room entities, Rust JSON, or platform-service implementations.

State ownership:

- Rust: deterministic validation, path planning, templates, frontmatter, Markdown materialization, hashes, and operation IDs.
- Kotlin domain: orchestration, use cases, recovery decisions, state machines, and repository interfaces.
- Android data/platform: Room, durable files, URI grants, provider commits, WorkManager, audio, inference, permissions, billing, widgets, IME, and Wear transport.
- Compose: presentation state only.

## 5. Navigation and responsive layout

### Phone

```text
Quick Capture (root)
  -> History -> Transcript detail/edit/export
  -> Settings
       -> Models -> Language / Auto-stop
       -> Capture Presets -> Preset editor
            -> Destination library/editor
            -> Entry template library/editor
            -> Location/metadata/voice/processing settings
       -> Capture Bar customization
       -> Recording Queue
       -> Stats
       -> App Language
       -> Upgrade / restore
```

- Back from a secondary screen returns to the exact prior capture state.
- A completed one-way task such as initial vault setup or purchase cannot be re-entered by Back.
- Sheets represent short interruptions; editors and multi-step configuration are destinations.
- Android system back first closes transient selection/search/sheet state, then navigates.

### Tablet/foldable

- Keep Quick Capture visually dominant and immediately editable.
- Use list-detail panes for Presets, History, and Settings only at expanded widths.
- Do not introduce a permanent navigation rail merely because space exists; the iOS product is intentionally capture-first.
- Verify split screen, freeform resize, portrait/landscape, fold posture, hardware keyboard, mouse, and stylus.

## 6. Design-system work

Before feature screens, create a small Android Vox design system:

- port Geist/Geist Mono font assets and dynamic type scale
- encode light/dark semantic colors from `GeistTheme.swift`
- encode spacing `4/8/12/16/24/32/40/64/96`, radii `6/12/16/full`, and heights `32/40/48`
- provide Vox buttons, icon buttons, cards, list rows, banners, chips, section labels, segmented controls, progress, editor tool buttons, and recording status components
- require minimum 48 dp Android touch targets even where the iOS visual control is smaller
- support edge-to-edge insets, dynamic color opt-out by default to preserve brand colors, font scale through 200%, high-contrast text, screen readers, switch access, keyboard navigation, and Reduce Motion/Remove Animations
- keep motion restrained: native navigation, immediate press feedback, standard sheets, and recording-state transitions only

Reference images already in the repository:

- `artifacts/app-store-raw-latest/`
- `artifacts/app-store-raw-light/`
- `artifacts/app-language-screenshots/`
- `artifacts/voice-auto-stop-ui/`
- `artifacts/appstore-watch-screenshots/`

Create an Android golden set for the same named stories rather than comparing unrelated screens.

## 7. Delivery phases

### Phase A — Freeze parity and visual contracts

Work:

- Record a clean implementation baseline and preserve the current user changes.
- Reconcile the 271-row capability ledger against the latest working-tree iOS changes.
- Add UI acceptance metadata to every user-visible applicable capability.
- Capture canonical iOS screenshots and short recordings for every primary flow in light/dark, default/large text, empty/content/error/permission/quota states.
- Define platform-equivalence decisions for scanner, OCR languages, drawing-source format, system shortcuts, IME fallback, notifications, local enrichment, and Watch/Wear behavior.
- Turn the design-system values into Android tokens and snapshot tests.

Exit gate:

- Every applicable iOS feature has an Android owner, parity class, milestone, and test/evidence path.
- No unresolved product decision can invalidate M3–M5 architecture.
- Canonical visual stories and interaction recordings are versioned and named.

### Phase B — Finish M3: usable text/link vertical slice

Work:

- Replace the placeholder bottom-nav shell with capture-first navigation.
- Implement onboarding and SAF vault selection/repair.
- Wire the existing durable enqueue, Room index, Rust bridge, materialization coordinator, SAF executor, readback verification, quota transaction, and tombstone flow into production.
- Build the real Quick Capture editor for text and URL payloads, fixed initial preset, route status, Send, local-save acknowledgement, inline error, pending/retry, and minimal History.
- Add WorkManager drain/reconciliation without enabling unreviewed automatic startup behavior.
- Clear/rebase the composer only after the durable package boundary succeeds.

Exit gate:

- Text and link captures work end to end from the app against local storage plus Google Drive and OneDrive providers.
- Process death at every durable transition preserves one recoverable capture.
- Revoked grants lead to repair, not loss.
- Output path and UTF-8 note bytes match Rust/Swift fixtures exactly.
- Capture acknowledgement p95 and startup budgets from the architecture plan pass on the low and current device tiers.

### Phase C — M4: voice recording and transcription

Work:

- Implement the microphone foreground service, notification actions, audio focus/interruption handling, pause/resume/stop/cancel, elapsed time, live level meter, two-second-or-better durable flush, and crash recovery.
- Reproduce tap-to-record, long-press detailed controls, Add to Draft vs Send with Preset, attach-audio, imported audio/video, live transcript preview, transcript result row, and quota UI.
- Implement recording jobs, scheduling policy, retention rules, Retry/Retry All/Process Now, copy/share/delete, and audio-only fallback.
- Use `createOnDeviceSpeechRecognizer` only after an explicit availability check; never use the generic recognizer as a silent fallback because it may stream audio. Integrate and benchmark an app-owned local long-form ASR backend for dependable offline parity.
- Add model downloads, selection, language support, cancellation, storage display, deletion, and VAD/auto-stop.

Exit gate:

- Screen-off, task dismissal, interruption, process kill, reboot recovery-after-relaunch, permission revocation, full disk, and ASR failure preserve a recoverable recording.
- A 60-minute physical-device recording meets loss, memory, battery, and thermal gates.
- No capture audio or transcript reaches a network service.
- Voice UI matches the iOS story set in all states and sustains 60 fps through the full recording flow.

### Phase D — M5: composer, multimodal capture, routing, and presets

Work:

- Add photos, screenshot-only selection, camera, generic files, audio import, multi-page scan/PDF, journal-page OCR to Markdown, sketch source/preview, URL prompt, and one-shot current location.
- Add the horizontal attachment strip and the complete configurable Capture Bar action set: media, files, scan, extract text, undo, Markdown formatting, link, due date, checklist, bullet list, paste, internal link, sketch, location, timestamp, date, and text case.
- Implement the selection-aware editor and undo behavior, long text limits, media budgets, keyboard visibility, focus restoration, and hardware keyboard support.
- Implement Capture Preset list/editor, icon selection, quick-access pins, destinations, new/existing/rolling notes, append/prepend/heading placement, path overrides, templates, metadata/frontmatter, entry formatting, audio rules, location policy, processing mode, speaker labels, and default/enable state.
- Extend Rust contracts in the existing promotion order: rolling notes, existing-note mutation, attachments, templates/frontmatter, then idempotency markers.
- Implement location unavailable retry/cancel/send-once/always behavior and freeze the origin-time result in the durable request.

Exit gate:

- Every F-IU-02 through F-IU-26 and F-IU-30 through F-IU-43 behavior has row-level Android evidence or an approved native-equivalent mapping.
- All payloads survive derived-processing failure with originals intact.
- Existing-note provider races never overwrite changed content and never blindly retry ambiguous commits.
- Swift, Kotlin, and Rust golden outputs agree for all shared operations.

### Phase E — history, stats, settings, billing, localization, and polish

Work:

- Complete unified transcript/capture History with search, filtering, editing, selection deletion, retry, share, reveal-equivalent, and TXT/Markdown/JSON/YAML export.
- Build Stats with totals, duration, attachment counts, seven-day activity, and source breakdown using content-free local data.
- Complete Settings, Models, language, auto-stop, Capture Bar, recording queue, debug/support, privacy, release notes, and app-language screens.
- Add the one-time Play purchase, restore/query on startup and resume, pending/refund/cancel handling, quotas, and store-specific entitlement disclosure. Keep billing traffic isolated from content.
- Localize every shipped string into the product’s supported app languages, including RTL and plural rules; add per-app language APIs where supported.
- Add empty/loading/error/offline/permission/unsupported-device states for every screen.

Exit gate:

- F-IU-27 through F-IU-60 applicable rows are verified.
- TalkBack, Switch Access, 200% font scale, RTL, dark/light, landscape, tablet/foldable, and hardware keyboard matrices pass.
- Purchase state cannot lose, duplicate, or block recovery of user content.
- All content-bearing storage remains excluded from backup/device transfer.

### Phase F — M6: Android entry points and IME

Work:

- Add share receive activity with immediate local copying of temporary URI grants.
- Add stable deep links and static/dynamic/pinned shortcuts for capture actions and presets.
- Add Glance widgets, Quick Settings tile, and complete recording/failure notification actions.
- Build the Vox.md IME with setup education, explicit microphone state, live/final transcript handling, model/preset selection, usage limits, haptics, heartbeat/recovery, and durable pending text.
- Refuse dictation in password/sensitive fields and use a correlation token so stale results cannot enter a different editor.
- Use the approved visible capture activity when OEM/API restrictions make direct microphone capture unreliable.

Exit gate:

- All applicable F-KW rows have acceptance evidence.
- Duplicate/recreated intents enqueue at most one request.
- Share grants are unnecessary after enqueue completes.
- Widget/tile/IME flows obey background and microphone foreground-service restrictions on the supported API/OEM matrix.
- IME recreation, focus loss, editor switch, fallback process death, duplicate result, and stale token tests never insert into the wrong field.

### Phase G — M7: Wear OS parity

Work:

- Add the `wear` module, Wear Compose recorder, durable local queue, pause/resume/cancel, timer, permissions, and failure states.
- Add preset selection and frozen preset snapshots.
- Implement Tile, complication, ongoing activity, and recording notification.
- Implement the existing wearable protocol over Data Layer assets/channels with checksums, resumable frontiers, reconciliation, reassignment, retry, discard, and staged acknowledgements.
- Preserve recordings until the phone has durably ingested them and the configured vault/recording-only boundary authorizes deletion.

Exit gate:

- Every applicable F-WT row passes on a Pixel/reference watch and a Samsung watch.
- Ten queued recordings including one 60-minute recording survive 72 hours disconnected, within the declared storage threshold.
- Kill, reboot, disconnect, duplicate, corruption, reinstall, and unsupported-protocol cases preserve one usable package and an actionable repair path.

### Phase H — M9: local intelligence parity

Work:

- Implement on-device cleanup, title, tags, category, checklist, meeting-note structure, custom instructions, image alt text, and speaker diarization using app-owned local models.
- Define quality, latency, memory, storage, battery, and supported-device tiers.
- Preserve the original capture and use deterministic fallback whenever inference is unavailable or fails.
- Never truncate captured text silently and never send it to a hosted inference service.

Exit gate:

- Every shipped iOS intelligence outcome has an approved local Android implementation and device-tier behavior.
- Unsupported devices receive a clear local fallback without content loss.
- Remaining deferred/unavailable ledger rows block the parity claim unless product scope is explicitly amended.

### Phase I — Production hardening and release (remaining M8/M10 work)

Work:

- Run full security/privacy review, dependency/license audit, SBOM, native-symbol upload, Play Data Safety review, target-SDK/FGS policy review, and backup artifact inspection.
- Complete baseline profiles, macrobenchmarks, startup, Compose recomposition, memory, battery, thermal, and package-size work.
- Run internal, closed, and staged Play tracks with rollback and content-recovery drills.
- Publish support documentation for permissions, vault repair, model repair, recording recovery, billing, Wear sync, and deletion/export.

Exit gate:

- The ledger has no applicable `inventoried`, `implemented`, unavailable, or deferred parity rows.
- Signed phone/tablet and Wear artifacts are reproducible from pinned source.
- Release, downgrade, rollback, provider repair, purchase repair, and data recovery runbooks have been exercised.
- No open data-loss, duplicate-delivery, network-transcription, incorrect-insertion, or Wear-transfer defect remains.

## 8. Cross-cutting test strategy

Every feature PR should include the smallest relevant set:

- pure unit/property tests for reducers, formatters, limits, and state transitions
- shared Rust/Swift/Kotlin golden fixture tests for paths and exact Markdown bytes
- repository tests for package/Room divergence, leases, quota, tombstones, and migration
- Compose semantics tests for behavior and accessibility
- screenshot tests for canonical visual stories on phone, tablet, light/dark, large text, and RTL
- instrumentation for permissions, lifecycle, process death, provider behavior, intents, notifications, and foreground services
- physical-device flows on the named Pixel/Samsung/low-tier/tablet/foldable/Wear matrix
- screen recordings for complete moving flows, reviewed at speed and frame-by-frame

A screen is complete only after verifying default, loading, empty, populated, error, permission-denied, quota-limited, offline, long-content, large-text, dark, RTL, and interrupted-process states that apply to it.

## 9. Recommended implementation order inside each phase

Use vertical slices rather than building all repositories, then all screens:

1. define the capability rows and acceptance tests
2. implement durable/domain behavior
3. add the native platform adapter
4. wire one real screen and its complete state cycle
5. test process/lifecycle failure paths
6. compare screenshots and full-motion recording to the named iOS story
7. run physical-device evidence
8. mark rows verified only after artifacts are retained

The next concrete slice is: **onboarding + SAF vault selection/repair + real text/link Quick Capture + durable local-save acknowledgement + Rust materialization + provider commit/readback + minimal history/retry**.

## 10. Main risks and early decisions

| Risk | Mitigation / decision |
| --- | --- |
| Generic Android speech recognition may use the network | Only admit the explicit on-device recognizer after capability checks; ship an app-owned local backend for dependable offline behavior |
| Foreground microphone launches are restricted | Start recording from a visible user action, declare the microphone service type/permissions, and design widget/tile/IME fallback flows around current platform limits |
| SAF providers vary and commits can be ambiguous | Keep the existing prepared-plan, marker, readback, and reconciliation design; test local, Drive, and OneDrive providers physically |
| Pixel-copying iOS makes Android feel foreign | Match hierarchy, tokens, density, terms, and outcomes; translate controls/navigation/system surfaces natively |
| Scanner/OCR dependencies can download code/models | Make acquisition explicit, document it, provide offline/readiness states, and never claim capture completion before local durable staging |
| IME lifecycle and OEM behavior can misroute transcripts | Use durable session IDs and editor correlation tokens; block sensitive fields; retain visible-activity fallback |
| Local ASR/enrichment may exceed low-tier limits | Benchmark before selection, define model/device tiers, keep originals, and fail to deterministic local behavior |
| Large scope hides unfinished edge states | Gate completion through row-level ledger evidence and named visual/interaction stories |
| Existing user work is present in the repository | Start implementation from a reviewed clean baseline and never overwrite unrelated working-tree changes |

## 11. Definition of parity complete

Android may be described as matching the iOS app only when:

- every applicable ledger row is verified with direct evidence
- every primary iOS visual story has an approved Android counterpart in light/dark and relevant form factors
- all supported capture inputs produce equivalent user-owned Markdown and attachments
- user content is durable before success or UI clearing
- retries are idempotent and ambiguous provider results never trigger blind rewrites
- all transcription, OCR, enrichment, and diarization paths meet the documented local-processing promise
- system entry points, IME, and Wear preserve the same capture and recovery contract as the main app
- accessibility, localization, billing, privacy, performance, and release gates pass

## 12. Current official Android constraints used by this plan

- Compose and adaptive UI guidance: <https://developer.android.com/develop/ui/compose/documentation> and <https://developer.android.com/develop/adaptive-apps>
- Storage Access Framework and persisted tree access: <https://developer.android.com/training/data-storage/shared/documents-files>
- Microphone foreground service restrictions: <https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start>
- Explicit on-device speech recognition API: <https://developer.android.com/reference/android/speech/SpeechRecognizer>
- ML Kit on-device document scanner: <https://developers.google.com/ml-kit/vision/doc-scanner/android>
- Play one-time purchase lifecycle: <https://developer.android.com/google/play/billing/lifecycle/one-time>

These links inform platform-equivalence choices. Exact versions and SDK behavior remain governed by the repository’s pinned toolchain and ADR process.
