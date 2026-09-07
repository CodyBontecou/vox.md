# iPhone microphone: all-zero input — September 7, 2026

Status: **input failure reproduced; user subsequently reports in-app recording recovered; underlying cause unresolved**. The code change improves diagnosis and error reporting, not microphone recovery, and was not installed on the phone before the user reported recovery.

## Observations

On the connected iPhone 17 Pro running iOS 27 beta (24A5430a), the in-app mic displayed “No speech detected.” The app's debug log showed:

- A 24 kHz input route captured 7.2 and 5.3 seconds with peak amplitude logged as zero.
- The built-in 48 kHz input captured 3.9 seconds with peak amplitude logged as zero.
- Those attempts failed the input-amplitude check before transcription. Parakeet v2 was selected and successfully prepared; it was not invoked for these attempts.

An opt-in, temporary XCTest probe then inspected the **raw input buffers before conversion**, alongside the existing 16 kHz conversion:

- Microphone permission granted, `AVAudioApplication.shared.isInputMuted == false`, input gain `1.0`, built-in microphone route.
- Every raw and converted sample was exactly zero.
- The result was unchanged with or without reasserting the active audio session, without mixing, in record/measurement mode, or in play-and-record/measurement mode.
- Each configuration used a fresh engine. A typical two-second probe delivered 96,000 raw frames and 31,779 converted frames, both with a peak of exactly zero.

The probe retained aggregate levels only and did not change microphone permission, input mute, or app preferences. It restored the previous audio-session category/mode/options and was removed from the repository after use. Its XCTest success means the diagnostic executed, **not** that microphone capture succeeded. This does not establish whether Voice Memos or other apps are affected.

## Code change and regression checks

`Voxboard/RecordingInputValidation.swift` distinguishes all-zero input, muted input, and low-but-nonzero input instead of labeling all three “No speech detected.” It preserves usable audio captured before a later mute. `PersistentRecorder.swift` uses the classification and logs route type, sample rate, gain, mute state, and a peak value that does not round tiny nonzero signals to `0.0000`.

The five new classification tests and seven existing recording pause/resume tests passed on the iOS 27 simulator: **12 tests, 0 failures**. This validates error classification and existing pause behavior, not hardware recovery.

Local evidence (not committed):

- `/tmp/vox-mic-debug.log`
- `/tmp/vox-mic-diagnostics.xcresult`, `/tmp/vox-mic-diagnostics.log`
- `/tmp/vox-mic-diagnostics2.xcresult`, `/tmp/vox-mic-diagnostics2.log`
- `/tmp/vox-MicrophoneInputDiagnosticsTests.swift` (final diagnostic configurations)
- `/tmp/vox-mic-validation-tests.xcresult`, `/tmp/vox-mic-validation-tests.log`

The user subsequently reported that in-app recording was working again. No Voice Memos result or instrumented successful capture was collected. Treat this as user-reported recovery from an intermittent input failure, not proof that the code change fixed it. If it recurs, check Voice Memos before restarting to distinguish a Vox.md-specific problem from a phone-wide input problem.
