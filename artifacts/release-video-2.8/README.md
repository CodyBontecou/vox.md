# Vox.md 2.8 release video

Generated with Remotion from the existing Argent-captured simulator clips in
`artifacts/release-notes-2.8/notelet/`.

Output:

- `vox-md-2.8-release.mp4` — 1080×1920, 30 fps, 56.9s, silent H.264
- `vox-md-2.8-poster.png` — poster frame
- `vox-md-2.8-contact-sheet.jpg` — quick visual review sheet

Composition source:

- `release-video/src/index.tsx`
- `release-video/public/clips/*.mp4`

Re-render:

```sh
cd release-video
npm run render
npm run still
```

Note: Argent can control the connected physical iPhone, but Argent screen
recording is not supported for physical iPhones. This cut uses automated Argent
simulator footage plus a Remotion text card for the hardware/Shortcuts Toggle
Recording feature.
