#!/usr/bin/env python3
"""Correct the app's own translations for UI terms visible in the App Store screenshots.

Real localized captures exposed catalog entries that are wrong (ja "Export" = 輸出, trade
export; ja "Queued" = ケータイ; es "Today" = "Hoy en día") or missing (iPad/Duo
sidebar and route-inspector labels). The store-frame translations in
scripts/localization/store-screenshots/strings/<locale>.json were reviewed per language,
so they are the source here. Only the terms below are touched.

    python3 scripts/localization/fix_visible_catalog_terms.py [--check]
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CATALOG = REPO / "Voxboard/Localizable.xcstrings"
STRINGS = REPO / "scripts/localization/store-screenshots/strings"

# store locale file -> catalog language
LANGS = {
    "ar-SA": "ar", "de-DE": "de", "es-ES": "es", "fr-FR": "fr", "hi": "hi", "id": "id",
    "it": "it", "ja": "ja", "ko": "ko", "nl-NL": "nl", "pl": "pl", "pt-BR": "pt-BR",
    "ru": "ru", "th": "th", "tr": "tr", "uk": "uk", "vi": "vi", "zh-Hans": "zh-Hans",
    "zh-Hant": "zh-Hant",
}


def sentence_case(text: str, lang: str) -> str:
    if text != text.upper() or text == text.lower():
        return text  # already mixed case, or a script without case
    lower = text.lower() if lang != "tr" else text.replace("I", "ı").replace("İ", "i").lower()
    return lower[:1].upper() + lower[1:]


def last_part(text: str) -> str:
    return text.split("·")[-1].strip()


# catalog key -> (how to derive it from a store-frame string, when to apply it).
# "missing": only fill absent entries. "all": the shipped values are wrong almost
# everywhere. A set: only those languages, as flagged in review. Untranslated English
# (value equal to the key) is always replaced.
TERMS = {
    # labels the redesign rendered verbatim (now localized in code)
    "ROUTES": (lambda t, l: t("ROUTES"), "missing"),
    "VIEWS": (lambda t, l: t("VIEWS"), "missing"),
    "CAPTURE": (lambda t, l: t("CAPTURE"), "missing"),
    "PROCESS": (lambda t, l: t("PROCESS"), "missing"),
    "SHAPE": (lambda t, l: t("SHAPE"), "missing"),
    "DELIVER": (lambda t, l: t("DELIVER"), "missing"),
    "WILL WRITE": (lambda t, l: t("WILL WRITE"), "missing"),
    "THIS ROUTE": (lambda t, l: t("THIS ROUTE"), "missing"),
    "ROUTE": (lambda t, l: t("ROUTE"), "missing"),
    # mistranslated in the shipped catalog
    "Export": (lambda t, l: t("Export"), {"ja", "ko", "zh-Hans", "zh-Hant", "vi", "es", "pt-BR", "fr", "ru", "tr", "it", "uk"}),
    "Edit": (lambda t, l: t("Edit"), "all"),
    "Send": (lambda t, l: t("Send"), {"es", "pt-BR", "hi", "it", "ja", "uk"}),
    "Voice": (lambda t, l: t("Voice"), {"es", "it", "ja", "ko", "zh-Hans", "id", "de"}),
    "Checklist": (lambda t, l: t("Checklist"), {"zh-Hans", "id", "es"}),
    "Sketch": (lambda t, l: t("Sketch"), {"uk", "ar", "fr", "vi", "de"}),
    "Scan": (lambda t, l: t("Scan"), {"vi", "tr", "ar", "de"}),
    "Activity": (lambda t, l: t("Activity"), {"pl", "hi", "tr", "ja", "vi"}),
    "Today": (lambda t, l: sentence_case(t("TODAY"), l), {"ko", "es", "pt-BR"}),
    "Delivered": (lambda t, l: sentence_case(t("DELIVERED"), l), {"ja", "ko", "zh-Hans", "ar", "pl"}),
    "Queued": (lambda t, l: capitalize(t("queued")), {"es", "pt-BR", "ja", "ar"}),
    "append": (lambda t, l: last_part(t("Daily · append")), "all"),
    "prepend": (lambda t, l: last_part(t("Weekly · prepend")), "all"),
}


# Per-language overrides of the derived values above (layout or wording).
OVERRIDES = {
    # "başa ekle" wraps the Routes card chip ("Haftalık · başa ekle") onto the next card.
    ("prepend", "tr"): "başa",
}

# Terms with no store-frame source: explicit per-language values.
# "Disabled" (a route that is turned off) shipped as "disabled people" in most languages.
EXPLICIT = {
    "Disabled": {
        "ar": "معطّل", "bn": "নিষ্ক্রিয়", "de": "Deaktiviert", "es": "Desactivado", "fr": "Désactivé",
        "hi": "अक्षम", "id": "Nonaktif", "it": "Disattivato", "ja": "無効", "ko": "사용 안 함",
        "nl": "Uitgeschakeld", "pl": "Wyłączone", "pt-BR": "Desativado", "ru": "Отключено",
        "ta": "முடக்கப்பட்டது", "th": "ปิดใช้งาน", "tr": "Devre dışı", "uk": "Вимкнено",
        "ur": "غیر فعال", "vi": "Đã tắt", "zh-Hans": "已停用", "zh-Hant": "已停用",
    },
    # Recording-details attachment chip: "Audi" (ar), "Audião" (pt-BR), "About Audio" (tr)…
    "Audio": {
        "ar": "صوت", "id": "Audio", "it": "Audio", "pt-BR": "Áudio", "ta": "ஆடியோ",
        "th": "เสียง", "tr": "Ses",
    },
    # Library reading-pane tab: shipped as "translation" (ar, bn, th), "translator" (ko),
    # "transfer" (ur) or half English (id, tr, vi, ta).
    "Transcript": {
        "ar": "النص المفرّغ", "bn": "ট্রান্সক্রিপ্ট", "id": "Transkrip", "it": "Trascrizione",
        "ko": "녹취록", "pl": "Transkrypcja", "ta": "எழுத்துப்படி", "th": "ข้อความถอดเสียง",
        "tr": "Transkript", "ur": "ٹرانسکرپٹ", "vi": "Bản ghi lời",
    },
}


def capitalize(text: str) -> str:
    return text[:1].upper() + text[1:]


def main() -> int:
    check = "--check" in sys.argv
    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]
    changes = []
    for store_locale, lang in LANGS.items():
        table = json.loads((STRINGS / f"{store_locale}.json").read_text())
        t = lambda key: table[key]
        for key, (derive, scope) in TERMS.items():
            value = OVERRIDES.get((key, lang)) or derive(t, lang).strip()
            entry = strings.setdefault(key, {})
            locs = entry.setdefault("localizations", {})
            current = locs.get(lang, {}).get("stringUnit", {}).get("value")
            untranslated = current is not None and current.lower() == key.lower() and value.lower() != key.lower()
            applies = (
                current is None if scope == "missing"
                else scope == "all" or lang in scope or untranslated
            )
            if applies and current != value:
                changes.append(f"{lang:7} {key!r}: {current!r} -> {value!r}")
                locs[lang] = {"stringUnit": {"state": "translated", "value": value}}
    for key, values in EXPLICIT.items():
        locs = strings.setdefault(key, {}).setdefault("localizations", {})
        for lang, value in values.items():
            current = locs.get(lang, {}).get("stringUnit", {}).get("value")
            if current != value:
                changes.append(f"{lang:7} {key!r}: {current!r} -> {value!r}")
                locs[lang] = {"stringUnit": {"state": "translated", "value": value}}
    for line in changes:
        print(line)
    print(f"{len(changes)} catalog values {'would change' if check else 'updated'}")
    if not check:
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", ": ")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
