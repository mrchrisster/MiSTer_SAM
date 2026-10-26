# SPDX-License-Identifier: GPL-3.0-or-later
"""Refine prepared lists using explicit genre folders or exact curated aliases.

Never scans collections, rewrites master lists, or adds candidates removed by
another filter. Missing metadata produces an empty category, not all games.
"""
import argparse
from functools import lru_cache
import json
import os
from pathlib import Path
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sam_titles import title_key, title_keys

PRESETS = ('off', 'pinball', 'arcade_horizontal', 'arcade_vertical', 'shmups',
           'fighting', 'puzzle', 'racing')
FOLDERS = {
    'pinball': {'pinball', 'all pinball games', 'allpinballgames', '1allpinballgames'},
    'shmups': {'shoot em ups', 'shoot em up', 'shmups', 'shmup'},
    'fighting': {'fighting', 'fighters', 'fighting games', 'fighters 1v1', 'fighting 1v1'},
    'puzzle': {'puzzle', 'puzzles', 'puzzle games'},
    'racing': {'racing', 'racing games', 'driving'},
    'arcade_horizontal': {'horizontal', 'horizontal 180'},
    'arcade_vertical': {'vertical', 'vertical cw', 'vertical ccw'},
}
EXCLUSION_TAGS = {'beta', 'hack', 'homebrew', 'prototype', 'unlicensed',
                  'translations', 'usa', 'japan', 'europe'}
TAG_FOLDERS = {'hack': {'hack', 'hacks'}, 'translations': {'translation', 'translations'},
               'prototype': {'prototype', 'prototypes'}, 'beta': {'beta', 'betas'}}


@lru_cache(maxsize=4096)
def folder_key(value):
    value = unicodedata.normalize('NFKC', value).casefold().strip()
    value = re.sub(r'^\s*\d+(?:\s*[.\-:]\s*|\s+)', '', value)
    return re.sub(r'[^\w]+', ' ', value.replace('_', ' ')).strip()


def folder_matches(path, preset):
    # Exclude the basename: "Pinball.sfc" is a title, not genre metadata.
    parts = [folder_key(part) for part in path.split('/')[:-1]]
    if preset.startswith('arcade_'):
        return any(part in FOLDERS[preset] for part in parts)
    # Console packs declare their category hierarchy explicitly. Title-named
    # folders (especially CD collections) are never genre declarations.
    for index, part in enumerate(parts[:-1]):
        if part in {'genre', 'genres'} and parts[index + 1] in FOLDERS[preset]:
            return True
    return False


def category_title_keys(path):
    # Preserve legacy filename bytes in output, but never discard an unknown
    # byte to manufacture a reviewed title alias. Unrelated directory bytes do
    # not invalidate a normal leaf title.
    parts = path.rsplit('/', 2)
    leaf = parts[-1]
    if any('\udc80' <= character <= '\udcff' for character in leaf):
        return set()
    keys = title_keys(path)
    if len(keys) > 1 and len(parts) > 1 and any('\udc80' <= character <= '\udcff' for character in parts[-2]):
        return {title_key(leaf)}
    return keys


MRA_HEADER_LIMIT = 256 * 1024
MRA_HEADER_CHUNK = 4096


def orientation_fields(path):
    """Read bounded root metadata, stopping before the first ROM payload.

    A late declaration after root-level <rom> is intentionally unknown. MRA
    files may embed large ROM data; category selection must never parse it.
    """
    fields = {}
    parser = ET.XMLPullParser(events=('start', 'end'))
    depth = 0
    remaining = MRA_HEADER_LIMIT
    try:
        with Path(path).open('rb') as source:
            while remaining:
                chunk = source.read(min(MRA_HEADER_CHUNK, remaining))
                if not chunk:
                    break
                remaining -= len(chunk)
                parser.feed(chunk)
                for event, element in parser.read_events():
                    if event == 'start':
                        depth += 1
                        if depth == 2 and element.tag == 'rom':
                            return fields
                    else:
                        if depth == 2 and element.tag in {'rotation', 'orientation'}:
                            fields[element.tag] = (element.text or '').strip().casefold()
                        depth -= 1
                        element.clear()
    except (OSError, ET.ParseError):
        return {}
    return fields


