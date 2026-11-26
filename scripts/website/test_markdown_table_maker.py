"""Logic tests for the in-browser Markdown table maker."""
from pathlib import Path
import re
import shutil
import subprocess
import unittest

GUIDE = Path(__file__).resolve().parents[2]/'website-content/guides/markdown-table-maker.html'

HARNESS = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(process.argv[1], 'utf8');
const source = /<script>([\s\S]*)<\/script>/.exec(html)[1];
const window = {};
vm.runInNewContext(source, {window, document: {getElementById() { return null; }}});
const api = window.voxTable;
const out = (text, o) => api.run(text, Object.assign({pad: 'compact', breaks: 'br'}, o || {})).output;

// Detection: spreadsheet copy (tabs), CSV, semicolon, pipe, Markdown.
assert.equal(api.detect('a\tb\n1\t2'), 'tab');
assert.equal(api.detect('a,b\n1,2'), 'comma');
assert.equal(api.detect('a;b\n1,5;2,5'), 'semicolon');
assert.equal(api.detect('a|b\n1|2'), 'pipe');
assert.equal(api.detect('| a | b |\n| --- | --- |\n| 1 | 2 |'), 'markdown');
assert.equal(api.detect('a | b\n--- | ---\n1 | 2'), 'markdown');
assert.equal(api.detect('just one column\nmore'), 'single');
assert.equal(api.detect('[[N|A]],x\n[[M|B]],y'), 'comma');

// Plain conversion, compact.
assert.equal(out('a,b\n1,2'), '| a | b |\n| --- | --- |\n| 1 | 2 |');
assert.equal(out('a\tb\r\n1\t2\r\n'), '| a | b |\n| --- | --- |\n| 1 | 2 |');

// Quoted CSV: commas, escaped quotes, multi-line cells.
assert.equal(out('n,o\n"Lee, Sam","say ""hi"""'), '| n | o |\n| --- | --- |\n| Lee, Sam | say "hi" |');
assert.equal(out('a,b\n"one\ntwo",x'), '| a | b |\n| --- | --- |\n| one<br>two | x |');
assert.equal(out('a,b\n"one\ntwo",x', {breaks: 'space'}), '| a | b |\n| --- | --- |\n| one two | x |');

// Obsidian pipes: wikilink alias, image size, plain pipe, no double escape.
let r = api.run('a,b\n[[Note|Alias]],![[img.png|200]]\nx | y,already \\| escaped', {pad: 'compact'});
assert.equal(r.output, '| a | b |\n| --- | --- |\n| [[Note\\|Alias]] | ![[img.png\\|200]] |\n| x \\| y | already \\| escaped |');
assert.equal(r.escaped, 3);
assert.equal(r.wiki, 2);

// The page example.
const example = 'Page,Owner,Preview,Notes\n[[Project plan|Plan]],"Lee, Sam",![[img.png|200]],"Draft done\nReview on Friday"\n"Say ""hello""",Ana,,Ready to ship';
assert.ok(html.includes(example.replace(/\n/g, '\\n')));
r = api.run(example, {pad: 'compact', breaks: 'br'});
assert.equal(r.format, 'comma');
assert.equal(r.warnings.length, 0);
assert.equal(r.output.split('\n')[2], '| [[Project plan\\|Plan]] | Lee, Sam | ![[img.png\\|200]] | Draft done<br>Review on Friday |');
assert.equal(r.output.split('\n')[3], '| Say "hello" | Ana |  | Ready to ship |');

// Padding and alignment.
assert.equal(out('Name,Qty\nApple,3', {pad: 'pad', aligns: ['left', 'right']}),
  '| Name  |  Qty |\n| :---- | ---: |\n| Apple |    3 |');
assert.equal(out('a,b\nx,y', {aligns: ['center', 'none']}), '| a | b |\n| :---: | --- |\n| x | y |');
assert.equal(out('a,b\nx,y', {pad: 'pad', aligns: ['center', 'none']}), '|   a   | b   |\n| :---: | --- |\n|   x   | y   |');

// Header option adds an empty header row.
assert.equal(out('1,2', {header: false}), '|  |  |\n| --- | --- |\n| 1 | 2 |');

// Uneven rows: line-numbered warnings, padded with empty cells, widened.
r = api.run('a,b,c\n1,2\n3,4,5,6\n"x\ny",z,q', {pad: 'compact'});
assert.deepEqual(JSON.parse(JSON.stringify(r.warnings)), [
  {type: 'short', line: 2, found: 2, expected: 3, max: 4},
  {type: 'long', line: 3, found: 4, expected: 3, max: 4}]);
