import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "issue22_simulator", ROOT / "scripts/select-issue22-ios-test-simulator.py"
)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)

OLD = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
CURRENT = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
BETA = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"


def runtime(version, available=True):
    return {
        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-" + version.replace(".", "-"),
        "version": version,
        "buildversion": "synthetic-build-" + version,
        "isAvailable": available,
    }


def device(udid, name="iPhone 17 Pro", available=True):
    return {"udid": udid, "name": name, "isAvailable": available}


class Issue22SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.runtimes = [runtime("26.2"), runtime("26.5"), runtime("27.0")]
        self.devices = {
            self.runtimes[0]["identifier"]: [device(OLD)],
            self.runtimes[1]["identifier"]: [device(CURRENT)],
            self.runtimes[2]["identifier"]: [device(BETA)],
        }

    def select(self, sdk="26.5"):
        return selector.select_simulator(sdk, self.runtimes, self.devices)

    def test_older_first_runtime_and_newer_beta_cannot_win_over_selected_sdk(self):
        selected = self.select()
        self.assertEqual(selected["destination"], f"platform=iOS Simulator,id={CURRENT}")
        self.assertEqual(selected["runtime"]["version"], "26.5")
        self.assertEqual(selected["runtime"]["buildversion"], "synthetic-build-26.5")

    def test_missing_sdk_runtime_fails_instead_of_quietly_testing_older_os(self):
        self.runtimes.pop(1)
        with self.assertRaisesRegex(ValueError, "refusing an older or beta runtime fallback"):
            self.select()

    def test_unavailable_runtime_or_device_cannot_supply_a_destination(self):
        self.runtimes[1]["isAvailable"] = False
        with self.assertRaises(ValueError):
            self.select()
        self.runtimes[1]["isAvailable"] = True
        self.devices[self.runtimes[1]["identifier"]][0]["isAvailable"] = False
        with self.assertRaises(ValueError):
            self.select()

    def test_existing_device_preference_is_applied_only_within_matched_runtime(self):
        self.devices[self.runtimes[1]["identifier"]] = [
            device(OLD, "iPhone 15"), device(CURRENT, "iPhone 17 Pro"),
        ]
        self.assertEqual(self.select()["device"]["udid"], CURRENT)

    def test_other_iphone_is_valid_but_ipad_is_not_a_fallback(self):
        self.devices[self.runtimes[1]["identifier"]] = [device(CURRENT, "iPhone SE (3rd generation)")]
        self.assertEqual(self.select()["device"]["udid"], CURRENT)
        self.devices[self.runtimes[1]["identifier"]] = [device(CURRENT, "iPad Pro")]
        with self.assertRaises(ValueError):
            self.select()

    def test_equivalent_version_spelling_and_invalid_destination(self):
        self.assertEqual(self.select("26.5.0")["device"]["udid"], CURRENT)
        self.devices[self.runtimes[1]["identifier"]] = [device("invalid-udid")]
        with self.assertRaises(ValueError):
            self.select()

    def test_cli_retains_runtime_inventory_and_writes_github_destination(self):
        with tempfile.TemporaryDirectory() as work:
            output = Path(work) / "github-output"
            metadata = Path(work) / "logs/simulator.json"
            with patch.object(selector.sys, "argv", [
                "selector", "--github-output", str(output), "--metadata", str(metadata),
            ]), patch.object(selector.subprocess, "check_output", side_effect=[
                "26.5\n", json.dumps({"runtimes": self.runtimes}), json.dumps({"devices": self.devices}),
            ]):
                self.assertEqual(selector.main(), 0)
            self.assertEqual(output.read_text(), f"destination=platform=iOS Simulator,id={CURRENT}\n")
            receipt = json.loads(metadata.read_text())
            self.assertEqual(receipt["selected"]["runtime"]["version"], "26.5")
            self.assertEqual(len(receipt["available_runtimes"]), 3)

    def test_cli_failure_retains_inventory_without_publishing_destination(self):
        self.runtimes.pop(1)
        with tempfile.TemporaryDirectory() as work:
            output = Path(work) / "github-output"
            metadata = Path(work) / "simulator.json"
            with patch.object(selector.sys, "argv", [
                "selector", "--github-output", str(output), "--metadata", str(metadata),
            ]), patch.object(selector.subprocess, "check_output", side_effect=[
                "26.5\n", json.dumps({"runtimes": self.runtimes}), json.dumps({"devices": self.devices}),
            ]):
                self.assertEqual(selector.main(), 1)
            self.assertFalse(output.exists())
            self.assertIn("No available iPhone simulator", json.loads(metadata.read_text())["error"])

    def test_ios_ci_uses_selector_and_keeps_attempt_specific_diagnostics(self):
        workflow = (ROOT / ".github/workflows/apple-ci.yml").read_text()
        ios_job = workflow.split("  ios-tests:\n", 1)[1].split("  macos-build:\n", 1)[0]
        self.assertIn("python3 scripts/select-issue22-ios-test-simulator.py", ios_job)
        self.assertIn("voxboard-ios-test-diagnostics-${{ github.run_id }}-${{ github.run_attempt }}", ios_job)
        self.assertIn("build/logs/ios-simulator.json", ios_job)
        self.assertIn("build/logs/ios-test-summary.json", ios_job)


def collect_fixture_reports(workflow, with_marker=True):
    """Execute the actual retained-diagnostics shell against synthetic files."""
    ios_job = workflow.split("  ios-tests:\n", 1)[1].split("  macos-build:\n", 1)[0]
    block = ios_job.split("      - name: Collect simulator crash reports\n", 1)[1]
    script = textwrap.dedent(block.split("        run: |\n", 1)[1].split("      - name:", 1)[0])
    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        reports = root / "home/Library/Logs/DiagnosticReports"
        reports.mkdir(parents=True)
        logs = root / "build/logs"
        logs.mkdir(parents=True)
        now = time.time()
        if with_marker:
            marker = logs / "ios-tests-started"
            marker.touch()
            os.utime(marker, (now - 2, now - 2))
        for name, timestamp in [
            ("Voxboard-current.ips", now - 1),
            ("Voxboard-stale.ips", now - 5),
            ("OtherApp-current.ips", now - 1),
        ]:
            report = reports / name
            report.write_text("synthetic crash report " + name)
            os.utime(report, (timestamp, timestamp))
        result = subprocess.run(["bash", "-c", script], cwd=root, env={
            **os.environ, "HOME": str(root / "home"), "RUNNER_TEMP": str(root / "runner"),
            "GITHUB_OUTPUT": str(root / "github-output"),
        }, capture_output=True, text=True)
        retained = {
            path.name: path.read_text() for path in (logs / "crash-reports").glob("*.ips")
        }
        return result, retained, (root / "github-output").read_text()


class Issue22DiagnosticsTests(unittest.TestCase):
    def test_collector_retains_only_this_invocations_host_reports(self):
        workflow = (ROOT / ".github/workflows/apple-ci.yml").read_text()
        result, retained, output = collect_fixture_reports(workflow)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(retained, {
            "Voxboard-current.ips": "synthetic crash report Voxboard-current.ips",
        })
        self.assertEqual(output, "crash-reports-collected=1\n")

    def test_no_test_invocation_cannot_collect_previous_runner_crashes(self):
        workflow = (ROOT / ".github/workflows/apple-ci.yml").read_text()
        result, retained, output = collect_fixture_reports(workflow, with_marker=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(retained, {})
        self.assertEqual(output, "crash-reports-collected=0\n")


if __name__ == "__main__":
    unittest.main()
