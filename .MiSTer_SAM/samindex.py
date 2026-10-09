#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Interpreted SAM scanner. Exit 0=games, 8=successful empty scan, 2=failure."""
import argparse
import fcntl
import hashlib
import json
import os
import stat
from pathlib import Path
import signal
import sys
import tempfile
import time
import zipfile

from sam_catalog import Catalog, CatalogError, ROOT
from sam_zip import DirectoryZip

VERSION = 'samindex-python 1.0'
CACHE_VERSION = 3


def verified_cache(path, identity):
    """Verify a complete cache before emitting any paths; memory stays bounded."""
    with open(path, 'rb') as stream:
        if json.loads(stream.readline()) != identity: return None
        start = stream.tell()
        stream.seek(0, os.SEEK_END)
        end = stream.tell()
        stream.seek(max(start, end-512))
        tail = stream.read()
        footer_line = tail.splitlines()[-1]
        footer = json.loads(footer_line)
        if not isinstance(footer, dict) or type(footer.get('complete')) is not int:
            raise ValueError('Missing cache completion record')
        payload_end = end - len(footer_line) - 1
        digest = hashlib.sha256(); count = 0
        stream.seek(start)
        remaining = payload_end-start
        while remaining > 0:
            block = stream.read(min(65536, remaining))
            if not block: raise ValueError('Truncated cache')
            digest.update(block); count += block.count(b'\n'); remaining -= len(block)
        if digest.hexdigest() != footer.get('sha256'): raise ValueError('Corrupt cache payload')
        if count != footer['complete']: raise ValueError('Corrupt cache member count')
    return start, payload_end, count


def warn(message):
    print('samindex: ' + message, file=sys.stderr)


def find_folder(path):
    """Exact paths win; otherwise match only the final folder, as mrext does."""
    try:
        if os.path.isdir(path): return path
        parent, name = os.path.split(path.rstrip('/'))
        with os.scandir(parent) as entries:
            choices = sorted(e.name for e in entries if len(e.name) == len(name) and e.name.lower() == name.lower())
        for choice in choices:
            found = os.path.join(parent, choice)
            if os.path.isdir(found): return found
    except FileNotFoundError:
        return None
    return None


