"""Logic tests for the in-browser speech time calculator."""
from pathlib import Path
import re
import shutil
import subprocess
import unittest

GUIDE = Path(__file__).resolve().parents[2]/'website-content/guides/speech-time-calculator.html'

HARNESS = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(process.argv[1], 'utf8');
const source = /<script>([\s\S]*)<\/script>/.exec(html)[1];
const window = {};
vm.runInNewContext(source, {window, document: {getElementById() { return null; }}});
const api = window.voxSpeechTime;
const words = (t) => api.countWords(t).words;

// Word counting: hyphenated words once, numbers count, punctuation-only tokens do not.
assert.equal(words('a well-known idea'), 3);
assert.equal(words('In 2026 we sold 1,000 units at 3.5% - quickly.'), 9);
assert.equal(words('one — two – three'), 3);
assert.equal(words('  \n\n '), 0);
assert.equal(words(''), 0);
assert.equal(words('hello\r\nworld'), 2);

// Fixture: frontmatter, heading, list, link, wikilink, bold.
const fixture = '---\ntitle: Opening talk\ntags: [speech]\n---\n# Opening remarks\n\n- First point, **well-known** idea\n- See [the guide](https://example.com/guide) and [[Project plan|plan]]\n\nTotal: 2026 plans.\n';
assert.deepEqual({...api.countWords(fixture)}, {words: 14, paragraphs: 3});
// The page's own example is the same fixture.
const ex = /var EXAMPLE = '([^\n]*)';/.exec(source)[1].replace(/\\n/g, '\n').replace(/\\\//g, '/');
assert.equal(ex, fixture.trimEnd());
assert.equal(words(ex), 14);

// Markdown pieces.
assert.equal(words('> quoted line\n> * nested'), 3);
assert.equal(words('1. one\n2) two\n- [ ] task\n- [x] done'), 4);
assert.equal(words('See [[Folder/Note title]] and [[Note#Heading]] and ![[image.png]]'), 6);
assert.equal(words('![alt text](pic.png) after'), 1);
assert.equal(words('visit https://example.com/a?b=c now or www.example.org today'), 4);
assert.equal(words('text<!-- hidden words --> more %%private%% end'), 3);
assert.equal(words('a `code` b ~~gone~~ c ==marked== _em_ __strong__'), 8);
assert.equal(words('snake_case stays'), 2);
assert.equal(words('| a | b |\n| --- | --- |\n| c | d |'), 4);
assert.equal(words('before\n\n---\n\nafter'), 2);
assert.equal(words('```js\nlet x\n```'), 2);
assert.equal(words('word[^1]\n\n[^1]: note text'), 3);
assert.equal(words('---\ntitle: x\n'), 2);
assert.equal(words('---\n---\nbody here'), 2);
assert.equal(words('café naïve 日本'), 3);

// Time formulas.
const t = (o) => api.scriptTime(o);
assert.equal(t({words: 1000, wpm: 130}).total, 462);
assert.equal(api.fmt(462), '7:42');
assert.equal(api.fmt(3725), '1:02:05');
assert.equal(api.fmt(0), '0:00');
assert.equal(t({words: 1000, wpm: 150}).total, 400);
const p = t({words: 1000, paragraphs: 12, wpm: 130, pausePara: 3, slides: 10, pauseSlide: 4});
assert.deepEqual({...p}, {speech: 462, pauses: 76, total: 538});
assert.equal(api.fmt(p.total), '8:58');
assert.equal(t({words: 0, wpm: 130}).total, 0);

// Invalid pace gives an error, never NaN or Infinity.
for (const wpm of [0, 39, 401, NaN, Infinity, -5, undefined]) assert.equal(t({words: 100, wpm}).error, 'bad-wpm');
assert.equal(api.wordsForTime({minutes: 5, wpm: 39}).error, 'bad-wpm');
assert.equal(t({words: 100, wpm: 40}).total, 150);
assert.equal(t({words: 100, wpm: 400}).total, 15);

// Time to words.
assert.equal(api.wordsForTime({minutes: 5, wpm: 130}).words, 650);
assert.equal(api.wordsForTime({minutes: 5, wpm: 150}).words, 750);
assert.equal(api.wordsForTime({minutes: 5, wpm: 130, reserve: 60}).words, 520);
assert.equal(api.wordsForTime({minutes: 1, wpm: 130, reserve: 60}).error, 'no-room');
assert.equal(api.wordsForTime({minutes: 1, wpm: 130, reserve: 90}).error, 'no-room');
assert.equal(api.wordsForTime({minutes: 0.5, wpm: 130}).words, 65);

// Durations.
assert.equal(api.parseDuration('4:35'), 275);
assert.equal(api.parseDuration(' 0:12 '), 12);
assert.equal(api.parseDuration('75:00'), 4500);
assert.equal(api.parseDuration('1:04:35'), 3875);
assert.equal(api.parseDuration('0:00'), 0);
for (const bad of ['', 'abc', '4', '4:60', '4:5', '-1:00', '1:2:3', '4:35:99', '1e3:00']) assert.equal(api.parseDuration(bad), null);

// Measuring.
assert.deepEqual({...api.measure(650, 300)}, {wpm: 130});
assert.deepEqual({...api.measure(1000, 462)}, {wpm: 130});
assert.equal(api.measure(100, 0).error, 'zero-duration');
assert.equal(api.measure(0, 60).error, 'no-transcript');
assert.equal(api.measure(5, 600).error, 'pace-out-of-range');
assert.equal(api.measure(10000, 60).error, 'pace-out-of-range');
assert.deepEqual({...api.compare(150, 130)}, {kind: 'faster', pct: 15});
assert.deepEqual({...api.compare(100, 130)}, {kind: 'slower', pct: 23});
assert.deepEqual({...api.compare(130, 130)}, {kind: 'same'});

// Quick tables on the page match the formula exactly.
const fmtNum = api.num;
const minuteRows = [...html.matchAll(/<tr><th scope="row">(\d+) minutes?<\/th><td>([\d,]+)<\/td><td>([\d,]+)<\/td><\/tr>/g)];
assert.deepEqual(minuteRows.map(r => +r[1]), [1, 2, 3, 5, 7, 10, 15, 20]);
for (const r of minuteRows) {
  assert.equal(r[2], fmtNum(api.wordsFor(+r[1], 130)));
  assert.equal(r[3], fmtNum(api.wordsFor(+r[1], 150)));
}
const wordRows = [...html.matchAll(/<tr><th scope="row">([\d,]+) words<\/th><td>(\d+:\d\d)<\/td><td>(\d+:\d\d)<\/td><\/tr>/g)];
assert.deepEqual(wordRows.map(r => +r[1].replace(',', '')), [500, 750, 1000, 1500, 2000, 2500]);
for (const r of wordRows) {
  const n = +r[1].replace(',', '');
  assert.equal(r[2], api.fmt(api.secondsFor(n, 130)));
  assert.equal(r[3], api.fmt(api.secondsFor(n, 150)));
}
// Figures quoted in the copy.
assert.equal(api.fmt(api.secondsFor(1000, 100)), '10:00');
assert.equal(api.fmt(api.secondsFor(1000, 170)), '5:53');
assert.equal(api.fmt(api.secondsFor(1000, 183)), '5:28');
assert.equal(api.wordsFor(5, 183), 915);
assert.equal(api.wordsFor(5, 100) + '-' + api.wordsFor(5, 170), '500-850');
assert.equal(api.wordsFor(3, 130) + '-' + api.wordsFor(3, 150), '390-450');
assert.equal(api.wordsFor(10, 130) + '-' + api.wordsFor(10, 150), '1300-1500');
assert.equal(Math.round(238 / 183 * 100), 130);
'''


@unittest.skipUnless(shutil.which('node'), 'Node is required for website JavaScript tests')
class SpeechTimeCalculatorTests(unittest.TestCase):
    def test_calculator_logic(self):
        result = subprocess.run(['node','-e',HARNESS,str(GUIDE)],text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_page_makes_no_network_requests(self):
        script = re.search(r'<script>(.*)</script>',GUIDE.read_text(),re.S).group(1)
        for needle in ('fetch(','XMLHttpRequest','sendBeacon','WebSocket','http://','https://','localStorage','import('):
            self.assertNotIn(needle,script)

    def test_every_input_has_a_label(self):
        html = GUIDE.read_text()
        for tag in re.findall(r'<(?:input|textarea)\b[^>]*\bid="([^"]+)"',html):
            self.assertRegex(html,r'<label[^>]*for="%s"'%re.escape(tag))


if __name__ == '__main__':
    unittest.main()
