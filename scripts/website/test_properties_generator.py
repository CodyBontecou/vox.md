"""Logic tests for the in-browser Obsidian properties generator and checker."""
from pathlib import Path
import re
import shutil
import subprocess
import unittest

GUIDE = Path(__file__).resolve().parents[2]/'website-content/guides/obsidian-properties-generator.html'

HARNESS = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(process.argv[1], 'utf8');
const source = /<script>([\s\S]*)<\/script>/.exec(html)[1];
const window = {};
vm.runInNewContext(source, {window, document: {getElementById() { return null; }}});
const api = window.voxProperties;
const build = (rows, mode) => api.build(rows, mode || 'none');
const one = (type, value, name, mode) => build([{name: name || 'k', type, value}], mode).split('\n')[1];
const rules = (text) => api.check(text).problems.map(p => p.line + ':' + p.rule);
const same = (a, b) => assert.equal(JSON.stringify(a), JSON.stringify(b));
const wrap = (body) => '---\n' + body + '\n---\n';

// Generator: every type.
assert.equal(one('text', 'Weekly review'), 'k: Weekly review');
assert.equal(one('number', '4'), 'k: 4');
assert.equal(one('number', 'abc'), 'k:');
assert.equal(one('checkbox', 'true'), 'k: true');
assert.equal(one('checkbox', 'false'), 'k: false');
assert.equal(one('date', '2026-11-21'), 'k: 2026-11-21');
assert.equal(one('datetime', '2026-11-21T10:30'), 'k: 2026-11-21T10:30:00');
assert.equal(one('datetime', '2026-11-21T10:30:15'), 'k: 2026-11-21T10:30:15');
assert.equal(build([{name: 'topics', type: 'list', value: 'sleep\n\n focus '}]), '---\ntopics:\n  - sleep\n  - focus\n---\n');
assert.equal(build([{name: 'tags', type: 'tags', value: '#a b\n2026, x/y'}]), '---\ntags:\n  - a-b\n  - x/y\n---\n');
assert.equal(build([{name: 'aliases', type: 'list', value: ''}]), '---\naliases: []\n---\n');
assert.equal(build([{name: '', type: 'text', value: 'x'}]), '');

// Quoting of text values.
assert.equal(one('text', '[[Note]]'), 'k: "[[Note]]"');
assert.equal(one('text', '"[[Note]]"'), 'k: "[[Note]]"');
assert.ok(build([{name: 'k', type: 'list', value: '[[A]]'}]).includes('  - "[[A]]"'));
for (const v of ['a: b', '#tag', '[x]', '{x}', '*x', '&x', '!x', '%x', '@x', 'yes', 'No', 'TRUE', 'null', '42', '3.5', '2026-11-21', 'say "hi": now']) {
  assert.ok(/^k: ".*"$/.test(one('text', v)), v + ' -> ' + one('text', v));
}
assert.equal(one('text', 'say "a": b'), 'k: "say \\"a\\": b"');
for (const v of ['plain', 'a:b', 'two words', 'C# notes']) assert.equal(one('text', v), 'k: ' + v);
assert.equal(api.cleanTag('#My tag!'), 'My-tag');
assert.equal(api.cleanTag('2026'), '');
assert.equal(api.cleanTag('y2026'), 'y2026');
assert.equal(api.cleanTag('inbox/to-read'), 'inbox/to-read');

// Template tokens.
assert.equal(one('date', '', 'd', 'core'), 'd: {{date:YYYY-MM-DD}}');
assert.equal(one('datetime', '', 'd', 'core'), 'd: {{date:YYYY-MM-DD[T]HH:mm:ss}}');
assert.equal(one('date', '', 'd', 'templater'), 'd: <% tp.date.now("YYYY-MM-DD") %>');
assert.equal(one('datetime', '', 'd', 'templater'), 'd: <% tp.date.now("YYYY-MM-DD[T]HH:mm:ss") %>');
assert.equal(one('text', '{{title}}', 't', 'core'), 't: {{title}}');
assert.equal(one('text', '{{title}}', 't', 'none'), 't: "{{title}}"');

// Warnings and Route metadata.
same(api.warnings([{name: 'a', type: 'text', value: ''}, {name: 'a', type: 'text', value: ''}], 'none').map(w => w.id), ['w-duplicate']);
same(api.warnings([{name: 'n', type: 'number', value: 'x'}], 'none').map(w => w.id), ['w-number']);
same(api.warnings([{name: 'tags', type: 'tags', value: '2026\n#ok tag'}], 'none').map(w => w.id), ['w-tag-empty', 'w-tag']);
assert.equal(api.routeMetadata([{name: 'tags', type: 'tags', value: 'journal\nidea'}, {name: 'done', type: 'checkbox', value: 'true'},
  {name: 'project', type: 'text', value: '[[Vox.md launch]]'}, {name: 'empty', type: 'text', value: ''}, {name: 'l', type: 'list', value: 'a, b\nc'}]),
  'tags: [journal, idea]\ndone: true\nproject: "[[Vox.md launch]]"\nl: ["a, b", c]');

