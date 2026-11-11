# Retention messages and offers

Paste-ready store configuration for the subscription retention flow. Sources: the iOS design
canvas page "Retention Messages" (boards `RM_*`) and the Android canvas page "Retention Flow"
(boards `RF_*`). Bracketed values such as `[YOUR PRICE]` are decisions that are still open; do not
paste them literally.

Offer identifiers and reference names are permanent in both stores. Decide them before saving.

## What happens when a subscription ends

The copy below must stay true to the apps. In both apps, paid access ending makes the Library
read-only. It does not hand back the free allowance.

- **iOS:** the Library becomes read-only (`UsageTracker.isLibraryReadOnly`). New recordings,
  transcription and delivery pause.
- **Android:** once Google Play confirms that a previously verified subscription is gone,
  `hasSubscriptionAccessEnded` is set and recorded in signed evidence. After that:
  - `AndroidCaptureRepository` rejects every new capture, whichever surface sends it (app,
    keyboard, widget, Quick Settings, share sheet or Wear OS).
  - Recording start and keyboard voice input are blocked.
  - Transcripts can't be edited or added to a draft.
  - Library still allows read, search, copy, export, share and delete.
  - Captures already saved on the phone finish delivering.
  - Recordings that haven't been transcribed keep their audio.

---

## App Store Connect: retention messages

Location: App Store Connect › your app › Subscriptions › group "Vox.md Unlimited" › Retention
Messaging. You can have one message per subscription and up to 10 per app. These use 3 of the 10.
Lifetime (`bontecou.Voxboard.unlock`) isn't a subscription, so it gets no message.

Character limits: [CONFIRM IN APP STORE CONNECT].

### A: Individual Yearly

| Field | Value |
|---|---|
| Reference name | `RM-A Notes stay · Individual Yearly` |
| Subscription | Vox.md Unlimited · Individual Yearly (`bontecou.Voxboard.individual.yearly`) |
| Header (32 chars) | `Your notes stay. Capture pauses.` |
| Body (137 chars) | `When your subscription ends, your library stays readable and searchable. New recordings, transcription and delivery to your routes pause.` |
| Image | `RM_Img_Keep`, 3840 × 2160, exported at 1× |

The image's note card shows what stays (readable, searchable, exportable), and the paused Speak
button shows what stops. The image contains English Markdown motifs ("kept", "readable"), so
localize it or use image B where English doesn't fit.

### B: Individual Weekly

| Field | Value |
|---|---|
| Reference name | `RM-B Routes everywhere · Individual Weekly` |
| Subscription | Vox.md Unlimited · Individual Weekly (`bontecou.Voxboard.individual.weekly`) |
| Header (28 chars) | `Your routes, on every device` |
| Body (130 chars) | `When your subscription ends, new captures from the voice keyboard, Apple Watch and Mac stop. Notes already in your vault stay put.` |
| Image | `RM_Img_Routes`, 3840 × 2160, exported at 1× |

The image shows the four capture surfaces (keyboard, Watch, Mac and widgets) wired to the vault.
It has no text, so it needs no localization. Before shipping, confirm that the Mac app shares this
subscription group in every storefront, because the body says "Mac".

### C: Family Yearly and Family Weekly

| Field | Value |
|---|---|
| Reference name | `RM-C Your files · Family` |
| Subscriptions | Vox.md Unlimited · Family Yearly (`bontecou.Voxboard.family.yearly`) and Family Weekly (`bontecou.Voxboard.family.weekly`) |
| Header (28 chars) | `Your notes are already yours` |
| Body (145 chars) | `Everything Vox.md filed is plain Markdown in folders you choose. It stays there when your subscription ends; new captures and transcription stop.` |
| Image | `RM_Img_Yours`, 3840 × 2160, exported at 1× |

The image shows `.md` sheets in a `~/Vault` folder with the on-device lock. It echoes the paywall
lines "Plain Markdown files you own" and "Audio is never uploaded to Vox.md." The `~/Vault` label
is English, so localize the image or use image B.

### Localization

Localize the header and body for every storefront each subscription is sold in. en-US is the
default, and the app already ships 39 App Store localizations.

### Review checklist (from the canvas)

- [x] No offers, discounts, "free" or prices appear in any header, body or image. The offer appears
  only in Apple's own card.
- [x] Loss statements are factual and match the read-only Library gate. View, search, copy, export
  and delete stay free.
- [x] No coercion, urgency, statistics or superlatives. Sentence case, no all caps, no exclamation
  marks.
- [x] When there's an offer, it replaces the image. Subscribers who aren't eligible see the text and
  image.
- [ ] Localize all three for every storefront.
- [ ] Confirm the header and body character limits in App Store Connect.
- [ ] Confirm the Mac app shares the subscription group (message B).

### How the app shows them

Apple shows retention messages and retention offers only in its own in-app management sheet, not
on the web page. Every iOS "Manage Subscriptions" entry opens that sheet:

- Settings uses `AppStore.showManageSubscriptions(in:)` (`MetaSettingsView`).
- Both paywall entries use `.manageSubscriptionsSheet(isPresented:)` (`PaywallView`). They used to
  open `https://apps.apple.com/account/subscriptions` in the browser.

## App Store Connect: retention offers

Location: Subscriptions › each subscription › Subscription Prices › Offers › Retention Offer. Set
per-country prices for every storefront [STOREFRONT LIST]. Each billing plan type allows up to 10
offers.