class Scanner:
    def __init__(self, catalog, roots=None, cache=None, refresh=False):
        self.catalog = catalog
        self.roots = roots if roots is not None else catalog.compat['storage_roots']
        self.cache = Path(cache) if cache else None
        self.refresh = refresh
        self.hits = self.misses = self.corrupt = 0
        self.root_folders = []
        for root in self.roots:
            resolved = find_folder(root)
            if resolved and resolved not in self.root_folders: self.root_folders.append(resolved)

    def folders(self, identifier, active=False):
        core = self.catalog.sam_system(identifier)
        results = []
        seen = set()
        for root in self.root_folders:
            # A medium disappearing after discovery is an error, not an empty
            # collection. Preserve the last published list in that case.
            if not stat.S_ISDIR(os.stat(root).st_mode):
                raise OSError('Storage root is no longer a directory: ' + root)
            for folder in core.get('folders', []):
                path = find_folder(os.path.join(root, folder))
                if path and path not in seen:
                    seen.add(path); results.append(path)
                    if active: return results
        return results

    def members(self, archive):
        stamp = os.stat(archive)
        identity = dict(format=CACHE_VERSION, path=os.path.abspath(archive), size=stamp.st_size,
                        mtime_ns=stamp.st_mtime_ns, inode=stamp.st_ino, device=stamp.st_dev)
        cache_file = None
        if self.cache:
            key = hashlib.sha256(os.fsencode(os.path.abspath(archive))).hexdigest()
            cache_file = self.cache / (key + '.members')
            if not self.refresh:
                try:
                    verified = verified_cache(cache_file, identity)
                    if verified:
                        with cache_file.open('rb') as stream:
                            stream.seek(verified[0])
                            self.hits += 1
                            for _ in range(verified[2]):
                                line = stream.readline()
                                member = line[:-1].decode('utf-8')
                                yield member
                            after = os.stat(archive)
                            if (after.st_size, after.st_mtime_ns, after.st_ino, after.st_dev) != (stamp.st_size, stamp.st_mtime_ns, stamp.st_ino, stamp.st_dev):
                                raise OSError('Archive changed during cached scan: ' + archive)
                            return
                except FileNotFoundError: pass
                except (ValueError, UnicodeError, IndexError):
                    # A corrupt cache is not a corrupt ROM archive; rebuild it.
                    pass
        self.misses += 1
        temp = None
        stream = None
        try:
            if cache_file:
                cache_file.parent.mkdir(parents=True, exist_ok=True)
                fd, temp = tempfile.mkstemp(prefix=cache_file.name+'.tmp.', dir=str(cache_file.parent))
                stream = os.fdopen(fd, 'wb', buffering=1024*1024)
                stream.write((json.dumps(identity) + '\n').encode('ascii'))
            if stream is None:
                fd, temp = tempfile.mkstemp(prefix='sam-zip-members.')
                stream = os.fdopen(fd, 'wb', buffering=1024*1024)
                stream.write((json.dumps(identity) + '\n').encode('ascii'))
            digest = hashlib.sha256(); count = 0
            # Only the central directory is read; game data is never extracted.
            with DirectoryZip(archive) as bundle:
                for member in bundle.names():
                    if '\n' in member or '\r' in member:
                        warn('Skipping unrepresentable archive name'); continue
                    if stream:
                        line = (member + '\n').encode('utf-8')
                        stream.write(line); digest.update(line); count += 1
            after = os.stat(archive)
            if (after.st_size, after.st_mtime_ns, after.st_ino, after.st_dev) != (stamp.st_size, stamp.st_mtime_ns, stamp.st_ino, stamp.st_dev):
                raise OSError('Archive changed during scan: ' + archive)
            if stream:
                stream.write((json.dumps(dict(complete=count, sha256=digest.hexdigest()))+'\n').encode('ascii'))
                stream.flush(); os.fsync(stream.fileno()); stream.close(); stream = None
                if cache_file:
                    os.replace(temp, cache_file); temp = None
                    completed = cache_file
                else: completed = Path(temp)
                verified = verified_cache(completed, identity)
                with completed.open('rb') as payload:
                    payload.seek(verified[0])
                    for _ in range(verified[2]):
                        yield payload.readline()[:-1].decode('utf-8')
        except zipfile.BadZipFile as error:
            self.corrupt += 1
            warn('Skipping corrupt archive %s: %s' % (archive, error))
        finally:
            if stream: stream.close()
            if temp:
                try: os.unlink(temp)
                except FileNotFoundError: pass

    def walk(self, identifier, root):
        extensions = self.catalog.extensions(identifier)
        visited = set()
        stack = []
        def enter(real, display):
            if real in visited: return
            visited.add(real)
            with os.scandir(real) as entries:
                ordered = sorted(entries, key=lambda item: item.name)
            stack.append((real, display, iter(ordered)))
        enter(os.path.realpath(root), root)
        while stack:
            real, display, entries = stack[-1]
            try: entry = next(entries)
            except StopIteration:
                stack.pop(); continue
            name = entry.name
            shown = display + '/' + name
            if entry.is_symlink():
                try:
                    target = os.path.realpath(entry.path)
                    info = os.stat(target)
                except FileNotFoundError:
                    warn('Skipping broken symlink: ' + shown); continue
                if stat.S_ISDIR(info.st_mode): enter(target, shown); continue
                if not stat.S_ISREG(info.st_mode): continue
            elif entry.is_dir(follow_symlinks=False):
                enter(entry.path, shown); continue
            elif not entry.is_file(follow_symlinks=False): continue
            lower = name.lower()
            if lower.endswith('.zip'):
                for member in self.members(entry.path):
                    parts = member.replace('\\', '/').split('/')
                    if member.startswith('/') or '..' in parts or not parts[-1]:
                        warn('Skipping unsafe archive name: ' + member); continue
                    if not parts[-1].startswith('.') and member.lower().endswith(extensions):
                        yield shown + '/' + member
            elif not name.startswith('.') and lower.endswith(extensions):
                if '\n' in shown or '\r' in shown:
                    warn('Skipping unrepresentable path'); continue
                yield shown


def acquire_lock(path, timeout=60):
    stream = open(path, 'a+')
    deadline = time.monotonic() + timeout
    while True:
        try:
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return stream
        except BlockingIOError:
            if time.monotonic() >= deadline:
                stream.close(); raise OSError('Another indexer still holds ' + str(path))
            time.sleep(.1)


