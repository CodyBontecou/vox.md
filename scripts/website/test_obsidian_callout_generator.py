"""Logic tests for the in-browser Obsidian callout generator."""
from pathlib import Path
import re
import shutil
import subprocess
import unittest

GUIDE = Path(__file__).resolve().parents[2]/'website-content/guides/obsidian-callout-generator.html'

HARNESS = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(process.argv[1], 'utf8');
const source = /<script>([\s\S]*)<\/script>/.exec(html)[1];
const window = {};
vm.runInNewContext(source, {window, document: {getElementById() { return null; }}});
const api = window.voxCallout;
const gen = (o) => api.run(o).output;

assert.equal(gen({type: 'note', body: 'hi'}), '> [!note]\n> hi');
assert.equal(gen({type: 'tip', title: 'Remember', body: ''}), '> [!tip] Remember');
assert.equal(gen({type: 'faq', fold: '+', title: 'Q', body: 'a'}), '> [!faq]+ Q\n> a');
assert.equal(gen({type: 'faq', fold: '-', body: 'a'}), '> [!faq]-\n> a');
assert.equal(gen({type: 'note', fold: 'x', body: 'a'}), '> [!note]\n> a');
// Blank lines kept as ">" or dropped; edges trimmed.
assert.equal(gen({type: 'note', body: '\n\na\n\nb\n\n'}), '> [!note]\n> a\n>\n> b');
assert.equal(gen({type: 'note', body: 'a\n\nb', blank: false}), '> [!note]\n> a\n> b');
// Nesting.
assert.equal(gen({type: 'example', depth: 2, body: 'a\n\nb'}), '> > > [!example]\n> > > a\n> > >\n> > > b');
assert.equal(gen({type: 'note', depth: 9, body: 'a'}), '> > > > [!note]\n> > > > a');
assert.equal(gen({type: 'note', depth: 'x', body: 'a'}), '> [!note]\n> a');
// Pasted > prefixes are not doubled.
assert.equal(gen({type: 'note', body: '> a\n>b\n> > c\n>'}), '> [!note]\n> a\n> b\n> c');
// Lists, code and CRLF.
assert.equal(gen({type: 'info', body: '- a\r\n  - b\r\n```\r\nx\r\n```'}), '> [!info]\n> - a\n>   - b\n> ```\n> x\n> ```');
// Title is one line.
assert.equal(gen({type: 'note', title: '  a\n b  '}), '> [!note] a b');
// Custom type and warning.
let r = api.run({type: 'note', custom: 'My Type', body: 'a'});
assert.equal(r.output, '> [!My-Type]\n> a');
assert.equal(JSON.stringify(r.warnings), JSON.stringify(['custom-warning']));
assert.equal(r.defaultTitle, 'My Type');
r = api.run({type: 'note', custom: 'TLDR'});
assert.equal(JSON.stringify(r.warnings), JSON.stringify([]));
r = api.run({type: 'tip', custom: '  [!!]  '});
assert.equal(r.output, '> [!tip]');
assert.equal(api.run({type: 'tldr'}).defaultTitle, 'Tldr');
// Types match the Obsidian Help list.
const list = api.types.map(t => [t.id].concat(t.aliases).join('/')).join(';');
assert.equal(list, 'note;abstract/summary/tldr;info;todo;tip/hint/important;success/check/done;question/help/faq;warning/caution/attention;failure/fail/missing;danger/error;bug;example;quote/cite');
assert.equal(api.lookup('CAUTION').id, 'warning');
assert.equal(api.lookup('nope'), null);
'''


@unittest.skipUnless(shutil.which('node'), 'Node is required for website JavaScript tests')
class CalloutGeneratorTests(unittest.TestCase):
    def test_callout_logic(self):
        result = subprocess.run(['node','-e',HARNESS,str(GUIDE)],text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_static_example_matches_tool(self):
        html = GUIDE.read_text()
        block = re.search(r'<pre class="guide-code" id="default-callout"><code>(.*?)</code>',html,re.S).group(1)
        self.assertEqual(block,'&gt; [!warning]- Back up first\n&gt; Copy the vault before you change the plugin settings.\n&gt;\n&gt; Then restart Obsidian.\n')

    def test_page_makes_no_network_requests(self):
        script = re.search(r'<script>(.*)</script>',GUIDE.read_text(),re.S).group(1)
        for needle in ('fetch(','XMLHttpRequest','sendBeacon','WebSocket','http://','https://','localStorage'):
            self.assertNotIn(needle,script)


if __name__ == '__main__':
    unittest.main()
