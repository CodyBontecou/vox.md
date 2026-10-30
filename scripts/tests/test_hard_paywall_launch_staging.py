import hashlib
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('launch_stage', ROOT / 'scripts/stage-hard-paywall-website.py')
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class WebsiteStagingTests(unittest.TestCase):
    def test_replace_requires_exactly_one_match(self):
        self.assertEqual(stage.replace_once('old', 'old', 'new'), 'new')
        for text in ('absent', 'old old'):
            with self.assertRaises(AssertionError):
                stage.replace_once(text, 'old', 'new')

    def test_stages_without_modifying_deployable_source(self):
        names = ('index.html', 'docs/index.html', 'llms.txt', 'terms.html', 'privacy.html')
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'website'
            output = Path(temp) / 'staged'
            for name in names:
                dest = source / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / 'website' / name, dest)
            output.mkdir(parents=True)
            shutil.copyfile(ROOT / 'docs/launch/hard-paywall/privacy-policy-proposed.html', output / 'privacy-policy-proposed.html')
            before = {n: hashlib.sha256((source / n).read_bytes()).hexdigest() for n in names}
            with patch.object(stage, 'SOURCE', source), patch.object(stage, 'OUT', output):
                stage.main()
            self.assertEqual(before, {n: hashlib.sha256((source / n).read_bytes()).hexdigest() for n in names})
            for name in names:
                text = (output / 'website-staged' / name).read_text()
                self.assertNotIn('$89.99', text, 'Do not prematurely advertise the later Family lifetime increase')
                self.assertNotIn('15 minutes of transcription', text)
                self.assertNotIn('15-minute free transcription allowance', text)
                self.assertNotIn('starts a fresh free allowance', text)
            docs = (output / 'website-staged/docs/index.html').read_text()
            self.assertIn('Viewing', (output / 'website-staged/terms.html').read_text())
            self.assertIn('Cancel a trial at least 24 hours', docs)
            self.assertIn('Existing lifetime purchases remain valid', docs)
            self.assertIn('History clock button', docs)
            privacy = (output / 'website-staged/privacy.html').read_text()
            self.assertIn('pseudonymous', privacy)
            self.assertIn('does not collect custom usage analytics', privacy)
            self.assertNotIn('Production builds send', privacy)
            self.assertNotIn('An anonymous Vox.md install ID', privacy)
            self.assertNotIn('resets the free usage allowance', privacy)
            self.assertTrue((output / 'website.patch').exists())

    def test_in_app_slider_has_no_transition_entry(self):
        text = (ROOT / 'Voxboard/ReleaseNotes.swift').read_text()
        self.assertNotIn('version: "2.14"', text)
        self.assertNotIn('bontecou.Voxboard.individual.weekly', text)


if __name__ == '__main__':
    unittest.main()
