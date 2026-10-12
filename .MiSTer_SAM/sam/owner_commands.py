# SPDX-License-Identifier: GPL-3.0-or-later
"""Private RAM command boundary for the warm session owner.

Physical readers remain in MCP. These records carry decisions, never input
events. A completed acknowledgement is bound to the same owner and selection.
"""
import json
import math
import os
from pathlib import Path
import stat
import time

from sam.session import owner_key, read_literal_file

URGENT = frozenset({'stop', 'exit_to_menu'})
ACTIONS = frozenset({'next', 'previous', 'mute', 'm82_play'}) | URGENT
FIELDS = frozenset({'request_id', 'action', 'owner_pid', 'owner_start', 'launch', 'expires'})


def session_path(runtime, owner):
    pid, start = owner_key(owner)
    return Path(runtime) / ('session-' + pid + ':' + start)


def enabled(runtime, owner):
    marker = read_literal_file(str(session_path(runtime, owner) / 'prototype-controls'))
    return (marker.get('owner_pid'), marker.get('owner_start')) == owner_key(owner)


def acknowledgement_directory(runtime):
    # Cleanup removes private session scratch before Menu completion. Retain
    # completion receipts in RAM until their caller has consumed them.
    return Path(runtime) / 'engine-receipts'


def acknowledgement_name(request):
    return 'ack-' + request['owner_pid'] + '-' + request['owner_start'] + '-' + request['request_id'] + '.json'


def prune_receipts(directory):
    """Bound abandoned RAM receipts at command boundaries, never timer ticks."""
    records = []
    try:
        for path in Path(directory).glob('ack-*.json'):
            name = path.name[4:-5].split('-')
            if (len(name) != 3 or not name[0].isdigit() or not name[1].isdigit()
                    or len(name[2]) != 32 or any(char not in '0123456789abcdef' for char in name[2])):
                continue
            try:
                metadata = path.lstat()
            except OSError:
                continue
            if stat.S_ISREG(metadata.st_mode):
                records.append((metadata.st_mtime, path))
        records.sort(key=lambda item: item[0], reverse=True)
        cutoff = time.time() - 60
        for index, (modified, path) in enumerate(records):
            if index >= 255 or modified < cutoff:
                try:
                    path.unlink(missing_ok=True)
                except OSError:
                    pass
    except OSError:
        pass


def atomic(path, value):
    temporary = path.with_name(path.name + '.tmp.' + str(os.getpid()))
    try:
        with open(temporary, 'x', encoding='utf-8') as target:
            json.dump(value, target, separators=(',', ':'), ensure_ascii=False)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def read(path):
    descriptor = None
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)
                             | getattr(os, 'O_NONBLOCK', 0))
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            return None
        data = os.read(descriptor, 4097)
        if len(data) > 4096:
            return None
        return json.loads(data.decode('utf-8'))
    except (OSError, ValueError, UnicodeError):
        return None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def valid(request, owner, now=None):
    if not isinstance(request, dict) or set(request) != FIELDS:
        return False
    token = request['request_id']
    if (not isinstance(token, str) or len(token) != 32
            or any(char not in '0123456789abcdef' for char in token)):
        return False
    if (not isinstance(request['action'], str) or request['action'] not in ACTIONS
            or (request['owner_pid'], request['owner_start']) != owner_key(owner)
            or (request['action'] not in URGENT
                and request['launch'] != owner.get('launch', '0'))):
        return False
    expiry = request['expires']
    return (type(expiry) in (float, int) and math.isfinite(expiry)
            and (time.monotonic() if now is None else now) <= expiry)


def acknowledge(directory, request, *, ok, state='applied', error=''):
    """Accepted is observable, but only applied reports successful delivery."""
    prune_receipts(directory)
    atomic(Path(directory) / acknowledgement_name(request),
           dict(request_id=request['request_id'], owner_pid=request['owner_pid'],
                owner_start=request['owner_start'], launch=request['launch'],
                state=state, ok=bool(ok), error=error))


def submit(runtime, owner, action, current, timeout=2):
    if action not in ACTIONS:
        raise ValueError('Unsupported owner command')
    directory = session_path(runtime, owner) / 'commands'
    acknowledgements = acknowledgement_directory(runtime)
    # The owner creates this directory before advertising readiness. A sender
    # cannot resurrect scratch after cleanup has started.
    if not directory.is_dir() or not acknowledgements.is_dir() or current(owner) is None:
        return False
    token = os.urandom(16).hex()
    pid, start = owner_key(owner)
    request = dict(request_id=token, action=action, owner_pid=pid, owner_start=start,
                   launch=owner.get('launch', '0'), expires=time.monotonic() + timeout)
    prefix = 'req-urgent-' if action in URGENT else 'req-'
    path = directory / (prefix + token + '.json')
    ack = acknowledgements / acknowledgement_name(request)
    def completion(reply):
        if (isinstance(reply, dict) and reply.get('request_id') == token
                and (reply.get('owner_pid'), reply.get('owner_start')) == (pid, start)
                and reply.get('launch') == request['launch']
                and reply.get('state') in {'applied', 'failed'}):
            return reply.get('state') == 'applied' and reply.get('ok') is True
        return None
    try:
        atomic(path, request)
        deadline = time.monotonic() + (20 if action in URGENT else timeout)
        while time.monotonic() < deadline:
            result = completion(read(ack))
            if result is not None:
                return result
            if current(owner) is None:
                # Completion can be published between the first read and the
                # liveness check. A retained, identity-bound ack wins that race.
                return completion(read(ack)) is True
            time.sleep(.02)
        return False
    except OSError:
        return False
    finally:
        path.unlink(missing_ok=True)
        ack.unlink(missing_ok=True)
