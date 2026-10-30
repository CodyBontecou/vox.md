#!/usr/bin/env python3
"""Build the static website with embedded CSS to avoid a render-blocking request."""
import argparse
import json
from html import unescape
from website_markdown import MarkdownDocument
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent


def build(destination: Path) -> None:
    source = ROOT / 'website'
    if destination.exists():
        raise SystemExit(f'Refusing to overwrite existing directory: {destination}')
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns('.DS_Store'))
    css = (source / 'geist.css').read_text()
    # Font URLs now resolve from each HTML document, including nested docs pages.
    css = re.sub(r'url\("(?!/|https?:|data:)([^\"]+)"\)', r'url("/\1")', css)
    # Strip comments and indentation without rewriting values or CSS strings.
    css = re.sub(r'/\*.*?\*/', '', css, flags=re.S)
    css = '\n'.join(line.strip() for line in css.splitlines() if line.strip())
    markdown_routes = {}
    documents = []
    product = {}
    for page in destination.rglob('*.html'):
        html = page.read_text()
        relative = page.relative_to(destination).as_posix()
        route = '/' + relative
        canonical = route[:-10] if route.endswith('index.html') else route[:-5]
        parser = MarkdownDocument('https://vox.isolated.tech' + canonical)
        parser.feed(html)
        if relative == 'index.html':
            blocks = re.findall(r'<script type="application/ld\+json">(.*?)</script>', html, re.S)
            app = next(item for block in blocks if (item := json.loads(block)).get('@type') == 'SoftwareApplication')
            product = {key: app[key] for key in ['name', 'description', 'url', 'downloadUrl', 'operatingSystem', 'applicationCategory']}
            product['documentationUrl'] = 'https://vox.isolated.tech/docs/'
            product['supportUrl'] = 'https://vox.isolated.tech/contact'
        if relative != '404.html':
            title = unescape(re.search(r'<title>(.*?)</title>', html, re.S)[1])
            description = unescape(re.search(r'<meta name="description" content="([^"]*)', html)[1])
            documents.append({'title': title, 'url': 'https://vox.isolated.tech' + canonical,
                              'description': description, 'markdownUrl': 'https://vox.isolated.tech' + canonical})
        markdown_path = '/' + relative[:-5] + '.md'
        markdown = parser.markdown()
        if not parser.has_title:
            # Some article layouts put the document heading before <main>.
            markdown = '# ' + title + '\n\n' + markdown
        page.with_suffix('.md').write_text(markdown)
        for alias in {route, canonical, route[:-5]}:
            markdown_routes[alias] = markdown_path
        html, count = re.subn(
            r'<link rel="stylesheet" href="(?:/|(?:\.\./)*)geist\.css">',
            lambda _: '<style data-source="geist.css">\n' + css + '\n</style>',
            html,
        )
        inline_count = len(re.findall(r'<style(?:\s[^>]*)?>', html))
        # Authored localized landing pages may carry their own font/layout CSS.
        # Preserve one self-contained stylesheet; still reject unstyled/duplicate pages.
        if count != 1 and not (count == 0 and inline_count == 1):
            raise SystemExit(f'Expected one shared or inline stylesheet in {page}')
        page.write_text(html)
    worker = (ROOT / 'worker/website/index.mjs').read_text()
    worker = worker.replace('/* @generated-markdown-routes */ {}', json.dumps(markdown_routes, sort_keys=True))
    worker = worker.replace('/* @generated-public-data */ {}', json.dumps({'product': product, 'documents': sorted(documents, key=lambda item: item['url'])}, sort_keys=True))
    (destination / '_worker.js').write_text(worker)
    (destination / '_routes.json').write_text(json.dumps({
        'version': 1, 'include': ['/*'],
        'exclude': ['/fonts/*', '/screenshots/*', '/blog/best-voice-to-text-keyboard-iphone/assets/*'],
    }))
    print(f'Built website: {destination}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    build(parser.parse_args().destination.resolve())
