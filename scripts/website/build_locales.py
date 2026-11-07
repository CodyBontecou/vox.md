#!/usr/bin/env python3
"""Render locale catalogs from English page/guide sources, without translation APIs.

--extract refreshes en.json; --check never writes; --check-catalog validates only.
Catalog IDs are content hashes: unchanged segments keep their IDs across edits.
"""
import argparse
from collections import Counter
from hashlib import sha256
from html import escape, unescape
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
from urllib.parse import urljoin, urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / 'website'
CATALOGS = ROOT / 'website-content/locales'
HOST = 'https://vox.isolated.tech'
LANGUAGES = {'en': 'English', 'ar': 'العربية', 'bn': 'বাংলা', 'de': 'Deutsch', 'es': 'Español', 'fr': 'Français', 'hi': 'हिन्दी', 'id': 'Bahasa Indonesia', 'it': 'Italiano', 'ja': '日本語', 'ko': '한국어', 'nl': 'Nederlands', 'pl': 'Polski', 'pt-BR': 'Português (Brasil)', 'ru': 'Русский', 'ta': 'தமிழ்', 'th': 'ไทย', 'tr': 'Türkçe', 'uk': 'Українська', 'ur': 'اردو', 'vi': 'Tiếng Việt', 'zh-Hans': '简体中文', 'zh-Hant': '繁體中文'}
PROTECTED = ['Vox.md', 'Apple Intelligence', 'Apple Speech', 'Whisper', 'whisper.cpp', 'Parakeet', 'FluidAudio', 'CoreML', 'Obsidian', 'Markdown', 'App Store', 'Apple Watch', 'iPhone', 'iPad', 'iOS', 'iPadOS', 'watchOS', 'macOS', 'Android', 'Google Play', 'Wear OS', 'M4A', 'WAV', 'TXT', 'JSON', 'YAML', 'SF Symbols', 'ZenQuotes', 'Core ML', 'Whisper Tiny', 'Whisper Base', 'Whisper Small', 'Whisper Medium', 'Whisper Large v3 Turbo', 'Parakeet v2', 'Parakeet v3', 'Daily Inbox']
# Longest first prevents Whisper being counted inside whisper.cpp, etc.
TOKENS = re.compile('|'.join(re.escape(s) for s in sorted(PROTECTED, key=len, reverse=True)) + r'|\b(?:Command|Control|Option|Shift|Ctrl|Alt|Cmd)(?:[-+](?:Command|Control|Option|Shift|Ctrl|Alt|Cmd|Return|Enter|Tab|Space|Escape|Delete|Backspace|[A-Za-z0-9]))+\b|[⌘⌃⌥⇧]+[A-Za-z0-9↵⏎]|±\d+(?:m|h)\b|https?://[^\s<>"\)。、」』”]+|[\w.+-]+@[\w.-]+|\{[^{}]*\}|%\d*\$?[a-zA-Z@]|\[\[[^\]]*\]\]|(?:[\w{}.-]+/)+[\w{}.-]+\.(?:md|json|html|txt|yml|yaml|xml|wav|m4a|jpg|png)\b|(?<![\w/.-])/(?:[\w{}.-]+/)*[\w{}.-]+|\b[\w.-]+\.(?:md|json|html|txt|yml|yaml|xml|wav|m4a|jpg|png)\b')
NOTICE = 'This translation is provided for convenience. The English version governs in case of any discrepancy.'
LABEL = 'Language'
# Exact current-source occurrences name tutorial headings/routes, not app UI
# controls. Keep them aligned with the deliberately unchanged sample code.
LITERAL_EXAMPLES = {'Inbox', 'Tasks', 'Daily Inbox'}
SEARCH_TEXT = {'section': 'Section', 'guide': 'Guide', 'empty': 'No matches for “{query}”'}
SCHEMA_TEXT = {'name', 'description', 'headline', 'text', 'featureList', 'contactType', 'availableLanguage', 'articleBody', 'caption'}
VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}


