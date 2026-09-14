import copy
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "android_runtime_localizations",
    ROOT / "apps/android/scripts/generate-runtime-localizations.py",
)
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class AndroidLocalizationAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads(GENERATOR.CATALOG.read_text(encoding="utf-8"))["strings"]
        cls.audit = GENERATOR.localization_audit(cls.catalog)

    def test_aliases_are_reviewed_case_only_catalog_variants(self):
        self.assertEqual(
            GENERATOR.SOURCE_ALIASES,
            {
                "Advanced YAML template": "Advanced YAML Template",
                "Append filename": "Append Filename",
                "Attachments folder": "Attachments Folder",
                "Custom instruction": "Custom Instruction",
                "Edit transcript": "Edit Transcript",
                "Search History": "Search history",
            },
        )
        for source, catalog_source in GENERATOR.SOURCE_ALIASES.items():
            self.assertEqual(source.casefold(), catalog_source.casefold())
            self.assertNotIn(source, self.catalog)
            self.assertIn(catalog_source, self.catalog)
            self.assertTrue(all(
                GENERATOR.translated_value(self.catalog[catalog_source], locale) is not None
                for locale in GENERATOR.LOCALES
            ))

    def test_audit_stays_explicitly_unapproved(self):
        self.assertEqual(self.audit["reviewStatus"], "requires-human-translation")
        self.assertIn("not translation approval", self.audit["limitations"][0])
        self.assertIn("Dynamic-source call sites are inventoried", self.audit["limitations"][1])
        self.assertIn("fall back to English", self.audit["limitations"][2])
        incomplete_catalog = copy.deepcopy(self.catalog)
        del incomplete_catalog["Selected"]["localizations"]["de"]
        incomplete_audit = GENERATOR.localization_audit(incomplete_catalog)
        self.assertEqual(incomplete_audit["incompleteCatalogSourceCount"], 1)
        self.assertEqual(
            incomplete_audit["incompleteCatalogSources"],
            [{
                "source": "Selected",
                "missingLocales": ["de"],
                "locations": GENERATOR.literal_runtime_sources()["Selected"],
            }],
        )

    def test_audit_inventory_requires_deliberate_review_when_copy_changes(self):
        self.assertEqual(self.audit["runtimeSourceLiteralCount"], 2_403)
        self.assertEqual(self.audit["literalRuntimeSourceCount"], 707)
        self.assertEqual(self.audit["catalogBackedSourceCount"], 216)
        self.assertEqual(self.audit["aliasBackedSourceCount"], 6)
        self.assertEqual(self.audit["incompleteCatalogSourceCount"], 0)
        self.assertEqual(self.audit["missingCatalogSourceCount"], 485)
        self.assertEqual(self.audit["fallbackSourceCount"], 485)
        self.assertEqual(self.audit["dynamicRuntimeCallSiteCount"], 0)
        self.assertEqual(self.audit["dynamicRuntimeExpressionCount"], 0)
        self.assertEqual(self.audit["integerFormatSourceCount"], 16)
        self.assertEqual(self.audit["pluralReviewStatus"], "requires-human-review")
        self.assertNotIn(
            "source: String",
            [item["expression"] for item in self.audit["dynamicRuntimeCalls"]],
        )
        self.assertEqual(
            self.audit["literalRuntimeSourceCount"],
            self.audit["catalogBackedSourceCount"]
            + self.audit["aliasBackedSourceCount"]
            + self.audit["incompleteCatalogSourceCount"]
            + self.audit["missingCatalogSourceCount"],
        )

    def test_conditional_predicate_literals_are_not_reported_as_copy(self):
        expression = (
            'if (failureCode == "notDisplayCopy") "Visible failure" '
            'else if (phase == "notCopyEither") "Visible fallback" else "Visible result"'
        )
        ranges = GENERATOR.conditional_predicate_ranges(expression)
        values = [
            GENERATOR.decode_literal('"' + match.group(1) + '"')
            for match in GENERATOR.STRING_LITERAL.finditer(expression)
            if not any(start <= match.start() < end for start, end in ranges)
        ]
        self.assertEqual(values, ["Visible failure", "Visible fallback", "Visible result"])

    def test_first_argument_parser_preserves_nested_commas(self):
        region = 'if (enabled(a, b)) "A" else "B", count, another(argument, "not source")'
        self.assertEqual(
            GENERATOR.source_expression(region),
            'if (enabled(a, b)) "A" else "B"',
        )

    def test_generated_audit_is_byte_for_byte_current(self):
        expected = json.dumps(self.audit, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        self.assertEqual(GENERATOR.AUDIT.read_text(encoding="utf-8"), expected)

    def test_runtime_catalog_format_arguments_match_source_contracts(self):
        self.assertEqual(self.audit["formatArgumentContractStatus"], "validated")
        for source in GENERATOR.source_literals():
            catalog_source = GENERATOR.resolved_catalog_source(self.catalog, source)
            if catalog_source is None:
                continue
            for locale in GENERATOR.LOCALES:
                value = GENERATOR.translated_value(self.catalog[catalog_source], locale)
                if value is not None:
                    self.assertEqual(
                        GENERATOR.format_signature(value),
                        GENERATOR.format_signature(source),
                        f"{locale}: {source}",
                    )
        with self.assertRaisesRegex(SystemExit, "format arguments differ"):
            GENERATOR.validate_format_compatibility("%lld captures", "%@ captures", "de")

    def test_kotlin_escaped_positional_placeholder_is_not_interpolation(self):
        decoded = GENERATOR.decode_literal(r'"%1\$@ · %2\$lld"')
        self.assertEqual(decoded, "%1$@ · %2$lld")
        self.assertIsNone(GENERATOR.KOTLIN_INTERPOLATION.search(decoded))
        self.assertIsNotNone(GENERATOR.KOTLIN_INTERPOLATION.search("$label"))

    def test_runtime_localization_plumbing_is_not_reported_as_dynamic_ui_copy(self):
        self.assertEqual(
            GENERATOR.DYNAMIC_AUDIT_EXCLUDED_PATHS,
            {"apps/android/app/src/main/kotlin/md/vox/android/RuntimeLocalization.kt"},
        )
        self.assertNotIn(
            "source",
            [item["expression"] for item in self.audit["dynamicRuntimeCalls"]],
        )


if __name__ == "__main__":
    unittest.main()
