# Android Application: iOS Functionality and UI Parity Plan

Status: **Implementation in progress — broad local feature and release-engineering pass complete; physical parity and Play release evidence remain open**

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

The repository now contains a broad Android implementation rather than the original placeholder shell. As of the 2026-09-13 implementation checkpoint:

- The capture-first Compose app includes onboarding and vault repair, text/link capture, the selection-aware editor and Capture Bar, attachments and multimodal tools, capture presets, local history/detail/edit/export, stats, settings, models, recording recovery, billing UI, and app-language selection.
- Durable capture packages, Room indexing, quotas, WorkManager recovery, Rust/UniFFI planning and Markdown materialization, SAF commits/readback, rolling notes, and existing-note mutation are wired into the production flow.
- Voice capture uses a microphone foreground service with checkpointed chunks, notification controls, recovery, scheduling/retention, imported audio/video decoding, live local preview, local Vosk transcription, voice auto-stop, and segmented listening.
- Optional local speaker identification downloads a checksum-pinned Vosk speaker model only after an explicit user action, performs conservative on-device vector clustering, preserves plain text when evidence is insufficient, and never sends capture content to a service.
- The Android share receiver, deep links, app shortcuts, widget, Quick Settings tile, IME, Wear app, Wear Tile, complication, and versioned phone/watch transfer protocol are implemented.
- Wear transfers now preserve the frozen preset through phone ingestion, publish distinct receiving and durably-ingested frontiers, automatically transcribe and route `Transcribe & Capture` recordings with the recording UUID as the idempotency key, and retain Watch audio until a correlated complete-frontier delivery receipt or explicit durably-receipted discard. `Recording Only` writes checksum/read-back-verified WAV files directly into the frozen preset's SAF folder and filename policy without invoking transcription or location. Retry resumes from the acknowledged chunk over idempotent Data Layer paths. The round-screen app, Tile, complication, foreground notification, and true Wear Ongoing Activity have direct API 34 device tests. Recording-originated Markdown delivery uses zero Capture quota units, while normal text Capture reservations remain chargeable only after a verified terminal commit.
- Transcript History now preserves raw and cleaned bodies independently, searches raw/cleaned text plus title/tags/category, edits both bodies and organization fields durably, deletes the exact selected transcript without disturbing filtered-out history, and dispatches prior transcripts through Share or TXT/Markdown/JSON/YAML export. The YAML renderer matches the iOS core field contract and stable order for `id`, literal `text`, fractional ISO-8601 `date`, `duration_seconds`, `model_used`, and `language`. Deterministic offline None, Clean, Todo List, Meeting Notes, and the bounded grounded custom-instruction subset preserve the source and have direct fixture assertions; arbitrary model-driven custom instructions remain outside the verified local subset. Direct API 35 device tests also verify the deterministic title, tags, category, checklist, meeting-note, and conservative local speaker-diarization outcomes.
- Camera, Photo Picker, files, document scan, OCR, sketch, location, formatting tools, templates/frontmatter, deterministic title/tags/category/checklist/meeting cleanup, bundled on-device image labeling for image aliases, and original-preserving fallbacks are implemented.
- Expanded-width History, Settings, and Capture Presets use capture-first list-detail layouts with detail-first Back behavior. A debug-only deterministic harness now renders 21 named stories through the production Capture, History, Settings, Models, Capture Presets, App Language, live-recording, vault-repair, empty-history, folder-repair, paused/failed/interrupted-recording, loading, quota/offline billing, ambiguous/permanent provider outcomes, and pending/active-entitlement surfaces. Its hash-bound evidence manifest retains 45 full-resolution baseline captures: all seven primary stories on the API 35 phone in dark, light, 200% text, and Arabic RTL; all seven on a Pixel Tablet profile in landscape; all seven on an opened 7.6-inch foldable; and focused Quick Capture/live-recording captures in half-opened and closed postures. Another 28 full-resolution phone captures cover the seven recovery/empty/recording/purchase state stories, and a separate 28 cover the seven loading/offline/quota/interruption/terminal-failure resilience stories, each in dark, light, 200% text, and Arabic RTL. Five full-resolution windowing captures prove Quick Capture in a real 1080×1187 phone split-screen pane and Quick Capture, Settings, and live recording in narrow and explicitly resized tablet freeform tasks with exact bounds recorded in the manifest. Two H.264 production motion clips retain the fresh-install vault permission route into the composer and the composer → Settings → Models → back → History route at 1080×2400/30 fps. Sampled-frame review found no clipping, theme flash, or broken intermediate state, and exact paths, bytes, timing metadata, hashes, MP4 signatures, and unreviewed status are gated. Visual review also found and fixed light-story system-bar contrast, large-text History-filter/recording-action wrapping, and completed/failed recording-card clipping in constrained windows, and the initialization indicator now has an explicit localized accessibility description. Six direct instrumentation tests render every named state, keep the applicable 200% recovery, quota, offline, interrupted-recording, purchase, History, and recording controls reachable and on usable control lines, verify polite TalkBack live-region semantics for 11 state changes, and verify labeled, clickable, scroll-reachable controls with at least 48 dp accessibility touch bounds across 12 Switch Access recovery surfaces. The real TalkBack service bound on the API 35 emulator and exposed the interrupted state plus separate Resume/Finish/Cancel nodes, but injected traversal did not produce stable review evidence after its first-run dialog; real human TalkBack and Switch Access traversal therefore remains open. The phone, state, resilience, windowing, and motion captures use Argent; its simulator server could not start on the original headless large-screen sweep, so the manifest explicitly records the lossless Android `screencap` fallback for those earlier tablet/foldable files. Physical-device/OEM review, expansion and human full-speed/frame-by-frame approval of the moving-flow matrix, actual assistive-service traversal, and human golden approval remain open.
- Four current iOS references—Quick Capture, Settings, Models, and Capture Presets—have direct Argent comparisons. Native cross-platform dimensions correctly produce a 1206×2622 versus 1080×2400 mismatch; clearly labeled diagnostic normalization reports 4.53%, 13.53%, 56.46%, and 7.38% pixel change respectively. Every comparison remains `captured-unreviewed`; the release gate validates hashes, dimensions, provenance, limitations, and the absence of an unsupported approval claim rather than treating pixel similarity as product approval.
- The phone and Wear design systems package the exact shared Geist Regular/Medium/SemiBold and Geist Mono Regular/Medium binaries used by iOS. All 15 phone Material typography roles use Geist, transcript/timer monospace surfaces use Geist Mono, Wear defaults to Geist, and APK/AAB validators pin every font by SHA-256. System sans/monospace fallbacks are rejected by governance.
- Android-owned shortcut, widget, tile, capture-entry, Wear recorder, Wear Tile, and complication strings are generated from the iOS localization catalog for all 22 non-English resource qualifiers. The runtime table now contains 4,717 source/locale entries gathered from 2,368 stable literals across the app, capture-domain, data, and platform-service modules. It supports Apple-style positional and integer placeholders for dynamic Compose copy, including nested localized arguments, rejects translations whose argument indices or types differ from the English source, and safely falls back to the English source if formatting nevertheless fails at runtime. CI also rejects `$identifier`, `${...}`, nested conditional/interpolated localization calls, raw conditional text, or raw accessibility labels that bypass localization. Billing benefits, usage/price labels and outcomes, typed vault notices and normal snackbars, Capture and Transcript History export results, recording-queue operations, configured-export failures, recovery/download progress, generated History state and Capture Bar action labels, recording chunk counts, category labels, processing outcomes, preset routes, finite enum labels, and download/transcription failures are routed through the same runtime localization boundary; raw provider exception text is no longer displayed. Six Android case-only source variants reuse their exact reviewed iOS catalog equivalents across all locales. A generated, branch-aware `apps/android/localization-review.json` inventory binds every literal source to its Kotlin locations and remains explicitly marked `requires-human-translation`; CI rejects stale audit bytes, incomplete or absent locale coverage, incomplete alias targets, parser drift, count drift, and any translation or plural-approval overclaim. It records 678 literal runtime phrases—211 complete direct catalog matches, six reviewed aliases, no partially translated catalog entries, and 461 Android-only phrases that still fall back to English. All previously unresolved finite-domain paths are now explicit and the audit contains zero dynamic-source call sites; localization-runtime plumbing is explicitly excluded from that UI inventory. A real Arabic app-language lifecycle test and emulator screenshots confirm RTL recreation, alignment, control order, translated shared-catalog copy, and no clipping at 200% text. Reviewed translation of the 461 gaps, plural review of the 16 integer-format candidates, inherited catalog-quality review, and canonical RTL screenshot approval remain open.
- The connected-device gates pass all 13 instrumentation tests on the API 36 phone emulator, 57 isolated API 35 app tests, a separate two-phase API 35 uninstall/reinstall qualification, a two-case exact-hash offline local-speech and Wear transcript-delivery qualification, 14 production-client download/integrity/offline-inference phases across all five Whisper sizes and both Parakeet versions, and 13 round API 34 Wear OS tests. The routine API 35 run discovers 61 tests and intentionally skips four named/local model cases because their large immutable downloads are isolated gates. The named-model qualification covers Tiny, Base, Small, and both Parakeet versions on the standard device, Medium and Large v3 Turbo on an isolated 8 GB device, and a pre-download memory rejection for Medium on the standard 2.5 GB device. The reinstall qualification fills the actual Room free-quota ledger to its limit, uninstalls the isolated test application, reinstalls the same artifact, and proves that both the installation identity and usage ledger are new and empty before accepting the first fresh reservation. The local-speech qualification installs the reviewed Apache-2.0 English mobile Vosk archive, disables device connectivity, imports Vosk's real 16 kHz speech fixture, verifies expected phrases through the production `RecordingTranscriptionClient`, and routes the same real speech through a frozen Wear preset, the native Rust materializer, and verified Markdown SAF delivery; the model, transcript, and quota fixtures are removed afterward. The API 36 capture vertical slice creates a public test vault, obtains and persists a grant through the real system document picker, executes the production Room/durable-store/native-Rust/materialization/SAF path, writes through `com.android.externalstorage.documents`, and verifies the committed note by exact length and SHA-256 read-back. The Room qualification also proves failed/retried text reservations remain uncommitted until verified delivery and recording-originated delivery commits zero Capture units. The API 35 suite exercises the production document-tree exporter through a debug-only `DocumentsProvider`, proving unique new files, read/merge/write append, Obsidian frontmatter merging, YAML-as-Markdown output, selected-template reads, retained-audio copies, Watch inbox checksum/frontier enforcement, frozen-preset ingestion, and Recording Only nested-folder WAV delivery with content-free receipts. It also drives the real Compose Capture Bar, History, Recording Queue, external-entry flows, committed-versus-volatile live transcript presentation, local processing and diarization outcomes, the installed Vox IME, deterministic visual stories, 200% text controls, state-specific TalkBack live-region semantics, 48 dp Switch Access touch targets, and a Play restore diagnostic built from a tainted purchase object that retains product/state evidence while excluding account, order, token, signature, profile, and timestamp identifiers. A separate API 35 keystore qualification proves that last-confirmed Play ownership evidence round-trips, while preference tampering, product substitution, and installation-key loss all clear the cache and fail closed. The IME test types through real keyboard accessibility nodes and proves that editor IPC failure preserves both byte-identical durable audio and recoverable text. The suite covers all media/file/scan/OCR/sketch/location/paste/undo dispatch, Capture Bar visibility/reordering, persistent voice-note review, one-shot entry-template selection, typed location-unavailable choices, transcript search/edit/share/export, retained-audio controls, preset reassignment, external-entry normalization, and production-backed relaunch recovery. It runs the foreground recorder through pause, resume, stop, notification actions, WAV export, forced transcription failure and audio recovery, concurrent capture, and configurable pause/persistent-listening controls. The Wear suite drives every inventoried wrist status, recorder/preset/recovery controls, exact shared typography, a real microphone lifecycle, notification actions and Ongoing Activity serialization, durable queue/retry/discard/deletion authorization, frozen snapshots, Tile and complication payloads, and resumable idempotent Data Layer assets from an acknowledged frontier. This is strong local-provider and focused UI evidence; physical-device model performance and thermal benchmarking, Drive/OneDrive, full state-specific golden/accessibility approval, and provider-race campaigns on physical devices remain open.
- The current Android/Wear local gate passes: `check`, debug instrumentation APK assembly, phone and Wear debug artifact validation, optimized phone and Wear release bundles, release artifact validation, SBOM validation, and the visual-evidence integrity gate. The visual gate now closes 106 deterministic/state/resilience/form-factor/windowing captures plus two onboarding captures and two production motion clips. The validators review exported components and permissions, backup exclusions, billing permission scope, exact shared font hashes, Vox/JNA/Sherpa ELF packaging for all four phone ABIs, absence of phone-only Rust/ASR/OCR/image-labeling runtimes from Wear DEX, and the hashes/dimensions/task bounds/provenance/unreviewed status of every retained visual artifact, plus the motion clips' closed inventory, MP4 signature, byte counts, and capture metadata. The debug Wear artifact fell from 192 MB of stale/shared runtime payload to a clean 40 MB artifact after this boundary was enforced.
- Optimized, resource-shrunk release bundles build and pass release validation: the current phone AAB is approximately 106 MiB, the Wear AAB is approximately 3.9 MiB, dormant phone-only inference types are absent from optimized Wear DEX, and a deterministic CycloneDX 1.5 SBOM inventories 340 locked release components. CI now runs localization freshness plus the debug and optimized-release gates. Environment-only phone/Wear signing and cryptographic signature validation pass with a disposable test key; checked artifacts remain intentionally unsigned, and production credentials plus Play delivery remain release gates.
- Contract and toolchain governance covers the completed application and Wear release surface. The project-contract suite passes all 131 mutation tests; the contract manifest validates 191 governed files, 98 fixtures, 271 capabilities, and four mirrors; and the toolchain validator binds 178 Android/Wear implementation files, including the adaptive layout surface, exact shared fonts, deterministic visual harness, hash-bound screenshot and motion evidence manifest, responsive-control assertions, localization fallback and format-argument audits, typed UI-message/export-failure paths, Play pending/refund continuity rules and a tamper-evident Android Keystore-backed entitlement cache, and lifecycle/visual checks, plus the six-module graph, Room migrations through version 5, dependency locks, CI, localization, SBOM, signing, reinstall, Vosk/Sherpa local-inference, named-model, billing-diagnostics, and release validators. The local evidence registry distinguishes deterministic fixtures, instrumented device guarantees, focused instrumented UI interactions, and deterministic Rust library semantics; device and UI claims require both an `src/androidTest` source and a passing connected-test gate.
- The completion ledger now records 233 of 238 Android/Wear-applicable rows as verified. In addition to the capture, editor, routing, history, voice, quota, stats, processing, export, and remote-lifecycle coverage above, this now includes the installed Android voice keyboard and its failure-preservation policy, the verified uninstall-reset product adjustment, privacy-safe Play restore diagnostics, real offline production-client transcription, automatic exact-language/language/English fallback model selection, all five Whisper sizes and both Parakeet versions through immutable SHA-256-pinned packages and real offline production-client inference, memory preflight for Medium and Large Turbo, frozen Wear-preset background transcription and verified Markdown delivery, committed and volatile live transcript behavior, deterministic local title/tags/category/checklist/meeting/custom processing, conservative speaker diarization, Wear capture entry, every inventoried wrist UI phase, real pause/resume, durable frozen-preset queues, receiving/ingested frontiers, correlated deletion authorization, explicit discard, retry, preset reassignment, Recording Only filename/folder/WAV policy, resumable Data Layer transfer, and the Wear app/Tile/complication/notification/Ongoing Activity surfaces. These claims are bound to exact executable assertions and passing Android, connected-device, Wear-device, or Rust library gates through the strict evidence registry. The remaining five Android/Wear rows stay inventoried until their required Play-account or Apple-grandfathering scope evidence exists; across the full 271-row product ledger, 262 rows are verified and nine remain inventoried.
- The deterministic Rust library gate passes all 29 tests, including the complete target/placement, scoped-formatting, native-owned asset-descriptor, ordered structured-location, typed location-unavailability, consent-frozen label, and exact/city/advanced frozen-location oracles. The workspace-wide run still stops only at the intentionally provenance-bound Swift-oracle hash check, which cannot be truthfully regenerated until these working-tree changes are reviewed and committed as a clean source revision. This is a release-evidence prerequisite, not an Android runtime failure.
- Pixel emulator evidence covers durable text capture, WAV import/transcription, H.264/AAC video audio-track import/transcription, explicit speaker-model acquisition, a diarization-enabled recording flow, and a hash-bound image capture whose locally generated description appears in the prepared Markdown. This is integration evidence, not the required physical-device/OEM/provider/performance matrix.

