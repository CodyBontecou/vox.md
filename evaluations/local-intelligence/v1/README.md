# Shared local-intelligence evaluation v1

`corpus.json` is the same input and scoring contract for Android and Apple runners.
It tests instruction following beyond the deterministic keyword fallback, required
facts, output size, links and speaker ownership. Passing these six cases is a small
functional gate, not proof of unrestricted instruction or multilingual quality.

Speaker clips are four unmodified utterances from LibriSpeech dev-clean, converted
losslessly from FLAC to mono 16 kHz PCM WAV with FFmpeg. Readers 2277 and 2035 are
alternated to test both separation and returning-speaker attribution. The corpus
records the source-FLAC and committed-WAV SHA-256 and exact duration. Source archive:
https://www.openslr.org/resources/12/dev-clean.tar.gz (LibriSpeech, CC BY 4.0;
https://www.openslr.org/12). Attribution: Vassil Panayotov, Guoguo Chen, Daniel Povey
and Sanjeev Khudanpur, “LibriSpeech: An ASR corpus based on public domain audio
books,” ICASSP 2015; recordings derived from LibriVox volunteers.

The speaker metric is duration-weighted known-turn attribution error after the
best **one-to-one** mapping of anonymous predicted labels to reference speakers.
A collapsed single-speaker output, extra labels, missing turns and invalid durations
are penalized. This is not an overlap/VAD/boundary diarization-error-rate benchmark.
Results must identify runtime/model/source revision and separate real-model runs
from scorer/unit tests. Physical-device, noisy/conversational and overlap benchmarks
remain additional qualification.
