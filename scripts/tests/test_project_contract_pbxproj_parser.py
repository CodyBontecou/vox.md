"""The project contract parses build settings independent of Xcode quoting style."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/test-project-contracts.sh"


def load_parser() -> dict:
    source = SCRIPT.read_text()
    start = source.index("_PBX_TOKEN = re.compile(")
    end = source.index("\ntry:\n    project_objects = parse_pbxproj(project)")
    namespace: dict = {"re": re}
    exec(compile(source[start:end], str(SCRIPT), "exec"), namespace)
    return namespace


UNQUOTED = """// !$*UTF8*$!
{
	objects = {
		AAA /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = "Voxboard Widget/VoxboardWidget.entitlements";
				IPHONEOS_DEPLOYMENT_TARGET = 17.6;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = "bontecou.Voxboard.Voxboard-Widget";
			};
			name = Debug;
		};
	};
	rootObject = AAA /* Project object */;
}
"""

QUOTED = """// !$*UTF8*$!
{
	objects = {
		AAA /* Debug */ = {
	buildSettings = {
		"ASSETCATALOG_COMPILER_APPICON_NAME" = AppIcon;
		"CODE_SIGN_ENTITLEMENTS" = "Voxboard Widget/VoxboardWidget.entitlements";
		"IPHONEOS_DEPLOYMENT_TARGET" = "17.6";
		"LD_RUNPATH_SEARCH_PATHS" = (
			"$(inherited)",
			"@executable_path/Frameworks",
		);
		"PRODUCT_BUNDLE_IDENTIFIER" = "bontecou.Voxboard.Voxboard-Widget";
	};
	isa = XCBuildConfiguration;
	name = Debug;
};
	};
	rootObject = AAA /* Project object */;
}
"""


class PbxprojParserTests(unittest.TestCase):
    def setUp(self):
        self.parser = load_parser()

    def test_quoted_keys_and_reordered_fields_parse_identically(self):
        parse = self.parser["parse_pbxproj"]
        self.assertEqual(parse(UNQUOTED), parse(QUOTED))
        settings = parse(QUOTED)["objects"]["AAA"]["buildSettings"]
        self.assertEqual(settings["IPHONEOS_DEPLOYMENT_TARGET"], "17.6")
        self.assertEqual(settings["LD_RUNPATH_SEARCH_PATHS"], ["$(inherited)", "@executable_path/Frameworks"])

    def test_canonical_settings_text_matches_xcode_unquoted_style(self):
        settings = self.parser["parse_pbxproj"](QUOTED)["objects"]["AAA"]["buildSettings"]
        text = self.parser["pbx_settings_text"](settings)
        self.assertIn("\nASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n", text)
        self.assertIn("\nIPHONEOS_DEPLOYMENT_TARGET = 17.6;\n", text)
        self.assertIn('\nCODE_SIGN_ENTITLEMENTS = "Voxboard Widget/VoxboardWidget.entitlements";\n', text)
        self.assertIn('\nPRODUCT_BUNDLE_IDENTIFIER = "bontecou.Voxboard.Voxboard-Widget";\n', text)

    def test_malformed_project_is_rejected(self):
        with self.assertRaises((ValueError, IndexError)):
            self.parser["parse_pbxproj"]("{ objects = { AAA = { isa = XCBuildConfiguration } }; }")

    def test_checked_in_project_parses(self):
        project = (ROOT / "Voxboard.xcodeproj/project.pbxproj").read_text()
        objects = self.parser["parse_pbxproj"](project)["objects"]
        configurations = [item for item in objects.values() if item.get("isa") == "XCBuildConfiguration"]
        self.assertGreaterEqual(len(configurations), 2)


if __name__ == "__main__":
    unittest.main()
