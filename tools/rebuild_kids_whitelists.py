"""Offline, platform-specific Kids whitelist rebuild. SPDX-License-Identifier: GPL-3.0-or-later."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / '.MiSTer_SAM'))
from sam_titles import altered_release, title_key, title_text

ALLOWED = {'E', 'EC', 'KA', 'K-A'}


def select_titles(core, catalog, curated):
    selected = {}
    known = catalog.get(core, {})
    for title in curated.get(core, []):
        key = title_key(title)
        ratings = set(known.get(key, {}).get('ratings', []))
        if altered_release(title) or (ratings and not ratings <= ALLOWED):
            continue
        selected.setdefault(key, {'title': title_text(title), 'basis': 'same-platform age metadata + content review' if ratings else 'conservative content review (unrated)',
            'ratings': sorted(ratings)})
    return sorted(selected.values(), key=lambda entry: entry['title'].casefold())


def include_romset_aliases(entries, aliases):
    """Only stock set identifiers whose same-platform game was already reviewed."""
    selected = {title_key(entry['title']): entry for entry in entries}
    for alias, evidence in aliases.items():
        target = selected.get(title_key(evidence['title']))
        if target is None:
            raise ValueError('ROM-set alias has no reviewed title: ' + alias)
        if not alias.isascii() or not alias.isalnum() or altered_release(alias):
            raise ValueError('invalid stock ROM-set identifier: ' + alias)
        target.setdefault('romset_aliases', []).append(alias)
        if title_key(alias) not in selected:
            selected[title_key(alias)] = {'title': alias, 'basis': 'same-platform reviewed stock ROM-set alias',
                'reviewed_title': target['title'], 'ratings': target['ratings'], 'romset_source': evidence['source']}
    return sorted(selected.values(), key=lambda entry: entry['title'].casefold())


def rebuild(audit, check=False):
    catalog = json.loads((audit / 'metadata-catalog.json').read_text(encoding='utf-8'))
    provenance = json.loads((audit / 'metadata-source.json').read_text(encoding='utf-8'))
    manifest = json.loads((REPO / 'docs/kids-curated.json').read_text(encoding='utf-8'))
    report = {'standard': sorted(ALLOWED), 'metadata_source': provenance,
              'primary_spot_checks': manifest['primary_spot_checks'],
              'romset_aliases': manifest.get('romset_aliases', {}),
              'curated_manifest_sha256': hashlib.sha256((REPO / 'docs/kids-curated.json').read_bytes()).hexdigest(),
              'cores': {}}
    for original in sorted((audit / 'originals').glob('*_rated.txt')):
        core = original.name.removesuffix('_rated.txt')
        entries = select_titles(core, catalog, manifest['cores'])
        for spot in manifest['primary_spot_checks']:
            if spot['core'] != core:
                continue
            for entry in entries:
                if title_key(entry['title']) == title_key(spot['title']):
                    entry.update(basis='same-platform primary ESRB + content review',
                                 ratings=[spot['rating']], primary_source=spot['url'])
        entries = include_romset_aliases(entries, manifest.get('romset_aliases', {}).get(core, {}))
        titles = [entry['title'] for entry in entries]
        payload = ''.join(title + '\n' for title in titles)
        target = REPO / 'SAM/Rated' / original.name
        if check:
            if target.read_text(encoding='utf-8') != payload:
                raise SystemExit('stale whitelist: ' + original.name)
        else:
            with target.open('w', encoding='utf-8', newline='\n') as output:
                output.write(payload)
        old = [line.strip() for line in original.read_text(encoding='utf-8').splitlines() if line.strip()]
        old_keys = {title_key(title) for title in old}
        new_keys = {title_key(title) for title in titles}
        report['cores'][core] = {'old_lines': len(old), 'new_titles': len(titles),
            'added': [title for title in titles if title_key(title) not in old_keys],
            'removed': [title for title in old if title_key(title) not in new_keys],
            'output_sha256': hashlib.sha256(payload.encode()).hexdigest(), 'entries': entries}
    if not check:
        (audit / 'whitelist-evidence.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit', required=True, type=Path, help='metadata-catalog/source and originals directory')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    report = rebuild(args.audit, args.check)
    for core, result in report['cores'].items():
        print(f"{core}: {result['old_lines']} -> {result['new_titles']}; added {len(result['added'])}, removed {len(result['removed'])}")
