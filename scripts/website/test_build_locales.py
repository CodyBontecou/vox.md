"""Localization contracts; fixtures never write generated website files."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_locales as locales


class ExtractionTests(unittest.TestCase):
    def test_entities_are_one_segment_and_offsets_are_lossless(self):
        source = '<main><p title="A &amp; B">Text &amp; more &#123;location&#125;.</p><p>After.</p></main>'
        strings = {}
        locales.transform(source, collect=strings)
        self.assertEqual(set(strings.values()), {'A & B', 'Text & more {location}.', 'After.'})
        translated = {k: '訳 ' + v for k,v in strings.items()}
        html = locales.transform(source, translated)
        self.assertIn('title="訳 A &amp; B"',html)
        self.assertIn('訳 Text &amp; more {location}.',html)
        self.assertIn('<p>訳 After.</p>',html)

    def test_sample_code_scripts_styles_and_svg_are_not_translated(self):
        source = '<main><pre><code>GET /api/v1/product\n{location}</code></pre><script>const thing = "English";</script><style>.label {content:"English"}</style><svg><text>English</text></svg><p>Actual prose</p></main>'
        strings = {}
        locales.transform(source, collect=strings)
        self.assertEqual(list(strings.values()), ['Actual prose'])
        output = locales.transform(source, {locales.key('Actual prose'): '実際の文章'})
        self.assertEqual(output,source.replace('Actual prose','実際の文章'))

    def test_schema_text_is_translated_but_schema_identifiers_are_literal(self):
        source = '<script type="application/ld+json">' + json.dumps({'@type':'Article','name':'A title','description':'A description','url':'https://example.com','featureList':['First feature']}) + '</script>'
        strings = {}
        locales.transform(source, collect=strings)
        self.assertEqual(set(strings.values()), {'A title','A description','First feature'})
        html = locales.transform(source,{k:'訳 ' + v for k,v in strings.items()})
        self.assertIn('"@type": "Article"', html)
        self.assertIn('"url": "https://example.com"', html)
        self.assertIn('"name": "訳 A title"', html)

    def test_prose_slashes_are_not_mistaken_for_file_paths(self):
        self.assertEqual(locales.token_counts('format/mode and append/prepend'), {})
        self.assertEqual(locales.token_counts('Inbox/{date}.md and /api/v1/product'), {'Inbox/{date}.md': 1, '/api/v1/product': 1})
        self.assertEqual(locales.token_counts('https://example.com/help。次へ'), {'https://example.com/help': 1})
        self.assertFalse(locales.literal('Contact Vox.md'))
        self.assertTrue(locales.literal('Journal/Pages/2026-11-06 0912.md'))

    def test_ids_do_not_depend_on_order(self):
        a,b = {},{}
        locales.transform('<p>One</p><p>Two</p>',collect=a)
        locales.transform('<p>Two</p><p>One</p>',collect=b)
        self.assertEqual(a,b)

    def test_site_language_set_matches_both_shipped_apps(self):
        ios = json.loads((locales.ROOT/'Voxboard/Localizable.xcstrings').read_text())
        ios_languages = {language for unit in ios['strings'].values() for language in unit.get('localizations',{})}
        self.assertEqual(set(locales.LANGUAGES),ios_languages)
        resource_names = {'ar':'ar','bn':'bn','de':'de','es':'es','fr':'fr','hi':'hi','id':'b+id','it':'it','ja':'ja','ko':'ko','nl':'nl','pl':'pl','pt-BR':'pt-rBR','ru':'ru','ta':'ta','th':'th','tr':'tr','uk':'uk','ur':'ur','vi':'vi','zh-Hans':'b+zh+Hans','zh-Hant':'b+zh+Hant'}
        resources = locales.ROOT/'apps/android/app/src/main/res'
        actual = {p.name for p in resources.glob('values-*') if (p/'strings.xml').exists()}
        self.assertEqual(actual,{'values-'+r for r in resource_names.values()})
        self.assertEqual(set(locales.LANGUAGES),{'en',*resource_names})

    def test_app_identity_allowances_are_locale_specific_and_label_bounded(self):
        label = 'Quick Record'
        prose = 'This is a long untranslated help paragraph that must never gain a website translation exception from an app fallback.'
        strings = {locales.key(s):s for s in (label,prose,'Unfinished')}
        app = {'strings': {
            label: {'localizations': {'de': {'stringUnit': {'state':'translated','value':label}}, 'ja': {'stringUnit': {'state':'translated','value':'速記録'}}}},
            prose: {'localizations': {'de': {'stringUnit': {'state':'translated','value':prose}}}},
            'Unfinished': {'localizations': {'de': {'stringUnit': {'state':'new','value':'Unfinished'}}}}
        }}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'Voxboard').mkdir()
            (root/'Voxboard/Localizable.xcstrings').write_text(json.dumps(app))
            with patch.object(locales,'ROOT',root):
                allowed = locales.identical_translation_allowlists(strings)
        self.assertIn(locales.key(label),allowed['de'])
        self.assertNotIn(locales.key(label),allowed['ja'])
        self.assertNotIn(locales.key(prose),allowed['de'])
        self.assertNotIn(locales.key('Unfinished'),allowed['de'])

    def test_source_catalog_covers_all_english_pages(self):
        sources = locales.sources()
        self.assertEqual(len(sources),22)
        self.assertIn('blog/transcribe-voice-memos-iphone/index.html',sources)
        self.assertIn('docs/location/index.html',sources)
        self.assertNotIn('zh-hans/index.html',sources)
        self.assertEqual(locales.english_catalog(),locales.load('en'))


class CatalogValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.patch = patch.object(locales,'CATALOGS',self.path)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.source = 'Use Vox.md with Markdown and {location}; see https://example.com/help and Inbox/{date}.md.'
        self.ident = locales.key(self.source)
        self.en = {'strings':{self.ident:self.source}, 'allow_identical':[]}
        self.cat = {'metadata': {'locale':'ja','status':'requires-human-review','source':'machine'}, 'strings':{self.ident:'Vox.md で Markdown と {location} を使用。https://example.com/help と Inbox/{date}.md を参照。'}}
        (self.path/'en.json').write_text(json.dumps(self.en))

    def save(self):
        target = self.path/'ja.json'
        target.write_text(json.dumps(self.cat,ensure_ascii=False))
        return target

    def test_valid_catalog_does_not_write_any_file(self):
        self.save()
        before = {p:p.read_bytes() for p in self.path.iterdir()}
        self.assertEqual(locales.validate('ja'),self.cat)
        self.assertEqual(before,{p:p.read_bytes() for p in self.path.iterdir()})

    def test_missing_and_extra_keys_are_rejected(self):
        self.cat['strings'] = {'extra':'訳'}
        self.save()
        with self.assertRaisesRegex(ValueError,'missing keys:.*extra keys:'):
            locales.validate('ja')

    def test_protected_names_placeholders_urls_and_paths_are_rejected(self):
        for old,new in [('Vox.md','ボックス'),('Markdown','マークダウン'),('{location}','{場所}'),('https://example.com/help','https://example.com/ja/help'),('Inbox/{date}.md','受信箱/{date}.md')]:
            with self.subTest(token=old):
                self.cat['strings'][self.ident] = '訳 ' + self.source.replace(old,new)
                self.save()
                with self.assertRaisesRegex(ValueError,'altered protected'):
                    locales.validate('ja')

    def test_altered_model_names_and_keyboard_shortcuts_are_rejected(self):
        self.source += ' Press Control-B with Whisper Small.'
        self.en['strings'][self.ident] = self.source
        (self.path/'en.json').write_text(json.dumps(self.en))
        for old,new in [('Control-B','Control-X'),('Whisper Small','Whisper 小型')]:
            with self.subTest(token=old):
                self.cat['strings'][self.ident] = '訳 ' + self.source.replace(old,new)
                self.save()
                with self.assertRaisesRegex(ValueError,'altered protected'):
                    locales.validate('ja')

    def test_html_injection_is_rejected(self):
        for injection in ['<img src=x>', '<script', '>']:
            with self.subTest(injection=injection):
                self.cat['strings'][self.ident] = '訳 ' + self.source + injection
                self.save()
                with self.assertRaisesRegex(ValueError,'altered HTML'):
                    locales.validate('ja')

    def test_identical_english_is_rejected_except_explicit_source_allowlist(self):
        self.cat['strings'][self.ident] = self.source
        self.save()
        with self.assertRaisesRegex(ValueError,'untranslated English'):
            locales.validate('ja')
        self.en['allow_identical'] = [self.ident]
        locales.validate('ja',self.en)

    def test_one_locales_identity_allowance_does_not_allow_anothers_english(self):
        self.cat['strings'][self.ident] = self.source
        self.save()
        self.en['allow_identical_by_locale'] = {'de':[self.ident]}
        with self.assertRaisesRegex(ValueError,'untranslated English'):
            locales.validate('ja',self.en)
        self.en['allow_identical_by_locale']['ja'] = [self.ident]
        locales.validate('ja',self.en)

    def test_review_claims_invalid_json_and_duplicates_are_rejected(self):
        self.cat['metadata']['status'] = 'reviewed'
        self.save()
        with self.assertRaisesRegex(ValueError,'metadata'):
            locales.validate('ja')
        (self.path/'ja.json').write_text('{bad json')
        with self.assertRaises(ValueError):
            locales.validate('ja')
        (self.path/'ja.json').write_text('{"strings":{},"strings":{}}')
        with self.assertRaisesRegex(ValueError,'Duplicate JSON key'):
            locales.validate('ja')


class RenderingTests(unittest.TestCase):
    def test_url_scheme_preserves_legal_canonicals_and_lowercases_prefixes(self):
        self.assertEqual(locales.localized(locales.route('blog/guide/index.html'),'pt-BR'),'/pt-br/blog/guide/')
        self.assertEqual(locales.localized(locales.route('privacy.html'),'zh-Hant'),'/zh-hant/privacy.html')
        self.assertEqual(locales.localized(locales.route('contact.html'),'ar'),'/ar/contact')

    def test_rtl_links_metadata_switchers_and_literal_samples(self):
        source = '<html lang="en"><head><title>Page</title><meta name="description" content="Description"><link rel="canonical" href="https://vox.isolated.tech/docs/"><meta property="og:url" content="https://vox.isolated.tech/docs/"><link rel="stylesheet" href="../geist.css"><script type="application/ld+json">{"@type":"WebPage","name":"Page","description":"Description","url":"https://vox.isolated.tech/docs/"}</script></head><body><nav><a href="../contact.html">Contact</a></nav><main><h1>Page</h1><img src="../screenshots/photo.png" alt="Photo"><pre><code>&lt;a href="../contact.html"&gt;literal&lt;/a&gt;</code></pre></main><footer>Footer</footer></body></html>'
        strings = {}
        locales.transform(source,collect=strings)
        strings = {k:'ترجمة ' + v for k,v in strings.items()}
        strings[locales.key(locales.LABEL)] = 'اللغة'
        strings.update({locales.key(value):'ترجمة ' + value for value in locales.SEARCH_TEXT.values()})
        with patch.object(locales,'active_locales',return_value=['en','ar','ja']), patch('download_links.decorate_html',side_effect=lambda text,path:text):
            html = locales.enhance(source,'docs/index.html','ar',strings)
        self.assertIn('<html lang="ar" dir="rtl"',html)
        self.assertIn('href="https://vox.isolated.tech/ar/docs/"',html)
        self.assertIn('href="/ar/contact"',html)
        self.assertIn('src="/screenshots/photo.png"',html)
        self.assertIn('href="/geist.css"',html)
        self.assertIn('hreflang="ja" href="https://vox.isolated.tech/ja/docs/"',html)
        self.assertIn('hreflang="x-default" href="https://vox.isolated.tech/docs/"',html)
        self.assertEqual(html.count('class="language-switcher"'),2)
        self.assertIn('href="/ja/docs/" lang="ja" hreflang="ja"',html)
        self.assertIn('"inLanguage": "ar"',html)
        self.assertIn('&lt;a href="../contact.html"&gt;literal&lt;/a&gt;',html)
        self.assertIn('name="twitter:title" content="ترجمة Page"',html)

    def test_full_site_render_uses_validated_catalogs_without_writing_site(self):
        # Deliberately synthetic test strings, never saved as a real translation.
        originals = locales.sources()
        en = locales.english_catalog()
        translated = {k: v if k in en['allow_identical'] else v + ' 訳' for k,v in en['strings'].items()}
        languages = list(locales.LANGUAGES)
        config = {'app_store_url':'https://apps.apple.com/us/app/voxboard/id6758967337', 'verified_campaign_link': None, 'qr_campaign':'test_qr','campaigns':{}}
        for r in originals:
            for l in languages:
                p = locales.localized('/' + (r[:-10] if r.endswith('index.html') else r),l)
                config['campaigns'][p] = 'test_' + locales.sha256(p.encode()).hexdigest()[:16]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'en.json').write_text(json.dumps(en,ensure_ascii=False))
            for language in languages:
                if language != 'en':
                    catalog = {'metadata': {'locale':language,'status':'requires-human-review','source':'machine'}, 'strings': translated}
                    (root/(language+'.json')).write_text(json.dumps(catalog,ensure_ascii=False))
            site = root/'website'
            with patch.object(locales,'CATALOGS',root), patch.object(locales,'SITE',site), patch.object(locales,'sources',return_value=originals), patch.object(locales,'_PATHS',list(originals)), patch.object(locales,'active_locales',return_value=languages), patch('download_links.load_config',return_value=config):
                outputs = locales.output_files()
            self.assertEqual(len(outputs),508)
            self.assertFalse(site.exists())
            from check_site import Page
            canonical_pages = {}
            for target,html in outputs.items():
                if target.suffix != '.html':
                    continue
                with self.subTest(page=target):
                    self.assertEqual(html.count('class="language-switcher"'),2)
                    self.assertEqual(html.count('hreflang="x-default"'),1)
                    relative = target.relative_to(site)
                    language = next((l for l in languages if l != 'en' and relative.parts[0] == l.lower()),'en')
                    english_path = Path(*relative.parts[1:]) if language != 'en' else relative
                    public = locales.HOST + locales.localized(locales.route(english_path),language)
                    expected_alternates = [(l,locales.HOST+locales.localized(locales.route(english_path),l)) for l in languages]
                    expected_alternates.append(('x-default',locales.HOST+locales.route(english_path)))
                    with patch.object(Path,'read_text',return_value=html):
                        page = Page(target)
                    self.assertEqual(page.languages,[language])
                    self.assertEqual(page.direction,'rtl' if language in {'ar','ur'} else 'ltr')
                    self.assertEqual(page.canonicals,[public])
                    self.assertEqual(sorted(page.alternates),sorted(expected_alternates))
                    self.assertEqual(page.counts['h1'],1)
                    self.assertEqual(page.counts['main'],1)
                    self.assertTrue(page.schema)
                    canonical_pages[public] = (target,page)
                    self.assertIn('name="twitter:description"',html)
                    self.assertEqual(html.count('rel="canonical"'),1)
                    self.assertNotIn('href="../geist.css"',html)
                    # Every embedded schema remains valid JSON after localization.
                    import re
                    for block in re.findall(r'<script type="application/ld\+json">(.*?)</script>',html,re.S):
                        schema = json.loads(block)
                        self.assertEqual(schema['inLanguage'],language)
                        self.assertTrue(schema['name'])
                        self.assertTrue(schema['description'])
            import xml.etree.ElementTree as ET
            sitemap = ET.fromstring(outputs[site/'sitemap.xml'])
            submitted = []
            for entry in sitemap:
                url = entry.find('{*}loc').text
                submitted.append(url)
                self.assertIn(url,canonical_pages)
                target,page = canonical_pages[url]
                self.assertNotEqual(target.name,'404.html')
                actual = [(a.get('hreflang'),a.get('href')) for a in entry.findall('{http://www.w3.org/1999/xhtml}link')]
                self.assertEqual(sorted(actual),sorted(page.alternates))
                self.assertIn(url,outputs[site/'llms.txt'])
            self.assertEqual(len(submitted),483)
            self.assertEqual(set(submitted),{url for url,(target,_) in canonical_pages.items() if target.name != '404.html'})
            self.assertEqual(len(submitted),len(set(submitted)))

    def test_check_rejects_stale_generated_output_without_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            site = root/'website'
            site.mkdir()
            target = site/'index.html'
            target.write_text('current')
            with patch.object(locales,'ROOT',root), patch.object(locales,'SITE',site), patch.object(locales,'output_files',return_value={target:'current'}), patch('sys.argv',['build_locales.py','--check']), contextlib.redirect_stdout(io.StringIO()):
                locales.main()
                self.assertEqual(target.read_text(),'current')
                target.write_text('stale')
                with self.assertRaisesRegex(SystemExit,'stale locales'):
                    locales.main()
                self.assertEqual(target.read_text(),'stale')

    def test_production_language_set_never_depends_on_catalog_presence(self):
        with patch.dict('os.environ',{},clear=True):
            self.assertEqual(len(locales.active_locales()),23)
        with patch.dict('os.environ',{'VOX_WEBSITE_PILOT':'ja'}):
            self.assertEqual(locales.active_locales(),['en','ja'])


if __name__ == '__main__':
    unittest.main()
