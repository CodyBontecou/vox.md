# Stereo recording on iPhone (#118)

High and Lossless can record in stereo from the iPhone's built-in microphones
(Settings → Recording Quality → Stereo). Speech, the Watch, keyboard
dictation and Keyboard Listening stay mono.

## How it works

- `StereoRecordingInput` follows Apple's *Capturing stereo audio from built-in
  microphones*: it picks a built-in mic data source whose supported polar
  patterns include `.stereo` (front, then back, then any), sets it as the
  preferred data source with the stereo pattern, and sets the input
  orientation from the interface orientation (again at each take start).
- Only when the current input route is the built-in mic. Wired, USB,
  Bluetooth/AirPods and CarPlay inputs are never overridden.
- Only for a one-shot recording that can keep its audio
  (`PersistentRecorder.oneShotMayKeepAudio`). Keyboard dictation, continuous
  dictation and Keyboard Listening keep the mono input their transcripts have
  always used. A recording started while Keyboard Listening is already on
  reuses that mono engine; the footer says so, and while Keyboard Listening
  is on and Stereo is on, the Stereo row shows a warning.
- The input node's real channel count decides stereo vs mono
  (`StereoRecordingInput.keptChannelCount`): two only when stereo was set up
  and the node delivers two channels. The route is given ~200 ms to report the
  stereo pattern, and the log records whether it did
  (`stereo(dataSource:…, routeConfirmed:…)`), but a late route report never
  turns stereo off. A two-channel interface that was not set up for stereo
  (USB, line in) stays mono, and a node that still delivers one channel logs
  `Stereo input reported 1 ch; keeping mono`.
- The stereo data source is undone when listening stops, so it never carries
  over to Keyboard Listening or another app. It is never pinned with
  `setPreferredInput`, so AirPods or a headset connected later still win.
- The live 16 kHz stream mixes channels only for a stereo take. Other
  multichannel inputs (USB, line in) keep their first-channel conversion.
  The mix is an average: a source centred between the mics gives the same
  16 kHz signal as a mono take, without clipping (tested).
- An interruption or engine restart ends the current take before listening
  restarts, so a take never switches from stereo to mono halfway. A route
  change the engine survives (one channel arriving on a stereo tap) is
  copied to both sides (dual-mono). The recorder logs how many frames of the
  take that affected when the file is finished.
- Recovered takes: only stereo kept files get the new downmixed copy. Mono
  recovered files reach the engine exactly as before.
- Undoing the stereo selection is retried until the session accepts it; a
  relaunch always starts from the system default (session preferences are
  per process).

## Checked on the simulator

`.argent/e2e/stereo-recording-mono-fallback.yaml` records a real take with
High + Stereo on. The simulator mic has no stereo data sources, which is the
same fallback path as an external, Bluetooth or AirPods mic: the log reads
`Stereo input: unavailable(reason: "built-in mic has no data sources")` and
the saved file is `1 ch, 48000 Hz, aac` (afinfo). Real 2-channel output still
needs the device check below.
- Transcription: the live 16 kHz stream and the 16 kHz copy of a kept file
  mix both channels (`downmix`). Imported files keep their existing
  conversion (first channel only), so their transcripts do not change.
  Recovered High/Lossless takes get the same mixed copy as live ones.
- If the route drops to one channel mid-take, the tap copies it to both
  sides so the kept file keeps recording.

## Device check (the simulator has no stereo microphones)

Run before release on an iPhone XS or later, built-in mics, no headset:

1. Settings → Recording Quality → High, Stereo on. Make sure Keyboard
   Listening is off.
2. Record ~10 s from the app (or a widget/Shortcut) while speaking from the
   left, then the right, of the phone. Finish the recording.
3. Pull the kept file (Files, or Xcode → Devices → app container) and run
   `afinfo <file>.m4a`. Expect `2 ch, 48000 Hz` and AAC (High) or ALAC
   (Lossless). Playback should pan left/right.
4. Connect AirPods (or a wired/USB mic), record again: expect `1 ch` and a
   saved recording. Disconnect them and record again: expect `2 ch`.
5. A/B transcript check: record the same short speech (same position, front
   of the phone) once with Stereo off and once with Stereo on; the two
   transcripts should match. The unit tests only prove that a centred source
   gives the same 16 kHz signal.
6. With Stereo still on, turn on Keyboard Listening and dictate: it stays
   mono (log shows `Stereo input: notRequested`) and transcribes as before.
7. Optional: rotate to landscape before a take; left/right should follow the
   screen.

## Spatial Audio (#133)

Settings → Recording Quality now offers **Mono / Stereo / Spatial Audio** for
High and Lossless (stored as `recordingStereo` + `recordingSpatialAudio`, never
synced to Apple Watch). Spatial Audio is listed only on an iPhone on iOS 26+
whose built-in mic supports first-order ambisonics (FOA); elsewhere the row is
hidden and the footer says why.

### Capture path

