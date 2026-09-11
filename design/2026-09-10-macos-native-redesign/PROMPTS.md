# Concept-generation prompts

Mode: built-in image generation, using the organized screenshots as visual references.

## 01 — Capture workspace

```text
Use case: ui-mockup
Asset type: high-fidelity macOS desktop app concept screenshot
Primary request: Reimagine the Vox.md Capture workspace as a beautiful, unmistakably Mac-native desktop application. This is a new design inspired by the supplied current-app screenshots, not an edit and not a visual restyling of the current layout.
Input images: Image 1 is the current Capture workspace reference for feature inventory only; preserve the product purpose but replace the visual hierarchy and interaction model.
Scene/backdrop: one complete resizable Mac application window filling a landscape 16:10 frame, with standard red/yellow/green traffic lights and a unified title bar.
Subject: a focused document-style capture workspace. A narrow translucent source-list sidebar contains only "Capture" selected, "Activity", and "Library", plus a small "Favorites" group with "Default". The center is a clean white Markdown document editor showing a short realistic note titled "Project kickoff" with a few lines of transcript. A standard trailing inspector is open with compact sections for "Destination", "Processing", and "Attachments".
Style/medium: shippable native macOS product UI, realistic screenshot, SF Symbols-like line icons, San Francisco system typography, crisp 1x desktop density, subtle vibrancy and hairline dividers.
Composition/framing: standard sparse toolbar integrated into the title bar with sidebar toggle, New Capture, a "Default" preset pop-up, a clear coral recording/stop control with a tiny live waveform and elapsed time, and an inspector toggle. Generous document margins but no empty wasteland.
Color palette: system white, warm off-white, graphite text, restrained cool-gray chrome; coral/vermilion used only for active voice recording. System blue only for selection/focus.
Text (verbatim, sparse): "Vox.md", "Capture", "Activity", "Library", "Favorites", "Default", "Project kickoff", "Destination", "Processing", "Attachments", "Recording 00:42", "Send".
Constraints: practical desktop layout; all text legible; no bottom command bar; no oversized rounded cards; no pill-heavy segmented controls; no yellow warning banner; no iPad-style settings rows; no giant circular chevrons; no duplicated controls; no logo other than the text Vox.md; no watermark.
```

Reference: `01-current-ui/03-capture-main.png`

## 02 — Activity workspace

```text
Use case: ui-mockup
Asset type: high-fidelity macOS desktop app concept screenshot
Primary request: Design the Vox.md Activity workspace that unifies the current Recording Queue and History into one coherent Mac-native desktop workflow, matching the same design system as a premium native Capture app.
Input images: Image 1 is the current Recording Queue reference and Image 2 is the current History reference; use them only to understand content and states, then replace their iOS-like cards and duplicated empty panes.
Scene/backdrop: one complete Mac application window filling a landscape 16:10 frame, standard traffic lights, unified title bar and toolbar.
Subject: a three-column macOS split view. Left translucent source-list sidebar has "Capture", "Activity" selected with badge 2, and "Library". Middle column is a dense chronological list grouped "Now" and "Today": "Interview notes" is Transcribing at 68% with a thin progress indicator; "Voice memo" is Failed with a subtle coral status; "Project kickoff" is Sent; "Book quote" is Draft. Right detail pane shows the selected "Interview notes" item with compact metadata, waveform, readable transcript preview, and contextual "Retry" only where relevant.
Style/medium: shippable native macOS product UI, realistic screenshot, system typography, compact row density, SF Symbols-like line icons, subtle vibrancy, hairline separators, restrained shadows.
Composition/framing: native toolbar with sidebar toggle, title "Activity", a segmented filter "All  In Progress  Needs Attention" kept compact, trailing search field, and inspector toggle. Rows use selection highlight and context, not separate floating cards.
Color palette: system white, warm off-white, graphite, cool gray; coral/vermilion only for voice activity and failure; system blue for selection.
Text (verbatim, sparse): "Activity", "Capture", "Library", "Now", "Today", "Interview notes", "Transcribing 68%", "Voice memo", "Failed", "Project kickoff", "Sent", "Book quote", "Draft", "Retry", "Search Activity".
Constraints: practical desktop information architecture; readable typography; no huge empty canvas; no oversized rounded cards; no bottom toolbar; no duplicated empty state; no iPad-style form rows; no giant circular chevrons; no watermark.
```

References: `01-current-ui/04-recording-queue.png`, `01-current-ui/06-history-empty.png`

## 03 — First-run setup

```text
Use case: ui-mockup
Asset type: high-fidelity macOS first-run setup assistant concept screenshot
Primary request: Design a welcoming first-run Setup Assistant for Vox.md that replaces the current warning-first destination and model setup experience. It must feel like a refined native Mac utility, not an iOS settings screen enlarged for desktop.
Input images: Image 1 is the current destination setup reference and Image 2 is the current transcription model catalog reference; use them only for functional requirements.
Scene/backdrop: a compact centered Mac setup window about 760 by 560 points on a softly blurred neutral desktop, standard traffic lights and a simple title bar.
Subject: "Welcome to Vox.md" with a small elegant waveform mark and one-sentence explanation. A compact aligned setup grid has four desktop-style rows separated by hairlines: "Notes folder" with path "~/Documents/Notes" and "Choose…"; "Transcription" with "Parakeet v3 · Recommended" and "800 MB"; "Microphone" with status "Ready"; "Quick capture" with shortcut "⌥ Space". A small privacy note says processing stays on this Mac.
Style/medium: shippable native macOS setup assistant, realistic screenshot, San Francisco system typography, compact controls, precise alignment, white and translucent materials, no decorative illustration.
Composition/framing: comfortable margins; one clear blue primary button "Use Recommended Setup" at bottom right, secondary button "Customize…" beside it, and "Not Now" as a quiet text action. The primary decision is obvious without a wall of options.
Color palette: system white, graphite, cool gray; a restrained coral waveform accent; system blue primary action.
Text (verbatim): "Welcome to Vox.md", "Capture thoughts without breaking your flow.", "Notes folder", "~/Documents/Notes", "Choose…", "Transcription", "Parakeet v3 · Recommended", "800 MB", "Microphone", "Ready", "Quick capture", "⌥ Space", "Processing stays on this Mac.", "Not Now", "Customize…", "Use Recommended Setup".
Constraints: all text legible; one compact Mac window; no permanent sidebar; no scrolling; no stacked rounded iOS cards; no oversized switches; no giant circular buttons; no warning banners; no mobile onboarding dots; no watermark.
```

References: `01-current-ui/01-destination-setup.png`, `01-current-ui/07-transcription-models.png`

