# Vaultaire SEO analysis

Observed October 26, 2026. This is a public-site audit, not access to Vaultaire's analytics or Search Console.

## Main finding

Vaultaire operates a broad search acquisition funnel around a narrow app category: informational guides, competitor comparisons and reviews, specific personal scenarios, free browser tools, and localized versions. The strongest reproducible idea is matching a page to a concrete user problem and giving that reader a relevant path to the app.

## Scale observed

The [sitemap index](https://vaultaire.app/sitemap.xml) references [sitemap 1](https://vaultaire.app/sitemap-1.xml) and [sitemap 2](https://vaultaire.app/sitemap-2.xml). Parsing both returned **7,550 unique URLs across 32 language/locale versions**. These are submitted URLs, not a verified count of indexed or ranking pages.

The 250 English URLs break down as follows; section counts include their hub pages:

| Section | URLs |
| --- | ---: |
| Guides | 122 |
| Scenarios | 44 |
| Comparisons and reviews | 33 |
| Tools and supporting tutorials | 31 |
| Features | 13 |
| Homepage and other pages | 7 |

Localization is broader than translated navigation. The [German homepage](https://vaultaire.app/de/) has translated main content. Homepage HTML declares 32 language/locale alternatives plus x-default using hreflang. This can help search engines route users to the appropriate version; it does not prove that every translation is good, indexed, or attracting traffic. See [Google's localized-page guidance](https://developers.google.com/search/docs/specialty/international/localized-versions).

## How the content captures demand

1. **Problems before product awareness.** [How to hide photos on iPhone](https://vaultaire.app/guides/hide-photos-iphone/) addresses a task people already search for. Other sitemap topics address hidden photos in iCloud, forgotten vault passwords, transfers to a new phone, and photo access permissions. These are more specific entry points than expecting everyone to search for the brand.
2. **Commercial evaluation.** The [best photo vault apps guide](https://vaultaire.app/guides/best-photo-vault-apps-iphone/) includes a quick answer, comparison tables, pricing, pros and cons, evaluation criteria, and related guides. The [comparison hub](https://vaultaire.app/compare/) links to 16 competitors; the sitemap includes both comparison and review routes. These serve buyers evaluating alternatives. The publisher sells the product it ranks first: claims about competitors require independent checking.
3. **Situational intent.** [Partner knows my iPhone passcode](https://vaultaire.app/scenarios/partner-knows-iphone-passcode/) addresses an immediate problem and places an app download link near the opening answer. The scenario section extends to family devices, repair shops, photo handoffs and other concrete situations.
4. **Tools as acquisition pages.** The [tools hub](https://vaultaire.app/tools/) lists 12 utilities, including metadata removal, face redaction, compression, resizing, conversion, and QR creation, with supporting tutorials. The [metadata tool](https://vaultaire.app/tools/photo-metadata/) combines AI provenance, C2PA, EXIF and location questions in a privacy-related utility. Tools can attract task-based searches and referrals; their actual traffic and backlink contribution is unverified.

The common editorial move is to answer the initial task, explain a privacy limitation, and introduce Vaultaire as a possible next step. This makes an app CTA relevant to the reader's original concern. It also means factual accuracy in those explanations matters.

## Internal linking and conversion

The homepage links directly to feature pages and competitor comparisons. The comparison hub links to the best-apps guide; the guide links to individual comparisons and related guides. The tools hub links to tools and their tutorials. These observable links help expose related pages and create routes from research to product evaluation.

The homepage offers an App Store link, desktop QR code, and an SMS-link option. Guides repeat app links at relevant points. These are conversion choices, not evidence of a ranking advantage. See the [homepage](https://vaultaire.app/) and [best-apps guide](https://vaultaire.app/guides/best-photo-vault-apps-iphone/).

## Technical implementation observed

The homepage's initial HTML contains substantive text and ordinary anchor links, so discovery is not dependent on executing the interface's JavaScript. It contains a descriptive title, meta description, canonical URL, hreflang links, social metadata, and JSON-LD for SoftwareApplication, Organization, Brand, WebSite, FAQPage, HowTo and BreadcrumbList. CSS/font preloads and deferred JavaScript suggest performance awareness, but no field Core Web Vitals or Lighthouse measurements were taken.

[robots.txt](https://vaultaire.app/robots.txt) allows general crawling, excludes /go/, references the sitemap, and explicitly allows several search and AI bots. These are accessibility and interpretation measures, not proof of higher rankings or AI citations. Structured data is supporting infrastructure; its presence alone does not establish eligibility for any particular search feature.

## Evidence of business results and operating process

The founder [reported on LinkedIn](https://www.linkedin.com/posts/synopsi_well-vaultaireapp-made-16271-in-may-2026-activity-7468018307430985729-VxHu) approximately 80 downloads/day and 9% conversion to paid at the time, attributing growth to both SEO and ASO. He explicitly said a viral tweet contributed to May's $16,271 revenue. These are self-reported, historical figures and do not isolate web SEO's contribution.

An [October 18 Starter Story interview](https://podcasts.apple.com/nz/podcast/this-app-is-making-%242-000-per-day/id1856101070?i=1000796998732), available through a [third-party transcript](https://businessmaxxing.com/episode/ep_q6l7rvl3kq2aja4w), describes an agent-assisted process: examine search opportunities, publish roughly one focused guide daily, connect it through internal links, and use reader behavior to place app CTAs. Treat details as reported interview claims, not an audited production workflow. Own-site query impressions/clicks/position are Search Console-style metrics, even where the transcript calls the tool Keyword Planner. The founder's [Gum repository](https://github.com/ehmo/gum) independently confirms Google API tooling including Search Console and Google Ads, not the publishing cadence or effectiveness.

## Practical lessons

For another app, begin with a small cluster of high-intent user problems, a substantive alternatives comparison, and clear internal links to the product. Use Search Console to improve pages already receiving relevant impressions and measure app downloads and paid users by landing page. Expand localization after validating useful demand and translation quality. Build a free tool only when its users plausibly need the paid app.

Do not copy page count as a success metric, unsupported competitor claims, or assume generic tool traffic converts well. Google's [people-first content guidance](https://developers.google.com/search/docs/fundamentals/creating-helpful-content) emphasizes original, useful, reliable content. The submitted page footprint demonstrates ambition and coverage; actual organic clicks, country distribution, backlink authority, conversions by page, and causality remain unverified. A third-party traffic lookup was attempted but its connector authentication was expired.
