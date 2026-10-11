# SPDX-License-Identifier: GPL-3.0-or-later
"""Remember a definitive empty selection in RAM until its inputs change.

No collection traversal, ROM hashing or timer/input polling happens here. The
foreground records one outcome; MCP checks cached dependency metadata only when
autostart is blocked. Explicit starts clear the record after owned cleanup.
"""
import argparse
import ast
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import time

if __package__ in (None, ''):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sam.config_reload import DEFAULT_CORES, bounded_bytes, parse_ini, signature
from sam.session import owner_key, read_literal_file, read_session

MAX_RECORD = 256 * 1024


def read_json(path):
    descriptor = None
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_NOFOLLOW', 0))
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            return None
        data = os.read(descriptor, MAX_RECORD + 1)
        return json.loads(data) if len(data) <= MAX_RECORD else None
    except (OSError, ValueError, UnicodeError):
        return None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def literal_mapping(path, name):
    """Read only a published dict's literals, never import artwork code."""
    try:
        data = bounded_bytes(path)
        tree = ast.parse(data.decode('utf-8'))
        result = {}
        for node in tree.body:
            if not isinstance(node, ast.Assign):
                continue
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == name:
                    value = node.value
                    if isinstance(value, ast.Call) and isinstance(value.func, ast.Name) and value.func.id == 'dict' and not value.args:
                        result = {item.arg: ast.literal_eval(item.value) for item in value.keywords if item.arg}
                    elif isinstance(value, ast.Dict):
                        result = ast.literal_eval(value)
                elif isinstance(target, ast.Subscript) and isinstance(target.value, ast.Name) and target.value.id == name:
                    # Python 3.9+ represents the subscript directly.
                    result[ast.literal_eval(target.slice)] = ast.literal_eval(node.value)
        return result
    except (OSError, ValueError, SyntaxError, TypeError, UnicodeError):
        return {}


def dependency_paths(ini, lists, root, runtime, values):
    """Fixed metadata inputs for the configured cores; no ROM tree walking."""
    cores = sorted(set(str(values.get('corelist', DEFAULT_CORES)).lower().replace(' ', '').split(',')))
    if not cores or len(cores) > 64 or any(not re.fullmatch(r'[a-z0-9_]{1,32}', core) for core in cores):
        raise ValueError('Invalid core list for empty-selection record')
    public = lists.parent
    paths = {ini, runtime/'category-preset', runtime/'gameroulette.ini', lists/'.excludetags',
             root/'artwork/database/.generation', root/'modules', root/'lib',
             root/'sam_titles.py', root/'sam_kids_filter.py', root/'sam_compat.json',
             root/'artwork/sam_artwork_resolver.py', root/'artwork/sam_artwork.py',
             root/'artwork/sam_artwork_database.py'}
    for folder in ('modules', 'lib'):
        # Small code directory only, once per failed selection, never ROM files.
        paths.update((root/folder).glob('*.sh'))
        paths.update((root/folder).glob('*.py'))
    for core in cores:
        paths.update((lists/(core+'_gamelist.txt'), lists/(core+'.partial'),
                      public/'Rated'/(core+'_rated.txt'), public/'Rated'/(core+'_mature.txt'),
                      public/'Blacklists'/(core+'_blacklist.txt'),
                      public/'Blacklists'/(core+'_gamelist_exclude.txt'),
                      public/'Ignore'/(core+'_excludelist.txt')))
    systems = literal_mapping(root/'artwork/sam_artwork.py', 'SYSTEMS')
    extras = literal_mapping(root/'artwork/sam_artwork_database.py', 'EXTRA')
    folders = set()
    for core in cores:
        if core in systems:
            folders.add(systems[core])
            folders.update(extras.get(core, ()))
    if str(values.get('Artwork_source', 'database')).lower() == 'database':
        for folder in folders:
            directory = root/'artwork/database/docs'/folder/'Artwork'
            paths.update((directory/'index.tsv', directory/'gameinfo.tsv'))
    else:
        for folder in folders:
            for mount in (Path('/media/fat'), *(Path('/media/usb%d' % i) for i in range(8))):
                directory = mount/'docs'/folder/'Artwork'
                paths.add(directory)
                if directory.is_dir():
                    paths.add(directory/'index.tsv')
                    break
    if 'arcade' in cores or 'stv' in cores:
        custom = os.environ.get('SAM_ARCADE_ORGANIZER_DATA')
        if custom:
            paths.add(Path(custom))
        else:
            paths.update((root.parent/'.config/arcade-organizer/data.zip',
                          root.parent/'.cache/arcade-organizer/data.zip'))
    return sorted(str(path.absolute()) for path in paths)


def metadata(paths):
    return {path: list(value) if (value := signature(path)) is not None else None for path in paths}


