**iOS 27 on-device intelligence implementation plan**

Prepared September 7, 2026. Implemented in the working tree; device release checks below remain open.

Improve Vox.md's existing local text processing and add optional automatic image descriptions. All inference uses Apple's on-device system model. Preserve current transcription engines, Capture Presets, durable delivery, and support for older operating systems.

**Implementation and verification — September 7, 2026**

The app now has preset-aware guided text generation, per-request readiness/language/context checks, terminal error mapping, bounded inference deadlines, and a shared inference slot. Timed-out model work cannot publish late results. A source-structure safeguard retains the original text when generated output loses common literal links, code blocks, clean-mode headings, or speaker labels. This safeguard is conservative; it is not a proof that all prose preserves its meaning.

The opt-in image adapter is wired through direct Capture submission and inbox delivery on both apps. It preserves description provenance, snapshots the app locale, validates staged files, decodes an orientation-correct bounded preview, and persists success or fallback before delivery. Tests cover original-byte preservation, image-only Keep Original mode, provided/empty descriptions, ten-image deadlines, non-cooperative work, cancellation, and reuse after a failed destination write.

| Check | Recorded result |
| --- | --- |
| SDK 27 builds | Xcode 27 beta 6 (27A5252f): iOS app and extensions, Mac app, Watch app and Watch widget build successfully. |
| Older compiler compatibility | Xcode 26.6 builds the iOS app/extensions successfully; compiler and runtime guards exclude the new image APIs. Deployment targets are unchanged. |
| Portable tests | 505 shared XCTest tests, 277 Capture Core XCTest tests, and 10 Swift Testing tests pass. |
| App-hosted tests | Full iOS 27 suite: 146 tests, 1 optional real-model test skipped, no failures. The subsequently added direct-Send cancellation/staging test also passes. Final focused rerun: 4 tests, 1 skipped, no failures. |
| Persistence and repository checks | Synthetic persistence fixtures and Capture view structure checks pass. Capability conversion, contract manifest, toolchain, validation-definition checks, and 95 contract validator tests pass. Regenerating the manifest also refreshes a pre-existing stale hash for the project-contract script. The broader project-contract script stops on two pre-existing unmapped keys: `shortcutRecordingLiveActivityEnabled` and `capturePresetProcessingGateMigrationVersion`. |
| Text model evaluation | Real inference on this Mac running macOS 26.5.1, after Apple Intelligence was enabled. All six candidate fixtures preserve their required content; an oversized request is rejected before generation. See the [synthetic evaluation report](validation/on-device-intelligence-2026-09-07.json). |
| Image decoding and errors | App-hosted tests verify a rotated 2400×1200 JPEG becomes a 768×1536 preview, corrupt data is rejected, and SDK 27 errors map to terminal outcomes. |
| Settings and export | iOS 27 UI inspection verifies default-off behavior, the master switch, and Keep Original independence. A standard Markdown renderer produces the expected `img` alt attribute and encoded path. Eleven new strings cover all 23 catalog languages with no new audit errors; the whole catalog still has pre-existing audit findings. |

The text report is a small synthetic preservation check, not a general model-quality or performance benchmark. Several ordinary inputs remain effectively unchanged and the custom fixture does not reliably follow its requested bullet format in either implementation. The previous cleanup output dropped a Markdown heading; the candidate retained all required structure. Recorded timings are single observations (including variable warmup), not evidence of a speed improvement. The runner recreates the prior clean-mode instructions/schema and uses the compatibility string workflow for the other baseline cases.

The iPhone was subsequently upgraded to iOS 27.0 beta. Real image generation and full synthetic capture delivery now pass on hardware, with original image bytes and accompanying Markdown preserved. Device QA also found and fixed image-token-preflight failures and preset edits lost on restart. See the [iPhone QA record](validation/ios27-iphone-qa-2026-09-07.md) for measured timings, Argent coverage, fixture isolation, and remaining release checks. Broad photo/screenshot/sketch quality, peak memory, offline inference, Obsidian/VoiceOver behavior, the Mac editor, and non-English descriptions remain unverified. The option remains off by default.

