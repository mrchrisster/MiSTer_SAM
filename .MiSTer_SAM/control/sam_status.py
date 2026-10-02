# SPDX-License-Identifier: AGPL-3.0-or-later
"""Read SAM's literal atomic state file; never execute or unescape its values."""
import os
from pathlib import Path
import stat

MODES = {'normal': 'attract', 'roulette': 'roulette', 'm82': 'm82', 'samvideo': 'video'}
KEYS = {'active', 'mode', 'timer', 'start_time', 'owner_pid', 'owner_start',
        'game', 'rom_path', 'core', 'setname', 'game_kept'}
LIMIT = 4096


def inactive():
    return {'active': False, 'mode': 'off', 'gametimer': 0, 'next_game_at': None}


def parse_sam_state(raw):
    values = {}
    for line in raw.decode('utf-8').split('\n'):
        line = line.removesuffix('\r')
        if not line:
            continue
        key, value = line.split('=', 1)
        if not key:
            raise ValueError('Empty key')
        if key not in KEYS:
            continue
        if key in values:
            raise ValueError('Duplicate status key')
        values[key] = value
    return values


def integer(value):
    if not value or len(value) > 20 or not value.isascii() or not value.isdigit():
        raise ValueError('Invalid nonnegative integer')
    result = int(value)
    if result > 2**63 - 1:
        raise ValueError('Integer out of range')
    return result


def read_sam_status(path='/tmp/SAM_state', proc_root='/proc'):
    try:
        flags = os.O_RDONLY | os.O_NONBLOCK | getattr(os, 'O_NOFOLLOW', 0)
        fd = os.open(path, flags)
        with os.fdopen(fd, 'rb') as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                return inactive()
            raw = source.read(LIMIT + 1)
        if len(raw) > LIMIT:
            return inactive()
        values = parse_sam_state(raw)
        if values['active'] != 'yes':
            return inactive()
        mode = MODES[values['mode']]
        timer = integer(values['timer'])
        start = integer(values['start_time'])
        pid = integer(values['owner_pid'])
        ticks = integer(values['owner_start'])
        if pid <= 0 or ticks <= 0:
            return inactive()
        # comm (field 2) can contain spaces and parentheses. Everything after
        # its LAST closing parenthesis starts at state, Linux stat field 3.
        raw_stat = (Path(proc_root) / str(pid) / 'stat').read_text()
        prefix, tail = raw_stat.rsplit(')', 1)
        if integer(prefix.split('(', 1)[0].strip()) != pid:
            return inactive()
        fields = tail.split()
        if fields[0] in {'Z', 'X', 'x'} or integer(fields[19]) != ticks:
            return inactive()
        # An expired timer does not imply that SAM stopped or lost ownership.
        return {'active': True, 'mode': mode, 'gametimer': timer,
                'next_game_at': start + timer if start > 0 and timer > 0 else None}
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        return inactive()
