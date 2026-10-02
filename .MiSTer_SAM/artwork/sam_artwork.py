#!/usr/bin/env python3
"""SAM artwork matching using its bundled, monitor-compatible pack resolver."""
import argparse
import ast
import ctypes
import hashlib
import io
import json
import os
from pathlib import Path
import re
import threading
import zipfile
import zlib
import xml.etree.ElementTree as ET

SYSTEMS = dict(nes='NES', fds='FDS', snes='SNES', n64='N64', gb='GAMEBOY',
    gbc='GBC', sgb='GAMEBOY', gba='GBA', genesis='Genesis', sms='SMS', gg='GameGear',
    megacd='MegaCD', saturn='Saturn', tgfx16='TGFX16', tgfx16cd='TGFX16-CD',
    psx='PSX', atari2600='Atari2600', atari5200='ATARI5200', atari7800='ATARI7800',
    atarilynx='AtariLynx', jaguar='Jaguar', neogeo='NEOGEO', neogeocd='NeoGeo-CD',
    s32x='S32X', colecovision='Coleco', intellivision='Intellivision',
    vectrex='VECTREX', wonderswan='WonderSwan', wonderswancolor='WonderSwanColor',
    amigacd32='AmigaCD32', cdi='CD-i', arcade='Arcade', stv='Arcade')
SYSTEMS['3do'] = '3DO'

def monitor_namespace(source):
    # Import only resolver definitions: never start the server or its threads.
    tree = ast.parse(Path(source).read_text(encoding='utf-8'))
    names = {'_PACK_SYSTEM', '_PACK_MOUNTS', '_PACK_SIBLINGS', '_PACK_BORROWS', '_MRA_READ_CAP', '_MRA_SETNAME_RE'}
    funcs = {'_pack_dir', '_pack_folders', '_pack_lookup_any', '_pack_title',
             '_pack_index', '_pack_lookup', '_pack_key_from_state', '_mra_setname', '_get_mtime_ns'}
    nodes = [n for n in tree.body if
             isinstance(n, ast.FunctionDef) and n.name in funcs or
             isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id in names for t in n.targets)]
    ns = dict(os=os, re=re, io=io, threading=threading, ET=ET,
              _pack_index_cache={}, _pack_index_lock=threading.Lock(),
              _mra_setname_cache={}, _mra_setname_lock=threading.Lock())
    exec(compile(ast.Module(body=nodes, type_ignores=[]), source, 'exec'), ns)
    if not funcs.issubset(ns):
        raise RuntimeError('Installed monitor lacks required resolver functions')
    return ns

