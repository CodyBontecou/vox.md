"""Exercise the actual Apple CI selection step without requiring Xcode."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
OLD = "11111111-1111-4111-8111-111111111111"
CURRENT = "22222222-2222-4222-8222-222222222222"
OTHER = "33333333-3333-4333-8333-333333333333"


def runtime(version, available=True, platform="iOS"):
    return {
        "identifier": f"com.apple.CoreSimulator.SimRuntime.{platform}-{version.replace('.', '-')}",
        "name": f"{platform} {version}",
        "version": version,
        "isAvailable": available,
    }


def device(udid, name="iPhone 17 Pro", available=True):
    return {"udid": udid, "name": name, "isAvailable": available}


def selection_step():
    workflow = (ROOT / ".github/workflows/apple-ci.yml").read_text()
    match = re.search(
        r"(?ms)^      - name: Select iOS simulator\n.*?^        run: \|\n"
        r"(?P<script>.*?)(?=^      - name:)",
        workflow,
    )
    if not match:
        raise AssertionError("Missing Apple CI iOS simulator selection step")
    return textwrap.dedent(match.group("script"))


class CIiOSSimulatorTests(unittest.TestCase):
    def select(self, entries, sdk="26.5", sdk_failure=False):
        payload = {"runtimes": [], "devices": {}}
        for os_runtime, devices in entries:
            payload["runtimes"].append(os_runtime)
            payload["devices"][os_runtime["identifier"]] = devices
        with tempfile.TemporaryDirectory() as work:
            work = Path(work)
            fixture = work / "simulators.json"
            fixture.write_text(json.dumps(payload))
            # Run the workflow step in a disposable cwd so its diagnostic
            # receipt cannot overwrite real build evidence in the checkout.
            (work / "scripts").symlink_to(ROOT / "scripts", target_is_directory=True)
            output = work / "github-output"
            xcrun = work / "xcrun"
            xcrun.write_text(f"#!{sys.executable}\n" + textwrap.dedent("""\
                import json, os, sys
                from pathlib import Path
                args = sys.argv[1:]
                payload = json.loads(Path(os.environ["SIMULATOR_FIXTURE"]).read_text())
                if args == ["--sdk", "iphonesimulator", "--show-sdk-version"]:
                    if os.environ["SDK_FAILURE"] == "1":
                        sys.exit(1)
                    print(os.environ["SDK_VERSION"])
                elif args == ["simctl", "list", "runtimes", "--json"]:
                    print(json.dumps({"runtimes": payload["runtimes"]}))
                elif args == ["simctl", "list", "devices", "available", "--json"]:
                    print(json.dumps({"devices": payload["devices"]}))
                elif args == ["simctl", "list", "devices", "available", "iOS"]:
                    for runtime in payload["runtimes"]:
                        if not runtime["isAvailable"] or not runtime["name"].startswith("iOS "):
                            continue
                        print(f'-- {runtime["name"]} --')
                        for device in payload["devices"][runtime["identifier"]]:
                            if device["isAvailable"]:
                                print(f'    {device["name"]} ({device["udid"]}) (Shutdown)')
                else:
                    print(f"Unexpected xcrun arguments: {args}", file=sys.stderr)
                    sys.exit(2)
                """))
            xcrun.chmod(0o755)
            result = subprocess.run(
                ["bash", "-e", "-o", "pipefail", "-c", selection_step()],
                cwd=work,
                env={
                    **os.environ,
                    "PATH": f"{work}{os.pathsep}{os.environ['PATH']}",
                    "GITHUB_OUTPUT": str(output),
                    "SIMULATOR_FIXTURE": str(fixture),
                    "SDK_VERSION": sdk,
                    "SDK_FAILURE": "1" if sdk_failure else "0",
                },
                capture_output=True,
                text=True,
                timeout=10,
            )
            metadata = work / "build/logs/ios-simulator.json"
            receipt = json.loads(metadata.read_text()) if metadata.exists() else {}
            return result, output.read_text() if output.exists() else "", receipt

    def assert_selected(self, entries, expected=CURRENT, sdk="26.5"):
        result, output, receipt = self.select(entries, sdk=sdk)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(output, f"destination=platform=iOS Simulator,id={expected}\n")
        self.assertEqual(receipt["selected"]["sdk_version"], sdk)
        self.assertEqual(receipt["selected"]["device"]["udid"], expected)

    def assert_rejected(self, entries, sdk="26.5", **kwargs):
        result, output, receipt = self.select(entries, sdk=sdk, **kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(output, "", "A failed selector must not publish a destination")
        self.assertIn("::error::", result.stdout + result.stderr)
        self.assertIn("error", receipt)

    def test_older_runtime_listed_first_cannot_override_selected_xcode_sdk(self):
        self.assert_selected([
            (runtime("26.2"), [device(OLD)]),
            (runtime("26.5"), [device(CURRENT)]),
        ])

    def test_newer_beta_runtime_cannot_override_stable_xcode_sdk(self):
        self.assert_selected([
            (runtime("27.0"), [device(OTHER)]),
            (runtime("26.5"), [device(CURRENT)]),
        ])

    def test_other_platform_with_same_version_is_not_an_ios_destination(self):
        self.assert_selected([
            (runtime("26.5", platform="watchOS"), [device(OTHER)]),
            (runtime("26.5"), [device(CURRENT)]),
        ])

    def test_unavailable_devices_are_ignored(self):
        self.assert_selected([(runtime("26.5"), [
            device(OTHER, available=False), device(CURRENT),
        ])])

    def test_iphone_is_selected_instead_of_ipad(self):
        self.assert_selected([(runtime("26.5"), [
            device(OTHER, name="iPad Pro 13-inch"), device(CURRENT),
        ])])

    def test_preferred_iphone_is_independent_of_device_listing_order(self):
        self.assert_selected([(runtime("26.5"), [
            device(OTHER, name="iPhone 17"), device(CURRENT),
        ])])

    def test_new_iphone_model_is_a_valid_fallback(self):
        self.assert_selected([(runtime("26.5"), [device(CURRENT, name="iPhone 18")])])

    def test_other_patch_runtime_cannot_override_exact_sdk_version(self):
        # #36's shared policy requires the exact SDK/runtime version.
        self.assert_selected([
            (runtime("26.5"), [device(OLD)]),
            (runtime("26.5.1"), [device(CURRENT)]),
        ], sdk="26.5.1")
        self.assert_rejected([(runtime("26.5"), [device(OLD)])], sdk="26.5.1")

    def test_missing_sdk_matched_runtime_fails_without_falling_back_to_26_2(self):
        self.assert_rejected([(runtime("26.2"), [device(OLD)])])

    def test_unavailable_sdk_matched_runtime_fails(self):
        self.assert_rejected([
            (runtime("26.2"), [device(OLD)]),
            (runtime("26.5", available=False), [device(CURRENT)]),
        ])

    def test_only_ipads_on_sdk_matched_runtime_fails(self):
        self.assert_rejected([(runtime("26.5"), [device(CURRENT, name="iPad mini")])])

    def test_broken_sdk_lookup_fails_without_selecting_any_runtime(self):
        self.assert_rejected([(runtime("26.5"), [device(CURRENT)])], sdk_failure=True)

    def test_workflow_pins_toolchain_with_fixed_concurrency_runtime(self):
        workflow = (ROOT / ".github/workflows/apple-ci.yml").read_text()
        ios_job = workflow.split("  ios-tests:\n", 1)[1].split("  macos-build:\n", 1)[0]
        self.assertIn("xcode-version: '26.6'", ios_job)
        self.assert_rejected([(runtime("26.2"), [device(OLD)])])

    def test_malformed_sdk_version_fails_early(self):
        self.assert_rejected([(runtime("26.5"), [device(CURRENT)])], sdk="not-a-version")

    def test_selected_runtime_and_sdk_are_attested_in_retained_receipt(self):
        result, _, receipt = self.select([(runtime("26.5"), [device(CURRENT)])])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Using SDK-matched simulator", result.stdout + result.stderr)
        self.assertEqual(receipt["selected"]["runtime"]["version"], "26.5")
        self.assertEqual(receipt["sdk_version"], "26.5")
        workflow = (ROOT / ".github/workflows/apple-ci.yml").read_text()
        self.assertIn("build/logs/ios-simulator.json", workflow)
        self.assertIn("build/logs/ios-test-summary.json", workflow)
        self.assertIn("Collect App Intents registration metadata", workflow)
        self.assertIn("build/logs/app-intents", workflow)


if __name__ == "__main__":
    unittest.main()
