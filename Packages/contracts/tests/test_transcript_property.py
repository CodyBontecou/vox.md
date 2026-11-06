"""The Unicode key rule is semantic, avoiding incompatible Python/ECMA regex alphabets."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("property_contract_validator", ROOT / "Packages/contracts/scripts/validate.py")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)

class TranscriptPropertyContractTests(unittest.TestCase):
    def test_unicode_property_names_are_valid_without_changing_text_bytes(self):
        schema = json.loads((ROOT / "Packages/contracts/capture-preparation-input/v1/schema.json").read_text())
        property_schema = schema["properties"]["preset"]["properties"]["metadataPolicy"]["properties"]["transcriptProperty"]
        value = {"name": "記録_2", "value": 'yes\n---\nadmin: true\n"quoted"'}
        VALIDATOR.schema_validate(value, property_schema)
        VALIDATOR.validate_transcript_property_tree({"metadataPolicy": {"transcriptProperty": value}})
        self.assertEqual(value["value"], 'yes\n---\nadmin: true\n"quoted"')

    def test_yaml_syntax_cannot_be_a_property_name(self):
        for name in ("note: other", "note\nother", "[note]", " "):
            with self.subTest(name=name), self.assertRaises(VALIDATOR.ContractError):
                VALIDATOR.validate_transcript_property_tree({"metadataPolicy": {"transcriptProperty": {"name": name, "value": "safe"}}})

    def test_transcript_value_limit_is_explicit(self):
        schema = json.loads((ROOT / "Packages/contracts/capture-preparation-input/v1/schema.json").read_text())
        property_schema = schema["properties"]["preset"]["properties"]["metadataPolicy"]["properties"]["transcriptProperty"]
        VALIDATOR.schema_validate({"name": "note", "value": "x" * 65536}, property_schema)
        with self.assertRaises(VALIDATOR.ContractError):
            VALIDATOR.schema_validate({"name": "note", "value": "x" * 65537}, property_schema)