// Checker: the answer-box example has no problems.
const example = /<pre class="guide-code" id="default-properties"><code>([\s\S]*?)<\/code>/.exec(html)[1].replace(/&quot;/g, '"');
same(api.check(example).problems, []);
same(api.check(build([
  {name: 'tags', type: 'tags', value: 'a\nb/c'}, {name: 'aliases', type: 'list', value: '[[X]]\nY: z'}, {name: 'cssclasses', type: 'list', value: 'wide'},
  {name: 't', type: 'text', value: '#x'}, {name: 'n', type: 'number', value: '1'}, {name: 'c', type: 'checkbox', value: 'true'},
  {name: 'd', type: 'date', value: '2026-11-21'}, {name: 'dt', type: 'datetime', value: '2026-11-21T10:30'}, {name: 'e', type: 'list', value: ''}])).problems, []);
same(api.check(build([{name: 'd', type: 'date', value: ''}], 'templater')).problems, []);
same(api.check(build([{name: 'd', type: 'date', value: ''}], 'core')).problems, []);

// Checker: each rule reports its line.
same(rules(wrap('tags:\n\t- a')), ['3:tabs']);
same(rules('---\ntags:\n  - a\n'), ['1:no-close']);
same(rules('tags:\n  - a\n---\n'), ['1:no-open']);
same(rules(wrap('project: [[Note]]')), ['2:link-unquoted']);
same(rules(wrap('related:\n  - [[Note]]')), ['3:link-unquoted']);
same(rules(wrap('related: [[[A]], [[B]]]')), ['2:link-unquoted']);
same(rules(wrap('related: ["[[A]]", "[[B]]"]')), []);
same(rules(wrap('tags:\n  - my tag')), ['3:tag-space']);
same(rules(wrap('tags:\n  - #journal')), ['3:tag-hash']);
same(rules(wrap('tags: [#a, b]')), ['2:tag-hash']);
same(rules(wrap('tags:\n  - 1984')), ['3:tag-numeric']);
same(rules(wrap('tags:\n  - y1984\n  - inbox/to-read')), []);
same(rules(wrap('tags:\n  - "bad!"')), ['3:tag-chars']);
same(rules(wrap('tag: a\nalias: b\ncssclass: c')), ['2:deprecated', '3:deprecated', '4:deprecated']);
same(rules(wrap('a:\n  b: 1')), ['3:nested']);
same(rules(wrap('a: {b: 1}')), ['2:nested']);
same(rules(wrap('a:\n  - name: x')), ['3:nested']);
same(rules(wrap('a: **bold** text')), ['2:bad-start']);
same(rules(wrap('a: some **bold** text')), ['2:markdown']);
same(rules(wrap('a: "see [site](https://example.com)"')), ['2:markdown']);
same(rules(wrap('a: see [[Note]] today')), []);
same(rules(wrap('a: 1\nb: 2\na: 3')), ['4:duplicate']);
same(rules(wrap('title: Plan: phase 1')), ['2:bad-colon']);
same(rules(wrap('title: @home')), ['2:bad-start']);
same(rules(wrap('title: "open')), ['2:unclosed-quote']);
same(rules(wrap('title: a #b')), ['2:comment']);
same(rules(wrap('title:x')), ['2:not-pair']);
same(rules(wrap('a: |\n  line: one\n  line two\nb: 1')), []);
same(rules(wrap('a: [x,\n  y]\nb: 1')), []);
same(rules(wrap('# comment\na: {{title}}\nb: <% tp.date.now("YYYY") %>')), []);
same(rules('---\r\ntags:\r\n\t- a\r\n---\r\n'), ['3:tabs']);
assert.equal(api.check('').empty, true);
assert.equal(api.check('{"tags": ["a"]}').json, true);
// Body text after the closing --- is not checked.
same(rules('---\na: 1\n---\n# Heading: x\n- [[Link]]\n'), []);
'''


@unittest.skipUnless(shutil.which('node'), 'Node is required for website JavaScript tests')
class PropertiesGeneratorTests(unittest.TestCase):
    def test_generator_and_checker_logic(self):
        result = subprocess.run(['node','-e',HARNESS,str(GUIDE)],text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_page_makes_no_network_requests(self):
        script = re.search(r'<script>(.*)</script>',GUIDE.read_text(),re.S).group(1)
        for needle in ('fetch(','XMLHttpRequest','sendBeacon','WebSocket','http://','https://','import('):
            self.assertNotIn(needle,script)

    def test_every_message_the_script_uses_exists(self):
        html = GUIDE.read_text()
        names = set(re.findall(r'data-message="([^"]+)"',html))
        script = re.search(r'<script>(.*)</script>',html,re.S).group(1)
        for rule in re.findall(r"add\([^,]+, '([a-z-]+)'",script):
            self.assertIn('m-'+rule,names)
            self.assertIn('f-'+rule,names)
        for warning in re.findall(r"id: '(w-[a-z-]+)'",script):
            self.assertIn(warning,names)
        for t in ('text','list','number','checkbox','date','datetime','tags'):
            self.assertIn('type-'+t,names)


if __name__ == '__main__':
    unittest.main()
