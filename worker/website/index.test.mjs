import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createWebsiteHandler, prefersMarkdown } from './index.mjs';

const data = { product: { name: 'Vox.md', url: 'https://vox.isolated.tech/' }, documents: [{ title: 'Guide', url: 'https://vox.isolated.tech/docs/' }] };
const fetch = createWebsiteHandler({ '/': '/index.md', '/docs/': '/docs/index.md' }, data);
const env = { ASSETS: { async fetch(request) {
  const path = new URL(request.url).pathname;
  if (path === '/index.md' || path === '/docs/index.md') return new Response('# Vox.md\n\nLocal capture for Markdown.', { headers: { 'Content-Type': 'text/plain', Vary: 'Accept-Encoding' } });
  if (path === '/') return new Response('<main><h1>Vox.md</h1></main>', { headers: { 'Content-Type': 'text/html', Vary: 'Accept-Encoding' } });
  if (path === '/app-icon.webp') return new Response(new Uint8Array([1, 2, 3]), { headers: { 'Content-Type': 'image/webp' } });
  return new Response('<h1>Page not found</h1><a href="/docs/">Documentation</a>', { status: 404, headers: { 'Content-Type': 'text/html' } });
} } };
const request = (path, accept = '*/*', method = 'GET') => new Request('https://vox.isolated.tech' + path, { method, headers: { Accept: accept } });

test('negotiates explicit Markdown and honors media quality', () => {
  assert.equal(prefersMarkdown('text/markdown'), true);
  assert.equal(prefersMarkdown('text/html;q=0.5, text/markdown;q=1'), true);
  for (const accept of ['*/*', 'text/html', 'text/markdown;q=0', 'text/markdown;q=2', 'text/html;q=1,text/markdown;q=0.5']) assert.equal(prefersMarkdown(accept), false, accept);
});

test('serves main content as Markdown for homepage and nested docs', async () => {
  for (const path of ['/', '/docs/']) {
    const response = await fetch(request(path, 'text/markdown'), env);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('Content-Type'), /^text\/markdown/);
    assert.equal(response.headers.get('Vary'), 'Accept-Encoding, Accept');
    assert.match(await response.text(), /^# Vox.md/);
  }
});

test('HTML stays HTML and binary assets stay binary', async () => {
  const html = await fetch(request('/', 'text/html'), env);
  assert.match(html.headers.get('Content-Type'), /text\/html/);
  assert.match(await html.text(), /<h1>/);
  const image = await fetch(request('/app-icon.webp'), env);
  assert.equal(image.headers.get('Content-Type'), 'image/webp');
  assert.equal((await image.arrayBuffer()).byteLength, 3);
});

test('missing documents return actual 404 and Markdown recovery links', async () => {
  for (const accept of ['text/html', 'text/markdown']) {
    const response = await fetch(request('/missing-page', accept), env);
    assert.equal(response.status, 404);
    assert.match(response.headers.get('Content-Type'), new RegExp(accept));
    assert.match(await response.text(), /docs/);
  }
});

test('missing API URLs and JSON requests return structured 404 errors', async () => {
  for (const [path, accept] of [['/api/capture', '*/*'], ['/missing', 'application/json']]) {
    const response = await fetch(request(path, accept), env);
    assert.equal(response.status, 404);
    assert.match(response.headers.get('Content-Type'), /application\/problem\+json/);
    assert.match((await response.json()).resolution, /no public capture API/);
  }
});

test('HEAD and unsupported methods preserve HTTP semantics', async () => {
  for (const path of ['/', '/missing', '/api/missing']) {
    const response = await fetch(request(path, 'text/markdown', 'HEAD'), env);
    assert.equal(await response.text(), '');
  }
  const response = await fetch(request('/', '*/*', 'POST'), env);
  assert.equal(response.status, 405);
  assert.equal(response.headers.get('Allow'), 'GET, HEAD');
  assert.equal((await response.json()).code, 'method_not_allowed');
});

 test('public information API returns product facts and document links without credentials', async () => {
  for (const [path, expected] of [['/api/v1/product', data.product], ['/api/v1/documents', { documents: data.documents }]]) {
    const response = await fetch(request(path), env);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
    assert.deepEqual(await response.json(), expected);
    const head = await fetch(request(path, '*/*', 'HEAD'), env);
    assert.equal(head.status, 200);
    assert.equal(await head.text(), '');
  }
});
