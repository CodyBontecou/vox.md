#!/usr/bin/env python3
"""Build an unpublished, reviewable website patch. Never edits website/ or deploys."""
import difflib
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/launch/hard-paywall'
SOURCE = ROOT / 'website'


def replace_once(text, before, after):
    assert text.count(before) == 1, before
    return text.replace(before, after)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    patches, manifest = [], {}
    for name in ('index.html', 'docs/index.html', 'llms.txt', 'terms.html', 'privacy.html'):
        before = (SOURCE / name).read_text()
        after = before
        if name == 'index.html':
            after = replace_once(after,
                'Vox.md includes 15 minutes of transcription and 10 successful Capture deliveries free. Unlimited transcription and Capture are available with a one-time lifetime purchase, with no subscription or ads. Voice transcripts sent to Markdown use the transcription allowance rather than a second Capture allowance. The App Store shows the current price for your region.',
                'Vox.md is a free download. New Capture and transcription require paid access: choose Individual or Family, weekly, yearly, or lifetime. Eligible subscriptions include a seven-day free trial. Existing purchases remain valid, and viewing or exporting existing history requires no new purchase. Apple shows the current local price and renewal terms before you confirm.')
            after = replace_once(after, '15 transcription minutes + 10 Capture deliveries free', 'Seven-day free trial for eligible subscriptions')
        elif name == 'docs/index.html':
            after = replace_once(after,
                'The 15-minute free transcription allowance applies to keyboard dictation as well as app recordings and imports.',
                'New keyboard dictation, app recordings, and imported-audio transcription require paid access. Existing purchases and eligible subscription trials provide access.')
            after = replace_once(after, 'Free usage status, lifetime unlock, and purchase restore.',
                'Individual and Family plans, subscription management, lifetime purchases, and restore.')
            start = after.index('        <h3 id="pricing-limits">')
            end = after.index('        <h3 id="privacy-data">', start)
            after = after[:start] + '''        <h3 id="pricing-limits">Plans, trials, and existing purchases</h3>
        <ul>
          <li>New Capture deliveries and transcription require paid access. There is no recurring free allowance.</li>
          <li>Choose Individual or Family access, with weekly, yearly, or lifetime purchase options. Family plans support Apple Family Sharing.</li>
          <li>US subscription prices are $0.99/week or $29.99/year for Individual, and $1.99/week or $49.99/year for Family. Prices vary by storefront; the price Apple displays before confirmation is authoritative. Lifetime options remain available at the current local App Store price.</li>
          <li>Eligible subscriptions include a seven-day free trial, then renew automatically at the displayed price unless canceled. Apple determines introductory-offer eligibility across the subscription group. Lifetime purchases have no trial or automatic renewal.</li>
          <li>Manage or cancel subscriptions in Apple Account settings. Cancel a trial at least 24 hours before it ends to avoid renewal. Canceling does not delete existing history. Buying lifetime access does not automatically cancel an active subscription; manage that subscription separately.</li>
          <li>Existing lifetime purchases remain valid. Verified owners of qualifying original paid-app versions keep their existing access. Use Restore Purchases with the Apple Account that purchased access.</li>
          <li>Without paid access, use the History clock button on the iOS paywall or View and Export Existing History on Mac. Read, search, copy, export, and explicit deletion remain available. Editing, new recordings, new Capture deliveries, and queued Capture retries require paid access.</li>
          <li>The discounted Individual-to-Family lifetime upgrade is for existing Individual lifetime owners, not subscription-only users. There is no monthly plan. Reinstalling does not reset Apple's trial eligibility.</li>
        </ul>

''' + after[end:]
        elif name == 'llms.txt':
            after = replace_once(after, 'settings map, free allowances, lifetime unlock, and data handling.',
                'settings map, paid plans, trials, existing purchases, unpaid history access, and data handling.')
            after = replace_once(after,
                'The free tier includes 15 minutes of transcription and 10 successful Capture deliveries. Failed writes and idempotent retries do not consume a successful delivery. Unlimited use is a one-time lifetime purchase with no subscription or renewal. Localized App Store pricing is authoritative; US options are $19.99 Individual, $39.99 Family, and $19.99 Family Upgrade, with purchasing-power pricing in other storefronts.',
                'New Capture and transcription require paid access. Individual and Family each offer weekly, yearly, or lifetime access. US subscriptions are $0.99/week or $29.99/year for Individual and $1.99/week or $49.99/year for Family. Eligible subscriptions include a seven-day trial and then renew automatically at the displayed price until canceled in Apple Account settings; Apple determines eligibility across the shared subscription group. Lifetime purchases have no trial or renewal. Existing purchases remain valid, and viewing/exporting existing history requires no new purchase. Local App Store prices are authoritative. Buying lifetime access does not automatically cancel an active subscription. There is no monthly plan or resettable free allowance.')
        elif name == 'privacy.html':
            after = (OUT / 'privacy-policy-proposed.html').read_text()
        else:
            start = after.index('    <h2>License</h2>')
            end = after.index('    <h2>Speech Models</h2>', start)
            after = after[:start] + '''    <h2>License</h2>
    <p>Vox.md source code is available under the GNU Affero General Public License v3.0 (AGPL-3.0). Rights to use, modify, and redistribute that source are governed by its license. App Store distribution is also subject to Apple's standard Licensed Application End User License Agreement and applicable law.</p>

''' + after[end:]
            after = replace_once(after, '    <h2>Speech Models</h2>', '''    <h2>Purchases and Subscriptions</h2>
    <p>New Capture deliveries and transcription require paid access. Individual and Family access are available through weekly or yearly auto-renewable subscriptions or a one-time lifetime purchase. Apple displays the applicable local price and terms before confirmation. Eligible subscriptions include a seven-day free trial; Apple determines introductory eligibility. Lifetime purchases do not include a trial and do not automatically renew.</p>
    <p>Subscriptions renew automatically unless canceled through Apple Account settings. Cancel a trial at least 24 hours before it ends to avoid renewal. Deleting the app or purchasing lifetime access does not automatically cancel an existing subscription. Use Apple's subscription-management controls to manage or cancel it separately. Purchase restoration, billing, refunds, and Family Sharing are handled through Apple under its applicable terms.</p>
    <p>Existing purchases remain valid. Viewing and exporting existing history do not require a new purchase. Canceling a subscription does not delete existing local history or previously exported files. Apple's <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">standard Licensed Application End User License Agreement</a> also applies.</p>

    <h2>Speech Models</h2>''')
        if name == 'terms.html':
            after = after.replace('Effective: February 9, 2026 · Last updated: July 17, 2026',
                'Applies to Vox.md 2.14 when released · Prepared October 30, 2026')
            after = after.replace('production onboarding analytics are disabled by default as described in the Privacy Policy.',
                'this release removes custom app usage analytics and advertising attribution as described in the Privacy Policy. Optional HTTP delivery sends configured text to the endpoint you explicitly choose.')
            after = after.replace('production onboarding analytics are disabled by default.',
                'this release removes custom app usage analytics and advertising attribution. Optional HTTP delivery is controlled by your destination settings.')
        if name == 'docs/index.html':
            after = after.replace('Production onboarding analytics are disabled by default. The app contains no third-party analytics SDK, ad network, or cross-app tracker.',
                'Vox.md 2.14 removes custom in-app analytics and advertising attribution. Upgrades erase retired local event queues and analytics identifiers. Essential services and earlier retained server records have separate disclosures.')
        if name == 'llms.txt':
            start = after.index('Production onboarding analytics are disabled by default.')
            end = after.index('Location is not collected by the developer or analytics.', start)
            after = after[:start] + 'The candidate removes custom app analytics, advertising attribution, persistent analytics identifiers and event uploads in every build configuration. Older binaries and previously received server records are unchanged until an approved cutover and deletion. Essential services remain. ' + after[end:]
        target = OUT / 'website-staged' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(after)
        manifest[name] = {'before_sha256': hashlib.sha256(before.encode()).hexdigest(),
                          'staged_sha256': hashlib.sha256(after.encode()).hexdigest()}
        patches.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                           fromfile='a/website/' + name, tofile='b/website/' + name))
    (OUT / 'website.patch').write_text(''.join(patches))
    (OUT / 'website-stage-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Staged five website files and website.patch; live source and public site unchanged.')


if __name__ == '__main__':
    main()