def key(text):
    return 's_' + sha256(text.encode()).hexdigest()[:16]


def literal(text):
    """Explicit lexical allowlist for code/brands/names, not English fallback."""
    rest = TOKENS.sub('', text)
    rest = re.sub(r'\b(?:Cody Bontecou|Isolated Tech|SteamingCoax|Eric Know|PromisedOne|Safari|Mac|EOF|md|en|USD|B|GB|MB|KB|HTTP|HTTPS|URL|API|GET|POST)\b', '', rest)
    if text in LITERAL_EXAMPLES or re.fullmatch(r'#{1,6} (?:Inbox|Tasks|Notes)',text):
        return True
    model_name = re.fullmatch(r'(?:Whisper (?:Tiny|Base|Small|Medium|Large v3 Turbo)|Parakeet v[23]):?', text)
    directory = re.fullmatch(r'[\w./~-]+/',text)
    file_example = re.fullmatch(r'(?:[\w{}.-]+/)+[\w{}.-]+(?: \d+)?\.(?:md|json|html|txt|yml|yaml|xml|wav|m4a|jpg|png)',text)
    return not re.search('[a-zA-Z]', rest) or bool(model_name or directory or file_example or re.fullmatch(r'[A-Za-z_]+(?:_[A-Za-z_]+)+', text))


def route(relative):
    s = str(relative)
    if s.endswith('index.html'):
        return '/' + s[:-10]
    # Preserve existing legal .html canonicals; other top-level pages are extensionless.
    if Path(s).name in {'about.html', 'contact.html', 'developers.html', '404.html'}:
        s = s[:-5]
    return '/' + s


def localized(url, locale):
    return url if locale == 'en' else '/' + locale.lower() + url


def sources():
    from build_guides import render
    result = {p.relative_to(ROOT / 'website-content/pages').as_posix(): p.read_text() for p in (ROOT / 'website-content/pages').rglob('*.html')}
    template = (ROOT / 'scripts/website/templates/guide.html').read_text()
    for source in (ROOT / 'website-content/guides').glob('*.html'):
        target, text = render(source, template)
        result[target.relative_to(SITE).as_posix()] = text
    return {r: re.sub(r'(?m)^[ \t]*<nav aria-label="Language">.*?</nav>', '', text, flags=re.S) for r,text in sorted(result.items())}


class Segments(HTMLParser):
    """Lossless offset edits: scripts, styles, code and sample files remain literal."""
    def __init__(self, text, strings=None, collect=None):
        super().__init__(convert_charrefs=False)
        self.text = text
        self.strings = strings
        self.collect = collect
        self.edits = []
        self.stack = []
        self.classes = []
        self.lines = [0]
        for m in re.finditer('\n', text):
            self.lines.append(m.end())
        self.feed(text)

    def pos(self):
        line, col = self.getpos()
        return self.lines[line - 1] + col

    def translate(self, value):
        text = unescape(value).strip()
        if not text or not re.search(r'[A-Za-z]', text):
            return value
        ident = key(text)
        if self.collect is not None:
            self.collect[ident] = text
        if self.strings is None:
            return value
        translation = self.strings[ident]
        leading = value[:len(value) - len(value.lstrip())]
        trailing = value[len(value.rstrip()):]
        return leading + escape(translation, quote=True) + trailing

    def handle_starttag(self, tag, attrs):
        raw = self.get_starttag_text()
        start = self.pos()
        a = dict(attrs)
        if not any(t in {'script', 'style', 'svg'} for t in self.stack):
            for m in re.finditer(r'([\w:-]+)\s*=\s*([\'"])(.*?)\2', raw, re.S):
                name, value = m[1], m[3]
                if name in {'alt', 'title', 'aria-label', 'placeholder'} or (tag == 'meta' and name == 'content' and (a.get('name', '') in {'description', 'twitter:title', 'twitter:description', 'twitter:image:alt'} or a.get('property', '') in {'og:title', 'og:description', 'og:site_name', 'og:image:alt'})):
                    self.edits.append((start + m.start(3), start + m.end(3), self.translate(value)))
        if tag not in VOID:
            self.stack.append(tag)
            self.classes.append(set(a.get('class','').split()))

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if tag in self.stack:
            depth = len(self.stack) - 1 - self.stack[::-1].index(tag)
            self.stack = self.stack[:depth]
            self.classes = self.classes[:depth]

    def literal_context(self):
        classes = set().union(*self.classes) if self.classes else set()
        return (any(t in {'script','style','code','pre','kbd','samp','svg'} for t in self.stack)
                or bool(classes & {'r-tree','r-file','r-tab-current'})
                or ('r-yaml' in classes and self.stack[-1:] == ['dt']))

    def handle_data(self, data):
        if self.literal_context():
            return
        start = self.pos()
        # Merge entity references with adjacent text before parsing (see transform).
        self.edits.append((start, start + len(data), self.translate(data)))

    def output(self):
        text = self.text
        for start, end, value in sorted(self.edits, reverse=True):
            text = text[:start] + value + text[end:]
        return text


