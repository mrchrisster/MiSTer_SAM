# Copyright (C) 2025-2026 chipster6502
# SPDX-License-Identifier: AGPL-3.0-or-later
# Pack resolver extracted from MiSTer Monitor 2.11.1, distributed under AGPL v3+
# https://github.com/chipster6502/MiSTer_monitor
# No running or installed MiSTer Monitor is required by this bundled module.
import os
import re
import io
import threading
_pack_index_cache = {}
_pack_index_lock = threading.Lock()
_mra_setname_cache = {}
_mra_setname_lock = threading.Lock()

def _get_mtime_ns(path):
    """Returns mtime in nanoseconds, or 0 on error."""
    try:
        return os.stat(path).st_mtime_ns
    except:
        return 0
_MRA_SETNAME_RE = re.compile(b'<\\s*setname\\s*>\\s*([^<]+?)\\s*<\\s*/\\s*setname\\s*>', re.IGNORECASE)
_MRA_READ_CAP = 262144

def _mra_setname(mra_path):
    """The <setname> declared inside an .mra; '' when absent or unreadable."""
    stamp = 0
    try:
        stamp = _get_mtime_ns(mra_path)
    except Exception:
        return ''
    if not stamp:
        return ''
    with _mra_setname_lock:
        cached = _mra_setname_cache.get(mra_path)
        if cached and cached[0] == stamp:
            return cached[1]
    setname = ''
    try:
        with open(mra_path, 'rb') as f:
            blob = f.read(_MRA_READ_CAP)
        m = _MRA_SETNAME_RE.search(blob)
        if m:
            setname = m.group(1).decode('utf-8', 'ignore').strip()
    except Exception as e:
        print(f'⚠️ .mra setname read failed: {e}')
    with _mra_setname_lock:
        _mra_setname_cache[mra_path] = (stamp, setname)
    return setname
_PACK_SYSTEM = {'Nintendo NES/Famicom': 'NES', 'Famicom Disk System': 'FDS', 'Satellaview': 'Satellaview', 'Super Nintendo/Super Famicom': 'SNES', 'Nintendo 64': 'N64', 'Nintendo Game Boy': 'GAMEBOY', 'Nintendo Game Boy Color': 'GBC', 'Nintendo Game Boy Advance': 'GBA', 'Nintendo Game Boy Advance 2P': 'GBA', 'Sega Genesis/Mega Drive': 'Genesis', 'Sega Master System': 'SMS', 'Sega Game Gear': 'GameGear', 'Sega Mega-CD': 'MegaCD', 'Sega Saturn': 'Saturn', 'TurboGrafx-16/PC Engine': 'TGFX16', 'TurboGrafx-16/PC Engine CD-Rom': 'TGFX16-CD', 'Sony PlayStation': 'PSX', 'Atari 2600': 'Atari2600', 'Atari 5200': 'ATARI5200', 'Atari 7800': 'ATARI7800', 'Atari Lynx': 'AtariLynx', 'Atari Lynx (2P)': 'AtariLynx', 'Atari Jaguar': 'Jaguar', 'Neo-Geo': 'NEOGEO', 'Neo-Geo CD': 'NeoGeo-CD', 'Nintendo Virtual Boy': 'VirtualBoy', 'Sega SG-1000': 'SG-1000', 'Sega Genesis/Megadrive 32X': 'S32X', 'PC Engine SuperGrafx': 'SuperGrafx', 'Neo-Geo Pocket': 'NeoGeoPocket', 'Neo Geo Pocket': 'NeoGeoPocket', 'Neo-Geo Pocket Color': 'NeoGeoPocket-Color', 'Neo Geo Pocket Color': 'NeoGeoPocket-Color', 'Bandai WonderSwan': 'WonderSwan', 'Bandai WonderSwan Color': 'WonderSwanColor', 'Colecovision': 'Coleco', 'Mattel/INTV Intellivision': 'Intellivision', 'Vectrex': 'VECTREX', 'Videopac G7000/Odyssey 2': 'ODYSSEY2', '3DO Interactive Multiplayer': '3DO', 'Philips CD-i': 'CD-i', 'Amiga CD32': 'AmigaCD32'}
_PACK_MOUNTS = ['/media/fat'] + ['/media/usb%d' % i for i in range(8)]

def _pack_dir(system_folder):
    """Absolute path of the pack folder for a system, '' when not installed."""
    if not system_folder:
        return ''
    for mount in _PACK_MOUNTS:
        candidate = os.path.join(mount, 'docs', system_folder, 'Artwork')
        if os.path.isdir(candidate):
            return candidate
    return ''
_PACK_SIBLINGS = {'GAMEBOY': ('GBC',), 'GBC': ('GAMEBOY',), 'FDS': ('NES',), 'Satellaview': ('SNES',)}
_PACK_BORROWS = {'Nintendo Super Game Boy': ('GAMEBOY', 'GBC')}

def _pack_folders(friendly):
    """Pack folders to try for a system, most specific first."""
    borrowed = _PACK_BORROWS.get(friendly)
    if borrowed:
        return list(borrowed)
    folder = _PACK_SYSTEM.get(friendly, '')
    if not folder:
        return []
    return [folder] + list(_PACK_SIBLINGS.get(folder, ()))

