#!/usr/bin/env python3
"""Generate Android phrase tables and CLDR quantities from iOS and Android catalogs."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from xml.sax.saxutils import escape


ROOT = Path(__file__).resolve().parents[3]
CATALOG = ROOT / "Voxboard" / "Localizable.xcstrings"
KOTLIN_ROOT = ROOT / "apps" / "android" / "app" / "src" / "main" / "kotlin"
RUNTIME_SOURCE_ROOTS = tuple(
    ROOT / "apps" / "android" / module / "src" / "main" / "kotlin"
    for module in ("app", "capture-domain", "data", "platform-services")
)
OUTPUT = ROOT / "apps" / "android" / "app" / "src" / "main" / "res" / "raw" / "vox_runtime_localizations.json"
ANDROID_CATALOG = ROOT / "apps/android/localization/android-strings.json"
ANDROID_OVERRIDES = ROOT / "apps/android/localization/android-overrides.json"
PLURAL_SPEC = ROOT / "apps/android/localization/plural-spec.json"
AUDIT = ROOT / "apps" / "android" / "localization-review.json"
DYNAMIC_AUDIT_EXCLUDED_PATHS = {
    "apps/android/app/src/main/kotlin/md/vox/android/RuntimeLocalization.kt",
}
RESOURCES = ROOT / "apps" / "android" / "app" / "src" / "main" / "res"
WEAR_RESOURCES = ROOT / "apps" / "android" / "wear" / "src" / "main" / "res"
LOCALES = (
    "ar", "bn", "de", "es", "fr", "hi", "id", "it", "ja", "ko", "nl", "pl",
    "pt-BR", "ru", "ta", "th", "tr", "uk", "ur", "vi", "zh-Hans", "zh-Hant",
)
ANDROID_QUALIFIERS = {
    "ar": "ar", "bn": "bn", "de": "de", "es": "es", "fr": "fr", "hi": "hi",
    "id": "b+id", "it": "it", "ja": "ja", "ko": "ko", "nl": "nl", "pl": "pl",
    "pt-BR": "pt-rBR", "ru": "ru", "ta": "ta", "th": "th", "tr": "tr", "uk": "uk",
    "ur": "ur", "vi": "vi", "zh-Hans": "b+zh+Hans", "zh-Hant": "b+zh+Hant",
}
PLATFORM_STRINGS = {
    "preset_widget_title": "Capture Presets",
    "preset_widget_description": "Open Vox.md directly to a durable Markdown capture draft.",
    "preset_widget_configure": "Settings",
    "preset_widget_unconfigured": "Choose Preset",
    "preset_widget_disabled": "Disabled",
    "preset_widget_missing": "Unavailable",
    "preset_widget_no_pins": "Choose Capture Preset",
    "preset_widget_storage_unavailable": "Shared Capture storage is unavailable.",
    "shortcut_capture_short": "Capture",
    "shortcut_capture_long": "Capture to Vox.md",
    "shortcut_voice_short": "Record voice note",
    "shortcut_voice_long": "Record with Vox.md",
    "widget_subtitle": "Capture ideas as they arrive.",
    "widget_capture": "Capture",
    "widget_record": "Record",
    "widget_description": "Capture an idea, task, link, file, scan, or recording.",
    "tile_capture_label": "Quick Capture",
    "tile_capture_subtitle": "Capture note",
}
WEAR_PLATFORM_STRINGS = {
    "wear_brand": "Vox.md",
    "wear_record": "Record",
    "wear_recording": "Recording",
    "wear_ready": "Ready",
    "wear_paused": "Paused",
    "wear_needs_attention": "Needs attention",
    "wear_failed": "Watch recording needs attention",
    "wear_saved": "Saved",
    "wear_saved_watch": "Watch recording saved",
    "wear_capture_preset": "Capture Preset",
    "wear_selected": "Selected",
    "wear_done": "Done",
    "wear_sync": "Sync",
    "wear_sync_status": "Sync Status",
    "wear_syncing": "Syncing",
    "wear_queued": "Queued",
    "wear_nothing_to_sync": "No Watch recordings waiting to sync.",
    "wear_recording_detail": "Pause for a break, Stop to save, or Cancel to delete.",
    "wear_paused_detail": "Recording paused. Resume when you're ready, or stop to save it.",
    "wear_failure_detail": "Open Vox.md to review a Watch recording delivery problem.",
    "wear_ready_detail": "Start a local Watch recording and sync it to Vox.md.",
    "wear_queue_preserved": "Watch recordings sync back",
    "wear_synced": "Synced",
    "wear_remote_waiting": "Waiting for iPhone",
    "wear_remote_transcribing": "Transcribing on iPhone",
    "wear_remote_saving": "Saving on iPhone",
    "wear_remote_failed": "Delivery failed",
    "wear_remote_transport_failed": "Needs attention",
    "wear_pause_action": "Pause Watch recording",
    "wear_resume_action": "Resume Watch recording",
    "wear_stop_action": "Stop Watch recording",
    "wear_cancel_action": "Cancel and delete Watch recording",
    "wear_start_action": "Start Watch recording",
    "wear_open_controls": "Show detailed recording controls",
    "wear_is_recording": "Vox.md is recording",
    "wear_one_recording_saved": "1 recording saved on Watch.",
    "wear_recordings_saved_count": "%lld recordings saved on Watch.",
    "wear_quick_capture": "Quick Capture",
    "wear_listening": "Listening",
    "wear_pending": "Queued",
    "wear_delivering": "Syncing",
    "wear_unavailable": "Unavailable",
    "wear_listening_detail": "Preparing microphone…",
    "wear_pending_detail": "Watch recordings stay saved locally and appear in your iPhone queue when your devices reconnect.",
    "wear_syncing_detail": "Sending Watch recording to the iPhone queue.",
    "wear_unavailable_detail": "Recording is safe on Watch. Tap Sync Queue to retry.",
    "wear_microphone_unavailable": "Microphone permission required on Apple Watch.",
    "wear_delivery_complete": "Delivered successfully. You can record another.",
    "wear_phone_receiving": "Your recording remains safe while it moves to iPhone.",
    "wear_review_recordings": "Watch Recordings",
    "wear_saved_recordings": "Recordings",
    "wear_retry_action": "Retry",
    "wear_discard_action": "Discard",
    "wear_confirm_discard_title": "Discard this Watch recording?",
    "wear_confirm_discard_detail": "Stops and permanently deletes this recording without syncing it to your iPhone.",
    "wear_discard_recording": "Discard Recording",
    "wear_keep_recording": "Done",
    "wear_back": "Done",
}
SOURCE_ALIASES = {
    "Advanced YAML template": "Advanced YAML Template",
    "Append filename": "Append Filename",
    "Attachments folder": "Attachments Folder",
    "Custom instruction": "Custom Instruction",
    "Edit transcript": "Edit Transcript",
    "Search History": "Search history",
}
STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
TEXT_LITERAL = re.compile(r'\bText\(\s*(?:(text)\s*=\s*)?("(?:[^"\\]|\\.)*")')
VOX_STRING_CALL = re.compile(r"\b(?:voxString|voxNotice|voxUiText)\(")
LOCALIZATION_CALL = re.compile(r"\b(?:voxString|voxFormat|voxNotice|voxUiText)\s*\(")
APPLE_FORMAT_TOKEN = re.compile(
    r"%(?!%)(?:(\d+)\$)?[-+# 0,(]*\d*(?:\.\d+)?(lld|ld|@|[dfs])"
)
KOTLIN_INTERPOLATION = re.compile(r"(?<!\d)\$(?:\{|[A-Za-z_])")
RAW_TEXT_CONDITIONAL = re.compile(
    r'\bText\(\s*if\s*\([^)]*\)\s*"|\bText\(\s*if\s*\([^)]*\)[^,\n]*\belse\s*"'
)
RAW_ACCESSIBILITY_TEXT = re.compile(
    r'\b(?:contentDescription|stateDescription|paneTitle)\s*=\s*(?:"|if\s*\()'
)


def decode_literal(encoded: str) -> str | None:
    if len(encoded) >= 2 and encoded[0] == encoded[-1] == '"':
        contents = encoded[1:-1]
        normalized: list[str] = []
        index = 0
        while index < len(contents):
            character = contents[index]
            if character == "\\" and index + 1 < len(contents):
                escaped = contents[index + 1]
                if escaped in {"$", "'"}:
                    normalized.append(escaped)
                else:
                    normalized.extend((character, escaped))
                index += 2
                continue
            normalized.append(character)
            index += 1
        encoded = '"' + "".join(normalized) + '"'
    try:
        return json.loads(encoded)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


def source_literals() -> set[str]:
    values: set[str] = set()
    for source_root in RUNTIME_SOURCE_ROOTS:
        for path in source_root.rglob("*.kt"):
            for match in STRING_LITERAL.finditer(path.read_text(encoding="utf-8")):
                value = decode_literal('"' + match.group(1) + '"')
                if value is not None and not KOTLIN_INTERPOLATION.search(value):
                    values.add(value)
    return values


def translated_value(entry: dict, locale: str) -> str | None:
    unit = entry.get("localizations", {}).get(locale, {}).get("stringUnit", {})
    value = unit.get("value")
    if unit.get("state") not in {"translated", "new"} or not isinstance(value, str):
        return None
    return value


def missing_translation_locales(entry: dict) -> list[str]:
    return [locale for locale in LOCALES if translated_value(entry, locale) is None]


def is_plural_variation_entry(entry: object) -> bool:
    """iOS plural entries carry `variations` instead of a stringUnit; Android serves those
    sources from plural-spec.json and its own catalog, never from the iOS phrase table."""
    return isinstance(entry, dict) and any(
        "variations" in localization for localization in entry.get("localizations", {}).values()
    )


def validate_source_aliases(catalog: dict) -> None:
    for source, catalog_source in SOURCE_ALIASES.items():
        if source in catalog:
            raise SystemExit(
                f"localization source alias is obsolete because an exact catalog entry exists: {source}"
            )
        entry = catalog.get(catalog_source)
        if not isinstance(entry, dict):
            raise SystemExit(f"localization source alias target is absent from iOS catalog: {catalog_source}")
        missing = missing_translation_locales(entry)
        if missing:
            raise SystemExit(
                f"localization source alias target lacks reviewed translations for {', '.join(missing)}: "
                f"{catalog_source}"
            )


def resolved_catalog_source(catalog: dict, source: str) -> str | None:
    if isinstance(catalog.get(source), dict):
        return source
    alias = SOURCE_ALIASES.get(source)
    return alias if alias is not None and isinstance(catalog.get(alias), dict) else None


def format_signature(value: str) -> tuple[tuple[int, str], ...]:
    arguments: dict[int, str] = {}
    next_sequential = 1
    for match in APPLE_FORMAT_TOKEN.finditer(value):
        index = int(match.group(1)) if match.group(1) is not None else next_sequential
        if match.group(1) is None:
            next_sequential += 1
        token = match.group(2)
        argument_type = (
            "integer" if token in {"lld", "ld", "d"}
            else "string" if token in {"@", "s"}
            else token
        )
        previous = arguments.get(index)
        if previous is not None and previous != argument_type:
            raise SystemExit(f"format argument {index} has conflicting types in: {value}")
        arguments[index] = argument_type
    return tuple(sorted(arguments.items()))


def validate_format_compatibility(source: str, translation: str, locale: str) -> None:
    expected = format_signature(source)
    actual = format_signature(translation)
    if actual != expected:
        raise SystemExit(
            f"{locale} localization format arguments differ for {source!r}: "
            f"expected {expected}, found {actual}"
        )


def android_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"')
    return escape(escaped)


def validate_android_catalog(data: dict) -> dict:
    if data.get("schemaVersion") != 1 or data.get("reviewStatus") != "requires-human-review":
        raise SystemExit("Android catalog must retain explicit human-review status")
    if data.get("provenance", {}).get("humanApproved") is not False:
        raise SystemExit("Android machine translations must not claim human approval")
    strings = data["strings"]
    for source, translations in strings.items():
        if set(translations) != set(LOCALES):
            raise SystemExit(f"Android translation locale coverage differs: {source}")
        for locale, value in translations.items():
            if not isinstance(value, str) or not value.strip():
                raise SystemExit(f"Empty Android translation: {locale}: {source}")
            validate_format_compatibility(source, value, locale)
            for token in re.findall(r"\{[A-Za-z][A-Za-z0-9_]*\}", source):
                if token not in value: raise SystemExit(f"Android template token lost: {locale}: {token}")
    return strings


def android_catalog() -> dict:
    strings = validate_android_catalog(json.loads(ANDROID_CATALOG.read_text(encoding="utf-8")))
    overrides = validate_android_catalog(json.loads(ANDROID_OVERRIDES.read_text(encoding="utf-8")))
    return strings | overrides


def phrase_translation(catalog: dict, android: dict, source: str, locale: str) -> str | None:
    key = resolved_catalog_source(catalog, source)
    value = translated_value(catalog[key], locale) if key is not None else None
    return value if value is not None else android.get(source, {}).get(locale)


PLURAL_CATEGORIES = {
    "ar": ("zero", "one", "two", "few", "many", "other"),
    "ru": ("one", "few", "many", "other"), "pl": ("one", "few", "many", "other"),
    "uk": ("one", "few", "many", "other"),
    **{locale: ("other",) for locale in ("id", "ja", "ko", "th", "vi", "zh-Hans", "zh-Hant")},
    **{locale: ("one", "many", "other") for locale in ("es", "fr", "it", "pt-BR")},
    **{locale: ("one", "other") for locale in ("bn", "de", "hi", "nl", "ta", "tr", "ur")},
}


def generate_plurals(catalog: dict, android: dict) -> dict:
    spec = json.loads(PLURAL_SPEC.read_text(encoding="utf-8"))
    if spec.get("reviewStatus") != "requires-human-review": raise SystemExit("Plural review must remain explicit")
    result = {}
    for source, item in spec["plurals"].items():
        if dict(format_signature(source)).get(item["countArgument"]) != "integer":
            raise SystemExit(f"Plural count must select an integer argument: {source}")
        forms = {"en": item["english"]}
        for locale in LOCALES:
            overrides = item.get("overrides", {}).get(locale, {})
            if set(overrides) != set(PLURAL_CATEGORIES[locale]):
                raise SystemExit(f"Plural categories differ: {locale}: {source}")
            forms[locale] = overrides
        for locale, quantities in forms.items():
            if set(quantities) != set(("one", "other") if locale == "en" else PLURAL_CATEGORIES[locale]):
                raise SystemExit(f"Plural categories differ: {locale}: {source}")
            for text in quantities.values(): validate_format_compatibility(source, text, locale)
        result[source] = {"countArgument": item["countArgument"], "forms": forms}
    sources = literal_runtime_sources()
    integer = {source for source in sources if any(t == "integer" for _, t in format_signature(source))}
    if integer - set(result) - set(spec["nonPluralSources"]):
        raise SystemExit("Unclassified integer format sources: " + str(sorted(integer - set(result) - set(spec["nonPluralSources"]))))
    return result


def generate(catalog: dict) -> dict[str, dict[str, str]]:
    validate_source_aliases(catalog)
    android = android_catalog()
    phrases = source_literals()
    table: dict[str, dict[str, str]] = {}
    for locale in LOCALES:
        translations: dict[str, str] = {}
        for source in sorted(phrases):
            value = phrase_translation(catalog, android, source, locale)
            if value is not None:
                validate_format_compatibility(source, value, locale)
                if value != source:
                    translations[source] = value
        table[locale] = translations
    return table


def rewrite_sources(catalog: dict) -> int:
    replacements = 0
    for path in KOTLIN_ROOT.rglob("*.kt"):
        original = path.read_text(encoding="utf-8")

        def replace(match: re.Match[str]) -> str:
            nonlocal replacements
            encoded = match.group(2)
            source = decode_literal(encoded)
            if source is None or KOTLIN_INTERPOLATION.search(source):
                return match.group(0)
            replacements += 1
            prefix = "Text(text = " if match.group(1) else "Text("
            return prefix + "voxString(" + encoded + ")"

        rewritten = TEXT_LITERAL.sub(replace, original)
        if rewritten != original:
            path.write_text(rewritten, encoding="utf-8")
    return replacements


def raw_text_literal_paths() -> list[Path]:
    result = []
    for path in KOTLIN_ROOT.rglob("*.kt"):
        contents = path.read_text(encoding="utf-8")
        if any(
            decode_literal(match.group(2)) is not None
            for match in TEXT_LITERAL.finditer(contents)
        ):
            result.append(path)
    return result


def vox_string_call_regions(contents: str) -> list[str]:
    regions: list[str] = []
    for match in VOX_STRING_CALL.finditer(contents):
        start = match.end()
        depth = 1
        escaped = False
        in_string = False
        index = start
        while index < len(contents) and depth > 0:
            character = contents[index]
            if in_string:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    in_string = False
            elif character == '"':
                in_string = True
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            index += 1
        regions.append(contents[start:index - 1] if depth == 0 else contents[start:])
    return regions


def localization_call_regions(contents: str) -> list[tuple[int, str]]:
    regions: list[tuple[int, str]] = []
    for match in LOCALIZATION_CALL.finditer(contents):
        line_start = contents.rfind("\n", 0, match.start()) + 1
        if re.search(r"\bfun\s*$", contents[line_start:match.start()]):
            continue
        start = match.end()
        depth = 1
        escaped = False
        in_string = False
        index = start
        while index < len(contents) and depth > 0:
            character = contents[index]
            if in_string:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    in_string = False
            elif character == '"':
                in_string = True
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            index += 1
        regions.append((start, contents[start:index - 1] if depth == 0 else contents[start:]))
    return regions


def source_expression(region: str) -> str:
    depths = {"(": 0, "[": 0, "{": 0}
    closing = {")": "(", "]": "[", "}": "{"}
    escaped = False
    in_string = False
    for index, character in enumerate(region):
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character in depths:
            depths[character] += 1
        elif character in closing:
            opener = closing[character]
            depths[opener] = max(0, depths[opener] - 1)
        elif character == "," and not any(depths.values()):
            return region[:index]
    return region


def conditional_predicate_ranges(expression: str) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for match in re.finditer(r"\b(?:if|when)\s*\(", expression):
        start = match.end() - 1
        depth = 1
        escaped = False
        in_string = False
        index = start + 1
        while index < len(expression) and depth > 0:
            character = expression[index]
            if in_string:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    in_string = False
            elif character == '"':
                in_string = True
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            index += 1
        if depth == 0:
            ranges.append((start, index))
    return ranges


def literal_runtime_sources() -> dict[str, list[str]]:
    locations: dict[str, set[str]] = {}
    for path in sorted(KOTLIN_ROOT.rglob("*.kt")):
        contents = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)
        for region_start, region in localization_call_regions(contents):
            expression = source_expression(region)
            predicate_ranges = conditional_predicate_ranges(expression)
            for match in STRING_LITERAL.finditer(expression):
                if any(start <= match.start() < end for start, end in predicate_ranges):
                    continue
                source = decode_literal('"' + match.group(1) + '"')
                if source is None or KOTLIN_INTERPOLATION.search(source):
                    continue
                line = contents.count("\n", 0, region_start + match.start()) + 1
                locations.setdefault(source, set()).add(f"{relative}:{line}")
    return {source: sorted(found) for source, found in sorted(locations.items())}


def dynamic_runtime_calls() -> list[dict[str, object]]:
    calls: dict[str, set[str]] = {}
    for path in sorted(KOTLIN_ROOT.rglob("*.kt")):
        contents = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)
        if str(relative) in DYNAMIC_AUDIT_EXCLUDED_PATHS:
            continue
        for region_start, region in localization_call_regions(contents):
            expression = source_expression(region).strip()
            predicate_ranges = conditional_predicate_ranges(expression)
            values = [
                match for match in STRING_LITERAL.finditer(expression)
                if not any(start <= match.start() < end for start, end in predicate_ranges)
                and (source := decode_literal('"' + match.group(1) + '"')) is not None
                and not KOTLIN_INTERPOLATION.search(source)
            ]
            if values:
                continue
            normalized = re.sub(r"\s+", " ", expression)
            line = contents.count("\n", 0, region_start) + 1
            calls.setdefault(normalized, set()).add(f"{relative}:{line}")
    return [
        {"expression": expression, "locations": sorted(locations)}
        for expression, locations in sorted(calls.items())
    ]


def localization_audit(catalog: dict) -> dict:
    validate_source_aliases(catalog)
    sources = literal_runtime_sources()
    exact = sorted(
        source for source in sources
        if isinstance(catalog.get(source), dict) and not is_plural_variation_entry(catalog[source])
        and not missing_translation_locales(catalog[source])
    )
    incomplete = sorted(
        source for source in sources
        if isinstance(catalog.get(source), dict) and not is_plural_variation_entry(catalog[source])
        and missing_translation_locales(catalog[source])
    )
    aliases = sorted(
        source for source in sources
        if source in SOURCE_ALIASES and resolved_catalog_source(catalog, source) is not None
    )
    android = android_catalog()
    android_backed = sorted(
        source for source in sources
        if source in android and (
            resolved_catalog_source(catalog, source) is None or is_plural_variation_entry(catalog.get(source))
        )
    )
    missing = sorted(source for source in sources if resolved_catalog_source(catalog, source) is None and source not in android)
    dynamic_calls = dynamic_runtime_calls()
    integer_sources = sorted(
        source for source in sources
        if any(argument_type == "integer" for _, argument_type in format_signature(source))
    )
    return {
        "schemaVersion": 1,
        "reviewStatus": "requires-human-review",
        "formatArgumentContractStatus": "validated",
        "pluralReviewStatus": "requires-human-review",
        "catalog": str(CATALOG.relative_to(ROOT)),
        "androidCatalog": str(ANDROID_CATALOG.relative_to(ROOT)),
        "androidCatalogBackedSourceCount": len(android_backed),
        "translationCoverageStatus": "complete" if not missing and not incomplete else "incomplete",
        "pluralImplementationStatus": "cldr-aware",
        "pluralSourceCount": len(json.loads(PLURAL_SPEC.read_text())["plurals"]),
        "runtimeSourceScanRoots": [str(path.relative_to(ROOT)) for path in RUNTIME_SOURCE_ROOTS],
        "runtimeSourceLiteralCount": len(source_literals()),
        "supportedLocales": list(LOCALES),
        "literalRuntimeSourceCount": len(sources),
        "catalogBackedSourceCount": len(exact),
        "aliasBackedSourceCount": len(aliases),
        "incompleteCatalogSourceCount": len(incomplete),
        "missingCatalogSourceCount": len(missing),
        "fallbackSourceCount": len(incomplete) + len(missing),
        "dynamicRuntimeCallSiteCount": sum(len(item["locations"]) for item in dynamic_calls),
        "dynamicRuntimeExpressionCount": len(dynamic_calls),
        "integerFormatSourceCount": len(integer_sources),
        "aliases": [
            {"source": source, "catalogSource": SOURCE_ALIASES[source]}
            for source in aliases
        ],
        "missingCatalogSources": [
            {"source": source, "locations": sources[source]}
            for source in missing
        ],
        "incompleteCatalogSources": [
            {
                "source": source,
                "missingLocales": missing_translation_locales(catalog[source]),
                "locations": sources[source],
            }
            for source in incomplete
        ],
        "dynamicRuntimeCalls": dynamic_calls,
        "integerFormatSources": [
            {"source": source, "locations": sources[source]}
            for source in integer_sources
        ],
        "limitations": [
            "This is a deterministic literal-source audit, not translation approval.",
            "Dynamic-source call sites are inventoried; the current finite-domain trace has no unresolved dynamic expressions.",
            "Missing sources fall back to English; Android machine translations require human linguistic review.",
        ],
    }


def interpolated_vox_string_paths() -> list[Path]:
    result = []
    for path in KOTLIN_ROOT.rglob("*.kt"):
        contents = path.read_text(encoding="utf-8")
        if any(
            (source := decode_literal('"' + match.group(1) + '"')) is not None
            and KOTLIN_INTERPOLATION.search(source)
            for region in vox_string_call_regions(contents)
            for match in STRING_LITERAL.finditer(region)
        ):
            result.append(path)
    return result


def raw_text_conditional_paths() -> list[Path]:
    return [
        path
        for path in KOTLIN_ROOT.rglob("*.kt")
        if RAW_TEXT_CONDITIONAL.search(path.read_text(encoding="utf-8"))
    ]


def raw_accessibility_text_paths() -> list[Path]:
    return [
        path
        for path in KOTLIN_ROOT.rglob("*.kt")
        if RAW_ACCESSIBILITY_TEXT.search(path.read_text(encoding="utf-8"))
    ]


def platform_resource_files(catalog: dict) -> dict[Path, str]:
    result: dict[Path, str] = {}
    for resource_root, strings in ((RESOURCES, PLATFORM_STRINGS), (WEAR_RESOURCES, WEAR_PLATFORM_STRINGS)):
        for locale, qualifier in ANDROID_QUALIFIERS.items():
            lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
            for name, source in strings.items():
                entry = catalog.get(source)
                if not isinstance(entry, dict):
                    raise SystemExit(f"missing platform string in iOS catalog: {source}")
                value = translated_value(entry, locale)
                if value is None:
                    raise SystemExit(f"missing {locale} platform translation: {source}")
                validate_format_compatibility(source, value, locale)
                value = value.replace("%lld", "%1$d")
                lines.append(f'    <string name="{name}">{android_string(value)}</string>')
            lines.append("</resources>")
            result[resource_root / f"values-{qualifier}" / "platform_localizations.xml"] = "\n".join(lines) + "\n"
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rewrite", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
    replacements = rewrite_sources(catalog) if args.rewrite else 0
    encoded = json.dumps(generate(catalog), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    audit = localization_audit(catalog)
    encoded_audit = json.dumps(audit, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    platform_files = platform_resource_files(catalog)
    plurals = generate_plurals(catalog, android_catalog())
    platform_files[RESOURCES / "raw/vox_runtime_plurals.json"] = json.dumps(plurals, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    watch_source = "%lld recordings saved on Watch."
    for locale, qualifier in [("en", ""), *ANDROID_QUALIFIERS.items()]:
        forms = plurals[watch_source]["forms"][locale]
        lines = ['<?xml version="1.0" encoding="utf-8"?>', '<resources>', '    <plurals name="wear_recordings_saved">']
        for category, value in forms.items():
            lines.append(f'        <item quantity="{category}">{android_string(value.replace("%lld", "%1$d"))}</item>')
        lines.extend(['    </plurals>', '</resources>'])
        platform_files[WEAR_RESOURCES / ("values" + ("-" + qualifier if qualifier else "")) / "platform_plurals.xml"] = "\n".join(lines) + "\n"
    if args.check:
        raw_paths = raw_text_literal_paths()
        if raw_paths:
            rendered = ", ".join(str(path.relative_to(ROOT)) for path in raw_paths)
            raise SystemExit(f"raw Compose Text literals bypass voxString: {rendered}")
        interpolated_paths = interpolated_vox_string_paths()
        if interpolated_paths:
            rendered = ", ".join(str(path.relative_to(ROOT)) for path in interpolated_paths)
            raise SystemExit(f"interpolated voxString calls cannot match catalog keys; use voxFormat: {rendered}")
        conditional_paths = raw_text_conditional_paths()
        if conditional_paths:
            rendered = ", ".join(str(path.relative_to(ROOT)) for path in conditional_paths)
            raise SystemExit(f"raw conditional Compose Text literals bypass voxString: {rendered}")
        accessibility_paths = raw_accessibility_text_paths()
        if accessibility_paths:
            rendered = ", ".join(str(path.relative_to(ROOT)) for path in accessibility_paths)
            raise SystemExit(f"raw accessibility text bypasses localization: {rendered}")
        if not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf-8") != encoded:
            raise SystemExit("runtime localization table is stale; run generate-runtime-localizations.py")
        if not AUDIT.is_file() or AUDIT.read_text(encoding="utf-8") != encoded_audit:
            raise SystemExit("localization review audit is stale; run generate-runtime-localizations.py")
        for path, expected in platform_files.items():
            if not path.is_file() or path.read_text(encoding="utf-8") != expected:
                raise SystemExit(f"platform localization is stale: {path}")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(encoded, encoding="utf-8")
        AUDIT.write_text(encoded_audit, encoding="utf-8")
        for path, contents in platform_files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents, encoding="utf-8")
    print(
        f"runtime localizations: {sum(len(v) for v in json.loads(encoded).values())} entries; "
        f"literal sources: {audit['literalRuntimeSourceCount']}; "
        f"missing catalog sources: {audit['missingCatalogSourceCount']}; rewrites: {replacements}"
    )


if __name__ == "__main__":
    main()
