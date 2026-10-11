# SPDX-License-Identifier: GPL-3.0-or-later
"""Change-only INI reads and owner-bound RAM reload requests.

Only the existing once-per-second status checker calls this watcher. Configuration
is literal data here; this module never evaluates shell expressions.
"""
import hashlib
import os
from pathlib import Path
import re
import shlex
import stat
from .session import owner_key

IMMEDIATE = {'gametimer', 'samtimeout', 'menuonly', 'listenjoy', 'listenkeyboard',
             'listenmouse', 'ignore_when_skip', 'samdebug', 'samdebuglog', 'm82_game_timer'}
SELECTION = {'corelist', 'corelistall', 'rating', 'kids_safe', 'dupe_mode', 'arcadeorient',
             'norepeat', 'disable_blacklist', 'coreweight', 'amigaselect', 'exclude',
             'skiptime', 'skipmessage', 'disablebootrom', 'category_preset'}
DEFAULTS = dict(rating='no', kids_safe='no', dupe_mode='normal', arcadeorient='', norepeat='yes',
                disable_blacklist='no', coreweight='no', amigaselect='all', exclude='',
                skiptime='10', skipmessage='yes', disablebootrom='no', category_preset='off')
DEFAULT_CORES = 'amiga,amigacd32,ao486,arcade,atari2600,atari5200,atari7800,atarilynx,c64,cdi,coco2,colecovision,intellivision,fds,gb,gbc,gba,genesis,gg,jaguar,megacd,n64,neogeo,neogeocd,nes,s32x,saturn,sgb,sms,snes,stv,tgfx16,tgfx16cd,3do,vectrex,wonderswan,wonderswancolor,psx,x68k,mgls'
DEFAULTS.update(corelist=DEFAULT_CORES, corelistall=DEFAULT_CORES)


def bounded_bytes(path, missing=b''):
    descriptor = None
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_NOFOLLOW', 0))
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError('Configuration must be a regular file')
        data = os.read(descriptor, 65537)
        if len(data) > 65536:
            raise ValueError('Configuration exceeds 64 KiB')
        return data
    except FileNotFoundError:
        return missing
    finally:
        if descriptor is not None:
            os.close(descriptor)


