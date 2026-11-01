import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]
SPEC=importlib.util.spec_from_file_location("physical_validation",ROOT/"apps/android/scripts/validate-physical-capture.py")
VALIDATOR=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(VALIDATOR)
RUNNER=VALIDATOR.RUNNER

class PhysicalCaptureQualificationTests(unittest.TestCase):
    def endurance(self):
        return {"scenario":"physical-60-minute-microphone","device":{"emulator":False,"manufacturer":"Google"},
            "wallSeconds":3601,"final":{"finalizedBytes":115200000,"phase":"COMPLETED","wavExportVerified":True,"wavBytes":115200044},
            "sampleCount":240,"maximumSampleGapSeconds":16,"processChanged":False,"recordingInterrupted":False,
            "startImplementationHashes":{"recorder":"a"*64},"endImplementationHashes":{"recorder":"a"*64},
            "installedBuildHashes":{"recorder":"a"*64}}

    def test_real_hour_and_microphone_workload_are_required(self):
        good=self.endurance();RUNNER.validate_endurance(good)
        for key,value in [("wallSeconds",3599),("scenario","imported-hour"),("sampleCount",10),("processChanged",True)]:
            bad=copy.deepcopy(good);bad[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):RUNNER.validate_endurance(bad)
        bad=copy.deepcopy(good);bad["device"]["emulator"]=True
        with self.assertRaisesRegex(ValueError,"physical"):RUNNER.validate_endurance(bad)

    def test_lost_audio_invalid_wav_and_stale_builds_fail(self):
        for field,value in [("finalizedBytes",1000),("wavBytes",115200043),("phase","INTERRUPTED"),("wavExportVerified",False)]:
            bad=self.endurance();bad["final"][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):RUNNER.validate_endurance(bad)
        bad=self.endurance();bad["installedBuildHashes"]={"recorder":"b"*64}
        with self.assertRaisesRegex(ValueError,"installed recorder"):RUNNER.validate_endurance(bad)

    def test_recovery_prefix_requires_every_original_chunk_exactly_once(self):
        before={"sessionID":"recording","chunks":[{"name":"chunk-000000.pcm","bytes":64000,"sha256":"a"*64}]}
        after=copy.deepcopy(before);after["chunks"].append({"name":"chunk-000001.pcm","bytes":2000,"sha256":"b"*64})
        self.assertTrue(RUNNER.preserved_prefix(before,after))
        for mutation in ["changed","missing","duplicate","session"]:
            bad=copy.deepcopy(after)
            if mutation=="changed":bad["chunks"][0]["sha256"]="c"*64
            elif mutation=="missing":bad["chunks"].pop(0)
            elif mutation=="duplicate":bad["chunks"].append(copy.deepcopy(bad["chunks"][0]))
            else:bad["sessionID"]="different"
            self.assertFalse(RUNNER.preserved_prefix(before,bad),mutation)

    def test_emulator_preflight_never_dispatches_microphone_commands(self):
        class Emulator:
            def identity(self):return {"emulator":True,"manufacturer":"Google"}
            def command(self,*args):raise AssertionError("must not mutate emulator")
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(SystemExit):RUNNER.record(Emulator(),Path(directory)/"run")

    def test_install_refuses_owner_application_and_nondebug_apks(self):
        RUNNER.validate_install_identity("package: name='md.vox.android.qualification' versionCode='3'\napplication-debuggable\n")
        for package,debug in [("md.vox.android",True),("md.vox.android.qualification.evil",True),("md.vox.android.qualification",False)]:
            with self.subTest(package=package,debug=debug),self.assertRaisesRegex(ValueError,"Refusing"):
                RUNNER.validate_install_identity("package: name='"+package+"'\n"+("application-debuggable\n" if debug else ""))

    def test_missing_hardware_cannot_be_reported_as_complete(self):
        matrix={"schemaVersion":1,"status":"incomplete","cases":{case:{"status":"unavailable","reason":"Hardware/account unavailable"} for case in VALIDATOR.REQUIRED}}
        self.assertEqual(VALIDATOR.validate_matrix(matrix)["passed"],0)
        bad=copy.deepcopy(matrix);bad["status"]="passed"
        with self.assertRaisesRegex(ValueError,"overclaims"):VALIDATOR.validate_matrix(bad)
        with self.assertRaisesRegex(ValueError,"remains incomplete"):VALIDATOR.validate_matrix(matrix,complete=True)

    def test_model_measurements_require_real_results_and_usable_thermal_samples(self):
        report={"modelID":"vosk-small-en-us-0.15","results":[{"round":i,"passed":True,"elapsedMillis":100} for i in range(3)]}
        samples=[{"thermalStatus":0,"lowMemory":False,"pssKiB":100000} for _ in range(3)]
        VALIDATOR.validate_model(report,samples,"speech")
        for sample in [{"thermalStatus":-1},{"thermalStatus":3},{"lowMemory":True},{"pssKiB":3*1024*1024}]:
            bad=copy.deepcopy(samples);bad[0].update(sample)
            with self.assertRaises(ValueError):VALIDATOR.validate_model(report,bad,"speech")
        report["results"][0]["passed"]=False
        with self.assertRaisesRegex(ValueError,"quality"):VALIDATOR.validate_model(report,samples,"speech")

if __name__=="__main__":unittest.main()
