# SPDX-License-Identifier: GPL-3.0-or-later
"""Local command gateway; the existing Bash engine remains the session backend.

Create once in long-lived callers. No polling, daemon or countdown work occurs
here. Owner-bound inputs target a verified pane ID, never the session name.
"""
import os
import importlib.util
from pathlib import Path
import subprocess
import sys
from sam.session import read_session


def owner_key(owner):
    if not owner:
        return None
    pid = str(owner.get('pid', owner.get('owner_pid', '')))
    start = str(owner.get('start', owner.get('owner_start', '')))
    if not pid.isascii() or not pid.isdigit() or int(pid) <= 0:
        return None
    if not start.isascii() or not start.isdigit():
        return None
    return pid, start


class CommandGateway:
    KEYS = {'next': 'n', 'skip': 'n', 'previous': 'p', 'mute': 'm', 'm82_play': 'y'}
    BACKEND = {'start', 'restart', 'stop', 'kill', 'stop_owner', 'exit_to_game',
               'exit_to_menu', 'exit_to_menu_fast', 'menu_audio_restore', 'unmute', 'ignore', 'validate_start'}
    TARGETED = {'stop', 'kill', 'exit_to_menu', 'stop_owner', 'exit_to_game', 'exit_to_menu_fast', 'menu_audio_restore', 'unmute'}

    def __init__(self, owner_reader=None, runner=None, pane_reader=None,
                 entrypoint=None, root=None, process_verifier=None, launcher=None):
        self.root = Path(root or os.environ.get('SAM_ROOT') or Path(__file__).resolve().parents[1])
        self.entrypoint = str(entrypoint or os.environ.get('SAM_ENTRY') or self.root.parent / 'MiSTer_SAM_on.sh')
        self.runner = runner or subprocess.run
        self.launcher = launcher or subprocess.Popen
        self.owner_reader = owner_reader or self.read_owner
        self.pane_reader = pane_reader or self.read_panes
        self.process_verifier = process_verifier or self.verify_owner
        self._control_client = None

    def verify_owner(self, pid, start):
        # Injected readers share the same contract as read_session: return a
        # verified snapshot, or None. This keeps caller paths and tests coherent.
        return owner_key(self.owner_reader()) == (pid, start)

    def read_owner(self):
        path = Path(os.environ.get('SAM_TMP_ROOT', '/tmp/.SAM_tmp')) / 'session-owner'
        return read_session(str(path))

    def read_panes(self):
        try:
            result = self.runner(['tmux', 'list-panes', '-t', '=SAM', '-F', '#{pane_id} #{pane_pid}'],
                                 capture_output=True, text=True, timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            return []
        if result.returncode:
            return []
        return [tuple(line.split()) for line in result.stdout.splitlines() if len(line.split()) == 2]

    def current(self, expected=None):
        current = self.owner_reader()
        key = owner_key(current)
        if not key or (expected is not None and owner_key(expected) != key):
            return None
        return current if self.process_verifier(*key) else None

    def backend_argv(self, action, args=(), owner=None):
        if action not in self.BACKEND:
            raise ValueError('Unsupported backend action: ' + action)
        if action in self.TARGETED and owner is not None:
            key = owner_key(owner)
            if not key:
                raise ValueError('Invalid owner identity')
            args = key + tuple(args)
        return ['bash', self.entrypoint, '--gateway-backend', action, *map(str, args)]

    def launch_start(self, *args, if_idle=False):
        """Return the tracked launcher so MCP retains its cancellation barrier."""
        if if_idle:
            args = ('--if-idle', *args)
        return self.launcher(self.backend_argv('start', args), start_new_session=True)

    def execute(self, action, *args, owner=None):
        action = action.lower()
        # Keep the historical shell PID/start entry contract. Never silently
        # replace a caller's expected owner with the current session.
        if action in self.TARGETED and args:
            if owner is not None or len(args) != 2:
                raise ValueError('Expected owner PID and start ticks')
            owner = {'pid': str(args[0]), 'start': str(args[1])}
            args = ()
        if action in self.KEYS:
            if args:
                raise ValueError('Input command takes no arguments')
            current = self.current(owner)
            if current is None:
                return False
            if action == 'm82_play' and (current.get('phase') != 'playing'
                    or (owner is not None and 'launch' in owner and current.get('launch', '0') != owner.get('launch', '0'))):
                return False
            key = owner_key(current)
            launch = current.get('launch', '0')
            panes = [pane for pane, pid in self.pane_reader() if pid == key[0] and pane.startswith('%') and pane[1:].isdigit()]
            latest = self.current({'pid': key[0], 'start': key[1]})
            if len(panes) != 1 or latest is None:
                return False
            if action == 'm82_play' and (latest.get('phase') != 'playing' or latest.get('launch', '0') != launch):
                return False
            # Pane IDs are stable for this server: a replacement pane cannot
            # inherit the named SAM target between validation and send-keys.
            try:
                return self.runner(['tmux', 'send-keys', '-t', panes[0], self.KEYS[action]], timeout=2).returncode == 0
            except (OSError, subprocess.TimeoutExpired):
                return False
        if action in self.BACKEND:
            if action in {'stop', 'kill', 'exit_to_menu', 'unmute'}:
                current = self.current(owner)
                if owner is not None and current is None:
                    return False
                # Bind cleanup to the observed owner; shell revalidates after
                # initialization. The sentinel preserves an inactive Menu/audio
                # request without permission to act on a late replacement.
                if current is not None:
                    owner = current
                else:
                    args = ('0', '0')
            if action in self.TARGETED and action not in {'menu_audio_restore', 'stop', 'kill', 'exit_to_menu', 'unmute'}:
                current = self.current(owner)
                if current is None:
                    return False
                owner = current
            try:
                return self.runner(self.backend_argv(action, args, owner)).returncode == 0
            except (OSError, subprocess.TimeoutExpired):
                return False
        if action == 'control' or action in {'status', 'pause', 'resume', 'play'}:
            control_args = list(args) if action == 'control' else [action, *args]
            if owner is not None and control_args and control_args[0] != 'status':
                key = owner_key(owner)
                # The durable journal resolves an accepted UUID before checking
                # today's owner. Keep that replay contract; a fresh request is
                # still owner-validated by the journal CLI before submission.
                replay_requested = any(arg == '--request-id' or str(arg).startswith('--request-id=') for arg in control_args)
                if not key or (not replay_requested and self.current(owner) is None):
                    return False
                control_args += ['--owner-pid', key[0], '--owner-start', key[1]]
            return self.control(control_args) == 0
        raise ValueError('Unknown SAM command: ' + action)

    def _load_control_client(self):
        control_path = str(self.root / 'control')
        if control_path not in sys.path:
            sys.path.insert(0, control_path)
        if self._control_client is None:
            spec = importlib.util.spec_from_file_location('_sam_journal_cli', self.root / 'control' / 'samctl.py')
            client = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(client)
            self._control_client = client
        return self._control_client

    def control(self, args):
        # Preserve the existing journal and CLI selection binding exactly.
        return self._load_control_client().main(list(args))

    def menu_status(self):
        """The lease needs one control/state pair, not CLI JSON/advertising."""
        transport = self._load_control_client().transport
        current, owner = transport.status(), transport.owner()
        return dict(active=bool(owner), state=owner, control=current)

    def menu_countdown(self, action, selection):
        """An internal, acknowledged pause lease needs no durable replay log."""
        if action not in {'pause', 'resume'}:
            raise ValueError('Unsupported menu countdown action')
        expected_owner = dict(pid=selection['owner_pid'], start=selection['owner_start'])
        if self.current(expected_owner) is None:
            return False
        transport = self._load_control_client().transport
        current = transport.status()
        identity = {key: selection[key] for key in ('owner_pid', 'owner_start', 'start_time', 'rom_path')}
        if (current.get('generation') != selection['generation']
                or current.get('identity') != identity):
            return False
        request = dict(action=action, expected_seq=None, game_path=selection['rom_path'],
                       request_id=transport.new_request_id())
        transport.validate(dict(request, expected_seq=0))
        code, _ = transport.submit(request, expected=current, journaled=False)
        return code == 200
