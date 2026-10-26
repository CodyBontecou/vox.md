# Website agent readiness

The deployed site uses the Pages advanced-mode Worker in
`worker/website/index.mjs`. The website build embeds the actual document routes
and public product metadata, then deploys the module as `_worker.js`.

The HTTP contract:

- GET and HEAD read public documents. Other methods return HTTP 405.
- HTML remains the default representation. An explicit `Accept: text/markdown`
  request selects the generated main content, respecting the HTML preference
  when media quality values differ. Both responses include `Vary: Accept`.
- A root `404.html` prevents Cloudflare Pages from returning the homepage for
  nonexistent paths. Missing Markdown documents return 404 with recovery links.
- Unknown API URLs return `application/problem+json`, with a code, explanation,
  requested path, and recovery hint.
- `/api/v1/product` exposes public product facts derived from homepage JSON-LD.
- `/api/v1/documents` lists public document titles, summaries, and URLs.
- `/openapi.json` describes those two read-only operations. `/developers`
  contains usage examples, cache behavior, methods, and error documentation.
- The public API has no authentication or private data access. Capture,
  transcription, note writes, and vault access remain installed app operations.

The source HTML remains authoritative. `scripts/website_markdown.py` generates
Markdown during the normal build, including relative-link resolution and code
block whitespace. The build derives the document index from the same HTML.
Full-size fonts and screenshot directories retain direct static asset delivery.

Run focused checks:

```sh
node --test worker/website/index.test.mjs
python3 -m unittest discover -s scripts/tests -p test_website_markdown.py
```

Check the live representations:

```sh
curl -i -H 'Accept: text/markdown' https://vox.isolated.tech/
curl -i -H 'Accept: text/html' https://vox.isolated.tech/
curl -i -H 'Accept: text/markdown' https://vox.isolated.tech/missing-page
curl https://vox.isolated.tech/api/v1/product
curl https://vox.isolated.tech/api/v1/documents
```

Use the Rescan control on [Is Agentic](https://is-agentic.com/scan/vox.isolated.tech)
after deployment. Its public API and CLI read archived snapshots; a previously
completed result can remain visible while the new scan is being archived.