To repeat the local text checks after a Debug build of `Voxboard Mac`:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
python3 scripts/run-foundation-model-evaluations.py /tmp/vox-intelligence-mac
```

The runner uses only synthetic fixtures and exits nonzero when candidate preservation or oversized-input rejection fails. For real image smoke testing, run `FoundationModelsImageTests/test_availableOS27ModelDescribesSyntheticImage` on an eligible OS 27 device with test environment `VOX_RUN_MODEL_EVALUATIONS=1`. That test describes a synthetic blue square and verifies source-byte preservation; it does not replace human review of photos, dense screenshots, or sparse sketches. Deterministic CI skips that opt-in inference test. CI continues to use Xcode 26.6; SDK 27 compatibility was verified locally with the explicit beta toolchain.

The original implementation plan follows for traceability.

**Product decisions**

| Area | Planned behavior |
| --- | --- |
| Existing enrichment | Improve cleanup, titles, tags, categories, checklists, meeting formatting, custom instructions, and existing folder routing. |
| Image option | Add **Generate Image Alt Text** to each Capture Preset, off by default, under the existing **Use Apple Intelligence** gate. |
| Image-only processing | Allow the image option with text Mode set to **Keep Original**. Voice/Text scope controls text processing only. Turning off the master gate disables both. |
| Eligible images | Newly attached or submitted staged photos, screenshots, camera/pasted images, and sketch previews represented by image/sketch payloads. |
| Description output | One short factual description, normally one sentence, in the supported app language, stored with its attachment and exported as image alt text. |
| Timing | Generate when an image is attached so the attachment chip can show the generated label before Send. Keep the existing Send/preparation fallback for deferred or queued captures, before the destination write. |
| Existing descriptions | Preserve provided descriptions, including an explicitly provided empty value. Replace only missing descriptions or placeholders explicitly marked by the app. |
| Failure | Preserve the original attachment and existing label. Complete delivery using the existing fallback policy. |
| Platform support | Existing text enrichment on eligible iOS/macOS 26+ devices; new image support on eligible iOS/iPadOS/macOS 27+ devices. Keep current minimum deployment targets. |

This iteration excludes cloud inference, additional model providers, conversational search, autonomous routing features, OCR replacement, document summarization from images, scanning previously exported notes, and downloading images embedded in Markdown. Scan PDFs and scannedDocument payloads keep their current OCR/export behavior. An imported image represented as a generic file keeps its existing file semantics.

Apple confirms that the system model changes when users upgrade to OS 27. The text work therefore starts with evaluating existing behavior and adopts new APIs where they resolve concrete limitations. [Foundation Models updates](https://developer.apple.com/documentation/Updates/FoundationModels)

**Current integration and implications**

Paths below are repository-relative implementation targets.

| Current code | What the implementation must account for |
| --- | --- |
| `Voxboard/FoundationModelsBackend.swift` | Uses the default system model, fresh sessions, and guided generation for basic enrichment and routing. |
| `Packages/VoxboardShared/Sources/VoxboardShared/TranscriptEnricher.swift` | Custom workflows and speaker-labelled transcripts use JSON text generation; a native error currently triggers another model call. |
| `Voxboard/VoxboardApp.swift`, `Voxboard Mac/VoxboardMacApp.swift` | Enrichment is injected only when the model is available at launch. Later asset readiness currently cannot restore a missing injected backend. |
| `Packages/VoxboardShared/Sources/VoxboardCaptureCore/CaptureVoxRequestProcessor.swift` | Processes text/audio/OCR payloads and skips images/sketches. It receives no asset staging root. |
| `Packages/VoxboardShared/Sources/VoxboardCaptureCore/CaptureModels.swift` | Images and sketch previews already carry optional `altText`; the origin of a label is not recorded. |
| `Packages/VoxboardShared/Sources/VoxboardCaptureCore/CaptureMarkdownRenderer.swift` | Image descriptions currently render as Obsidian embed aliases. Generated accessible alt text needs an explicit rendering contract. |
| `Voxboard App Shared/CaptureComposerViewModel.swift` | Saves a processed prepared request before writing; drafts resolve assets relative to their staging directory. |
| `Packages/VoxboardShared/Sources/VoxboardShared/CaptureInboxDeliveryService.swift` | Replaces pending requests with processed requests before delivery; inbox assets resolve relative to the capture root. |
| `CaptureDraftStore.swift`, `CaptureAppIntents.swift`, `ShareViewController.swift` | Each computes pending processing from text settings. All must admit image-only processing consistently. |

**1. Establish OS 27 compatibility and a baseline**

Use Xcode 27 and its SDK to compile the new image APIs. The currently selected installation is Xcode 26.6 with iOS/macOS 26.5 SDKs; OS 27 image code cannot be validated with that selected SDK. Check installed toolchains at implementation time before changing build configuration. Keep framework-dependent code in the iOS/Mac app targets so the keyboard, Watch, and portable capture package remain independent of FoundationModels.

Before changing prompts, run an app-level fixture harness on eligible physical OS 26 and OS 27 devices. Include short dictation, typed Markdown, OCR text, checklists, meeting notes, custom instructions, speaker labels, and the supported app languages. Record OS/device/model capability, latency, parse failures, refusals, and whether meaning, Markdown, and speaker attribution survive. Use synthetic or explicitly selected fixtures; avoid copying customer captures into logs.

The baseline is a release gate, not a claim that the new model is already better for every preset. Retain prompts that perform well; tune only demonstrated regressions or improvements.

**2. Make existing text processing more reliable**

Keep `FoundationModelsBackend` as the concrete on-device adapter, explicitly selecting `SystemLanguageModel`. Add a small capability/status layer for current model availability, supported locale, image support, and context budget. Construct the adapter on supported OS versions even if model assets are temporarily unavailable; check availability when each request runs and refresh UI status when the app becomes active. Unsupported devices and older OS versions continue to use the existing fallbacks.

Use locale support checks for requested output languages. Preserve the input language for cleanup and follow an explicit custom instruction only when supported. Automatic image descriptions use the app's language, snapshotted with the pending request so relaunching in another language cannot alter preparation. [Apple's language support guidance](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)

Extend the native enrichment entry point to accept the preset profile. Use the existing generated title/tags/category/cleanedText shape for preset-specific processing and speaker-labelled text as well, after the baseline confirms output quality. Keep normalization, static metadata merging, and deterministic checklist behavior. Separate app/preset instructions from captured data; a transcript or OCR passage containing instructions is still source content. Continue preserving URLs, wiki links, code fences, and anonymous speaker labels.

Preflight the actual instructions, source text, output schema, and output allowance using runtime context size and token counting where available. These APIs began in OS 26.4. Do not hardcode a universal OS 27 context capacity. When a full transformation cannot fit, preserve the original and use the existing fallback; do not silently truncate input or deliver a partly cleaned transcript. Cross-chunk meeting summarization is outside this iteration. [Foundation Models context APIs](https://developer.apple.com/documentation/Updates/FoundationModels)

Map OS-specific model errors to a small internal outcome set: unavailable, unsupported language, input too large, refusal, cancelled, timed out, and failed. Skip the second prompt attempt for known terminal outcomes. Retain a bounded compatibility fallback only where it can reasonably recover, within the original request deadline. Folder selection and folder-name generation use the same availability, budget, and error policy without changing their routing semantics.

Audit `withRunningTask` in `CaptureVoxTextProcessor.swift`: a throwing task group still waits for children that ignore cancellation. Existing hanging-backend tests cooperate with cancellation. Add a non-cooperative finite-delay fixture and ensure delivery can choose fallback at its deadline without later model output mutating a prepared request. Use a single-completion coordinator, cancel expired work, and keep unfinished inference bounded; if a timed-out session still occupies the inference slot, subsequent optional work falls back instead of accumulating tasks. Parent cancellation must stop preparation without marking the capture delivered. Log outcome codes and timings, not generated content or raw model errors containing input.

**3. Persist the image policy and description provenance**

Add `generateImageAltText: Bool = false` to both `CapturePreset` in `RecordingFlow.swift` and `CapturePresetProfile` in `CaptureVox.swift`, including initializers, coding keys, explicit encoders/decoders, and the `captureProfile` conversion. Missing values decode false. Keep the value in each request's existing immutable preset snapshot.

Add optional `altTextOrigin` metadata to image/sketch payloads, with values for app placeholder, provided text, and generated text. Keep the existing payload kind and `altText` wire keys. A missing origin with nonempty text means unknown/provided for preservation purposes; never infer provenance by matching localized strings. Newly staged labels such as Screenshot, Camera photo, Pasted image, and Sketch created on Mac are explicitly placeholders. Treat Share Sheet suggested filenames as placeholders. Callers providing descriptions mark them as provided. Keep provenance through draft/inbox serialization and payload reconstruction.

Description eligibility is: image policy enabled, master gate enabled, supported runtime, and description either missing or explicitly a placeholder. A provided empty description also opts out. Existing generated descriptions are reused. Old pending requests with no new flag keep previous behavior. No migration rewrites delivered notes.

Create one shared policy helper to decide whether a request requires text work, image work, or neither. Use it in draft submission, Share Sheet, Shortcuts, and other request constructors. In the processor, gate the text branch explicitly; an image-only pending request must not accidentally clean text because the processor now visits it.

**4. Generate descriptions inside capture preparation**

Add an injectable `CaptureImageDescribing` protocol with portable inputs/results and an app-target `FoundationModelsImageDescriber` implementation. The adapter uses a fresh on-device session, one image attachment, a short fixed instruction, and a guided result containing a description or an explicit unable-to-describe outcome. It does not accept a caller-selected model or instantiate a cloud model.

Prompt for visible, relevant details in one sentence, with no invented identities, intentions, context, or unreadable text. Treat text inside the image as content to describe, not instructions to execute. Target a concise sentence and enforce a maximum of 300 grapheme clusters; reject unusable output rather than cutting a word or emitting a refusal as alt text. Preserve existing labels when uncertain. Apple's image APIs support images with text prompts and guided output. [Multimodal prompting documentation](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)

Extend request processing with an explicit asset context. Direct submission supplies the draft staging directory; inbox delivery supplies the capture root. Add a bounded reader using the existing secure relative-file I/O approach. Enforce root containment, reject symlinks/unsupported or malformed images, honor orientation, and cap decoding memory. Use an inference preview when needed for large photos while retaining the original exported bytes. Image frameworks and FoundationModels stay outside the portable request processor.

Process image payloads and sketch previews in payload order, retaining drawing files and attachment associations. Start with one image inference at a time, a 10-second per-image deadline, and a 30-second total image-stage budget; these are provisional limits to tune against physical-device measurements. Remaining images use their existing descriptions when the budget or background execution time expires. Account for both text and images within the enclosing submission budget so additional images cannot multiply Send latency without a bound.

Keep model work in the host app. Share Sheet and Shortcuts stage/snapshot/enqueue, then the existing host drain performs processing. Wire the adapter into both app compositions and every direct/retry/background processing path. Background expiration preserves the pending request or a completed fallback preparation, according to whether preparation was persisted; it must not discard attachments.

For success or fallback, save the final request before any destination write using `savePreparedRequest` or `replaceProcessingRequest`. A failed destination write retries those exact bytes even after settings, OS model, or language changes. Computation interrupted before this persistence boundary may run again; make no exactly-once inference claim. Model tasks return values and never write files or update the draft themselves. Existing tombstone and staging cleanup rules apply to generated descriptions as captured content.

**5. Export alt text and expose the setting**

For generated descriptions, emit standard Markdown image syntax with the planned attachment path:

```markdown
![Handwritten checklist for the launch, with three completed tasks.](attachments/screenshot.png)
```

Use the same attachment filename and destination rules. Escape the label and encode the path for Markdown, including spaces, brackets, parentheses, percent signs, and hash characters. Preserve current wiki-embed output when generation is off, skipped, or fails. For sketches, apply the description to the preview and keep the editable-drawing link. Verify actual image alt semantics in Obsidian and a standard Markdown renderer, including VoiceOver; a visible caption or embed sizing parameter does not satisfy this requirement.

Add the toggle to the iOS and Mac preset editors alongside the current processing controls. Suggested help: “Describe photos, screenshots, and sketches on this device when you attach them. Existing descriptions are preserved.” Explain that Keep Original controls text, and that the image option is separate from Voice/Text scope. Show an availability reason on unsupported devices or when assets are unavailable; preserve a saved preference through temporary unavailability. Existing captures remain usable. Update relevant localization resources and the processing help/footer text.

Use the existing submission progress surface for “Describing images…” while active. Generation happens on Send; this scope adds no new image-description editor or automatic pre-Send analysis.

**6. Validate and ship in reviewable increments**

| Increment | Acceptance evidence |
| --- | --- |
| A — Baseline and text reliability | App-target model evaluations on OS 26/27; package tests for preset-aware structured output, unchanged source fallback, token limits, terminal errors, cancellation, and late-result rejection. Existing routing behavior is preserved. |
| B — Policy and payload plumbing | Old presets/drafts/requests decode correctly; the new flag defaults off and survives all conversions. Provided/empty descriptions survive. Missing/generated/placeholder origins round-trip. Image-only mode performs zero text calls. |
| C — Image generation and durable delivery | Mock-backed tests for per-image and total budgets, unavailable/unsupported/refused/corrupt input, original attachment byte preservation, correct staging roots, background interruption, and retry reuse after model/settings changes. |
| D — Rendering, UI, and device release gate | Toggle behavior on iOS/Mac, localization, Markdown escaping/path correctness, Obsidian/VoiceOver validation, offline generation with installed model assets, physical-device latency/memory checks, and older-device fallback. |

Extend the existing `TranscriptEnricherTests`, timeout suites, `CaptureVoxTests`, `CaptureModelCodableTests`, `CaptureDraftStoreTests`, `CaptureInboxDeliveryServiceTests`, and `CaptureMarkdownRendererTests`; add focused image-describer and asset-reader suites. Use deterministic fakes for application guarantees and device evaluations for model quality. Include the ten-image picker case, large rotated photos, screenshots with dense text, and sparse sketches. Require zero source/attachment loss, no duplicate delivery, and no request mutation from late model results. Manually review whether descriptions are useful and factually grounded before enabling the option in a release.

Build the app, Mac target, keyboard, Share Extension, widgets, and Watch targets to catch shared-model compatibility changes. Keep FoundationModels out of portable packages/extensions. The current Rust M2 admission only covers constrained text/link requests and rejects enriched/image requests; this work should preserve that boundary rather than expand it. Run relevant persistence fixtures if their consumers touch the added optional fields.

Ship increment A independently when its checks pass. Ship the image option after increments B–D, still defaulting off. Acceptance depends on measured output and delivery behavior; implementing an OS availability check alone is not completion.
