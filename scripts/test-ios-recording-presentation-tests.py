#!/usr/bin/env python3
"""Unit checks for the observe-only presentation parser, not native execution."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "presentation", Path(__file__).with_name("test-ios-recording-presentation.py")
)
presentation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(presentation)

OPTIONS = 'AXButton "Action Options"'
SUMMARY = 'AXGroup "Stop,  recording with , Preset"'
SYSTEM = f'AXButton "Open When Run" id="{presentation.PREFIX}OpenWhenRun"'
CUSTOM = f'AXButton "Open App" id="{presentation.PREFIX}openApp"'
FLAT = '\n'.join([OPTIONS, SUMMARY, 'AXButton "Open When Run" value="0"'])


class PresentationTests(unittest.TestCase):
    def test_primary_parameter_ids_accept_one_native_switch(self):
        presentation.check({"description": OPTIONS + '\n' + SYSTEM})

    def test_duplicate_physical_controls_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            presentation.check({"description": '\n'.join([OPTIONS, SYSTEM, CUSTOM])})

    def test_staged_simulator_flat_tree_accepts_one_native_switch(self):
        presentation.check({"source": "ax-service", "description": FLAT})

    def test_duplicate_simulator_controls_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            presentation.check({"source": "ax-service", "description": FLAT + '\nAXButton "Open App"'})

    def test_unstaged_or_multiple_actions_are_rejected(self):
        for description in [OPTIONS, SYSTEM, FLAT + '\n' + SUMMARY, FLAT + '\n' + OPTIONS]:
            with self.subTest(description=description), self.assertRaises(ValueError):
                presentation.check({"source": "ax-service", "description": description})

    def test_missing_or_unknown_tree_is_not_a_pass(self):
        for receipt in [{}, {"description": FLAT, "source": "unknown"}]:
            with self.subTest(receipt=receipt), self.assertRaises(ValueError):
                presentation.check(receipt)


if __name__ == "__main__":
    unittest.main()
