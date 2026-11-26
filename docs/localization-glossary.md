# Vox.md localization glossary

The product name is always `Vox.md`. Model, platform, file-format, shortcut,
URL, Markdown, wikilink, and printf tokens are preserved exactly.

| English | Preferred meaning |
|---|---|
| Capture | A durable quick-capture action, not a screenshot-only action |
| Transcription | Converting recorded speech to text |
| Recording | An audio recording or the act of recording |
| Notes | Plain Markdown notes/files |
| Clipboard | The system pasteboard |
| Keyboard Extension | The custom iOS keyboard extension |
| Unlimited Access / Vox.md Unlimited | Paid access to recording, transcription and Capture, from a weekly or yearly subscription or a one-time lifetime purchase |
| Subscription | An auto-renewing weekly or yearly plan billed by the App Store or Google Play |
| Free trial | The seven-day introductory offer on eligible subscriptions; never a free usage allowance |
| Lifetime | A one-time purchase that never renews and has no trial |
| Free allowance | Android only: the limited free transcription minutes and Captures before a plan is required |
| Family Sharing | Apple's Family Sharing entitlement |

Protected names include `Vox.md`, `Apple Intelligence`, `Apple Speech`,
`Whisper`, `whisper.cpp`, `Parakeet`, `FluidAudio`, `CoreML`, `Obsidian`,
`Markdown`, `App Store`, `Apple Watch`, `iPhone`, `iPad`, `iOS`, `watchOS`,
`macOS`, `Android`, `Google Play`, `Wear OS`, `M4A`, `WAV`, `TXT`, `JSON`, `YAML`, `SF Symbols`, and `ZenQuotes`.

The runtime draft uses Meta M2M100 1.2B (`facebook/m2m100_1.2B`) under the
MIT license. Machine translation is a completeness baseline. Evaluate it for
source fidelity, terminology, locale conventions, token preservation, and UI
fit.

Android additions live in `apps/android/localization/`: `android-strings.json`
contains offline machine drafts; `android-overrides.json` contains terminology,
reviewed iOS wording reuse and literal example corrections; `plural-spec.json`
contains explicit count-argument and CLDR category mappings. These additions remain
`requires-human-review` with no human approval claim. Transcription means speech
to text, vault means the user-selected Markdown storage folder, and preset means a
saved capture configuration. Retry repeats an operation; it never means discard,
withdraw or refund. Google Play Unlimited is an individual weekly or yearly subscription or lifetime purchase; Google Play has no Family plans.
File examples, template tokens, HTTP headers, IDs and URLs retain literal syntax.
