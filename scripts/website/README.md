# Static guide publishing

The deployed site remains plain HTML in `website/`. New capture guides share
`scripts/website/templates/guide.html`; their editable sources are in
`website-content/guides/`.

## Localized pages

`build_locales.py` owns generated English and localized HTML, the sitemap and
language discovery entries in `llms.txt`. Edit static English pages under
`website-content/pages/`, or guide sources and the guide template described
below, rather than editing generated HTML under `website/`.

English segments are deduplicated plain-text strings with content-derived IDs
in `website-content/locales/en.json`. Text nodes, accessible labels, image alt
text, social metadata and JSON-LD prose are extracted; executable code, sample
files, HTML markup, paths and template tokens remain literal. Translation files
have `metadata` and `strings` objects. Every non-English catalog must declare
`"status": "requires-human-review"` and `"source": "machine"`; these are machine
drafts, not claims of human approval.

To change copy, edit the English source, refresh `en.json`, then translate every
new/changed key and remove obsolete keys in every catalog. If editing the
catalog directly, make the same copy change in its English source: the check
rejects source/catalog drift. Unchanged copy retains its ID even when moved.

```sh
python3 scripts/website/build_locales.py --extract
python3 scripts/website/build_locales.py --check-catalog ja
npm run website:build
npm run website:check
```

The catalog validator only reads files; it never renders or writes `website/`.
It rejects missing/extra/duplicate keys, invalid JSON, incorrect review metadata,
changed protected names, URLs, paths, placeholders or Markdown/code syntax,
and unchanged English except explicit source-owned literal/name allowances.
`en.json` also owns locale-specific identity allowances: short, explicitly
translated app labels whose shipped wording is English, plus individually
confirmed lexical identities (for example Spanish `Ideas`). These are not a
locale-controlled bypass or a fallback for long untranslated prose.
Literal tutorial headings/routes (`Inbox`, `Tasks`, `Daily Inbox`) must remain
exactly aligned with unchanged sample code and named route examples, rather
than borrowing unrelated translated app controls. The homepage heading has an
independent full-sentence accessible-label segment, so every language can use
natural grammar without inheriting the visible strike-through markup's word
order.
Follow `docs/localization-glossary.md` and reuse shipped app UI labels exactly.
A changed source can require translation review even if adjacent string IDs do
not change. Inline text segments should be reviewed in page context.

URLs use lowercase BCP-47 prefixes (`/pt-br/blog/<slug>/`, `/zh-hant/docs/`),
while English retains its existing paths and legal `.html` canonicals. The
former hand-maintained `/zh-hans/` home uses the same generator. Assets and
sample code stay shared. Plain-link nav/footer switchers target the equivalent
page; canonical, reciprocal hreflang, social metadata, JSON-LD language, sitemap
alternates, and the deployment builder's Markdown/documents routes agree.
Arabic and Urdu are RTL; code and literal file examples remain LTR.

New pages need an English campaign mapping in `website-content/downloads.json`.
Then explicitly add deterministic per-locale campaign names (not Apple provider
tokens) before rebuilding:

```sh
python3 scripts/website/build_locales.py --sync-campaigns
```

Normal production builds require all 23 catalogs; missing translations never
fall back to English. During initial development only,
`VOX_WEBSITE_PILOT=ja npm run website:build` and the same environment on checks
render an isolated English/Japanese pilot. Do not deploy pilot output. A full
build must be run without this environment before review or release.

The external `search-chinese-landing-pages` Cloudflare Worker routes on
`vox.isolated.tech/` and `/sitemap.xml*` must be removed before or immediately
after merging the localized site. Otherwise injected alternates/sitemap data
can differ from the validated artifact and the exact release check will fail.
No Cloudflare changes are made by this build. Preserve the Naver verification
meta tag in the English homepage source; it already matches the live tag.

## Guide sources

Each source starts with a JSON metadata comment, followed by the article body
as HTML. Its filename must match the metadata slug. Edit those sources rather
than the generated `website/blog/<slug>/index.html` files. Comparison sources
set `"section": "compare"` to render to `website/compare/<slug>/index.html`
with Article schema and comparison breadcrumbs. Other section names are rejected.

