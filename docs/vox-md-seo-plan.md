# Vox.md SEO implementation plan

Audit date: October 26, 2026. Scope: public website at https://vox.isolated.tech/, its website/ source, current App Store listing, and primary Obsidian documentation. This document proposes changes; no production pages were changed or deployed.

## Recommendation

Build a focused acquisition cluster for **capturing into Obsidian from Apple devices**, starting with voice-to-daily-note and Apple Watch workflows. Adapt Vaultaire's process of useful search pages, comparisons, internal linking, measured app conversion, and selective localization. Prioritize a small set of demonstrably useful pages before scaling publishing volume.

Priorities below reflect product fit, purchase intent, available first-party proof, and production effort. They are not claims about measured keyword volume or difficulty. Search Console was unavailable during the initial audit; the [October 26 baseline](seo-baselines/2026-10-26/README.md) is now captured. Web conversion reports have not been accessed; App Store Connect Analytics was temporarily unavailable when opened.

### Implementation progress — October 26, 2026

First local implementation batch completed:

- Updated homepage positioning, free-allowance explanation, voice-to-Markdown example and contextual guide links.
- Added `/blog/voice-notes-to-obsidian-iphone/` with existing product screenshots, illustrative Markdown, local backend and file-provider requirements, native Obsidian options, metadata and breadcrumbs.
- Refreshed the existing keyboard guide's positioning, setup instructions, current screenshots and cross-links while preserving its URL.
- Linked the new article from the blog, documentation and `llms.txt`; added it to the sitemap.
- Replaced public recording-development notes with version-aware user instructions and limitations.
- Verified local links, fragments, JSON-LD, document landmarks and eight sitemap URLs. Inspected homepage and new guide at desktop and phone widths; fixed sticky-navigation overlap on guide anchors.

Second local implementation batch completed:

- Added the Apple Watch and daily-note routing guides, with contextual homepage, docs, blog and guide-to-guide links.
- Reused an existing Watch product screenshot and documented paired-iPhone transcription, queue recovery, daily path conventions, heading placement and task formatting.
- Moved the three new guides to editable sources under `website-content/guides/` and a shared renderer/template under `scripts/website/`. `npm run website:build` regenerates static deployable HTML; `npm run website:check` checks freshness, metadata, links, assets, fragments and sitemap coverage.

Search Console setup completed October 26: the canonical URL-prefix property is verified, the live sitemap was submitted successfully with 7 discovered URLs, and the existing parent property supplied a 90-day baseline of 2 clicks and 139 impressions. The latest 28 days have zero impressions. Homepage inspection reports Crawled — currently not indexed; a live test passed and Google accepted an indexing request. Prioritize index coverage and post-deployment inspection before evaluating content growth. Evidence and reporting limitations are in the dated baseline above.

Initial article set completed locally:

- Added the documented native Obsidian comparison and `/compare/` index, with explicit publisher disclosure, version/channel dates and no speed or accuracy benchmark claims.
- Added the iPhone capture-method decision guide linking to each detailed task guide.
- Added offline-transcription, links/photos/scans, and capture-template articles. The complete initial set now has eight generated pages: seven guides and one comparison, alongside the refreshed original keyboard article.
- Extended the shared renderer for validated comparison routes, Article schema and comparison breadcrumbs. `website:check` runs renderer and download-link tests. All 16 local pages and sitemap entries pass the static checks.

Download conversion preparation completed locally:

- Added a desktop-only QR disclosure beside the homepage download CTA. Apple Vision decoded the actual browser-rendered 176px QR to the correct direct App Store URL; phone layout hides the disclosure and has no horizontal overflow.
- Centralized page-specific campaign names and a separate QR campaign in `website-content/downloads.json`. All 16 pages use the shared download-link build/check pass.
- App Store Connect Analytics displayed a temporary-unavailability message. No verified provider token was available, so `verified_campaign_link` remains null and links stay direct. No campaign attribution or new website click telemetry is active.
- Added seven download-link tests, bringing the suite to 12 tests. Checks reject malformed campaign configuration, stale links, and mismatched QR destinations or assets. Activation instructions are in `scripts/website/README.md`.

