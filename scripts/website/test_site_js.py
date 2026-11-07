"""Run the actual docs-search event handler with a minimal DOM (Node stdlib only)."""
from pathlib import Path
import shutil
import subprocess
import unittest


@unittest.skipUnless(shutil.which('node'), 'Node is required for website JavaScript tests')
class DocsSearchTests(unittest.TestCase):
    def test_localized_empty_result_preserves_literal_query_characters(self):
        source = Path(__file__).resolve().parents[2]/'website/site.js'
        script = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[1], 'utf8');
for (const localized of [false, true]) {
  const handlers = {};
  const input = {
    value: '', addEventListener(name, handler) { handlers[name] = handler; },
    setAttribute() {}, removeAttribute() {}, closest() { return null; }
  };
  const results = {
    children: [], hidden: true,
    set innerHTML(value) { this.children = []; },
    appendChild(child) { this.children.push(child); },
    querySelectorAll() { return []; }
  };
  const document = {
    readyState: 'complete',
    documentElement: { dataset: localized ? {searchEmpty: '「{query}」に一致する結果はありません'} : {} },
    querySelector() { return null; }, querySelectorAll() { return []; },
    getElementById(id) { return id === 'docs-search-input' ? input : id === 'docs-search-results' ? results : null; },
    createElement() { return {textContent: '', className: ''}; }, addEventListener() {}
  };
  vm.runInNewContext(source, {document, window: {}}, {filename: 'website/site.js'});
  for (const query of ['$&', '$`', "$'", '$$', '<script>', '日本語']) {
    input.value = query;
    handlers.input();
    const expected = localized ? '「' + query + '」に一致する結果はありません' : 'No matches for “' + query + '”';
    assert.equal(results.children.length, 1);
    assert.equal(results.children[0].textContent, expected);
  }
}
'''
        result = subprocess.run(['node','-e',script,str(source)],text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)


if __name__ == '__main__':
    unittest.main()
