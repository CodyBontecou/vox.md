import argparse
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "capture_launch", Path(__file__).resolve().parents[1] / "test-ios-capture-launch.py")
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)

EXE = "file:///private/var/containers/Bundle/Application/test/Voxboard.app/Voxboard"


class Clock:
    now = 0.0

    def time(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class FakeDevice:
    def __init__(self, crash_at=None, stale_pid=False):
        self.pid = 100
        self.samples = 0
        self.crash_at = crash_at
        self.stale_pid = stale_pid
        self.calls = []

    def call(self, *args):
        self.calls.append(args)
        if args[0] == "process":
            if not self.stale_pid:
                self.pid += 1
            return {"process": {"processIdentifier": self.pid, "executable": EXE}}
        self.samples += 1
        processes = [] if self.samples == self.crash_at else [
            {"processIdentifier": self.pid, "executable": EXE}]
        return {"runningProcesses": processes}


class CaptureLaunchTests(unittest.TestCase):
    def run_smoke(self, device):
        clock = Clock()
        return smoke.cold_launches(device, "bontecou.Voxboard", "Voxboard", 3, 5,
                                   clock=clock.time, sleep=clock.sleep)

    def test_repeated_cold_launches_wait_full_window(self):
        device = FakeDevice()
        receipts = self.run_smoke(device)
        self.assertEqual([r["pid"] for r in receipts], [101, 102, 103])
        self.assertTrue(all(r["survived_seconds"] >= 5 and r["samples"] >= 6 for r in receipts))
        self.assertTrue(all("--terminate-existing" in c for c in device.calls if c[0] == "process"))
        self.assertFalse(any("--console" in c or "--start-stopped" in c for c in device.calls))

    def test_successful_launch_then_immediate_crash_fails(self):
        with self.assertRaises(smoke.SmokeFailure):
            self.run_smoke(FakeDevice(crash_at=1))

    def test_delayed_crash_fails_before_next_launch(self):
        device = FakeDevice(crash_at=4)
        with self.assertRaises(smoke.SmokeFailure):
            self.run_smoke(device)
        self.assertEqual(device.pid, 101)

    def test_warm_process_is_not_a_cold_launch(self):
        with self.assertRaises(smoke.SmokeFailure):
            self.run_smoke(FakeDevice(stale_pid=True))

    def test_other_pid_or_executable_cannot_mask_crash(self):
        for process in [{"processIdentifier": 999, "executable": EXE},
                        {"processIdentifier": 101, "executable": EXE + "Other"}]:
            with self.assertRaises(smoke.SmokeFailure):
                smoke.verify_process({"runningProcesses": [process]}, (101, EXE))

    def test_malformed_process_and_launch_responses_fail_closed(self):
        for response in [{}, {"runningProcesses": None}, {"runningProcesses": []}]:
            with self.assertRaises(smoke.SmokeFailure):
                smoke.verify_process(response, (101, EXE))
        for response in [{}, {"process": {}}, {"process": {"processIdentifier": "101", "executable": EXE}}]:
            with self.assertRaises(smoke.SmokeFailure):
                smoke.launch_identity(response, "Voxboard")

    def test_cli_failure_timeout_and_missing_json_cannot_pass(self):
        with tempfile.TemporaryDirectory() as work:
            device = smoke.Device("explicit-phone", Path(work))
            for result in [subprocess.CompletedProcess([], 1), subprocess.CompletedProcess([], 0)]:
                with patch.object(smoke.subprocess, "run", return_value=result):
                    with self.assertRaises(smoke.SmokeFailure):
                        device.call("info", "processes")
            with patch.object(smoke.subprocess, "run", side_effect=subprocess.TimeoutExpired("device", 40)):
                with self.assertRaises(smoke.SmokeFailure):
                    device.call("info", "processes")

    def test_non_success_json_is_rejected_even_with_zero_exit_code(self):
        def command(args, **kwargs):
            Path(args[args.index("--json-output") + 1]).write_text(
                json.dumps({"info": {"outcome": "failure"}, "result": {}}))
            return subprocess.CompletedProcess(args, 0)
        with tempfile.TemporaryDirectory() as work:
            with patch.object(smoke.subprocess, "run", side_effect=command):
                with self.assertRaises(smoke.SmokeFailure):
                    smoke.Device("explicit-phone", Path(work)).call("info", "processes")

    def test_device_options_precede_bundle_argument(self):
        def command(args, **kwargs):
            bundle_index = args.index("bontecou.Voxboard")
            for option in ["--device", "--json-output", "--timeout", "--terminate-existing"]:
                self.assertLess(args.index(option), bundle_index)
            Path(args[args.index("--json-output") + 1]).write_text(
                json.dumps({"info": {"outcome": "success"}, "result": {}}))
            return subprocess.CompletedProcess(args, 0)
        with tempfile.TemporaryDirectory() as work:
            with patch.object(smoke.subprocess, "run", side_effect=command):
                smoke.Device("explicit-phone", Path(work)).call(
                    "process", "launch", "--terminate-existing", "bontecou.Voxboard")

    def test_tiny_or_nonfinite_watch_window_is_rejected(self):
        for value in ["0", "1", "nan", "inf", "-1"]:
            with self.assertRaises(argparse.ArgumentTypeError):
                smoke.positive_seconds(value)


if __name__ == "__main__":
    unittest.main()
