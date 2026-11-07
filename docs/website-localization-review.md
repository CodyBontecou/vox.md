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

Existing English privacy text also contains differing statements about whether
production onboarding analytics are enabled by default. The translations retain
the source statements; resolving that product-policy inconsistency requires a
separate source-copy decision.