`AVAudioEngine` input taps can't deliver FOA, so a Spatial take records
through an `AVCaptureSession` (`Voxboard/SpatialAudioCapture.swift`) **instead
of** the engine. The two are never run together: FOA capture reconfigures the
built-in mics, which would trip the engine's configuration-change handling
mid-take, and nothing on the simulator could prove coexistence.

- Only for a one-shot take that keeps its audio and starts listening fresh
  (same rule as Stereo). Keyboard Listening, dictation and continuous
  dictation stay on the mono engine.
- The capture session uses the app's audio session and, by default, doesn't
  reconfigure it (`automaticallyConfiguresApplicationAudioSession = false`),
  so category, options and the per-take re-assert stay as they are. For a
  device test, `-VoxSpatialAutoConfiguresSession YES` lets it configure the
  session itself.
- Two `AVCaptureAudioDataOutput`s on the mic input with
  `multichannelAudioMode = .firstOrderAmbisonics`: FOA
  (`HOA_ACN_SN3D | 4`) and stereo.
- The stereo output, averaged to 16 kHz mono, feeds the same circular buffer
  and journal the engine tap feeds, so pre-roll, live transcription, voice
  auto-stop and crash recovery of the 16 kHz journal work as before.
- Start-up is checked, not assumed: the recorder waits up to 0.75 s for a
  4-channel FOA buffer and a 2-channel stereo buffer. Anything else (iOS
  before 26, no FOA mic, AirPods/wired/USB route, session error, no buffers)
  stops capture and falls back to the engine with Stereo requested, which
  itself falls back to mono. The log says why
  (`Spatial Audio capture unavailable (…); falling back to Stereo`).
- If capture stops mid-take (call, another app, media services reset), the
  take is cancelled with its 16 kHz journal kept for recovery, like an
  audio-session interruption.
- Pre-roll: the capture queue keeps ~4 s of deep-copied FOA/stereo buffers, so
  the spatial file starts at the same instant as the journal's seed. A
  one-shot take starts listening at take start, so there is little pre-roll
  either way. Listening start is slower by the probe (up to ~0.75 s, usually
  the first buffer interval).

### File

`kept_<request>_<uuid>.mp4` (`SpatialAudioFileWriter`, VoxboardShared):

1. stereo compatibility track, first and disabled: AAC ≈ 128 kbps (High) or
   ALAC (Lossless);
2. FOA track, APAC (settings from the capture output's recommendation),
   enabled, default of the alternate group shared with track 1;
3. one timed-metadata sample from `AVCaptureSpatialAudioMetadataSampleGenerator`
   (every FOA buffer analyzed), associated with the FOA track.

Why `.mp4` and this order: `.m4a` can't hold APAC (AVAssetWriter rejects it),
and iOS's AudioFile (AVAudioFile, AVAudioPlayer) can't open QuickTime `.mov`
but opens `.mp4` and reads its first audio track. With stereo first, the app's
existing duration checks, in-app players and 16 kHz conversion work on a
spatial file unchanged (checked on the simulator), while AVFoundation players
pick the enabled FOA track.

- Transcription copy: `KeptAudioInspector.makeTranscriptionCopy` reads the
  stereo track with AVAssetReader and averages it to 16 kHz mono.
- Export to the vault copies the bytes and keeps `.mp4`
  (`shouldPreserveEncoding`, `exportFileExtension`). Markdown embeds an `.mp4`
  as a video-style player in the app (AVPlayer); in-app audio players play the
  stereo track.
- Recovery: a claimed `kept_….mp4` recovers as one job and gets the downmixed
  copy (`isKeptMultichannelRecording`).
- Pauses are cut out of the file (later buffers are shifted back).
- Storage: spatial ≈ stereo size + 1.92 MB/min for the FOA track (High ≈ 3
  MB/min, Lossless ≈ 8 MB/min); the storage guard uses the same numbers.

### Device check (needs an iPhone 16/17 Pro or another FOA-capable iPhone)

Nothing here could run on the simulator. On a supported iPhone with iOS 26+:

1. Settings → Recording Quality → High → Spatial Audio. Keyboard Listening off.
2. Record ~20 s from the app, walking around the phone while talking. Check the
   log for `Spatial Audio capture started (FOA + stereo)` and, on stop,
   `Take finished: saved, … metadata=true`.
3. `afinfo` / `mediainfo` the kept `.mp4`: a 2-ch AAC track (disabled) and a
   4-ch APAC track. Play it in Files and Photos/QuickTime with AirPods Pro and
   listen for spatial rendering. If FOA never starts, retry with
   `-VoxSpatialAutoConfiguresSession YES`.
4. Transcript A/B against a Stereo take of the same speech.
5. Connect AirPods and record: expect the Stereo→mono fallback and a saved
   `.m4a`.
6. Lossless + Spatial: expect an ALAC stereo track.
7. Background the app mid-take and lock the phone: confirm capture keeps
   running (audio background mode) or that the take lands in recovery.
