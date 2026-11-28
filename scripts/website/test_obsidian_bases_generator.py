"""Logic tests for the in-browser Obsidian Bases generator."""
from html import unescape
from pathlib import Path
import re
import shutil
import subprocess
import unittest

GUIDE = Path(__file__).resolve().parents[2]/'website-content/guides/obsidian-bases-generator.html'

HARNESS = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(process.argv[1], 'utf8');
const source = /<script>([\s\S]*)<\/script>/.exec(html)[1];
const window = {};
vm.runInNewContext(source, {window, document: {getElementById() { return null; }}});
const api = window.voxBases;
const codes = (r) => r.issues.map(i => i.level + ':' + i.code).join(',');
const view = (o) => Object.assign({type: 'table', name: 'V', order: 'file.name', limit: '', group: '', dir: 'ASC', filters: '', summaries: []}, o);

// Quoting: comparisons are single-quoted, text values double-quoted inside.
let r = api.build({mode: 'and', filters: [{kind: 'prop', a: 'status', op: '!=', b: 'done'}], views: [view({})]});
assert.equal(r.yaml, 'filters:\n  and:\n    - \'status != "done"\'\nviews:\n  - type: table\n    name: "V"\n    order:\n      - file.name');
// Numbers, booleans and functions stay raw; spaces get a note.
r = api.build({filters: [{kind: 'prop', a: 'n', op: '>=', b: '3'}, {kind: 'prop', a: 'x', op: '==', b: 'true'}, {kind: 'prop', a: 'd', op: '<', b: 'today()'}, {kind: 'prop', a: 'p', op: '==', b: 'to read'}], views: [view({})]});
assert.match(r.yaml, /- 'n >= 3'\n    - 'x == true'\n    - 'd < today\(\)'\n    - 'p == "to read"'/);
assert.match(codes(r), /info:i-space/);
// Functions.
r = api.build({mode: 'or', filters: [{kind: 'hasTag', a: '#a'}, {kind: 'inFolder', a: 'My "x" dir'}, {kind: 'hasLink', a: 'Note'}, {kind: 'hasLink', a: 'this.file'}, {kind: 'ext', a: '.md'}], views: [view({})]});
assert.match(r.yaml, /^filters:\n  or:\n    - file\.hasTag\("a"\)\n    - file\.inFolder\("My \\"x\\" dir"\)\n    - file\.hasLink\("Note"\)\n    - file\.hasLink\(this\.file\)\n    - 'file\.ext == "md"'/);
// not mode, no filter reminder, empty rows dropped.
r = api.build({mode: 'not', filters: [{kind: 'hasTag', a: 'x'}], views: [view({})]});
assert.match(r.yaml, /^filters:\n  not:/);
r = api.build({filters: [{kind: 'hasTag', a: ''}], views: [view({})]});
assert.ok(!/filters:/.test(r.yaml));
assert.match(codes(r), /i-no-filter/);
assert.match(codes(r), /warn:i-empty-value/);
// Validation.
r = api.build({filters: [{kind: 'hasTag', a: 'x'}], views: [view({name: ' '})]});
assert.match(codes(r), /error:i-view-name/);
r = api.build({filters: [{kind: 'hasTag', a: 'x'}], formulas: [{name: 'a', expr: 'formula.a + 1'}], views: [view({})]});
assert.match(codes(r), /error:i-formula-self/);
r = api.build({filters: [{kind: 'hasTag', a: 'x'}], formulas: [{name: 'a', expr: 'formula.ab + 1'}], views: [view({})]});
assert.ok(!/i-formula-self/.test(codes(r)));
assert.match(r.yaml, /formulas:\n  a: 'formula\.ab \+ 1'/);
r = api.build({formulas: [{name: 'it', expr: "if(x, 'a')"}], views: [view({})]});
assert.match(r.yaml, /  it: 'if\(x, ''a''\)'/);
r = api.build({formulas: [{name: 'bad name', expr: '1'}], views: [view({})]});
assert.match(codes(r), /error:i-formula-name/);
r = api.build({filters: [{kind: 'hasTag', a: 'x'}], views: [view({group: 'status'})]});
assert.match(codes(r), /warn:i-group-order/);
assert.match(r.yaml, /groupBy:\n      property: status\n      direction: ASC/);
r = api.build({filters: [{kind: 'hasTag', a: 'x'}], views: [view({group: 'file.name', dir: 'DESC'})]});
assert.ok(!/i-group-order/.test(codes(r)));
assert.match(r.yaml, /direction: DESC/);
r = api.build({views: []});
assert.match(codes(r), /error:i-no-views/);
r = api.build({views: [view({type: 'map'}), view({type: 'kanban'})]});
assert.match(codes(r), /i-map/);
assert.match(codes(r), /i-kanban/);
// Limit, summaries, view filters.
r = api.build({filters: [{kind: 'hasTag', a: 'x'}], views: [view({limit: '10', filters: 'file.inFolder("A")\nstatus == "x"', summaries: [{prop: 'price', fn: 'Sum'}, {prop: 'p', fn: 'Nope'}]})]});
assert.match(r.yaml, /    limit: 10\n    filters:\n      and:\n        - file\.inFolder\("A"\)\n        - 'status == "x"'\n    order:/);
assert.match(r.yaml, /    summaries:\n      price: Sum$/);
assert.match(codes(r), /error:i-summary-bad/);
// Output modes, file name and embeds.
r = api.build({filters: [{kind: 'hasTag', a: 'x'}], output: 'block', basename: 'My: base/1', views: [view({name: 'Open #1'})]});
assert.ok(r.output.startsWith('```base\n') && r.output.endsWith('\n```'));
assert.equal(r.filename, 'My base 1.base');
assert.equal(r.embed, '![[My base 1.base]]');
assert.equal(r.embedView, '![[My base 1.base#Open 1]]');
// Summaries match the syntax page defaults.
assert.equal(api.summaries.join(','), 'Average,Min,Max,Sum,Range,Median,Stddev,Earliest,Latest,Checked,Unchecked,Empty,Filled,Unique');
// Presets give no errors and no missing-name problems.
for (const k of Object.keys(api.presets)) {
  const res = api.build(api.presets[k].state);
  assert.ok(!/error/.test(codes(res)), k + ' ' + codes(res));
  assert.ok(!/warn/.test(codes(res)), k + ' ' + codes(res));
}
'''

DUMP = r'''
const fs = require('node:fs');
const vm = require('node:vm');
const source = /<script>([\s\S]*)<\/script>/.exec(fs.readFileSync(process.argv[1], 'utf8'))[1];
const window = {};
vm.runInNewContext(source, {window, document: {getElementById() { return null; }}});
const out = {};
for (const k of Object.keys(window.voxBases.presets)) out[k] = window.voxBases.build(window.voxBases.presets[k].state).yaml;
process.stdout.write(JSON.stringify(out));
'''


@unittest.skipUnless(shutil.which('node'), 'Node is required for website JavaScript tests')
class BasesGeneratorTests(unittest.TestCase):
    def test_bases_logic(self):
        result = subprocess.run(['node','-e',HARNESS,str(GUIDE)],text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_static_examples_match_presets(self):
        import json
        result = subprocess.run(['node','-e',DUMP,str(GUIDE)],text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        presets = json.loads(result.stdout)
        html = GUIDE.read_text()
        for key,pid in (('reading','example-reading'),('projects','example-projects'),('week','example-week'),('backlinks','example-backlinks'),('voice','example-voice')):
            block = re.search(r'<pre class="guide-code" id="%s"><code>(.*?)</code>'%pid,html,re.S).group(1)
            self.assertEqual(unescape(block).rstrip('\n'),presets[key],key)
        lead = re.search(r'id="default-base"><code>(.*?)</code>',html,re.S).group(1)
        self.assertEqual(unescape(lead).rstrip('\n'),presets['projects'])

    def test_page_makes_no_network_requests(self):
        script = re.search(r'<script>(.*)</script>',GUIDE.read_text(),re.S).group(1)
        for needle in ('fetch(','XMLHttpRequest','sendBeacon','WebSocket','http://','https://','localStorage'):
            self.assertNotIn(needle,script)


if __name__ == '__main__':
    unittest.main()
