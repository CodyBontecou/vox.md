import json
from pathlib import Path
import tempfile
import unittest

from download_links import decorate_html, destination, load_config


APP_URL = "https://apps.apple.com/us/app/voxboard/id6758967337"


class DownloadLinkTests(unittest.TestCase):
    def setUp(self):
        self.config = {"app_store_url": APP_URL, "verified_campaign_link": None,
                       "qr_campaign": "test_qr", "campaigns": {"/": "test_home"}}

    def validate(self, config):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "downloads.json"
            path.write_text(json.dumps(config))
            return load_config(path)

    def enable_test_provider(self):
        # Synthetic fixture only: production config intentionally has no token.
        self.config["verified_campaign_link"] = APP_URL + "?pt=123456&ct=test_fixture&mt=8"

    def test_missing_provider_keeps_direct_downloads(self):
        self.validate(self.config)
        self.assertEqual(destination(self.config, "test_home"), APP_URL)
        output = decorate_html(f'<a href="{APP_URL}">Get app</a>', "/", self.config)
        self.assertIn(f'href="{APP_URL}"', output)
        self.assertNotIn("?pt=", output)
        self.assertNotIn("?ct=", output)

    def test_provider_and_campaign_are_both_present_when_enabled(self):
        self.enable_test_provider()
        self.validate(self.config)
        output = decorate_html(f'<a href="{APP_URL}">Get app</a>', "/", self.config)
        self.assertIn('pt=123456&amp;ct=test_home&amp;mt=8', output)
        self.assertIn('data-download-campaign="test_home"', output)

    def test_qr_uses_a_separate_campaign_and_rewrite_is_idempotent(self):
        self.enable_test_provider()
        html = f'<a data-download-kind="qr" href="{APP_URL}">QR</a>'
        output = decorate_html(html, "/", self.config)
        self.assertIn("ct=test_qr", output)
        self.assertEqual(decorate_html(output, "/", self.config), output)
        self.assertEqual(output.count("data-download-campaign="), 1)

    def test_review_links_and_foreign_apps_are_not_rewritten(self):
        self.enable_test_provider()
        for url in (APP_URL + "?action=write-review", APP_URL.replace("6758967337", "123"),
                    APP_URL.replace("apps.apple.com", "example.com")):
            html = f'<a href="{url}">Link</a>'
            self.assertEqual(decorate_html(html, "/", self.config), html)

    def test_missing_page_campaign_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "campaign mapping"):
            decorate_html(f'<a href="{APP_URL}">Get app</a>', "/new-page/", self.config)

    def test_wrong_app_or_incomplete_provider_link_is_rejected(self):
        for link in (APP_URL + "?ct=only", APP_URL + "?pt=123&ct=test&mt=8&pt=456",
                     APP_URL.replace("6758967337", "123") + "?pt=123&ct=test&mt=8"):
            config = dict(self.config, verified_campaign_link=link)
            with self.assertRaises(ValueError):
                self.validate(config)

    def test_campaign_names_are_unique_and_within_apples_length_limit(self):
        for campaigns in ({"/": "x" * 31}, {"/": "test_qr"}):
            with self.assertRaises(ValueError):
                self.validate(dict(self.config, campaigns=campaigns))


if __name__ == "__main__":
    unittest.main()
