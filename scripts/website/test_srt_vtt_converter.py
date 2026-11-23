"""Logic tests for the in-browser SRT and VTT converter (synthetic sample files only)."""
from pathlib import Path
import re
import shutil
import subprocess
import unittest

GUIDE = Path(__file__).resolve().parents[2]/'website-content/guides/srt-vtt-to-text-markdown.html'

HARNESS = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(process.argv[1], 'utf8');
const source = /<script>([\s\S]*)<\/script>/.exec(html)[1];
const window = {};
vm.runInNewContext(source, {window, document: {getElementById() { return null; }}});
const api = window.voxSubtitles;
const conv = (text, o) => api.convert(text, o || {});
const out = (text, o) => { const r = conv(text, o); assert.ok(r.ok, JSON.stringify(r)); return r.output; };

// SRT with a BOM and CRLF, real-world shaped.
const srt = '﻿1\r\n00:00:01,000 --> 00:00:03,500\r\nHello and welcome.\r\n\r\n2\r\n00:00:03,600 --> 00:00:06,000\r\nThis is the <i>second</i> line,\r\nacross two lines.\r\n\r\n3\r\n00:00:12,000 --> 00:00:14,000\r\nAfter a pause.\r\n';
let p = api.parse(srt);
assert.equal(p.format, 'srt');
assert.equal(p.cues.length, 3);
assert.equal(p.cues[1].start, 3600);
assert.equal(p.cues[1].end, 6000);
assert.equal(out(srt, {output: 'text'}), 'Hello and welcome. This is the second line, across two lines.\n\nAfter a pause.\n');
assert.equal(out(srt, {output: 'text', gap: 0}), 'Hello and welcome. This is the second line, across two lines. After a pause.\n');
assert.equal(out(srt, {output: 'text', merge: false}), 'Hello and welcome.\nThis is the second line,\nacross two lines.\nAfter a pause.\n');
assert.equal(out(srt, {output: 'text', timestamps: true}), '[00:01] Hello and welcome. This is the second line, across two lines.\n\n[00:12] After a pause.\n');

// SRT -> VTT -> SRT round trip keeps text and timings.
const vttFromSrt = out(srt, {output: 'vtt', strip: false});
assert.equal(vttFromSrt, 'WEBVTT\n\n00:00:01.000 --> 00:00:03.500\nHello and welcome.\n\n00:00:03.600 --> 00:00:06.000\nThis is the <i>second</i> line,\nacross two lines.\n\n00:00:12.000 --> 00:00:14.000\nAfter a pause.\n');
const back = out(vttFromSrt, {output: 'srt', strip: false});
assert.equal(back, srt.replace(/^﻿/, '').replace(/\r\n/g, '\n').replace(/\n$/, '') + '\n');

// No index lines, no blank line at the end, short VTT timestamps, no hours.
const noIndex = '00:01.000 --> 00:02.500\nShort stamps.\n\n01:02:03.004 --> 01:02:05.000\nWith hours.';
p = api.parse(noIndex);
assert.equal(p.format, 'vtt');
assert.equal(p.cues[0].start, 1000);
assert.equal(p.cues[1].start, 3723004);
assert.ok(out(noIndex, {output: 'srt'}).startsWith('1\n00:00:01,000 --> 00:00:02,500\nShort stamps.\n\n2\n01:02:03,004 --> 01:02:05,000\nWith hours.'));
assert.equal(out(noIndex, {output: 'text', timestamps: true}).split('\n')[0], '[00:01] Short stamps.');
assert.ok(out(noIndex, {output: 'text', timestamps: true, gap: 0}).indexOf('[00:01]') === 0);

// VTT with NOTE, STYLE, REGION, identifiers, cue settings and voice tags.
const vtt = api.sample;
p = api.parse(vtt);
assert.equal(p.format, 'vtt');
assert.equal(p.cues.length, 6);
assert.equal(p.cues[0].settings, 'align:start position:10%');
assert.equal(out(vtt, {output: 'text'}),
  'Host: Welcome, everyone. Today we are planning the spring newsletter.\n\nGuest: I can draft the intro by Friday. [Music]\n\nHost: Great. Please share it in the team notes.\n\nGuest: Will do.\n');
assert.equal(out(vtt, {output: 'text', dropSound: true}).includes('[Music]'), false);
const md = out(vtt, {output: 'md', timestamps: true, dropSound: true, title: 'Team sync', date: '2026-11-23', source: 'Invented', properties: true});
assert.equal(md, '---\ntitle: Team sync\ndate: 2026-11-23\nsource: Invented\ntags:\n  - transcript\n---\n\n# Team sync\n\n' +
  '[00:01] **Host:** Welcome, everyone. Today we are planning the spring newsletter.\n\n[00:07] **Guest:** I can draft the intro by Friday.\n\n[00:15] **Host:** Great. Please share it in the team notes.\n\n[00:19] **Guest:** Will do.\n');
