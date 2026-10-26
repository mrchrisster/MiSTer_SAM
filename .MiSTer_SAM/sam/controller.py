# SPDX-License-Identifier: GPL-3.0-or-later
"""MCP-local session host and bounded literal CLI mailbox.

Only the private same-UID CLI mailbox accepts environment overrides. Public
Monitor controls retain their existing owner/selection-bound journal gateway.
"""
from contextlib import contextmanager
import os
from pathlib import Path
import queue
import re
import select
import signal
import stat
import threading
import time

MAX_RECORD = 16384
MAX_PENDING = 64
MAX_RECEIPTS = 128
ACTIONS = frozenset(('start', 'restart', 'next', 'previous', 'mute', 'm82_play',
                     'pause', 'resume', 'play', 'ignore', 'stop', 'kill',
                     'exit_to_menu', 'exit_to_game', 'menu_hold', 'menu_release'))
URGENT = frozenset(('stop', 'kill', 'exit_to_menu', 'exit_to_game'))
FIELDS = frozenset(('version', 'id', 'action', 'target', 'if_idle', 'owner_pid',
                    'owner_start', 'launch', 'host_pid', 'host_start',
                    'client_pid', 'client_start', 'expires', 'pending_id', 'pending_epoch'))
ENVIRONMENT = frozenset(('SAM_INI', 'SAM_LIST_ROOT', 'SAM_SESSION_LIST_ROOT',
                         'SAM_EXIT_TRACE', 'SAM_ENTRY', 'SAM_START_FROM_UI',
                         'SAM_START_FEEDBACK_TIMEOUT', 'SAM_CONFIG_ROOT',
                         'SAM_MISTER_ROOT', 'SAM_STATE_FILE', 'SAM_GAME_LOG'))
TOKEN = re.compile(r'^[0-9a-f]{32}$')
DECIMAL = re.compile(r'^(0|[1-9][0-9]{0,19})$')


def process_start(pid):
    try:
        fields = Path('/proc/{}/stat'.format(pid)).read_text().rsplit(') ', 1)[1].split()
        return fields[19] if fields[0] not in ('Z', 'X', 'x') else None
    except (OSError, ValueError, IndexError):
        return None


def read_record(path, uid=None):
    descriptor = None
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)
                             | getattr(os, 'O_NONBLOCK', 0))
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or (uid is not None and
                (metadata.st_uid != uid or metadata.st_mode & 0o077)):
            return None
        data = os.read(descriptor, MAX_RECORD + 1)
        if len(data) > MAX_RECORD:
            return None
        result = {}
        for line in data.decode('utf-8').splitlines():
            if '=' not in line:
                return None
            key, value = line.split('=', 1)
            if key in result or not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', key) or '\x00' in value:
                return None
            result[key] = value
        return result
    except (OSError, UnicodeError):
        return None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def atomic_record(path, record):
    data = ''.join('{}={}\n'.format(key, value) for key, value in record.items())
    if len(data.encode('utf-8')) > MAX_RECORD or any('\n' in str(value) or '\r' in str(value)
                                                   for value in record.values()):
        raise ValueError('Invalid literal record')
    temporary = path.with_name(path.name + '.tmp.' + str(os.getpid()) + '.' + str(threading.get_ident()))
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w', encoding='utf-8') as target:
            target.write(data)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def owner_key(owner):
    return (str(owner['pid']), str(owner['start'])) if owner else None