def _pack_lookup_any(folders, keys, crc, size):
    """First (path, resolved_key, folder) any folder yields for any key.
    Folders come from the shared-catalogue rule; several keys appear when the
    reported game name is ambiguous as a path (see _pack_key_from_state).
    """
    if isinstance(keys, str):
        keys = [keys]
    for folder in folders:
        pack_dir = _pack_dir(folder)
        if not pack_dir:
            continue
        for key in keys or ['']:
            found, resolved = _pack_lookup(pack_dir, key, crc, size)
            if found:
                return (found, resolved, folder)
    return ('', '', folders[0] if folders else '')

def _pack_title(name):
    """A dump name without its parenthesised tags, so '<Title> (NTSC)
    (Publisher) (1988)' and '<Title> (USA)' both reduce to '<title>'."""
    return re.sub('\\s+', ' ', re.sub('\\([^)]*\\)', ' ', name)).strip().lower()

def _pack_index(pack_dir):
    """(by_name, by_hash, by_title) for a pack folder. Empty dicts when there is
    no index.tsv: a pack without one still resolves by exact filename."""
    index_path = os.path.join(pack_dir, 'index.tsv')
    try:
        stamp = os.stat(index_path).st_mtime_ns
    except OSError:
        return ({}, {}, {})
    with _pack_index_lock:
        cached = _pack_index_cache.get(pack_dir)
        if cached and cached[0] == stamp:
            return (cached[1], cached[2], cached[3])
    by_name, by_hash, by_title = ({}, {}, {})
    try:
        with io.open(index_path, encoding='utf-8', errors='replace') as f:
            for line in f:
                if not line or line[0] == '#':
                    continue
                parts = line.rstrip('\r\n').split('\t')
                if len(parts) < 4:
                    continue
                name, crc, size, key = (parts[0], parts[1], parts[2], parts[3])
                if not key:
                    continue
                if name:
                    by_name[name.strip().lower()] = key
                    title = _pack_title(name)
                    if title:
                        by_title[title] = key if by_title.get(title, key) == key else ''
                if crc and size:
                    by_hash['%s:%s' % (crc.strip().lower(), size.strip())] = key
    except Exception as e:
        print('⚠️ pack index read failed: %s' % e)
        return ({}, {}, {})
    with _pack_index_lock:
        _pack_index_cache[pack_dir] = (stamp, by_name, by_hash, by_title)
    return (by_name, by_hash, by_title)

def _pack_lookup(pack_dir, key, crc, size):
    """(abs_path, resolved_key) for a game, ('', '') when the pack has no image.
    Steps, cheapest first:

      1. the exact key as a filename — one stat();
      2. the index by variant name — the user holds a dump the pack did not
         pick as representative;
      3. a trailing '(setname)' as a key — rom packs that prefix the identifier
         with a title of their own;
      4. the index by crc+size — a renamed file; free, rom-details already
         computed the CRC;
      5. the index by title alone — collections that tag their dumps
         differently; skipped when the title is not unique.
    """
    if not pack_dir:
        return ('', '')
    if key:
        direct = os.path.join(pack_dir, key + '.jpg')
        if os.path.isfile(direct):
            return (direct, key)
    by_name, by_hash, by_title = _pack_index(pack_dir)
    if key:
        mapped = by_name.get(key.strip().lower())
        if mapped:
            candidate = os.path.join(pack_dir, mapped + '.jpg')
            if os.path.isfile(candidate):
                return (candidate, mapped)
    if key:
        tail = re.search('\\(([^()]+)\\)\\s*$', key)
        if tail:
            setname = tail.group(1).strip()
            candidate = os.path.join(pack_dir, setname + '.jpg')
            if setname and os.path.isfile(candidate):
                return (candidate, setname)
    if crc and size:
        mapped = by_hash.get('%s:%s' % (str(crc).strip().lower(), str(size).strip()))
        if mapped:
            candidate = os.path.join(pack_dir, mapped + '.jpg')
            if os.path.isfile(candidate):
                return (candidate, mapped)
    if key:
        mapped = by_title.get(_pack_title(key))
        if mapped:
            candidate = os.path.join(pack_dir, mapped + '.jpg')
            if os.path.isfile(candidate):
                return (candidate, mapped)
    return ('', '')

def _pack_key_from_state(game_path, is_arcade):
    """Pack key candidates for the loaded game, derived from state ALONE.

    Deliberately independent of rom-details: the display asks for artwork before
    (and sometimes without) triggering a hash, so tying resolution to it left
    /media/artwork serving the PREVIOUS game. Only the CRC fallback needs the
    hash, and that runs later as a refinement.
    """
    if not game_path:
        return []
    if is_arcade:
        if game_path.lower().endswith('.mra'):
            setname = _mra_setname(game_path).strip().lower()
            if setname and re.match('^[a-z0-9][a-z0-9_-]*$', setname):
                return [setname]
        return []
    keys = [os.path.splitext(os.path.basename(game_path))[0]]
    if '/' in game_path:
        head = game_path
        while '/' in head:
            head = head.rsplit('/', 1)[0]
            if os.path.isdir(head) or os.path.isdir('/media/fat/' + head):
                tail = game_path[len(head) + 1:]
                whole = os.path.splitext(tail)[0]
                if whole and whole not in keys:
                    keys.append(whole)
                break
    return keys
