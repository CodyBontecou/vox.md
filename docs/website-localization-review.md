# Website translation review

All non-English website catalogs are machine drafts and require human review.
Their metadata must remain `status: requires-human-review` and `source: machine`
until a separate review process is defined. Passing catalog checks establishes
coverage and token integrity, not translation quality or human approval.

Review full pages, not just isolated segments. Inline markup can split a sentence
across several catalog IDs. Check the homepage tagline, navigation, download
calls to action, accessibility text, legal meaning, and the one-time lifetime
purchase wording first. Screenshots and code samples intentionally remain in
their original language.

## Japanese pilot

The catalog reuses shipped app labels exactly where those labels are referenced.
Some existing app translations are awkward or incorrect in ordinary Japanese:

- `Quick Capture` → `速い捕獲`
- singular `Capture Preset` → `キャプチャプレス`, while plural `Capture Presets`
  uses `キャプチャプリセット`
- `Template` → `寺`; `Entry Template` → `入り口 寺`
- `Create Heading` → `創出ヘッド`

These are inherited app terminology issues, not human-approved translations.
They should be reviewed in the app and website together rather than silently
renaming a product control on the website alone. App catalog changes are outside
this website task.

## Other inherited app terminology

Worker reviews found the same problem across the remaining language families.
These examples are **existing app strings**, not recommended translations:

| Languages | Examples requiring app-and-site review |
|---|---|
| es / fr / it / pt-BR | Template becomes a temple (`Templos`, `Temple`, `Templo`); French Heading is `Le chef`; Italian Paste is `Pasticceria`. Brazilian prose uses Brazilian conventions, but exact controls can inherit European wording such as `Ficheiros de anexo`. |
| de / nl | Dutch Undo is `elf`; Capture Sent is `Gevangen door`. German app strings mix formal and informal address; current website prose uses informal address. |
| ru / uk / pl | Template becomes a temple; Undo becomes nine or eleven. Russian Paste is `Паста`; several preset and statistics labels are malformed. |
| zh-Hans / zh-Hant / ko | Template is `寺庙` / `寺廟` / `템플`; Chinese Paste is bread and Korean Paste is pasta. Models becomes fashion models in Chinese. Watch Recordings can mistake Watch for a verb. |
| hi / bn / ta | Entry template becomes entering a temple; Undo becomes nine or eleven. Hindi Paste is pasta; Tamil Paste is summer. Transcribing can incorrectly say translating. |
| ar / ur / tr | Template is `معبد` / `tapınak`; Undo becomes numbers. Urdu Paste is onion (`پیاز`); Turkish Paste is make cake (`Pasta yapın`). |
| id / th / vi | Template becomes a temple/church. Thai Import audio says upload audio; this names the existing control, **not** a change to local-audio processing. Retry drafts can misleadingly mean withdrawal/refund; explanatory retry prose must retain repeat-operation meaning. |

Protected names and literal examples take precedence over app drafts. Generic
prose must describe the actual feature, not import an unrelated control-label
translation. When an instruction identifies a real control, keep its shipped
wording and review it together with the app. In particular, check capture versus
screenshot, audio recording versus record achievement, speech-to-text versus
translation, and lifetime purchase versus subscription.

## Source-policy discrepancy

Existing English privacy text also contains differing statements about whether
production onboarding analytics are enabled by default. The translations retain
the source statements; resolving that product-policy inconsistency requires a
separate source-copy decision.
