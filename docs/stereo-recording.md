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
  reuses that mono engine; the settings footer says so.
- If the engine's input node still reports one channel after configuration,
  the take records mono and the log says
  `Stereo input reported 1 ch; keeping mono`. Nothing fails.
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
5. With Stereo still on, turn on Keyboard Listening and dictate: it stays
   mono (log shows `Stereo input: notRequested`) and transcribes as before.
6. Optional: rotate to landscape before a take; left/right should follow the
   screen.

## Follow-up: Spatial Audio (not in this change)

Spatial Audio capture (iOS 26 Audio Mix, WWDC25 session 251) needs more than
this change's `AVAudioEngine` input tap. Expected work, to be confirmed
against the session and its sample code:

- Capture: an `AVCaptureSession` audio input with the spatial (first-order
  ambisonics) multichannel format on supported iPhones, instead of the shared
  always-on engine that also feeds live transcription.
- File: write the spatial audio track plus the stereo compatibility track
  and its metadata (`AVAssetWriter`), rather than `AVAudioFile`.
- Transcription: render a 16 kHz mono downmix from the spatial track (or use
  the stereo compatibility track) so transcripts match.
- Pre-roll and crash recovery would need the same treatment as the kept
  file has here, and export/playback paths must keep the spatial track.
- Settings: a third layout option shown only on devices that support it.
