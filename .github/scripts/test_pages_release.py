import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('check-pages-release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

class ReleaseBoundaryTests(unittest.TestCase):
    def test_only_managed_beacon_is_ignored(self):
        beacon = '<script defer src="https://static.cloudflareinsights.com/beacon.min.js/test"></script>'
        self.assertEqual(release.normalize_html('<main>Body</main>' + beacon), '<main>Body</main>')
        other = '<script src="https://example.org/changed.js"></script>'
        self.assertIn(other, release.normalize_html(other))

    def test_sitemap_cannot_escape_origin_or_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'index.html').write_text('site')
            self.assertEqual(release.local_page(root, 'https://site.test/', 'https://site.test'), root / 'index.html')
            for url in ['https://other.test/', 'https://site.test/../outside', 'https://site.test/?q=secret']:
                with self.subTest(url=url), self.assertRaises(ValueError):
                    release.local_page(root, url, 'https://site.test')

    def test_fresh_deployment_404_is_retried_but_other_errors_are_not(self):
        from urllib.error import HTTPError
        calls = []
        def flaky(url, accept='text/html'):
            calls.append(url)
            if len(calls) < 3:
                raise HTTPError(url, 404, 'Not Found', {}, None)
            return {}, b'ok'
        original_once, original_sleep = release.fetch_once, release.time.sleep
        release.fetch_once, release.time.sleep = flaky, lambda _: None
        try:
            self.assertEqual(release.fetch('https://example.pages.dev/'), ({}, b'ok'))
            self.assertEqual(len(calls), 3)
            def forbidden(url, accept='text/html'):
                raise HTTPError(url, 403, 'Forbidden', {}, None)
            release.fetch_once = forbidden
            with self.assertRaises(HTTPError):
                release.fetch('https://example.pages.dev/')
        finally:
            release.fetch_once, release.time.sleep = original_once, original_sleep

    def test_stale_edge_content_is_retried_then_still_fails(self):
        attempts = []
        def settles():
            attempts.append(1)
            if len(attempts) < 3:
                raise release.StaleContent('old release')
            return 'current'
        original_sleep = release.time.sleep
        release.time.sleep = lambda _: None
        try:
            self.assertEqual(release.until_current(settles), 'current')
            self.assertEqual(len(attempts), 3)
            attempts.clear()
            def never():
                attempts.append(1)
                raise release.StaleContent('old release')
            with self.assertRaises(release.StaleContent):
                release.until_current(never)
            self.assertEqual(len(attempts), len(release.RETRY_DELAYS) + 1)
            def other():
                attempts.append(1)
                raise ValueError('Unexpected canonical')
            attempts.clear()
            with self.assertRaises(ValueError):
                release.until_current(other)
            self.assertEqual(len(attempts), 1)
        finally:
            release.time.sleep = original_sleep

if __name__ == '__main__':
    unittest.main()