| # | Subscription | Type | Reference name | Offer identifier | Eligibility |
|---|---|---|---|---|---|
| 1 | Individual Yearly | Pay up front · 1 year · [YOUR PRICE] | `Individual Yearly Retention 1Y` | `bontecou.Voxboard.individual.yearly.retention1y` | Minimum paid duration 1 year; wait between offers 1 year |
| 2 | Individual Weekly | Free · 2 weeks | `Individual Weekly Retention Free 2W` | `bontecou.Voxboard.individual.weekly.retentionfree2w` | Minimum paid duration [4 weeks, or the nearest ASC option]; wait between offers [3 months] |
| 3 | Family Yearly | Pay up front · 1 year · [YOUR PRICE] | `Family Yearly Retention 1Y` | `bontecou.Voxboard.family.yearly.retention1y` | Minimum paid duration 1 year; wait between offers 1 year |
| 4 | Family Weekly | Pay as you go · [N] weeks at [YOUR PRICE] per week | `Family Weekly Retention PAYG` | `bontecou.Voxboard.family.weekly.retentionpayg` | Minimum paid duration [4 weeks]; wait between offers [3 months] |

---

## Google Play Console: offers

Location: Play Console › Monetize with Play › Products › Subscriptions. IDs follow the app's
catalog (`VoxPlayCatalog.kt`): products `vox_unlimited_*`, base plans `weekly` and `yearly`, and
lowercase offer IDs with hyphens. The app shows only `ProductDetails` prices and never hardcodes
any.

Play writes all of the copy on its cancel-flow, retention and win-back screens. Only the offer
(type, phases, price and eligibility) is ours.

### `vox_unlimited_yearly` › base plan `yearly` (P1Y)

| Offer ID | Purpose | Phases | Eligibility | Tags |
|---|---|---|---|---|
| `free-trial-1w` | Existing free trial | Free P1W, then base price | New customer acquisition | (existing) |
| `retention-1y` | Retention offer in Play's cancel flow | 1 × P1Y at [YOUR PRICE], then base price | [CONFIRM PLAY OPTION]; paid ≥ 1 year, once per 1 year (matches iOS) | none |
| `winback-1y` | Win-back offer for lapsed Yearly subscribers | 1 × P1Y at [YOUR PRICE], then base price | Lapsed Yearly, ended ≥ [N] days ago, once per [12 months] | none |
| `switch-yearly-1y` | App-funded offer, shown only in the in-app "Before you go" sheet | **Exactly** 1 × P1Y at [YOUR PRICE] (below the base price, same currency), then base price | **Developer determined** | **`retention-in-app`** (required) |

How the app uses `switch-yearly-1y`:

- **Selection.** The card appears only when `ProductDetails` for `vox_unlimited_yearly` returns this
  offer ID on the `yearly` base plan, with the `retention-in-app` tag and a non-blank offer token.
  Its phases must be exactly one finite P1Y phase priced below a recurring P1Y phase in the same
  currency. The copy says "for the first year, then [price] a year", so any other shape hides the
  card. See `yearlySwitchOffer` in `SubscriptionRetention.kt`.
- **Eligibility.** The app applies this rule itself. The person must be an active, verified Weekly
  subscriber, with Play connected and nothing pending, scheduled or purchasing. Lifetime owners,
  Yearly, free and lapsed users never see it.
- **Purchase.** It's bought as a Weekly → Yearly replacement with `WITH_TIME_PRORATION`, the app's
  existing switch mode, so it starts now and credits the unused weekly time.

### `vox_unlimited_weekly` › base plan `weekly` (P1W)

| Offer ID | Purpose | Phases | Eligibility |
|---|---|---|---|
| `free-trial-1w` | Existing free trial | Free P1W, then base price | New customer acquisition (existing) |
| `retention-free-2w` | Retention offer in Play's cancel flow | Free P2W, then base price | [CONFIRM PLAY OPTION]; paid ≥ [4 weeks], once per [3 months] (matches iOS) |
| `winback-4w` | Win-back offer for lapsed Weekly subscribers | 4 × P1W at [YOUR PRICE], then base price | Lapsed Weekly, ended ≥ [N] days ago, once per [6 months] |

### Plan Change targets: none today

Play's Plan Change step in the cancel flow moves a subscriber to a cheaper base plan. Each Vox.md
subscription has exactly one base plan, so there's no target. Weekly is a separate product and
isn't cheaper over a year. To enable Plan Change, add a lower-priced base plan, for example monthly
at [YOUR PRICE]: [DECISION].

### Other open items

- Some Play cancel-flow retention offers roll out through an Early Access Program:
  [CONFIRM ENROLMENT].
- Play Billing's client API returns no renewal or expiry date, and the app has no server. The app
  therefore says "Google Play shows your next billing date". Showing the date would need the Play
  Developer API and a backend: [DECISION].

### Android in-app surfaces (for reference)

| Surface | Where | What it does |
|---|---|---|
| Settings › Subscription | Settings card, for anyone with a purchase or a lapsed subscription | Shows the plan and its status, the Play price and "Renews automatically. Google Play shows your next billing date." Offers Manage or cancel (subscriptions only), Change plan and Restore Purchase. Lifetime has no cancel path. |
| Before you go | Manage or cancel | A single sheet: the paid period, what stops, what you keep and, for eligible Weekly subscribers, the `switch-yearly-1y` card. "Keep Unlimited" and "Continue to cancel" are the same size. Continue to cancel opens `https://play.google.com/store/account/subscriptions?sku=<product>&package=<package>` in one tap. |
| Subscription ended | Settings › Subscription after a lapse | Shows what's paused, what still works, See plans and Open Google Play subscriptions, where Play shows its win-back offer. |
