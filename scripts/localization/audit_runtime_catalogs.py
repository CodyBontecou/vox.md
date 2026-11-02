#!/usr/bin/env python3
"""Audit shipped Vox.md String Catalog coverage and token preservation."""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path


RUNTIME_LOCALES = (
    "ar", "bn", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko",
    "nl", "pl", "pt-BR", "ru", "ta", "th", "tr", "uk", "ur", "vi",
    "zh-Hans", "zh-Hant",
)

CATALOGS = (
    "Voxboard/Localizable.xcstrings",
    "Voxboard Keyboard/Localizable.xcstrings",
    "Voxboard/InfoPlist.xcstrings",
    "Voxboard Keyboard/InfoPlist.xcstrings",
    "Voxboard Widget/InfoPlist.xcstrings",
    "Voxboard Watch/InfoPlist.xcstrings",
    "Voxboard Watch Widget/InfoPlist.xcstrings",
    "Voxboard Mac/InfoPlist.xcstrings",
    "Voxboard Share Extension/InfoPlist.xcstrings",
)

PROTECTED_TERMS = (
    "Vox.md", "whisper.cpp", "Whisper", "Parakeet", "Apple Speech",
    "Apple Intelligence", "Foundation Models", "FluidAudio", "CoreML",
    "Obsidian", "Markdown", "App Store", "Apple Watch", "iPhone", "iPad",
    "macOS", "watchOS", "iOS", "M4A", "WAV", "TXT", "JSON", "YAML",
    "SF Symbols", "Cmd-Tab",
)
FORMAT_PATTERN = r"%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.\d+|\.\*)?(?:hh|h|ll|l|L|z|j|t|q)?[@diuoxXfFeEgGaAcCsSpn]"
PROTECTED_PATTERN = re.compile(
    "|".join(
        (
            r"https?://(?=[\s.,;:!?)]|$)",
            r"https?://[^\s<>]+",
            r"!?\[\[[^\]\n]+\]\]",
            r"`[^`\n]+`",
            r"\{[^{}\n]+\}",
            FORMAT_PATTERN,
            r"(?<![\w.])\.(?:md|m4a|wav|txt|json|ya?ml|voxsketch)\b",
            r"(?:⌃|⌥|⌘|⇧)+[^\s,.;:]+|\bF(?:[1-9]|1[0-6])\b",
            r"APPLE INTELLIGENCE",
            r"VOX\.MD",
            r"IOS",
            r"MACOS",
            *(re.escape(term) for term in sorted(PROTECTED_TERMS, key=len, reverse=True)),
        )
    )
)
# CLDR cardinal plural categories that String Catalog plural variations must
# provide for each shipped locale. Every category is required, and no other
# category may appear, so a translation cannot silently fall back to "other"
# (for example Russian "few"/"many" or Arabic "zero"/"two").
PLURAL_CATEGORIES = {
    "ar": ("zero", "one", "two", "few", "many", "other"),
    "bn": ("one", "other"),
    "de": ("one", "other"),
    "en": ("one", "other"),
    "es": ("one", "many", "other"),
    "fr": ("one", "many", "other"),
    "hi": ("one", "other"),
    "id": ("other",),
    "it": ("one", "many", "other"),
    "ja": ("other",),
    "ko": ("other",),
    "nl": ("one", "other"),
    "pl": ("one", "few", "many", "other"),
    "pt-BR": ("one", "many", "other"),
    "ru": ("one", "few", "many", "other"),
    "ta": ("one", "other"),
    "th": ("other",),
    "tr": ("one", "other"),
    "uk": ("one", "few", "many", "other"),
    "ur": ("one", "other"),
    "vi": ("other",),
    "zh-Hans": ("other",),
    "zh-Hant": ("other",),
}
INTEGER_FORMAT_PATTERN = re.compile(r"%(?:\d+\$)?[-+#0 ']*\d*(?:hh|h|ll|l|q|z|j|t)?[diuoxX]")
CANONICAL_CASE_INSENSITIVE = {
    term.casefold(): term for term in PROTECTED_TERMS
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    parser.add_argument("--output", type=Path, help="Write the JSON report to this path")
    parser.add_argument("--root", type=Path, help="Repository root to audit (defaults to this checkout)")
    return parser.parse_args()


def source_value(key: str, entry: dict) -> str:
    english = entry.get("localizations", {}).get("en", {})
    plural = english.get("variations", {}).get("plural", {})
    if plural:
        return plural.get("other", {}).get("stringUnit", {}).get("value", key)
    return english.get("stringUnit", {}).get("value", key)


def localized_units(localization: dict) -> tuple[list[tuple[str | None, dict]], list[dict]]:
    """Return (variant, stringUnit) pairs for a locale plus structural problems.

    Plain entries yield one unit with variant None. Plural entries yield one
    unit per CLDR category and are checked against PLURAL_CATEGORIES.
    """
    problems: list[dict] = []
    unit = localization.get("stringUnit")
    variations = localization.get("variations")
    if variations is None:
        return ([(None, unit)] if unit else []), problems
    if unit is not None:
        problems.append({"kind": "mixed-string-unit-and-variations"})
    unsupported = sorted(set(variations) - {"plural"})
    if unsupported:
        problems.append({"kind": "unsupported-variation", "variations": unsupported})
    plural = variations.get("plural")
    if not isinstance(plural, dict) or not plural:
        problems.append({"kind": "missing"})
        return [], problems
    return [(category, plural[category].get("stringUnit")) for category in plural], problems


def protected_tokens(value: str) -> Counter[str]:
    tokens: list[str] = []
    for match in PROTECTED_PATTERN.finditer(value):
        token = match.group(0)
        tokens.append(CANONICAL_CASE_INSENSITIVE.get(token.casefold(), token))
    return Counter(tokens)


def natural_text(value: str) -> str:
    return PROTECTED_PATTERN.sub("", value).strip()


def forbidden_controls(value: str) -> list[str]:
    allowed = {"\n", "\t"}
    return sorted(
        {
            f"U+{ord(character):04X}"
            for character in value
            if unicodedata.category(character) == "Cc" and character not in allowed
        }
    )


def main() -> int:
    args = parse_args()
    root = (args.root or Path(__file__).resolve().parents[2]).resolve()
    errors: list[dict] = []
    identical: dict[str, list[dict]] = defaultdict(list)
    duplicates: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    coverage: dict[str, dict[str, int]] = {}

    for relative_path in CATALOGS:
        path = root / relative_path
        catalog = json.loads(path.read_text(encoding="utf-8"))
        entries = [
            (key, entry)
            for key, entry in catalog.get("strings", {}).items()
            if key and entry.get("shouldTranslate") is not False
        ]
        coverage[relative_path] = {"translatable": len(entries)}

        for locale in RUNTIME_LOCALES:
            completed = 0
            for key, entry in entries:
                source = source_value(key, entry)
                localization = entry.get("localizations", {}).get(locale, {})
                units, problems = localized_units(localization)
                for problem in problems:
                    errors.append({**problem, "catalog": relative_path, "locale": locale, "key": key})
                if not units:
                    if not problems:
                        errors.append({"kind": "missing", "catalog": relative_path, "locale": locale, "key": key})
                    continue
                is_plural = units[0][0] is not None
                if is_plural:
                    expected_categories = PLURAL_CATEGORIES[locale]
                    found_categories = [category for category, _ in units]
                    missing_categories = [c for c in expected_categories if c not in found_categories]
                    unexpected_categories = sorted(set(found_categories) - set(expected_categories))
                    if missing_categories:
                        errors.append({"kind": "plural-category-missing", "catalog": relative_path, "locale": locale, "key": key, "categories": missing_categories})
                    if unexpected_categories:
                        errors.append({"kind": "plural-category-unexpected", "catalog": relative_path, "locale": locale, "key": key, "categories": unexpected_categories})
                    if not INTEGER_FORMAT_PATTERN.search(source):
                        errors.append({"kind": "plural-without-integer-argument", "catalog": relative_path, "locale": locale, "key": key})
                    if missing_categories or unexpected_categories:
                        continue
                locale_complete = True
                representative = None
                for category, unit in units:
                    location = {"catalog": relative_path, "locale": locale, "key": key}
                    if category is not None:
                        location["plural"] = category
                    if not unit:
                        errors.append({"kind": "missing", **location})
                        locale_complete = False
                        continue
                    state = unit.get("state")
                    value = unit.get("value")
                    if state != "translated":
                        errors.append({"kind": "state", **location, "state": state})
                    if not isinstance(value, str) or not value.strip():
                        errors.append({"kind": "empty", **location})
                        locale_complete = False
                        continue
                    if category in (None, "other"):
                        representative = value
                    if protected_tokens(source) != protected_tokens(value):
                        errors.append(
                            {
                                "kind": "protected-token-mismatch",
                                **location,
                                "source_tokens": dict(protected_tokens(source)),
                                "value_tokens": dict(protected_tokens(value)),
                            }
                        )
                    controls = forbidden_controls(value)
                    if controls:
                        errors.append({"kind": "control-character", **location, "controls": controls})
                if not locale_complete or representative is None:
                    continue
                completed += 1
                value = representative
                if locale != "en" and value == source and re.search(r"[A-Za-z]{3}", natural_text(source)):
                    identical[locale].append({"catalog": relative_path, "key": key})
                if locale != "en" and len(natural_text(source)) >= 4:
                    duplicates[locale][value].append(source)
            coverage[relative_path][locale] = completed

    repeated = {
        locale: [
            {"value": value, "source_count": len(set(sources)), "sources": sorted(set(sources))[:8]}
            for value, sources in values.items()
            if len(set(sources)) >= 5
        ]
        for locale, values in duplicates.items()
    }
    repeated = {locale: items for locale, items in repeated.items() if items}
    result = {
        "catalogs": coverage,
        "errors": errors,
        "source_identical_review": dict(sorted(identical.items())),
        "repeated_translation_review": repeated,
    }

    rendered_json = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.output:
        output = args.output if args.output.is_absolute() else root / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered_json, encoding="utf-8")
    if args.json:
        print(rendered_json, end="")
    else:
        for catalog, counts in coverage.items():
            locale_counts = [counts[locale] for locale in RUNTIME_LOCALES]
            print(f"{catalog}: {counts['translatable']} keys; locale coverage {min(locale_counts)}-{max(locale_counts)}")
        print(f"Errors: {len(errors)}")
        print(f"Source-identical entries requiring review: {sum(map(len, identical.values()))}")
        print(f"Repeated-output groups requiring review: {sum(map(len, repeated.values()))}")

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