def parse_ini(data):
    values = {}
    for line in data.decode('utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith(('#', ';')):
            continue
        match = re.fullmatch(r'([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(.*)', line)
        if not match:
            raise ValueError('Live reload requires literal INI assignments')
        key, raw = match.groups()
        tokens = shlex.split(raw, comments=True, posix=True)
        if raw.startswith('('):
            if key != 'exclude':
                raise ValueError('Live reload supports only the literal exclude array')
            if not tokens or not tokens[0].startswith('(') or not tokens[-1].endswith(')'):
                raise ValueError('Unclosed INI array')
            tokens[0] = tokens[0][1:]
            tokens[-1] = tokens[-1][:-1]
            value = tuple(token for token in tokens if token)
        elif len(tokens) <= 1:
            value = tokens[0] if tokens else ''
        else:
            raise ValueError('Unquoted INI value')
        literals = value if isinstance(value, tuple) else (value,)
        if any(any(character in literal for character in ('\n', '\r', '\0', '`', '$')) for literal in literals):
            raise ValueError('Live reload requires literal values')
        values[key] = value
    for key, fallback in (('gametimer', '120'), ('samtimeout', '60'), ('m82_game_timer', '180')):
        raw = values.get(key, fallback)
        if not re.fullmatch(r'[0-9]{1,8}', raw):
            raise ValueError('Invalid ' + key)
    return values


def signature(path):
    try:
        info = os.stat(path, follow_symlinks=False)
        return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns
    except FileNotFoundError:
        return None


class IniWatcher:
    def __init__(self, ini_path, runtime_root, list_root=None):
        self.ini_path = Path(ini_path)
        self.root = Path(runtime_root)
        self.tags_path = Path(list_root or '/media/fat/SAM/Gamelists') / '.excludetags'
        self.identity = None
        self.pending_identity = None
        self.values = None
        self.data = b''
        self.category = b''
        self.roulette = b''
        self.tags = b''
        self.published = None

    def poll(self, owner=None):
        paths = (self.ini_path, self.root / 'category-preset', self.root / 'gameroulette.ini', self.tags_path)
        identity = tuple(signature(path) for path in paths)
        if identity[0] is None:
            raise ValueError('SAM INI is unavailable; retaining running settings')
        changed = identity != self.identity
        if changed:
            # Editors may rewrite in place. Require two ordinary checker samples
            # with the same identity before consuming a changed file.
            if self.values is not None and self.pending_identity != identity:
                self.pending_identity = identity
                return None
            data, category, roulette, tags = (bounded_bytes(path) for path in paths)
            values = parse_ini(data)
            values.update(parse_ini(roulette))
            if identity != tuple(signature(path) for path in paths):
                return None
            self.identity, self.pending_identity = identity, None
            self.data, self.category, self.roulette, self.values = data, category, roulette, values
            self.tags = tags
        if self.values is None:
            return None
        key = owner_key(owner)
        publication = (key, self.identity)
        if key and publication != self.published:
            session = self.root / ('session-%s:%s' % key)
            if session.is_dir() and (session / 'config.ini').is_file():
                baseline = parse_ini(bounded_bytes(session / 'config.ini'))
                baseline.update(parse_ini(bounded_bytes(session / 'config-roulette')))
                differences = {name for name in self.values.keys() | baseline.keys()
                               if self.values.get(name) != baseline.get(name)}
                structural = any(name not in IMMEDIATE | SELECTION and not name.endswith('pathfilter') for name in differences)
                structural |= self.roulette.rstrip(b'\r\n') != bounded_bytes(session / 'config-roulette').rstrip(b'\r\n')
                selection = bool(differences - IMMEDIATE) or self.category.rstrip(b'\r\n') != bounded_bytes(session / 'config-category').rstrip(b'\r\n')
                selection |= self.tags.rstrip(b'\r\n') != bounded_bytes(session / 'config-tags').rstrip(b'\r\n')
                revision = hashlib.sha256(self.data + b'\0' + self.category + b'\0' + self.roulette + b'\0' + self.tags).hexdigest()
                record = dict(pid=key[0], start=key[1], revision=revision,
                              structural=str(int(structural)), selection=str(int(selection)),
                              gametimer=self.values.get('gametimer', '120'),
                              m82timer=self.values.get('m82_game_timer', '180'),
                              debug=self.values.get('samdebug', 'no'), debuglog=self.values.get('samdebuglog', 'no'))
                for name in SELECTION | {name for name in self.values if name.endswith('pathfilter')}:
                    if name != 'exclude':
                        record['setting_' + name] = self.values.get(name, DEFAULTS.get(name, ''))
                # The only supported array consists of literal words. Encode
                # each word separately, never shell syntax to source/evaluate.
                excluded = self.values.get('exclude', ())
                if isinstance(excluded, str):
                    excluded = (excluded,) if excluded else ()
                for index, word in enumerate(excluded):
                    record['exclude_' + str(index)] = word
                temporary = session / ('config-update.tmp.%s' % os.getpid())
                try:
                    # Versioned comparison baselines let the foreground promote
                    # exactly the snapshot it applied, even if a newer edit arrives.
                    for suffix, content in (('ini', self.data), ('category', self.category), ('roulette', self.roulette), ('tags', self.tags)):
                        (session / ('config-%s.%s' % (revision, suffix))).write_bytes(content)
                    temporary.write_text(''.join('%s=%s\n' % item for item in record.items()), encoding='utf-8')
                    os.replace(temporary, session / 'config-update')
                    self.published = publication
                except FileNotFoundError:
                    temporary.unlink(missing_ok=True)
        return dict(self.values) if changed else None