assert.equal(out(vtt, {output: 'md', heading: false, names: false, dropSound: true}).startsWith('Welcome, everyone.'), true);
// Merged turns: gap rule splits the paragraph inside one speaker's turn.
assert.equal(out(vtt, {output: 'md', dropSound: true, gap: 1, heading: false}).split('\n\n')[0], '**Host:** Welcome, everyone. Today we are planning the spring newsletter.');
// VTT -> SRT: header, NOTE, settings dropped; renumbered; voice becomes a prefix.
const toSrt = out(vtt, {output: 'srt'});
assert.ok(toSrt.startsWith('1\n00:00:01,000 --> 00:00:04,200\nHost: Welcome, everyone. Today we are planning\n\n2\n00:00:04,200 --> 00:00:06,500\n'));
assert.equal(/WEBVTT|NOTE|align:|<v/.test(toSrt), false);
assert.ok(toSrt.includes('Guest: I can draft the intro by Friday.'));
// VTT -> VTT keeps settings, ids and voices when tags are kept.
const keep = out(vtt, {output: 'vtt', strip: false});
assert.ok(keep.includes('1\n00:00:01.000 --> 00:00:04.200 align:start position:10%\n<v Host>Welcome, everyone. Today we are planning</v>'));
assert.ok(keep.includes('<i>intro</i>'));
assert.equal(keep.includes('NOTE'), false);

// Name: prefixes, with at least two matching lines.
const prefixed = '00:00:01.000 --> 00:00:02.000\nJane Doe: Hi there.\n\n00:00:02.000 --> 00:00:03.000\nJane Doe: How are you?\n\n00:00:03.500 --> 00:00:04.000\nSam: Fine.';
assert.equal(out(prefixed, {output: 'md', heading: false}), '**Jane Doe:** Hi there. How are you?\n\n**Sam:** Fine.\n');
assert.equal(out(prefixed, {output: 'md', heading: false, prefix: false}), 'Jane Doe: Hi there. Jane Doe: How are you? Sam: Fine.\n');
assert.equal(out('00:00:01.000 --> 00:00:02.000\nNote: one only.\n', {output: 'text'}), 'Note: one only.\n');

// Rolling auto-captions.
const rolling = '00:00:01.000 --> 00:00:03.000\nfirst line\n\n00:00:03.000 --> 00:00:03.010\nfirst line\n\n00:00:03.010 --> 00:00:05.000\nfirst line\nsecond line\n\n00:00:05.000 --> 00:00:05.010\nsecond line\n\n00:00:05.010 --> 00:00:07.000\nsecond line\nthird line\n';
assert.equal(out(rolling, {output: 'text', merge: false, dedupe: true}), 'first line\nsecond line\nthird line\n');
assert.equal(out(rolling, {output: 'text', merge: false}).split('\n').length, 8);
assert.ok(out(rolling, {output: 'srt', dedupe: true}).startsWith('1\n00:00:01,000 --> 00:00:03,010\nfirst line\n\n2\n00:00:03,010 --> 00:00:05,010\nsecond line'));

// Sound cues and inline tags.
const sound = '00:00:01.000 --> 00:00:02.000\n<i>[Music]</i>\n\n00:00:02.000 --> 00:00:03.000\n♪ la la ♪\n\n00:00:03.000 --> 00:00:04.000\n(laughs)\n\n00:00:04.000 --> 00:00:05.000\n<c.yellow>Real</c> speech [applause] here &amp; there &lt;3\n';
assert.equal(out(sound, {output: 'text', dropSound: true}), 'Real speech here & there <3\n');
assert.ok(out(sound, {output: 'text'}).includes('[Music]'));
assert.equal(out('00:00:01.000 --> 00:00:02.000\n<00:00:01.500><c> a</c><00:00:01.800><c> b</c>\n', {output: 'text'}), 'a b\n');

// Markdown escaping and YAML conventions.
assert.equal(out('00:00:01.000 --> 00:00:02.000\n# not a heading *bold* costs $5 #tag snake_case\n', {output: 'md', heading: false}), '\\# not a heading \\*bold\\* costs \\$5 \\#tag snake_case\n');
assert.equal(out('00:00:01.000 --> 00:00:02.000\n- item\n', {output: 'md', heading: false}), '\\- item\n');
assert.equal(out('00:00:01.000 --> 00:00:02.000\nx\n', {output: 'md', heading: false, properties: true, title: 'Plan: phase 1', date: '', tags: 'Team sync, 2026, a/b'}),
  '---\ntitle: "Plan: phase 1"\ntags:\n  - Team-sync\n  - a/b\n---\n\nx\n');

// Errors, not silence.
assert.equal(conv('').error, 'empty');
assert.equal(conv('just some text\nwith no timing').ok, false);
assert.equal(conv('just some text').error, 'no-cues');
assert.equal(conv('WEBVTT\n\nNOTE nothing else').error, 'no-cues');
assert.equal(conv(srt, {dropSound: true}).ok, true);
assert.equal(conv('00:00:01.000 --> 00:00:02.000\n[Music]\n', {dropSound: true}).error, 'empty-output');
'''


@unittest.skipUnless(shutil.which('node'), 'Node is required for website JavaScript tests')
class SubtitleConverterTests(unittest.TestCase):
    def test_converter_logic(self):
        result = subprocess.run(['node','-e',HARNESS,str(GUIDE)],text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_page_makes_no_network_requests(self):
        script = re.search(r'<script>(.*)</script>',GUIDE.read_text(),re.S).group(1)
        for needle in ('fetch(','XMLHttpRequest','sendBeacon','WebSocket','http://','https://','import(','localStorage'):
            self.assertNotIn(needle,script)

    def test_every_message_the_script_uses_exists(self):
        html = GUIDE.read_text()
        names = set(re.findall(r'data-message="([^"]+)"',html))
        script = re.search(r'<script>(.*)</script>',html,re.S).group(1)
        for name in re.findall(r"message\('([a-z-]+)'[,)]",script):
            self.assertIn(name,names)
        for name in ('err-no-cues','err-empty-output','format-srt','format-vtt','title-text','title-md','title-srt','title-vtt'):
            self.assertIn(name,names)