def schema_walk(data, translate, field=None):
    if isinstance(data, dict):
        return {k: schema_walk(v, translate, k) for k, v in data.items()}
    if isinstance(data, list):
        return [schema_walk(v, translate, field) for v in data]
    if isinstance(data, str) and field in SCHEMA_TEXT:
        return unescape(translate(data))
    return data


def transform(text, strings=None, collect=None):
    # Parse text-node spans directly to retain entity lengths and byte offsets.
    class EntityParser(Segments):
        def handle_data(self, data):
            if self.literal_context():
                return
            start = self.pos()
            end = self.text.find('<', start)
            if end == -1:
                end = len(self.text)
            if self.edits and any(a <= start < b for a,b,_ in self.edits):
                return
            value = self.text[start:end]
            self.edits.append((start, end, self.translate(value)))
        def handle_entityref(self, name):
            self.handle_data('')
        def handle_charref(self, name):
            self.handle_data('')
    p = EntityParser(text, strings, collect)
    output = p.output()
    def schema(m):
        obj = schema_walk(json.loads(m[1]), p.translate)
        return '<script type="application/ld+json">\n' + json.dumps(obj, ensure_ascii=False, indent=2).replace('<', '\\u003c') + '\n</script>'
    return re.sub(r'<script type="application/ld\+json">(.*?)</script>', schema, output, flags=re.S)


def identical_translation_allowlists(strings):
    """Source-owned exceptions, never a translator-controlled English fallback.

    The task requires exact shipped UI labels, including labels deliberately
    retained in English. Only short, explicitly translated app entries qualify;
    long copied help/prose never gains an exception through this mechanism.
    """
    allowed = {locale: set() for locale in LANGUAGES if locale != 'en'}
    app = json.loads((ROOT / 'Voxboard/Localizable.xcstrings').read_text())
    for source, unit in app['strings'].items():
        localizations = unit.get('localizations', {})
        source = localizations.get('en', {}).get('stringUnit', {}).get('value', source)
        ident = key(source)
        if ident not in strings or len(source) > 60 or len(source.split()) > 6:
            continue
        for locale in allowed:
            translation = localizations.get(locale, {}).get('stringUnit', {})
            if translation.get('state') == 'translated' and translation.get('value') == source:
                allowed[locale].add(ident)
    # Worker-reported and source-reviewed lexical identities, including Dutch
    # imperatives shared with English. Exact locale/segment matches only, never
    # arbitrary prose fallback. Widgets is covered by shipped app labels.
    natural_identities = {
        'es': ('Ideas', 'local', 'bytes', 'Control', 'Blog', 'no', 'Token'),
        'id': ('Blog', 'Platform', 'Token'),
        'nl': ('bytes', 'wikilink.', 'Privacy', 'cloud', '03 / Routes',
               'sitemap', 'route:', 'link.', 'Open Vox.md.', 'Blog',
               'Open Routes.', 'Focus', 'Platform', 'Token'),
    }
    for locale, words in natural_identities.items():
        for source in words:
            if key(source) in strings:
                allowed[locale].add(key(source))
    return {locale: sorted(ids) for locale, ids in allowed.items()}