class Catalogue:
    def __init__(self, source, cache):
        self.ns = monitor_namespace(source)
        self.cache_path = Path(cache)
        try:
            self.cache = json.loads(self.cache_path.read_text())
        except (OSError, ValueError):
            self.cache = {}
        self.images = self.cache.setdefault('images', {})
        self.hashes = self.cache.setdefault('hashes', {})
        self.zips = {}
        self.available_folders = {}
        self.source_digest = hashlib.sha256(Path(source).read_bytes()).hexdigest()
        self.inventory = {}

    def fast_names(self):
        """One directory/index read per pack, no per-ROM artwork stat calls."""
        import types
        original_dir = self.ns['_pack_dir']
        original_index = self.ns['_pack_index']
        directories, indexes, images = {}, {}, {}
        def directory(folder):
            if folder not in directories:
                value = original_dir(folder)
                directories[folder] = value
                if value:
                    images[value] = {entry.name for entry in os.scandir(value) if entry.name.endswith('.jpg')}
                    self.available_folders[folder] = bool(images[value])
            return directories[folder]
        def index(value):
            if value not in indexes: indexes[value] = original_index(value)
            return indexes[value]
        def isfile(path):
            parent, name = os.path.split(path)
            return name in images[parent] if parent in images else os.path.isfile(path)
        proxy_path = types.SimpleNamespace(**vars(os.path))
        proxy_path.isfile = isfile
        proxy_os = types.SimpleNamespace(**vars(os))
        proxy_os.path = proxy_path
        self.ns['os'] = proxy_os
        self.ns['_pack_dir'] = directory
        self.ns['_pack_index'] = index

    def fingerprint(self, core, paths):
        folders = {SYSTEMS.get(core, '')}
        if core == 'nes': folders.add('FDS')
        if core == 'snes': folders.add('Satellaview')
        if core == 'genesis': folders.add('SMS')
        if core == 'atari7800': folders.add('Atari2600')
        if core == 'neogeo': folders.add('NeoGeo-CD')
        if core == 'sgb': folders.add('GBC')
        for folder in tuple(folders):
            folders.update(self.ns['_PACK_SIBLINGS'].get(folder, ()))
        inventory = []
        for folder in sorted(folders):
            if folder not in self.inventory:
                entries = []
                # Include all mounts: monitor chooses the first installed folder.
                for mount in self.ns['_PACK_MOUNTS']:
                    directory = Path(mount) / 'docs' / folder / 'Artwork'
                    if not folder or not directory.is_dir(): continue
                    for entry in sorted(directory.iterdir()):
                        if entry.suffix.lower() not in {'.jpg', '.tsv'}: continue
                        try:
                            stat = entry.stat()
                            entries.append((str(entry), stat.st_size, stat.st_mtime_ns))
                        except OSError: pass
                self.inventory[folder] = entries
            inventory.extend(self.inventory[folder])
        roms = set()
        for path in paths:
            match = re.search(r'(?i)\.zip/', path)
            roms.add(path[:match.end()-1] if match else path)
        stamps = []
        for path in sorted(roms):
            try:
                stat = os.stat(path)
                stamps.append((path, stat.st_size, stat.st_mtime_ns))
            except OSError: stamps.append((path, None, None))
        return hashlib.sha256(json.dumps([self.source_digest, inventory, paths, stamps]).encode()).hexdigest()

    def decode(self, path):
        stamp = list((os.stat(path).st_mtime_ns, os.stat(path).st_size))
        old = self.images.get(path)
        if old and old['stamp'] == stamp:
            return old['ok']
        # Full JPEG pixel decode with the MiSTer's existing libturbojpeg.
        lib = ctypes.CDLL('libturbojpeg.so.0')
        lib.tjInitDecompress.restype = ctypes.c_void_p
        lib.tjDecompressHeader3.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong] + [ctypes.POINTER(ctypes.c_int)] * 4
        lib.tjDecompress2.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p] + [ctypes.c_int] * 5
        lib.tjDestroy.argtypes = [ctypes.c_void_p]
        data = Path(path).read_bytes()
        buf = ctypes.create_string_buffer(data)
        handle = lib.tjInitDecompress()
        w, h, sub, color = [ctypes.c_int() for _ in range(4)]
        ok = False
        try:
            if handle and lib.tjDecompressHeader3(handle, buf, len(data), ctypes.byref(w), ctypes.byref(h), ctypes.byref(sub), ctypes.byref(color)) == 0:
                if 0 < w.value * h.value <= 20000000:
                    pixels = ctypes.create_string_buffer(w.value * h.value * 3)
                    ok = lib.tjDecompress2(handle, buf, len(data), pixels, w.value, 0, h.value, 0, 0) == 0
        finally:
            if handle:
                lib.tjDestroy(handle)
        self.images[path] = dict(stamp=stamp, ok=ok)
        return ok

    def metadata(self, path):
        match = re.search(r'(?i)\.zip/', path)
        if match:
            archive, member = path[:match.end()-1], path[match.end():]
            if archive not in self.zips:
                with zipfile.ZipFile(archive) as z:
                    self.zips[archive] = {i.filename.lower(): i for i in z.infolist()}
            info = self.zips[archive].get(member.lower())
            if info:
                return '%08X' % info.CRC, info.file_size
            return '', 0
        p = Path(path)
        if not p.is_file() or p.suffix.lower() in {'.chd', '.iso', '.cue', '.pbp', '.mra', '.mgl', '.zip'}:
            return '', 0
        stat = p.stat()
        if stat.st_size > 16 * 1024 * 1024:
            return '', 0
        stamp = [stat.st_mtime_ns, stat.st_size]
        old = self.hashes.get(path)
        if old and old['stamp'] == stamp:
            return old['crc'], stat.st_size
        crc = 0
        with p.open('rb') as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b''):
                crc = zlib.crc32(chunk, crc)
        crc = '%08X' % (crc & 0xffffffff)
        self.hashes[path] = dict(stamp=stamp, crc=crc)
        return crc, stat.st_size

    def resolve(self, core, path, validate=True):
        folder = SYSTEMS.get(core)
        if not folder:
            return '', 'unsupported system/layout'
        # Shared cores must follow the monitor's extension-based system routing.
        ext = Path(path).suffix.lower()
        if core == 'genesis' and ext == '.sms': folder = 'SMS'
        if core == 'atari7800':
            if ext == '.a26': folder = 'Atari2600'
            elif ext != '.a78':
                try:
                    with open(path, 'rb') as f: head = f.read(16)
                    folder = 'ATARI7800' if head[1:10] == b'ATARI7800' else 'Atari2600'
                except OSError: folder = 'Atari2600'
        if core == 'nes' and ext in {'.fds', '.qd'}: folder = 'FDS'
        if core == 'snes' and ext == '.bs': folder = 'Satellaview'
        if core == 'neogeo' and ext in {'.cue', '.chd', '.iso'}: folder = 'NeoGeo-CD'
        folders = [folder] + list(self.ns['_PACK_SIBLINGS'].get(folder, ()))
        if core == 'sgb': folders = ['GAMEBOY', 'GBC']
        for f in folders:
            if f not in self.available_folders:
                directory = self.ns['_pack_dir'](f)
                self.available_folders[f] = bool(directory and any(Path(directory).glob('*.jpg')))
        if not any(self.available_folders[f] for f in folders):
            return '', 'no installed JPEG artwork'
        keys = (self.ns['_pack_key_from_state'](path, core in {'arcade', 'stv'})
                if validate or getattr(self, 'full_keys', False) or core in {'arcade', 'stv', 'neogeo'}
                else [os.path.splitext(os.path.basename(path))[0]])
        found, _, _ = self.ns['_pack_lookup_any'](folders, keys, '', '')
        if not found and (validate or '.zip/' in path.lower()):
            crc, size = self.metadata(path)
            found, _, _ = self.ns['_pack_lookup_any'](folders, keys, crc, size)
        if not found: return '', 'no monitor match'
        return (found, '') if not validate or self.decode(found) else ('', 'image decode failed')

    def save(self):
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.cache_path.with_suffix('.tmp')
        tmp.write_text(json.dumps(self.cache))
        tmp.replace(self.cache_path)

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--server', default=str(Path(__file__).with_name('sam_artwork_resolver.py')),
                   help='Resolver source override for compatibility tests; normally use the bundled resolver')
    p.add_argument('--cache', required=True)
    p.add_argument('--source', choices=('packs', 'database'), default='packs')
    p.add_argument('--style', choices=('box2d', 'box3d'), default='box2d')
    p.add_argument('--database', default=str(Path(__file__).with_name('database')))
    p.add_argument('--downloads', default=str(Path(__file__).with_name('downloads')))
    p.add_argument('--lists')
    p.add_argument('--output')
    p.add_argument('--cores', help='Optional comma-separated SAM core names')
    p.add_argument('--names-only', action='store_true', help='Fast per-core name/index filter; decode only the chosen image before launch')
    p.add_argument('--cover-output')
    p.add_argument('--protected-root')
    p.add_argument('--check', nargs=2, metavar=('CORE', 'PATH'))
    a = p.parse_args()
    if a.source == 'database':
        from sam_artwork_database import DatabaseCatalogue, ensure_catalogs
        cores = [a.check[0]] if a.check else (a.cores.split(',') if a.cores else None)
        if cores is None:
            cores = [source.name.removesuffix('_gamelist.txt')
                     for source in Path(a.lists).glob('*_gamelist.txt')]
        if not ensure_catalogs(a.database, cores):
            return 3  # Download failure, not an empty matching result.
        cat = DatabaseCatalogue(a.server, a.cache, a.database, a.downloads, a.style, cores=cores)
    else:
        cat = Catalogue(a.server, a.cache)
    cat.protected_root = a.protected_root
    if a.names_only: cat.fast_names()
    if a.check:
        try: found, reason = cat.resolve(*a.check)
        except Exception as error: found, reason = '', str(error)
        cat.save()
        if found and a.cover_output:
            from sam_artwork_database import atomic_write
            atomic_write(Path(a.cover_output), (getattr(cat, "last_image", found) + "\n").encode("utf-8"))
        if not found: print('SAM artwork: ' + reason, file=__import__('sys').stderr)
        return 0 if found else 1
    out = Path(a.output)
    out.mkdir(parents=True, exist_ok=True)
    try: summary = json.loads((out / 'summary.json').read_text())
    except (OSError, ValueError): summary = {}
    any_selected = False
    # Build atomically per core; never modify original SAM lists or ROMs.
    for source in sorted(Path(a.lists).glob('*_gamelist.txt')):
        core = source.name.removesuffix('_gamelist.txt')
        if a.cores and core not in a.cores.split(','): continue
        accepted, rejected = [], []
        paths = [s for s in source.read_text(errors='replace').splitlines() if s]
        fingerprint = None if a.names_only else cat.fingerprint(core, paths)
        cached = cat.cache.setdefault('catalogues', {}).get(core, {})
        if not a.names_only and cached.get('fingerprint') == fingerprint:
            accepted, rejected = cached['accepted'], cached['rejected']
        else:
            for count, path in enumerate(paths):
                if count and count % 500 == 0:
                    print('%s: scanned %d/%d candidates' % (core, count, len(paths)), flush=True)
                try: found, reason = cat.resolve(core, path, validate=not a.names_only)
                except Exception as e: found, reason = '', str(e)
                if found: accepted.append(path)
                else: rejected.append(dict(path=path, reason=reason))
            if not a.names_only:
                cat.cache['catalogues'][core] = dict(fingerprint=fingerprint, accepted=accepted, rejected=rejected)
        cat.save()
        target = out / source.name
        tmp = target.with_suffix('.tmp')
        tmp.write_text(''.join(s + '\n' for s in accepted))
        tmp.replace(target)
        summary[core] = dict(eligible=len(accepted), excluded=len(rejected))
        any_selected = any_selected or bool(accepted)
        (out / (core + '_excluded.json')).write_text(json.dumps(rejected, indent=2))
        print('%s: %s eligible, %s excluded' % (core, len(accepted), len(rejected)), flush=True)
    cat.save()
    (out / 'summary.json').write_text(json.dumps(summary, indent=2))
    return 0 if any_selected else 2

if __name__ == '__main__':
    raise SystemExit(main())
