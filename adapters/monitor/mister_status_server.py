#!/usr/bin/env python3
# MiSTer Monitor — MiSTer-side server
# Copyright (C) 2025-2026 chipster6502
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public
# License along with this program.  If not, see
# <https://www.gnu.org/licenses/>.

"""MiSTer Status Server."""

from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import json
import os
import subprocess
import time
import glob
import re
import shutil
import hashlib
import zlib
import zipfile
import io
import socket
from urllib.parse import urlparse
from sam_status import read_sam_status
import sam_control

# =============================================================================
# SERVER_VERSION — this file's release. Exposed in /status/snapshot and
# /status/version. Bump on every release, together with FIRMWARE_VERSION in
# the sketches.
# =============================================================================
SERVER_VERSION = "2.11.1"

# RetroAchievements resolver (optional sibling module): if it is missing the
# server still starts and the route reports the error.
try:
    from ra_status import (get_ra_status, start_ra_polling,
                           get_ra_event, get_ra_achievements)
    _RA_AVAILABLE = True
except Exception as _ra_e:
    _RA_AVAILABLE = False
    print(f"ℹ️ ra_status not loaded ({_ra_e}); /status/retroachievements disabled")
import queue

def _load_names_txt():
    """Reads /media/fat/names.txt and returns {corename: friendly_name}."""
    names = {}
    try:
        with open('/media/fat/names.txt', 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if ':' in line and not line.startswith('#') and not line.startswith('|'):
                    key, _, value = line.partition(':')
                    key = key.strip()
                    value = value.strip()
                    if key and value:
                        names[key] = value
        print(f"✅ names.txt loaded: {len(names)} entries")
    except FileNotFoundError:
        print("ℹ️ names.txt not found - this is normal; using raw core names.")
    except Exception as e:
        print(f"⚠️ Error reading names.txt: {e}")
    return names

NAMES_TXT = _load_names_txt()

# --- System constants (module level: used by _update_state) ----------------

# Entries MUST be lowercase: membership is tested with corename.lower().
KNOWN_NON_ARCADE_SYSTEMS = frozenset({
    'nes', 'nintendo', 'famicom', 'snes', 'super nintendo', 'n64', 'nintendo64',
    'gameboy', 'gbc', 'gba', 'fds', 'sgb',
    'genesis', 'megadrive', 'sega', 'mastersystem', 'sms', 'gamegear', 'gg',
    'saturn', 'dreamcast', 'megacd', 'segacd', 's32x', 'sg1000',
    'psx', 'playstation', 'ps1',
    'atari2600', 'atari5200', 'atari7800', 'atarilynx', 'atari800', 'atarist',
    'colecovision', 'intellivision', 'vectrex', 'odyssey2', 'channelf',
    'astrocade', 'creativision', 'tutor', 'supervision', 'gamate', 'pokemonmini',
    'msx', 'msx1', 'msx2', 'msx2plus', 'x68000', 'pc8801', 'sharp', 'x1', 'pc88', 'mz',
    'turbografx16', 'pcengine', 'tgfx16', 'tgfx16cd', 'supergrafx',
    'wonderswan', 'wonderswancolor', 'ngp', 'ngpc',
    'gx4000', 'amstradcpc', 'amstrad', 'cpc6128', 'zx48', 'zxspectrum', 'zx81', 'zx80',
    'oric', 'bbcmicro', 'acorn', 'electron', 'archimedes', 'enterprise', 'samcoupe',
    'aquarius', 'microbee', 'atom', 'laser500',
    'vic20', 'c64', 'c128', 'c16', 'plus4', 'pet2001', 'ti99', 'trs80', 'coco', 'dragon', 'mc10',
    'trs80coco2', 'coleco', 'adam', 'apple2', 'applei', 'macplus',
    'svi318', 'fmtowns', 'amiga', 'ao486', 'pcxt', 'z386',
    'amigacd32',
    'gb',
    'neogeo',
    'x68k',
    'apogee', 'archie', 'ay-3-8500', 'acornelectron', 'altair8800',
    'amstrad pcw', 'bk0011m', 'casio_pv-2000', 'coco3', 'coco2',
    'edsac', 'epochgalaxyii', 'galaksija', 'interact', 'laser', 'lynx48', 'lynx48/96k',
    'multicomp', 'orao', 'ondra_spo186', 'pmd85', 'rx78', 'sord m5',
    'ti-99_4a', 'trs-80', 'tsconf', 'tatungeinstein',
    'tomyscramble', 'uk101', 'vector06', 'homelab', 'bbcbridgecompanion',
    'pocketchallengev2', 'myvision', 'supervision8000', 'vt52',
    'sg-1000', 'tomytutor',
    'scv', 'pdp1',
    'spectrum', 'zxnext',
    'apple-ii', 'apple-iigs', 'apple-i', 'sam',
})

CORE_NAME_MAPPING = {
    'NES': 'Nintendo NES/Famicom',
    'SNES': 'Super Nintendo/Super Famicom',
    'N64': 'Nintendo 64',
    'FDS': 'Famicom Disk System',
    'Satellaview': 'Satellaview',
    'GAMEBOY': 'Nintendo Game Boy',
    'GB': 'Nintendo Game Boy',
    'GBC': 'Nintendo Game Boy Color',
    'GBA': 'Nintendo Game Boy Advance',
    'GBA2P': 'Nintendo Game Boy Advance 2P',
    'SGB': 'Nintendo Super Game Boy',
    'GameNWatch': 'Nintendo Game & Watch',
    'GAMEBOY2P': 'Nintendo Game Boy Color',
    'VirtualBoy': 'Nintendo Virtual Boy',
    'Genesis': 'Sega Genesis/Mega Drive',
    'MegaDrive': 'Sega Genesis/Mega Drive',
    'PapriumMD': 'Paprium (Mega Drive)',
    'MegaVGMDrive': 'Genesis / Mega Drive VGM Player',
    'SMS': 'Sega Master System',
    'GG': 'Sega Game Gear',
    'Saturn': 'Sega Saturn',
    'S32X': 'Sega Genesis/Megadrive 32X',
    'MegaCD': 'Sega Mega-CD',
    'SegaCD': 'Sega CD/Mega CD',
    'SG1000': 'Sega SG-1000',
    'GameGear': 'Sega Game Gear',
    'PSX': 'Sony PlayStation',
    'PlayStation': 'Sony PlayStation',
    'TurboGrafx16': 'TurboGrafx-16/PC Engine',
    'PCEngine': 'TurboGrafx-16/PC Engine',
    'TGFX16': 'TurboGrafx-16/PC Engine',
    'TGFX16-CD': 'TurboGrafx-16/PC Engine CD-Rom',
    'SuperGrafx': 'PC Engine SuperGrafx',
    'Atari2600': 'Atari 2600',
    'ATARI5200': 'Atari 5200',
    'ATARI7800': 'Atari 7800',
    'AtariLynx': 'Atari Lynx',
    'AtariLynx2P': 'Atari Lynx (2P)',
    'ATARI800': 'Atari 8bit',
    'AtariST': 'Atari ST/STE',
    'MAME': 'Arcade',
    'mame': 'Arcade',
    'Arcade': 'Arcade',
    'PET2001': 'Commodore PET',
    'C64': 'Commodore 64',
    'C128': 'Commodore 128',
    'VIC20': 'Commodore Vic-20',
    'Minimig': 'Commodore Amiga',
    'Amiga': 'Commodore Amiga',
    'Amiga500': 'Commodore Amiga',
    'Amiga500HD': 'Commodore Amiga',
    'Amiga600HD': 'Commodore Amiga',
    'CD32': 'Amiga CD32',
    'AmigaCD32': 'Amiga CD32',
    'AO486': 'PC Dos',
    'PCXT': 'PC Dos',
    'PCXT-EGA': 'PC Dos',
    'PCjr': 'PC Dos',
    # z386: unofficial 80386 core by nand2mario.
    'Z386': 'PC Dos',
    'Jupiter': 'Jupiter Ace',
    'PC8801': 'NEC PC-8801',
    'BK0011M': 'Elektronika BK0011M',
    'eg2000': 'EG2000 Colour Genie',
    'lynx48': 'Camputers Lynx',
    'Lynx48': 'Camputers Lynx',
    'AQUARIUS': 'Mattel Aquarius',
    'sharpmz': 'SHARP MZ Series',
    'QL': 'Sinclair QL',
    'SPMX': 'Specialist MX',
    'SVI328': 'Spectravideo SVI-328',
    'AliceMC10': 'Alice 4K / Tandy MC-10',
    'MSX': 'MSX Computer',
    'MSX1': 'MSX1 Computer',
    'MSX2': 'MSX2 Computer',
    'MSX2Plus': 'MSX2+ Computer',
    'Spectrum': 'ZX Spectrum',
    'zx48': 'ZX Spectrum',
    'ZX81': 'ZX81 Computer',
    'ZXNext': 'ZX Spectrum Next',
    'Amstrad': 'Amstrad CPC',
    'AmstradCPC': 'Amstrad CPC',
    'GX4000': 'Amstrad GX4000',
    'Apple-II': 'Apple II',
    'APPLE-I': 'Apple I',
    'MACPLUS': 'Apple Macintosh Plus',
    'Apple-IIgs': 'Apple IIgs',
    'Apple-Lisa': 'Apple Lisa',
    'MACLC': 'Apple Macintosh LC',
    'X68000': 'Sharp X68000',
    'Coleco': 'Colecovision',
    'Intellivision': 'Mattel/INTV Intellivision',
    'VECTREX': 'Vectrex',
    'ODYSSEY2': 'Videopac G7000/Odyssey 2',
    'ChannelF': 'Channel F',
    'CreatiVision': 'VTech CreatiVision',
    'SuperVision': 'Watara Supervision',
    'WonderSwan': 'Bandai WonderSwan',
    'WonderSwanColor': 'Bandai WonderSwan Color',
    'NGP': 'Neo Geo Pocket',
    'NGPC': 'Neo Geo Pocket Color',
    'PokemonMini': 'Pokemon Mini',
    'Gamate': 'Bit Corporation Gamate',
    'AVision': 'Adventure Vision',
    'Arcadia': 'Arcadia 2001',
    'CD-i': 'Philips CD-i',
    'MegaDuck': 'Mega Duck',
    'NEOGEO': 'Neo-Geo',
    'NeoGeo-CD': 'Neo-Geo CD',
    'NeoGeoPocket': 'Neo-Geo Pocket',
    'NeoGeoPocket-Color': 'Neo-Geo Pocket Color',
    'cdi':          'Philips CD-i',
    'colecovision': 'Colecovision',
    'jaguar':       'Atari Jaguar',
    'neogeocd':     'Neo-Geo CD',
    'tgfx16cd':     'TurboGrafx-16/PC Engine CD-Rom',
    'x68k':         'Sharp X68000',
    'Neo Geo MVS/AES': 'Neo-Geo',
    'Casio_PV-1000': 'Casio PV-1000',
    'VC4000': 'Interton VC 4000',
    'PocketChallenge': 'Pocket Challenge V2',
    'BBCMicro': 'BBC Micro',
    'AcornElectron': 'Acorn Electron',
    'ARCHIE': 'Acorn Archimedes',
    'AcornAtom': 'Acorn Atom',
    'TI-99_4A': 'TI-99/4A',
    'TRS-80': 'TRS-80 Color Computer',
    'COCO3': 'TRS-80 Color Computer 3',
    'CoCo2': 'TRS-80 Color Computer 2',
    'SAM': 'SAM Coupé',
    'SAMCOUPE': 'MGT SAM Coupé',
    'Oric': 'Oric 1 / Atmos',
    'nes': 'Nintendo NES/Famicom',
    'snes': 'Super Nintendo/Super Famicom',
    'genesis': 'Sega Genesis/Mega Drive',
    'megadrive': 'Sega Genesis/Mega Drive',
    'gameboy': 'Nintendo Game Boy',
    'gameboycolor': 'Nintendo Game Boy Color',
    'gameboyadvance': 'Nintendo Game Boy Advance',
    'nintendo64': 'Nintendo 64',
    'supernintendo': 'Super Nintendo',
    'playstation': 'Sony PlayStation',
    'commodore64': 'Commodore 64',
    'pcengine': 'TurboGrafx-16/PC Engine',
    'turbografx16': 'TurboGrafx-16/PC Engine',
    'mastersystem': 'Sega Master System',
    'atari2600': 'Atari 2600',
    'Adam': 'Coleco Adam',
    'Altair8800': 'Altair 8800',
    'APOGEE': 'Apogee BK-01 / Radio-86RK',
    'Arduboy': 'Arduboy',
    'Astrocade': 'Bally Astrocade',
    'BBCBridgeCompanion': 'BBC Bridge Companion',
    'C16': 'Commodore 16 - Plus/4',
    'Casio_PV-2000': 'Casio PV-2000',
    'Chess': 'Chess',
    'Chip8': 'SuperChip / Chip-8',
    'Donut': 'Donut',
    'Enterprise': 'Elan Enterprise',
    'FLAPPY': 'Flappy Bird',
    'Game and Watch': 'Nintendo Game & Watch',
    'GBMidi': 'Midi to Game Boy sound module',
    'GenMidi': 'Midi to Genesis sound module',
    'Interact': 'Interact Home Computer',
    'IQ151': 'IQ 151',
    'Laser': 'Vtech Laser 310',
    'MultiComp': 'MultiComp from Grant Searle',
    'MyVision': 'Nichibutsu My Vision',
    'Ondra SPO 186': 'Ondra SPO 186',
    'ORAO': 'Orao / Eagle',
    'PDP1': 'DEC PDP-1',
    'PMD85': 'Tesla PMD 85',
    'RX78': 'Bandai RX-78',
    'SlugCross': 'Slug Cross from bhayame',
    'SuperVision8000': 'Bandai Super Vision 8000',
    'TatungEinstein': 'Tatung Einstein TC01 & 256',
    'TK2000': 'TK 2000 Color Computer',
    'TomyTutor': 'Tomy Tutor / Pyuta / Pyuta Jr.',
    'TSConf': 'TSConf',
    'UK101': 'Compukit UK101',
    'VECTOR06': 'Vector-06C',
    'VT52': 'DEC VT52',
    '3DO': '3DO Interactive Multiplayer',
    'CBM-II': 'Commodore CBM-II',
    'FM-7': 'Fujitsu FM-7',
    'Gamecom': 'Tiger Game.com',
    'GameKing': 'TimeTop GameKing',
    'JR100': 'National JR-100',
    'Loopy': 'Casio Loopy',
    'NeXT': 'NeXT Computer',
    'PocketStation': 'Sony PocketStation',
    'SGIIndy': 'SGI Indy',
    'Studio-II': 'RCA Studio II',
    'SuperAcan': 'Funtech Super Acan',

    # Reported by the runtime unknown-core log. The CORENAME here is the
    # literal string the core wrote, which the .rbf name does not always give.
    'ABC80': 'Luxor ABC 80',
    'Amstrad PCW': 'Amstrad PCW',
    'Tamagotchi': 'Tamagotchi',
}

# names.txt only names cores the curated table does not know. Lookups are
# case-insensitive and the curated names are the key of the firmware's
# ScreenScraper table, so a user label must never replace one.
_curated_lower = {k.lower() for k in CORE_NAME_MAPPING}
for k, v in NAMES_TXT.items():
    if k.lower() not in _curated_lower:
        CORE_NAME_MAPPING[k] = v

# Set of all known system friendly names — used to detect CURRENTPATH = core name
KNOWN_SYSTEM_NAMES = set(v.lower() for v in CORE_NAME_MAPPING.values()) | \
                     set(v.lower() for v in NAMES_TXT.values())

# Case-insensitive lookup dict — keys are lowercased
CORE_NAME_MAPPING_LOWER = {k.lower(): v for k, v in CORE_NAME_MAPPING.items()}


# ---------------------------------------------------------------------------
# Unknown cores
# ---------------------------------------------------------------------------
# Records the CORENAMEs this server cannot name, so the exact key a mapping
# needs is known without guessing. Local only: the file never leaves the MiSTer.
# threading is re-imported here because the real import lands further down,
# after this block runs (sys.modules makes the repeat free).
import threading

_UNKNOWN_CORES_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), 'unknown_cores.json')

_unknown_cores = {}                  # raw corename -> {first_seen, last_seen, count}
_unknown_cores_lock = threading.Lock()
_unknown_cores_loaded = False


def _core_resolves(name):
    """
    True when `name` already yields a friendly name through the same chain the
    evaluator uses, so the diagnostic log cannot disagree with the screen: the
    fallback on the MGL/setname prefix is part of that chain.

    RA_ is not stripped here: the caller passes the already-stripped
    lookup_name, matching the evaluator.
    """
    if not name:
        return True
    if name in CORE_NAME_MAPPING or name.lower() in CORE_NAME_MAPPING_LOWER:
        return True
    if '-' in name:
        prefix = name.split('-', 1)[0]
        if prefix in CORE_NAME_MAPPING or prefix.lower() in CORE_NAME_MAPPING_LOWER:
            return True
    return False


def _load_unknown_cores():
    """Restore the log so counts survive a restart. Corruption is not fatal."""
    global _unknown_cores, _unknown_cores_loaded
    if _unknown_cores_loaded:
        return
    _unknown_cores_loaded = True
    try:
        with open(_UNKNOWN_CORES_FILE, 'r') as f:
            data = json.load(f)
        if isinstance(data.get('cores'), dict):
            _unknown_cores = data['cores']
            print(f"📋 Unknown-core log restored: {len(_unknown_cores)} entries")
            # Drop entries a later update has since mapped: "seen once,
            # unnamed" has no value once the core has a name.
            resolved = [k for k in _unknown_cores if _core_resolves(k)]
            if resolved:
                for k in resolved:
                    del _unknown_cores[k]
                print(f"🧹 Unknown-core log: dropped {len(resolved)} entries now "
                      f"covered by CORE_NAME_MAPPING ({', '.join(resolved[:5])}"
                      f"{'...' if len(resolved) > 5 else ''})")
                _save_unknown_cores_locked()
    except FileNotFoundError:
        pass
    except Exception as e:
        # A truncated file must never stop the server from serving status.
        print(f"⚠️ unknown_cores.json unreadable ({e}) - starting a fresh log")


def _save_unknown_cores_locked():
    """
    Atomic write (temp file + os.replace): the MiSTer loses power by having
    its plug pulled, and a half-written JSON would make
    _load_unknown_cores() discard the whole history.
    """
    tmp = _UNKNOWN_CORES_FILE + '.tmp'
    try:
        with open(tmp, 'w') as f:
            json.dump({'comment': 'Cores this MiSTer ran that MiSTer Monitor '
                                  'could not name. Local only; nothing is sent '
                                  'anywhere. Safe to delete.',
                       'updated': int(time.time()),
                       'cores': _unknown_cores}, f, indent=1)
        os.replace(tmp, _UNKNOWN_CORES_FILE)
    except Exception as e:
        print(f"⚠️ Cannot persist unknown_cores.json: {e}")
        try:
            os.unlink(tmp)
        except Exception:
            pass


def _note_unknown_core(raw_corename):
    """
    Record a core name absent from CORE_NAME_MAPPING. Membership is the
    test, NOT 'friendly == raw': several cores map to themselves
    ('MSX' -> 'MSX') and would be filed as unknown forever.

    Disk is touched only on a new name or once a minute, so a core left
    running cannot turn this into a write loop on the SD card.
    """
    name = (raw_corename or '').strip()
    if not name or name.upper() == 'MENU':
        return
    if _core_resolves(name):
        return

    now = int(time.time())
    with _unknown_cores_lock:
        _load_unknown_cores()
        entry = _unknown_cores.get(name)
        if entry is None:
            _unknown_cores[name] = {'first_seen': now, 'last_seen': now,
                                    'count': 1}
            print(f"❓ Unknown core recorded: '{name}' "
                  f"(no CORE_NAME_MAPPING entry) -> /status/unknown_cores")
            _save_unknown_cores_locked()
            return
        entry['count'] = entry.get('count', 0) + 1
        stale = now - entry.get('last_seen', 0) >= 60
        entry['last_seen'] = now
        if stale:
            _save_unknown_cores_locked()


def get_unknown_cores():
    """Payload for /status/unknown_cores."""
    with _unknown_cores_lock:
        _load_unknown_cores()
        cores = [
            {'corename': k,
             'first_seen': v.get('first_seen'),
             'last_seen': v.get('last_seen'),
             'count': v.get('count', 0)}
            for k, v in _unknown_cores.items()
        ]
    cores.sort(key=lambda c: (-(c['count'] or 0), c['corename'].lower()))
    return {
        'count': len(cores),
        'cores': cores,
        'note': ('Cores this MiSTer ran that could not be mapped to a friendly '
                 'name. These strings are the literal CORENAME and are exactly '
                 'what a mapping must be keyed on. Local only.'),
        'timestamp': int(time.time()),
    }

import threading

# --- Centralized state (all access must hold _state_lock) ------------------
_state_lock = threading.Lock()

# Serializes rom-details computation: a second caller blocks here and picks up
# the cache the first one wrote, instead of starting a duplicate hash/CRC.
_rom_details_compute_lock = threading.Lock()

