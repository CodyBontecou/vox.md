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

```sh
PLAY_CONSOLE_KEY_PATH=/path/to/service-account.json \
CONFIRM_PLAY_LISTING_GRAPHICS=md.vox.android:en-US \
apps/android/scripts/upload-google-play-listing-graphics.sh
```

This replaces the en-US feature graphic and all three screenshot sets in one
Play edit. `PLAY_LISTING_DRY_RUN=1` validates the edit without committing it.