def scan_outputs(scanner, systems, directory, no_dupes=False, progress=False, quiet=False):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    staged = []
    total = 0
    try:
        for number, identifier in enumerate(systems):
            alias = scanner.catalog.sam_id(identifier)
            target = directory / (alias + '_gamelist.txt')
            fd, temp = tempfile.mkstemp(prefix=target.name+'.tmp.', dir=str(directory))
            staged.append((temp, target))
            count = 0
            exact, names = set(), set()
            # MiSTer commonly mounts FAT/exFAT with sync. Small writes each
            # trigger storage synchronization, so batch them in a bounded 1 MiB
            # buffer, then fsync once before publishing the complete list.
            with os.fdopen(fd, 'w', buffering=1024*1024, encoding='utf-8', errors='surrogateescape', newline='\n') as output:
                for folder in scanner.folders(identifier):
                    if not quiet:
                        if progress: print('XXX\n%d\nScanning %s (%s)\nXXX' % (number*100//len(systems), identifier, folder), flush=True)
                        else: print('Scanning %s: %s' % (identifier, folder), flush=True)
                    for path in scanner.walk(identifier, folder):
                        if path in exact: continue
                        exact.add(path)
                        base = path.rsplit('/', 1)[-1]
                        if no_dupes and base in names: continue
                        if no_dupes: names.add(base)
                        output.write(path + '\n'); count += 1
                output.flush(); os.fsync(output.fileno())
            total += count
        # Complete scans, including empty ones, replace stale lists. Any read or
        # write failure before this point leaves all previous outputs untouched.
        for temp, target in staged: os.replace(temp, target)
        return total
    finally:
        for temp, _ in staged:
            try: os.unlink(temp)
            except FileNotFoundError: pass


def main():
    # SAM cancels owned preparations with SIGTERM. Unwind staging/cache cleanup
    # and release locks rather than leaving abandoned temporary files.
    signal.signal(signal.SIGTERM, lambda number, frame: sys.exit(128 + number))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-q', action='store_true')
    parser.add_argument('-s', default='all')
    parser.add_argument('-o', default='.')
    parser.add_argument('-p', action='store_true')
    parser.add_argument('-d', action='store_true')
    parser.add_argument('-nodupes', action='store_true')
    parser.add_argument('-version', action='store_true')
    parser.add_argument('--refresh', action='store_true')
    parser.add_argument('--cache', default=str(ROOT / 'index-cache'))
    parser.add_argument('--root', action='append', help='Override discovery roots; may repeat')
    parser.add_argument('--catalog')
    parser.add_argument('--compat')
    parser.add_argument('--source-record')
    parser.add_argument('--lock-timeout', type=float, default=60)
    parser.add_argument('--stats', help='Write cache statistics as JSON')
    args = parser.parse_args()
    if args.version:
        print(VERSION); return 0
    started = time.monotonic()
    try:
        catalog = Catalog(args.catalog, args.compat, args.source_record)
        systems = sorted(catalog.systems) if args.s == 'all' else [s.strip() for s in args.s.split(',') if s.strip()]
        for identifier in systems: catalog.sam_system(identifier)
        scanner = Scanner(catalog, args.root, args.cache, args.refresh)
        if args.d:
            for identifier in systems:
                folders = scanner.folders(identifier, active=True)
                if folders: print(catalog.sam_id(identifier) + ':' + folders[0])
            return 0
        with _directory_lock(args.o, args.lock_timeout):
            total = scan_outputs(scanner, systems, args.o, args.nodupes, args.p, args.q)
        if args.stats:
            Path(args.stats).write_text(json.dumps(dict(seconds=time.monotonic()-started, games=total,
                zip_cache_hits=scanner.hits, zip_cache_misses=scanner.misses, corrupt_archives=scanner.corrupt)))
        if not args.q:
            text = 'Indexing complete (%d games in %.3fs)' % (total, time.monotonic()-started)
            print('XXX\n100\n'+text+'\nXXX' if args.p else text)
        return 0 if total else 8
    except (OSError, CatalogError, ValueError) as error:
        warn(str(error)); return 2


def _directory_lock(directory, timeout):
    Path(directory).mkdir(parents=True, exist_ok=True)
    return acquire_lock(Path(directory) / '.samindex.lock', timeout)


if __name__ == '__main__':
    sys.exit(main())
