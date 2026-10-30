#!/usr/bin/env python3
"""Render guide sources to deployable static HTML; --check detects stale output."""

import argparse
from datetime import date
from html import escape
import json
from pathlib import Path
import re

from download_links import decorate_html

ROOT = Path(__file__).resolve().parents[2]
HOST = "https://vox.isolated.tech"


def render(source, template):
    text = source.read_text()
    if not text.startswith("<!--") or "-->" not in text:
        raise ValueError(f"Missing JSON metadata comment: {source}")
    metadata, body = text[4:].split("-->", 1)
    meta = json.loads(metadata)
    slug = meta["slug"]
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", slug) or source.stem != slug:
        raise ValueError(f"Invalid guide slug: {source}")
    section = meta.get("section", "blog")
    if section not in ("blog", "compare"):
        raise ValueError(f"Invalid guide section: {source}")
    section_label = "Guides" if section == "blog" else "Comparisons"
    published = date.fromisoformat(meta["published"])
    modified = date.fromisoformat(meta["modified"])
    if modified < published:
        raise ValueError(f"Modified date precedes publication: {source}")
    url = f"{HOST}/{section}/{slug}/"
    image = HOST + meta["image"]
    article = {
        "@context": "https://schema.org", "@type": "BlogPosting" if section == "blog" else "Article",
        "headline": meta["title"], "description": meta["description"],
        "image": image, "datePublished": meta["published"],
        "dateModified": meta["modified"], "mainEntityOfPage": url,
        "author": {"@type": "Person", "name": "Cody Bontecou", "url": "https://codybontecou.com/"},
        "publisher": {"@type": "Organization", "name": "Isolated Tech", "url": "https://isolated.tech/"},
    }
    breadcrumb = {
        "@context": "https://schema.org", "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": i, "name": name, "item": item}
            for i, (name, item) in enumerate([
                ("Vox.md", HOST + "/"), (section_label, f"{HOST}/{section}/"),
                (meta["title"], url),
            ], 1)
        ],
    }
    values = {key.upper(): escape(str(value), quote=True) for key, value in meta.items()}
    values.update({
        "URL": url, "IMAGE": image,
        "FACT_LABEL": escape(meta.get("fact_label", "Requires")),
        "DISPLAY_DATE": f"{modified.strftime('%B')} {modified.day}, {modified.year}",
        "BODY": body.strip(),
        "SCHEMA": "\n".join(
            '<script type="application/ld+json">\n'
            + json.dumps(data, ensure_ascii=False, indent=2).replace("<", "\\u003c")
            + "\n</script>" for data in (article, breadcrumb)
        ),
    })
    # Substitute the template once: body content is not a template language.
    output = re.sub(r"__([A-Z_]+)__", lambda match: values[match[1]], template)
    output = decorate_html(output, f"/{section}/{slug}/")
    return ROOT / "website" / section / slug / "index.html", output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    template = (ROOT / "scripts/website/templates/guide.html").read_text()
    stale = []
    sources = sorted((ROOT / "website-content/guides").glob("*.html"))
    if not sources:
        raise SystemExit("No guide sources found")
    for source in sources:
        target, output = render(source, template)
        if args.check:
            if not target.exists() or target.read_text() != output:
                stale.append(str(target.relative_to(ROOT)))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(output)
    if stale:
        raise SystemExit("Run npm run website:build; stale guides:\n" + "\n".join(stale))
    print(f"{'Checked' if args.check else 'Built'} {len(sources)} static guides")


if __name__ == "__main__":
    main()