class _MenuGateway:
    """One engine's selection view; replacing the engine cannot transfer a lease."""
    def __init__(self, controller, engine, session_type, launch):
        self.controller, self.engine = controller, engine
        self.session_type, self.launch = session_type, launch

    def read_owner(self):
        return self.controller.owner_reader()

    def menu_status(self):
        owner = self.read_owner()
        if owner is None:
            return dict(active=False, state={}, control={})
        if self.engine is None:
            return self.controller.gateway.menu_status()
        if owner_key(owner) != (str(self.engine.pid), str(self.engine.start)) or self.engine.control is None:
            return dict(active=False, state={}, control={})
        control, state = self.engine.control.status(), self.engine.control.owner()
        return dict(active=bool(state), state=state, control=control)

    def menu_countdown(self, action, selection):
        if self.engine is None:
            return self.controller.gateway.menu_countdown(action, selection)
        owner, before = self.read_owner(), self.menu_status()
        if (owner_key(owner) != (str(self.engine.pid), str(self.engine.start)) or
            owner.get('launch', '0') != self.launch or
            self.session_type.selection(owner, before) != selection):
            return False
        if not self.engine.queue_local(action, owner, launch=self.launch, timeout=5):
            return False
        after_owner, after = self.read_owner(), self.menu_status()
        return (owner_key(after_owner) == owner_key(owner) and
                after_owner.get('launch', '0') == self.launch and
                self.session_type.selection(after_owner, after) == selection and
                after.get('control', {}).get('paused') is (action == 'pause'))