assert.equal(r.output.split('\n')[2], '| 1 | 2 |  |  |');
assert.equal(r.cols, 4);
assert.equal(api.run('a,b\n' + '1\n'.repeat(7), {}).warnings.slice(-1)[0].type, 'more');

// Markdown input: re-align, keep alignment colons, export CSV and TSV.
const md = '| Name | Qty |\n|:--|--:|\n| Apple | 3 |\n| [[N\\|A]] | a<br>b |';
r = api.run(md, {pad: 'pad'});
assert.equal(r.format, 'markdown');
assert.deepEqual(JSON.parse(JSON.stringify(r.aligns)), ['left', 'right']);
assert.equal(r.output, '| Name     |    Qty |\n| :------- | -----: |\n| Apple    |      3 |\n| [[N\\|A]] | a<br>b |');
assert.equal(api.run(md, {out: 'csv'}).output, 'Name,Qty\nApple,3\n[[N|A]],"a\nb"');
assert.equal(api.run(md, {out: 'tsv'}).output, 'Name\tQty\nApple\t3\n[[N|A]]\t"a\nb"');
assert.equal(api.run('a,b\n"x,y",z', {out: 'tsv'}).output, 'a\tb\nx,y\tz');
assert.equal(api.run('a,b\n"x,y",z', {out: 'csv'}).output, 'a,b\n"x,y",z');
// Round trip.
assert.equal(api.run(api.run('a,b\n"x\ny",[[N|A]]', {pad: 'compact'}).output, {pad: 'compact'}).output,
  '| a | b |\n| --- | --- |\n| x<br>y | [[N\\|A]] |');

// Markdown warnings with line numbers.
r = api.run('| a | b |\n| 1 | 2 |', {});
assert.deepEqual(JSON.parse(JSON.stringify(r.warnings)), [{type: 'no-delimiter', line: 2}]);
assert.equal(r.output.split('\n')[1].replace(/\s+/g, ''), '|---|---|');
r = api.run('| a | b |\n| --- | --- | --- |\n| 1 | 2 |', {});
assert.equal(r.warnings[0].type, 'delim-count');
assert.equal(r.warnings[0].line, 2);
r = api.run('| a | b |\n| --- | --- |\n| 1 | 2 |\n\n| 3 | 4 |\n| 5 |', {});
assert.deepEqual(JSON.parse(JSON.stringify(r.warnings)), [
  {type: 'blank', line: 4},
  {type: 'short', line: 6, found: 1, expected: 2, max: 2}]);

// Edge cases.
assert.equal(api.run('', {}).rows.length, 0);
assert.equal(api.run('  \n\n', {}).rows.length, 0);
assert.equal(out('only\nlines'), '| only |\n| --- |\n| lines |');
assert.equal(out('a,b\n\n\n1,2'), '| a | b |\n| --- | --- |\n| 1 | 2 |');
assert.equal(api.parseDelimited('a,b\n\n1,2', ',')[1].line, 3);
assert.equal(api.parseDelimited('a,"x\ny"\n1,2', ',')[1].line, 3);
assert.equal(out('a;b\n1;2', {delimiter: 'semicolon'}), '| a | b |\n| --- | --- |\n| 1 | 2 |');
console.log('ok');
'''


class MarkdownTableMakerTests(unittest.TestCase):
    def test_logic(self):
        node = shutil.which('node')
        if not node:
            self.skipTest('node is not installed')
        result = subprocess.run([node, '-e', HARNESS, str(GUIDE)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_page_is_self_contained(self):
        html = GUIDE.read_text(encoding='utf-8')
        script = re.search(r'<script>([\s\S]*)</script>', html).group(1)
        for needle in ('fetch(', 'XMLHttpRequest', 'sendBeacon', 'WebSocket', 'import(', 'importScripts', 'EventSource'):
            self.assertNotIn(needle, script)
        self.assertNotRegex(html, r'<script[^>]+src=')
        self.assertNotRegex(html, r'<link[^>]+rel="stylesheet"')
        self.assertIn('id="tb-nojs"', html)
        self.assertIn('class="mt-nojs"', html)
        for ident in re.findall(r'getElementById\(\'([^\']+)\'\)', script):
            self.assertIn('id="%s"' % ident, html)


if __name__ == '__main__':
    unittest.main()
