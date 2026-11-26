"""Logic tests for the in-browser Obsidian daily note template generator."""
from pathlib import Path
import re
import shutil
import subprocess
import unittest

GUIDE = Path(__file__).resolve().parents[2]/'website-content/guides/obsidian-daily-note-template.html'

HARNESS = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(process.argv[1], 'utf8');
const source = /<script>([\s\S]*)<\/script>/.exec(html)[1];
const window = {};
vm.runInNewContext(source, {window, document: {getElementById() { return null; }}});
const api = window.voxDailyTemplate;
const day = api.parseDate('2026-11-21');
const base = {system: 'core', props: ['date', 'weekday', 'tags'], tag: 'daily', format: 'YYYY-MM-DD', nav: false, titledate: false,
  sections: ['focus', 'tasks', 'journal', 'inbox'], order: ['focus', 'tasks', 'journal', 'inbox', 'meetings', 'gratitude', 'log', 'review']};
const fmt = (f, d) => api.formatMoment(f, d || day);

// Every offered token.
const expected = {YYYY: '2026', YY: '26', MM: '11', M: '11', MMM: 'Nov', MMMM: 'November', DD: '21', D: '21',
  ddd: 'Sat', dddd: 'Saturday', ww: '47', Q: '4'};
for (const [token, text] of Object.entries(expected)) {
  assert.equal(JSON.stringify(fmt(token)), JSON.stringify({text, unsupported: []}), token);
}
const jan = api.parseDate('2026-01-05');
assert.equal(fmt('YYYY/MM/YYYY-MM-DD', jan).text, '2026/01/2026-01-05');
assert.equal(fmt('M-D', jan).text, '1-5');
assert.equal(fmt('YYYY/MMMM/YYYY-MMM-DD', api.parseDate('2023-01-01')).text, '2023/January/2023-Jan-01');
assert.equal(fmt('ww', api.parseDate('2026-01-01')).text, '01');
assert.equal(fmt('ww', api.parseDate('2026-12-31')).text, '01');
assert.equal(fmt('[Week] ww', day).text, 'Week 47');
assert.equal(fmt('Q', api.parseDate('2026-03-31')).text, '1');
assert.equal(fmt('Q', api.parseDate('2026-04-01')).text, '2');

// Unsupported tokens are reported, not silently changed.
assert.equal(fmt('Do MMMM HH:mm').unsupported.join(), 'Do,HH,mm');
assert.equal(fmt('DDD').unsupported.join(), 'DDD');
assert.equal(fmt('YYYY-MM-DD').unsupported.length, 0);
assert.equal(api.parseDate('2026-02-30'), null);

// Paths and folders.
assert.equal(api.previewPath('Journal', 'YYYY/MM/YYYY-MM-DD', day), 'Journal/2026/11/2026-11-21.md');
assert.equal(api.previewPath(' /Journal/ ', 'YYYY-MM-DD', day), 'Journal/2026-11-21.md');
assert.equal(api.previewPath('', 'YYYY-MM-DD', day), '2026-11-21.md');
assert.equal(api.fileTitleFormat('YYYY/MMMM/YYYY-MMM-DD'), 'YYYY-MMM-DD');

// Core output has no Templater syntax and no offsets, even if links are requested.
const core = api.build({...base, nav: true, titledate: true});
assert.ok(core.includes('date: {{date:YYYY-MM-DD}}'));
assert.ok(core.includes('weekday: {{date:dddd}}'));
assert.ok(core.includes('# {{title}}'));
assert.ok(!core.includes('<%') && !core.includes('tp.') && !core.includes('Previous'));
assert.equal(core, '---\ndate: {{date:YYYY-MM-DD}}\nweekday: {{date:dddd}}\ntags:\n  - daily\n---\n# {{title}}\n\n## Top 3\n- [ ] \n- [ ] \n- [ ] \n\n## Tasks\n- [ ] \n\n## Journal\n\n\n## Inbox\n- \n');

// Templater output.
const tp = api.build({...base, system: 'templater', nav: true, titledate: true, format: 'YYYY/MM/YYYY-MM-DD'});
assert.ok(tp.includes('date: <% tp.date.now("YYYY-MM-DD", 0, tp.file.title, "YYYY-MM-DD") %>'));
assert.ok(tp.includes('[[<% tp.date.now("YYYY-MM-DD", -1, tp.file.title, "YYYY-MM-DD") %>]]'));
assert.ok(tp.includes('[[<% tp.date.now("YYYY-MM-DD", 1, tp.file.title, "YYYY-MM-DD") %>]]'));
assert.ok(tp.includes('# <% tp.file.title %>'));
const tpPlain = api.build({...base, system: 'templater'});
assert.ok(tpPlain.includes('date: <% tp.date.now("YYYY-MM-DD") %>'));
assert.ok(!tpPlain.includes('Previous'));

// Plain Markdown has no template syntax at all.
const plain = api.build({...base, system: 'plain', nav: true});
assert.ok(!/\{\{|<%/.test(plain));

// Controls change the output: tag, order, sections, properties.
assert.ok(api.build({...base, tag: '#My Tag!'}).includes('  - My-Tag'));
assert.ok(api.build({...base, props: ['mood', 'energy']}).includes('mood: \nenergy: '));
assert.ok(!api.build({...base, props: []}).startsWith('---'));
const reordered = api.build({...base, order: ['inbox', 'journal', 'tasks', 'focus', 'meetings', 'gratitude', 'log', 'review']});
assert.ok(reordered.indexOf('## Inbox') < reordered.indexOf('## Top 3'));
assert.ok(api.build({...base, sections: ['review']}).includes('## End-of-day review'));
'''


@unittest.skipUnless(shutil.which('node'), 'Node is required for website JavaScript tests')
class DailyNoteTemplateTests(unittest.TestCase):
    def test_generator_logic(self):
        result = subprocess.run(['node','-e',HARNESS,str(GUIDE)],text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_static_default_matches_generator_default(self):
        html = GUIDE.read_text()
        blocks = re.findall(r'<code[^>]*>(---\n.*?)</code>',html,re.S)
        self.assertEqual(len(blocks),2)
        self.assertEqual(blocks[0],blocks[1])
        self.assertIn('date: {{date:YYYY-MM-DD}}',blocks[0])
        self.assertNotIn('<%',blocks[0])

    def test_page_makes_no_network_requests(self):
        script = re.search(r'<script>(.*)</script>',GUIDE.read_text(),re.S).group(1)
        for needle in ('fetch(','XMLHttpRequest','sendBeacon','WebSocket','http://','https://'):
            self.assertNotIn(needle,script)


if __name__ == '__main__':
    unittest.main()
