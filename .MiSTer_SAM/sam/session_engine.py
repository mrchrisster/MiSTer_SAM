#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Warm session coordinator around the existing protected Bash adapters.

Standalone sessions publish this process; hosted sessions publish their unique
Bash adapter while MCP only coordinates its protocol. The child loads configuration
and existing picker/launch/cleanup modules once. Its fixed protocol never carries
shell code or ROM paths; the adapter retains its selected record and owned jobs.
"""
from collections import deque, namedtuple
import ctypes
import importlib.util
import importlib
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import termios
import threading
import time
import types


MAX_MESSAGE = 4096
ACTIONS = frozenset(('boundary', 'prepare', 'take', 'launch', 'timer_begin',
                     'timer_tick', 'key', 'control', 'cleanup'))
KEYS = {'next': 'n', 'previous': 'p', 'mute': 'm', 'm82_play': 'y'}
_CONTROL_MODULES = {}
_CONTROL_LOCK = threading.Lock()


def control_for(root, environment):
    """Reuse imported code while binding session paths without env swaps."""
    key = str(root.resolve())
    with _CONTROL_LOCK:
        if key not in _CONTROL_MODULES:
            control_path = str(root / 'control')
            if control_path not in sys.path:
                sys.path.insert(0, control_path)
            spec = importlib.util.spec_from_file_location('_sam_engine_control', root / 'control/sam_control.py')
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            _CONTROL_MODULES[key] = module
        cached = _CONTROL_MODULES[key]
        if str(root) not in sys.path:
            sys.path.insert(0, str(root))
        owner_commands = importlib.import_module('sam.owner_commands')
    # Functions share imported code/locks while retaining each session's
    # immutable journal/state/mailbox paths.
    control = types.ModuleType(cached.__name__)
    control.__dict__.update(cached.__dict__)
    control.ROOT = Path(environment.get('SAM_CONTROL_ROOT', '/tmp/mister_sam_control'))
    control.STORE = Path(environment.get('SAM_CONTROL_STORE', '/media/fat/Scripts/.MiSTer_SAM/control-journal'))
    control.STATE = Path(environment.get('SAM_CONTROL_STATE', environment.get('SAM_STATE_FILE', '/tmp/SAM_state')))
    control.MONITOR = environment.get('SAM_CONTROL_MONITOR', 'http://127.0.0.1:8081/status/snapshot')
    for name, function in cached.__dict__.items():
        if isinstance(function, types.FunctionType) and function.__globals__ is cached.__dict__:
            bound = types.FunctionType(function.__code__, control.__dict__, name,
                                       function.__defaults__, function.__closure__)
            bound.__kwdefaults__ = function.__kwdefaults__
            control.__dict__[name] = bound
    return control, owner_commands


def process_start(pid):
    try:
        data = Path('/proc/{}/stat'.format(pid)).read_text()
        fields = data.rsplit(') ', 1)[1].split()
        return fields[19] if fields[0] not in ('Z', 'X', 'x') else None
    except (OSError, ValueError, IndexError):
        return None


def process_group_identity(pid):
    """Include zombies: an unreaped launch leader still pins its identity."""
    try:
        fields = Path('/proc/{}/stat'.format(pid)).read_text().rsplit(') ', 1)[1].split()
        return fields[19], fields[0], int(fields[2]), int(fields[3])
    except (OSError, ValueError, IndexError):
        return None


def atomic_text(path, value):
    temporary = path.with_name(path.name + '.tmp.' + str(os.getpid()))
    temporary.write_text(value, encoding='utf-8')
    os.replace(temporary, path)


class Reply(namedtuple('_Reply', 'serial code mode phase timer paused remaining action')):
    # An immutable protocol record needs no dataclasses/inspect/AST imports on
    # the ARM startup path. It retains the same fields and constructor.
    __slots__ = ()

    @classmethod
    def parse(cls, line):
        parts = line.split('\t')
        if len(parts) != 8:
            raise ValueError('Malformed adapter response')
        serial, code, mode, phase, timer, paused, remaining, action = parts
        if serial not in ('ready', 'validated') and (not serial.isascii() or not serial.isdigit()):
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
    def __init__(self, entry, root, target='', launcher=subprocess.Popen, clock=time.monotonic,
                 hosted=False, environment=None, log=None, input_stream=None):
        self.entry, self.root, self.target = str(entry), Path(root), target
        self.launcher, self.clock = launcher, clock
        self.hosted = bool(hosted)
        self.environment = dict(os.environ if environment is None else environment)
        self.log = log
        self.input_stream = input_stream if input_stream is not None else (None if hosted else sys.stdin)
        if hosted and self.input_stream is sys.stdin:
            raise ValueError('Hosted sessions cannot own controller stdin')
        self.controller_pid, self.controller_start = os.getpid(), process_start(os.getpid())
        if self.controller_start is None:
            raise RuntimeError('Session requires a live Linux PID/start identity')
        self.pid, self.start = (None, None) if hosted else (self.controller_pid, self.controller_start)
        self.runtime = Path(self.environment.get('SAM_TMP_ROOT', '/tmp/.SAM_tmp'))
        self.session = self.commands = None
        if not hosted:
            self.bind_owner(self.pid, self.start)
        self.selector = selectors.DefaultSelector()
        self._wake_lock = threading.Lock()
        self._wake_pipe = None
        if hosted:
            self._wake_pipe = os.pipe()
            for descriptor in self._wake_pipe:
                os.set_blocking(descriptor, False)
            self.selector.register(self._wake_pipe[0], selectors.EVENT_READ, 'wake')
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
        self.endpoint_published = False
        self.preflight_reply = None
        self.preflight_done = threading.Event()
        self.activation_requested = threading.Event()
        self.activated = False
        self.ready = threading.Event()
        self.finished = threading.Event()
        self.result = None
        self.error = None
        self._menu_stop = False
        self._stop_requested = False
        self._ready_received = False
        self._state_lock = threading.RLock()
        self._finishing_receipt = None

    def bind_owner(self, pid, start):
        self.pid, self.start = pid, start
        self.session = self.runtime / ('session-{}:{}'.format(pid, start))
        self.commands = self.session / 'commands'

    def start_adapter(self):
        environment = dict(self.environment, SAM_ENGINE_ROOT=str(self.root))
        options = dict(env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
        if self.log is not None:
            options['stderr'] = self.log
        if self.hosted:
            environment.pop('SAM_ENGINE_OWNER_PID', None)
            environment.pop('SAM_ENGINE_OWNER_START', None)
            environment.update(SAM_ENGINE_CONTROLLER_PID=str(self.controller_pid),
                               SAM_ENGINE_CONTROLLER_START=self.controller_start)
            mode = '--engine-hosted-adapter'
            options['start_new_session'] = True
        else:
            environment.update(SAM_ENGINE_OWNER_PID=str(self.pid), SAM_ENGINE_OWNER_START=self.start)
            libc = ctypes.CDLL(None, use_errno=True)
            libc.prctl.argtypes = (ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong)
            libc.prctl.restype = ctypes.c_int
            expected_parent = self.pid

            def parent_death_signal():
                # Standalone owners have no threads at fork. Hosted launches
                # rely on the platform guardian instead of preexec_fn.
                if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0 or os.getppid() != expected_parent:
                    os._exit(125)

            options['preexec_fn'] = parent_death_signal
            mode = '--engine-adapter'
        self.adapter = self.launcher(['bash', self.entry, mode, self.target], **options)
        identity = process_group_identity(self.adapter.pid) if self.hosted else None
        self.adapter_start = identity[0] if identity is not None else process_start(self.adapter.pid)
        if self.adapter_start is None:
            raise RuntimeError('Adapter exited before identity registration')
        if self.hosted:
            self.bind_owner(self.adapter.pid, self.adapter_start)
        os.set_blocking(self.adapter.stdout.fileno(), False)
        self.selector.register(self.adapter.stdout, selectors.EVENT_READ, 'adapter')
        try:
            if self.input_stream is not None:
                self.selector.register(self.input_stream, selectors.EVENT_READ, 'keyboard')
            if not self.hosted and self.input_stream is not None and os.isatty(self.input_stream.fileno()):
                self.terminal_settings = termios.tcgetattr(self.input_stream.fileno())
                settings = termios.tcgetattr(self.input_stream.fileno())
                settings[3] &= ~(termios.ICANON | termios.ECHO)
                settings[6][termios.VMIN] = 1
                settings[6][termios.VTIME] = 0
                termios.tcsetattr(self.input_stream.fileno(), termios.TCSANOW, settings)
        except (OSError, ValueError):
            pass
        # Import the existing public claim/ack implementation once, never on a
        # timer tick. Its state/identity/expiry validation remains authoritative.
        self.control, self.owner_commands = control_for(self.root, self.environment)
        self.ack_directory = self.owner_commands.acknowledgement_directory(self.runtime)
        self.ack_directory.mkdir(mode=0o700, parents=True, exist_ok=True)

    def publish_endpoint(self):
        self.commands.mkdir(mode=0o700, exist_ok=True)
        atomic_text(self.session / 'prototype-controls',
                    'owner_pid={}\nowner_start={}\n'.format(self.pid, self.start))
        self.endpoint_published = True

    def current(self):
        if self.pid is None:
            return None
        try:
            record = dict(line.split('=', 1) for line in (self.runtime / 'session-owner').read_text().splitlines())
            return record if record.get('pid') == str(self.pid) and record.get('start') == self.start else None
        except (OSError, ValueError):
            return None

    def scan_commands(self):
        if self.stopping or not self.current():
            return
        if not self.endpoint_published:
            # The adapter publishes this owner's identity before startup hooks.
            # Admit urgent Stop while those hooks are blocked, but do not create
            # scratch until the live adapter has established its private session.
            if (not (self.session / 'alive').is_file() or self.adapter.poll() is not None
                    or process_start(self.adapter.pid) != self.adapter_start):
                return
            self.publish_endpoint()
        for path in sorted(self.commands.glob('req-*.json'),
                           key=lambda item: (not item.name.startswith('req-urgent-'), item.name)):
            if path.name in self.claimed:
                continue
            if self.reply is None and not path.name.startswith('req-urgent-'):
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
                # Hosted owners can exit before their controller publishes the
                # terminal receipt. Acceptance proves this exact Stop reached
                # the owner, but never reports cleanup as successfully applied.
                self.owner_commands.acknowledge(self.ack_directory, request, ok=False, state='accepted')
                self.stop_receipts.append(('direct', path, request))
                if self.adapter.poll() is None and process_start(self.adapter.pid) == self.adapter_start:
                    os.kill(self.adapter.pid, signal.SIGUSR1)
                    self.stop_signalled = True
                self.stopping = True
                return
            if self.reply is None:
                # A forged urgent filename cannot make ordinary controls ready.
                continue
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
        if (self.reply is not None and self.reply.phase in ('playing', 'video')
                and self.outstanding is None and len(self.queued) < 256):
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
        with self._state_lock:
            if self.stopping:
                self.acknowledge(receipt, False)
                return
            self.send_bound(action, argument, receipt)

    def send_bound(self, action, argument='', receipt=None):
        if action not in ACTIONS or argument not in ('', 'n', 'p', 'm', 'y', 'pause', 'resume', 'ignore', 'next', 'play'):
            raise ValueError('Invalid adapter operation')
        if receipt is not None and receipt[0] == 'direct':
            owner = self.current()
            if not owner or not self.owner_commands.valid(receipt[2], owner, now=self.clock()):
                self.acknowledge(receipt, False)
                return
        if receipt is not None and receipt[0] == 'local':
            if not self.local_valid(receipt[1], self.current()):
                self.acknowledge(receipt, False)
                return
        self.sequence += 1
        self.adapter.stdin.write('{}\t{}\t{}\n'.format(self.sequence, action, argument).encode('ascii'))
        self.outstanding = (str(self.sequence), action, receipt)

    def acknowledge(self, receipt, ok):
        if receipt is None:
            return
        if receipt[0] == 'local':
            receipt[1]['ok'] = bool(ok)
            receipt[1]['event'].set()
        elif receipt[0] == 'direct':
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
        if self.hosted and reply.serial == 'validated':
            if self.preflight_reply is not None or self.reply is not None or self.activated:
                raise RuntimeError('Unexpected adapter preflight response')
            self.preflight_reply = reply
            self.preflight_done.set()
            if reply.code:
                raise RuntimeError('Adapter preflight failed')
            return
        if self.reply is None:
            if self.hosted and (not self.activated or self.preflight_reply is None):
                raise RuntimeError('Adapter became ready before activation')
            if reply.serial != 'ready' or reply.code:
                raise RuntimeError('Adapter initialization failed')
            if self.hosted and (not self.current() or not (self.session / 'alive').is_file()
                                or process_start(self.adapter.pid) != self.adapter_start):
                raise RuntimeError('Adapter did not establish its session owner')
            self.reply = reply
            self.publish_endpoint()
            self._ready_received = True
            self.ready.set()
            return
        if self.outstanding is None or reply.serial != self.outstanding[0]:
            raise RuntimeError('Unexpected adapter response')
        _, operation, receipt = self.outstanding
        self.outstanding, self.reply = None, reply
        applied = reply.code == 0 or (reply.code == 1 and operation in ('key', 'control')
                                     and reply.action in ('next', 'previous'))
        if operation == 'control' and self.public_action == 'play' and applied:
            if receipt is not None and receipt[0] == 'local':
                self._finishing_receipt = receipt
            else:
                self.acknowledge(receipt, applied)
            self.adapter_finishing = True
            self.stopping = True
            return
        self.acknowledge(receipt, applied)
        if reply.code > 1 and operation not in ('key', 'control'):
            raise RuntimeError('Session adapter failed during ' + operation)
        if (operation in ('key', 'control', 'timer_tick') and reply.action in ('next', 'previous')
                and reply.code <= 1) or (operation == 'timer_tick' and reply.code == 1):
            self.next_operation = ('boundary', '')
            self.next_tick = 0
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

    def stop(self, menu=True):
        """Request cleanup in the controller thread, never signal MCP."""
        with self._state_lock:
            self._menu_stop = self._menu_stop or bool(menu)
            self._stop_requested = True
            self.request_stop()
        self.wake()

    def local_valid(self, request, owner):
        if (not owner or request.get('cancelled') or self.stopping
                or self.clock() > request['expires']
                or (owner.get('pid'), owner.get('start')) != (request['pid'], request['start'])
                or owner.get('launch', '0') != request['launch']):
            return False
        if request['action'] == 'm82_play':
            return self.reply is not None and self.reply.mode == 'm82' and owner.get('phase') == 'playing'
        if request['action'] in ('pause', 'resume', 'play', 'ignore'):
            return self.reply is not None and self.reply.mode in ('normal', 'roulette') and owner.get('phase') == 'playing'
        return True

    def queue_local(self, action, expected_owner, launch=None, timeout=25):
        """Bound private controller commands; public Monitor keeps its journal."""
        controls = {'pause', 'resume', 'play', 'ignore', 'exit_to_game'}
        if action not in controls and action not in KEYS:
            raise ValueError('Unsupported local action')
        if type(timeout) not in (int, float) or not 0 < timeout <= 60:
            return False
        if not expected_owner:
            return False
        request = dict(pid=str(expected_owner.get('pid', '')), start=str(expected_owner.get('start', '')),
                       launch=str(expected_owner.get('launch', '0') if launch is None else launch),
                       action=action, expires=self.clock() + timeout, event=threading.Event(), ok=False, cancelled=False)
        with self._state_lock:
            if not self.local_valid(request, self.current()) or len(self.queued) >= 256:
                return False
            operation = 'control' if action in controls else 'key'
            argument = 'play' if action == 'exit_to_game' else action if operation == 'control' else KEYS[action]
            self.queued.append((operation, argument, ('local', request)))
        self.wake()
        if not request['event'].wait(timeout):
            with self._state_lock:
                request['cancelled'] = True
            return False
        return request['ok']

    def wake(self):
        # Selector wakeups are private controller notifications, never input.
        with self._wake_lock:
            if self._wake_pipe is not None:
                try:
                    os.write(self._wake_pipe[1], b'1')
                except OSError:
                    pass  # A full pipe already guarantees a pending wakeup.

    def wait_preflight(self, timeout=None):
        """Wait for validation or failure without activating the adapter."""
        if not self.hosted:
            raise RuntimeError('Preflight is available only for hosted sessions')
        return (self.preflight_done.wait(timeout) and self.preflight_reply is not None
                and self.preflight_reply.code == 0 and not self.stopping)

    def activate(self):
        """Release one validated adapter after prior-owner cleanup."""
        with self._state_lock:
            if (not self.hosted or self.stopping or self.finished.is_set()
                    or self.preflight_reply is None or self.preflight_reply.code
                    or self.activation_requested.is_set()):
                return False
            self.activation_requested.set()
        self.wake()
        return True

    def wait_ready(self, timeout=None):
        """Ready is adapter initialization, not first controls-ready display."""
        return self.ready.wait(timeout) and self._ready_received and not self.stopping

    def wait_timeout(self):
        # Pipe readiness already wakes protocol continuations immediately. Only
        # idle countdown/preparation retries have a deadline; keyboard events
        # must not restart a full poll interval when one is almost due.
        if self.reply is not None and self.outstanding is None:
            if self.queued:
                return 0
            return min(.1, max(0, self.next_tick - self.clock()))
        return .1

    def cancel_preflight_group(self):
        """Reap a private, unactivated group while its leader remains pinned."""
        pid = self.adapter.pid

        def leader():
            identity = process_group_identity(pid)
            return identity if (identity and identity[0] == self.adapter_start
                                and identity[2:] == (pid, pid)) else None

        def members():
            result = []
            for path in Path('/proc').glob('[0-9]*/stat'):
                member_pid = int(path.parent.name)
                identity = process_group_identity(member_pid)
                if identity and identity[1] not in ('Z', 'X', 'x') and identity[2:] == (pid, pid):
                    result.append(member_pid)
            return result

        identity = leader()
        if identity is None:
            # Never guess a PGID after the original leader identity is lost.
            return 1
        if identity[1] not in ('Z', 'X', 'x'):
            os.kill(pid, signal.SIGSTOP)
            deadline = time.monotonic() + .25
            while time.monotonic() < deadline:
                identity = leader()
                if identity is None:
                    return 1
                if identity[1] in ('T', 't', 'Z', 'X', 'x'):
                    break
                time.sleep(.01)
            else:
                if leader() is None:
                    return 1
                # A blocked kernel task may not acknowledge STOP yet. Its
                # exact private leader still pins the group; queue termination
                # so it cannot resume preflight work after the I/O completes.
        if leader() is None:
            return 1
        os.killpg(pid, signal.SIGTERM)
        deadline = time.monotonic() + .5
        while time.monotonic() < deadline and any(member != pid for member in members()):
            time.sleep(.02)
        identity = leader()
        if identity is None:
            return 1
        if any(member != pid for member in members()):
            os.killpg(pid, signal.SIGKILL)
        elif identity[1] not in ('Z', 'X', 'x'):
            os.kill(pid, signal.SIGCONT)
        deadline = time.monotonic() + .5
        while time.monotonic() < deadline and members():
            time.sleep(.02)
        if members():
            if leader() is None:
                return 1
            os.killpg(pid, signal.SIGKILL)
            deadline = time.monotonic() + .5
            while time.monotonic() < deadline and members():
                time.sleep(.02)
        return 1 if members() else 0

    def shutdown(self):
        # TERM reaches the exact persistent adapter while Python remains the
        # live published owner. Existing hooks retain Menu/audio ownership.
        status = 0
        if self.adapter is not None:
            preflight_failed = 0
            if self.hosted and not self.activated:
                preflight_failed = self.cancel_preflight_group()
            elif not self.stop_signalled and not self.adapter_finishing and self.adapter.poll() is None and process_start(self.adapter.pid) == self.adapter_start:
                if self._menu_stop and self.current():
                    os.kill(self.adapter.pid, signal.SIGUSR1)
                    self.stop_signalled = True
                else:
                    self.adapter.terminate()
            status = self.adapter.wait()
            if (self.hosted and not self.activated and self._stop_requested
                    and status in (-signal.SIGTERM, -signal.SIGKILL)
                    and not self.current()):
                # A pre-owner adapter has no session teardown to complete.
                # Intentional preflight cancellation is not a startup failure.
                status = 0
            if preflight_failed:
                status = 1
            if self._finishing_receipt is not None:
                self.acknowledge(self._finishing_receipt, status == 0)
                self._finishing_receipt = None
            for receipt in self.stop_receipts:
                self.acknowledge(receipt, self.stop_signalled and status == 0)
            if self.outstanding is not None:
                self.acknowledge(self.outstanding[2], False)
                self.outstanding = None
            self.adapter.stdin.close()
            self.adapter.stdout.close()
        if self.terminal_settings is not None:
            try:
                termios.tcsetattr(self.input_stream.fileno(), termios.TCSANOW, self.terminal_settings)
            except (OSError, ValueError):
                pass  # A closed viewer cannot prevent completion receipts.
        for _, _, receipt in self.queued:
            self.acknowledge(receipt, False)
        self.selector.close()
        with self._wake_lock:
            if self._wake_pipe is not None:
                for descriptor in self._wake_pipe:
                    os.close(descriptor)
                self._wake_pipe = None
        return 0 if status == 0 else 1

    def run(self):
        result = 0
        if not self.hosted:
            signal.signal(signal.SIGTERM, self.request_stop)
            # Ctrl-C detaches through the monitor key table, not owner death.
            signal.signal(signal.SIGINT, lambda *_: None)
        try:
            if not self.stopping:
                self.start_adapter()
            while not self.stopping:
                for key, _ in self.selector.select(self.wait_timeout()):
                    if key.data == 'adapter':
                        if not self.read_adapter():
                            self.stopping = True
                            if self.hosted and not self.activated:
                                self.error = 'Adapter exited before activation'
                                result = 1
                            else:
                                result = self.adapter.wait()
                            if self.outstanding is not None:
                                _, operation, receipt = self.outstanding
                                self.acknowledge(receipt, result == 0 and operation == 'control'
                                                 and receipt is not None and receipt[0] == 'public'
                                                 and self.public_action == 'play')
                                self.outstanding = None
                    elif key.data == 'wake':
                        os.read(self._wake_pipe[0], 4096)
                    else:
                        data = os.read(self.input_stream.fileno(), 4096)
                        if data:
                            self.keyboard(data)
                        else:
                            self.selector.unregister(self.input_stream)
                if self.stopping:
                    break
                if self.hosted and self.activation_requested.is_set() and not self.activated:
                    with self._state_lock:
                        if self.stopping:
                            break
                        if process_start(self.adapter.pid) != self.adapter_start:
                            raise RuntimeError('Adapter exited before activation')
                        # Cancellation can never treat a token-written adapter
                        # as a preflight group, even if publication is pending.
                        self.activated = True
                        self.adapter.stdin.write(b'activate\n')
                self.scan_commands()
                if self.stopping:
                    break
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
            self.error = str(error)
            self.stopping = True
            result = 1
            output = self.log if hasattr(self.log, 'write') else sys.stderr
            try:
                message = 'SAM ERROR: {}\n'.format(error)
                try:
                    output.write(message)
                except TypeError:
                    output.write(message.encode('utf-8'))
            except (OSError, ValueError):
                pass  # A closed viewer must not block hosted completion.
        finally:
            try:
                if self.shutdown():
                    result = 1
            except (OSError, ValueError, RuntimeError) as error:
                self.error = str(error)
                result = 1
            finally:
                self.result = result if result >= 0 else 1
                self.preflight_done.set()
                self.ready.set()
                self.finished.set()
        return self.result


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    # The installed launcher always supplies these three literal flags. Keep
    # help and other supported CLI forms, but load argparse only for those.
    if len(argv) == 6 and argv[::2] == ['--root', '--entry', '--target']:
        return SessionEngine(argv[3], argv[1], argv[5]).run()
    import argparse
    parser = argparse.ArgumentParser()
    root = Path(__file__).resolve().parents[1]
    parser.add_argument('--root', default=str(root))
    parser.add_argument('--entry', default=str(root.parent / 'MiSTer_SAM_on.sh'))
    parser.add_argument('--target', default='')
    args = parser.parse_args(argv)
    return SessionEngine(args.entry, args.root, args.target).run()


if __name__ == '__main__':
    sys.exit(main())
