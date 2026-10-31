import importlib.util
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
            self.assertIn('<style data-source="geist.css">', html)
            self.assertNotIn('<link rel="stylesheet"', html)
            self.assertIn('Capture ideas into Obsidian', (output / 'index.md').read_text())
            guide = (output / 'blog/obsidian-daily-note-iphone/index.md').read_text()
            self.assertTrue(guide.startswith('# Capture into an Obsidian Daily Note from iPhone'))
            self.assertIn('Book dentist appointment', guide)
            self.assertIn('https://vox.isolated.tech/docs/', (output / '404.md').read_text())
            worker = (output / '_worker.js').read_text()
            self.assertNotIn('/* @generated-markdown-routes */', worker)
            self.assertIn('"/docs/": "/docs/index.md"', worker)
            self.assertIn('"/contact": "/contact.md"', worker)
            locale = (output / 'zh-hans/index.html').read_text()
            self.assertIn('<style>', locale)
            self.assertIn('lang="zh-Hans"', locale)
            self.assertIn('Vox.md', (output / 'zh-hans/index.md').read_text())
            self.assertIn('"/zh-hans/": "/zh-hans/index.md"', worker)


if __name__ == '__main__':
    unittest.main()
