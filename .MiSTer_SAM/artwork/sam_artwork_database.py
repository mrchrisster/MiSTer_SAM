# SPDX-License-Identifier: AGPL-3.0-or-later
"""Small published indexes and selected-cover verification for SAM.

Missing catalogs are downloaded once for the selected core before filtering;
only the chosen cover is fetched/decoded before launch. Installed packs and
ROMs are never written or removed. Online displays fetch the same published
image independently; Monitor's local /media/artwork endpoint is unchanged.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import os
from pathlib import Path
import time
import types
from urllib.parse import quote
from urllib.request import urlopen

from sam_artwork import Catalogue, SYSTEMS

BASE = 'https://raw.githubusercontent.com/chipster6502'
CACHE_BYTES = 32 * 1024 * 1024
GROUPS = {
    'atari': ('ATARI5200', 'ATARI7800', 'Atari2600', 'AtariLynx', 'Jaguar'),
    'nintendo-consoles': ('FDS', 'N64', 'NES', 'SNES', 'Satellaview'),
    'nintendo-handhelds': ('GAMEBOY', 'GBA', 'GBC'),
    'sega': ('GameGear', 'Genesis', 'MegaCD', 'S32X', 'SG-1000', 'SMS', 'Saturn'),
    'snk': ('NEOGEO', 'NeoGeo-CD', 'NeoGeoPocket', 'NeoGeoPocket-Color'),
    'sony': ('PSX',), 'arcade': ('Arcade',),
    'nec': ('SuperGrafx', 'TGFX16', 'TGFX16-CD'),
}
EXTRA = dict(nes=('FDS',), fds=('NES',), snes=('Satellaview',),
             gb=('GBC',), gbc=('GAMEBOY',), sgb=('GBC',),
             genesis=('SMS',), atari7800=('Atari2600',), neogeo=('NeoGeo-CD',))


def folder_url(folder, style='box2d', base=BASE):
    group = next((g for g, folders in GROUPS.items() if folder in folders), 'misc')
    return f'{base}/artworkdb-{group}/media-{style}/docs/{folder}/Artwork/'


def image_keys(text):
    keys = set()
    for line in text.splitlines():
        if line.startswith('#'): continue
        row = line.split('\t')
        if len(row) < 4: continue
        key = row[3]
        if key and key not in ('.', '..') and '/' not in key and '\\' not in key:
            keys.add(key)
    return keys


def metadata_keys(text):
    return {row[0] for line in text.splitlines() if not line.startswith('#')
            for row in [line.split('\t')] if len(row) >= 6 and row[0]}


def fetch(url, maximum, timeout=10):
    with urlopen(url, timeout=timeout) as response:
        data = response.read(maximum + 1)
    if len(data) > maximum: raise ValueError('Download exceeds size limit')
    return data


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f'.tmp.{os.getpid()}')
    try:
        tmp.write_bytes(data)
        tmp.replace(path)
    finally:
        tmp.unlink(missing_ok=True)


def setup(root, cores, refresh=False, base=BASE):
    """Download box2d catalogs, as the APK does; style affects cover URL only."""
    folders = set()
    for core in cores:
        if core not in SYSTEMS:
            print(f'{core}: no supported artwork database', flush=True)
            continue
        folders.add(SYSTEMS[core])
        folders.update(EXTRA.get(core, ()))
    def download(folder):
        directory = Path(root) / 'docs' / folder / 'Artwork'
        index, info = directory / 'index.tsv', directory / 'gameinfo.tsv'
        if not refresh and index.is_file() and info.is_file():
            usable = image_keys(index.read_text(encoding='utf-8')) & metadata_keys(info.read_text(encoding='utf-8'))
            if usable: return folder, len(usable), 'cached'
        # Validate both before replacing either; failure keeps the previous data.
        data = fetch(folder_url(folder, base=base) + 'index.tsv', 16 * 1024 * 1024)
        details = fetch(folder_url(folder, base=base) + 'gameinfo.tsv', 16 * 1024 * 1024)
        usable = image_keys(data.decode('utf-8')) & metadata_keys(details.decode('utf-8'))
        if not usable: raise ValueError('No usable index/metadata entries')
        atomic_write(info, details)
        atomic_write(index, data)
        return folder, len(usable), 'downloaded'
    successful = 0
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(download, folder): folder for folder in sorted(folders)}
        for future in as_completed(futures):
            folder = futures[future]
            try:
                folder, count, result = future.result()
                print(f'{folder}: {count} entries ({result})', flush=True)
                successful += 1
            except Exception as error:
                print(f'{folder}: unavailable ({error}); previous files retained', flush=True)
    if not successful:
        print('No databases ready. Choose installed packs or retry database setup.', flush=True)
        return 2
    atomic_write(Path(root) / '.generation', str(time.time_ns()).encode('ascii'))
    return 0


def ensure_catalogs(root, cores, base=BASE):
    """Lazy initialization: no all-system startup scan or manual setup needed."""
    supported = [core for core in cores if core in SYSTEMS]
    if not supported:
        return True  # Normal matching reports unsupported systems.
    for core in supported:
        folders = (SYSTEMS[core],) + EXTRA.get(core, ())
        ready = False
        for folder in folders:
            directory = Path(root) / 'docs' / folder / 'Artwork'
            try:
                ready = bool(image_keys((directory / 'index.tsv').read_text(encoding='utf-8'))
                             & metadata_keys((directory / 'gameinfo.tsv').read_text(encoding='utf-8')))
            except (OSError, ValueError):
                ready = False
            if ready: break
        if not ready:
            print(f'SAM artwork: downloading catalogs for {core}...', flush=True)
            if setup(root, [core], base=base) != 0:
                print(f'SAM artwork ERROR: catalog download failed for {core}. '
                      'Check Internet access and restart SAM to retry. Current game was not replaced.',
                      flush=True)
                return False
    return True


class DatabaseCatalogue(Catalogue):
    def __init__(self, source, cache, database, downloads, style, base=BASE, cores=None):
        super().__init__(source, cache)
        self.database, self.downloads = Path(database), Path(downloads)
        self.style, self.base = style, base
        self.full_keys = True
        self.ns['_PACK_MOUNTS'] = [str(self.database)]
        directories = {}
        if cores is None:
            directories_to_read = self.database.glob('docs/*/Artwork')
        else:
            folders = set()
            for core in cores:
                if core in SYSTEMS:
                    folders.add(SYSTEMS[core])
                    folders.update(EXTRA.get(core, ()))
            directories_to_read = (self.database / 'docs' / folder / 'Artwork' for folder in sorted(folders))
        for directory in directories_to_read:
            try:
                keys = image_keys((directory / 'index.tsv').read_text(encoding='utf-8'))
                keys &= metadata_keys((directory / 'gameinfo.tsv').read_text(encoding='utf-8'))
            except (OSError, ValueError): keys = set()
            directories[str(directory)] = {key + '.jpg' for key in keys}
            self.available_folders[directory.parent.name] = bool(keys)
        real_path = os.path
        def isfile(path):
            parent, name = os.path.split(path)
            if parent in directories and name.endswith('.jpg'):
                return name in directories[parent]
            return real_path.isfile(path)
        proxy_path = types.SimpleNamespace(**vars(os.path))
        proxy_path.isfile = isfile
        proxy_os = types.SimpleNamespace(**vars(os))
        proxy_os.path = proxy_path
        self.ns['os'] = proxy_os

    def fast_names(self):
        # Cache pack/index lookups too: no per-candidate index/directory stat.
        original_dir = self.ns['_pack_dir']
        original_index = self.ns['_pack_index']
        directories, indexes, parents = {}, {}, {}
        def directory(folder):
            if folder not in directories: directories[folder] = original_dir(folder)
            return directories[folder]
        def index(path):
            if path not in indexes: indexes[path] = original_index(path)
            return indexes[path]
        self.ns['_pack_dir'] = directory
        self.ns['_pack_index'] = index
        # Monitor derives archive keys by walking to a real parent directory.
        # Many candidates share those parents; probing USB storage for every ROM
        # can dominate the first pass. Keep the same rule with per-pass caching.
        original_isdir = self.ns['os'].path.isdir
        def isdir(path):
            if path not in parents: parents[path] = original_isdir(path)
            return parents[path]
        self.ns['os'].path.isdir = isdir

    def metadata(self, path):
        # The online APK cannot match renamed files by CRC. Stay conservative:
        # eligibility must be identifiable from names/aliases, without ROM reads.
        return '', 0

    def resolve(self, core, path, validate=True):
        found, reason = super().resolve(core, path, validate)
        if reason == 'no installed JPEG artwork':
            reason = 'no cached database; run SAM artwork setup/refresh'
        return found, reason

    def decode(self, virtual_image):
        relative = Path(virtual_image).relative_to(self.database / 'docs')
        folder, key = relative.parts[0], relative.stem
        identifier = hashlib.sha256(f'{folder}/{key}'.encode('utf-8')).hexdigest()
        image = self.downloads / self.style / folder / (identifier + '.jpg')
        good = False
        if image.is_file():
            good = super().decode(str(image))
        if not good:
            data = fetch(folder_url(folder, self.style, self.base) + quote(key, safe='') + '.jpg', 8 * 1024 * 1024)
            atomic_write(image, data)
            if not super().decode(str(image)):
                image.unlink(missing_ok=True)
                return False
        stamp = image.stat()
        os.utime(image, ns=(time.time_ns(), stamp.st_mtime_ns))
        self.last_image = str(image)
        self.trim(image)
        return True

    def trim(self, protected):
        pins = {protected}
        root = getattr(self, 'protected_root', None)
        if root:
            for record in Path(root).glob('*.record'):
                try:
                    for line in record.read_text(encoding='utf-8').splitlines():
                        if line.startswith('cover='): pins.add(Path(line.split('=', 1)[1]))
                except OSError: pass
        entries = []
        for image in self.downloads.glob('*/*/*.jpg'):
            try:
                stamp = image.stat()
                entries.append((stamp.st_atime_ns, stamp.st_size, image))
            except OSError: continue
        total = sum(size for _, size, _ in entries)
        for _, size, image in sorted(entries):
            if total <= CACHE_BYTES: break
            if image in pins: continue
            try:
                image.unlink()
                total -= size
                self.images.pop(str(image), None)
            except OSError: pass


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Download/refresh small SAM artwork catalogs')
    parser.add_argument('--root', required=True)
    parser.add_argument('--cores', required=True, help='Comma-separated SAM core IDs')
    parser.add_argument('--refresh', action='store_true')
    args = parser.parse_args()
    raise SystemExit(setup(args.root, [c.strip().lower() for c in args.cores.split(',') if c.strip()], args.refresh))
