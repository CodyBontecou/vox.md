#!/usr/bin/env python3
"""Apply only the owner-approved 2.14 version-localization descriptions/notes.

Defaults to a read-only preflight. --apply performs scoped writes; --verify only
reads back the desired fields. Does not touch in-app Notelet release notes.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/evidence/subscription-transition-20261029/listing-application'
SOURCE = OUT.parent / 'listing-copy-proposed.json'
VERSIONS = {'ios': '805e71b5-fba0-4e6c-85e5-1df5373c51b1',
            'mac': '045ffb94-b19a-4d5a-abc4-8c06f9947c51'}


def save(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def run(name, args):
    proc = subprocess.run(['asc', *args], capture_output=True, text=True)
    if proc.returncode:
        (OUT / (name + '.error.txt')).write_text(proc.stderr)
        raise RuntimeError(name + ': ' + proc.stderr)
    data = json.loads(proc.stdout) if proc.stdout.strip() else None
    save(name + '.json', data)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--apply', action='store_true')
    group.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    approval_path = OUT / 'owner-approval.json'
    if approval_path.exists():
        assert json.loads(approval_path.read_text())['source_sha256'] == source_hash, 'Proposal changed since approval; obtain new owner approval.'
    rows = json.loads(SOURCE.read_text())
    assert len(rows) == 78
    assert len({r['localization_id'] for r in rows}) == 78
    current = {}
    for platform, vid in VERSIONS.items():
        version = run(platform + '-version-preflight', ['api', 'GET', '/v1/appStoreVersions/' + vid])['data']
        assert version['attributes']['versionString'] == '2.14'
        assert version['attributes']['releaseType'] == 'MANUAL'
        if args.apply:
            assert version['attributes']['appStoreState'] in ('PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW')
        data = run(platform + '-preflight', ['localizations', 'list', '--version', vid, '--paginate'])['data']
        current[platform] = {r['id']: r for r in data}
        assert len(data) == 39
    for row in rows:
        existing = current[row['platform']][row['localization_id']]
        assert existing['attributes']['locale'] == row['locale']
        for field in ('description', 'whatsNew'):
            assert 0 < len(row[field]) <= 4000
        if not args.verify:
            baseline = json.loads((OUT.parent / (row['platform'] + '-localizations-before.json')).read_text())['data']
            old = next(r for r in baseline if r['id'] == row['localization_id'])
            for field in ('description', 'whatsNew'):
                assert existing['attributes'].get(field) in (old['attributes'].get(field), row[field]), (row['locale'], field, 'concurrent change')
    if args.apply:
        if not approval_path.exists():
            save('owner-approval', {'recorded_at': datetime.now(timezone.utc).isoformat(),
                 'source_sha256': source_hash,
                 'scope': 'Owner approved App Store descriptions and release notes for both platforms; in-app slider excluded. Manual release and existing-price freeze retained.'})
        for row in rows:
            attrs = current[row['platform']][row['localization_id']]['attributes']
            if all(attrs.get(k) == row[k] for k in ('description', 'whatsNew')):
                continue
            body = {'data': {'type': 'appStoreVersionLocalizations', 'id': row['localization_id'],
                            'attributes': {k: row[k] for k in ('description', 'whatsNew')}}}
            name = row['platform'] + '-' + row['locale']
            save(name + '-request.json', body)
            run(name + '-applied', ['api', 'PATCH', '/v1/appStoreVersionLocalizations/' + row['localization_id'],
                                  '--body-file', str(OUT / (name + '-request.json')), '--confirm'])
            time.sleep(0.35)
    if args.verify or args.apply:
        verified = 0
        for platform, vid in VERSIONS.items():
            data = run(platform + '-verified', ['localizations', 'list', '--version', vid, '--paginate'])['data']
            indexed = {r['id']: r['attributes'] for r in data}
            for row in (r for r in rows if r['platform'] == platform):
                attrs = indexed[row['localization_id']]
                assert all(attrs[k] == row[k] for k in ('description', 'whatsNew'))
                baseline = json.loads((OUT.parent / (platform + '-localizations-before.json')).read_text())['data']
                old = next(r for r in baseline if r['id'] == row['localization_id'])['attributes']
                for key in ('keywords', 'marketingUrl', 'supportUrl', 'promotionalText'):
                    assert attrs.get(key) == old.get(key), (row['locale'], key)
                verified += 1
        save('verification.json', {'verified_at': datetime.now(timezone.utc).isoformat(), 'records': verified,
                                  'fields': ['description', 'whatsNew'], 'other_listing_fields_unchanged': True,
                                  'in_app_release_notes_modified': False})
        print('Verified', verified, 'localized listings; unrelated fields unchanged.')
    else:
        print('Read-only preflight passed for 78 scoped version localizations. Use --apply for approved writes.')


if __name__ == '__main__':
    main()
