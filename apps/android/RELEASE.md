# Android release gates

The local, credential-free release gate builds optimized phone and Wear App Bundles, validates manifests and backup exclusions, checks native ABIs and Wear runtime isolation, verifies the exact shared Geist and Geist Mono font hashes in APK/AAB packaging, verifies the committed CycloneDX inventory, and validates the hashes, dimensions, provenance, and explicitly unreviewed state of the retained visual-parity captures:

```sh
./gradlew releaseReadiness
```

The phone bundle includes the pinned Whisper Small ONNX model as an install-time Google Play AI
pack. On a clean build, `:whisper_small:provisionBundledWhisperSmall` downloads the three model
files from their immutable Hugging Face revision and verifies their exact sizes and SHA-256 hashes.
The assets are generated and ignored by Git. `:app:validateReleaseBundle` independently verifies
the source files and the copies inside the final AAB; a missing, stale, or altered model fails the
release gate.

Named speech-model qualification is an explicit device gate because it downloads large immutable packages and is intentionally excluded from the routine connected suite. Run it once for each supported model ID with the reviewed 16 kHz fixture:

```sh
ANDROID_HOME=/path/to/android-sdk \
ANDROID_SERIAL=emulator-5554 \
VOX_TEST_SPEECH_WAV=/absolute/path/to/vosk-api-test.wav \
VOX_TEST_NAMED_MODEL_ID=ggml-tiny \
./gradlew connectedDebugAndroidTestNamedModel
```

Accepted IDs are `ggml-tiny`, `ggml-base`, `ggml-small`, `ggml-medium`, `ggml-large-v3-turbo`, `parakeet-v2`, and `parakeet-v3`. Each run downloads and verifies the pinned package while online, switches the device to airplane mode, transcribes the exact-hash fixture through the production capture and transcription clients, and clears the isolated app sandbox afterward. Medium requires at least 3.5 GB of reported device memory and Large v3 Turbo at least 6.5 GB; qualifying those models therefore requires a suitably provisioned emulator or physical device. The fixture must have SHA-256 `dcfea5712c43a43ba7ae8083afb39d36993e5a69c46e88b68aaa72b65cb615bb`.

The generated bundles are intentionally unsigned when production signing variables are absent. Production signing uses one Play-compatible key for the phone and Wear modules and reads credentials only from the process environment:

```text
VOX_ANDROID_STORE_FILE
VOX_ANDROID_STORE_PASSWORD
VOX_ANDROID_KEY_ALIAS
VOX_ANDROID_KEY_PASSWORD
```

With all four values present, run:

```sh
./gradlew signedReleaseReadiness
```

That task performs every credential-free release check and then verifies the JAR signatures on both AABs. It fails closed for a partial environment, missing keystore, unsigned bundle, or invalid signature. Keystores are ignored by Git and must remain outside the repository and CI logs.

Passing this local gate does not constitute a Play release. The Play Console product configuration, app-signing enrollment, Data Safety and foreground-service declarations, internal/closed/staged tracks, rollback, provider repair, purchase repair, and content-recovery drills still require their retained external evidence.

Passing the visual-evidence integrity gate is likewise not human visual approval. The current manifest intentionally remains `captured-unreviewed`; approve it only through a reviewed change that also updates the gate's policy and retained evidence.
