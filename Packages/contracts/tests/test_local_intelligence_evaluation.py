import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]
SPEC=importlib.util.spec_from_file_location("intelligence_evaluations",ROOT/"apps/android/scripts/validate-intelligence-evaluations.py")
VALIDATOR=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(VALIDATOR)

class LocalIntelligenceEvaluationTests(unittest.TestCase):
    def setUp(self): self.corpus=json.loads(VALIDATOR.CORPUS.read_text())
    def test_shared_audio_hashes_formats_and_zero_error_target_are_bound(self):
        VALIDATOR.validate_corpus(self.corpus)
        broken=copy.deepcopy(self.corpus);broken["speakerMaximumAttributionError"]=.5
        with self.assertRaisesRegex(ValueError,"weakened"):VALIDATOR.validate_corpus(broken)
        broken=copy.deepcopy(self.corpus);broken["speakerAudio"][0]["sha256"]="0"*64
        with self.assertRaisesRegex(ValueError,"digest"):VALIDATOR.validate_corpus(broken)
    def test_dropping_an_instruction_case_fails_closed(self):
        self.corpus["instructionCases"].pop()
        with self.assertRaisesRegex(ValueError,"inventory"):VALIDATOR.validate_corpus(self.corpus)
    def test_speaker_reports_cannot_hide_collapse_or_missing_turns(self):
        self.assertAlmostEqual(.5,VALIDATOR.speaker_error(["a","b","a","b"],["1"]*4,[1]*4))
        self.assertAlmostEqual(0,VALIDATOR.speaker_error(["a","b"],["2","1"],[1,1]))
        with self.assertRaisesRegex(ValueError,"lost turns"):VALIDATOR.speaker_error(["a","b"],["1"],[1,1])
    def test_four_model_methods_are_mandatory_instead_of_assumption_skips(self):
        for name in ("LocalSpeechInferenceInstrumentationTest.kt","NamedModelInferenceInstrumentationTest.kt"):
            source=(ROOT/"apps/android/app/src/androidTest/kotlin/md/vox/android"/name).read_text()
            self.assertNotIn("assumeTrue",source)
            self.assertEqual(source.count("@ProvisionedModelTest"),2)
        for name in ("validate-local-speech.py","validate-named-speech-model.py"):
            self.assertIn('"INSTRUMENTATION_STATUS_CODE: -4"',(ROOT/"apps/android/scripts"/name).read_text())
    def test_native_and_model_pins_are_consistent_with_the_sbom(self):
        manager=(ROOT/"apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/InstructionModelManager.kt").read_text()
        self.assertIn(VALIDATOR.MODEL_SHA256,manager)
        sbom=json.loads((ROOT/"artifacts/android-release/vox-android-sbom.cdx.json").read_text())
        self.assertEqual(sum(VALIDATOR.MODEL_SHA256 in json.dumps(c) for c in sbom["components"]),1)
        self.assertNotIn("java.net",(ROOT/"apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/LocalIntelligence.kt").read_text())
    def test_retained_full_model_and_cross_platform_reports_are_truthful(self):
        VALIDATOR.validate_reports(self.corpus,VALIDATOR.REPORTS)
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)
            for path in VALIDATOR.REPORTS.glob("*.json"): (target/path.name).write_bytes(path.read_bytes())
            path=target/"receipt.json";receipt=json.loads(path.read_text());receipt["fullPhoneSuite"]=False;path.write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ValueError,"development-only"):VALIDATOR.validate_reports(self.corpus,target)

if __name__=="__main__":unittest.main()