def orientation_matches(path, preset):
    fields = orientation_fields(path)
    rotation = fields.get('rotation')
    orientation = fields.get('orientation')
    expected = 'horizontal' if preset == 'arcade_horizontal' else 'vertical'
    if orientation is not None and orientation.strip().casefold() in {'horizontal', 'vertical'}:
        return orientation.strip().casefold() == expected
    if rotation is None:
        return False
    value = rotation.strip().casefold()
    declared = re.fullmatch(r'(horizontal|vertical)(?:\s+\((?:cw|ccw)\))?', value)
    if declared:
        return declared.group(1) == expected
    try:
        degrees = int(value) % 360
    except ValueError:
        return False
    return degrees in ({0, 180} if expected == 'horizontal' else {90, 270})


class OrientationIndex:
    def __init__(self):
        self.files = {}
        self.titles = {}

    def axis(self, path):
        filename = path.rsplit('/', 1)[-1].casefold()
        if any('\udc80' <= character <= '\udcff' for character in filename):
            return None
        if filename in self.files:
            return self.files[filename]
        return self.titles.get(title_key(path))


def orientation_index_from_data(data):
    if not isinstance(data, dict):
        raise ValueError('Organizer metadata must be a setname dictionary')
    index = OrientationIndex()
    has_explicit_rotation = False
    for record in data.values():
        if not isinstance(record, dict):
            continue
        filename, rotation = record.get('file'), record.get('rotation')
        if not isinstance(filename, str) or '/' in filename or '\\' in filename or not filename.casefold().endswith('.mra'):
            continue
        axis = None
        if type(rotation) is int and rotation in {0, 90, 180, 270}:
            has_explicit_rotation = True
            axis = 'horizontal' if rotation in {0, 180} else 'vertical'
        # Unknown rotations also invalidate this canonical alias. Never inherit
        # Organizer's default zero or certify an unknown clone from a sibling.
        for target, key in ((index.files, filename.casefold()), (index.titles, title_key(filename))):
            if not key:
                continue
            if key not in target:
                target[key] = axis
            elif target[key] != axis:
                target[key] = None  # Conflicting clones cannot certify this alias.
    return index if has_explicit_rotation else None


def organizer_paths():
    override = os.environ.get('SAM_ARCADE_ORGANIZER_DATA')
    if override:
        return [Path(override)]
    root = Path(os.environ.get('SAM_MISTER_ROOT', '/media/fat')) / 'Scripts'
    return [root / '.config/arcade-organizer/data.zip', root / '.cache/arcade-organizer/data.zip']


def load_orientation_index(paths=None):
    limit = 2 * 1024 * 1024
    for path in organizer_paths() if paths is None else paths:
        try:
            path = Path(path)
            if path.stat().st_size > limit:
                continue
            with zipfile.ZipFile(path) as archive:
                member = archive.getinfo('mad_db.json')
                if member.file_size > limit or member.flag_bits & 1:
                    continue
                with archive.open(member) as source:
                    raw = source.read(limit + 1)
                if len(raw) > limit:
                    continue
                index = orientation_index_from_data(json.loads(raw))
                if index is not None:
                    return index
        except (OSError, ValueError, KeyError, zipfile.BadZipFile, RuntimeError):
            continue
    return None


def filter_paths(core, preset, candidates, master, aliases, orientation_index=None):
    if preset == 'off':
        return list(candidates)
    if preset not in PRESETS:
        raise ValueError('Unknown category preset')
    if preset.startswith('arcade_') and core != 'arcade':
        return []
    if preset.startswith('arcade_') and orientation_index is not None:
        expected = 'horizontal' if preset == 'arcade_horizontal' else 'vertical'
        return [path for path in candidates if orientation_index.axis(path) == expected]
    genre_paths = [path for path in master if folder_matches(path, preset)]
    if genre_paths:
        if preset.startswith('arcade_'):
            return [path for path in candidates if folder_matches(path, preset)]
        # Normal deduplication may retain the region/all-games copy before its
        # Genre copy. That copy still has exact per-core genre evidence in the
        # master. Refine existing candidates by those title keys, never add rows.
        genre_titles = set()
        for path in genre_paths:
            keys = category_title_keys(path)
            leaf_key = title_key(path)
            extension = path.rsplit('.', 1)[-1].casefold()
            if extension in {'chd', 'cue', 'bin', 'iso'} and re.fullmatch(r'(?:disc|disk|cd|track)0*\d{1,2}', leaf_key):
                keys.discard(leaf_key)  # "disc1" is not genre title evidence.
                parent = path.rsplit('/', 2)[-2] if '/' in path else ''
                if folder_key(parent) in FOLDERS[preset]:
                    keys.clear()  # A Genre label itself is not a CD game title.
            genre_titles.update(keys)
        return [path for path in candidates if folder_matches(path, preset) or category_title_keys(path) & genre_titles]
    # No full-MRA catalogue fallback. Exact orientation seeds are hints only;
    # the proposed candidate's real header is validated by candidate_prepare.
    allowed = {title_key(alias) for alias in aliases.get(preset, {}).get(core, [])}
    if not allowed:
        return []
    return [path for path in candidates if category_title_keys(path) & allowed]