def english_catalog():
    strings = {}
    for text in sources().values():
        transform(text, collect=strings)
    for text in [NOTICE, LABEL, *SEARCH_TEXT.values()]:
        strings[key(text)] = text
    return {'metadata': {'locale': 'en', 'status': 'source', 'source': 'English sources'}, 'allow_identical': sorted(k for k,v in strings.items() if literal(v)), 'allow_identical_by_locale': identical_translation_allowlists(strings), 'strings': dict(sorted(strings.items()))}


def load(locale):
    def unique(pairs):
        obj = {}
        for k,v in pairs:
            if k in obj:
                raise ValueError(f'Duplicate JSON key: {k}')
            obj[k] = v
        return obj
    return json.loads((CATALOGS / (locale + '.json')).read_text(), object_pairs_hook=unique)


def token_counts(text):
    return Counter(token.rstrip('.,;:!?。،؛') for token in TOKENS.findall(text))


def validate(locale, en=None):
    en = en or load('en')
    cat = load(locale)
    if not isinstance(cat,dict) or not isinstance(cat.get('strings'),dict):
        raise ValueError(f'{locale}: expected a catalog object with a strings object')
    errors = []
    if cat.get('metadata') != {'locale': locale, 'status': 'requires-human-review', 'source': 'machine'}:
        errors.append('metadata must identify locale, requires-human-review and machine')
    translated = cat.get('strings', {})
    if set(translated) != set(en['strings']):
        errors.append(f"missing keys: {sorted(set(en['strings']) - set(translated))}; extra keys: {sorted(set(translated) - set(en['strings']))}")
    for k, text in translated.items():
        if k not in en['strings']:
            continue
        source = en['strings'][k]
        if (source in LITERAL_EXAMPLES or re.fullmatch(r'#{1,6} (?:Inbox|Tasks|Notes)',source)) and text != source:
            errors.append(f'{k}: altered literal tutorial heading/route identifier')
        if not isinstance(text, str) or not text.strip():
            errors.append(f'{k}: expected nonempty string')
            continue
        # Catalogs are plain text, not translator-controlled HTML. Preserve the
        # occasional literal angle-bracket example, including unmatched brackets.
        if (Counter(re.findall(r'<[^>]*>|[<>]', text)) !=
                Counter(re.findall(r'<[^>]*>|[<>]', source))):
            errors.append(f'{k}: altered HTML/code brackets')
        if Counter(re.findall(r'`[^`]*`|\[\[[^\]]*\]\]|\*\*|#{1,6}|[-+] \[[ x]\]',text)) != Counter(re.findall(r'`[^`]*`|\[\[[^\]]*\]\]|\*\*|#{1,6}|[-+] \[[ x]\]',source)):
            errors.append(f'{k}: altered Markdown syntax/code')
        if Counter(c for c in text if c in '{}') != Counter(c for c in source if c in '{}'):
            errors.append(f'{k}: broken placeholder braces')
        if token_counts(text) != token_counts(source):
            errors.append(f'{k}: altered protected name, URL, path or placeholder')
        if text == source and k not in en['allow_identical'] and k not in en.get('allow_identical_by_locale', {}).get(locale, []):
            errors.append(f'{k}: untranslated English: {source[:90]}')
    if errors:
        raise ValueError(locale + ':\n' + '\n'.join(errors))
    return cat


