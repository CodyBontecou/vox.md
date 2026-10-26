#!/usr/bin/env python3
"""Check static page metadata, local links/assets, anchors and sitemap URLs."""

from collections import Counter
from html.parser import HTMLParser
import json
from pathlib import Path
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2] / "website"
HOST = "https://vox.isolated.tech"


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.path = path
        self.ids = []
        self.references = []
        self.counts = Counter()
        self.canonicals = []
        self.descriptions = []
        self.schema = []
        self.script_text = None
        self.feed(path.read_text())

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        self.counts[tag] += 1
        if "id" in attrs:
            self.ids.append(attrs["id"])
        if tag == "link" and attrs.get("rel") == "canonical":
            self.canonicals.append(attrs.get("href", ""))
        if tag == "meta" and attrs.get("name") == "description":
            self.descriptions.append(attrs.get("content", ""))
        if tag in ("a", "link", "script", "img", "source"):
            for key in ("href", "src"):
                if attrs.get(key):
                    self.references.append(attrs[key])
            if attrs.get("srcset"):
                self.references.extend(item.strip().split()[0] for item in attrs["srcset"].split(","))
        if tag == "script" and attrs.get("type") == "application/ld+json":
            self.script_text = ""

    def handle_data(self, text):
        if self.script_text is not None:
            self.script_text += text

    def handle_endtag(self, tag):
        if tag == "script" and self.script_text is not None:
            self.schema.append(json.loads(self.script_text))
            self.script_text = None


def main():
    pages = {path.resolve(): Page(path) for path in ROOT.rglob("*.html")}
    errors = []

    def fail(page, message):
        errors.append(f"{page.path.relative_to(ROOT)}: {message}")

    for path, page in pages.items():
        for tag in ("title", "h1", "main"):
            if page.counts[tag] != 1:
                fail(page, f"expected one {tag}, found {page.counts[tag]}")
        if len(page.ids) != len(set(page.ids)):
            fail(page, "duplicate element IDs")
        if len(page.descriptions) != 1 or not page.descriptions[0].strip():
            fail(page, "expected one nonempty meta description")
        relative = path.relative_to(ROOT)
        canonical = HOST + "/" + relative.as_posix()
        if canonical.endswith("index.html"):
            canonical = canonical[:-len("index.html")]
        if page.canonicals != [canonical]:
            fail(page, f"expected canonical {canonical}")
        for reference in page.references:
            url = urlsplit(reference)
            if url.scheme or url.netloc:
                if url.scheme in ("http", "https") and url.netloc == urlsplit(HOST).netloc:
                    target = ROOT / unquote(url.path).lstrip("/")
                else:
                    continue
            elif url.path:
                target = (ROOT / unquote(url.path).lstrip("/")) if url.path.startswith("/") else path.parent / unquote(url.path)
            else:
                target = path
            if target.is_dir():
                target /= "index.html"
            target = target.resolve()
            if not target.is_relative_to(ROOT.resolve()) or not target.exists():
                fail(page, f"missing local target: {reference}")
            elif url.fragment and target in pages and unquote(url.fragment) not in pages[target].ids:
                fail(page, f"missing fragment: {reference}")

    urls = [node.text for node in ET.parse(ROOT / "sitemap.xml").findall(".//{*}loc")]
    if len(urls) != len(set(urls)):
        errors.append("Sitemap contains duplicate URLs")
    submitted = set(urls)
    for page in pages.values():
        if page.canonicals and page.canonicals[0] not in submitted:
            fail(page, "canonical missing from sitemap")
    known = {canonical for page in pages.values() for canonical in page.canonicals}
    for url in submitted - known:
        errors.append(f"Sitemap URL has no canonical page: {url}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Checked {len(pages)} pages and {len(urls)} sitemap URLs: metadata, JSON-LD, local links/assets and anchors pass")


if __name__ == "__main__":
    main()