def excluded_by_tags(path, tags):
    if not tags:
        return False
    parts = [folder_key(part) for part in path.split('/')[:-1]]
    raw_annotations = re.findall(r'[\[(]([^\]\)]*)[\])]', path.rsplit('/', 1)[-1])
    annotations = [folder_key(value) for value in raw_annotations]
    for tag in tags:
        if any(part in TAG_FOLDERS.get(tag, {tag}) for part in parts):
            return True
        for annotation in annotations:
            words = set(annotation.split())
            aliases = {'prototype': {'proto'}, 'unlicensed': {'unl'},
                       'translations': {'translation', 'translated'}}
            if tag in words or words & aliases.get(tag, set()):
                return True
        if tag == 'translations' and any(re.match(r'^\s*t[+-]', value, re.I) for value in raw_annotations):
            return True
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--core', required=True)
    parser.add_argument('--preset', required=True, choices=PRESETS)
    parser.add_argument('--list', type=Path)
    parser.add_argument('--master', type=Path)
    parser.add_argument('--aliases', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--organizer-data', action='append', type=Path)
    parser.add_argument('--check-orientation', type=Path)
    parser.add_argument('--mra-orientation', action='store_true',
                        help='Filter this candidate batch using bounded real MRA headers')
    parser.add_argument('--exclude-tags', default='')
    args = parser.parse_args()
    if args.mra_orientation and (args.core != 'arcade' or args.preset not in ('arcade_horizontal', 'arcade_vertical')):
        parser.error('MRA orientation filtering requires an arcade orientation preset')
    if args.check_orientation is not None:
        if args.core != 'arcade' or not args.preset.startswith('arcade_'):
            parser.error('Orientation validation requires an arcade orientation preset')
        return 0 if orientation_matches(str(args.check_orientation), args.preset) else 1
    if any(value is None for value in (args.list, args.master, args.aliases, args.output)):
        parser.error('Filtering requires --list, --master, --aliases and --output')
    try:
        candidates = args.list.read_text(encoding='utf-8', errors='surrogateescape').splitlines()
        master = args.master.read_text(encoding='utf-8', errors='surrogateescape').splitlines()
        aliases = json.loads(args.aliases.read_text(encoding='utf-8'))
        tags = {tag.strip().casefold() for tag in args.exclude_tags.split(',') if tag.strip()}
        if not tags <= EXCLUSION_TAGS:
            raise ValueError('Unknown category exclusion tag')
        if args.mra_orientation:
            # Inspect only the prepared batch, never discover new files or parse
            # embedded ROM payloads. Unknown metadata stays excluded.
            selected = [path for path in candidates if orientation_matches(path, args.preset)]
        else:
            index = load_orientation_index(args.organizer_data) if args.preset.startswith('arcade_') else None
            selected = filter_paths(args.core, args.preset, candidates, master, aliases, index)
        selected = [path for path in selected if not excluded_by_tags(path, tags)]
        args.output.write_text(''.join(path + '\n' for path in selected), encoding='utf-8', errors='surrogateescape')
    except (OSError, UnicodeError, ValueError, TypeError) as error:
        parser.exit(2, 'SAM category filter failed: ' + str(error) + '\n')
    return 0 if selected else 1


if __name__ == '__main__':
    raise SystemExit(main())