```sh
npm run website:build
npm run website:check
```

Python 3.9 or later is required; normal builds and checks need no additional packages. The build
renders title and social metadata, canonical URL, author/date, navigation,
article schema and breadcrumbs. The download-link pass also updates App Store anchors across the static site.
The check command runs the renderer and download-link tests, rejects stale
generated guides and checks all deployed HTML
for metadata, local links and assets, anchor targets and sitemap coverage.

When adding a guide, also add contextual links to the blog index and relevant
product/docs sections, add its entry to the blog's JSON-LD and the sitemap,
and update `llms.txt`. These editorial placements are intentionally explicit;
the renderer does not decide which content is related.

Serve `website/` locally for browser inspection. Check phone and desktop widths,
anchor navigation, images and sample Markdown. Generated HTML and referenced
assets must be committed together. Use real publication and substantive-change
dates; mark illustrative examples clearly and verify app behavior separately
before claiming that a device workflow was tested.

## Download campaigns and desktop QR

`website-content/downloads.json` owns the app URL, each page's campaign name,
and a separate `seo_home_qr` campaign. Add a unique campaign mapping when adding
a page. Campaign names are limited to 30 characters.

Attribution is currently disabled: `verified_campaign_link` is `null`, so every
button and QR opens the direct App Store URL. The campaign data attributes do
not collect events. This implementation adds no telemetry requests.

To enable attribution, copy a real Vox.md campaign link from App Store Connect
Analytics into `verified_campaign_link`. It must contain Apple's `pt`, `ct` and
`mt=8` parameters. Never invent a provider token. The build reuses that provider
with the configured per-page campaign names. Apple reports campaign acquisition
subject to its delays and privacy thresholds; these are not website click counts.
See [Apple's campaign documentation](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links).

After changing the destination, regenerate the committed QR locally with a Python
runtime containing ReportLab, then rebuild and check:

```sh
python3 scripts/website/generate_download_qr.py
npm run website:build
npm run website:check
```

ReportLab is required only for QR regeneration. The SVG and its destination/hash
sidecar are committed together; ordinary checks reject a stale QR. No remote QR
service is used. Decode a browser-rendered QR after regeneration and verify the
full destination. On October 26, Apple Vision successfully decoded the rendered
176px QR to the direct Vox.md App Store URL. Desktop disclosure and 390px phone
layout were checked; the QR disclosure is hidden on phones.

The deployment script also runs `scripts/build-website.py`, preserving the inline
CSS, Markdown negotiation and read-only discovery API introduced on main. The
site check covers extensionless public pages and excludes the noindex 404 page
from sitemap requirements. Full localization covers 506 HTML pages (22 per language) and 483 sitemap
URLs (21 indexable pages per language). The noindex 404 pages are excluded.


## Cloud publishing

`.github/workflows/website-publish.yml` validates website changes on pull requests.
After a checked merge to `main`, it builds once, deploys and verifies a preview,
then publishes the same artifact to the existing Pages project `voxboard` and
checks production HTML, canonical metadata, sitemap and public asset bytes.
A dispatch on `main` verifies and republishes that revision. Publishing is
serialized and refuses a main revision that has been superseded. The build
uses Node24/Python3.12; Wrangler is pinned to4.156.0.

GitHub Actions needs repository secret `CLOUDFLARE_API_TOKEN` with Pages Edit
for the owning account, and repository variable `CLOUDFLARE_ACCOUNT_ID`. Never
commit credentials. Secrets are available only to main-branch publishing steps;
pull requests validate without deployment access. Deployment runs from the
runner's temporary directory, preserving existing dashboard runtime/bindings
rather than applying unrelated repository deployment configuration or D1 migrations.

Keep the previous production deployment for rollback. Do not bypass checks or
publish a source checkout missing content, locale/legal pages or privacy
protections already live. The source checkpoint for this setup preserves that
published baseline; subsequent changes must update owning generators and their
committed output together. A successful deploy does not prove Google indexing
or qualified downloads.
