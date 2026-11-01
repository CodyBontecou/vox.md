# Android local intelligence parity — November 1, 2026

The custom-instruction path now runs an app-owned, CPU-only llama.cpp model instead
of interpreting a few English keywords. It is wired into both capture delivery and
completed recording processing. Built-in deterministic modes remain available.

The phone-only runtime is llama.cpp b5046, source revision
`74d4f5b041ad837153b0e90fc864b8290e01d8d5`, with its source archive SHA-256 checked
before each native build. All four API-28 ABIs are source-built with portable CPU
settings; no LLM binary or type may leak into optimized Wear artifacts. The default
instruction model is Qwen2.5 1.5B Instruct Q4_K_M, revision
`91cad51170dc346986eccefdc2dd33a9da36ead9`, exactly 1,117,320,736 bytes with SHA-256
`6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e`.
The smaller 0.5B candidate was rejected after it failed a strict output-format case.
MIT/Apache license texts are packaged; both dependencies appear in the SBOM.

Download/ready/cancel/delete controls are available in Models and the custom preset
editor. Downloads are explicit and contain only public model bytes. Size, digest,
free storage and a minimum 3 GB device-memory tier are checked before publication.
An invalid import cannot replace a working model; interrupted partial files are
removed. App-private model files are reverified before generation. Unsupported or
low-memory devices preserve the original capture and show an actionable status.

Inference has no network API. Its context is bounded to 4,096 tokens and a complete
response of at most 1,024 generated tokens, with a 90-second native deadline and
cancellation. Neither source text nor instructions are silently truncated to fit.
Model-role markers in user data are tokenized as literal data. Empty, incomplete,
invalid-UTF-8 or protected-content-losing responses are rejected. URLs, wiki links,
code fences and repeated speaker labels are preserved; benign sentence punctuation
and Markdown label emphasis are accepted. Original text and outcomes remain durable while a capture is pending; completed captures retain payload-free markers under the existing compaction policy. Recording transcripts retain their existing retention policy.
The UI still requires native linguistic review for its translated failure messages.

Frozen preset context is supplied to the model as data. Sending a completed,
processed recording reuses its reviewed result only when its text and processing
policy match the frozen snapshot; it retains the raw transcript for the audit and
avoids applying non-idempotent instructions twice.

## Shared evaluations

`evaluations/local-intelligence/v1/corpus.json` is consumed by Kotlin and Swift.
Six instruction cases test ordered names, exact line/CSV output formats, polite
rewriting, Spanish extraction, required summary facts, URL preservation and speaker
ownership/filler removal. Shared mutation examples reject dropped facts, wrong order,
extra text, retained filler and swapped decisions. These are bounded functional
checks, not a certificate of unrestricted instruction or multilingual quality.

The speaker benchmark uses four public LibriSpeech utterances from two readers,
with their original-file/derived-WAV hashes and attribution recorded in the corpus.
It measures duration-weighted known-turn attribution error after a one-to-one label
permutation. Collapsed speakers, excess labels and missing turns cannot inflate the
score. This is not an overlap/VAD/boundary diarization-error-rate claim.

Apple Foundation Models and the production FluidAudio/SpeakerDiarizationService
provide live Apple reference runs using the same corpus. The Apple speaker baseline
exposes a short-turn quality gap: 29.3% attribution error in the initial measurement.
Reports preserve whether the zero-error target was met. Android must independently
meet the zero-error target and must not regress against the measured Apple baseline;
an unchanged Apple reference measurement is not relabeled as a passed quality gate.
Apple Intelligence weight revisions are system-managed and unavailable through the
public API; the reference report records OS identity instead of inventing a model hash.

## Required model gate

The four former assumption-skipped ASR tests now fail when inputs are missing.
`connectedDebugAndroidTestLocalIntelligence` runs the general phone suite plus
mandatory Vosk and named Whisper Tiny phases, then real instruction and speaker
inference. Fixture hashes are checked before modifying the explicitly selected
emulator; inference runs with connectivity disabled and prior connectivity is restored.
Missing fixtures, skipped tests, incomplete reports and development-only runs fail
qualification. A separate 4 GB AVD is used; the baseline AVD is preserved.

Run with `ANDROID_HOME` and `ANDROID_SERIAL` set:

```
./apps/android/gradlew -p apps/android connectedDebugAndroidTestLocalIntelligence
swift run --package-path Packages/VoxboardShared VoxboardIntelligenceEvaluation evaluations/local-intelligence/v1/corpus.json /tmp/apple-instructions.json
VOXBOARD_SHARED_CONTAINER_OVERRIDE=/tmp/vox-apple-intelligence swift run --package-path Packages/VoxboardShared VoxboardIntelligenceEvaluation evaluations/local-intelligence/v1/corpus.json /tmp/apple-speakers.json speakers
```

Full validation and retained final measurements will be recorded when checks finish.
Physical devices, broader languages/instructions, noisy/overlapping/conversational
speech, latency/memory/thermal budgets and human quality approval remain qualification.
