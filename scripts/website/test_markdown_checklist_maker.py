"""Logic tests for the in-browser Markdown checklist maker."""
from pathlib import Path
import re
import shutil
import subprocess
import unittest

GUIDE = Path(__file__).resolve().parents[2]/'website-content/guides/markdown-checklist-maker.html'

HARNESS = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(process.argv[1], 'utf8');
const source = /<script>([\s\S]*)<\/script>/.exec(html)[1];
const window = {};
vm.runInNewContext(source, {window, document: {getElementById() { return null; }}});
const api = window.voxChecklist;
const make = (text, o) => api.run(text, Object.assign({mode: 'make'}, o || {})).output;
const strip = (text, o) => api.run(text, Object.assign({mode: 'strip'}, o || {})).output;
const eq = (a, b) => assert.equal(JSON.stringify(a), JSON.stringify(b));

// Acceptance example, tab mode, no doubled markers.
const sample = '- buy milk\n  - oat\n1. call Sam\n- [x] send invoice';
assert.equal(make(sample), '- [ ] buy milk\n\t- [ ] oat\n- [ ] call Sam\n- [x] send invoice');
assert.ok(!/- - \[/.test(make('- - [ ] a\n* 1. [x] b')));
assert.equal(make('- - [ ] a\n* 1. [x] b'), '- [ ] a\n- [x] b');

// Plain lines, markers, blank lines, headings, rules.
assert.equal(make('a\n\n  \n+ b\n2) c\n---\n-'), '- [ ] a\n- [ ] b\n- [ ] c');
assert.equal(make('## Plan\nship\n# Top\n  later'), '## Plan\n- [ ] ship\n# Top\n- [ ] later');
assert.equal(make('#tag thing'), '- [ ] #tag thing');
assert.equal(make('a\r\n- b\r\n'), '- [ ] a\n- [ ] b');

// Indentation: tabs, 2 and 4 spaces, detect, output step, level clamping.
assert.equal(make('a\n\tb\n\t\tc'), '- [ ] a\n\t- [ ] b\n\t\t- [ ] c');
assert.equal(make('a\n    b\n        c'), '- [ ] a\n\t- [ ] b\n\t\t- [ ] c');
assert.equal(make('a\n  b\n    c', {unit: '2'}), '- [ ] a\n\t- [ ] b\n\t\t- [ ] c');
assert.equal(make('a\n    b\n        c', {unit: '4'}), '- [ ] a\n\t- [ ] b\n\t\t- [ ] c');
assert.equal(make('a\n  b\n    c', {indent: '2'}), '- [ ] a\n  - [ ] b\n    - [ ] c');
assert.equal(make('a\n  b\n    c', {indent: '4'}), '- [ ] a\n    - [ ] b\n        - [ ] c');
assert.equal(make('    a\n        b'), '- [ ] a\n\t- [ ] b');
assert.equal(make('a\n\t\t\tb'), '- [ ] a\n\t- [ ] b');

// Status: keep, or reset. Nothing is guessed.
const states = '- [x] a\n- [X] b\n- [-] c\n- [?] d\n- [ ] e\ndone: f\nx g';
assert.equal(make(states), '- [x] a\n- [X] b\n- [-] c\n- [?] d\n- [ ] e\n- [ ] done: f\n- [ ] x g');
assert.equal(make(states, {reset: true}), '- [ ] a\n- [ ] b\n- [ ] c\n- [ ] d\n- [ ] e\n- [ ] done: f\n- [ ] x g');

// Progress.
eq(api.progress('- [x] a\n- [X] b\n- [-] c\n- [?] d\n- [ ] e'), {done: 4, total: 5});
eq(api.progress('x\n- plain'), {done: 0, total: 0});
eq(api.run(states, {mode: 'make'}).progress, {done: 4, total: 7});
eq(api.run(states, {mode: 'make', reset: true}).progress, {done: 0, total: 7});
eq(api.run('- [x] a\n- [ ] b\nplain', {mode: 'strip'}).progress, {done: 1, total: 2});
eq(api.run(sample, {mode: 'make'}).progress, {done: 1, total: 4});

// Due dates: exact syntax, ISO date.
const d = '2026-11-25';
assert.equal(make('a', {due: 'tasks-due', date: d}), '- [ ] a 📅 2026-11-25');
assert.equal(make('a', {due: 'tasks-scheduled', date: d}), '- [ ] a ⏳ 2026-11-25');
assert.equal(make('a', {due: 'tasks-start', date: d}), '- [ ] a 🛫 2026-11-25');
assert.equal(make('a', {due: 'dataview', date: d}), '- [ ] a [due:: 2026-11-25]');
assert.equal(make('a', {due: 'reminder', date: d}), '- [ ] a (@2026-11-25)');
assert.equal(make('a', {due: 'reminder-time', date: d, time: '09:30'}), '- [ ] a (@2026-11-25 09:30)');
assert.equal(make('a\n\tb', {due: 'reminder', date: d}), '- [ ] a (@2026-11-25)\n\t- [ ] b (@2026-11-25)');
assert.equal(make('a', {due: 'none', date: d}), '- [ ] a');
// Bad input adds nothing and warns; existing dates are not doubled.
let r = api.run('a', {mode: 'make', due: 'dataview', date: '2026-02-30'});
assert.equal(r.output, '- [ ] a');
eq(r.warnings, ['bad-date']);
r = api.run('a', {mode: 'make', due: 'reminder-time', date: d, time: '25:00'});
assert.equal(r.output, '- [ ] a (@2026-11-25)');
eq(r.warnings, ['bad-time']);
r = api.run('a 📅 2026-12-01\nb', {mode: 'make', due: 'tasks-due', date: d});
assert.equal(r.output, '- [ ] a 📅 2026-12-01\n- [ ] b 📅 2026-11-25');
eq(r.warnings, ['skipped']);
eq(api.run('(maybe) a', {mode: 'make'}).warnings, ['paren']);
assert.equal(api.isoDate(new Date(2026, 0, 5, 23, 59)), '2026-01-05');

// Reverse mode and round trips.
assert.equal(strip('- [ ] a\n\t- [x] b\n- [?] c'), '- a\n\t- b\n- c');
assert.equal(strip('- [ ] a\n\t- [x] b', {stripto: 'plain'}), 'a\nb');
assert.equal(strip('- [ ] a\n    - [x] b', {indent: '2'}), '- a\n  - b');
const made = make(sample, {reset: true});
assert.equal(make(strip(made), {reset: true}), made);
assert.equal(make(strip(made, {indent: '4'}), {reset: true}), made);
assert.equal(make(make(sample)), make(sample));
assert.equal(make(''), '');
'''


@unittest.skipUnless(shutil.which('node'), 'Node is required for website JavaScript tests')
class ChecklistMakerTests(unittest.TestCase):
    def test_checklist_logic(self):
        result = subprocess.run(['node','-e',HARNESS,str(GUIDE)],text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_static_example_matches_tool(self):
        html = GUIDE.read_text()
        block = re.search(r'<pre class="guide-code" id="default-checklist"><code>(.*?)</code>',html,re.S).group(1)
        self.assertEqual(block,'- [ ] buy milk\n\t- [ ] oat\n- [ ] call Sam\n- [x] send invoice\n')

    def test_page_makes_no_network_requests(self):
        script = re.search(r'<script>(.*)</script>',GUIDE.read_text(),re.S).group(1)
        for needle in ('fetch(','XMLHttpRequest','sendBeacon','WebSocket','http://','https://','localStorage'):
            self.assertNotIn(needle,script)


if __name__ == '__main__':
    unittest.main()
