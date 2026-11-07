import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from website_markdown import MarkdownDocument


class WebsiteMarkdownTests(unittest.TestCase):
    def render(self, html):
        document = MarkdownDocument('https://vox.isolated.tech/docs/')
        document.feed(html)
        return document.markdown()

    def test_main_content_excludes_navigation_and_executable_content(self):
        text = self.render('<nav>Menu</nav><main><h1>Guide</h1><script>secret()</script><svg><path /></svg><p>Useful text</p></main><footer>Footer</footer>')
        self.assertEqual(text, '# Guide\n\nUseful text\n')

    def test_accessible_heading_replaces_visual_fragments_once(self):
        text = self.render('<main><h1 aria-label="Tus ideas, en un archivo local.">Tus ideas, en un <span aria-hidden="true">nube</span><span>local </span><strong>archivo.</strong></h1><p>Después.</p></main>')
        self.assertEqual(text, '# Tus ideas, en un archivo local.\n\nDespués.\n')

    def test_links_and_images_resolve_relative_to_the_original_page(self):
        text = self.render('<main><h2>Help</h2><p>Read <a href="../contact">support</a>.</p><img src="example.webp" alt="Example"></main>')
        self.assertIn('[support](https://vox.isolated.tech/contact)', text)
        self.assertIn('![Example](https://vox.isolated.tech/docs/example.webp)', text)

    def test_lists_emphasis_and_code_remain_readable(self):
        text = self.render('<main><ul><li><strong>Route</strong> to <code>Inbox.md</code></li><li>Capture</li></ul><pre><code>one\n  two</code></pre></main>')
        self.assertIn('- **Route** to `Inbox.md`', text)
        self.assertIn('- Capture', text)
        self.assertIn('```\none\n  two\n```', text)

    def test_build_embeds_shared_styles_and_generates_document_routes(self):
        spec = importlib.util.spec_from_file_location('build_website', SCRIPTS / 'build-website.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'site'
            module.build(output)
            html = (output / 'index.html').read_text()
            self.assertEqual(html.count('class="language-switcher"'), 2)
            self.assertIn('href="/ja/" lang="ja"', html)
            self.assertNotIn('href="ja/"', html)
            self.assertIn('<style data-source="geist.css">', html)
            self.assertNotIn('<link rel="stylesheet"', html)
            self.assertIn('Capture ideas into Obsidian', (output / 'index.md').read_text())
            guide = (output / 'blog/obsidian-daily-note-iphone/index.md').read_text()
            # The Signal article layout keeps the guide heading inside <main>.
            self.assertIn('# Capture into an Obsidian daily note from iPhone', guide)
            self.assertIn('Book dentist appointment', guide)
            self.assertIn('https://vox.isolated.tech/docs/', (output / '404.md').read_text())
            worker = (output / '_worker.js').read_text()
            self.assertNotIn('/* @generated-markdown-routes */', worker)
            self.assertIn('"/docs/": "/docs/index.md"', worker)
            self.assertIn('"/contact": "/contact.md"', worker)
            locale = (output / 'ja/index.html').read_text()
            self.assertIn('https://vox.isolated.tech/ja/', locale)
            self.assertIn('<style data-source="geist.css">', locale)
            self.assertIn('<html lang="ja" dir="ltr"', locale)
            self.assertIn('data-download-campaign=', locale)
            self.assertIn('https://apps.apple.com/us/app/voxboard/id6758967337', (output / 'ja/index.md').read_text())
            self.assertIn('Obsidian', (output / 'ja/index.md').read_text())
            self.assertIn('"/ja/": "/ja/index.md"', worker)
            public = json.loads(worker.split('const publicData = ',1)[1].split(';\n',1)[0])
            self.assertEqual(len(public['documents']),len(list(output.rglob('*.html'))) - len(list(output.rglob('404.html'))))
            documents = {item['url']:item for item in public['documents']}
            self.assertEqual(documents['https://vox.isolated.tech/ja/docs/']['inLanguage'],'ja')
            self.assertEqual(documents['https://vox.isolated.tech/ja/privacy.html']['markdownUrl'],'https://vox.isolated.tech/ja/privacy.html')
            self.assertNotIn('https://vox.isolated.tech/ja/404',documents)
            self.assertIn('"/ja/privacy.html": "/ja/privacy.md"',worker)


if __name__ == '__main__':
    unittest.main()
