#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Warm session coordinator around the existing protected Bash adapters.

The published owner is this process. One child loads the trusted configuration
and existing picker/launch/cleanup modules once. Its fixed protocol never carries
shell code or ROM paths; the adapter retains its selected record and owned jobs.
"""
import argparse
from collections import deque
import ctypes
from dataclasses import dataclass
import importlib.util
import importlib
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import termios
import time


MAX_MESSAGE = 4096
ACTIONS = frozenset(('boundary', 'prepare', 'take', 'launch', 'timer_begin',
                     'timer_tick', 'key', 'control', 'cleanup'))
KEYS = {'next': 'n', 'previous': 'p', 'mute': 'm', 'm82_play': 'y'}


def process_start(pid):
    try:
        data = Path('/proc/{}/stat'.format(pid)).read_text()
        fields = data.rsplit(') ', 1)[1].split()
        return fields[19] if fields[0] not in ('Z', 'X', 'x') else None
    except (OSError, ValueError, IndexError):
        return None


def atomic_text(path, value):
    temporary = path.with_name(path.name + '.tmp.' + str(os.getpid()))
    temporary.write_text(value, encoding='utf-8')
    os.replace(temporary, path)


@dataclass(frozen=True)
class Reply:
    serial: str
    code: int
    mode: str
    phase: str
    timer: int
    paused: bool
    remaining: int
    action: str

    @classmethod
    def parse(cls, line):
        parts = line.split('\t')
        if len(parts) != 8:
            raise ValueError('Malformed adapter response')
        serial, code, mode, phase, timer, paused, remaining, action = parts
        if serial != 'ready' and (not serial.isascii() or not serial.isdigit()):
            raise ValueError('Invalid adapter sequence')
        if mode not in ('normal', 'roulette', 'm82', 'samvideo'):
            raise ValueError('Invalid adapter mode')
        if phase not in ('preparing', 'loading', 'playing', 'video', 'stopping'):
            raise ValueError('Invalid adapter phase')
        if paused not in ('0', '1') or action not in ('-', 'next', 'previous'):
            raise ValueError('Invalid adapter state')
        numbers = (code, timer, remaining)
        if any(not x.isascii() or not x.isdigit() or len(x) > 12 for x in numbers):
            raise ValueError('Invalid adapter timer')
        return cls(serial, int(code), mode, phase, int(timer), paused == '1', int(remaining), action)


class SessionEngine:
    def __init__(self, entry, root, target='', launcher=subprocess.Popen, clock=time.monotonic):
        self.entry, self.root, self.target = str(entry), Path(root), target
        self.launcher, self.clock = launcher, clock
        self.pid, self.start = os.getpid(), process_start(os.getpid())
        if self.start is None:
            raise RuntimeError('Session requires a live Linux PID/start identity')
        self.runtime = Path(os.environ.get('SAM_TMP_ROOT', '/tmp/.SAM_tmp'))
        self.session = self.runtime / ('session-{}:{}'.format(self.pid, self.start))
        self.commands = self.session / 'commands'
        self.selector = selectors.DefaultSelector()
        self.adapter = None
        self.adapter_start = None
        self.buffer = b''
        self.sequence = 0
        self.outstanding = None
        self.next_operation = ('boundary', '')
        self.queued = deque()
        self.claimed = set()
        self.reply = None
        self.stopping = False
        self.control = None
        self.owner_commands = None
        self.next_tick = 0
        self.next_prepare = 0
        self.terminal_settings = None
        self.public_action = None
        self.stop_receipts = []
        self.stop_signalled = False
        self.adapter_finishing = False

    def start_adapter(self):
        environment = dict(os.environ, SAM_ENGINE_OWNER_PID=str(self.pid),
                           SAM_ENGINE_OWNER_START=self.start, SAM_ENGINE_ROOT=str(self.root))
        libc = ctypes.CDLL(None, use_errno=True)
        libc.prctl.argtypes = (ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong)
        libc.prctl.restype = ctypes.c_int
        expected_parent = self.pid

        def parent_death_signal():
            # This process has no threads at fork. Fence the interval before
            # exec too: losing the owner must cancel an adapter already loading.
            if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0 or os.getppid() != expected_parent:
                os._exit(125)

        self.adapter = self.launcher(['bash', self.entry, '--engine-adapter', self.target],
                                     env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     bufsize=0, preexec_fn=parent_death_signal)
        self.adapter_start = process_start(self.adapter.pid)
        if self.adapter_start is None:
            raise RuntimeError('Adapter exited before identity registration')
        os.set_blocking(self.adapter.stdout.fileno(), False)
        self.selector.register(self.adapter.stdout, selectors.EVENT_READ, 'adapter')
        try:
            self.selector.register(sys.stdin, selectors.EVENT_READ, 'keyboard')
            if os.isatty(sys.stdin.fileno()):
                self.terminal_settings = termios.tcgetattr(sys.stdin.fileno())
                settings = termios.tcgetattr(sys.stdin.fileno())
                settings[3] &= ~(termios.ICANON | termios.ECHO)
                settings[6][termios.VMIN] = 1
                settings[6][termios.VTIME] = 0
                termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, settings)
        except (OSError, ValueError):
            pass
        # Import the existing public claim/ack implementation once, never on a
        # timer tick. Its state/identity/expiry validation remains authoritative.
        control_path = str(self.root / 'control')
        if control_path not in sys.path:
            sys.path.insert(0, control_path)
        spec = importlib.util.spec_from_file_location('_sam_engine_control', self.root / 'control/sam_control.py')
        self.control = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.control)
        if str(self.root) not in sys.path:
            sys.path.insert(0, str(self.root))
        self.owner_commands = importlib.import_module('sam.owner_commands')
        self.ack_directory = self.owner_commands.acknowledgement_directory(self.runtime)
        self.ack_directory.mkdir(mode=0o700, parents=True, exist_ok=True)

    def publish_endpoint(self):
        self.commands.mkdir(mode=0o700, exist_ok=True)
        atomic_text(self.session / 'prototype-controls',
                    'owner_pid={}\nowner_start={}\n'.format(self.pid, self.start))

    def current(self):
        try:
            record = dict(line.split('=', 1) for line in (self.runtime / 'session-owner').read_text().splitlines())
            return record if record.get('pid') == str(self.pid) and record.get('start') == self.start else None
        except (OSError, ValueError):
            return None

    def scan_commands(self):
        if self.reply is None or self.stopping or not self.current():
            return
        for path in sorted(self.commands.glob('req-*.json'),
                           key=lambda item: (not item.name.startswith('req-urgent-'), item.name)):
            if path.name in self.claimed:
                continue
            request = self.owner_commands.read(path)
            prefix = 'req-urgent-' if path.name.startswith('req-urgent-') else 'req-'
            request_id = path.name[len(prefix):-5]
            if len(request_id) != 32 or any(c not in '0123456789abcdef' for c in request_id):
                continue
            owner = self.current()
            valid = bool(owner and self.owner_commands.valid(request, owner, now=self.clock())
                         and request['request_id'] == request_id)
            # Bind selection input to the launch the gateway observed, including
            # preparing/loading requests. A successor never inherits old input.
            if valid and request['action'] in ('stop', 'exit_to_menu'):
                self.stop_receipts.append(('direct', path, request))
                if self.adapter.poll() is None and process_start(self.adapter.pid) == self.adapter_start:
                    os.kill(self.adapter.pid, signal.SIGUSR1)
                    self.stop_signalled = True
                self.stopping = True
                return
            if valid and request['action'] == 'm82_play':
                valid = self.reply.mode == 'm82' and self.reply.phase == 'playing'
            self.claimed.add(path.name)
            if valid and len(self.queued) < 256:
                self.queued.append(('key', KEYS[request['action']], ('direct', path, request)))
            else:
                # A malformed envelope cannot supply acknowledgement identity.
                if (isinstance(request, dict) and request.get('request_id') == request_id
                        and request.get('owner_pid') == str(self.pid)
                        and request.get('owner_start') == self.start
                        and isinstance(request.get('launch'), str)
                        and request['launch'].isascii() and request['launch'].isdigit()):
                    self.owner_commands.acknowledge(self.ack_directory, request, ok=False, state='failed')
                path.unlink(missing_ok=True)
                self.claimed.discard(path.name)
        if self.reply.phase in ('playing', 'video') and self.outstanding is None and len(self.queued) < 256:
            request = self.control.claim_request(self.pid, self.start)
            if request:
                self.queued.append(('control', request['action'], ('public', request['request_id'])))

    def keyboard(self, data):
        # One burst produces one navigation action; mute/play keep their order.
        navigation = None
        for key in data.decode('ascii', errors='ignore'):
            key = key.lower()
            if key in ('n', 'p'):
                navigation = key
            elif key in ('m', 'y'):
                if len(self.queued) < 256:
                    self.queued.append(('key', key, None))
        if navigation:
            self.queued = deque(item for item in self.queued if item[0] != 'key' or item[1] not in ('n', 'p') or item[2] is not None)
            if len(self.queued) < 256:
                self.queued.append(('key', navigation, None))

    def send(self, action, argument='', receipt=None):
        if action not in ACTIONS or argument not in ('', 'n', 'p', 'm', 'y', 'pause', 'resume', 'ignore', 'next', 'play'):
            raise ValueError('Invalid adapter operation')
        if receipt is not None and receipt[0] == 'direct':
            owner = self.current()
            if not owner or not self.owner_commands.valid(receipt[2], owner, now=self.clock()):
                self.acknowledge(receipt, False)
                return
        self.sequence += 1
        self.adapter.stdin.write('{}\t{}\t{}\n'.format(self.sequence, action, argument).encode('ascii'))
        self.outstanding = (str(self.sequence), action, receipt)

    def acknowledge(self, receipt, ok):
        if receipt is None:
            return
        if receipt[0] == 'direct':
            try:
                self.owner_commands.acknowledge(self.ack_directory, receipt[2], ok=ok,
                                               state='applied' if ok else 'failed')
                receipt[1].unlink(missing_ok=True)
            except OSError:
                pass  # Cleanup may have revoked the private endpoint already.
            self.claimed.discard(receipt[1].name)
        else:
            self.control.acknowledge(receipt[1], 200 if ok else 503,
                                     '' if ok else 'SAM action could not be completed')

    def complete(self, reply):
        if self.reply is None:
            if reply.serial != 'ready' or reply.code:
                raise RuntimeError('Adapter initialization failed')
            self.reply = reply
            self.publish_endpoint()
            return
        if self.outstanding is None or reply.serial != self.outstanding[0]:
            raise RuntimeError('Unexpected adapter response')
        _, operation, receipt = self.outstanding
        self.outstanding, self.reply = None, reply
        applied = reply.code == 0 or (reply.code == 1 and operation in ('key', 'control')
                                     and reply.action in ('next', 'previous'))
        self.acknowledge(receipt, applied)
        if operation == 'control' and self.public_action == 'play' and applied:
            self.adapter_finishing = True
            self.stopping = True
            return
        if reply.code > 1 and operation not in ('key', 'control'):
            raise RuntimeError('Session adapter failed during ' + operation)
        if (operation in ('key', 'control', 'timer_tick') and reply.action in ('next', 'previous')
                and reply.code <= 1) or (operation == 'timer_tick' and reply.code == 1):
            self.next_operation = ('boundary', '')
        elif operation == 'boundary':
            self.next_operation = ('prepare', '')
        elif operation == 'prepare':
            self.next_prepare = self.clock() + 1
            self.next_operation = ('take', '')
        elif operation == 'take':
            self.next_operation = ('launch', '') if reply.code == 0 else ('take', '')
            if reply.code:
                self.next_tick = self.clock() + .1
        elif operation == 'launch':
            self.next_operation = ('timer_begin', '') if reply.code == 0 else ('boundary', '')
        elif operation == 'timer_begin':
            self.next_operation = ('timer_tick', '')
            self.next_tick = self.clock()
        elif operation == 'timer_tick':
            self.next_operation = ('timer_tick', '')
            self.next_tick = self.clock() + .1
        # Adapter mode hooks render their specialized countdown/loading state.

    def read_adapter(self):
        data = os.read(self.adapter.stdout.fileno(), MAX_MESSAGE)
        if not data:
            return False
        self.buffer += data
        if len(self.buffer) > MAX_MESSAGE and b'\n' not in self.buffer:
            raise RuntimeError('Oversized adapter response')
        while b'\n' in self.buffer:
            line, self.buffer = self.buffer.split(b'\n', 1)
            if len(line) > MAX_MESSAGE:
                raise RuntimeError('Oversized adapter response')
            self.complete(Reply.parse(line.decode('ascii')))
        return True

    def request_stop(self, *_):
        self.stopping = True

    def shutdown(self):
        # TERM reaches the exact persistent adapter while Python remains the
        # live published owner. Existing hooks retain Menu/audio ownership.
        status = 0
        if self.adapter is not None:
            if not self.stop_signalled and not self.adapter_finishing and self.adapter.poll() is None and process_start(self.adapter.pid) == self.adapter_start:
                self.adapter.terminate()
            status = self.adapter.wait()
            for receipt in self.stop_receipts:
                self.acknowledge(receipt, self.stop_signalled and status == 0)
            self.adapter.stdin.close()
            self.adapter.stdout.close()
        if self.terminal_settings is not None:
            try:
                termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, self.terminal_settings)
            except (OSError, ValueError):
                pass  # A closed viewer cannot prevent completion receipts.
        for _, _, receipt in self.queued:
            self.acknowledge(receipt, False)
        self.selector.close()
        return 0 if status == 0 else 1

    def run(self):
        result = 0
        signal.signal(signal.SIGTERM, self.request_stop)
        # Ctrl-C detaches through the monitor's tmux key table; it must not kill
        # the owner. The existing monitor key table also handles Q locally.
        signal.signal(signal.SIGINT, lambda *_: None)
        try:
            self.start_adapter()
            while not self.stopping:
                for key, _ in self.selector.select(.1):
                    if key.data == 'adapter':
                        if not self.read_adapter():
                            self.stopping = True
                            result = self.adapter.wait()
                            if self.outstanding is not None:
                                _, operation, receipt = self.outstanding
                                self.acknowledge(receipt, result == 0 and operation == 'control'
                                                 and receipt is not None and receipt[0] == 'public'
                                                 and self.public_action == 'play')
                    else:
                        data = os.read(sys.stdin.fileno(), 4096)
                        if data:
                            self.keyboard(data)
                        else:
                            self.selector.unregister(sys.stdin)
                if self.stopping:
                    break
                self.scan_commands()
                if self.reply is not None and self.outstanding is None:
                    if self.queued:
                        operation, argument, receipt = self.queued.popleft()
                        self.public_action = argument if operation == 'control' else None
                        self.send(operation, argument, receipt)
                    elif self.clock() >= self.next_tick:
                        operation, argument = self.next_operation
                        if operation == 'take' and self.clock() >= self.next_prepare:
                            operation = 'prepare'
                        self.send(operation, argument)
        except (OSError, ValueError, RuntimeError, ImportError) as error:
            sys.stderr.write('SAM ERROR: {}\n'.format(error))
            result = 1
        finally:
            if self.shutdown():
                result = 1
        return result if result >= 0 else 1


def main(argv=None):
    parser = argparse.ArgumentParser()
    root = Path(__file__).resolve().parents[1]
    parser.add_argument('--root', default=str(root))
    parser.add_argument('--entry', default=str(root.parent / 'MiSTer_SAM_on.sh'))
    parser.add_argument('--target', default='')
    args = parser.parse_args(argv)
    return SessionEngine(args.entry, args.root, args.target).run()


if __name__ == '__main__':
    sys.exit(main())
