#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Owned controller-death guardian; only a verified adapter may be signalled."""
import os
import signal
import stat
import sys
import time


def process_matches(pid, ticks, proc_root='/proc'):
    try:
        with open(os.path.join(proc_root, pid, 'stat'), encoding='utf-8') as stream:
            data = stream.read(4097)
        if len(data) > 4096 or not data.startswith(pid + ' ('):
            return False
        fields = data.rsplit(') ', 1)[1].split()
        return fields[0] not in ('Z', 'X', 'x') and fields[19] == ticks
    except (OSError, ValueError, IndexError):
        return False


def literal_record(path):
    descriptor = None
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)
                             | getattr(os, 'O_NONBLOCK', 0))
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            return {}
        data = os.read(descriptor, 4097)
        if len(data) > 4096:
            return {}
        result = {}
        for line in data.decode('utf-8').splitlines():
            key, value = line.split('=', 1)
            if key in result:
                return {}
            result[key] = value
        return result
    except (OSError, ValueError, UnicodeError):
        return {}
    finally:
        if descriptor is not None:
            os.close(descriptor)


def owns_session(runtime, session, pid, ticks):
    if session != os.path.join(runtime, 'session-' + pid + ':' + ticks):
        return False
    record = literal_record(os.path.join(runtime, 'session-owner'))
    try:
        alive = os.lstat(os.path.join(session, 'alive'))
        return (record.get('pid'), record.get('start')) == (pid, ticks) and stat.S_ISREG(alive.st_mode)
    except OSError:
        return False


def watch(controller_pid, controller_start, adapter_pid, adapter_start, runtime, session,
          matches=process_matches, owned=owns_session, send=os.kill, wait=time.sleep):
    while owned(runtime, session, adapter_pid, adapter_start) and matches(adapter_pid, adapter_start):
        if not matches(controller_pid, controller_start):
            # Recheck immediately at the action boundary: an old guardian cannot
            # acquire permission to stop a replacement owner or reused PID.
            if owned(runtime, session, adapter_pid, adapter_start) and matches(adapter_pid, adapter_start):
                try:
                    send(int(adapter_pid), signal.SIGUSR1)
                except ProcessLookupError:
                    pass
            return
        wait(.25)


def process_identity(pid):
    try:
        with open('/proc/' + pid + '/stat', encoding='utf-8') as stream:
            fields = stream.read(4097).rsplit(') ', 1)[1].split()
        return fields[19], fields[2], fields[3], fields[0]
    except (OSError, ValueError, IndexError):
        return None


def owner_published(runtime, pid, ticks):
    record = literal_record(os.path.join(runtime, 'session-owner'))
    return (record.get('pid'), record.get('start')) == (pid, ticks)


def activation_seen(runtime, session, pid, ticks):
    if session != os.path.join(runtime, 'session-' + pid + ':' + ticks):
        return False
    try:
        return stat.S_ISDIR(os.lstat(session).st_mode)
    except OSError:
        return False


def preflight_stop(adapter_pid, adapter_start, group, sid, runtime, session):
    """Serialize with activation; only unactivated private work may be killed."""
    import fcntl
    with open(os.path.join(runtime, 'session-owner.lock'), 'a') as lock:
        deadline = time.monotonic() + 2
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if owner_published(runtime, adapter_pid, adapter_start):
                    if owns_session(runtime, session, adapter_pid, adapter_start) and process_matches(adapter_pid, adapter_start):
                        os.kill(int(adapter_pid), signal.SIGUSR1)
                    return
                if time.monotonic() >= deadline:
                    # An unactivated adapter cannot enter hardware setup after
                    # controller loss: activation and guardian_begin recheck it.
                    # Retain exact group/SID checks below instead of hanging on
                    # a lock left open by an unrelated preflight helper.
                    break
                time.sleep(.05)
        if (owner_published(runtime, adapter_pid, adapter_start)
                or activation_seen(runtime, session, adapter_pid, adapter_start)):
            if owns_session(runtime, session, adapter_pid, adapter_start) and process_matches(adapter_pid, adapter_start):
                os.kill(int(adapter_pid), signal.SIGUSR1)
            return
        identity = process_identity(adapter_pid)
        if not identity or identity[:3] != (adapter_start, group, sid) or identity[3] in ('Z', 'X', 'x'):
            return
        # Retain identities before TERM can remove the group leader. Remaining
        # helpers are individually fenced by start/group/session for escalation.
        members = {}
        for name in os.listdir('/proc'):
            if not name.isdigit():
                continue
            found = process_identity(name)
            if found and found[1:3] == (group, sid) and found[3] not in ('Z', 'X', 'x'):
                members[name] = found
        os.killpg(int(group), signal.SIGTERM)
    deadline = time.monotonic() + 1
    def retained_member(pid, identity):
        current = process_identity(pid)
        return current and current[:3] == identity[:3] and current[3] not in ('Z', 'X', 'x')
    while time.monotonic() < deadline:
        if not any(retained_member(pid, identity) for pid, identity in members.items()):
            return
        time.sleep(.05)
    # Group membership is a separate stable lease after its leader exits. Never
    # issue group KILL without the original leader's current identity.
    # This guardian retains the original private SID from its own registered
    # group. The SID cannot become another session while this lease is live.
    # Rescan for late forks, and revalidate each PID/start before signalling.
    if str(os.getsid(0)) != sid:
        return
    for _ in range(8):
        if (owner_published(runtime, adapter_pid, adapter_start)
                or activation_seen(runtime, session, adapter_pid, adapter_start)):
            return
        found_members = []
        for name in os.listdir('/proc'):
            current = process_identity(name) if name.isdigit() else None
            if current and current[1:3] == (group, sid) and current[3] not in ('Z', 'X', 'x'):
                found_members.append((name, current))
        if not found_members:
            return
        for pid, identity in found_members:
            current = process_identity(pid)
            if current and current[:3] == identity[:3] and current[3] not in ('Z', 'X', 'x'):
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
        time.sleep(.05)


def watch_hosted(controller_pid, controller_start, adapter_pid, adapter_start, runtime, session, group, sid):
    activated = False
    while process_matches(adapter_pid, adapter_start):
        active = owner_published(runtime, adapter_pid, adapter_start)
        activated = activated or active or activation_seen(runtime, session, adapter_pid, adapter_start)
        if active and not owns_session(runtime, session, adapter_pid, adapter_start):
            return  # This owner has already revoked its hardware authority.
        if not process_matches(controller_pid, controller_start):
            try:
                if activated:
                    if owns_session(runtime, session, adapter_pid, adapter_start) and process_matches(adapter_pid, adapter_start):
                        os.kill(int(adapter_pid), signal.SIGUSR1)
                else:
                    preflight_stop(adapter_pid, adapter_start, group, sid, runtime, session)
            except ProcessLookupError:
                pass
            return
        time.sleep(.25)


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) not in (6, 8) or any(not value.isascii() or not value.isdigit() for value in args[:4]):
        return 64
    if int(args[0]) <= 1 or int(args[2]) <= 1:
        return 64
    if len(args) == 8:
        if args[6:] != [args[2], args[2]]:
            return 64
        watch_hosted(*args)
    else:
        watch(*args)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