def active_locales():
    # Explicit isolated pilot mode; production never silently drops a locale or
    # substitutes English when a translation is absent.
    pilot = os.environ.get('VOX_WEBSITE_PILOT')
    if pilot:
        if pilot not in LANGUAGES or pilot == 'en':
            raise ValueError('VOX_WEBSITE_PILOT must name a supported non-English locale')
        return ['en', pilot]
    return list(LANGUAGES)


def enhance(text, relative, locale='en', strings=None):
    url = route(relative)
    public = localized(url, locale)
    langs = active_locales()
    strings = strings or load('en')['strings']
    text = re.sub(r'<link[^>]*hreflang=[^>]*>\s*', '', text)
    text = re.sub(r'<nav aria-label="Language">.*?</nav>', '', text, flags=re.S)
    text = transform(text, strings)
    search_attributes = ''.join(f' data-search-{name}="{escape(strings[key(value)], quote=True)}"' for name,value in SEARCH_TEXT.items())
    text = re.sub(r'<html\b[^>]*>', f'<html lang="{locale}" dir="{"rtl" if locale in {"ar", "ur"} else "ltr"}"{search_attributes}>', text, count=1)
    text = re.sub(r'(<link rel="canonical" href=")[^"]*', lambda m: m[1] + HOST + public, text)
    text = re.sub(r'(<meta property="og:url" content=")[^"]*', lambda m: m[1] + HOST + public, text)
    alternates = '\n'.join(f'<link rel="alternate" hreflang="{l}" href="{HOST}{localized(url,l)}">' for l in langs)
    alternates += f'\n<link rel="alternate" hreflang="x-default" href="{HOST}{url}">'
    title = re.search(r'<title>(.*?)</title>', text, re.S)[1]
    description = re.search(r'<meta name="description" content="([^"]*)', text)[1]
    for label, value in [('twitter:title', title), ('twitter:description', description)]:
        if f'name="{label}"' not in text:
            alternates += f'\n<meta name="{label}" content="{value}">'
    text = text.replace('</head>', alternates + '\n</head>')
    switcher = '<details class="language-switcher"><summary>' + escape(strings[key(LABEL)]) + '</summary><ul>' + ''.join(f'<li><a href="{localized(url,l)}" lang="{l}" hreflang="{l}"' + (' aria-current="page"' if l == locale else '') + f'>{name}</a></li>' for l,name in LANGUAGES.items() if l in langs) + '</ul></details>'
    # Keep language controls within the same bounded chrome containers. Adding
    # them after the wrapper creates a full-width second nav row on desktop.
    for closing_tag in ('</nav>', '</footer>'):
        end = text.index(closing_tag)
        container = text.rfind('</div>',0,end)
        opening = text.rfind('<nav' if closing_tag == '</nav>' else '<footer',0,end)
        position = container if container > opening else end
        text = text[:position] + switcher + text[position:]
    if locale != 'en' and Path(relative).name in {'privacy.html', 'terms.html'}:
        text = re.sub(r'(<main\b[^>]*>)', lambda m: m[0] + '<p class="translation-notice">' + escape(strings[key(NOTICE)]) + f' <a href="{url}" lang="en" hreflang="en">English</a></p>', text, count=1)
    # Resolve all local asset and page references against the English page first.
    # Root-relative assets remain shared; only known HTML page routes get prefixes.
    known = {route(r): r for r in sources_paths()}
    known.update({'/' + r: r for r in sources_paths()})
    base = HOST + '/' + relative
    def reference(m):
        name, quote, value = m[1], m[2], unescape(m[3])
        if value.startswith(('#', 'mailto:', 'tel:', 'data:', 'javascript:')):
            return m[0]
        parsed = urlsplit(urljoin(base, value))
        if parsed.netloc != 'vox.isolated.tech':
            return m[0]
        path = parsed.path
        target = known.get(path)
        if target:
            path = localized(route(target), locale)
        suffix = ('?' + parsed.query if parsed.query else '') + ('#' + parsed.fragment if parsed.fragment else '')
        # Do not prefix canonical/alternate/switcher references a second time.
        return name + '=' + quote + escape((HOST if value.startswith(HOST) else '') + path + suffix, quote=True) + quote
    # Rewrite body and shared asset references, not head canonical/hreflang metadata.
    head, body = text.split('</head>', 1)
    class References(HTMLParser):
        def __init__(self, document):
            super().__init__(convert_charrefs=False)
            self.document = document
            self.lines = [0] + [m.end() for m in re.finditer('\n', document)]
            self.edits = []
            self.feed(document)
        def handle_starttag(self, tag, attrs):
            if tag not in {'a', 'img', 'link', 'script', 'source', 'video', 'audio'}:
                return
            raw = self.get_starttag_text()
            line,col = self.getpos()
            start = self.lines[line-1] + col
            rewritten = re.sub(r'\b(href|src)=(\"|\x27)(.*?)\2', reference, raw)
            self.edits.append((start,start+len(raw),rewritten))
        def handle_startendtag(self, tag, attrs):
            self.handle_starttag(tag,attrs)
        def output(self):
            out = self.document
            for start,end,value in reversed(self.edits):
                out = out[:start] + value + out[end:]
            return out
    body = References(body).output()
    # A language link always targets its stated language, never the current locale.
    body = re.sub(r'(<a href=")[^"]*(" lang="([^"]+)" hreflang="[^"]+")', lambda m: m[1] + localized(url,m[3]) + m[2], body)
    # Shared head assets also need absolute paths on nested locale routes.
    head = re.sub(r'\b(href|src)=(\"|\x27)(.*?)\2', lambda m: reference(m) if not m[3].startswith(('https:', '/','#')) else m[0], head)
    def schema(m):
        obj = json.loads(m[1])
        def walk(x):
            if isinstance(x, dict):
                for k,v in list(x.items()):
                    if isinstance(v,str) and v.startswith(HOST) and urlsplit(v).path in known:
                        x[k] = HOST + localized(route(known[urlsplit(v).path]),locale)
                    else:
                        walk(v)
            elif isinstance(x,list):
                for v in x: walk(v)
        walk(obj)
        obj['inLanguage'] = locale
        if 'name' not in obj:
            obj['name'] = unescape(re.search(r'<title>(.*?)</title>', head, re.S)[1])
        if 'description' not in obj:
            obj['description'] = unescape(re.search(r'<meta name="description" content="([^"]*)',head)[1])
        return '<script type="application/ld+json">\n' + json.dumps(obj,ensure_ascii=False,indent=2).replace('<','\\u003c') + '\n</script>'
    if '<script type="application/ld+json">' not in head:
        head += '\n<script type="application/ld+json">' + json.dumps({'@context':'https://schema.org','@type':'WebPage','name':unescape(title),'description':unescape(description),'url':HOST+public},ensure_ascii=False).replace('<','\\u003c') + '</script>\n'
    text = re.sub(r'<script type="application/ld\+json">(.*?)</script>', schema, head + '</head>' + body, flags=re.S)
    from download_links import decorate_html
    # Campaign config uses file paths for extensionless top-level pages.
    campaign_path = localized('/' + (relative[:-10] if relative.endswith('index.html') else relative), locale)
    return decorate_html(text, campaign_path)


