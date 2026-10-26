#!/usr/bin/env python3
"""Bounded MCP process cleanup; never identify a process by a substring."""
import argparse
import os
from pathlib import Path
import signal
import sys
import time


def identity(pid, script, proc=Path('/proc')):
    try:
        base = proc / str(pid)
        stat = (base / 'stat').read_text().rsplit(')', 1)[1].split()
        if stat[0] == 'Z':
            return None
        exe = os.readlink(base / 'exe')
        if exe != os.path.realpath(sys.executable):
            return None
        argv = (base / 'cmdline').read_bytes().split(b'\0')
        # MCP is invoked as an executable script or python SCRIPT, never -c/-m.
        if len(argv) < 2 or os.fsdecode(argv[1]) != str(script):
            return None
        return (int(pid), stat[19], exe)
    except (OSError, ValueError, IndexError):
        return None


def processes(script, proc=Path('/proc')):
    return [found for item in proc.iterdir() if item.name.isdecimal()
            if (found := identity(item.name, script, proc)) is not None]


def stop(script, grace=25, proc=Path('/proc')):
    # A warm MCP owns session coordination. Let guarded Menu/audio cleanup
    # complete before escalation; an idle MCP still exits immediately.
    owned = processes(script, proc)
    def remaining():
        return [item for item in owned if identity(item[0], script, proc) == item]
    def send(sig):
        for item in remaining():
            try:
                os.kill(item[0], sig)
            except ProcessLookupError:
                pass
    send(signal.SIGTERM)
    deadline = time.monotonic() + grace
    while remaining() and time.monotonic() < deadline:
        time.sleep(.05)
    send(signal.SIGKILL)
    deadline = time.monotonic() + 1
    while remaining() and time.monotonic() < deadline:
        time.sleep(.05)
    if remaining() or processes(script, proc):
        raise RuntimeError('Verified MCP process remains after bounded shutdown')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('script', type=Path)
    parser.add_argument('--single', action='store_true', help='Require exactly one verified MCP')
    parser.add_argument('--running', action='store_true', help='Check for any verified MCP without stopping it')
    args = parser.parse_args()
    if args.single:
        raise SystemExit(0 if len(processes(args.script)) == 1 else 1)
    if args.running:
        raise SystemExit(0 if processes(args.script) else 1)
    stop(args.script)
