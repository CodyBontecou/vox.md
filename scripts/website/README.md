# Static guide publishing

The deployed site remains plain HTML in `website/`. New capture guides share
`scripts/website/templates/guide.html`; their editable sources are in
`website-content/guides/`.

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
from sitemap requirements. After integration, 21 HTML pages and 20 sitemap URLs
are checked.
