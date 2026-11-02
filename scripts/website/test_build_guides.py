import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from build_guides import render


class GuideRoutingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.source = Path(self.directory.name) / "capture-options.html"
        self.metadata = {
            "slug": "capture-options", "title": 'Capture & "notes"',
            "description": "Choose a route", "image": "/app-icon.png",
            "published": "2026-10-26", "modified": "2026-10-26",
        }

    def render_source(self, **overrides):
        metadata = dict(self.metadata, **overrides)
        self.source.write_text("<!--" + json.dumps(metadata) + "-->\n<p>__TITLE__ stays literal in article text.</p>")
        config = {"app_store_url": "https://apps.apple.com/us/app/voxboard/id6758967337",
                  "verified_campaign_link": None, "qr_campaign": "test_qr",
                  "campaigns": {"/blog/capture-options/": "test_blog", "/compare/capture-options/": "test_compare"}}
        with patch("download_links.load_config", return_value=config):
            return render(self.source, "__TITLE__\n__URL__\n__BODY__\n__SCHEMA__")

    def test_default_blog_route_escapes_metadata_without_reinterpreting_body(self):
        target, output = self.render_source()
        self.assertEqual(target.parts[-3:], ("blog", "capture-options", "index.html"))
        self.assertIn("Capture &amp; &quot;notes&quot;", output)
        self.assertIn("<p>__TITLE__ stays literal in article text.</p>", output)
        self.assertIn('"@type": "BlogPosting"', output)

    def test_comparison_uses_its_own_canonical_schema_and_breadcrumb(self):
        target, output = self.render_source(section="compare")
        self.assertEqual(target.parts[-3:], ("compare", "capture-options", "index.html"))
        self.assertIn("https://vox.isolated.tech/compare/capture-options/", output)
        self.assertIn('"@type": "Article"', output)
        self.assertIn('"name": "Comparisons"', output)
        self.assertIn('"item": "https://vox.isolated.tech/compare/"', output)
        self.assertNotIn('"@type": "BlogPosting"', output)

    def test_unknown_section_cannot_write_outside_supported_routes(self):
        with self.assertRaisesRegex(ValueError, "Invalid guide section"):
            self.render_source(section="../docs")

    def test_metadata_slug_must_match_source_filename(self):
        with self.assertRaisesRegex(ValueError, "Invalid guide slug"):
            self.render_source(slug="another-slug")

    def test_review_date_cannot_precede_publication(self):
        with self.assertRaisesRegex(ValueError, "Modified date precedes publication"):
            self.render_source(modified="2026-10-25")


if __name__ == "__main__":
    unittest.main()