_state = {
    'core':              'Menu',   # friendly name — used for display, image lookup, and ScreenScraper mapping
    'core_raw':          '',       # raw CORENAME at commit time ('AO486', 'neogeo'); '' when unknown
    'system_name':       'Menu',   # alias of 'core' (same value); kept for backward compatibility
    'game_system':       '',       # the GAME's real system when a backwards-compatible core opened it
    'artwork_path':      '',       # absolute path of the pack image for the loaded game, '' when none
    'artwork_seq':       -1,       # the seq that artwork_path was resolved for; a mismatch means stale
    'game':              '',       # game name (filename without extension)
    'game_path':         '',       # absolute path to ROM file
    'is_arcade':         False,    # True if current core is arcade
    'rom_details':       None,     # last ScreenScraper result (dict or None)
    'rom_details_stale': True,     # True = needs refresh on next request
    'seq':               0,        # monotonic generation counter — bumps on every REAL identity change
    'updated_at':        0.0,      # epoch of last committed change
    'last_event':        'boot',   # 'boot' | 'load' | 'core' | 'menu' | 'sam'
}

# Raw CORENAME at the last evaluation: a core change must always bypass the
# navigation gate.
_last_evaluated_corename = None

# Error tracking — exposed via /status/error_state and /status/all
server_error_state        = ''    # last error message, empty string if none
last_valid_core           = ''    # last corename that produced a valid state
last_valid_core_timestamp = 0.0   # epoch time of last valid state update

def _atari_78_or_26(game_path):
    """Real system of a game loaded through the Atari7800 core (plays both).
    .a26 -> 2600; .a78 -> 7800; else sniff the A78 header signature ('ATARI7800'
    at offset 1) when the file is readable. Headerless dumps and ZIP-internal
    paths fall back to 2600."""
    p = game_path.lower()
    if p.endswith('.a26'):
        return 'Atari 2600'
    if p.endswith('.a78'):
        return 'Atari 7800'
    try:
        if os.path.isfile(game_path):
            with open(game_path, 'rb') as f:
                head = f.read(16)
            if len(head) >= 10 and head[1:10] == b'ATARI7800':
                return 'Atari 7800'
    except OSError:
        pass
    return 'Atari 2600'


def _md_or_sms(game_path):
    """Real system of a game loaded through the MegaDrive core (plays both).
    No header sniffing needed: the core exposes two separate file slots, so a
    .sms can only have come through the Master System one.

    Returns the same string the stock SMS core resolves to, so artwork, the
    image cache folder and the RA console lookup behave identically whichever
    core opened the game."""
    if game_path.lower().endswith('.sms'):
        return 'Sega Master System'
    return 'Sega Genesis/Mega Drive'


# Disc formats of the NeoGeo CD side ('.pbp' excluded: it is a PSX container).
_NEOGEO_CD_EXTS = ('.cue', '.chd', '.iso')
_FDS_EXTS = ('.fds', '.qd')
_SATELLAVIEW_EXTS = ('.bs',)


def _nes_or_fds(game_path):
    """Real system of a game loaded through the NES core, which serves both.

    The core reports itself as NES whatever it loads; the extension decides
    (.fds/.qd = disk, anything else = cartridge). The answer travels in
    game_system, not in the core name: the panel keeps reading 'NES'.
    """
    if game_path.lower().endswith(_FDS_EXTS):
        return 'Famicom Disk System'
    return 'Nintendo NES/Famicom'


def _snes_or_satellaview(game_path):
    """Real system of a game loaded through the SNES core, which serves both.

    The extension decides: a Satellaview dump is always .bs. Same shape as
    _nes_or_fds() — the answer travels in game_system and the panel keeps
    reading 'SNES'.
    """
    if game_path.lower().endswith(_SATELLAVIEW_EXTS):
        return 'Satellaview'
    return 'Super Nintendo/Super Famicom'


def _neogeo_cart_or_cd(game_path):
    """Real console of a game loaded through the stock NEOGEO core (serves both).

    Neo Geo CD is a separate console and the two sides never share a container
    (cartridges: .neo, romset ZIP or romset folder; CD: a disc image), so the
    extension alone decides.

    Unlike _md_or_sms(), the answer belongs in the CORE name: SAM already
    reports 'Neo-Geo CD' for the same disc, and the firmware does not read
    game_system at all. Returning CORE_NAME_MAPPING['neogeocd'] makes both
    paths converge on one ScreenScraper system, image and cache folder.
    """
    if game_path.lower().endswith(_NEOGEO_CD_EXTS):
        return 'Neo-Geo CD'
    return 'Neo-Geo'


def _commit_state(core, game, game_path, is_arcade, event, core_raw='', game_system=''):
    """
    Atomically commits a derived state. Bumps 'seq' and invalidates the
    rom-details cache ONLY when the identity actually changed.
    Returns True if the state changed.
    """
    with _state_lock:
        changed = (_state['core']      != core or
                   _state['game']      != game or
                   _state['game_path'] != game_path or
                   _state['is_arcade'] != is_arcade)
        # Refreshed even when the identity did not change, and kept OUT of
        # 'changed': a raw-only flip must not bump seq nor wipe rom_details.
        _state['core_raw'] = core_raw
        # Derived from the same game_path as this identity, so rewriting it
        # unconditionally is free and can never disagree.
        _state['game_system'] = game_system
        if changed:
            _state['core']              = core
            _state['system_name']       = core
            _state['game']              = game
            _state['game_path']         = game_path
            _state['is_arcade']         = is_arcade
            _state['rom_details']       = None
            _state['rom_details_stale'] = True
            _state['seq']              += 1
            _state['updated_at']        = time.time()
            _state['last_event']        = event
        seq_now = _state['seq']
    if changed:
        # Resolve the pack image now: the display fetches artwork before
        # rom-details, so a later resolution would serve the previous game's.
        _pack_resolve_for_state(game_path, is_arcade, game_system, core, seq_now)
        print(f"✅ State committed (seq={seq_now}, {event}): core='{core}' game='{game}' arcade={is_arcade}")
    else:
        print(f"♻️ Evaluation confirmed current state (seq={seq_now}) — rom cache preserved")
    return changed

# --- Background watcher thread: monitors /tmp/ files via inotifywait -------
_WATCHED_FILES = [
    '/tmp/CORENAME',
    '/tmp/ACTIVEGAME',
    '/tmp/CURRENTPATH',
    '/tmp/FILESELECT',
    '/tmp/FULLPATH',
    '/tmp/STARTPATH',   # arcade ROM path — needed to detect arcade game changes
    '/tmp/SAM_Games.log',  # SAM's own log: the only signal on same-core hops
]

def _ensure_watched_files():
    """
    inotifywait aborts if ANY watched path is missing, which traps the watcher
    in a restart loop on setups without MiSTer Remote. Create the missing ones
    as empty files; MiSTer overwrites them as soon as it writes.
    """
    for path in _WATCHED_FILES:
        try:
            if not os.path.exists(path):
                open(path, 'a').close()
                print(f"📄 Created missing watch target: {path}")
        except Exception as e:
            print(f"⚠️ Could not create {path}: {e}")

def _is_known_non_arcade(corename):
    """Returns True if corename belongs to a known non-arcade system."""
    return corename.lower() in KNOWN_NON_ARCADE_SYSTEMS


def _read_file(path):
    """Reads a /tmp/ file and returns its content stripped, or '' on error."""
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read().strip()
    except:
        return ''


# ─────────────────────────────────────────────────────────────────────────────
# ROM-load contention guard
#
# Hashing reads from the same SD the core is loading from, so wait until that
# process stops reading. Watched through 'rchar' in /proc/<pid>/io, which also
# covers network-backed storage.
# Best-effort and fails OPEN: never blocks detection, never holds a lock and
# never raises.
# ─────────────────────────────────────────────────────────────────────────────
_LOAD_POLL_INTERVAL  = 0.25         # seconds between rchar samples
_LOAD_ACTIVITY_BYTES = 512 * 1024   # per-poll growth above this = "still loading"
_LOAD_QUIET_WINDOW   = 1.5          # seconds with no activity = load finished
_LOAD_INITIAL_GRACE  = 0.8          # if no activity seen by now, assume idle
_LOAD_MAX_WAIT       = 25.0         # hard cap (streaming cores never go quiet)


def _find_mister_pid():
    """Return the PID of the running MiSTer binary, or None. Fails soft."""
    try:
        out = subprocess.check_output(['pidof', 'MiSTer'],
                                      stderr=subprocess.DEVNULL, timeout=2)
        parts = out.decode(errors='ignore').strip().split()
        if parts:
            return int(parts[0])
    except Exception:
        pass
    # Fallback for environments without a working pidof: scan /proc/*/comm
    try:
        for entry in os.listdir('/proc'):
            if not entry.isdigit():
                continue
            try:
                with open(f'/proc/{entry}/comm', 'r') as f:
                    if f.read().strip() == 'MiSTer':
                        return int(entry)
            except Exception:
                continue
    except Exception:
        pass
    return None


def _read_mister_rchar(pid):
    """Return cumulative 'rchar' bytes from /proc/<pid>/io, or None."""
    try:
        with open(f'/proc/{pid}/io', 'r') as f:
            for line in f:
                if line.startswith('rchar:'):
                    return int(line.split(':', 1)[1].strip())
    except Exception:
        pass
    return None


def _wait_for_rom_load_to_settle():
    """
    Block until the core has finished copying the ROM to SDRAM, so hashing does
    not compete with the load. Returns promptly when the system is idle, when
    the signal is unavailable, or after _LOAD_MAX_WAIT.
    """
    pid = _find_mister_pid()
    if pid is None:
        return  # can't observe -> proceed (same behaviour as before)

    prev = _read_mister_rchar(pid)
    if prev is None:
        return

    start         = time.monotonic()
    last_activity = start
    saw_activity  = False

    while True:
        time.sleep(_LOAD_POLL_INTERVAL)
        now = time.monotonic()

        cur = _read_mister_rchar(pid)
        if cur is None:
            return  # process gone / unreadable -> proceed

        if (cur - prev) > _LOAD_ACTIVITY_BYTES:
            saw_activity  = True
            last_activity = now
        prev = cur

        # Was loading, now quiet for the full window -> load finished.
        if saw_activity and (now - last_activity) >= _LOAD_QUIET_WINDOW:
            print(f"⏳ ROM load settled after {now - start:.1f}s — hashing now")
            return

        # Nothing was loading when we arrived -> don't wait the full window.
        if not saw_activity and (now - start) >= _LOAD_INITIAL_GRACE:
            return

        # Safety cap (e.g. streaming cores that never go quiet).
        if (now - start) >= _LOAD_MAX_WAIT:
            print(f"⏳ ROM load wait hit {_LOAD_MAX_WAIT:.0f}s cap — hashing anyway")
            return


def _get_mtime_ns(path):
    """Returns mtime in nanoseconds, or 0 on error."""
    try:
        return os.stat(path).st_mtime_ns
    except:
        return 0

def _sam_looks_like_path(s):
    """
    True when a SAM_Games.log third field is a real path and not a bare game
    name. SAM logs some content by name only (Amiga WHDLoad/MGL demos), which
    poisons game_path with a value nothing can open. A genuine SAM path is
    always absolute, so requiring a leading '/' is enough.
    """
    return bool(s) and s.startswith('/')


