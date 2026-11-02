# Vox.md Google Search baseline

Captured October 26, 2026, before deploying the local SEO changes. Canonical website: https://vox.isolated.tech/.

## Connection and scope

- Added the URL-prefix property `https://vox.isolated.tech/` to the existing signed-in Search Console account. Google automatically verified ownership through the existing domain-name-provider verification. No DNS record, new user, or third-party analytics integration was added.
- Submitted `https://vox.isolated.tech/sitemap.xml`. Search Console reports **Success**, last read October 26, with **7 discovered pages**. The exact live sitemap is preserved in `live-sitemap.xml`. Discovered is not the same as indexed.
- The new URL-prefix property's performance and indexing reports are still processing. The baseline therefore uses the existing `sc-domain:isolated.tech` property, filtered to pages containing `https://vox.isolated.tech/`.
- Search type is **Web (text-based)**, as recorded in the export. This snapshot is not an App Store, conversion, or all-channel traffic report. No API/OAuth connector was configured; access was through the existing Google browser session.

[Open the fixed baseline report](https://search.google.com/search-console/performance/search-analytics?resource_id=sc-domain%3Aisolated.tech&page=*https%3A%2F%2Fvox.isolated.tech%2F&start_date=20260726&end_date=20261023&metrics=CLICKS%2CIMPRESSIONS%2CCTR%2CPOSITION).

## Reporting windows

Daily dates use Search Console's Pacific Time convention. The fixed end date is October 23, allowing three calendar days before capture for reporting latency. This is a cautious cutoff, not a guarantee that Google will never revise the data. Both interval endpoints are inclusive.

| Window | Dates | Clicks | Impressions | CTR | Average position |
| --- | --- | ---: | ---: | ---: | ---: |
| 90-day baseline | July 26–October 23, 2026 | 2 | 139 | 1.44% | 17.5 |
| Latest 28 days | September 26–October 23, 2026 | 0 | 0 | Not applicable | Not applicable |
| Previous 28 days | August 29–September 25, 2026 | 1 | 108 | 0.93% | Approximately 13.4 |

Clicks and impressions are summed from the daily export. CTR is clicks divided by impressions, not an average of daily percentages. The 90-day position is the rounded Search Console UI value. The previous-window position is weighted by impressions from the exported daily positions, which are already rounded, so it is approximate. Zero-impression periods have no meaningful CTR or position; a displayed UI zero must not be interpreted as rank zero.

The last day with a recorded impression in this export is **September 23, 2026**. The latest 28 days have 108 fewer impressions than the prior period. Volume is too small to infer a stable CTR trend or forecast commercial results.

## Pages that appeared

Original URLs and query strings are preserved in the export. These page rows sum to the 139 headline impressions and 2 clicks.

| Page | Clicks | Impressions | Position |
| --- | ---: | ---: | ---: |
| Homepage `/` | 2 | 41 | 5.76 |
| `/blog/best-voice-to-text-keyboard-iphone/` | 0 | 59 | 32.68 |
| `/privacy` | 0 | 25 | 8.24 |
| `/terms` | 0 | 10 | 5.20 |
| Homepage with AppAgg referral parameters | 0 | 3 | 3.67 |
| `/privacy.html` | 0 | 1 | 5.00 |

The homepage's CTR is 4.88% (2 / 41). The keyboard article receives the most impressions but has no reported clicks. Its small sample and average position near 33 do not establish a title/CTR problem; strengthen the content and internal links while addressing indexing first. The `/privacy` and `/privacy.html` variants warrant a later canonical/redirect check. Do not change their historical rows in the baseline.

## Reported queries, countries and devices

The query table has 10 rows, totaling **25 impressions and zero clicks**. Among those disclosed rows, `vox md` accounts for 6 impressions, while the remaining 19 are nonbranded voice/keyboard queries. `voice to text iphone` has 7 impressions at position 35.57. No disclosed query mentions Obsidian or Apple Watch in this snapshot.

This is an incomplete query view, not a complete branded/nonbranded traffic split. All 2 headline clicks and 114 of the 139 impressions are absent from the query rows. Search Console omits some query details and warns that filtered tables/totals can be partial. Do not assign the missing portion to a brand category.

Country rows contain only 25 impressions: United States 13, Germany 4, Philippines 2, Australia 2, and Belgium, Finland, United Kingdom and Canada 1 each. Device rows likewise contain 25 impressions: Desktop 18 and Mobile 7, with zero disclosed clicks. These dimension totals do not reconcile to the chart/page totals. Treat them as the reported subset; do not infer a complete audience or device conversion split. The Search appearance export has headers and no data rows.

## Legacy hostname

The same parent property, dates and search type were checked with a separate page filter containing `https://voxboard.isolated.tech/`. The UI shows **0 clicks, 0 impressions, and no query rows**. Record CTR and position as not applicable. This does not establish that the old hostname never received traffic outside this window or that its redirects are correctly configured.

## Current indexing concern

On October 26, Google Index inspection of the homepage returned **URL is not on Google**, with **Crawled — currently not indexed**. The report showed:

- Last crawl: September 9, 2026, 1:36:40 AM as displayed by the UI; that display's timezone was not established.
- Crawl allowed: Yes. Page fetch: Successful. Indexing allowed: Yes.
- User-declared canonical: `https://vox.isolated.tech/`. Google-selected canonical: Inspected URL.
- Discovery references include the sitemap, AppAgg and an Obsidian Reddit discussion.

A fresh live test on October 26 returned **URL is available to Google** and **Page can be indexed**. This establishes live availability, not inclusion in Google's index. The homepage indexing request was **accepted** on October 26. Google confirmed that the URL was added to a priority crawl queue. This is a request, not confirmation that the page has been indexed.

The absence of recent impressions and the current exclusion make index coverage the immediate concern. These observations do not prove exactly when the homepage left the index or why Google excluded it.

## Next actions and measurement

1. Confirm the homepage indexing request and inspect the existing keyboard article and docs as the new property fills in. Requesting indexing is not a guarantee of inclusion.
2. Deploy the completed website changes through the normal release flow when authorized. As captured here, the live sitemap still has 7 URLs; the local implementation has 10. Never request indexing for local-only guide URLs.
3. After deployment, confirm the live sitemap includes the new canonical URLs and contextual links, and inspect those live pages in Search Console.
4. Compare the next complete 28-day window with September 26–October 23. Keep the same page filter, search type and aggregation. If moving to the new URL-prefix property, retain this parent-filtered report for continuity and check whether the scopes/totals agree.
5. Track indexed pages, nonbranded impressions/clicks, and app-download clicks separately. Search Console clicks are not installs or paid conversions. Campaign attribution remains a separate implementation step.

No recurring monitor was scheduled. A later report should use a new dated directory and retain this snapshot unchanged.

## Preserved evidence

- `canonical-search-console-export.zip`: original Google export, unchanged.
- `canonical-export/`: its original Chart, Queries, Pages, Countries, Devices, Search appearance and Filters CSVs.
- `summary.json`: reporting configuration, calculated windows, connection/indexing observations and export SHA-256.
- `live-sitemap.xml`: live public sitemap at capture.

Methodology references: [Google performance reporting](https://support.google.com/webmasters/answer/7576553), [Search Analytics dates and aggregation](https://developers.google.com/webmaster-tools/v1/searchanalytics/query). Google does not guarantee disclosure of every query row. The original export is the source of record for this baseline.
