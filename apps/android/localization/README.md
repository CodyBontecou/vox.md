# Android translation sources

The generator reads the iOS catalog first, then the Android supplementary catalog
and its explicit overrides. It never edits the iOS catalog. All 22 non-English
languages are required for every supplementary source. Placeholder indices/types,
brace tokens, integer-source classification and CLDR category completeness are
checked before any resources are written.

`android-strings.json` contains 571 offline M2M100 1.2B draft translations: the
original 557 missing sources plus the quantity patterns added during migration.
`android-overrides.json` corrects domain terms, reuses equivalent iOS wording and
preserves literal file/identifier examples. `plural-spec.json` owns all 12 plural
patterns and explicitly classifies six numeric formats that are not quantities.
Every layer requires human linguistic review; coverage is not approval. Review
long explanations as well as labels for meaning, grammar, terminology and UI fit.

Normal development needs only Python's standard library:

```
python3 apps/android/scripts/generate-runtime-localizations.py
python3 apps/android/scripts/generate-runtime-localizations.py --check
python3 -m unittest discover -s Packages/contracts/tests -p test_android_localization_audit.py
```

The optional draft authoring script uses the existing localization pipeline's
Torch/Transformers/SentencePiece/OpenCC dependencies. Download the public
`facebook/m2m100_1.2B` model separately. Pass its local directory and a JSON array of
English source strings to `translate-android-localizations.py --model PATH
--sources PATH`. Inference is offline with `local_files_only=True`; repository
strings are never sent to a translation service. The model is MIT licensed.
Review generated drafts and edit explicit overrides before regenerating resources.
Machine output alone must never set `humanApproved` to true.