def _sam_get_current():
    """
    Reads SAM_Games.log and returns (is_active, core, game, path).
    Format: "HH:MM:SS - corename - /full/path/to/game".
    False tuple if the log is missing, too old, or has no valid entry.
    """
    sam_log_path = '/tmp/SAM_Games.log'

    if not os.path.exists(sam_log_path):
        return False, '', '', '', ''

    age = time.time() - os.path.getmtime(sam_log_path)
    if age > 300:  # 5 minutes
        print(f"🔍 SAM_Games.log too old: {age:.1f}s")
        return False, '', '', '', ''

    try:
        with open(sam_log_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return False, '', '', '', ''

    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        parts = line.split(' - ')
        if len(parts) >= 3:
            sam_core_raw = parts[1].strip()
            sam_field    = ' - '.join(parts[2:])
            # SAM sometimes logs by name only. Keep the name for display, but
            # never propagate a non-path as game_path: it is not openable.
            game_filename = sam_field.split('/')[-1]
            sam_game      = os.path.splitext(game_filename)[0]
            sam_path      = sam_field if _sam_looks_like_path(sam_field) else ''
            # Some SAM log entries contain only a title. Recover its literal ROM
            # path only from a live owner reporting that same core and game.
            selected = sam_control.owner()
            if (not sam_path and selected and selected.get('core') == sam_core_raw
                    and selected.get('game') == sam_game):
                sam_path = selected.get('rom_path', '')
            sam_core      = (CORE_NAME_MAPPING.get(sam_core_raw) or
                             CORE_NAME_MAPPING_LOWER.get(sam_core_raw.lower()) or
                             sam_core_raw)
            sam_core      = CORE_NAME_MAPPING.get(sam_core, sam_core)
            print(f"✅ SAM detected — core='{sam_core}' game='{sam_game}'")
            return True, sam_core_raw, sam_core, sam_game, sam_path

    return False, '', '', '', ''


def _sam_is_current():
    """
    True if SAM_Games.log is active AND the most recent detection source
    (CORENAME/ACTIVEGAME are not significantly newer than the log).
    """
    sam_log_path = '/tmp/SAM_Games.log'
    if not os.path.exists(sam_log_path):
        return False

    sam_ts = os.path.getmtime(sam_log_path)
    # Max expected lag between SAM's log write and CORENAME/ACTIVEGAME landing
    # (2-5 s observed). A longer window misattributes a later manual load to SAM.
    grace  = 10  # seconds

    for fname in ['CORENAME', 'ACTIVEGAME']:
        try:
            fts = os.path.getmtime(f'/tmp/{fname}')
            if fts > sam_ts + grace:
                print(f"🔄 {fname} newer than SAM by {fts - sam_ts:.1f}s — SAM not current")
                return False
        except:
            pass

    return True

_KNOWN_ROM_EXTS = {
    '.zip', '.mra', '.mgl', '.rom', '.bin', '.iso', '.chd',
    # Nintendo
    '.nes', '.fds', '.nsf', '.sfc', '.smc', '.bs', '.spc',
    '.gba', '.gb', '.gbc', '.n64', '.z64', '.min',
    # Sega
    '.smd', '.md', '.gen', '.32x', '.sg', '.sms', '.gg',
    # Sony
    '.psx', '.exe',
    # NEC / Hudson
    '.pce', '.sgx',
    # SNK
    '.neo', '.ngp', '.ngc',
    # Atari
    '.a78', '.a52', '.a26', '.lnx', '.jag', '.j64',
    '.atr', '.xex', '.cas', '.car', '.atx', '.xfd',
    '.st', '.msa', '.stx', '.dim',
    # Other consoles / handhelds
    '.ws', '.wsc', '.pc2', '.col', '.cv', '.vec', '.ovr', '.int',
    '.sv', '.ch8', '.hex', '.gmc',
    # Commodore
    '.prg', '.d64', '.d81', '.t64', '.tap', '.crt', '.g64', '.reu',
    # Spectrum / SAM / Next
    '.tzx', '.z80', '.sna', '.trd', '.scl', '.csw', '.mgt',
    # Amstrad CPC
    '.cdt', '.cpc', '.voc',
    # Amiga / PC
    '.vhd', '.hdf', '.adf', '.adz', '.img', '.ima', '.vfd',
    # Apple
    '.do', '.po', '.2mg', '.nib', '.hdv',
    # MSX
    '.mx1', '.mx2', '.dsk', '.cue',
    # Japanese computers
    '.d88', '.ram',
    # British / misc micros
    '.ssd', '.dsd', '.ace', '.mdv', '.win', '.bas', '.lod',
    '.vz', '.caq', '.c10', '.ccc', '.cmd', '.jvi', '.m99',
    # Eastern-bloc / other computers
    '.c00', '.com', '.edd', '.fdd', '.rka', '.rkr', '.rks',
    '.rmm', '.odi', '.gam', '.cin', '.k7', '.p',
    # PDP-1
    '.pdp', '.rim',
}

# Containers whose CRC ScreenScraper never indexes (per-pack VHDs, whose CRC is
# unstable anyway because the guest OS rewrites them). Extensible.
_NO_HASH_EXTS = {'.vhd'}

# Extensions worth hashing on most cores but not on specific ones. Keyed by the
# RAW CORENAME, since names.txt lets a user rename the friendly one.
#
# .chd on ao486: pack-built CHDs are in no database, and hashing ~700 MB costs
# ~35 s of ARM — longer than the firmware's HTTP timeout. NOT global: on console
# CD cores the CHD's MD5 is exactly what resolves the RetroAchievements set.
_NO_HASH_EXTS_BY_CORE = {
    'AO486': {'.chd'},
}


def _read_corename_raw():
    """Raw CORENAME ('AO486'), RA_-prefix stripped. '' when unreadable."""
    try:
        with open('/tmp/CORENAME', 'r') as f:
            corename = f.read().strip()
    except Exception:
        return ''
    # RA_-prefixed cores: the RetroAchievements toolkit ships RA_SNES etc.
    return corename[3:] if corename.startswith('RA_') else corename


def _is_no_hash(ext, corename):
    """
    True when hashing this file can never yield a usable CRC/MD5.

    Single source of truth for the hashing decision and for the no_hash flag:
    if the two disagree, the firmware burns its whole retry budget waiting for
    a CRC that is never coming.
    """
    ext = (ext or '').lower()
    if ext in _NO_HASH_EXTS:
        return True
    return ext in _NO_HASH_EXTS_BY_CORE.get(corename or '', frozenset())


# ---------------------------------------------------------------------------
# NeoGeo -> ScreenScraper romnom
# ---------------------------------------------------------------------------
# ScreenScraper indexes NeoGeo as MAME romsets ('<romset>.zip') while MiSTer runs
# .neo containers whose CRC is in no database, so the CRC route can never match.
# SS's fuzzy fallback on romnom only works when the pack names the file the way
# SS does, and 48 of the 281 romsets carry a subtitle it does not expect.
# The romset id is always present and always right, so it is sent as romnom:
# an exact match, with no CRC and no fuzzy search.
_NEOGEO_CORENAMES = frozenset({'neogeo'})


# Rom packs that keep a readable filename and park the romset id in trailing
# parentheses: '<Title> (<romset>).neo'. Scanned lazily, and only after the
# direct probes miss.
_NEOGEO_ROM_EXTS = ('.neo', '.zip')


def _neogeo_file_with_embedded_id(directory, romset_id):
    """Path of a file whose stem ends with '(<romset_id>)', or None."""
    if not romset_id:
        return None
    needle = '(' + romset_id.strip().lower() + ')'
    hits = []
    try:
        for entry in os.listdir(directory):
            stem, ext = os.path.splitext(entry)
            if ext.lower() not in _NEOGEO_ROM_EXTS:
                continue
            if stem.strip().lower().endswith(needle):
                hits.append(os.path.join(directory, entry))
    except Exception as e:
        print(f"\u26a0\ufe0f NeoGeo directory scan failed: {e}")
        return None
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        print(f"\u26a0\ufe0f {len(hits)} files embed romset id "
              f"'{romset_id}' \u2014 refusing to guess")
    return None



# Both files are read because a user may own either collection: each rom
# distribution ships its own romset list under a different name.
_ROMSET_XML_NAMES = ('romsets.xml', 'gog-romsets.xml')

_romset_cache = {}                    # directory -> (mtime_stamp, frozenset)
_romset_cache_lock = threading.Lock()


# --- .mra <setname> corroboration --------------------------------------------
# Main_MiSTer writes the romset's <setname> to /tmp/CORENAME on an arcade .mra
# load, so a .mra at STARTPATH whose setname equals CORENAME IS the current
# launch: positive identity, with no freshness window of its own.
# Cached by (path, mtime): evaluate() runs on every inotify burst.
_MRA_SETNAME_RE = re.compile(
    rb'<\s*setname\s*>\s*([^<]+?)\s*<\s*/\s*setname\s*>', re.IGNORECASE)
_MRA_READ_CAP = 262144                # generous: real .mra files are 2-50 KB

_mra_setname_cache = {}               # path -> (mtime_ns, setname)
_mra_setname_lock = threading.Lock()


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
        print(f"\u26a0\ufe0f .mra setname read failed: {e}")

    with _mra_setname_lock:
        _mra_setname_cache[mra_path] = (stamp, setname)
    return setname


def _mra_confirms_corename(startpath, corename):
    """True when the .mra at STARTPATH declares the core running right now."""
    if not startpath or not corename:
        return False
    if not startpath.lower().endswith('.mra'):
        return False
    setname = _mra_setname(startpath)
    return bool(setname) and setname.lower() == corename.strip().lower()


def _load_romset_names(directory):
    """
    Every romset id declared by the NeoGeo core's own data files.
    A 'name' may carry comma-separated aliases; each one is registered, since
    any of them can be the filename on disk.
    Cached per directory and invalidated by mtime (the file is 41 KB).
    """
    if not directory or not os.path.isdir(directory):
        return frozenset()

    paths = [os.path.join(directory, n) for n in _ROMSET_XML_NAMES]
    try:
        stamp = tuple(os.path.getmtime(p) if os.path.isfile(p) else 0
                      for p in paths)
    except Exception:
        return frozenset()
    if not any(stamp):
        return frozenset()

    with _romset_cache_lock:
        cached = _romset_cache.get(directory)
        if cached and cached[0] == stamp:
            return cached[1]

    import xml.etree.ElementTree as ET
    names = set()
    for p in paths:
        if not os.path.isfile(p):
            continue
        try:
            root = ET.parse(p).getroot()
        except Exception as e:
            print(f"⚠️ {os.path.basename(p)} parse failed: {e}")
            continue
        for rs in root.iter('romset'):
            for alias in (rs.get('name') or '').split(','):
                alias = alias.strip().lower()
                if alias:
                    names.add(alias)

    frozen = frozenset(names)
    with _romset_cache_lock:
        _romset_cache[directory] = (stamp, frozen)
    print(f"ℹ️ NeoGeo romset ids loaded from {directory}: {len(frozen)}")
    return frozen


_romset_title_cache = {}              # directory -> (mtime_stamp, {id: title})


def _neogeo_romset_title(directory, romset):
    """
    Display title of a romset id, from the same data files the core reads.
    The OSD browser shows this title and leaves it in CURRENTPATH; a launcher
    that skips the browser leaves the id, and the panel should not.
    """
    if not directory or not romset or not os.path.isdir(directory):
        return ''
    paths = [os.path.join(directory, n) for n in _ROMSET_XML_NAMES]
    try:
        stamp = tuple(os.path.getmtime(p) if os.path.isfile(p) else 0
                      for p in paths)
    except Exception:
        return ''
    if not any(stamp):
        return ''

    with _romset_cache_lock:
        cached = _romset_title_cache.get(directory)
        if cached and cached[0] == stamp:
            return cached[1].get(romset.strip().lower(), '')

    import xml.etree.ElementTree as ET
    titles = {}
    for p in paths:
        if not os.path.isfile(p):
            continue
        try:
            root = ET.parse(p).getroot()
        except Exception:
            continue
        for rs in root.iter('romset'):
            title = (rs.get('altname') or '').strip()
            if not title:
                continue
            for alias in (rs.get('name') or '').split(','):
                alias = alias.strip().lower()
                if alias:
                    titles.setdefault(alias, title)

    with _romset_cache_lock:
        _romset_title_cache[directory] = (stamp, titles)
    return titles.get(romset.strip().lower(), '')


def _neogeo_games_dir(rom_path):
    """
    The directory holding romsets.xml for this ROM. The ROM can be nested while
    romsets.xml always sits at the games/NEOGEO root, so walk upwards until a
    romset file appears. Bounded to 4 levels.
    """
    if not rom_path:
        return None
    # A ZIP-internal path is not a filesystem path: the ZIP is the real entry.
    m = re.search(r'(.+\.zip)', rom_path, re.IGNORECASE)
    d = os.path.dirname(m.group(1) if m else rom_path)
    for _ in range(4):
        if not d or d == '/':
            break
        if any(os.path.isfile(os.path.join(d, n)) for n in _ROMSET_XML_NAMES):
            return d
        d = os.path.dirname(d)
    return None


def _resolve_neogeo_probe(mister_path):
    """
    Filesystem path for a MiSTer-relative path like 'games/NEOGEO/x/<romset>'.
    Only used to answer "is this a romset folder?" from the naming code, which
    runs outside the request handler and cannot call its resolver.
    """
    if not mister_path:
        return ''
    if mister_path.startswith('/'):
        return mister_path
    return os.path.join('/media/fat', mister_path)


def _neogeo_romset_label(path, corename):
    """
    The romset id when the path's own name IS the romset id, else ''.

    Covers the three shapes the core accepts: an unzipped romset folder, a
    zipped one, and a '.neo' named after the romset. Says nothing about
    hashability — that is _neogeo_romset_dir()'s job.
    Returns '' for '<Title> (<romset>).neo', whose stem is a title.
    """
    core = (corename or '').strip()
    if core.upper().startswith('RA_'):
        core = core[3:]
    if core.lower() not in _NEOGEO_CORENAMES:
        return ''
    if not path:
        return ''
    if os.path.isdir(path):
        name = os.path.basename(path.rstrip('/')).strip().lower()
    elif os.path.isfile(path):
        name = os.path.splitext(os.path.basename(path))[0].strip().lower()
    else:
        return ''
    if not name:
        return ''
    names = _load_romset_names(_neogeo_games_dir(path))
    return name if name in names else ''


def _is_sd_root_file(path):
    """True when the path is a file sitting directly in the card's root, where
    configuration, scripts and documentation live but no game does. Both mount
    points are covered because a path can be resolved through either.
    """
    try:
        parent = os.path.dirname(os.path.normpath(path)).rstrip('/')
    except Exception:
        return False
    return parent in ('/media/fat', '/media/usb0', '/media/usb1', '/media/usb2',
                      '/media/usb3', '/media/usb4', '/media/usb5', '')


def _neogeo_romset_dir(path, corename):
    """
    The romset id when `path` is a romset CONTAINER (a romset folder, zipped
    or not), else ''. Narrower than _neogeo_romset_label() on purpose: this one
    drives no_hash, and a container has no single file to hash.
    """
    if not path:
        return ''
    is_container = (os.path.isdir(path) or
                    (path.lower().endswith('.zip') and os.path.isfile(path)))
    if not is_container:
        return ''
    return _neogeo_romset_label(path, corename)
    # The RA_ prefix is stripped here rather than in every caller: the
    # display-name call site passes the raw CORENAME.


def _neogeo_ss_romnom(rom_path, filename, corename):
    """
    ScreenScraper romnom for a NeoGeo ROM: '<romset>.zip', or '' when unknown.

    Two candidates, most confident first: the parenthesised group at the end of
    the stem ('<Title> (<romset>).neo'), then the bare stem. Both are confirmed
    against romsets.xml before use; '' leaves the firmware's current behaviour
    untouched.

    Prefix matching is deliberately not attempted: a title can prefix two
    different romset ids, and guessing between them is not acceptable.
    """
    if (corename or '').strip().lower() not in _NEOGEO_CORENAMES:
        return ''

    stem = os.path.splitext(os.path.basename(filename or ''))[0]
    if not stem:
        return ''

    candidates = []
    m = re.search(r'\(([^()]+)\)\s*$', stem)
    if m:
        candidates.append(m.group(1).strip())
    candidates.append(stem.strip())

    names = _load_romset_names(_neogeo_games_dir(rom_path))
    if not names:
        return ''

    for c in candidates:
        if c.lower() in names:
            romnom = c.lower() + '.zip'
            print(f"🎯 NeoGeo romset resolved: '{stem}' -> romnom={romnom}")
            return romnom

    print(f"ℹ️ NeoGeo: no romset id confirmed for '{stem}' - using filename")
    return ''

# --- Container-image denylist -------------------------------------------------
# A DOS .vhd usually holds a whole environment or a compilation rather than a
# title, but jeuRecherche always returns its best fuzzy hit (observed: id 170580
# for 'boot'), so the firmware would show wrong artwork. Not an extension check:
# some collections ship one .vhd per game with a real title, where name search
# is right. Matching happens AFTER _clean_search_name(), i.e. lowercased and
# with -/_/whitespace collapsed, so one entry covers 'pack-1' and 'Pack 1'.

# Whole-name matches: the cleaned name IS the container, no suffix possible.
GENERIC_MEDIA_NAMES = {'hdd', 'harddisk', 'system'}

# OS designators that may qualify a bare container marker: 'BOOT-DOS98'.
_OS_TOKEN = r'(?:(?:ms)?dos ?\d*(?:\.\d+)?|win ?(?:31|3\.1|95|98|me|xp)|w9[58])'

# Bare container names, optionally qualified by an OS designator. 'boot' is not
# a free prefix: real DOS titles begin with that word, so only 'boot' alone or
# 'boot <os>' counts. A false positive kills artwork for a real game forever.
GENERIC_MEDIA_RE = re.compile(
    r'^(?:hdd?\d*|disk\d*|drive ?[a-z]|' + _OS_TOKEN + r'|boot(?: ' + _OS_TOKEN + r')?)$',
    re.I,
)

# Leading-marker matches: a collection marker plus any builder or variant
# suffix, which every distribution writes differently. Leading only: a real
# title may contain the same marker mid-name and must still reach the search.
GENERIC_MEDIA_PREFIXES = ('shareware', 'top 300')


def is_generic_media_name(stem):
    """True when the cleaned name identifies a container image, not a game."""
    s = re.sub(r'[-_\s]+', ' ', (stem or '').strip().lower()).strip()
    if not s:
        return False
    if s in GENERIC_MEDIA_NAMES or GENERIC_MEDIA_RE.match(s):
        return True
    return any(s == p or s.startswith(p + ' ') for p in GENERIC_MEDIA_PREFIXES)


# Some collections glue variant markers onto the stem as pseudo-extensions that
# splitext() does not remove, so they survive into the query and miss a game
# that IS in the database. Only two are in use: '.mt32' (Roland MT-32 build) and
# '.r2/.r3/.r4' (setup revision). They stack in either order, hence the loop.
_VARIANT_RE = re.compile(
    r'(?:'
    r'[.\-_ ]+(?:mt32|mt-32)'   # audio build; separator varies in community packs
    r'|\.r\d+'                  # setup revision; always dotted
    r')$',
    re.I,
)

# A trailing '-<n>' is a CD disc number, not part of the title.
# Two guards: at most 2 digits, so a '-300' compilation marker survives; and
# the remainder must be more than one word, so a short hyphenated title is not
# decapitated to its first letter.
_DISC_RE = re.compile(r'(.*)-\d{1,2}$')


def _strip_disc_number(base):
    """Removes a trailing CD disc number when it cannot be part of the title."""
    mo = _DISC_RE.match(base)
    if not mo:
        return base
    title = mo.group(1)
    return title if ' ' in title else base   # one-word remainder: keep the original


def _strip_variant_markers(base):
    """Removes stacked trailing variant markers ('.r2.mt32') from a file stem."""
    while True:
        stripped = _VARIANT_RE.sub('', base)
        if stripped == base:      # the pattern needs >=1 separator char, so every
            return base           # successful sub shortens: no infinite loop
        base = stripped


def _clean_search_name(name):
    """
    Derives a ScreenScraper text-search query from a game/file name: strips the
    extension, variant markers, disc numbers, bracketed tags and ALL
    parenthesised groups, then collapses separators.
      'Some Title (1990)(Publisher).vhd' -> 'Some Title'
      'some title-1.mt32.chd'            -> 'some title'
      'Some Title_[tag].mgl'             -> 'Some Title'
    Recall beats precision: jeuRecherche matches best on bare titles.
    """
    base = os.path.splitext(os.path.basename(name or ''))[0]
    base = _strip_variant_markers(base)        # '.mt32', '.r2' audio/revision siblings
    base = _strip_disc_number(base)            # '-1' CD disc number
    base = re.sub(r'\[[^\]]*\]', '', base)     # [tags]
    base = re.sub(r'\([^)]*\)', '', base)      # (Year)(Publisher)(Region)
    base = base.lstrip('~ ')                   # some collections mark broken setups with '~'
    base = base.replace('_', ' ')
    base = re.sub(r'\s{2,}', ' ', base).strip(' -.')
    return base

def _norm_game_label(s):
    """Casefold + collapse whitespace, for identity comparison only."""
    return ' '.join((s or '').split()).casefold()


def _path_names_game(candidate, game):
    """
    True when a tracker path plausibly NAMES the committed game. Matching is
    deliberately generous — a false accept costs nothing, a false reject blocks
    a legitimate hash:

      suffix    — the normalized candidate equals the game, or ends with
                  '/' + game (whole string first: NeoGeo titles can contain '/').
      stem      — same test with the last component's extension stripped.
      component — any single component equals the game, raw or without its own
                  extension ('.../Game (E)/track01.cue').
    """
    ng = _norm_game_label(game)
    if not ng:
        return True
    cand = (candidate or '').replace('\\', '/').rstrip('/')
    nc = _norm_game_label(cand)
    if nc == ng or nc.endswith('/' + ng):
        return True
    stem_cand = os.path.splitext(cand)[0]
    ns = _norm_game_label(stem_cand)
    if ns == ng or ns.endswith('/' + ng):
        return True
    for part in cand.split('/'):
        np = _norm_game_label(part)
        if np == ng or _norm_game_label(os.path.splitext(part)[0]) == ng:
            return True
    return False


# ---------------------------------------------------------------------------
# Boxart Pack — local artwork resolution
#
# One image per GAME (not per dump) at docs/<System>/Artwork/<key>.jpg, plus an
# index.tsv of (name, crc, size, key) rows mapping every known dump of a game to
# the image that represents it, so a regional variant with no file of its own
# is sent to the image of the dump the pack picked.
# Installed with path 'pext', so the mount points are probed, never assumed.
# ---------------------------------------------------------------------------

# Friendly system name -> pack folder. Keyed on what get_game_system() resolves,
# not on core_raw, which would send a Master System cartridge to the Genesis
# folder. Must move together with the builder's scope.ini: a system present in
# one and absent from the other falls through to ScreenScraper.
_PACK_SYSTEM = {
    'Nintendo NES/Famicom':            'NES',
    'Famicom Disk System':             'FDS',
    'Satellaview':                     'Satellaview',
    'Super Nintendo/Super Famicom':    'SNES',
    'Nintendo 64':                     'N64',
    'Nintendo Game Boy':               'GAMEBOY',
    'Nintendo Game Boy Color':         'GBC',
    'Nintendo Game Boy Advance':       'GBA',
    'Nintendo Game Boy Advance 2P':    'GBA',
    'Sega Genesis/Mega Drive':         'Genesis',
    'Sega Master System':              'SMS',
    'Sega Game Gear':                  'GameGear',
    'Sega Mega-CD':                    'MegaCD',
    'Sega Saturn':                     'Saturn',
    'TurboGrafx-16/PC Engine':         'TGFX16',
    'TurboGrafx-16/PC Engine CD-Rom':  'TGFX16-CD',
    'Sony PlayStation':                'PSX',
    'Atari 2600':                      'Atari2600',
    'Atari 5200':                      'ATARI5200',
    'Atari 7800':                      'ATARI7800',
    'Atari Lynx':                      'AtariLynx',
    'Atari Lynx (2P)':                 'AtariLynx',
    'Atari Jaguar':                    'Jaguar',
    'Neo-Geo':                         'NEOGEO',
    'Neo-Geo CD':                      'NeoGeo-CD',
    'Nintendo Virtual Boy':            'VirtualBoy',
    'Sega SG-1000':                    'SG-1000',
    'Sega Genesis/Megadrive 32X':      'S32X',
    'PC Engine SuperGrafx':            'SuperGrafx',
    # The NGP/NGPC cores report these consoles without the hyphen.
    'Neo-Geo Pocket':                  'NeoGeoPocket',
    'Neo Geo Pocket':                  'NeoGeoPocket',
    'Neo-Geo Pocket Color':            'NeoGeoPocket-Color',
    'Neo Geo Pocket Color':            'NeoGeoPocket-Color',
    'Bandai WonderSwan':               'WonderSwan',
    'Bandai WonderSwan Color':         'WonderSwanColor',
    'Colecovision':                    'Coleco',
    'Mattel/INTV Intellivision':       'Intellivision',
    'Vectrex':                         'VECTREX',
    'Videopac G7000/Odyssey 2':        'ODYSSEY2',
    '3DO Interactive Multiplayer':     '3DO',
    'Philips CD-i':                    'CD-i',
    'Amiga CD32':                      'AmigaCD32',
}

_PACK_MOUNTS = ['/media/fat'] + ['/media/usb%d' % i for i in range(8)]

# dir -> (mtime_ns, {name_lower: key}, {'crc:size': key}). Arcade's index is 12k
# rows and only changes when the Downloader rewrites it.
_pack_index_cache = {}
_pack_index_lock = threading.Lock()


def _pack_dir(system_folder):
    """Absolute path of the pack folder for a system, '' when not installed."""
    if not system_folder:
        return ''
    for mount in _PACK_MOUNTS:
        candidate = os.path.join(mount, 'docs', system_folder, 'Artwork')
        if os.path.isdir(candidate):
            return candidate
    return ''


# Catalogues that share a core: each keeps its own docs/ folder and falls back to
# its sibling. ScreenScraper splits dual-mode cartridges between catalogues, so a
# game the pack HAS would otherwise read as missing. FDS falls back to NES but
# not the other way round: a cartridge must never receive the disk release's box.
_PACK_SIBLINGS = {
    'GAMEBOY': ('GBC',),
    'GBC': ('GAMEBOY',),
    'FDS': ('NES',),
    # Same asymmetry: a cartridge never receives a Satellaview box.
    'Satellaview': ('SNES',),
}

# Cores with no catalogue of their own. The Super Game Boy core runs Game Boy
# cartridges and ScreenScraper's SGB catalogue carries poorer media, so it
# borrows the Game Boy folders instead of getting a pack of its own.
_PACK_BORROWS = {
    'Nintendo Super Game Boy': ('GAMEBOY', 'GBC'),
}


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
                return found, resolved, folder
    return '', '', (folders[0] if folders else '')


def _pack_title(name):
    """A dump name without its parenthesised tags, so '<Title> (NTSC)
    (Publisher) (1988)' and '<Title> (USA)' both reduce to '<title>'."""
    return re.sub(r'\s+', ' ', re.sub(r'\([^)]*\)', ' ', name)).strip().lower()


def _pack_index(pack_dir):
    """(by_name, by_hash, by_title) for a pack folder. Empty dicts when there is
    no index.tsv: a pack without one still resolves by exact filename."""
    index_path = os.path.join(pack_dir, 'index.tsv')
    try:
        stamp = os.stat(index_path).st_mtime_ns
    except OSError:
        return {}, {}, {}

    with _pack_index_lock:
        cached = _pack_index_cache.get(pack_dir)
        if cached and cached[0] == stamp:
            return cached[1], cached[2], cached[3]

    by_name, by_hash, by_title = {}, {}, {}
    try:
        with io.open(index_path, encoding='utf-8', errors='replace') as f:
            for line in f:
                if not line or line[0] == '#':
                    continue
                parts = line.rstrip('\r\n').split('\t')
                if len(parts) < 4:
                    continue
                name, crc, size, key = parts[0], parts[1], parts[2], parts[3]
                if not key:
                    continue
                if name:
                    by_name[name.strip().lower()] = key
                    # '' marks a title two different games share: matching it
                    # would be a coin flip, so it is left unresolved.
                    title = _pack_title(name)
                    if title:
                        by_title[title] = key if by_title.get(
                            title, key) == key else ''
                # Arcade rows carry no crc or size (a MAME set is a zip of many
                # files), so they resolve by name, which is exact anyway.
                if crc and size:
                    by_hash['%s:%s' % (crc.strip().lower(), size.strip())] = key
    except Exception as e:
        print("\u26a0\ufe0f pack index read failed: %s" % e)
        return {}, {}, {}

    with _pack_index_lock:
        _pack_index_cache[pack_dir] = (stamp, by_name, by_hash, by_title)
    return by_name, by_hash, by_title


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
        return '', ''

    if key:
        direct = os.path.join(pack_dir, key + '.jpg')
        if os.path.isfile(direct):
            return direct, key

    by_name, by_hash, by_title = _pack_index(pack_dir)

    if key:
        mapped = by_name.get(key.strip().lower())
        if mapped:
            candidate = os.path.join(pack_dir, mapped + '.jpg')
            if os.path.isfile(candidate):
                return candidate, mapped

    # A rom pack naming its files '<title> (<setname>)' resolves on the setname
    # alone. It only fires when that tail IS a key in this folder, which is what
    # makes it safe: the tail of '<Title> (World) (Rev 1)' is 'Rev 1', and no
    # pack has an image called that.
    if key:
        tail = re.search(r'\(([^()]+)\)\s*$', key)
        if tail:
            setname = tail.group(1).strip()
            candidate = os.path.join(pack_dir, setname + '.jpg')
            if setname and os.path.isfile(candidate):
                return candidate, setname

    # The server formats CRC32 uppercase ('05FBB855'), the index stores it
    # lowercase, so both sides are normalised.
    if crc and size:
        mapped = by_hash.get('%s:%s' % (str(crc).strip().lower(), str(size).strip()))
        if mapped:
            candidate = os.path.join(pack_dir, mapped + '.jpg')
            if os.path.isfile(candidate):
                return candidate, mapped

    if key:
        mapped = by_title.get(_pack_title(key))
        if mapped:
            candidate = os.path.join(pack_dir, mapped + '.jpg')
            if os.path.isfile(candidate):
                return candidate, mapped

    return '', ''


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
            if setname and re.match(r'^[a-z0-9][a-z0-9_-]*$', setname):
                return [setname]
        return []
    # Consoles: the standard dump name without its extension. Zip paths carry
    # the real name at the end, so basename() covers them too.
    keys = [os.path.splitext(os.path.basename(game_path))[0]]

    # A game NAME may contain a slash (NeoGeo titles from romsets.xml do), which
    # basename() would cut down to the last segment, so the candidate is rebuilt
    # from the last directory that actually exists on disk.
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


def _pack_resolve_for_state(game_path, is_arcade, game_system, core, seq):
    """Resolves the pack image at state-commit time and records which seq it
    belongs to, so /media/artwork is correct before the display asks."""
    path = ''
    try:
        folders = (['Arcade'] if is_arcade
                   else _pack_folders(game_system or core))
        if folders:
            keys = _pack_key_from_state(game_path, is_arcade)
            path, resolved, system_folder = _pack_lookup_any(folders, keys, '', '')
            if path:
                print("\U0001f5bc\ufe0f local artwork: %s/%s.jpg" % (system_folder, resolved))
    except Exception as e:
        print("\u26a0\ufe0f local artwork lookup failed: %s" % e)
    with _state_lock:
        _state['artwork_path'] = path
        _state['artwork_seq'] = seq


def _pack_annotate(result):
    """Adds artwork_local / artwork_key / artwork_system to a rom-details result
    and caches the resolved path for /media/artwork to serve.

    Never raises: a pack problem must not be able to break rom-details, which
    the firmware needs for everything else.
    """
    result['artwork_local'] = False
    result['artwork_key'] = ''
    result['artwork_system'] = ''
    try:
        with _state_lock:
            is_arcade = _state['is_arcade']
            friendly = _state['game_system'] or _state['core']
            path_for_name = _state['game_path']

        folders = ['Arcade'] if is_arcade else _pack_folders(friendly)
        if not folders:
            return result
        system_folder = folders[0]

        if is_arcade:
            # The .mra names its romset in <setname>, and that id is the pack's
            # arcade key — the same identifier ss_romnom extracts above.
            arc_path = result.get('path') or path_for_name or ''
            key = ''
            if arc_path.lower().endswith('.mra'):
                setname = _mra_setname(arc_path).strip().lower()
                if setname and re.match(r'^[a-z0-9][a-z0-9_-]*$', setname):
                    key = setname
        else:
            # Consoles: the standard dump name without its extension.
            key = os.path.splitext(result.get('filename') or '')[0]

        found, resolved, system_folder = _pack_lookup_any(
            folders, key, result.get('crc32'), result.get('size'))
        result['artwork_system'] = system_folder
        if found:
            result['artwork_local'] = True
            result['artwork_key'] = resolved
            # Only ever UPGRADES what the state commit resolved: the CRC step
            # can find an image the name step missed, but a miss here must not
            # wipe a good path.
            with _state_lock:
                if _state['artwork_path'] != found:
                    _state['artwork_path'] = found
                    _state['artwork_seq'] = _state['seq']
            print("\U0001f5bc\ufe0f local artwork: %s/%s.jpg" % (system_folder, resolved))
    except Exception as e:
        print("\u26a0\ufe0f local artwork lookup failed: %s" % e)
    return result


def _enrich_rom_result(result, detection_method=None):
    """
    Adds name-search metadata to a rom-details result (success OR failure):
      search_name      — clean title for jeuRecherche.php. Always populated:
                         the firmware displays it even when it must not search.
      no_hash          — True when the CRC can NEVER arrive. Distinct from
                         hash_calculated, which is also False while a hash is
                         still in flight.
      ss_romnom        — ScreenScraper romnom override ('<romset>.zip'); '' means
                         "use the filename", i.e. exactly today's behaviour.
      container_image  — True when search_name denotes a whole-environment or
                         compilation image rather than a game ('boot', a
                         collection marker). These must never be
                         text-searched: jeuRecherche has no "no match" and
                         returns confident-looking wrong artwork.
      name_search_hint — True when the CRC route cannot work.

    The last two are independent: a DOS game with a valid but unindexed CRC has
    both False and must STILL reach the text search after the CRC path misses.
    """
    with _state_lock:
        game_for_name = _state['game']
        path_for_name = _state['game_path']

    ext = os.path.splitext(result.get('path') or path_for_name or '')[1].lower()
    search_name = _clean_search_name(result.get('filename') or game_for_name)
    corename_raw = _read_corename_raw()
    no_hash = _is_no_hash(ext, corename_raw)
    # A romset folder has no single file to hash, so the CRC can never arrive.
    # Saying so stops the firmware spending its retry budget waiting for one.
    _ng_path = result.get('path') or path_for_name

    # When the path's name is a romset id it is useless as a ScreenScraper text
    # search: use the title the core resolved from romsets.xml instead. Used
    # verbatim — _clean_search_name() is built for FILENAMES and would truncate
    # a title containing a slash to its last segment.
    if game_for_name and _neogeo_romset_label(_ng_path, corename_raw):
        search_name = ' '.join(game_for_name.split())

    # A romset CONTAINER (folder or zip) has no single file to hash.
    if not no_hash and _neogeo_romset_dir(_ng_path, corename_raw):
        no_hash = True

    result['search_name']      = search_name
    result['no_hash']          = bool(no_hash)
    result['container_image']  = bool(is_generic_media_name(search_name))
    result['ss_romnom']        = _neogeo_ss_romnom(
        result.get('path') or path_for_name,
        result.get('filename'),
        corename_raw)
    # Arcade: the launched .mra names its romset in <setname>, and that id IS
    # ScreenScraper's key (SS indexes arcade as MAME romsets), exactly like the
    # NeoGeo override above. Same contract: '' means "use the filename", so a
    # missing or malformed setname changes nothing.
    if not result['ss_romnom']:
        _arc_p = (result.get('path') or path_for_name or '')
        if _arc_p.lower().endswith('.mra'):
            _arc_sn = _mra_setname(_arc_p).strip().lower()
            if _arc_sn and re.match(r'^[a-z0-9][a-z0-9_-]*$', _arc_sn):
                result['ss_romnom'] = _arc_sn + '.zip'
                print(f"🕹️ arcade romnom from .mra setname: '{result['ss_romnom']}'")
    result['name_search_hint'] = bool(
        (not result.get('available')) or
        (not result.get('crc32')) or
        no_hash
    )

    # no_rom_on_disk — there is a NAME to show but no rom file to hash at all
    # (SAM name-only content: Amiga demos, WHDLoad, some MGL). The firmware uses
    # it to show a stable NOT-IN-DATABASE card instead of the
    # "DOWNLOADING -> download failed" flash. Keyed on detection_method and not
    # on available: a legitimate CD32/DOS title resolves a real file and its
    # name search must still run.
    result['no_rom_on_disk'] = bool(detection_method == 'sam_no_path')

    # Local-first artwork. Runs last: it consumes filename, crc32 and size.
    _pack_annotate(result)
    return result

# ---------------------------------------------------------------------------
# MiSTer system folders that can never contain the RUNNING game. The OSD file
# browser is one generic component reused for scripts, filters, gamma tables,
# documentation and core selection, and every confirmed selection emits the very
# same FILESELECT + CURRENTPATH breadcrumbs as a game launch. Companion daemons
# amplify the noise: running a script can leave ACTIVEGAME='Scripts' behind.
# Any path whose first component (after the mount prefix) lands in this set, or
# starts with '_' (_Console, _Utility, _@Favorites …), is browser debris.
# ---------------------------------------------------------------------------
# How much OLDER than ACTIVEGAME the 'selected' witness may be and still count
# as the same launch. Trackers mirror browser state a settle delay AFTER
# menu.cpp writes 'selected'; a launcher that bypasses the OSD leaves it minutes
# behind instead, and then ACTIVEGAME must win.
_SELECTED_STALENESS_MARGIN_S = 5.0
_SELECTED_PAIRING_S = 5.0

_MISTER_SYSTEM_DIRS = frozenset({
    'scripts', 'filters', 'filters_audio', 'gamma', 'shadow_masks',
    'presets', 'cheats', 'config', 'linux', 'font', 'saves',
    'savestates', 'screenshots', 'wallpapers', 'docs',
})

_MOUNT_PREFIX_RE = re.compile(r'^/?(?:media/(?:fat|usb\d+)/)?', re.IGNORECASE)

def _is_system_path(path):
    """True when 'path' points into a MiSTer system folder — never a game."""
    if not path:
        return False
    rest = _MOUNT_PREFIX_RE.sub('', path.strip(), count=1)
    first = rest.split('/', 1)[0]
    return bool(first) and (first.lower() in _MISTER_SYSTEM_DIRS
                            or first.startswith('_'))

# ---------------------------------------------------------------------------
# ZIP virtual paths for the state machine. Inside a pack zip
# (games/<System>/a.zip/a/<title>) os.path probing is blind: the composed
# candidate is neither a file nor an isdir, and the browsed location would be
# minted as the game name. The zip's central directory answers both questions,
# cached by (path, mtime_ns) because the evaluator runs on every inotify burst.
#
# Splitting mirrors is_zip_path; member matching mirrors
# get_zip_file_info_enhanced (exact, case-insensitive, then stem). The
# basename-only strategy is NOT mirrored: identity needs the whole path to agree.
# ---------------------------------------------------------------------------
_ZIP_SPLIT_RE = re.compile(r'(.+\.zip)', re.IGNORECASE)

_zip_dir_cache = {}      # zip_abs -> (mtime_ns, lower_map, stem_map, dirset)
_zip_dir_lock = threading.Lock()


def _zip_split(path):
    """('games/X/a.zip', 'a/title') for a zip virtual path, else ('', '')."""
    if not path or '.zip' not in path.lower():
        return '', ''
    m = _ZIP_SPLIT_RE.search(path)
    if not m:
        return '', ''
    zip_part = m.group(1)
    internal = path[len(zip_part):].lstrip('/')
    return zip_part, internal


def _zip_entries(zip_abs):
    """Cached central-directory views; ({}, {}, frozenset()) when unreadable."""
    stamp = 0
    try:
        stamp = _get_mtime_ns(zip_abs)
    except Exception:
        pass
    if not stamp:
        return {}, {}, frozenset()

    with _zip_dir_lock:
        cached = _zip_dir_cache.get(zip_abs)
        if cached and cached[0] == stamp:
            return cached[1], cached[2], cached[3]

    lower_map, stem_map, dirs = {}, {}, set()
    try:
        with zipfile.ZipFile(zip_abs, 'r') as zf:
            for name in zf.namelist():
                norm = name.replace('\\', '/')
                if norm.endswith('/'):
                    dirs.add(norm.rstrip('/').lower())
                    continue
                lower_map.setdefault(norm.lower(), norm)
                stem_map.setdefault(
                    os.path.splitext(norm)[0].lower(), []).append(norm)
                parts = norm.split('/')
                for i in range(1, len(parts)):
                    dirs.add('/'.join(parts[:i]).lower())
    except Exception as e:
        print(f"\u26a0\ufe0f zip central directory unreadable: "
              f"{os.path.basename(zip_abs)}: {e}")
        lower_map, stem_map, dirs = {}, {}, set()

    dirset = frozenset(dirs)
    with _zip_dir_lock:
        _zip_dir_cache[zip_abs] = (stamp, lower_map, stem_map, dirset)
    return lower_map, stem_map, dirset


def _zip_member_match(zip_abs, internal):
    """The real member for a (possibly extensionless) internal path, or ''."""
    if not internal:
        return ''
    lower_map, stem_map, _ = _zip_entries(zip_abs)
    if not lower_map:
        return ''
    norm = internal.replace('\\', '/').lstrip('/')
    hit = lower_map.get(norm.lower())
    if hit:
        return hit
    stems = stem_map.get(os.path.splitext(norm)[0].lower())
    if not stems:
        return ''
    rom_hit = next((m for m in stems
                    if os.path.splitext(m)[1].lower() in _KNOWN_ROM_EXTS),
                   None)
    return rom_hit if rom_hit else stems[0]


def _zip_internal_is_folder(zip_abs, internal):
    """True when the internal path is a DIRECTORY inside the zip."""
    if not internal:
        return False
    _, _, dirset = _zip_entries(zip_abs)
    return internal.replace('\\', '/').strip('/').lower() in dirset


_MGL_FILE_PATH_RE = re.compile(r'<file\b[^>]*\bpath\s*=\s*"([^"]*)"', re.I)
_MGL_MAX_BYTES = 8192


def _is_launcher_mgl(path):
    """
    True for the scratch MGL a launcher generates to load a game (Zaparoo's
    '/media/fat/.LASTLAUNCH.mgl'). A named MGL stored with the games is the
    identity the user launched and keeps its own name, so only hidden files
    and the card root — where launchers drop theirs — qualify.
    """
    if not path or not path.lower().endswith('.mgl'):
        return False
    return os.path.basename(path).startswith('.') or _is_sd_root_file(path)


def _media_exists(path):
    """
    True when a path is on disk OR names a real member inside a zip, which
    exists() cannot see. Launchers write both forms, so every resolved media
    path is checked here rather than at each call site.
    """
    if not path:
        return False
    if os.path.exists(path):
        return True
    zip_rel, zip_internal = _zip_split(path)
    if not zip_rel or not zip_internal:
        return False
    zip_abs = (zip_rel if zip_rel.startswith('/')
               else os.path.join('/media/fat', zip_rel))
    return bool(_zip_member_match(zip_abs, zip_internal))


_CD32_CFG = '/media/fat/config/AmigaCD32.cfg'
_CD32_PATH_OFFSET = 3100
_CD32_PATH_LEN = 108


def _amiga_cd32_media():
    """
    The disc the CD32 core has mounted, or ''. Launchers do not name it in the
    MGL: they write the path into AmigaCD32.cfg and emit a bare <setname>, so
    the config is the only witness of what is running.
    """
    try:
        with open(_CD32_CFG, 'rb') as f:
            f.seek(_CD32_PATH_OFFSET)
            raw = f.read(_CD32_PATH_LEN)
    except Exception as e:
        print(f"⚠️ AmigaCD32.cfg unreadable: {e}")
        return ''

    rel = raw.split(b'\x00', 1)[0].decode('utf-8', 'replace').strip()
    if not rel:
        return ''
    while rel.startswith('../'):        # stored relative to /media
        rel = rel[3:]
    path = os.path.normpath('/media/' + rel.lstrip('/'))
    if not _media_exists(path):
        print(f"⚠️ AmigaCD32 disc not found: {path}")
        return ''
    return path


def _mgl_target(mgl_path):
    """
    The ROM an MGL points at, or '' when it names none (core-only MGL), cannot
    be read, or resolves to something absent. Launchers write the media path
    prefixed by a fixed run of parent hops, so stripping them yields it back;
    AmigaCD32 is the exception and is read from the core's cfg instead.
    """
    try:
        with open(mgl_path, 'r', errors='replace') as f:
            xml = f.read(_MGL_MAX_BYTES)
    except Exception as e:
        print(f"⚠️ MGL unreadable: {mgl_path} ({e})")
        return ''

    m = _MGL_FILE_PATH_RE.search(xml)
    if not m:
        if 'AmigaCD32' in xml:
            return _amiga_cd32_media()
        print(f"ℹ️ MGL names no file: {mgl_path}")
        return ''

    raw = (m.group(1)
           .replace('&quot;', '"').replace('&apos;', "'")
           .replace('&lt;', '<').replace('&gt;', '>')
           .replace('&amp;', '&'))       # &amp; last, or it un-escapes the rest

    cleaned = raw.replace('\\', '/')
    while cleaned.startswith('../'):
        cleaned = cleaned[3:]
    if not cleaned.startswith('/'):
        cleaned = '/' + cleaned
    if not cleaned.startswith(('/media/', '/tmp/')):
        # hand-written MGL: the path is relative to the MGL's own folder
        cleaned = os.path.join(os.path.dirname(mgl_path), raw)
    cleaned = os.path.normpath(cleaned)

    if _media_exists(cleaned):
        return cleaned

    print(f"⚠️ MGL target does not exist: {cleaned}")
    return ''


def _deref_launcher_mgl(path, label='ACTIVEGAME'):
    """
    Replaces a launcher's scratch MGL with the ROM inside it. Without this the
    trackers announce the MGL itself, so the stem ('.LASTLAUNCH') becomes the
    title and the SD-root guard drops the path. Falls back to the value it was
    given whenever the MGL names nothing usable.
    """
    if not _is_launcher_mgl(path):
        return path
    abs_mgl = path if path.startswith('/') else os.path.join('/media/fat', path)
    target = _mgl_target(abs_mgl)
    if not target:
        return path
    print(f"🔗 {label} is a launcher MGL — dereferenced to: '{target}'")
    return target


_LAUNCH_MGL = '/media/fat/.LASTLAUNCH.mgl'


def _scratch_mgl_game(corename_ts):
    """
    The game named by the scratch MGL at the card root, when that MGL was
    written for the current core load. Console Mode launches through it and
    announces nothing else, so the MGL is the only witness; the window keeps
    one left by an earlier launcher out. FAT rounds mtimes to 2 s.
    """
    mgl_ts = _get_mtime_ns(_LAUNCH_MGL) / 1e9
    if not mgl_ts or not (corename_ts - 30 <= mgl_ts <= corename_ts + 5):
        return ''
    return _mgl_target(_LAUNCH_MGL)


def _game_name_from_path(path):
    """
    Extracts the game name from a file path. Only strips the extension when it
    is a known ROM extension, so version suffixes like '.000' survive.
    """
    base = os.path.basename(path)
    ext  = os.path.splitext(base)[1].lower()
    return os.path.splitext(base)[0] if ext in _KNOWN_ROM_EXTS else base

def _update_state():
    """
    Reads /tmp/ files and updates _state.
    Called by the watcher thread on every relevant filesystem event.
    """
    corename    = _read_file('/tmp/CORENAME')
    activegame  = _deref_launcher_mgl(_read_file('/tmp/ACTIVEGAME'))
    currentpath = _read_file('/tmp/CURRENTPATH')
    # FILESELECT's CONTENT, not just its mtime: Main_MiSTer writes 'active'
    # while the browser is open and 'selected' at the moment of a real launch.
    fileselect  = _read_file('/tmp/FILESELECT')
    fullpath    = _read_file('/tmp/FULLPATH')

    # --- Navigation vs real load (tolerant gate) ---
    # During OSD navigation FILESELECT and CURRENTPATH are written back-to-back
    # (sub-millisecond apart); on a real load only FILESELECT is touched. A
    # tolerance window separates them: a cursor move plus Enter is >= ~100 ms.
    global _last_evaluated_corename

    # --- SAM detection runs BEFORE the OSD guard ---
    # SAM loads in bursts that timing alone cannot tell apart from OSD
    # navigation, so the guard would swallow every same-core SAM hop. When SAM
    # owns the state a burst IS a real load: decide here and return.
    # _last_evaluated_corename is advanced so a later non-SAM event still has a
    # correct baseline for the guard.
    if _sam_is_current():
        sam_active, sam_core_raw, sam_core_friendly, sam_game, sam_path = _sam_get_current()
        if sam_active and sam_core_raw:
            corename = _read_file('/tmp/CORENAME')
            _last_evaluated_corename = corename
            print(f"🎮 SAM active — core='{sam_core_friendly}' game='{sam_game}'")
            sam_arcade = sam_core_raw.lower() in {'arcade', 'stv'} or sam_path.lower().endswith('.mra')
            _commit_state('Arcade' if sam_arcade else sam_core_friendly, sam_game, sam_path,
                          is_arcade=sam_arcade, event='sam', core_raw=sam_core_raw)
            return

    fs_ns = _get_mtime_ns('/tmp/FILESELECT')
    cp_ns = _get_mtime_ns('/tmp/CURRENTPATH')
    ag_ns = _get_mtime_ns('/tmp/ACTIVEGAME')

    _NAV_COUPLING_MS = 50.0
    delta_ms = abs(fs_ns - cp_ns) / 1e6

    core_changed      = (corename != _last_evaluated_corename)
    activegame_recent = (time.time_ns() - ag_ns) <= 3_000_000_000  # explicit launch (Remote/Zaparoo)

    # Timing cannot separate navigation from launch here, but content can:
    # 'selected' is written only on an actual launch, so it vetoes the
    # navigation verdict — and it needs no tracker running.
    fileselect_load = (fileselect == 'selected')

    if (delta_ms <= _NAV_COUPLING_MS and not core_changed
            and not activegame_recent and not fileselect_load):
        print(f"🔀 OSD navigation detected (Δ={delta_ms:.2f} ms) — state unchanged")
        return

    _last_evaluated_corename = corename

    # --- Menu ---
    if not corename or corename.upper() == 'MENU':
        print("📋 MENU detected")
        _commit_state('Menu', '', '', is_arcade=False, event='menu',
                      core_raw=corename)
        return

    # --- Resolve friendly core name ---
    # The RetroAchievements toolkit loads adapted cores through MGLs whose
    # <setname> prefixes the stock name with 'RA_'. Strip it so they resolve
    # exactly like their stock counterparts; the raw corename keeps flowing to
    # the arcade/ACTIVEGAME logic below.
    lookup_name = corename[3:] if corename.startswith('RA_') else corename
    friendly_name = (CORE_NAME_MAPPING.get(lookup_name) or
                    CORE_NAME_MAPPING_LOWER.get(lookup_name.lower()) or
                    lookup_name)
    friendly_name = CORE_NAME_MAPPING.get(friendly_name, friendly_name)

    if friendly_name == corename and '-' in corename:
        prefix = corename.split('-', 1)[0]
        prefix_friendly = (CORE_NAME_MAPPING.get(prefix) or
                           CORE_NAME_MAPPING_LOWER.get(prefix.lower()))
        if prefix_friendly:
            print(f"🔧 MGL prefix '{prefix}' resolved to core '{prefix_friendly}'")
            friendly_name = prefix_friendly

    # --- Arcade detection ---
    ARCADE_FRESHNESS = 30  # seconds
    corename_ts   = _get_mtime_ns('/tmp/CORENAME') / 1e9
    activegame_ts = _get_mtime_ns('/tmp/ACTIVEGAME') / 1e9
    fileselect_ts = _get_mtime_ns('/tmp/FILESELECT') / 1e9
    # 'selected' is testimony about the CURRENT launch only while it is not
    # staler than the freshest tracker write (see _SELECTED_STALENESS_MARGIN_S)
    # AND while CURRENTPATH was rewritten with it: menu.cpp writes both in the
    # same event, so a lone 'selected' is a core load refreshing the file's
    # mtime over the content — and the path — of an older launch.
    fileselect_paired = abs(fileselect_ts - cp_ns / 1e9) <= _SELECTED_PAIRING_S
    fileselect_fresh = (fileselect == 'selected' and fileselect_paired and
                        fileselect_ts >= activegame_ts
                        - _SELECTED_STALENESS_MARGIN_S)
    startpath_ts  = _get_mtime_ns('/tmp/STARTPATH') / 1e9

    activegame_arcade_fresh = (
        activegame and
        '/_Arcade/' in activegame and
        activegame_ts >= corename_ts - ARCADE_FRESHNESS
    )

    # STARTPATH points at the launched .mra for arcade cores, and the .mra
    # extension is arcade-exclusive, so this also catches arcades started from
    # _@Favorites or custom folders. Freshness is checked against CORENAME so a
    # stale STARTPATH cannot misclassify a console game loaded afterwards.
    startpath = ''
    try:
        with open('/tmp/STARTPATH', 'r') as f:
            startpath = f.read().strip()
    except Exception:
        pass

    startpath_is_mra = startpath.lower().endswith('.mra')
    startpath_arcade_fresh = (
        startpath_is_mra and
        startpath_ts >= corename_ts - ARCADE_FRESHNESS
    )

    # Large MRAs can take longer than ARCADE_FRESHNESS to write CORENAME, which
    # drops a launch that is perfectly real. The .mra's own <setname> settles it
    # without reopening the window the freshness gate exists to close.
    if startpath_is_mra and not startpath_arcade_fresh:
        if _mra_confirms_corename(startpath, corename):
            startpath_arcade_fresh = True
            print(f"\U0001f579\ufe0f .mra setname matches CORENAME '{corename}' "
                  f"(core took {corename_ts - startpath_ts:.1f}s > "
                  f"{ARCADE_FRESHNESS}s freshness) - accepting launch")

    is_arcade = False
    game_name = ''
    game_path = ''

    if activegame_arcade_fresh:
        # Arcade launched via Remote — use ACTIVEGAME
        is_arcade = True
        game_name = _game_name_from_path(activegame)
        game_path = activegame
        print(f"🕹️ Arcade (Remote launch): {game_name}")

    elif startpath_arcade_fresh:
        # Arcade launched via OSD, detected by the .mra in STARTPATH: works
        # regardless of the launch folder (_Arcade, _@Favorites, …).
        is_arcade = True
        game_name = _game_name_from_path(startpath)
        game_path = startpath
        print(f"🕹️ Arcade (OSD .mra launch): {game_name}")

    elif fullpath and 'arcade' in fullpath.lower() and not _is_known_non_arcade(corename):
        # Arcade launched via OSD (legacy path-based detection, kept as fallback)
        is_arcade = True
        game_name = _game_name_from_path(currentpath)
        game_path = currentpath
        print(f"🕹️ Arcade (OSD launch): {game_name}")

    else:
        # Non-arcade — prefer ACTIVEGAME, fall back to CURRENTPATH

        cp_ext = os.path.splitext(currentpath)[1].lower() if currentpath else ''
        currentpath_is_core_name = (
            currentpath and
            cp_ext not in _KNOWN_ROM_EXTS and
            (
                currentpath.lower() in KNOWN_SYSTEM_NAMES or
                (
                    '(' not in currentpath and
                    (
                        currentpath == '..' or
                        currentpath.startswith('_@') or
                        currentpath.lower() == corename.lower() or
                        currentpath.lower() == friendly_name.lower() or
                        currentpath.lower().replace(' ', '').replace('/', '') == corename.lower() or
                        currentpath.lower() in friendly_name.lower() or
                        friendly_name.lower().endswith(currentpath.lower()) or
                        corename.lower() in currentpath.lower().replace(' ', '').replace('+', '')
                    )
                )
            )
        )


        # --- FILESELECT='selected': Main_MiSTer's own launch witness ---------
        # Every menu.cpp path that writes 'selected' writes CURRENTPATH in the
        # SAME event, so while FILESELECT reads it CURRENTPATH is first-hand
        # testimony of the launched item and needs no tracker at all. Resolved
        # up front so the chain below can still fall through to ACTIVEGAME when
        # nothing here matches.
        base = fullpath.rstrip('/') if fullpath else ''
        if currentpath and base and not base.endswith(currentpath):
            cp_composed = base + '/' + currentpath        # browser: dir + item
        else:
            cp_composed = base or currentpath             # MGL: already the file

        # System-path verdicts shared by every branch below: a script, filter,
        # gamma or cheat selection leaves these breadcrumbs and is never a game,
        # not from the browser files and not from a mirrored ACTIVEGAME.
        cp_is_system        = _is_system_path(cp_composed)
        activegame_is_system = _is_system_path(activegame)

        # A directory is a location, not a game identity: trackers leave the
        # browsed FOLDER here and it would displace the game committed a moment
        # earlier. Folder values may still establish identity on a NEW core, and
        # confirmed NeoGeo romset folders stay first-class.
        ag_probe = ((activegame if activegame.startswith('/')
                     else os.path.join('/media/fat', activegame))
                    if activegame else '')
        # Zip-shaped variant: browsing INSIDE a pack zip leaves
        # 'games/<System>/a.zip/a' here, which isdir() cannot see,
        # so its basename was minted as the game name. The central
        # directory settles it. Zip-ROOT mirrors (empty internal)
        # are left alone: a single-game zip launched via ACTIVEGAME
        # is legitimate.
        ag_zip_rel, ag_zip_internal = _zip_split(activegame)
        ag_zip_is_folder = False
        if ag_zip_rel and ag_zip_internal:
            _ag_zip_abs = (ag_zip_rel if ag_zip_rel.startswith('/')
                           else os.path.join('/media/fat', ag_zip_rel))
            ag_zip_is_folder = _zip_internal_is_folder(_ag_zip_abs,
                                                       ag_zip_internal)
        activegame_is_folder = (bool(activegame) and not activegame_is_system
                                and (os.path.isdir(ag_probe)
                                     or ag_zip_is_folder)
                                and not _neogeo_romset_dir(ag_probe, corename))

        # Same verdict for CURRENTPATH: browsing into a game folder leaves the
        # FOLDER here, and the fallback at the end of the chain minted it as a
        # game (browsing games/NeoGeoPocket committed a game of that name).
        # Being a directory is the only reliable witness — the core-name test
        # above matches neither folder nor core.
        cp_probe = ((cp_composed if cp_composed.startswith('/')
                     else os.path.join('/media/fat', cp_composed))
                    if cp_composed else '')
        cp_zip_rel, cp_zip_internal = _zip_split(cp_composed)
        cp_zip_is_folder = False
        if cp_zip_rel and cp_zip_internal:
            _cp_zip_abs = (cp_zip_rel if cp_zip_rel.startswith('/')
                           else os.path.join('/media/fat', cp_zip_rel))
            cp_zip_is_folder = _zip_internal_is_folder(_cp_zip_abs,
                                                       cp_zip_internal)
        cp_is_folder = (bool(cp_composed) and not cp_is_system
                        and (os.path.isdir(cp_probe) or cp_zip_is_folder)
                        and not _neogeo_romset_dir(cp_probe, corename))

        selected_launch = None            # (game_name, game_path) or None
        if (fileselect_fresh and currentpath
                and not currentpath_is_core_name):
            candidate = cp_composed
            if cp_is_system:
                # 'selected' also fires for scripts, filters, gamma tables,
                # shadow masks, docs and SoundFonts — same browser, same hook.
                print(f"🛡️ FILESELECT=selected on a system path — "
                      f"not a game: {candidate}")
            elif cp_ext in _KNOWN_ROM_EXTS:
                # Plain file launch — the common case (unchanged from v2).
                selected_launch = (_game_name_from_path(currentpath), candidate)
                print(f"🎯 Launch via FILESELECT=selected: {selected_launch[0]}")
            else:
                probe = candidate if candidate.startswith('/') \
                        else os.path.join('/media/fat', candidate)
                if os.path.isdir(probe):
                    # Enter pressed ON a folder. CD cores auto-select when the
                    # folder holds exactly one image matching their extension
                    # filter, and launch with CURRENTPATH still holding the
                    # FOLDER name. Resolve the image here so game_path names a
                    # real file. A NeoGeo romset folder has no disc
                    # inside and is kept as the folder itself.
                    disc = ''
                    try:
                        entries = sorted(os.listdir(probe))
                    except Exception:
                        entries = []
                    for ext in ('.chd', '.cue', '.iso', '.pbp'):
                        m = [f for f in entries if f.lower().endswith(ext)]
                        if m:
                            disc = candidate.rstrip('/') + '/' + m[0]
                            break
                    selected_launch = (_game_name_from_path(currentpath),
                                       disc or candidate)
                    print(f"🎯 Folder launch via FILESELECT=selected: "
                          f"{selected_launch[0]}"
                          + (f" -> {os.path.basename(disc)}" if disc else ""))
                elif corename.lower() in _NEOGEO_CORENAMES:
                    # NeoGeo romset via OSD: CURRENTPATH carries the display
                    # TITLE from romsets.xml, not the id on disk, so the
                    # composed path does not exist. Kept verbatim — it can
                    # legally contain '/' — because it is what the panel shows
                    # and what ScreenScraper searches on; rom_details resolves
                    # the real file later.
                    selected_launch = (currentpath.strip(), candidate)
                    print(f"🎯 NeoGeo title via FILESELECT=selected: "
                          f"{currentpath}")
                elif _zip_split(candidate)[0]:
                    # ZIP virtual path: the browser is INSIDE a pack
                    # zip (games/<System>/a.zip/a/<title>), which
                    # neither the extension test nor isdir() can see.
                    # The zip's central directory settles it, with the
                    # same stem tolerance as rom-details, and
                    # game_path lands on the REAL member.
                    zip_rel, zip_internal = _zip_split(candidate)
                    zip_abs = (zip_rel if zip_rel.startswith('/')
                               else os.path.join('/media/fat', zip_rel))
                    member = _zip_member_match(zip_abs, zip_internal)
                    if member:
                        selected_launch = (_game_name_from_path(currentpath),
                                           zip_rel + '/' + member)
                        print(f"🎯 ZIP launch via FILESELECT=selected: "
                              f"{selected_launch[0]} -> "
                              f"{os.path.basename(member)}")
                    else:
                        print(f"🔍 FILESELECT=selected inside a zip but no "
                              f"member matches: '{candidate}' — falling back")
                # Anything else: leave selected_launch empty and let the
                # ACTIVEGAME / CURRENTPATH fallbacks below decide, as before.

        if currentpath_is_core_name:
            # Core loaded without a game — clear game state. BUT a selector
            # confirm can masquerade as this: a preset whose name contains the
            # core name leaves the same breadcrumbs with no core load behind
            # them. A real core load
            # always rewrites STARTPATH, so when that witness is absent, the
            # core is unchanged and a game is established, the running game is
            # kept instead of wiped.
            core_load_witness = (core_changed or
                                 (time.time() - startpath_ts) <= 15.0)
            prev_game, prev_path = '', ''
            if not core_load_witness:
                with _state_lock:
                    prev_game = _state['game']
                    prev_path = _state['game_path']
            if not core_load_witness and prev_game:
                game_name, game_path = prev_game, prev_path
                print("🛡️ Core-name lookalike from a selector — keeping current game")
            else:
                game_name = ''
                game_path = ''
                print(f"🎮 Non-arcade: core={corename} loaded without game (CURRENTPATH='{currentpath}')")
        # A launch witnessed by Main_MiSTer outranks every tracker: some mirror
        # FULLPATH — the FOLDER — into ACTIVEGAME, and then every game in one
        # folder looks identical. Resolution lives in the selected_launch block.
        elif selected_launch:
            game_name, game_path = selected_launch

        # ACTIVEGAME freshness gate (mirror of the arcade branch): a stale
        # ACTIVEGAME surviving a later core-only load must not be paired with the
        # new core. 30 s covers launchers that announce the game seconds BEFORE
        # the core lands, and slow core loads.
        elif (activegame and not activegame.lower().endswith('.ini') and
              not activegame_is_system and
              not (activegame_is_folder and not core_changed) and
              activegame_ts >= corename_ts - 30):
            game_name = _game_name_from_path(activegame)
            game_path = activegame
            # NeoGeo romset-folder layout: ACTIVEGAME carries the romset id
            # while CURRENTPATH carries the title the core resolved from
            # romsets.xml. Show the title (also what ScreenScraper searches on);
            # the path stays on ACTIVEGAME, which is what exists on disk.
            if (currentpath and currentpath != game_name and
                    os.path.splitext(currentpath)[1].lower()
                    not in _KNOWN_ROM_EXTS and
                    _neogeo_romset_label(_resolve_neogeo_probe(activegame),
                                       corename)):
                print(f"🎯 NeoGeo romset folder: showing title "
                      f"'{currentpath}' instead of romset id '{game_name}'")
                # Used verbatim, NOT through _game_name_from_path(): this is
                # already a bare title and can legally carry a slash.
                game_name = currentpath.strip()
        # Folder gate mirrors the ACTIVEGAME branch, core_changed clause
        # included: on a genuinely NEW core a folder may still establish
        # identity, during plain browsing of an unchanged core it never may.
        elif (currentpath and not currentpath.lower().endswith('.ini')
              and not cp_is_system
              and not (cp_is_folder and not core_changed)):
            game_name = _game_name_from_path(currentpath)
            game_path = cp_composed
        else:
            game_path = _scratch_mgl_game(corename_ts)
            game_name = _game_name_from_path(game_path)
            if game_name:
                print(f"🔗 Scratch MGL is the only witness: '{game_path}'")

        # Every source rejected as a system path or as a folder leaves
        # game_name empty, but on a genuinely new core that emptiness is the
        # truth, while on an unchanged core (a script or cheat picked during
        # play, or the game folder a folder launch leaves in CURRENTPATH once
        # the OSD rewrites FILESELECT) blanking would wipe the panel
        # mid-session — so the current identity is re-asserted instead.
        if (not game_name and not currentpath_is_core_name
                and (activegame_is_system or cp_is_system
                     or activegame_is_folder or cp_is_folder)
                and not core_changed):
            with _state_lock:
                game_name = _state['game']
                game_path = _state['game_path']
            if game_name:
                print("🛡️ Only system paths or folders on offer — "
                      "keeping current game")

        # NeoGeo: whichever source won, an id on the panel means no browser
        # supplied the title. romsets.xml has it.
        if game_name and game_path:
            romset = _neogeo_romset_label(_resolve_neogeo_probe(game_path),
                                          corename)
            if romset and game_name.strip().lower() == romset:
                title = _neogeo_romset_title(_neogeo_games_dir(game_path),
                                             romset)
                if title:
                    print(f"🎯 NeoGeo title from romsets.xml: "
                          f"'{title}' for romset '{romset}'")
                    game_name = title

        print(f"🎮 Non-arcade: core={corename} game={game_name}")

    # One core, two consoles. NOT the backwards-compatible case below: see
    # _neogeo_cart_or_cd() for why the CD side changes the reported core.
    if not is_arcade and friendly_name == 'Neo-Geo' and game_path:
        friendly_name = _neogeo_cart_or_cd(game_path)

    # Backwards-compatible cores run software older than themselves (a 2600
    # cartridge in the Atari 7800 core, a Master System one in the MegaDrive).
    # The CORE NAME stays what is actually loaded, so the panel reads like the
    # hardware on the desk; the game's real system travels in its own field for
    # the one consumer that must key off the GAME: the RetroAchievements console
    # lookup. Artwork does NOT read it — the firmware resolves that in
    # ssSystemForRom().
    game_system = ''
    if not is_arcade:
        # The 2-player Lynx core loads the same .lnx files, so its real system
        # is fixed rather than game-dependent. Feeds the RA console lookup only;
        # artwork is mapped in the firmware. Set unconditionally: the mapping
        # holds even with the core sitting empty in the menu.
        if friendly_name == 'Atari Lynx (2P)':
            game_system = 'Atari Lynx'
        elif game_path:
            if friendly_name == 'Atari 7800':
                game_system = _atari_78_or_26(game_path)
            elif friendly_name == 'Sega Genesis/Mega Drive':
                game_system = _md_or_sms(game_path)
            elif friendly_name == 'Nintendo NES/Famicom':
                game_system = _nes_or_fds(game_path)
            elif friendly_name == 'Super Nintendo/Super Famicom':
                game_system = _snes_or_satellaview(game_path)
        if game_system == friendly_name:
            game_system = ''      # the game belongs to its own core: nothing to say

    # Arcade is excluded on purpose: those cores are addressed by .mra and are
    # deliberately absent from CORE_NAME_MAPPING, so logging them would bury the
    # real finds under 160 false positives.
    if not is_arcade:
        _note_unknown_core(lookup_name)

    # Arcade keeps its raw name too (e.g. 'jtcps1'): the firmware finds it
    # unmapped and falls back to the friendly 'Arcade' -> 75, but the raw stays
    # observable for diagnostics.
    _commit_state('Arcade' if is_arcade else friendly_name,
                  game_name, game_path, is_arcade,
                  event='load' if game_name else 'core',
                  core_raw=corename, game_system=game_system)

_SETTLE_SECONDS      = 0.4   # quiet time after the last event before evaluating
_SAFETY_POLL_SECONDS = 15.0  # idle re-check; heals watcher restarts / lost events

_event_queue = queue.Queue()

def _watcher_thread():
    """
    Runs inotifywait in monitor mode and feeds raw events into _event_queue.
    Restarts automatically if inotifywait dies unexpectedly.
    """
    print("👁️ Watcher thread started")
    while True:
        _ensure_watched_files()
        try:
            proc = subprocess.Popen(
                ['inotifywait', '-m', '-e', 'close_write,create'] + _WATCHED_FILES,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                print(f"📂 inotify event: {line}")
                _event_queue.put(line)
            proc.wait()
            err = (proc.stderr.read() or '').strip()
            if err or proc.returncode not in (0, None):
                print(f"⚠️ inotifywait exited (code={proc.returncode}): {err or 'no stderr'}")
        except Exception as e:
            print(f"⚠️ Watcher thread error: {e}")
        print("🔄 Watcher thread restarting...")
        time.sleep(1)

def _evaluator_thread():
    """
    Consumes events and calls _update_state() exactly once per settled burst, so
    the last event of a burst (the real game load) can never be lost. A
    low-frequency idle poll re-checks FILESELECT and SAM_Games.log, so a missed
    inotify event cannot freeze the state permanently.
    """
    print("🧠 Evaluator thread started")
    pending = False
    last_evaluated_fs_ns  = 0
    last_evaluated_sam_ns = 0
    while True:
        timeout = _SETTLE_SECONDS if pending else _SAFETY_POLL_SECONDS
        try:
            _event_queue.get(timeout=timeout)
            pending = True          # burst open/extended — wait for quiet
            continue
        except queue.Empty:
            pass                    # timeout: burst settled, or idle tick

        if pending:
            pending = False
            _update_state()
            last_evaluated_fs_ns  = _get_mtime_ns('/tmp/FILESELECT')
            last_evaluated_sam_ns = max(_get_mtime_ns('/tmp/SAM_Games.log'), _get_mtime_ns('/tmp/SAM_state'))
        else:
            # Idle safety net: FILESELECT or SAM_Games.log moved but was never
            # evaluated. SAM matters here because a same-core hop touches ONLY
            # the log.
            fs_ns  = _get_mtime_ns('/tmp/FILESELECT')
            sam_ns = max(_get_mtime_ns('/tmp/SAM_Games.log'), _get_mtime_ns('/tmp/SAM_state'))
            if fs_ns > last_evaluated_fs_ns or sam_ns > last_evaluated_sam_ns:
                print("🛟 Safety poll: unevaluated FILESELECT/SAM change — evaluating")
                _update_state()
                last_evaluated_fs_ns  = fs_ns
                last_evaluated_sam_ns = sam_ns

# --- MiSTer Monitor UDP discovery responder -------------------------------
DISCOVERY_PORT    = 51234
DISCOVERY_REQUEST = b"MMON_DISCOVER_V1"
DISCOVERY_REPLY   = b"MMON_SERVER_V1:8081"   # advertise the HTTP port too

def _start_discovery_responder():
    """
    Lets the display find this server with no hardcoded IP: it broadcasts
    DISCOVERY_REQUEST and we reply (unicast) with DISCOVERY_REPLY, whose source
    IP is our address.
    """
    def _run():
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(('', DISCOVERY_PORT))
        except OSError as e:
            print(f"Discovery responder: cannot bind UDP {DISCOVERY_PORT}: {e}")
            return
        print(f"Discovery responder listening on UDP {DISCOVERY_PORT}")
        while True:
            try:
                data, addr = sock.recvfrom(64)
                if data.strip() == DISCOVERY_REQUEST:
                    sock.sendto(DISCOVERY_REPLY, addr)
                    print(f"Discovery: replied to {addr[0]}")
            except Exception as e:
                print(f"Discovery responder error: {e}")
                time.sleep(1)

    threading.Thread(target=_run, daemon=True).start()

def _start_watcher():
    """Starts the watcher (inotify producer) and evaluator (consumer) daemons."""
    threading.Thread(target=_watcher_thread, daemon=True).start()
    threading.Thread(target=_evaluator_thread, daemon=True).start()

# Session tracking — module-level so they persist across handler instances
_session_start   = time.time()
_requests_count  = 0

# Endpoint list shown to a human. The startup banner and the HTML index page
# both read from here, so the two cannot drift apart again — they already had:
# the banner listed the RetroAchievements endpoints, the index page did not.
#
# Inclusion criterion, from send_index_page's own docstring: that page exists so
# a manual connectivity test sees something reassuring. It is a browser landing
# page, not API documentation — so endpoints that need query parameters or
# return machine-only counters stay out (/status/snapshot,
# /status/retroachievements/event, /status/retroachievements/achievements).
PUBLIC_ENDPOINTS = [
    ('/status/core',              'Active core'),
    ('/status/game',              'Active game'),
    ('/status/rom',               'Loaded ROM'),
    ('/status/rom/details',       'ROM details (CRC, hash, path)'),
    ('/status/system',            'CPU, memory, uptime'),
    ('/status/storage',           'SD / USB storage'),
    ('/status/network',           'Network status'),
    ('/status/usb',               'USB devices'),
    ('/status/session',           'Session statistics'),
    ('/status/retroachievements', 'RetroAchievements progress for the active game'),
    ('/status/all',               'All data combined'),
    ('/status/unknown_cores',     'Cores this MiSTer ran that we cannot name'),
    ('/status/error_state',       'Current error state (troubleshooting)'),
    ('/status/version',           'Server version'),
    ('/media/artwork',            'Artwork for the loaded game, from the installed pack'),
]

class MiSTerStatusHandler(BaseHTTPRequestHandler):

    def do_POST(self):
        if urlparse(self.path).path != '/control/sam':
            self.send_error_response(404, 'Endpoint not found')
            return
        if not sam_control.trusted(self.client_address[0]) or self.headers.get('Origin'):
            self.send_error_response(403, 'SAM controls require the trusted local network')
            return
        try:
            if self.headers.get('Transfer-Encoding') or self.headers.get_content_type() != 'application/json':
                raise ValueError('Use application/json with Content-Length')
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= sam_control.MAX_REQUEST:
                raise ValueError('Invalid request size')
            self.connection.settimeout(3)
            def unique(pairs):
                result = {}
                for key, value in pairs:
                    if key in result: raise ValueError('Duplicate JSON key')
                    result[key] = value
                return result
            request = sam_control.validate(json.loads(self.rfile.read(length).decode('utf-8'), object_pairs_hook=unique))
        except NotImplementedError as error:
            self.send_error_response(501, str(error))
            return
        except (ValueError, OSError) as error:
            self.send_error_response(400, str(error))
            return
        try:
            cached = sam_control.journal_lookup(request)
            if cached is not None:
                code, body = cached
            else:
                snapshot = self.get_state_snapshot()
                if not snapshot['sam']['active'] or snapshot['seq'] != request['expected_seq'] or snapshot['game_path'] != request['game_path']:
                    code, body = 409, {'ok': False, 'error': 'Inactive or stale SAM selection'}
                elif request['action'] not in snapshot['sam'].get('controls', []):
                    code, body = 409, {'ok': False, 'error': 'SAM is transitioning or does not support controls in this mode'}
                else:
                    code, body = sam_control.submit(request)
        except (OSError, ValueError, KeyError):
            code, body = 503, {'ok': False, 'error': 'SAM control service unavailable'}
        payload = json.dumps(body).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def _is_ini_file(self, file_path):
        """.ini files are configuration, not games."""
        if not file_path:
            return False

        # Simply check if it's an .ini file
        if file_path.lower().endswith('.ini'):
            filename = os.path.basename(file_path)
            print(f"🚫 Detected .ini configuration file: '{filename}' - ignoring for game detection")
            return True

        return False


    def do_GET(self):
        """Handle GET requests"""
        global _requests_count
        _requests_count += 1
        parsed_path = urlparse(self.path)
        path = parsed_path.path

        # Main endpoints
        if path == '/' or path == '/status':
            self.send_index_page()
        elif path == '/status/core':
            self.send_text_response(self.get_current_core())
        elif path == '/status/game':
            self.send_text_response(self.get_current_game())
        elif path == '/status/rom':
            self.send_text_response(self.get_current_rom())
        elif path == '/status/system':
            self.send_json_response(self.get_system_info())
        elif path == '/status/storage':
            self.send_json_response(self.get_storage_info())
        elif path == '/status/usb':
            self.send_json_response(self.get_usb_info())
        elif path == '/status/network':
            self.send_json_response(self.get_network_stats())
        elif path == '/status/session':
            self.send_json_response(self.get_session_stats())
        elif path == '/status/unknown_cores':
            # Cores this server could not name, to turn a "raw name, no artwork"
            # report into the exact key to add. Local only.
            self.send_json_response(get_unknown_cores())
        elif path == '/status/retroachievements':
            if _RA_AVAILABLE:
                self.send_json_response(get_ra_status(self))
            else:
                self.send_json_response({'enabled': False,
                                         'status': 'module_unavailable',
                                         'timestamp': int(time.time())})
        elif path == '/status/retroachievements/event':
            # ~60-byte payload for the firmware's 5 s micro-poll: the monotonic
            # unlock counter plus the tail flag.
            if _RA_AVAILABLE:
                self.send_json_response(get_ra_event())
            else:
                self.send_json_response({'event_counter': 0,
                                         'status': 'module_unavailable',
                                         'timestamp': int(time.time())})
        elif path == '/status/retroachievements/achievements':
            # Flat paginated trophy list for the firmware subpages. Served
            # from the progress cache — zero extra RA API calls per page.
            if _RA_AVAILABLE:
                from urllib.parse import parse_qs
                q = parse_qs(parsed_path.query)
                ra_page = q.get('page', ['1'])[0]
                ra_per  = q.get('per',  ['6'])[0]
                self.send_json_response(
                    get_ra_achievements(self, ra_page, ra_per))
            else:
                self.send_json_response({'status': 'module_unavailable',
                                         'timestamp': int(time.time())})
        elif path == '/status/rom/details':
            from urllib.parse import parse_qs
            force = parse_qs(parsed_path.query).get('force', ['0'])[0] == '1'
            if force:
                self.send_json_response(self.get_rom_details_forced())
            else:
                self.send_json_response(self.get_rom_details())
        elif path == '/media/artwork':
            # Serves the pack image for the loaded game: the display cannot read
            # the MiSTer's SD, so the bytes have to travel. 404 means "no local
            # image" and the firmware falls back to ScreenScraper.
            self.send_artwork_response()
        elif path == '/status/error_state':
            # NEW ENDPOINT: Return current error state
            global server_error_state, last_valid_core, last_valid_core_timestamp
            self.send_json_response({
                'error_state': server_error_state,
                'has_error': bool(server_error_state),
                'last_valid_core': last_valid_core,
                'last_valid_timestamp': last_valid_core_timestamp,
                'timestamp': int(time.time())
            })
        elif path == '/status/version':
            self.send_json_response({
                'server_version': SERVER_VERSION,
                'timestamp': int(time.time()),
            })
        elif path == '/status/snapshot':
            # Atomic identity snapshot. Optional ?seq=N: if the caller already
            # has the current generation, reply with a tiny body so the ESP32
            # skips re-parsing.
            from urllib.parse import parse_qs
            known_seq = parse_qs(parsed_path.query).get('seq', [None])[0]
            snap = self.get_state_snapshot()
            if known_seq is not None and known_seq == str(snap['seq']):
                self.send_json_response({'seq': snap['seq'], 'unchanged': True,
                                         'sam': snap['sam'], 'timestamp': snap['timestamp']})
            else:
                self.send_json_response(snap)
        elif path == '/status/all':
            status = {
                'core': self.get_current_core(),
                'rom': self.get_current_rom(),
                'game': self.get_current_game(),
                'system': self.get_system_info(),
                'storage': self.get_storage_info(),
                'usb': self.get_usb_info(),
                'network': self.get_network_stats(),
                'session': self.get_session_stats(),
                'error_state': server_error_state,          # NEW
                'has_error': bool(server_error_state),      # NEW
                'last_valid_core': last_valid_core,         # NEW
                'timestamp': int(time.time()),
                'snapshot': self.get_state_snapshot(),   # atomic identity block
            }
            self.send_json_response(status)
        else:
            self.send_error_response(404, 'Endpoint not found')

    # ========== OPTIMIZED CORE FUNCTIONS ==========

    def get_current_core(self):
        """Returns the currently active core friendly name from centralized state."""
        with _state_lock:
            return _state['core']

    def get_game_system(self):
        """The system the loaded GAME belongs to: the running core in every
        ordinary case, its predecessor when a backwards-compatible core opened
        something older. Everything that describes what is on screen keeps using
        get_current_core()."""
        with _state_lock:
            return _state['game_system'] or _state['core']

    def get_state_snapshot(self):
        """
        Single-lock atomic snapshot of the core/game identity — what the firmware
        polls. rom_details is the CACHED value only; computation stays on
        /status/rom/details, which can take minutes for large CHDs.
        """
        sam = read_sam_status()
        control = sam_control.advertised()
        sam.update(control)
        if not sam['active']:
            sam.update(controls=[], paused=False)
            sam.pop('remaining_seconds', None)
        if sam['active'] and sam.get('paused'):
            sam['next_game_at'] = None
        with _state_lock:
            return {
                'seq':               _state['seq'],
                'server_version':    SERVER_VERSION,
                'core':              _state['core'],
                'core_raw':          _state['core_raw'],
                'system_name':       _state['system_name'],
                'game_system':       _state['game_system'],
                'game':              _state['game'],
                'game_path':         _state['game_path'],
                'is_arcade':         _state['is_arcade'],
                'rom_details_stale': _state['rom_details_stale'],
                'rom_details':       _state['rom_details'],
                'last_event':        _state['last_event'],
                'updated_at':        _state['updated_at'],
                'timestamp':         int(time.time()),
                'sam':               sam,
            }

    def resolve_zip_path(self, zip_path):
        """ZIP path resolution, handling relative paths from MiSTer."""
        if not zip_path:
            return None

        print(f"🔍 Resolving ZIP path: {zip_path}")

        # If already absolute and exists, return as-is
        if os.path.isabs(zip_path) and os.path.exists(zip_path):
            print(f"✅ ZIP found (absolute): {zip_path}")
            return zip_path

        # Common MiSTer root directories to try
        possible_roots = [
            "/media/fat",           # Standard MiSTer location
            "/tmp",                 # Current working directory
            "/",                    # Root filesystem
            "/opt/MiSTer",         # Alternative installation
            os.getcwd(),           # Current Python script directory
        ]

        # Clean up the relative path
        clean_path = zip_path
        if clean_path.startswith("../../../"):
            # Remove leading ../../../ which typically points to /media/fat from /tmp
            clean_path = clean_path.replace("../../../", "")
        elif clean_path.startswith("../../"):
            clean_path = clean_path.replace("../../", "")
        elif clean_path.startswith("../"):
            clean_path = clean_path.replace("../", "")

        print(f"🧹 Cleaned path: {clean_path}")

        # Try each possible root directory
        for root in possible_roots:
            candidate_path = os.path.join(root, clean_path)
            normalized_path = os.path.normpath(candidate_path)

            print(f"🔍 Trying: {normalized_path}")

            if os.path.exists(normalized_path):
                print(f"✅ ZIP found at: {normalized_path}")
                return normalized_path

        # If direct resolution fails, try to find the file by searching
        filename = os.path.basename(zip_path)
        print(f"🔍 Searching for ZIP filename: {filename}")

        # Search in common game directories (limited depth for performance)
        search_dirs = [
            "/media/fat/games",
            "/media/fat",
            "/tmp",
        ]

        for search_dir in search_dirs:
            if os.path.exists(search_dir):
                try:
                    print(f"🔍 Searching in: {search_dir}")
                    for root, dirs, files in os.walk(search_dir):
                        if filename in files:
                            found_path = os.path.join(root, filename)
                            print(f"✅ ZIP found by search: {found_path}")
                            return found_path

                        # Limit search depth to avoid performance issues
                        if root.count(os.sep) - search_dir.count(os.sep) >= 3:
                            dirs.clear()

                except Exception as e:
                    print(f"⚠️ Search error in {search_dir}: {e}")
                    continue

        print(f"❌ ZIP file not found: {zip_path}")
        return None

    def get_current_game(self):
        """Returns the currently active game name from centralized state."""
        with _state_lock:
            return _state['game']

    # ========== HELPER FUNCTIONS ==========

    def extract_game_name(self, game_path, preserve_parentheses=True):
        """Game name from a path (parentheses preserved for non-arcade)."""
        if not game_path:
            return ""

        # Extraer nombre base del archivo
        base_name = os.path.splitext(os.path.basename(game_path))[0]

        if preserve_parentheses:
            # For non-arcade games: preserve parentheses (full name)
            return base_name.strip()
        else:
            # For arcade: clean parentheses if needed
            clean_name = re.sub(r'\s*\([^)]*\)', '', base_name).strip()
            return clean_name

    def _is_activegame_current(self, corename, activegame):
        """True when ACTIVEGAME is current for the given core."""
        try:
            # Step 1: Check timestamp (basic validation)
            activegame_stat = os.path.getmtime('/tmp/ACTIVEGAME')
            age = time.time() - activegame_stat

            # If file is very old (more than 5 minutes), probably not current
            if age > 300:  # 5 minutes
                print(f"❌ ACTIVEGAME too old: {age:.1f}s > 300s")
                return False

            # Step 2: Check path consistency with core type
            if not corename or not activegame:
                print(f"❌ Missing corename or activegame")
                return False

            # Step 3: For known non-arcade systems, ACTIVEGAME should NOT be in _Arcade
            if _is_known_non_arcade(corename):
                if "/_Arcade/" in activegame:
                    print(f"❌ Non-arcade core '{corename}' but ACTIVEGAME is in _Arcade: {activegame}")
                    return False
                else:
                    print(f"✅ Non-arcade core '{corename}' with consistent ACTIVEGAME")
                    return True

            # Step 4: For potential arcade systems, check FULLPATH consistency
            try:
                with open('/tmp/FULLPATH', 'r') as f:
                    fullpath = f.read().strip()

                # If FULLPATH indicates arcade but ACTIVEGAME is not in _Arcade
                if ("arcade" in fullpath.lower() or "_Arcade" in fullpath):
                    if "/_Arcade/" not in activegame:
                        print(f"❌ FULLPATH indicates arcade but ACTIVEGAME not in _Arcade")
                        return False
                    else:
                        print(f"✅ Arcade context with consistent ACTIVEGAME")
                        return True
                else:
                    # FULLPATH doesn't indicate arcade, ACTIVEGAME should not be in _Arcade
                    if "/_Arcade/" in activegame:
                        print(f"❌ FULLPATH doesn't indicate arcade but ACTIVEGAME is in _Arcade")
                        return False
                    else:
                        print(f"✅ Non-arcade context with consistent ACTIVEGAME")
                        return True

            except Exception as e:
                print(f"⚠️ Error reading FULLPATH: {e}")
                # If we can't read FULLPATH, fall back to basic validation
                print(f"✅ FULLPATH unavailable, accepting ACTIVEGAME based on timestamp only")
                return True

        except Exception as e:
            print(f"❌ Error in _is_activegame_current: {e}")
            return False

    # ========== ORIGINAL FUNCTIONS (NO CHANGES) ==========

    def get_current_rom(self):
        """Current ROM filename from centralized state."""
        with _state_lock:
            game_path = _state['game_path']
            game_name = _state['game']
        if game_path:
            return os.path.basename(game_path)
        if game_name:
            return game_name
        return "No ROM"

    def get_system_info(self):
        """System information (without temperature)."""
        info = {
            'cpu_usage': 0.0,
            'memory_usage': 0.0,
            'uptime_seconds': 0,
            'load_average': [0.0, 0.0, 0.0]
        }

        # Load average
        try:
            with open('/proc/loadavg', 'r') as f:
                loads = f.read().strip().split()
                info['load_average'] = [float(loads[0]), float(loads[1]), float(loads[2])]
                load_1min = float(loads[0])
                info['cpu_usage'] = round(min(load_1min * 50, 100.0), 1)
        except:
            pass

        # Memory
        try:
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
                mem_total = int(re.search(r'MemTotal:\s+(\d+)', meminfo).group(1))
                mem_available = int(re.search(r'MemAvailable:\s+(\d+)', meminfo).group(1))
                info['memory_usage'] = round((1 - mem_available / mem_total) * 100, 1)
        except:
            pass

        # Uptime
        try:
            with open('/proc/uptime', 'r') as f:
                uptime = float(f.read().split()[0])
                info['uptime_seconds'] = int(uptime)
        except:
            pass

        return info

    def get_storage_info(self):
        """Storage information."""
        storage = {
            'sd_card': {'total_gb': 0, 'used_gb': 0, 'free_gb': 0, 'usage_percent': 0},
            'usb_drives': []
        }

        try:
            # SD card (/media/fat)
            if os.path.exists('/media/fat'):
                stat = shutil.disk_usage('/media/fat')
                total = stat.total / (1024**3)
                free = stat.free / (1024**3)
                used = total - free
                usage_percent = (used / total) * 100 if total > 0 else 0

                storage['sd_card'] = {
                    'total_gb': round(total, 1),
                    'used_gb': round(used, 1),
                    'free_gb': round(free, 1),
                    'usage_percent': round(usage_percent, 1)
                }
        except:
            pass

        return storage

    def get_usb_info(self):
        """USB device information."""
        usb_info = {
            'devices': [],
            'serial_ports': [],
            'ports_used': 0,
            'ports_total': 4
        }

        try:
            # USB devices via lsusb
            result = subprocess.run(['lsusb'], capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                for line in lines:
                    if line.strip():
                        match = re.match(r'Bus (\d+) Device (\d+): ID ([0-9a-f:]+) (.+)', line)
                        if match:
                            bus, device, usb_id, name = match.groups()
                            usb_info['devices'].append({
                                'bus': int(bus),
                                'device': int(device),
                                'id': usb_id,
                                'name': name.strip()
                            })

                usb_info['ports_used'] = len([d for d in usb_info['devices'] if 'hub' not in d['name'].lower()])
        except:
            pass

        return usb_info

    def get_network_stats(self):
        """Network statistics."""
        stats = {
            'connected': False,
            'interface': '',
            'ip_address': '',
            'rx_kbps': 0.0,
            'tx_kbps': 0.0,
            'rx_bytes': 0,
            'tx_bytes': 0
        }

        try:
            # Active network interface
            result = subprocess.run(['ip', 'route', 'get', '8.8.8.8'],
                                  capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                match = re.search(r'dev (\w+)', result.stdout)
                if match:
                    interface = match.group(1)
                    stats['interface'] = interface

                    # Interface IP
                    ip_result = subprocess.run(['ip', 'addr', 'show', interface],
                                             capture_output=True, text=True, timeout=3)
                    if ip_result.returncode == 0:
                        ip_match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', ip_result.stdout)
                        if ip_match:
                            stats['ip_address'] = ip_match.group(1)
                            stats['connected'] = True
        except:
            pass

        return stats

    def get_session_stats(self):
        """Session statistics."""
        current_time = time.time()
        session_duration = current_time - _session_start

        stats = {
            'session_start_time': int(_session_start),
            'session_duration_seconds': int(session_duration),
            'session_duration_formatted': self.format_duration(session_duration),
            'requests_count': _requests_count,
            'requests_per_minute': round((_requests_count / (session_duration / 60)) if session_duration > 0 else 0, 2),
            'current_time': int(current_time)
        }

        return stats

    def format_duration(self, seconds):
        """Formats a duration as readable text."""
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)

        if hours > 0:
            return f"{hours}h {minutes}m {secs}s"
        elif minutes > 0:
            return f"{minutes}m {secs}s"
        else:
            return f"{secs}s"

    # ========== ROM DETAILS WITH ZIP SUPPORT ==========

    def is_zip_path(self, path):
        """Checks whether the path contains a ZIP file.
        Returns (is_zip, zip_path, internal_path)."""
        if not path:
            return False, None, None

        # Look for .zip in the path (case insensitive)
        zip_match = re.search(r'(.+\.zip)', path, re.IGNORECASE)
        if zip_match:
            zip_path = zip_match.group(1)
            # Get the part after the ZIP file
            internal_path = path[len(zip_path):].lstrip('/')
            return True, zip_path, internal_path

        return False, None, None

    def get_zip_file_info_enhanced(self, zip_path, internal_path):
        """File info from inside a ZIP, using several search strategies.
        Returns (filename, file_size, crc32_int); the CRC comes straight from the
        ZIP central directory (ZipInfo.CRC), with no decompression."""
        try:
            with zipfile.ZipFile(zip_path, 'r') as zip_file:
                zip_files = zip_file.namelist()

                # Try multiple search strategies
                search_paths = [
                    internal_path,
                    internal_path.replace('\\', '/'),
                    internal_path.replace('/', '\\'),
                    internal_path.replace('\\', '/').lstrip('/'),
                    internal_path.replace('/', '\\').lstrip('\\')
                ]

                for search_path in search_paths:
                    if search_path in zip_files:
                        info = zip_file.getinfo(search_path)
                        filename = os.path.basename(search_path)
                        print(f"✅ File info found: {filename} ({info.file_size:,} bytes)")
                        return filename, info.file_size, info.CRC

                # Case-insensitive search
                internal_lower = internal_path.lower()
                for zip_file_path in zip_files:
                    if zip_file_path.lower() == internal_lower:
                        info = zip_file.getinfo(zip_file_path)
                        filename = os.path.basename(zip_file_path)
                        print(f"✅ File info (case-insensitive): {filename} ({info.file_size:,} bytes)")
                        return filename, info.file_size, info.CRC

                # Filename-only search
                target_filename = os.path.basename(internal_path).lower()
                for zip_file_path in zip_files:
                    if os.path.basename(zip_file_path).lower() == target_filename:
                        info = zip_file.getinfo(zip_file_path)
                        filename = os.path.basename(zip_file_path)
                        print(f"✅ File info (filename): {filename} ({info.file_size:,} bytes)")
                        return filename, info.file_size, info.CRC

                # Strategy 5: stem match, for cores that write the filename
                # without extension to CURRENTPATH.
                target_stem = os.path.splitext(internal_path)[0].lower()
                stem_matches = []
                for zip_file_path in zip_files:
                    zip_stem = os.path.splitext(zip_file_path)[0].lower()
                    if zip_stem == target_stem:
                        stem_matches.append(zip_file_path)

                if stem_matches:
                    rom_match = next(
                        (m for m in stem_matches
                         if os.path.splitext(m)[1].lower() in _KNOWN_ROM_EXTS),
                        None
                    )
                    chosen = rom_match if rom_match else stem_matches[0]
                    info = zip_file.getinfo(chosen)
                    filename = os.path.basename(chosen)
                    print(f"✅ File info (stem match): {filename} ({info.file_size:,} bytes)")
                    if len(stem_matches) > 1:
                        print(f"   ℹ️ {len(stem_matches)} candidates with same stem; chose ROM-ext match")
                    return filename, info.file_size, info.CRC

                print(f"❌ File info not found: {internal_path}")
                return None, 0, 0

        except Exception as e:
            print(f"❌ ZIP info error: {e}")
            return None, 0, 0

    def get_rom_details(self):
        """
        ROM details (CRC, hashes, path). Uses _state['rom_details'] as cache,
        refreshed when rom_details_stale is True.
        """
        print(f"[{time.strftime('%H:%M:%S')}] Getting ROM details...")

        with _state_lock:
            stale        = _state['rom_details_stale']
            cached       = _state['rom_details']
            seq_at_start = _state['seq']

        if not stale and cached is not None:
            print("📋 Using cached ROM details")
            return cached

        # Coalesce concurrent requests: a second caller blocks on this lock, then
        # re-checks the cache instead of starting a duplicate hash/CRC.
        with _rom_details_compute_lock:
            with _state_lock:
                stale   = _state['rom_details_stale']
                cached  = _state['rom_details']
            if not stale and cached is not None:
                print("📋 Using cached ROM details (computed by concurrent request)")
                return cached

            print("📄 Computing ROM details...")
            rom_path = self._get_enhanced_rom_path()

            if not rom_path:
                if getattr(self, '_identity_unconfirmed', False):
                    # Every tracker candidate named a DIFFERENT game than the
                    # committed one: the OSD cursor is resting on another title
                    # while the loaded game keeps running. Transient, so it is
                    # reported as its own error and NEVER cached.
                    # detection_method is deliberately NOT 'sam_no_path': that
                    # value sets no_rom_on_disk, which would let this transient
                    # state trigger the firmware's NOT-IN-DATABASE card.
                    result = {
                        "filename": "", "size": 0, "crc32": "", "md5": "", "sha1": "",
                        "path": "", "available": False,
                        "error": "identity_unconfirmed",
                        "detection_method": "identity_unconfirmed",
                        "timestamp": int(time.time())
                    }
                else:
                    result = {
                        "filename": "", "size": 0, "crc32": "", "md5": "", "sha1": "",
                        "path": "", "available": False,
                        "error": "No active ROM found",
                        "detection_method": "none",
                        "timestamp": int(time.time())
                    }
            else:
                is_zip, zip_path, internal_path = self.is_zip_path(rom_path)
                if is_zip:
                    result = self.get_rom_details_from_zip(rom_path, zip_path, internal_path)
                else:
                    result = self.get_rom_details_from_file(rom_path)
                result["detection_method"] = getattr(self, '_last_detection_method', 'unknown')

            _enrich_rom_result(result, getattr(self, '_last_detection_method', None))
            result['seq'] = seq_at_start
            with _state_lock:
                if result.get('error') == 'identity_unconfirmed':
                    # Not cached: the firmware's 10 s recurrent must keep
                    # recomputing until a corroborating witness appears.
                    print("⏳ Identity unconfirmed — result NOT cached (transient; recompute on next request)")
                elif _state['seq'] == seq_at_start:
                    _state['rom_details']       = result
                    _state['rom_details_stale'] = False
                else:
                    print("⚠️ State changed during ROM hashing — result NOT cached (belongs to a previous game)")

            return result

    def get_rom_details_forced(self):
        """
        Forced ROM details: bypasses game-name detection and timestamp checks so
        RESCAN GAME works even when FILESELECT timestamps are stale.
        """
        print("🔄 === FORCED ROM DETAILS (bypass timestamp check) ===")
        try:
            with _state_lock:
                seq_at_start = _state['seq']
            corename = ""
            try:
                with open('/tmp/CORENAME', 'r') as f:
                    corename = f.read().strip()
            except:
                pass

            is_arcade = self._is_arcade_system(corename)
            if is_arcade:
                rom_path = self._get_arcade_rom_path()
            else:
                rom_path = self._get_non_arcade_rom_path()

            if not rom_path:
                return _enrich_rom_result({
                    "filename": "", "size": 0, "crc32": "", "md5": "", "sha1": "",
                    "path": "", "available": False,
                    "error": "Forced scan: no ROM path found via CURRENTPATH/ACTIVEGAME",
                    "detection_method": "forced_none", "timestamp": int(time.time())
                })

            print(f"🔄 Forced path resolved: {rom_path}")
            is_zip, zip_path, internal_path = self.is_zip_path(rom_path)
            if is_zip:
                result = self.get_rom_details_from_zip(rom_path, zip_path, internal_path)
            else:
                result = self.get_rom_details_from_file(rom_path)

            result["detection_method"] = "forced"
            _enrich_rom_result(result, getattr(self, '_last_detection_method', None))
            result['seq'] = seq_at_start
            # Cache for later calls, but only if the active game hasn't changed
            # since hashing started (a slow CHD could attach to another game).
            with _state_lock:
                if _state['seq'] == seq_at_start:
                    _state['rom_details']       = result
                    _state['rom_details_stale'] = False
                else:
                    print("⚠️ State changed during forced ROM hashing — result NOT cached (belongs to a previous game)")
            return result

        except Exception as e:
            import traceback
            traceback.print_exc()
            return _enrich_rom_result({
                "filename": "", "size": 0, "crc32": "", "md5": "", "sha1": "",
                "path": "", "available": False,
                "error": f"Forced scan error: {str(e)}",
                "detection_method": "forced_error", "timestamp": int(time.time())
            })

    def _get_enhanced_rom_path(self):
        """
        ROM path detection: /status/game, then SAM_Games.log if the game matches,
        then CORENAME to pick arcade (STARTPATH) or non-arcade (ACTIVEGAME).
        """
        print("🔍 === ENHANCED ROM PATH DETECTION ===")

        # STEP 1: Get current game from /status/game endpoint
        try:
            current_game = self.get_current_game()
            print(f"📊 Current game from /status/game: '{current_game}'")

            if not current_game or current_game in ["", "Sin juego", "No game"]:
                print("❌ No current game detected")
                self._last_detection_method = "no_game"
                return None

        except Exception as e:
            print(f"❌ Error getting current game: {e}")
            current_game = None

        # STEP 2: Check SAM_Games.log if we have a current game
        if current_game:
            sam_rom_path = self._check_sam_games_log_for_path(current_game)
            if sam_rom_path:
                print(f"✅ Found ROM path in SAM_Games.log: {sam_rom_path}")
                self._last_detection_method = "sam_games_log"
                return sam_rom_path

            # SAM is authoritative. If it drives the state but its log entry has
            # no path on disk (Amiga demos, WHDLoad, some MGL), there is nothing
            # to hash — STOP HERE. Falling through would read /tmp/ACTIVEGAME|
            # CURRENTPATH|FULLPATH, which still hold the last manual OSD session
            # and would hash a stale, unrelated file.
            if _sam_is_current():
                print("⛔ SAM active with no path on disk — not hashing "
                      "stale /tmp/ ROM; deferring to name search")
                self._last_detection_method = "sam_no_path"
                return None

        # STEP 3: Check CORENAME to determine system type
        try:
            with open('/tmp/CORENAME', 'r') as f:
                corename = f.read().strip()
                print(f"📄 CORENAME: '{corename}'")
        except Exception as e:
            print(f"❌ Cannot read CORENAME: {e}")
            corename = ""

        if not corename:
            print("❌ No CORENAME available")
            self._last_detection_method = "no_corename"
            return None

        # STEP 4: Determine if this is an arcade system
        is_arcade = self._is_arcade_system(corename)
        print(f"🎮 System type - Arcade: {is_arcade}")

        if is_arcade:
            # For arcade systems, use STARTPATH
            rom_path = self._get_arcade_rom_path()
            if rom_path:
                self._last_detection_method = "arcade_startpath"
            else:
                self._last_detection_method = "arcade_failed"
        else:
            # For non-arcade systems, use ACTIVEGAME
            rom_path = self._get_non_arcade_rom_path()
            if rom_path:
                self._last_detection_method = "non_arcade_activegame"
            else:
                self._last_detection_method = "non_arcade_failed"

        return rom_path

    def _check_sam_games_log_for_path(self, current_game):
        """Path for the current game from SAM_Games.log, or None."""
        try:
            sam_log_path = '/tmp/SAM_Games.log'

            if not os.path.exists(sam_log_path):
                print(f"📄 SAM_Games.log not found at {sam_log_path}")
                return None

            # Check if file is recent enough (within 5 minutes)
            sam_stat = os.path.getmtime(sam_log_path)
            age = time.time() - sam_stat

            if age > 300:  # 5 minutes
                print(f"📄 SAM_Games.log too old: {age:.1f}s")
                return None

            # Read and parse the log file
            try:
                with open(sam_log_path, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
            except UnicodeDecodeError:
                with open(sam_log_path, 'r', encoding='latin-1') as f:
                    lines = f.readlines()

            if not lines:
                print("📄 SAM_Games.log is empty")
                return None

            # Process lines from last to first to find the most recent matching entry
            for i in range(len(lines) - 1, -1, -1):
                line = lines[i].strip()
                if not line:
                    continue

                # SAM format: "04:17:58 - atarilynx - /media/fat/games/AtariLynx/..."
                parts = line.split(' - ')

                if len(parts) >= 3:
                    sam_field = ' - '.join(parts[2:])  # Rejoin in case the field contains " - "

                    # Extract game name (path or bare name)
                    if sam_field:
                        game_filename = sam_field.split('/')[-1]
                        sam_game = os.path.splitext(game_filename)[0]

                        print(f"🔍 SAM entry - Game: '{sam_game}', Field: '{sam_field}'")

                        # Only return a REAL path: SAM logs some content by name
                        # only, which yields 'ROM file not found' downstream.
                        if self._games_match(current_game, sam_game):
                            if _sam_looks_like_path(sam_field):
                                print(f"✅ Game match with real path in SAM: '{current_game}'")
                                return sam_field
                            print(f"ℹ️ SAM match '{current_game}' has no path on disk — "
                                  f"deferring to name search")
                            return None

            print(f"❌ No matching game found in SAM_Games.log for: '{current_game}'")
            return None

        except Exception as e:
            print(f"❌ Error checking SAM_Games.log: {e}")
            return None

    def _games_match(self, game1, game2):
        """True when two game names match, allowing for naming variations."""
        if not game1 or not game2:
            return False

        # Direct match
        if game1 == game2:
            return True

        # Case insensitive match
        if game1.lower() == game2.lower():
            return True

        # Remove common suffixes/prefixes and compare
        clean1 = re.sub(r'\s*\([^)]*\)', '', game1).strip()
        clean2 = re.sub(r'\s*\([^)]*\)', '', game2).strip()

        if clean1.lower() == clean2.lower():
            return True

        return False

    def _is_arcade_system(self, corename):
        """True when the current core is an arcade system."""
        try:
            current_core = self.get_current_core()
            print(f"🎮 Current core from detection: '{current_core}'")

            # If get_current_core() returns "Arcade", it's arcade
            is_arcade = (current_core.lower() == "arcade")

            print(f"🎮 '{corename}' system type → Arcade: {is_arcade}")
            return is_arcade

        except Exception as e:
            print(f"❌ Error in _is_arcade_system: {e}")
            return False

    def _get_arcade_rom_path(self):
        """ROM path for arcade systems, from STARTPATH."""
        try:
            with open('/tmp/STARTPATH', 'r') as f:
                startpath = f.read().strip()
                print(f"📄 STARTPATH (arcade): '{startpath}'")

                if startpath and os.path.exists(startpath):
                    return startpath
                else:
                    print(f"❌ STARTPATH file does not exist: {startpath}")
                    return None

        except Exception as e:
            print(f"❌ Error reading STARTPATH: {e}")
            return None

    def _get_non_arcade_rom_path(self):
        """
        ROM path for non-arcade systems.

        ACTIVEGAME (when present) always contains the full path and is tried
        first. Otherwise CURRENTPATH holds the selected filename, which may have
        no directory component, and FULLPATH the browser directory, which may
        include a ZIP path. Joining them:

            FULLPATH.rstrip('/') + '/' + CURRENTPATH

        gives the complete virtual path that _resolve_mister_path() and
        is_zip_path() can parse.
        """
        self._identity_unconfirmed = False   # set by the loop tail; read by get_rom_details
        activegame = ""
        activegame_timestamp = 0
        currentpath_timestamp = 0

        try:
            with open('/tmp/ACTIVEGAME', 'r') as f:
                activegame = f.read().strip()
            activegame_timestamp = os.path.getmtime('/tmp/ACTIVEGAME')
        except:
            pass
        activegame = _deref_launcher_mgl(activegame)

        currentpath = ''
        currentpath_timestamp = 0
        fullpath = ''
        path_source = 'CURRENTPATH'
        try:
            with open('/tmp/CURRENTPATH', 'r') as f:
                currentpath = f.read().strip()
            currentpath_timestamp = os.path.getmtime('/tmp/CURRENTPATH')
        except:
            pass
        try:
            with open('/tmp/FULLPATH', 'r') as f:
                fullpath = f.read().strip()
        except:
            pass

        print(f"📄 ACTIVEGAME:       '{activegame}' (ts: {activegame_timestamp})")
        print(f"📄 {path_source}: '{currentpath}' (ts: {currentpath_timestamp})")
        print(f"📄 FULLPATH source:  '{fullpath}'")

        # When CURRENTPATH has no directory component, combine it with FULLPATH.
        if currentpath and not os.path.dirname(currentpath) and fullpath:
            fullpath_dir = fullpath.rstrip('/')
            if os.path.basename(fullpath_dir) == currentpath:
                # MGL/CHD launches: FULLPATH already includes the filename, so
                # joining would duplicate it. Use it as-is.
                print(f"🔗 FULLPATH already ends with CURRENTPATH - using it as-is: '{fullpath_dir}'")
                currentpath = fullpath_dir
            else:
                combined = fullpath_dir + '/' + currentpath
                print(f"🔗 CURRENTPATH has no directory - combining with FULLPATH: '{combined}'")
                currentpath = combined

        # Preferred order: FILESELECT='selected' outranks any mtime. menu.cpp
        # writes it on every real launch together with a CURRENTPATH naming the
        # launched item, while some trackers mirror the FOLDER into ACTIVEGAME a
        # moment later, so 'newest file wins' would hash the same game forever.
        # Without log_file_entry the file never reads it and the timestamp
        # ordering applies exactly as before.
        fileselect_selected = False
        try:
            with open('/tmp/FILESELECT', 'r') as f:
                fileselect_selected = (f.read().strip() == 'selected')
            if fileselect_selected:
                # Same corroboration as _update_state: a leftover 'selected'
                # must not outrank a fresh ACTIVEGAME from an OSD-less launcher,
                # and it only names CURRENTPATH when both were written together.
                fs_ts = os.path.getmtime('/tmp/FILESELECT')
                fileselect_selected = (
                    fs_ts >= activegame_timestamp - _SELECTED_STALENESS_MARGIN_S
                    and abs(fs_ts - currentpath_timestamp) <= _SELECTED_PAIRING_S)
        except Exception:
            fileselect_selected = False

        activegame_is_newer = activegame_timestamp > currentpath_timestamp
        if fileselect_selected:
            sources = [('CURRENTPATH', currentpath), ('ACTIVEGAME', activegame)]
            print("⏱️ Preferred source: CURRENTPATH (FILESELECT=selected)")
        elif activegame_is_newer:
            sources = [('ACTIVEGAME', activegame), ('CURRENTPATH', currentpath)]
            print("⏱️ Preferred source: ACTIVEGAME (newer)")
        else:
            sources = [('CURRENTPATH', currentpath), ('ACTIVEGAME', activegame)]
            print("⏱️ Preferred source: CURRENTPATH (newer)")

        # --- Identity corroboration (rom-details poisoning fix) --------------
        # CURRENTPATH is rewritten by merely RESTING the OSD cursor on a title,
        # so a details request landing then used to hash the highlighted game and
        # cache it under the running one. A candidate that does not NAME the
        # committed game is testimony about the browser and is dropped below.
        #
        # game_path comes from the same commit as the game name, so it is
        # coherent by construction. Appended LAST so every healthy flow keeps
        # the existing source order and the rescue only acts when the trackers
        # fail identity or resolution.
        with _state_lock:
            committed_game      = _state['game']
            committed_game_path = _state['game_path']
        identity_dropped = 0
        identity_passed  = 0   # candidates that survived the filter and
                               # were actually attempted: identity is the
                               # verdict only when this stays zero
        if committed_game and committed_game_path:
            sources.append(('STATE', committed_game_path))

        for source_name, source_path in sources:
            if not source_path:
                print(f"⏭️ {source_name} is empty - skipping")
                continue

            # Safety check: non-arcade path should not point into _Arcade
            if "_Arcade" in source_path:
                print(f"⚠️ {source_name} contains arcade path, skipping: '{source_path}'")
                continue

            # Safety check: scripts, filters, cheats & co. are browser debris
            # (see _is_system_path) — a tracker may have mirrored them here.
            if _is_system_path(source_path):
                print(f"🛡️ {source_name} points into a MiSTer system folder, "
                      f"skipping: '{source_path}'")
                continue

            # Identity guard: tracker testimony must name the committed game.
            # 'STATE' is exempt — it IS the committed identity's own path.
            if (committed_game and source_name != 'STATE'
                    and not _path_names_game(source_path, committed_game)):
                identity_dropped += 1
                print(f"🛡️ {source_name} names a different "
                      f"game than the committed one "
                      f"('{committed_game}') — skipping: "
                      f"'{source_path}'")
                continue

            # Survived the identity filter: from here on, any
            # failure is about the FILE, not about identity.
            identity_passed += 1

            try:
                final_path = self._resolve_mister_path(source_path)
                print(f"🔧 {source_name} resolved to: '{final_path}'")

                is_zip, zip_path, internal_path = self.is_zip_path(final_path)

                if is_zip:
                    print(f"📦 ZIP detected: {zip_path} -> '{internal_path}'")
                    if os.path.exists(zip_path):
                        print(f"✅ ZIP verified via {source_name}: {zip_path}")
                        return final_path
                    else:
                        print(f"❌ ZIP not found via {source_name}: {zip_path} - trying next source")
                        continue
                else:
                    if os.path.isfile(final_path) and _is_sd_root_file(final_path):
                        # A game is never loose in the card's root, where
                        # MiSTer.ini, scripts and readmes live. Reached when a
                        # bare name picks up a ROM extension by accident.
                        print(f"🛡️ {source_name} resolved into the SD root, not a "
                              f"game: {final_path}")
                        continue
                    if os.path.isfile(final_path):
                        print(f"✅ ROM file found via {source_name}: {final_path}")
                        return final_path
                    elif os.path.isdir(final_path):
                        # Folder-per-game layout. os.path.exists() is also true
                        # for directories, so without this branch the server
                        # would try to hash the folder itself (Errno 21).
                        print(f"📁 {source_name} resolved to a directory — searching disc image inside")
                        try:
                            entries = sorted(os.listdir(final_path))
                        except Exception as e:
                            print(f"❌ Cannot list directory: {e}")
                            entries = []
                        for ext in ('.chd', '.cue', '.iso', '.pbp'):
                            matches = [f for f in entries if f.lower().endswith(ext)]
                            if matches:
                                chosen = os.path.join(final_path, matches[0])
                                print(f"✅ Disc image found in folder ({source_name}): {chosen}")
                                return chosen
                        # NeoGeo romset-folder layout: the romset IS the folder,
                        # holding loose ROM parts. Confirmed against romsets.xml.
                        _rs = _neogeo_romset_dir(final_path, _read_corename_raw())
                        if _rs:
                            print(f"✅ NeoGeo romset folder ({source_name}): "
                                  f"{final_path} -> romset '{_rs}'")
                            return final_path
                        print(f"❌ No disc image inside directory: {final_path}")
                        print(f"❌ Direct file not found: {final_path}")
                    else:
                        print(f"❌ Direct file not found: {final_path}")

                        # CD images: some cores (PSX, Saturn) write CURRENTPATH without the
                        # extension. Try common disc-image extensions before giving up.
                        for ext in ('.chd', '.cue', '.iso', '.pbp'):
                            cd_candidate = final_path + ext
                            if os.path.exists(cd_candidate):
                                print(f"✅ CD image found ({source_name}): {cd_candidate}")
                                return cd_candidate

                        # Last resort: same-name ZIP in the same directory
                        # (handles individual per-game ZIPs: game.dsk → game.zip/game.dsk)
                        parent_dir = os.path.dirname(final_path)
                        target_filename = os.path.basename(final_path)
                        base_name = os.path.splitext(target_filename)[0]
                        zip_candidate = os.path.join(parent_dir, base_name + '.zip')
                        print(f"🔍 Trying same-name ZIP: '{zip_candidate}'")
                        if os.path.exists(zip_candidate):
                            virtual_path = zip_candidate + '/' + target_filename
                            print(f"✅ Same-name ZIP found ({source_name}): {virtual_path}")
                            return virtual_path

                        # Title-based fallbacks: some cores (notably NEOGEO) write
                        # the game's display TITLE to CURRENTPATH instead of the
                        # filename on disk.

                        # (a) Directory scan: a file whose name starts with the
                        #     title and has a known ROM extension.
                        try:
                            entries = sorted(os.listdir(parent_dir))
                        except Exception:
                            entries = []
                        title_l = target_filename.lower()
                        for entry in entries:
                            stem, ext = os.path.splitext(entry)
                            if ext.lower() in _KNOWN_ROM_EXTS and stem.lower().startswith(title_l):
                                candidate = os.path.join(parent_dir, entry)
                                if os.path.isfile(candidate):
                                    print(f"✅ Title-prefix match ({source_name}): {candidate}")
                                    return candidate

                        # (b) romsets.xml reverse lookup: display title -> romset
                        #     name -> romset file (NEOGEO layouts).
                        candidate = self._lookup_neogeo_romset(parent_dir, target_filename)
                        if candidate:
                            print(f"✅ romsets.xml match ({source_name}): {candidate}")
                            return candidate
                        print(f"❌ No valid path found via {source_name} - trying next source")
                        continue

            except Exception as e:
                print(f"❌ Error resolving {source_name}: {e} - trying next source")
                continue

        # Identity is the cause ONLY when nothing survived the filter to be
        # tried: the OSD browse folder in ACTIVEGAME is dropped on virtually
        # every launch, so keying on identity_dropped alone reported plain
        # missing-file failures as 'cursor resting on another title'.
        self._identity_unconfirmed = (identity_dropped > 0
                                      and identity_passed == 0)
        if self._identity_unconfirmed:
            print(f"❌ No valid ROM path found: {identity_dropped} candidate(s) named")
            print(f"   a different game than '{committed_game}' — identity unconfirmed")
            print(f"   (transient while the OSD cursor rests on another title)")
        else:
            print(f"❌ No valid ROM path found from any source")
        return None

    def _lookup_neogeo_romset(self, directory, title):
        """
        Reverse lookup in romsets.xml (NEOGEO): display title -> romset name.
        The core writes the TITLE to CURRENTPATH, so the file on disk can have a
        completely different name. Punctuation also differs
        between sources, so titles are compared on alphanumerics only.
        """
        # romsets.xml normally sits at the games/NEOGEO root while the user may
        # be browsing a pack subfolder, so look locally first and then walk up
        # with the same bounded search the id loader uses.
        xml_path = None
        for d in (directory, _neogeo_games_dir(os.path.join(directory, '_'))):
            if not d:
                continue
            for n in _ROMSET_XML_NAMES:
                p = os.path.join(d, n)
                if os.path.isfile(p):
                    xml_path = p
                    break
            if xml_path:
                break
        if not xml_path:
            return None
        try:
            import xml.etree.ElementTree as ET
            root = ET.parse(xml_path).getroot()
        except Exception as e:
            print(f"⚠️ romsets.xml parse failed: {e}")
            return None

        def norm(s):
            return re.sub(r'[^a-z0-9]', '', s.lower())

        wanted = norm(title)
        if not wanted:
            return None
        # Pass 1: exact match on normalized title (altname or romset name).
        # Pass 2: prefix match, which only counts if the file exists on disk;
        # if more than one qualifies we refuse to guess.
        exact_file = None
        prefix_files = []
        for rs in root.iter('romset'):
            name    = rs.get('name') or ''
            altname = rs.get('altname') or ''
            norm_alt  = norm(altname)
            norm_name = norm(name)

            is_exact  = (norm_alt == wanted or norm_name == wanted)
            is_prefix = (not is_exact and
                         (norm_alt.startswith(wanted) or norm_name.startswith(wanted)))
            if not (is_exact or is_prefix):
                continue

            found = None
            for filename in (name + '.neo', name + '.zip'):
                p = os.path.join(directory, filename)
                if os.path.isfile(p):
                    found = p
                    break
            if not found:
                # Romset-folder layout: the folder is named after the id.
                p = os.path.join(directory, name)
                if os.path.isdir(p):
                    found = p
            if not found:
                # Pack layout: readable filename with the id in trailing
                # parentheses ('<Title> (<romset>).neo').
                p = _neogeo_file_with_embedded_id(directory, name)
                if p:
                    print(f"📁 NeoGeo romset '{name}' found via "
                          f"embedded id: {os.path.basename(p)}")
                    found = p

            if is_exact:
                if found:
                    return found
                print(f"ℹ️ romsets.xml maps '{title}' -> '{name}' but no matching file on disk")
                return None
            if found:
                prefix_files.append((name, found))

        if len(prefix_files) == 1:
            print(f"ℹ️ romsets.xml prefix match: '{title}' -> '{prefix_files[0][0]}'")
            return prefix_files[0][1]
        if len(prefix_files) > 1:
            names = ', '.join(n for n, _ in prefix_files)
            print(f"⚠️ romsets.xml: '{title}' is ambiguous ({names}) — not guessing")
        return None

    def _resolve_mister_path(self, path):
        """Resolves MiSTer paths, handling the various relative patterns."""
        if not path:
            return path

        print(f"🔍 Resolving path: '{path}'")

        # Case 1: Already absolute path
        if os.path.isabs(path):
            resolved = os.path.normpath(path)
            print(f"✅ Already absolute: {resolved}")
            return resolved

        # Leading ../ is relative to /media/fat, so '../usb0/...' means
        # /media/usb0/... Without this the generic cleanup would prepend
        # /media/fat and produce /media/fat/fat/..., which does not exist.
        m = re.match(r'(?:\.\./)+((?:usb[0-7]|fat)/.*)$', path)
        if m:
            resolved = os.path.normpath('/media/' + m.group(1))
            print(f"🔧 Relative /media path resolved: {resolved}")
            return resolved

        # Case 2: Starts with ../../../media/fat/ - remove the ../ and normalize
        if path.startswith("../../../media/fat/"):
            # Extract the part after ../../../
            clean_path = path[9:]  # Remove "../../../"
            resolved = os.path.normpath("/" + clean_path)
            print(f"🔧 Cleaned ../../../ pattern: {resolved}")
            return resolved

        # Case 3: Starts with ../../ - try different resolutions
        if path.startswith("../../"):
            # Try removing ../../ and prepending /media/fat/
            clean_path = path[6:]  # Remove "../../"
            if clean_path.startswith("media/fat/"):
                resolved = os.path.normpath("/" + clean_path)
            else:
                resolved = os.path.normpath("/media/fat/" + clean_path)
            print(f"🔧 Cleaned ../../ pattern: {resolved}")
            return resolved

        # Case 4: Starts with ../
        if path.startswith("../"):
            clean_path = path[3:]  # Remove "../"
            if clean_path.startswith("media/fat/"):
                resolved = os.path.normpath("/" + clean_path)
            else:
                resolved = os.path.normpath("/media/fat/" + clean_path)
            print(f"🔧 Cleaned ../ pattern: {resolved}")
            return resolved

        # Case 5: Simple relative path (games/SMS/...)
        if not path.startswith("/"):
            resolved = os.path.normpath("/media/fat/" + path)
            print(f"🔧 Added /media/fat/ prefix: {resolved}")
            return resolved

        # Case 6: Fallback - normalize as-is
        resolved = os.path.normpath(path)
        print(f"🔧 Normalized as-is: {resolved}")
        return resolved

    def get_rom_details_from_file(self, rom_path):
        """ROM details for a regular file (not inside a ZIP)."""
        # Verify file exists
        if not os.path.exists(rom_path):
            print(f"ROM file not found: {rom_path}")
            return {
                "filename": "",
                "size": 0,
                "crc32": "",
                "md5": "",
                "sha1": "",
                "path": rom_path,
                "available": False,
                "error": "ROM file not found or not accessible",
                "timestamp": int(time.time())
            }

        # A romset can be a FOLDER: its identity is the
        # romset name — there is no single file whose bytes could be hashed.
        if os.path.isdir(rom_path):
            print(f"📁 Romset folder — name-based identity, no byte hash: "
                  f"{os.path.basename(rom_path)}")
            return {
                "filename": os.path.basename(rom_path),
                "size": 0,
                "crc32": "",
                "md5": "",
                "sha1": "",
                "path": rom_path,
                "available": True,
                "hash_calculated": False,
                "timestamp": int(time.time())
            }

        try:
            file_size = os.path.getsize(rom_path)
            filename = os.path.basename(rom_path)

            print(f"Processing ROM: {filename} ({file_size:,} bytes)")

            # Calculate hashes (skip only for pathologically large files)
            crc32 = ""
            md5 = ""
            sha1 = ""

            # Size limit so a corrupt or mis-resolved path cannot block the
            # server. 1GB covers any single CD image (a CHD is compressed).
            MAX_SIZE_FOR_HASH = 1024 * 1024 * 1024  # 1GB

            # Mutable containers (.vhd) are never worth hashing: ScreenScraper
            # does not index them and the guest OS rewrites them, so the CRC is
            # unstable by nature. Same outcome as file_too_large.
            _ext      = os.path.splitext(filename)[1].lower()
            _corename = _read_corename_raw()
            skip_hash = (_is_no_hash(_ext, _corename)
                         or bool(_neogeo_romset_dir(rom_path, _corename)))

            if skip_hash:
                _why = ("unindexable, mutable container" if _ext in _NO_HASH_EXTS
                        else f"locally built by the {_corename} collection; CRC in no database")
                print(f"Hash skipped for {filename}: {_why}")
            elif file_size <= MAX_SIZE_FOR_HASH:
                try:
                    _wait_for_rom_load_to_settle()   # don't hash mid-load

                    start_time = time.time()
                    print(f"Calculating hashes for {filename}...")

                    with open(rom_path, 'rb') as f:
                        # Read file in chunks to avoid saturating memory
                        chunk_size = 1024 * 1024  # 1MB chunks
                        crc32_calc = 0
                        md5_calc = hashlib.md5()
                        sha1_calc = hashlib.sha1()

                        bytes_processed = 0
                        while True:
                            chunk = f.read(chunk_size)
                            if not chunk:
                                break

                            # Update all hashes with the same chunk
                            crc32_calc = zlib.crc32(chunk, crc32_calc)
                            md5_calc.update(chunk)
                            sha1_calc.update(chunk)

                            bytes_processed += len(chunk)
                            time.sleep(0.003)   # ~0.3s extra per 100MB hashed

                    # Format results
                    crc32 = format(crc32_calc & 0xffffffff, '08X')
                    md5 = md5_calc.hexdigest().upper()
                    sha1 = sha1_calc.hexdigest().upper()

                    calc_time = time.time() - start_time
                    print(f"Hash calculation completed in {calc_time:.2f}s")
                    print(f"CRC32: {crc32}")
                    print(f"MD5: {md5}")
                    print(f"SHA1: {sha1}")

                except Exception as e:
                    error_msg = f"Hash calculation failed: {str(e)}"
                    print(f"ERROR: {error_msg}")
                    return {
                        "filename": filename,
                        "size": file_size,
                        "crc32": "",
                        "md5": "",
                        "sha1": "",
                        "path": rom_path,
                        "available": True,
                        "hash_calculated": False,
                        "error": error_msg,
                        "timestamp": int(time.time())
                    }
            else:
                print(f"File too large for hash calculation: {file_size:,} bytes > {MAX_SIZE_FOR_HASH:,} bytes")

            # Return successful result
            result = {
                "filename": filename,
                "size": file_size,
                "crc32": crc32,
                "md5": md5,
                "sha1": sha1,
                "path": rom_path,
                "available": True,
                "hash_calculated": len(crc32) > 0,
                "file_too_large": file_size > MAX_SIZE_FOR_HASH,
                "timestamp": int(time.time())
            }

            print(f"ROM details successfully extracted: {filename}")
            return result

        except Exception as e:
            error_msg = f"Error processing file: {str(e)}"
            print(f"ERROR: {error_msg}")
            return {
                "filename": os.path.basename(rom_path),
                "size": 0,
                "crc32": "",
                "md5": "",
                "sha1": "",
                "path": rom_path,
                "available": False,
                "error": error_msg,
                "timestamp": int(time.time())
            }

    def get_rom_details_from_zip(self, full_path, zip_path, internal_path):
        """ROM details for a file inside a ZIP."""
        print(f"\n🔍 === ENHANCED ZIP ROM DETAILS ===")
        print(f"Full path: {full_path}")
        print(f"ZIP path: {zip_path}")
        print(f"Internal path: {internal_path}")

        # Resolve the actual ZIP file location
        resolved_zip_path = self.resolve_zip_path(zip_path)

        if not resolved_zip_path:
            error_msg = f"ZIP file not found: {zip_path}"
            print(f"❌ {error_msg}")

            return {
                "filename": os.path.basename(internal_path) if internal_path else "",
                "size": 0,
                "crc32": "",
                "md5": "",
                "sha1": "",
                "path": full_path,
                "available": False,
                "error": error_msg,
                "zip_path": zip_path,
                "resolved_zip_path": None,
                "internal_path": internal_path,
                "timestamp": int(time.time())
            }

        # Some cores report the archive alone for a single-ROM zip. Resolve it to
        # the sole member so the strategies and the RA layer see a normal member.
        if not internal_path:
            _members, _, _ = _zip_entries(resolved_zip_path)
            if len(_members) == 1:
                internal_path = next(iter(_members.values()))
                print(f"📦 Sole member resolved: {internal_path}")

        try:
            print(f"📂 Opening ZIP: {resolved_zip_path}")

            # Get file info from ZIP with enhanced search
            filename, file_size, zip_crc = self.get_zip_file_info_enhanced(resolved_zip_path, internal_path)

            if not filename:
                # A NeoGeo romset ZIP has no ROM member: the archive IS the
                # romset. Valid, unhashable, identified by its name.
                _rs = _neogeo_romset_dir(resolved_zip_path, _read_corename_raw())
                if _rs:
                    print(f"✅ NeoGeo romset ZIP: "
                          f"{os.path.basename(resolved_zip_path)} -> romset '{_rs}'")
                    return _enrich_rom_result({
                        "filename": os.path.basename(resolved_zip_path),
                        "size": os.path.getsize(resolved_zip_path),
                        "crc32": "", "md5": "", "sha1": "",
                        "path": resolved_zip_path,
                        "available": True,
                        "hash_calculated": False,
                        "file_too_large": False,
                        "zip_path": resolved_zip_path,
                        "resolved_zip_path": resolved_zip_path,
                        "internal_path": "",
                    }, getattr(self, '_last_detection_method', None))

                error_msg = f"File not found inside ZIP: {internal_path}"
                print(f"❌ {error_msg}")

                # List some ZIP contents for debugging
                try:
                    with zipfile.ZipFile(resolved_zip_path, 'r') as zip_file:
                        zip_contents = zip_file.namelist()
                        print(f"📋 ZIP contents (first 5 files):")
                        for i, file_in_zip in enumerate(zip_contents[:5]):
                            print(f"   {i+1}. {file_in_zip}")
                        if len(zip_contents) > 5:
                            print(f"   ... and {len(zip_contents) - 5} more files")
                except Exception as e:
                    print(f"⚠️ Could not list ZIP contents: {e}")

                return {
                    "filename": os.path.basename(internal_path) if internal_path else "",
                    "size": 0,
                    "crc32": "",
                    "md5": "",
                    "sha1": "",
                    "path": full_path,
                    "available": False,
                    "error": error_msg,
                    "zip_path": zip_path,
                    "resolved_zip_path": resolved_zip_path,
                    "internal_path": internal_path,
                    "timestamp": int(time.time())
                }

            print(f"📁 File found in ZIP: {filename} ({file_size:,} bytes)")

            # CRC32 comes straight from the ZIP central directory (ZipInfo.CRC),
            # with no decompression: milliseconds instead of minutes, and no
            # SD/CPU contention with the core load. MD5/SHA1 are not stored
            # there and stay empty; a CRC match is all ScreenScraper needs.
            crc32 = format(zip_crc & 0xffffffff, '08X')
            md5 = ""
            sha1 = ""
            print(f"🔢 CRC32 from ZIP directory: {crc32} (no decompression)")

            # Return successful result
            result = {
                "filename": filename,
                "size": file_size,
                "crc32": crc32,
                "md5": md5,
                "sha1": sha1,
                "path": full_path,
                "available": True,
                "hash_calculated": len(crc32) > 0,
                "file_too_large": False,
                "zip_path": zip_path,
                "resolved_zip_path": resolved_zip_path,
                "internal_path": internal_path,
                "timestamp": int(time.time())
            }

            print(f"✅ ZIP ROM extraction successful!")
            print(f"📊 Result: {filename}, CRC32={crc32}, Size={file_size:,}")
            return result

        except Exception as e:
            error_msg = f"ZIP processing error: {str(e)}"
            print(f"❌ {error_msg}")

            return {
                "filename": os.path.basename(internal_path) if internal_path else "",
                "size": 0,
                "crc32": "",
                "md5": "",
                "sha1": "",
                "path": full_path,
                "available": False,
                "error": error_msg,
                "zip_path": zip_path,
                "resolved_zip_path": resolved_zip_path if 'resolved_zip_path' in locals() else None,
                "internal_path": internal_path,
                "timestamp": int(time.time())
            }

    # ========== HTTP RESPONSE HELPERS ==========

    def _artwork_by_hash(self, seq_at_start):
        """Second attempt at the pack image, using the CRC the state commit did
        not have. Returns '' when there is nothing to serve, and never raises.

        Arcade is excluded: a MAME set is a zip of many files and has no single
        hash, and its pack key is the .mra setname, which the state commit
        already resolves exactly.
        """
        try:
            with _state_lock:
                if _state['seq'] != seq_at_start:
                    return ''
                if _state['is_arcade']:
                    return ''
                friendly = _state['game_system'] or _state['core']

            folders = _pack_folders(friendly)
            if not folders:
                return ''

            details = self.get_rom_details()
            if not details or not details.get('crc32'):
                return ''

            # Hashing is slow enough that another game can be committed while it
            # runs; serving that result would be the stale-artwork bug.
            with _state_lock:
                if _state['seq'] != seq_at_start:
                    return ''

            key = os.path.splitext(details.get('filename') or '')[0]
            found, resolved, system_folder = _pack_lookup_any(
                folders, key, details.get('crc32'), details.get('size'))
            if not found:
                return ''

            with _state_lock:
                if _state['seq'] != seq_at_start:
                    return ''
                _state['artwork_path'] = found
                _state['artwork_seq'] = seq_at_start
            print("\U0001f5bc\ufe0f local artwork by hash: %s/%s.jpg"
                  % (system_folder, resolved))
            return found
        except Exception as e:
            print("\u26a0\ufe0f local artwork hash lookup failed: %s" % e)
            return ''

    def send_artwork_response(self):
        """Sends the pack image for the loaded game, or 404.

        The path is resolved during rom-details, not here, so this handler stays
        cheap enough to hit on every game change. Content-Length is mandatory:
        the ESP32 HTTP client needs it to size its read.
        """
        with _state_lock:
            artwork_path = _state.get('artwork_path', '')
            seq_at_start = _state['seq']
            fresh = (_state.get('artwork_seq', -1) == seq_at_start)

        # Serving an image resolved for a PREVIOUS game is worse than serving
        # none: 404 sends the display to ScreenScraper instead.
        if not fresh:
            self.send_error_response(404, 'Artwork not resolved for the current game')
            return

        # Fresh but EMPTY is not the same as "no artwork exists": the state
        # commit resolves the pack from the game's NAME alone, so _pack_lookup's
        # crc+size step — the one that catches a renamed dump — never ran. Retry
        # here with the hash: it costs once per game and only after the cheap
        # name lookup has already missed.
        if not artwork_path:
            artwork_path = self._artwork_by_hash(seq_at_start)

        if not artwork_path or not os.path.isfile(artwork_path):
            self.send_error_response(404, 'No local artwork for the loaded game')
            return

        try:
            with open(artwork_path, 'rb') as f:
                body = f.read()
        except OSError as e:
            self.send_error_response(500, 'Artwork unreadable: %s' % e)
            return

        self.send_response(200)
        self.send_header('Content-type', 'image/jpeg')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def send_text_response(self, data):
        body = str(data).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def send_index_page(self):
        """Landing page for humans hitting the server root. The display never
        calls '/'; this exists so a manual connectivity test returns something
        reassuring instead of a 404 that looks like a failure."""
        rows = ''.join(
            f'<li><a href="{p}">{p}</a> — {d}</li>' for p, d in PUBLIC_ENDPOINTS
        )
        html = (
            '<!DOCTYPE html><html><head><meta charset="utf-8">'
            '<title>MiSTer Monitor</title></head><body>'
            '<h1>MiSTer Monitor server</h1>'
            '<p>The server is running. Available endpoints:</p>'
            f'<ul>{rows}</ul>'
            '</body></html>'
        )
        body = html.encode('utf-8')
        self.send_response(200)
        self.send_header('Content-type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def send_json_response(self, data):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def send_error_response(self, code, message):
        body = message.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

if __name__ == '__main__':
    try:
        _start_watcher()
        _start_discovery_responder()
        if _RA_AVAILABLE:
            try:
                start_ra_polling(lambda: (_state, _state_lock))
            except Exception as e:
                print(f"ℹ️ RA polling not started: {e}")
        server = ThreadingHTTPServer(('', 8081), MiSTerStatusHandler)
        print("MiSTer Monitor Status Server v2 - port 8081")
        print(f"Version: {SERVER_VERSION}")
        print("Endpoints:")
        for _p, _d in PUBLIC_ENDPOINTS:
            print(f"  {_p:<26} - {_d}")
        # Parameterised endpoints: useful when debugging the server, but not
        # worth listing on the browser page, where they cannot be clicked.
        print("  /status/retroachievements/event - unlock counter micro-poll")
        print("  /status/retroachievements/achievements - trophy list (?page=N&per=M)")
        print("  /status/snapshot - atomic identity snapshot (?seq=N)")
        print("")
        server.serve_forever()
    except Exception as e:
        print(f"Error starting server: {e}")
        import traceback
        traceback.print_exc()