The feature inventory and 271-row capability ledger remain the completion authority. Rows must not be promoted merely because code exists: visual, accessibility, provider, physical-device, billing-console, Wear hardware, security, performance, and release evidence is still incomplete. In particular, production parity is blocked by complete Android-specific localization and RTL/plural review; human approval and complete failure/permission/quota/accessibility state coverage for the retained emulator goldens; physical-device/OEM coverage; multi-speaker quality benchmarking; arbitrary custom-instruction model coverage; physical Drive/OneDrive and long-recording testing; Pixel/Samsung Wear testing; Play Console product/refund/restore validation; and signed release, legal/license review, Play-track, rollback, and recovery drills. The SBOM generation gate is implemented, but its inventory still needs release/security review.

This plan continues to govern the remaining verification and release work. It does not replace the existing ADRs, contracts, durability rules, or shared Rust strategy.

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
- `artifacts/android-parity/` — hash-bound Android captures, normalized diagnostics, diffs, and explicit review limitations

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

Local emulator qualification is complete for this work list: 13 API 34 Wear tests cover all UI phases, exact shared typography, real recording pause/resume/stop, Ongoing Activity/notification actions, frozen presets, durable disconnected queues, retry/discard/deletion receipts, Tile/complication state, checksum-verified phone ingestion, verified Recording Only delivery, and acknowledged-frontier Data Layer replay. The physical reference/Samsung watch, 60-minute/72-hour endurance, reboot/corruption, and reinstalls in the exit gate remain release evidence.

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

The next concrete slice is the remaining release-critical evidence program: **review and commit a clean implementation baseline, regenerate the provenance-bound Swift oracle, obtain human approval for the retained phone/tablet/foldable/split/freeform, recovery, resilience, and captured motion evidence, finish Android-specific localization and RTL/plural review, complete human TalkBack/Switch Access traversal and expand the full moving-flow matrix, benchmark local inference and a 60-minute physical recording, validate Drive/OneDrive, Pixel/Samsung Wear, and Play Billing on real accounts/devices, then complete security, dependency/license and SBOM review, production signing, staged-track, rollback, and recovery gates**.

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