def same_configuration(session, ini, lists, runtime):
    comparisons = ((session/'config.ini', ini),
                   (session/'config-category', runtime/'category-preset'),
                   (session/'config-roulette', runtime/'gameroulette.ini'),
                   (session/'config-tags', lists/'.excludetags'))
    return (session/'config.ini').is_file() and all(
        bounded_bytes(saved).rstrip(b'\r\n') == bounded_bytes(current).rstrip(b'\r\n')
        for saved, current in comparisons)


def record_empty(session, mode, target, ini, lists, root, runtime, owner, revision='1'):
    if mode != 'ALL' or target:
        return False  # Single-core testing does not veto configured autoplay.
    pid, separator, ticks = owner.partition(':')
    if not separator or not pid.isdecimal() or not ticks.isdecimal():
        return False
    key = (pid, ticks)
    expected_outcome = ('reason=no_eligible_games\nrevision='+str(revision)+'\n').encode('ascii')
    if session != runtime/('session-'+owner):
        return False
    lock = None
    staged = None
    try:
        lock = os.open(runtime/'session-owner.lock', os.O_WRONLY | os.O_CREAT, 0o600)
        deadline = time.monotonic()+2
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    return False
                time.sleep(.02)
        if (owner_key(read_session(str(runtime/'session-owner'))) != key
                or not (session/'alive').is_file()
                or bounded_bytes(session/'outcome') != expected_outcome
                or not same_configuration(session, ini, lists, runtime)):
            return False
        values = parse_ini(bounded_bytes(ini))
        paths = dependency_paths(ini, lists, root, runtime, values)
        state = metadata(paths)
        if (owner_key(read_session(str(runtime/'session-owner'))) != key
                or not (session/'alive').is_file()
                or bounded_bytes(session/'outcome') != expected_outcome
                or not same_configuration(session, ini, lists, runtime)):
            return False
        outcome = dict(version=1, reason='no_eligible_games', owner=list(key),
                       context=[str(path.absolute()) for path in (ini, lists, root)], inputs=state)
        data = json.dumps(outcome, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        if len(data) > MAX_RECORD:
            return False
        descriptor, name = tempfile.mkstemp(prefix='.autostart-empty.', dir=runtime)
        staged = Path(name)
        with os.fdopen(descriptor, 'wb') as output:
            output.write(data)
        os.replace(staged, runtime/'autostart-empty.json')
        return True
    finally:
        if staged is not None:
            staged.unlink(missing_ok=True)
        if lock is not None:
            os.close(lock)


class EmptySelectionGuard:
    def __init__(self, ini, lists, root, runtime, clock=time.monotonic, interval=5):
        self.ini, self.lists, self.root, self.runtime = map(Path, (ini, lists, root, runtime))
        self.path = self.runtime/'autostart-empty.json'
        self.context = [str(path.absolute()) for path in (self.ini, self.lists, self.root)]
        self.clock, self.interval = clock, interval
        self.marker = None
        self.record = None
        self.next_check = 0

    def poll(self):
        marker = signature(self.path)  # RAM metadata only on ordinary ticks.
        if marker != self.marker:
            self.marker, self.record, self.next_check = marker, read_json(self.path), 0
        item = self.record
        if (not isinstance(item, dict) or item.get('version') != 1
                or item.get('reason') != 'no_eligible_games' or item.get('context') != self.context
                or not isinstance(item.get('inputs'), dict) or not 1 <= len(item['inputs']) <= 2048
                or any(not isinstance(path, str) or not Path(path).is_absolute()
                       or len(path) > 4096 for path in item['inputs'])):
            return False
        if self.clock() < self.next_check:
            return True
        self.next_check = self.clock()+self.interval
        if metadata(item['inputs']) == item['inputs']:
            return True
        # Publication uses this same transition lock. Recheck under it so a
        # newer failure cannot replace the file between comparison and unlink.
        descriptor = os.open(self.runtime/'session-owner.lock', os.O_WRONLY | os.O_CREAT, 0o600)
        try:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return False  # No waiting on an owner transition; reload next tick.
            if signature(self.path) == marker:
                self.path.unlink(missing_ok=True)
        finally:
            os.close(descriptor)
            self.marker, self.record = None, None
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('record',))
    for name in ('session', 'mode', 'target', 'ini', 'lists', 'root', 'runtime', 'owner', 'revision'):
        parser.add_argument('--'+name, required=True)
    args = parser.parse_args(argv)
    try:
        recorded = record_empty(Path(args.session), args.mode, args.target, Path(args.ini),
                                Path(args.lists), Path(args.root), Path(args.runtime), args.owner, args.revision)
        if recorded:
            print('SAM: No eligible games; automatic starts suspended until settings or catalogues change. Use m start to retry.', file=sys.stderr)
        return 0
    except (OSError, ValueError, UnicodeError) as error:
        print('SAM: Could not remember empty selection: '+str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
