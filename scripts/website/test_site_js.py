"""Run actual site event handlers with a minimal DOM (Node stdlib only)."""
from pathlib import Path
import shutil
import subprocess
import unittest


@unittest.skipUnless(shutil.which('node'), 'Node is required for website JavaScript tests')
class SiteBehaviorTests(unittest.TestCase):
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

    def test_scroll_spy_reveals_active_phone_chip_in_both_directions(self):
        source = Path(__file__).resolve().parents[2]/'website/site.js'
        script = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[1], 'utf8');
for (const rtl of [false, true]) {
  let movement = null;
  const list = {
    clientWidth: 300, scrollWidth: 900, scrollLeft: 0, offsetLeft: 0,
    getBoundingClientRect() { return {left: 0, right: 300}; },
    scrollTo({left}) { movement = left; },
    scrollBy({left}) { movement = left; }
  };
  const links = ['one', 'two'].map((id, i) => {
    const left = i === 0 ? 0 : rtl ? -200 : 450;
    return {
      attributes: {}, offsetLeft: left, offsetWidth: 120,
      getAttribute() { return '#' + id; },
      setAttribute(name, value) { this.attributes[name] = value; },
      removeAttribute(name) { delete this.attributes[name]; },
      addEventListener() {},
      getBoundingClientRect() { return {left, right: left + 120}; }
    };
  });
  const nav = {querySelectorAll() { return links; }, querySelector() { return list; }};
  const document = {
    readyState: 'complete', documentElement: {dir: rtl ? 'rtl' : 'ltr', scrollHeight: 4000},
    querySelector() { return nav; },
    getElementById(id) { return id === 'one' || id === 'two' ? {getBoundingClientRect() { return {top: id === 'one' ? -1000 : 0}; }} : null; }
  };
  const window = {innerHeight: 800, scrollY: 1000, addEventListener() {}};
  vm.runInNewContext(source, {document, window}, {filename: 'website/site.js'});
  assert.equal(links[1].attributes['aria-current'], 'true');
  assert(rtl ? movement < 0 : movement > 0, 'active chip must reveal toward its clipped edge; rtl=' + rtl + ', movement=' + movement);
}
'''
        result = subprocess.run(['node','-e',script,str(source)],text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_turkish_search_matches_native_case_and_literal_api_terms(self):
        source = Path(__file__).resolve().parents[2]/'website/site.js'
        script = r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[1], 'utf8');
const handlers = {};
function node() {
  return {
    children: [], attributes: {}, textContent: '',
    appendChild(child) { this.children.push(child); },
    setAttribute(k, v) { this.attributes[k] = v; },
    removeAttribute(k) { delete this.attributes[k]; },
    addEventListener() {}, scrollIntoView() {}
  };
}
const input = Object.assign(node(), {value: '', closest() { return null; }, addEventListener(k,v) { handlers[k] = v; }});
const results = node();
Object.defineProperty(results, 'innerHTML', {set() { this.children = []; }});
results.querySelectorAll = function () { return this.children.flatMap(li => li.children).filter(a => a.attributes.role === 'option'); };
const headings = ['İzinler ve sistem erişimi', 'API', 'Işık'].map((title, i) => ({
  id: 'heading-' + i, textContent: title, tagName: 'H3', nextElementSibling: null,
  closest() { return {id: 'section', querySelector() { return null; }}; }
}));
const document = {
  readyState: 'complete', documentElement: {lang: 'tr', dataset: {}},
  querySelector() { return null; },
  querySelectorAll(selector) { return selector.includes('h3[id]') ? headings : []; },
  getElementById(id) { return id === 'docs-search-input' ? input : id === 'docs-search-results' ? results : null; },
  createElement() { return node(); }, addEventListener() {}
};
vm.runInNewContext(source, {document, window: {}}, {filename: 'website/site.js'});
for (const [query, expected] of [['izinler', headings[0].textContent], ['api', 'API'], ['ışık', 'Işık']]) {
  input.value = query; handlers.input();
  const options = results.querySelectorAll();
  assert.equal(options.length, 1, query + ' must match its native/code heading');
  assert.equal(options[0].children[0].textContent, expected);
}
'''
        result = subprocess.run(['node','-e',script,str(source)],text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)


if __name__ == '__main__':
    unittest.main()