class Controller:
    def __init__(self, root=None, entry=None, runtime=None, *, engine_factory=None,
                 gateway=None, owner_reader=None, menu_active=None, admission=None,
                 identity_reader=process_start, clock=time.monotonic, wall_clock=time.time):
        self.root = Path(root or os.environ.get('SAM_ROOT', '/media/fat/Scripts/.MiSTer_SAM')).resolve()
        self.entry = Path(entry or self.root.parent / 'MiSTer_SAM_on.sh').resolve()
        self.runtime = Path(runtime or os.environ.get('SAM_TMP_ROOT', '/tmp/.SAM_tmp'))
        self.directory = self.runtime / 'command-host'
        self.requests, self.receipts = self.directory / 'requests', self.directory / 'receipts'
        self.endpoint = self.directory / 'endpoint'
        self.pid, self.start_ticks = os.getpid(), identity_reader(os.getpid())
        self.uid = os.geteuid() if hasattr(os, 'geteuid') else None
        self.identity_reader, self.clock, self.wall_clock = identity_reader, clock, wall_clock
        self.engine_factory, self.gateway = engine_factory, gateway
        self.owner_reader = owner_reader or self._owner
        self.menu_active = menu_active or self._menu_active
        self.admission = admission or self._admission
        self.closed = threading.Event()
        self.wake_read, self.wake_write = os.pipe()
        os.set_blocking(self.wake_read, False)
        os.set_blocking(self.wake_write, False)
        self.pipe_closing = False
        self.retired_pipe = []
        self.start_queue, self.control_queue, self.urgent_queue = (queue.Queue(MAX_PENDING),
                                                                queue.Queue(MAX_PENDING), queue.Queue(8))
        self.threads, self.claimed = [], set()
        self.claim_lock, self.engine_lock = threading.Lock(), threading.Lock()
        self.engine = self.engine_thread = None
        self.log = None
        self.host_lock = None
        self.running = False
        self.advertised = False
        self.next_maintenance = self.clock() + 30
        self.start_epoch = 0
        self.pending = None
        self.menu_session_type = None

    def _owner(self):
        from sam.session import read_session
        return read_session(str(self.runtime / 'session-owner'))

    def _menu_active(self):
        from sam.menu_session import active
        return active(Path(os.environ.get('SAM_MENU_TMP_ROOT', '/tmp/.SAM_menu')) / 'menu.lock')

    @contextmanager
    def _admission(self):
        import fcntl
        descriptor = os.open(self.runtime / 'session-start.lock', os.O_CREAT | os.O_RDWR
                             | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        deadline = self.clock() + 15
        try:
            while True:
                try:
                    fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if self.closed.is_set() or self.clock() >= deadline:
                        raise RuntimeError('Start admission is busy')
                    self.closed.wait(.05)
            yield
        finally:
            os.close(descriptor)

    def start(self):
        if self.running:
            return self
        if self.start_ticks is None:
            raise RuntimeError('Controller requires a live Linux identity')
        import fcntl
        self.runtime.mkdir(parents=True, exist_ok=True)
        for directory in (self.directory, self.requests, self.receipts):
            directory.mkdir(mode=0o700, exist_ok=True)
            metadata = directory.lstat()
            if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != self.uid:
                raise RuntimeError('Invalid private controller directory')
            os.chmod(directory, 0o700)
        self.host_lock = os.open(self.directory / 'host.lock', os.O_CREAT | os.O_RDWR
                                 | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        try:
            fcntl.flock(self.host_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            # Called on MCP's main thread. Keep this benign handler after close:
            # a client already checking the old endpoint may send one late wake.
            signal.signal(signal.SIGUSR2, lambda *_: self.wake())
            if self.engine_factory is None:
                from sam.session_engine import SessionEngine, control_for
                control_for(self.root, dict(os.environ))
                self.engine_factory = SessionEngine
            if self.gateway is None:
                from sam.commands import CommandGateway
                self.gateway = CommandGateway(root=self.root, entrypoint=str(self.entry))
            self.log = open(self.directory / 'session.log', 'a', buffering=1)
            self.running = True
            self._publish_epoch()
            for target in (self._serve, self._starts, self._controls, self._urgent):
                thread = threading.Thread(target=target, name='SAM-' + target.__name__, daemon=True)
                self.threads.append(thread)
                thread.start()
            atomic_record(self.endpoint, dict(version=1, pid=self.pid, start=self.start_ticks,
                                              root=str(self.root), entry=str(self.entry),
                                              mcp=str(self.root / 'MiSTer_SAM_MCP.py'), menu_leases=1))
            self.advertised = True
            self.wake()
            return self
        except BaseException:
            self.close()
            raise

    def wake(self):
        # This also runs in SIGUSR2's raw handler: no Python locks or Events.
        descriptor = self.wake_write
        if descriptor is None or self.pipe_closing:
            return
        try:
            os.write(descriptor, b'x')
        except OSError:
            pass  # A full pipe already represents a coalesced wake.

    def _valid(self, request):
        if not isinstance(request, dict) or not FIELDS.issubset(request) or any(
                key not in FIELDS and (not key.startswith('env_') or key[4:] not in ENVIRONMENT)
                for key in request):
            return False
        if request['version'] != '1' or not TOKEN.fullmatch(request['id']) or request['action'] not in ACTIONS:
            return False
        if (request['host_pid'], request['host_start']) != (str(self.pid), self.start_ticks):
            return False
        if any(not DECIMAL.fullmatch(request[key]) for key in
               ('owner_pid', 'owner_start', 'launch', 'client_pid', 'client_start', 'expires')):
            return False
        if request['client_pid'] == '0' or request['if_idle'] not in ('0', '1'):
            return False
        if (request['pending_id'] and not TOKEN.fullmatch(request['pending_id'])) or not DECIMAL.fullmatch(request['pending_epoch']):
            return False
        if not self.wall_clock() - 300 <= int(request['expires']) <= self.wall_clock() + 600:
            return False
        if int(request['expires']) < self.wall_clock():
            return False
        target = request['target']
        if request['action'] == 'menu_release':
            if not re.fullmatch(r'[A-Za-z0-9_=-]{1,8192}', target):
                return False
        elif target and not re.fullmatch(r'[a-z0-9_]{1,32}', target.strip().lower()):
            return False
        if request['action'] not in ('start', 'restart', 'menu_release') and target:
            return False
        if request['action'] not in ('start', 'restart') and request['if_idle'] != '0':
            return False
        for key, value in request.items():
            maximum = 8192 if key == 'target' and request['action'] == 'menu_release' else 2048
            if len(value) > maximum or '\r' in value or '\n' in value or '\x00' in value:
                return False
            if key == 'env_SAM_START_FROM_UI' and value not in ('0', '1'):
                return False
            if key == 'env_SAM_START_FEEDBACK_TIMEOUT' and not re.fullmatch(r'[0-9]{1,3}', value):
                return False
            if key == 'env_SAM_ENTRY':
                path = Path(value)
                try:
                    metadata = path.lstat()
                    if not path.is_absolute() or not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != self.uid:
                        return False
                except OSError:
                    return False
        return self._client_alive(request)

    def _client_alive(self, request):
        return (not self.closed.is_set() and
                int(request['expires']) >= self.wall_clock() and
                self.identity_reader(int(request['client_pid'])) == request['client_start'])

    def _reply(self, request, state, ok, error='', **extra):
        error = str(error).replace('\n', ' ').replace('\r', ' ')[:512]
        record = dict(version=1, id=request['id'], host_pid=self.pid, host_start=self.start_ticks,
                      state=state, ok=int(bool(ok)), error=error, **extra)
        for attempt in range(3):
            try:
                atomic_record(self.receipts / ('ack-' + request['id']), record)
                return
            except OSError:
                # A receipt reader can briefly prevent replacement on Windows
                # fixture hosts. Never turn that into a false applied result.
                if attempt < 2:
                    self.closed.wait(.01)

    def _finish(self, request, ok, error='', **extra):
        if '_local_done' in request:
            request['_local_result'].append(bool(ok))
            request['_local_done'].set()
            return
        self._reply(request, 'applied' if ok else 'failed', ok, error, **extra)
        with self.claim_lock:
            self.claimed.discard(request['id'])

    def _prune(self):
        records = []
        for path in self.receipts.glob('ack-*'):
            if not TOKEN.fullmatch(path.name[4:]):
                continue
            try:
                metadata = path.lstat()
                if stat.S_ISREG(metadata.st_mode):
                    records.append((metadata.st_mtime, path))
            except OSError:
                pass
        for index, (modified, path) in enumerate(sorted(records, reverse=True)):
            if index >= MAX_RECEIPTS or modified < self.wall_clock() - 600:
                path.unlink(missing_ok=True)
        # stdout history is optional RAM viewing data, not the diagnostic journal.
        try:
            if self.log and os.fstat(self.log.fileno()).st_size > 1024 * 1024:
                self.log.seek(0)
                self.log.truncate()
        except OSError:
            pass

    def _serve(self):
        while not self.closed.is_set():
            try:
                select.select([self.wake_read], [], [], max(0, self.next_maintenance - self.clock()))
            except (OSError, ValueError):
                # Windows' select only supports sockets. This is an offline
                # fixture fallback; installed Linux MCP uses the wake pipe.
                if os.name != 'nt':
                    break
                self.closed.wait(.05)
            try:
                while os.read(self.wake_read, 4096):
                    pass
            except OSError:
                pass
            if self.closed.is_set():
                break
            try:
                paths = [path for path in self.requests.glob('req-*') if TOKEN.fullmatch(path.name[4:])]
                if paths or self.clock() >= self.next_maintenance:
                    self._prune()
                    self.next_maintenance = self.clock() + 30
                for path in sorted(paths)[:MAX_PENDING]:
                    request = read_record(path, self.uid)
                    if not self._valid(request) or path.name != 'req-' + request['id']:
                        path.unlink(missing_ok=True)
                        continue
                    completed = read_record(self.receipts / ('ack-' + request['id']), self.uid)
                    if (completed and completed.get('state') in ('applied', 'failed') and
                        (completed.get('id'), completed.get('host_pid'), completed.get('host_start')) ==
                        (request['id'], str(self.pid), self.start_ticks)):
                        path.unlink(missing_ok=True)
                        continue
                    if request['action'] in ('start', 'restart'):
                        with self.engine_lock:
                            request['_start_epoch'] = int(request['pending_epoch'])
                            cancelled = request['_start_epoch'] != self.start_epoch
                        if cancelled:
                            self._finish(request, False, 'Start cancelled by Stop')
                            path.unlink(missing_ok=True)
                            continue
                    with self.claim_lock:
                        duplicate = request['id'] in self.claimed
                        if not duplicate:
                            self.claimed.add(request['id'])
                    if duplicate:
                        path.unlink(missing_ok=True)
                        continue
                    destination = (self.start_queue if request['action'] in ('start', 'restart') else
                                   self.urgent_queue if request['action'] in URGENT else self.control_queue)
                    self._reply(request, 'accepted', False)
                    try:
                        destination.put_nowait(request)
                    except queue.Full:
                        self._finish(request, False, 'Controller queue is full')
                    path.unlink(missing_ok=True)
            except OSError:
                continue

    def _start_engine(self, request):
        if self.engine_factory is None:
            from sam.session_engine import SessionEngine
            factory = SessionEngine
        else:
            factory = self.engine_factory
        environment = dict(os.environ, SAM_ROOT=str(self.root), SAM_TMP_ROOT=str(self.runtime))
        environment.update({key[4:]: value for key, value in request.items() if key.startswith('env_')})
        entry = environment.get('SAM_ENTRY', str(self.entry))
        engine = factory(entry, self.root, request['target'].strip().lower(), hosted=True,
                         environment=environment, log=self.log, input_stream=None)
        thread = threading.Thread(target=engine.run, name='SAM-session', daemon=True)
        thread.start()
        return engine, thread

    def _publish_epoch(self):
        atomic_record(self.directory / 'generation', dict(epoch=self.start_epoch,
                      host_pid=self.pid, host_start=self.start_ticks))

    def _cancel_starts(self):  # caller holds engine_lock
        self.start_epoch += 1
        self._publish_epoch()

    def _wait_preflight(self, engine, request, epoch):
        deadline = self.clock() + 45
        while self.clock() < deadline and self._client_alive(request) and epoch == self.start_epoch:
            if engine.wait_preflight(.05):
                return True
            if engine.finished.is_set():
                break
        return False

    def _stop_engine(self, engine, thread, *, menu=False, timeout=25):
        engine.stop(menu=menu)
        thread.join(timeout)
        return not thread.is_alive() and engine.result == 0

    def _starts(self):
        while not self.closed.is_set():
            request = self.start_queue.get()
            if request is None:
                break
            candidate = candidate_thread = None
            activated = False
            epoch = request.get('_start_epoch', self.start_epoch)
            try:
                with self.admission():
                    if not self._client_alive(request) or epoch != self.start_epoch:
                        raise RuntimeError('Start caller exited before admission')
                    if self.menu_active():
                        if request['if_idle'] == '1':
                            self._finish(request, True, message='Automatic start skipped: menu is open')
                            continue
                        raise RuntimeError('SAM menu is open; close it before starting')
                    current = self.owner_reader()
                    with self.engine_lock:
                        old, old_thread = self.engine, self.engine_thread
                    own_active = old is not None and not old.finished.is_set()
                    if request['if_idle'] == '1' and (current or own_active):
                        self._finish(request, True, message='SAM is already running; automatic start skipped')
                        continue
                    if current and (not own_active or owner_key(current) != (str(old.pid), str(old.start))):
                        raise RuntimeError('A foreign session owns SAM; stop it before starting')
                    candidate, candidate_thread = self._start_engine(request)
                    with self.engine_lock:
                        self.pending = (request['id'], epoch, candidate, candidate_thread,
                                        owner_key(current))
                        atomic_record(self.directory / 'pending', dict(id=request['id'], epoch=epoch,
                                      host_pid=self.pid, host_start=self.start_ticks))
                    if not self._wait_preflight(candidate, request, epoch):
                        raise RuntimeError(candidate.error or 'Start preflight failed or was cancelled')
                    if not self._client_alive(request) or epoch != self.start_epoch:
                        raise RuntimeError('Start caller exited before replacement')
                    if own_active and not self._stop_engine(old, old_thread, menu=True):
                        raise RuntimeError('Previous session cleanup did not complete')
                    if not self._client_alive(request) or epoch != self.start_epoch:
                        raise RuntimeError('Start caller exited before activation')
                    if self.menu_active() or self.owner_reader():
                        raise RuntimeError('Session/menu changed before activation')
                    if request['if_idle'] == '0':
                        (self.runtime / 'autostart-empty.json').unlink(missing_ok=True)
                    with self.engine_lock:
                        if epoch != self.start_epoch:
                            raise RuntimeError('Start cancelled before activation')
                        self.engine, self.engine_thread = candidate, candidate_thread
                        if not candidate.activate():
                            raise RuntimeError('Validated adapter refused activation')
                    activated = True
                    deadline = self.clock() + 30
                    while self.clock() < deadline and self._client_alive(request):
                        current = self.owner_reader()
                        if owner_key(current) == (str(candidate.pid), str(candidate.start)):
                            atomic_record(self.runtime / 'hosted-controller',
                                          dict(owner_pid=candidate.pid, owner_start=candidate.start,
                                               controller_pid=self.pid, controller_start=self.start_ticks,
                                               log=str(self.directory / 'session.log')))
                            break
                        if candidate.finished.wait(.05):
                            raise RuntimeError(candidate.error or 'Session exited before owner publication')
                    else:
                        raise RuntimeError('Start cancelled or owner publication timed out')
                # Admission protects replacement/publication, not a lengthy
                # explicit-core first launch. Controls remain independently live.
                if request['target']:
                    self._single_feedback(request, candidate)
                else:
                    self._finish(request, True, owner_pid=candidate.pid, owner_start=candidate.start,
                                 message='SAM session started. Use m monitor to view it')
                candidate = None
            except Exception as error:
                if candidate is not None:
                    self._stop_engine(candidate, candidate_thread, menu=activated)
                self._finish(request, False, error)
            finally:
                with self.engine_lock:
                    if self.pending and self.pending[0] == request['id']:
                        self.pending = None
                        (self.directory / 'pending').unlink(missing_ok=True)

    def _single_feedback(self, request, engine):
        duration = int(request.get('env_SAM_START_FEEDBACK_TIMEOUT', '180'))
        deadline = self.clock() + duration
        while self.clock() < deadline and self._client_alive(request):
            owner = self.owner_reader()
            if owner_key(owner) != (str(engine.pid), str(engine.start)):
                raise RuntimeError(engine.error or 'Session changed before a game launched')
            error_path = self.runtime / ('session-{}:{}'.format(engine.pid, engine.start)) / 'error'
            try:
                error = error_path.read_text()[:512].strip()
            except OSError:
                error = ''
            if error:
                raise RuntimeError(error)
            if owner.get('phase') in ('playing', 'video'):
                self._finish(request, True, owner_pid=engine.pid, owner_start=engine.start,
                             message='SAM running: ' + request['target'])
                return
            if engine.finished.wait(.05):
                raise RuntimeError(engine.error or 'Session exited before a game launched')
        if not self._client_alive(request):
            raise RuntimeError('Start caller exited during preparation')
        self._finish(request, True, owner_pid=engine.pid, owner_start=engine.start,
                     message='SAM is still preparing ' + request['target'] + '; use m monitor for progress')

    def _handle_control(self, request):
        if request['action'] in ('menu_hold', 'menu_release'):
            self._handle_menu(request)
            return
        expected = (request['owner_pid'], request['owner_start'])
        current = self.owner_reader()
        if expected == ('0', '0') and current is None and request['action'] in ('stop', 'kill', 'exit_to_menu'):
            with self.engine_lock:
                pending = self.pending
                if (self.owner_reader() is not None or pending is None or
                    (request.get('pending_id'), request.get('pending_epoch')) != (pending[0], str(pending[1]))):
                    self._finish(request, False, 'Pending start changed')
                    return
                self._cancel_starts()
            okay = self._stop_engine(pending[2], pending[3], menu=True)
            self._finish(request, okay, '' if okay else 'Pending start cleanup failed')
            return
        if owner_key(current) != expected:
            # A matching old-owner Stop during its replacement's preflight or
            # cleanup cancels that exact pending handoff. It cannot target a
            # separately published new owner after the old record disappears.
            with self.engine_lock:
                pending = self.pending
                cancelling_handoff = (current is None and request['action'] in ('stop', 'kill', 'exit_to_menu')
                                      and pending is not None and pending[4] == expected)
                if cancelling_handoff:
                    self._cancel_starts()
            if cancelling_handoff:
                okay = self._stop_engine(pending[2], pending[3], menu=True)
                self._finish(request, okay, '' if okay else 'Pending start cleanup failed')
            else:
                self._finish(request, False, 'Session is inactive or changed')
            return
        if request['action'] not in URGENT and current.get('launch', '0') != request['launch']:
            self._finish(request, False, 'Selection changed')
            return
        with self.engine_lock:
            engine, thread = self.engine, self.engine_thread
            pending = None
            if request['action'] in ('stop', 'kill', 'exit_to_menu'):
                self._cancel_starts()
                pending = self.pending
        if pending:
            pending[2].stop(menu=True)
        if request['action'] in ('stop', 'kill', 'exit_to_menu') and engine is not None and (
                str(engine.pid), str(engine.start)) == expected:
            okay = self._stop_engine(engine, thread, menu=True)
        else:
            if engine is not None and (str(engine.pid), str(engine.start)) == expected:
                okay = engine.queue_local(request['action'], current, launch=request['launch'],
                                          timeout=25 if request['action'] in ('play', 'exit_to_game') else 5)
            elif request['action'] == 'ignore':
                okay = self.gateway.execute('control', 'ignore', owner=current)
            else:
                okay = self.gateway.execute(request['action'], owner=current)
        self._finish(request, okay, '' if okay else 'Command failed or session changed')

    def _handle_menu(self, request):
        if self.menu_session_type is None:
            from sam.menu_session import MenuSession

            class ResidentMenuSession(MenuSession):
                # The scoped gateway never prints. Avoid MenuSession's standalone
                # helper stdout redirection affecting unrelated MCP threads.
                def _command(self, action, selection):
                    return self.gateway.menu_countdown(action, selection)

            self.menu_session_type = ResidentMenuSession
        owner = self.owner_reader()
        if request['action'] == 'menu_hold':
            expected = (request['owner_pid'], request['owner_start'])
            actual = owner_key(owner) or ('0', '0')
            if actual != expected or (owner and owner.get('launch', '0') != request['launch']):
                self._finish(request, False, 'SAM changed while opening the menu. Retry the menu.')
                return
        with self.engine_lock:
            engine = self.engine
        if engine is not None and owner_key(owner) != (str(engine.pid), str(engine.start)):
            engine = None
        gateway = _MenuGateway(self, engine, self.menu_session_type,
                               owner.get('launch', '0') if owner else '0')
        session = self.menu_session_type(gateway, gateway.read_owner, gateway.menu_status)
        if request['action'] == 'menu_hold':
            token = session.hold()
            if len(token) > 8192:
                raise RuntimeError('SAM menu pause token exceeds the transport limit')
            self._finish(request, True, token=token)
        else:
            session.release(request['target'])
            self._finish(request, True)

    def _control_loop(self, source):
        while not self.closed.is_set():
            request = source.get()
            if request is None:
                break
            try:
                if not self._client_alive(request):
                    self._finish(request, False, 'Command caller exited')
                else:
                    self._handle_control(request)
            except Exception as error:
                self._finish(request, False, error)

    def _controls(self):
        self._control_loop(self.control_queue)

    def _urgent(self):
        self._control_loop(self.urgent_queue)

    def execute_local(self, action, *args, owner=None):
        """Applied result for MCP callbacks; no CLI/controller mailbox files.

        Ordinary controls use the hosted engine's selection-bound Event queue.
        Urgent hosted Stop reaches the exact adapter directly. Foreign/extended
        API calls retain the verified legacy/public journal gateway.
        """
        action = action.lower()
        if action == 'control' and len(args) == 1 and args[0] in ('next', 'pause', 'resume', 'play', 'ignore'):
            action, args = args[0], ()
        if action in URGENT and len(args) == 2 and owner is None:
            owner, args = dict(pid=str(args[0]), start=str(args[1])), ()
        current = self.owner_reader()
        expected = owner if owner is not None else current
        with self.engine_lock:
            engine = self.engine
            pending = self.pending
        pending_only = (current is None and pending is not None and action in ('stop', 'kill', 'exit_to_menu')
                        and (expected is None or owner_key(expected) == ('0', '0') or pending[4] == owner_key(expected)))
        if (args or action not in ACTIONS or action in ('start', 'restart') or engine is None
                or owner_key(current) != (str(engine.pid), str(engine.start))) and not pending_only:
            return self.gateway.execute(action, *args, owner=owner)
        if self.closed.is_set() or (not pending_only and owner_key(expected) != owner_key(current)):
            return False
        if pending_only and expected is None:
            expected = dict(pid='0', start='0')
        done, result = threading.Event(), []
        request = dict(action=action, owner_pid=str(expected['pid']), owner_start=str(expected['start']),
                       launch=expected.get('launch', current.get('launch', '0')),
                       client_pid=str(self.pid), client_start=self.start_ticks,
                       expires=str(int(self.wall_clock()) + (30 if action in URGENT else 5)),
                       pending_id=pending[0] if pending_only else '',
                       pending_epoch=str(pending[1]) if pending_only else '0',
                       _local_done=done, _local_result=result)
        destination = self.urgent_queue if action in URGENT else self.control_queue
        try:
            destination.put_nowait(request)
        except queue.Full:
            return False
        return done.wait(30 if action in URGENT else 5) and result == [True]

    def close(self):
        # Revoke admission before asking the exact hosted owner to clean up.
        marker = read_record(self.endpoint)
        if self.advertised and marker and (marker.get('pid'), marker.get('start')) == (str(self.pid), self.start_ticks):
            self.endpoint.unlink(missing_ok=True)
        hosted = read_record(self.runtime / 'hosted-controller')
        if self.advertised and hosted and (hosted.get('controller_pid'), hosted.get('controller_start')) == (str(self.pid), self.start_ticks):
            (self.runtime / 'hosted-controller').unlink(missing_ok=True)
        self.closed.set()
        self.wake()
        for source in (self.start_queue, self.control_queue, self.urgent_queue):
            try:
                source.put_nowait(None)
            except queue.Full:
                pass  # A full queue's consumer is not blocked on get().
        with self.engine_lock:
            engine, thread = self.engine, self.engine_thread
        okay = True
        if engine is not None and thread is not None and thread.is_alive():
            okay = self._stop_engine(engine, thread, menu=True)
        for thread in self.threads:
            if thread is not threading.current_thread():
                thread.join(2)
        if self.log is not None:
            self.log.close()
            self.log = None
        if self.host_lock is not None:
            os.close(self.host_lock)
            self.host_lock = None
        self.running = False
        self.advertised = False
        # A raw signal handler or another thread may already have copied the
        # old descriptor. Retain it while this controller can still be called;
        # the registered benign handler keeps it alive until MCP process exit.
        self.pipe_closing = True
        descriptors = (self.wake_read, self.wake_write)
        self.wake_read = self.wake_write = None
        for descriptor in descriptors:
            if descriptor is not None:
                self.retired_pipe.append(descriptor)
        return okay

    def __del__(self):
        # An in-flight wake retains self, so these descriptors cannot be reused
        # until that call has returned. On installed MCP the signal callback
        # retains self for its remaining process lifetime (two bounded FDs).
        for descriptor in getattr(self, 'retired_pipe', ()):
            try:
                os.close(descriptor)
            except Exception:
                pass