Website changes are not deployed. Screenshots reuse existing assets; examples are explicitly illustrative, and app workflows were checked against repository documentation/source rather than newly tested on devices. The comparison cites current primary documentation and is not a hands-on benchmark. Device workflow review, deployment and campaign attribution remain pending. Search Console browser access is working; no API/OAuth connector or recurring monitor was configured. Broader comparisons, a template-builder tool and localization remain later experiments.

## Current-site findings

| Finding | Evidence | Implication |
| --- | --- | --- |
| Seven submitted URLs, one acquisition article | Live [sitemap](https://vox.isolated.tech/sitemap.xml), matching website/sitemap.xml | The main opportunity is focused content coverage, not a wholesale site rebuild. Submitted URLs do not establish indexation. |
| Useful foundation already exists | [Homepage](https://vox.isolated.tech/): server-delivered HTML, canonical, metadata, SoftwareApplication JSON-LD, optimized screenshot assets, ordinary anchor links | Retain the existing static site and improve it incrementally. Performance was not measured. |
| Hero has a broad promise | H1: “Capture Now. File It Exactly Where It Belongs.” | Explain Obsidian and the Apple-device audience in the visible headline. Title already mentions Obsidian; this is a clarity and conversion improvement, not a missing-title fix. |
| Strong workflows are buried in one large page | [Docs](https://vox.isolated.tech/docs/) combine setup, presets, models, keyboard, Watch, Mac and troubleshooting | Create distinct search answers with tested steps and examples, linking back to reference documentation. |
| Only article serves the older keyboard positioning | [Keyboard article](https://vox.isolated.tech/blog/best-voice-to-text-keyboard-iphone/) describes the main app as a standby recording surface, unlike the current composer-first homepage | Refresh screenshots and workflow claims. Its “best” title offers a broad category comparison rather than named, independently tested alternatives. |
| Public documentation contains release-internal material | [Docs](https://vox.isolated.tech/docs/#system-integrations) include a warning that unified recording changes are not ready for use/release and discuss beta/simulator decoding | Replace development detail with concise supported-version instructions and an honest limitation. Keep engineering investigation in repository notes. Do not market those actions before device verification. |
| Homepage obscures the commercial offer | Pricing FAQ sends readers to the App Store; docs explain free allowances and lifetime purchase | Surface 15 transcription minutes, 10 successful Capture deliveries, and one-time unlock. Confirm allowances against the shipping build. The [US listing](https://apps.apple.com/us/app/vox-md-quick-capture-notes/id6758967337) lists individual Unlimited at $9.99, Family Unlimited at $14.99, and Family Upgrade at $4.99. Clearly label US prices and allow regional differences. |
| Acquisition attribution is incomplete in inspected code | Homepage loads gated Cloudflare Web Analytics; its five App Store links have no campaign parameters; no outbound-download event found in inspected website source | Add aggregate CTA tracking and App Store campaign links so publishing decisions can use acquisition evidence. This does not establish what reports exist elsewhere. |

The established canonical host is vox.isolated.tech. Keep it during this work. The repository has a path-preserving redirect worker for the old voxboard.isolated.tech hostname; verify its live behavior during implementation. A Vox.md product name does not require a domain migration. Availability and ownership of the literal vox.md domain were not established.

## Competitive change that shapes the plan

[Obsidian's current iOS guide](https://obsidian.md/help/ios) describes native Quick Capture, daily-note placement, templates, widgets and Shortcuts. It requires Obsidian 1.14+ and iOS/iPadOS 26+. The [October 22 Obsidian 1.15 mobile early-access changelog](https://obsidian.md/changelog/2026-10-22-mobile-v1.15.0/) adds live voice transcription, Lock Screen capture, and saved recordings on iOS 26.

Every comparison should state version, release channel and test date. The argument cannot be that Obsidian has no quick capture, widgets, daily-note routing or voice capture. Test the actual differences: Vox.md's multi-input capture, preset behavior, heading insertion, choice of local speech engines, Watch-to-iPhone delivery, and earlier OS support with feature-specific requirements. Give readers an explicit “when built-in Obsidian is enough” answer.

## Phase 0: improve existing pages and measurement

Complete in the first two working days, before expanding the content queue.

### Homepage: /

- Proposed title: **Quick capture for Obsidian on iPhone and Apple Watch | Vox.md**.
- Proposed H1: **Capture ideas into Obsidian from iPhone, Mac, and Apple Watch.**
- Proposed supporting copy: “Save text, voice, links, photos, scans, and files to the note or heading you choose. Vox.md writes Markdown to your folder, with voice transcription on your device.”
- Primary CTA: **Download Vox.md free**. Explain the free allowances and one-time unlock nearby; do not imply unlimited free use.
- Add an actual phone-to-Markdown example: short spoken input, selected Daily Note preset, and final file/heading output. Identify any model or OS requirement.
- Link visibly to the first three tutorials once published: voice notes, Apple Watch, and daily-note routing. Add the comparison link when ready.
- Add a desktop QR download option generated from the same campaign link. Use existing screenshots and truthful proof; do not invent testimonials, speed or accuracy claims.
- Keep privacy language precise: transcription is local; choosing a cloud-backed destination can sync the resulting files. Avoid claiming universal offline delivery to unavailable file providers.

### Docs: /docs/

- Keep existing URLs and anchor IDs. Improve the existing page first; do not split all reference material into thin pages.
- Put a short first-capture checklist and links to workflow tutorials near the top.
- Remove or rewrite release-internal implementation notes into supported user behavior and current limitations.
- Use docs for controls, compatibility and troubleshooting. Use blog guides for the complete user task. Avoid copying the entire docs section into each guide.

### Existing keyboard article

Keep /blog/best-voice-to-text-keyboard-iphone/ to preserve its existing URL. Update to the current composer and keyboard setup; explain Full Access, main-app coordination, secure fields/apps where custom keyboards are unavailable, local backend preparation, and reviewed-text expectations. Replace stale screenshots. Either substantiate the existing “best” angle with named options tested under the same conditions, or use an accurate title such as “Private voice-to-text on iPhone: keyboard setup and options” while retaining the URL. Add links to the voice-to-Obsidian and offline guides.

### Measurement and publishing foundation

- Verify a Search Console property for the canonical site, inspect the homepage and article, submit the current sitemap, and export the previous 90 days by page/query/country/device as a baseline. Property/report availability is an implementation prerequisite, not established by this audit.
- Track aggregate app_store_click with stable page slug, CTA position (header, answer, middle, footer, QR), and device class. Never send captured note text, transcripts, local file paths, preset contents or tool inputs.
- Create App Store campaign links in App Store Connect, using stable tokens such as seo_voice_obsidian and seo_watch_obsidian; generate the provider token from the account rather than inventing one. Campaign attribution is aggregated and subject to Apple's thresholds/windows; a web click is not an install or purchase. See [Apple campaign documentation](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links).
- Keep the site static. Add one shared article/layout source and metadata manifest to generate title, canonical, related links and sitemap entries; a small build script is sufficient. Avoid copying headers and tracking scripts across dozens of independent HTML files.
- Set lastmod only on substantial updates. Validate canonical URLs, relative assets, structured data and internal links as part of each build. See [Google sitemap guidance](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap).

## Ordered new-page backlog

Paths below are proposed under https://vox.isolated.tech. Retain /blog/ as the article directory to avoid an unnecessary migration. Effort is a planning estimate in focused working days and includes writing, screenshots and workflow verification; wait time for review is excluded.

| Order | Proposed path and page title | Query intent | Why now / required proof | Effort |
| --- | --- | --- | --- | ---: |
| 1 | /blog/voice-notes-to-obsidian-iphone/ — **How to save iPhone voice notes to Obsidian** | obsidian voice notes iphone; voice to text obsidian | Closest voice-to-file product fit. Show vault setup, local backend, a recording, and resulting Markdown. Explain native Obsidian and imported audio options. | 1–2 days |
| 2 | /blog/apple-watch-obsidian-voice-notes/ — **Send Apple Watch voice notes to Obsidian** | apple watch obsidian; watch voice notes to markdown | Specific device workflow with strong fit. Demonstrate Watch recording, queued transfer to iPhone, transcription, and final note. Show phone-unavailable and retry behavior; do not imply standalone Watch transcription. | 1–2 days |
| 3 | /blog/append-to-obsidian-daily-note-iphone/ — **Append text and voice to an Obsidian daily note on iPhone** | append to obsidian daily note iphone; dictate daily note | Makes preset routing concrete. Show rolling filename, Tasks/Ideas heading, entry formatting, two successive captures and final file. Explain built-in Obsidian's supported append/prepend alternative. | 1 day |
| 4 | /compare/vox-md-vs-obsidian-quick-capture/ — **Vox.md vs Obsidian Quick Capture: which workflow fits?** | vox md vs obsidian; obsidian quick capture alternative | Timely objection handling. Test stable 1.14 and label 1.15 early access separately; include fair built-in-is-enough guidance. Compare versions, input types, Watch, local engines, routing, price and setup. | 1–2 days |
| 5 | /blog/obsidian-quick-capture-iphone/ — **Quick capture into Obsidian on iPhone: built-in tools, Shortcuts, and Vox.md** | obsidian quick capture iphone | Main cluster hub, published once supporting tutorials exist. A decision guide comparing approaches, not another setup guide for the same Vox.md workflow. Link to pages 1–4. | 1–2 days |
| 6 | /blog/offline-transcription-iphone-markdown/ — **Transcribe audio to Markdown offline on iPhone** | offline transcription iphone; audio to markdown | Adjacent privacy audience with direct product fit. Verify an airplane-mode example after backend setup and local-folder readiness. State language/device differences, model download needs and sync limitations. | 1–2 days |
| 7 | /blog/save-links-photos-obsidian-iphone/ — **Save links, photos, and scans to Obsidian from iPhone** | save photos obsidian iphone; share to obsidian | Proves capture beyond voice. Demonstrate Share Sheet, photo embed and OCR output. Compare native sharing fairly; distinguish a saved URL from full web article extraction. | 1–2 days |
| 8 | /blog/obsidian-capture-templates/ — **Obsidian capture templates for an inbox, daily journal, and task list** | obsidian capture templates; daily note capture template | A reusable resource that strengthens pages 1–3. Include copyable valid Markdown/YAML, sample input/output and exact token semantics. Distinguish Vox.md tokens from Obsidian/plugin syntax. | 1 day |

Create a lightweight /compare/ hub with the first comparison, linked from homepage and articles. Expand only when there are substantive comparisons to list. Expand /blog/ into a useful guide index grouped by Getting Started, Voice & Watch, Routing & Templates, and Private Transcription; remove “First Guide Live” once it no longer applies.

### Prevent overlap

- Homepage owns the product/category promise and app conversion.
- Quick-capture hub owns the choice between methods.
- Voice guide owns iPhone audio-to-note setup.
- Watch guide owns wrist-to-note handoff.
- Daily-note guide owns filename, heading and append behavior.
- Comparison owns version-specific product evaluation.
- Docs own setting definitions and reference details.

Combine close query variants in those pages. Do not create separate near-duplicates for “voice notes Obsidian iOS,” “Obsidian dictation iPhone,” and “speech to Obsidian iPhone” without evidence of distinct needs.

## Four-week delivery schedule

| Week | Deliverable | Exit condition |
| --- | --- | --- |
| 1 | Phase 0 improvements, reusable article layout, guide 1, and guide 2 if device evidence is ready | Baseline captured; click/campaign attribution configured; tested input-to-Markdown examples; published URLs work and are linked. |
| 2 | Finish guide 2, guide 3, native Obsidian comparison, comparison hub | Actual Watch handoff and routing proof; competitor version/channel labels; fair comparison sourced to official docs. |
| 3 | Quick-capture hub and offline guide; strengthen links among all first-wave pages | No duplicate primary intent; airplane-mode test and supported-version notes; each page reachable from a hub. |
| 4 | Mixed-media guide and template resource; refresh promising existing pages using the first data | Eight new substantive pages plus hubs completed if verification permits; early indexation checked; prioritize next sprint from observed queries rather than a fixed publishing quota. |

This is a roughly 12–16 focused-day content program plus foundation work. Adjust pace for real-device testing and evidence capture; do not publish unverified features to meet a date.

## Page acceptance checklist

Each guide needs an original screenshot/short demonstration, a clear answer near the top, tested numbered steps, real input and final Markdown output, prerequisites and limitations, a named author and accurate review date, one primary app-download action, and contextual links to two or three genuinely relevant pages. A modest “Download Vox.md free” CTA belongs after the initial useful answer and at the end; it should not obscure the instructions.

Titles and H1s should reflect the task; descriptions should explain the result. Add appropriate Article and BreadcrumbList data when their fields match the visible content. Structured data supports interpretation, not guaranteed ranking or rich results. See [Google Article guidance](https://developers.google.com/search/docs/appearance/structured-data/article). Do not add FAQ/HowTo markup merely to imitate Vaultaire's schema count.

Verify release availability against the App Store version and tested devices, not only repository README claims. In particular, do not promise unverified Action Button background recording, independent Watch transcription, universal languages, or cloud-free file synchronization.

## Linking and distribution

Add contextual homepage links beside voice, Watch, routing and privacy sections, not only a footer list. Link the quick-capture hub to each detailed method; link each method back to the decision guide where useful. Link the comparison from both the hub and voice guide. Each article should link directly to the relevant docs anchor. Related links should be rendered in HTML.

After publication, prepare useful, factually specific demonstrations for existing Obsidian community discussions and directory listings. Publish or message externally only under separate user authorization. Prioritize assets others may cite—working templates, tested setup instructions, and reproducible local-processing examples—over generic backlink submissions. Maintain any existing old-brand links through redirects rather than abandoning them.

## Later experiments

**Next comparisons:** Quick Capture for Obsidian, Drafts, and a current voice-first option. Research/test each before choosing a page; do not assume cloud dependence, missing exports or subscription pricing. One well-evidenced page is more valuable than many unsupported “vs” pages.

**First possible tool:** /tools/markdown-capture-template-builder/ after the template guide demonstrates interest. Generate an inbox, daily-entry or task-list template and preview example Markdown locally, with copy/download. Never upload user text. Do not claim it imports directly into Vox.md presets unless that feature exists and is tested. Give it a real explanatory page and link to the routing tutorial; keep arbitrary input states out of the index. Do not build generic image converters or a browser transcription service as this first SEO experiment.

**Localization:** begin only after identifying useful country/language demand in Search Console and App Store reporting. Pilot the homepage and best-performing guide in one locale with verified product-language support and human language review. Add reciprocal hreflang, translated titles, self-canonicals and localized navigation. Measure before adding another locale. The current app listing has many supported languages; this alone does not prove translated-site search demand.

**Defer:** broad “best note-taking apps” roundups, generic meeting/medical/legal scenario pages, mass comparison generation, domain migration, and hundreds of translated articles. Capture the specific Apple/Obsidian workflows first.

## Weekly operating loop and decision rules

Review weekly; use 28-day page/query trends and longer windows when volume is low. Separate branded Vox.md/Voxboard queries from nonbranded terms. Group synonyms before making new pages.

1. Inspect indexing for newly published canonical URLs. If not indexed, check fetchability, canonical selection, content distinctiveness and internal links before publishing more near-identical pages.
2. For relevant queries receiving impressions around positions 5–20, improve the page's actual answer, example or coverage. This is a candidate heuristic, not a prediction of gains.
3. When relevant impressions rise but clicks lag, evaluate position, SERP layout and title/description fit together. Zero clicks on a tiny sample is not sufficient evidence to commission another page.
4. When visits rise but download clicks lag, improve the task-specific demo, offer, compatibility explanation and CTA placement.
5. When App Store campaign traffic produces downloads but few purchases, inspect store/onboarding/product fit where aggregated reporting permits. Do not infer user-level attribution or purchases from website clicks.
6. Create the next page only when a recurring query/problem requires a distinct answer. Otherwise strengthen the existing canonical page.

Dashboard: indexed/submitted URLs, nonbranded impressions and clicks by cluster, landing-page visits, app-download click rate, campaign-attributed downloads, and campaign sales where Apple reports them. Show numerators and denominators, reporting delays and attribution limitations. First-month success means shipping the coherent cluster, working measurement, and evidence of discovery—not a promised traffic or revenue total. Review commercial impact at 60–90 days and expand the cluster with the best evidence.
