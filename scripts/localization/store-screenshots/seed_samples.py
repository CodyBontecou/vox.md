#!/usr/bin/env python3
"""Print the `-VoxSeedSamples` JSON for a locale (or write all to strings/seed/).

The DEBUG seed (`-VoxAdaptiveSeedDemo -VoxAdaptiveSeedLibrary`) fills the draft and
library with sample notes. For store screenshots each language must show the same
notes as the localized frames, so the text is assembled from strings/<locale>.json.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def tr(dictionary: dict, key: str) -> str:
    return dictionary.get(key, key)


def first_sentence(text: str) -> str:
    """The journal preview is cut off mid-sentence ("…before…"); keep its first full sentence."""
    import re
    match = re.match(r"(.+?(?:[.!?](?=\s|$)|[。！？।]))", text.strip())
    if match:
        return match.group(1)
    # Thai marks sentence breaks with a space, not punctuation.
    return text.strip().split(" ")[0].rstrip(" …")


def samples(locale: str) -> dict:
    d = {} if locale == "en-US" else json.loads((HERE / "strings" / f"{locale}.json").read_text())
    t = lambda k: tr(d, k)
    errands = [s.strip() for s in t("Renew passport · call the dentist · …").split("·")]
    errands = [e for e in errands if e and e not in ("…", "...")]
    return {
        "draft": "# {}\n- [ ] {}\n- [ ] {}\n\n{}".format(
            t("Project sync"),
            t("Review final designs"),
            t("Loop in design before Friday"),
            t("Decision: ship routing first and keep the composer calm"),
        ),
        "designCrit": "# {}\n{}".format(t("Design crit"), t("Keyboard picker needs bigger targets")),
        "tasks": "\n".join(f"- [ ] {e[:1].upper()}{e[1:]}" for e in errands),
        "morningPages": "{}\n{}".format(t("Morning pages"), first_sentence(t("Slept well. Want to keep the walk before…"))),
        "bookRecs": "{}\n{}".format(t("Book recs from Sam"), t("The Overstory, then anything by Le Guin")),
        "liveFinalized": t("So the plan is to ship routing first, and keep the composer exactly as calm as it is now."),
        "liveVolatile": t("Agreed. Can we add a task for the release notes and loop in design before Friday"),
    }


if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(json.dumps(samples(sys.argv[1]), ensure_ascii=False))
    else:
        out = HERE / "strings" / "seed"
        out.mkdir(exist_ok=True)
        locales = ["en-US"] + sorted(p.stem for p in (HERE / "strings").glob("*.json") if p.stem != "en")
        for loc in locales:
            (out / f"{loc}.json").write_text(json.dumps(samples(loc), ensure_ascii=False, indent=2) + "\n")
        print(f"wrote {len(locales)} seed files to {out}")