def sync_campaigns():
    """Explicit authoring operation; catalog validators never call this."""
    path = ROOT / 'website-content/downloads.json'
    config = json.loads(path.read_text())
    for relative in sources_paths():
        url = '/' + (relative[:-10] if relative.endswith('index.html') else relative)
        for locale in LANGUAGES:
            if locale == 'en':
                continue
            page = localized(url,locale)
            # Content-derived fixed-size campaign names survive title/copy changes.
            config['campaigns'].setdefault(page, 'seo_' + locale.lower().replace('-','_') + '_' + sha256(url.encode()).hexdigest()[:12])
    path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n')


_PATHS = None

def sources_paths():
    global _PATHS
    if _PATHS is None:
        _PATHS = list(sources())
    return _PATHS


def output_files():
    en = english_catalog()
    if load('en') != en:
        raise ValueError('English catalog is stale; run build_locales.py --extract and retranslate changed keys')
    catalogs = {'en': en}
    for locale in active_locales():
        if locale != 'en':
            catalogs[locale] = validate(locale, en)
    output = {}
    for relative, source in sources().items():
        for locale, cat in catalogs.items():
            target = relative if locale == 'en' else locale.lower() + '/' + relative
            output[SITE / target] = enhance(source, relative, locale, cat['strings'])
    ns = 'http://www.sitemaps.org/schemas/sitemap/0.9'
    xn = 'http://www.w3.org/1999/xhtml'
    ET.register_namespace('', ns)
    ET.register_namespace('xhtml', xn)
    tree = ET.Element(f'{{{ns}}}urlset')
    for relative in sources_paths():
        if Path(relative).name == '404.html':
            continue
        url = route(relative)
        for locale in catalogs:
            node = ET.SubElement(tree, f'{{{ns}}}url')
            ET.SubElement(node, f'{{{ns}}}loc').text = HOST + localized(url,locale)
            for l in list(catalogs) + ['x-default']:
                ET.SubElement(node, f'{{{xn}}}link', {'rel':'alternate', 'hreflang':l,'href': HOST + localized(url, 'en' if l == 'x-default' else l)})
    ET.indent(tree)
    output[SITE / 'sitemap.xml'] = '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(tree, encoding='unicode') + '\n'
    llms = (ROOT / 'website-content/llms.txt').read_text().split('\n## Languages\n')[0]
    llms += '\n## Languages\n\n'
    for locale in catalogs:
        llms += f'### {LANGUAGES[locale]} ({locale})\n\n'
        llms += 'Markdown is available through Accept: text/markdown.\n\n'
        for relative in sources_paths():
            if Path(relative).name == '404.html':
                continue
            target = relative if locale == 'en' else locale.lower() + '/' + relative
            title = unescape(re.search(r'<title>(.*?)</title>',output[SITE / target],re.S)[1])
            llms += f'- [{title}]({HOST}{localized(route(relative),locale)})\n'
        llms += '\n'
    output[SITE / 'llms.txt'] = llms.rstrip() + '\n'
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extract', action='store_true')
    parser.add_argument('--sync-campaigns', action='store_true')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--check-catalog', choices=list(LANGUAGES)[1:])
    args = parser.parse_args()
    try:
        if args.check_catalog:
            cat = validate(args.check_catalog)
            print(f"{args.check_catalog} pass {len(cat['strings'])}")
            return
        if args.sync_campaigns:
            sync_campaigns()
            return
        if args.extract:
            CATALOGS.mkdir(parents=True,exist_ok=True)
            (CATALOGS/'en.json').write_text(json.dumps(english_catalog(), ensure_ascii=False, indent=2)+'\n')
            return
        outputs = output_files()
        stale = []
        for locale in LANGUAGES:
            if locale == 'en':
                continue
            directory = SITE / locale.lower()
            for extra in directory.rglob('*.html'):
                if extra not in outputs:
                    stale.append(str(extra.relative_to(ROOT)) + ' (unexpected generated page)')
        if stale and not args.check:
            raise ValueError('Remove obsolete locale pages explicitly before rebuilding:\n' + '\n'.join(stale))
        for target,text in outputs.items():
            if args.check:
                if not target.exists() or target.read_text() != text:
                    stale.append(str(target.relative_to(ROOT)))
            else:
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_text(text)
        if stale:
            raise ValueError('Run npm run website:build; stale locales:\n'+'\n'.join(stale))
        print(f"{'Checked' if args.check else 'Built'} {len(outputs)-2} localized HTML pages")
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error))


if __name__ == '__main__':
    main()
