# Signal UI Source of Truth

Vox.md’s UI follows the **Signal** redesign (the “Vox.md — Signal redesign” design canvas). Signal keeps the Geist type families and spacing rhythm from the vendored Vercel Geist specifications in this directory (`design.md`, `design.dark.md`) but replaces their color, radius and control styling:

| Role | Light | Dark |
|---|---|---|
| Ground | `#F2F2EE` | `#0B0B0B` |
| Card | `#FFFFFF` | `#161616` |
| Border | `#DEDED8` | `#2A2A28` |
| Ink | `#121212` | `#F4F4F1` |
| Muted | `#5E5E5A` | `#9A9A95` |
| Accent fill (Send, default route) | `#2F3BE8` | `#2F3BE8` |
| Accent text / tint | `#2F3BE8` | `#9DA4FF` / `#6E78FF` |
| Recording | `#F0474A` | `#F0474A` |
| Needs you | `#E8590C` | `#FF8A4C` |
| Delivered | `#0F7B5F` | `#4CC9A0` |

Cards use 14–18pt continuous corners and a 1pt border with no shadow. Buttons are pills; primary is ink on ground, Send is the indigo fill. Section labels are Geist Mono, uppercase, 11pt.

`Voxboard/GeistTheme.swift` is the SwiftUI implementation (`Geist.*` tokens plus the `Signal*` components); `Voxboard Mac/MacBrand.swift` maps the Mac’s accent names onto it. `website/geist.css` is the web implementation. UI changes must use these tokens rather than ad-hoc colors.

The bundled Geist Sans and Geist Mono files live in `Voxboard/Fonts/` and `website/fonts/` under Vercel’s license. Geist Sans is for UI and prose. Geist Mono is for code, file paths, timers, sizes, metadata and section labels.

When the Signal design changes, update `GeistTheme.swift` and `website/geist.css` together, and keep this table in sync.
