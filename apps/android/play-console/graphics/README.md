# Google Play listing graphics

Source of truth: the **Vox.md — Google Play** design canvas
(https://claude.ai/artifact/2N2qLEenCQaPQxvaaY35XG). These PNGs are straight
renders of its artboards; edit the canvas, then re-export rather than editing
the PNGs.

| Play slot              | Files                              | Size      | Canvas artboards          |
| ---------------------- | ---------------------------------- | --------- | ------------------------- |
| Feature graphic        | `feature-graphic-1024x500.png`     | 1024×500  | `FeatureGraphic`          |
| Phone screenshots      | `screenshots/phone/01–07.png`      | 1080×1920 | `Phone01Capture`–`Phone07History` |
| 7-inch tablet          | `screenshots/tablet-7/01–03.png`   | 1920×1200 | `Tab7Capture`, `Tab7History`, `Tab7Dark` |
| 10-inch tablet         | `screenshots/tablet-10/01–03.png`  | 2560×1600 | `Tab10Capture`, `Tab10History`, `Tab10Dark` |
| App icon               | `app-icon-512.png`                 | 512×512   | see below                 |

File names sort in listing order.

The app icon ("I.7 · Singing .md file") lives on the **Vox.md — App Icon**
canvas (https://claude.ai/artifact/WzdzZxu7AKoVAbMVYnAQve, artboard `Doc7`).
Its 1024px render is the canonical
`Voxboard/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`; every iOS,
macOS, Watch and Play size is a resize of it, and Gradle derives the Android
launcher set from it. The themed-icon glyph is
`apps/android/branding/launcher-monochrome-1024.png`.

## Uploading

GitHub Actions owns uploads; there is no local Play key. Both paths run
`apps/android/scripts/upload-google-play-listing-graphics.sh` as the
`play-publisher` service account (Workload Identity, `google-play` environment):

- **Every Android Release** syncs these files after the bundle upload (the
  `Sync Play listing graphics` job), so committing new graphics before tagging is
  enough.
- **Between releases**, run the **Android Play Listing** workflow from `main`.
  It defaults to a dry run that lists which image sets differ; untick
  `dry_run` to commit.

The sync compares each set (icon, feature graphic, phone, 7-inch, 10-inch) with
what Play serves by SHA-256 and order, replaces only the sets that differ, and
commits nothing when everything matches. It refuses to commit while a submission
is in review rather than cancel it; re-run the workflow once review finishes.
