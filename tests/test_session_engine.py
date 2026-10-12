"""Warm owner protocol, selection fencing and completion regressions."""
from collections import deque
import io
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam.session_engine import Reply, SessionEngine
from sam import owner_commands


class Protocol(unittest.TestCase):
    def test_response_rejects_code_paths_and_ambiguous_fields(self):
        valid = '1\t0\tnormal\tplaying\t10\t0\t8\t-'
        self.assertEqual(Reply.parse(valid).remaining, 8)
        for value in (valid + '\t/path', valid.replace('playing', '$(touch /tmp/no)'),
                      valid.replace('\t10\t', '\t-10\t'), valid.replace('\t0\t8', '\t2\t8')):
            with self.subTest(value=value), self.assertRaises(ValueError):
                Reply.parse(value)

    def test_deadline_claim_response_can_override_expiry(self):
        with patch('sam.session_engine.process_start', return_value='123'):
            engine = SessionEngine('entry', PACKAGE / '.MiSTer_SAM', clock=lambda: 10)
        self.addCleanup(engine.selector.close)
        engine.reply = Reply('ready', 0, 'normal', 'playing', 10, False, 0, '-')
        engine.outstanding = ('1', 'timer_tick', None)
        engine.complete(Reply('1', 0, 'normal', 'playing', 10, True, 0, '-'))
        self.assertEqual(engine.next_operation, ('timer_tick', ''))
        self.assertTrue(engine.reply.paused)

    def test_navigation_burst_is_coalesced_before_successor(self):
        with patch('sam.session_engine.process_start', return_value='123'):
            engine = SessionEngine('entry', PACKAGE / '.MiSTer_SAM')
        self.addCleanup(engine.selector.close)
        engine.keyboard(b'n' * 40 + b'p')
        self.assertEqual(list(engine.queued), [('key', 'p', None)])
        engine.keyboard(b'n')
        self.assertEqual(list(engine.queued), [('key', 'n', None)])

    def test_keyboard_action_queue_is_bounded_during_a_blocked_adapter(self):
        with patch('sam.session_engine.process_start', return_value='123'):
            engine = SessionEngine('entry', PACKAGE / '.MiSTer_SAM')
        self.addCleanup(engine.selector.close)
        for _ in range(10):
            engine.keyboard(b'my' * 4096)
        self.assertLessEqual(len(engine.queued), 256)

    def test_exact_response_sequence_required(self):
        with patch('sam.session_engine.process_start', return_value='123'):
            engine = SessionEngine('entry', PACKAGE / '.MiSTer_SAM')
        self.addCleanup(engine.selector.close)
        engine.reply = Reply('ready', 0, 'normal', 'preparing', 0, False, 0, '-')
        engine.outstanding = ('3', 'launch', None)
        with self.assertRaises(RuntimeError):
            engine.complete(Reply('2', 0, 'normal', 'playing', 10, False, 10, '-'))

    def test_navigation_retained_through_boundary_is_not_reissued(self):
        with patch('sam.session_engine.process_start', return_value='123'):
            engine = SessionEngine('entry', PACKAGE / '.MiSTer_SAM')
        self.addCleanup(engine.selector.close)
        engine.reply = Reply('ready', 0, 'normal', 'playing', 0, False, 0, '-')
        engine.outstanding = ('1', 'key', None)
        engine.complete(Reply('1', 1, 'normal', 'playing', 0, False, 0, 'previous'))
        self.assertEqual(engine.next_operation, ('boundary', ''))
        engine.outstanding = ('2', 'boundary', None)
        engine.complete(Reply('2', 0, 'normal', 'preparing', 0, False, 0, 'previous'))
        self.assertEqual(engine.next_operation, ('prepare', ''))

    def test_rejected_control_preserves_current_countdown(self):
        with patch('sam.session_engine.process_start', return_value='123'):
            engine = SessionEngine('entry', PACKAGE / '.MiSTer_SAM')
        self.addCleanup(engine.selector.close)
        engine.reply = Reply('ready', 0, 'normal', 'playing', 10, False, 10, '-')
        engine.next_operation = ('timer_tick', '')
        engine.outstanding = ('1', 'control', None)
        engine.complete(Reply('1', 2, 'normal', 'playing', 10, False, 10, '-'))
        self.assertEqual(engine.next_operation, ('timer_tick', ''))


class Mailbox(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='sam-python-owner-')
        self.addCleanup(self.tmp.cleanup)
        self.runtime = Path(self.tmp.name)
        with patch.dict(os.environ, SAM_TMP_ROOT=str(self.runtime)), patch('sam.session_engine.process_start', return_value='123'):
            self.engine = SessionEngine('entry', PACKAGE / '.MiSTer_SAM', clock=lambda: 10)
        self.addCleanup(self.engine.selector.close)
        self.engine.owner_commands = owner_commands
        self.engine.ack_directory = owner_commands.acknowledgement_directory(self.runtime)
        self.engine.ack_directory.mkdir()
        self.engine.session.mkdir()
        self.engine.publish_endpoint()
        self.owner = dict(pid=str(self.engine.pid), start='123', phase='playing', launch='7')
        self.write_owner()
        self.engine.reply = Reply('ready', 0, 'normal', 'playing', 10, False, 10, '-')
        # An outstanding operation demonstrates acceptance stays responsive.
        self.engine.outstanding = ('1', 'launch', None)

    def write_owner(self):
        (self.runtime / 'session-owner').write_text(''.join('{}={}\n'.format(k, v) for k, v in self.owner.items()))

    def request(self, action='next', **changes):
        token = 'a' * 32
        request = dict(request_id=token, action=action, owner_pid=self.owner['pid'],
                       owner_start=self.owner['start'], launch=self.owner['launch'], expires=12)
        request.update(changes)
        path = self.engine.commands / ('req-' + token + '.json')
        owner_commands.atomic(path, request)
        return path, request

    def test_loading_mailbox_is_accepted_but_not_acknowledged_as_applied(self):
        path, request = self.request()
        self.engine.scan_commands()
        self.assertEqual(len(self.engine.queued), 1)
        self.assertFalse(list(self.engine.ack_directory.iterdir()))
        self.assertTrue(path.exists())

    def test_selection_changes_before_dispatch_are_rejected(self):
        path, request = self.request()
        self.engine.scan_commands()
        self.owner['launch'] = '8'
        self.write_owner()
        self.engine.adapter = type('Adapter', (), {'stdin': io.BytesIO()})()
        self.engine.outstanding = None
        self.engine.send(*self.engine.queued.popleft())
        ack = owner_commands.read(self.engine.ack_directory / owner_commands.acknowledgement_name(request))
        self.assertFalse(ack['ok'])
        self.assertEqual(ack['state'], 'failed')
        self.assertEqual(self.engine.adapter.stdin.getvalue(), b'')
        self.assertFalse(path.exists())

    def test_owner_and_nonfinite_expiry_rejected(self):
        for changes in ({'owner_start': '456'}, {'expires': float('nan')}, {'expires': 9}):
            with self.subTest(changes=changes):
                path, request = self.request(**changes)
                self.engine.scan_commands()
                self.assertFalse(self.engine.queued)
                self.assertFalse(path.exists())

    def test_applied_ack_has_complete_owner_identity(self):
        path, request = self.request()
        self.engine.scan_commands()
        receipt = self.engine.queued.popleft()[2]
        self.engine.acknowledge(receipt, True)
        ack = owner_commands.read(self.engine.ack_directory / owner_commands.acknowledgement_name(request))
        self.assertEqual((ack['owner_pid'], ack['owner_start'], ack['launch']),
                         (self.owner['pid'], self.owner['start'], '7'))
        self.assertEqual(ack['state'], 'applied')

    def test_stop_interrupts_verified_adapter_even_during_launch(self):
        path, request = self.request('stop', launch='6')
        path.rename(path.with_name('req-urgent-' + request['request_id'] + '.json'))
        for index in range(300):
            token = format(index, '032x')
            ordinary = dict(request, request_id=token, action='mute', launch='7')
            owner_commands.atomic(self.engine.commands / ('req-' + token + '.json'), ordinary)
        self.engine.adapter = type('Adapter', (), {'pid': 9999, 'poll': lambda _: None})()
        self.engine.adapter_start = '456'
        with patch('sam.session_engine.process_start', return_value='456'), patch('sam.session_engine.os.kill') as kill:
            self.engine.scan_commands()
        self.assertEqual(kill.call_count, 1)
        self.assertTrue(self.engine.stop_signalled)
        self.assertTrue(self.engine.stopping)
        self.assertFalse(list(self.engine.ack_directory.iterdir()))
        self.assertFalse(self.engine.queued)


class AdapterIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='sam-warm-adapter-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        # Windows checkouts can contain CRLF shell files. Exercise the exact
        # tracked sources in a temporary Linux checkout, as the install does.
        self.package = self.root / 'package'
        self.package.mkdir()
        shutil.copytree(PACKAGE / '.MiSTer_SAM', self.package / '.MiSTer_SAM',
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        shutil.copyfile(PACKAGE / 'MiSTer_SAM_on.sh', self.package / 'MiSTer_SAM_on.sh')
        for path in self.package.rglob('*'):
            if path.is_file() and path.suffix in ('.sh', '.py', '.ini', '.json'):
                path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
        ini = self.root / 'ini'
        ini.write_text('corelist="snes"\ncorelistall="snes"\nrating="no"\ngametimer=0\ncheck_for_new_games="no"\nmute="no"\n')
        lists = self.root / 'lists/Gamelists'
        lists.mkdir(parents=True)
        games = []
        for name in ('A', 'B', 'C', 'D'):
            game = self.root / (name + '.sfc')
            game.touch()
            games.append(str(game))
        (lists / 'snes_gamelist.txt').write_text('\n'.join(games) + '\n')
        self.runtime = self.root / 'runtime'
        self.log = self.root / 'launches'
        self.env = dict(os.environ, SAM_MODULES_OVERRIDE='controls',
                        SAM_ROOT=str(self.package / '.MiSTer_SAM'), SAM_INI=str(ini),
                        SAM_LIST_ROOT=str(self.root / 'lists'), SAM_TMP_ROOT=str(self.runtime),
                        SAM_SESSION_LIST_ROOT=str(self.root / 'session-lists'),
                        SAM_CONFIG_ROOT=str(self.root / 'config'), SAM_MISTER_ROOT=str(self.root / 'media'),
                        SAM_STATE_FILE=str(self.root / 'state'), SAM_CONTROL_STATE=str(self.root / 'state'),
                        SAM_CONTROL_ROOT=str(self.root / 'controls'), SAM_CONTROL_STORE=str(self.root / 'journal'),
                        SAM_GAME_LOG=str(self.root / 'games.log'), TEST_LOG=str(self.log))
        wrapper = self.root / 'adapter.sh'
        wrapper.write_text('''source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
source "$SAM_ROOT/lib/engine-adapter.sh"
sam_engine_parent_valid || exit 64
exec 3>&1
exec 1>&2
sam_prep(){ :; }
disable_bootrom(){ :; }
sam_cleanup(){ sam_emit display_off; }
sam_menu_delivery_begin(){ sam_menu_initial_main=fixture; sam_menu_initial_fifo=fixture; sam_menu_initial_marker=fixture; }
sam_menu_dispatch_quiesced_owner(){ printf 'menu-dispatched\\n' >> "$TEST_LOG.events"; }
sam_exit_finalize(){
    if [[ "$1" == game ]]; then sam_session_cleanup && sam_emit display_off game
    else printf 'menu-completed\\n' >> "$TEST_LOG.events"; fi
}
load_core(){
    sam_publish_phase loading || return 2
    printf '%s\\n' "$2" >> "$TEST_LOG"
    sam_emit display_launch "$3" "$2" "$1" ''
    local delay=.35
    [[ ! -e "$TEST_LOG.slow" ]] || delay=5
    sam_run_owned_command sleep "$delay"
}
sam_engine_adapter_main snes
''')
        self.output = open(self.root / 'output', 'w')
        self.addCleanup(self.output.close)
        self.process = subprocess.Popen(['python3', str(self.package / '.MiSTer_SAM/sam/session_engine.py'),
                                         '--root', str(self.package / '.MiSTer_SAM'), '--entry', str(wrapper), '--target', 'snes'],
                                        env=self.env, stdin=subprocess.PIPE, stdout=self.output, stderr=self.output)
        self.addCleanup(self.stop)

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
        try:
            self.process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stdin.close()

    def wait(self, condition):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if condition():
                return
            if self.process.poll() is not None:
                self.fail((self.root / 'output').read_text())
            time.sleep(.02)
        self.fail('Timed out: ' + (self.root / 'output').read_text())

    def ready(self):
        status = self.root / 'controls/status'
        return status.exists() and '\nready=1\n' in status.read_text()

    def launches(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_real_picker_warm_control_and_owned_cleanup(self):
        import json
        self.wait(self.ready)
        owner = dict(line.split('=', 1) for line in (self.runtime / 'session-owner').read_text().splitlines())
        self.assertEqual(owner['pid'], str(self.process.pid))
        marker = self.runtime / ('session-' + owner['pid'] + ':' + owner['start']) / 'prototype-controls'
        self.assertTrue(marker.exists())
        result = subprocess.run(['python3', str(self.package / '.MiSTer_SAM/control/samctl.py'), 'pause'],
                                env=self.env, capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(json.loads(result.stdout)['code'], 200)
        self.assertIn('paused=1', (self.root / 'controls/status').read_text())
        self.process.stdin.write(b'n' * 40)
        self.process.stdin.flush()
        self.wait(lambda: len(self.launches()) == 2)
        self.wait(self.ready)
        time.sleep(.5)
        self.assertEqual(len(self.launches()), 2)
        self.assertEqual(dict(line.split('=', 1) for line in (self.runtime / 'session-owner').read_text().splitlines())['pid'], str(self.process.pid))
        self.stop()
        self.assertFalse(list(self.runtime.glob('session-*/alive')))
        self.assertIn('active=no', (self.root / 'state').read_text())

    def slow_successor(self):
        self.wait(self.ready)
        Path(str(self.log) + '.slow').touch()
        self.process.stdin.write(b'n')
        self.process.stdin.flush()
        self.wait(lambda: len(self.launches()) == 2 and 'phase=loading' in (self.runtime / 'session-owner').read_text())

    def test_term_during_owned_launch_reaps_adapter_and_jobs(self):
        self.slow_successor()
        started = time.monotonic()
        self.stop()
        self.assertLess(time.monotonic() - started, 3)
        self.assertFalse(list(self.runtime.glob('session-*/alive')))
        self.assertFalse((self.runtime / 'cleanup-failure').exists(), (self.root / 'output').read_text())

    def test_urgent_stop_is_completed_during_owned_launch(self):
        from sam.session import read_session
        self.slow_successor()
        owner = read_session(str(self.runtime / 'session-owner'))
        started = time.monotonic()
        # The fixture replaces only Menu hardware convergence; actual launch
        # groups, picker, ownership, cleanup and completion mailbox remain real.
        receipts = []
        original_read = owner_commands.read

        def observe_receipt(path):
            value = original_read(path)
            if value is not None and Path(path).name.startswith('ack-'):
                receipts.append(value)
            return value

        with patch.object(owner_commands, 'read', side_effect=observe_receipt):
            completed = owner_commands.submit(self.runtime, owner, 'stop',
                                              lambda expected: read_session(str(self.runtime / 'session-owner')))
        evidence = dict(output=(self.root / 'output').read_text(), receipts=receipts,
                        owner=(self.runtime / 'session-owner').read_text(), exit=self.process.poll(),
                        elapsed=time.monotonic() - started,
                        failures=[(str(path), path.read_text()) for path in self.runtime.rglob('cleanup-error')])
        self.assertTrue(completed, repr(evidence))
        self.process.wait(timeout=3)
        self.assertLess(time.monotonic() - started, 3)
        self.assertFalse((self.runtime / 'cleanup-failure').exists(), (self.root / 'output').read_text())
        events = Path(str(self.log) + '.events').read_text().splitlines()
        self.assertEqual(events, ['menu-dispatched', 'menu-completed'])

    def test_parent_death_cancels_adapter_before_replacement(self):
        from sam.session_engine import process_start
        self.slow_successor()
        marker = next(self.runtime.glob('session-*/adapter-owner'))
        adapter = dict(line.split('=', 1) for line in marker.read_text().splitlines())
        self.process.kill()
        self.process.wait(timeout=3)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and process_start(int(adapter['pid'])) == adapter['start']:
            time.sleep(.02)
        self.assertIsNone(process_start(int(adapter['pid'])), (self.root / 'output').read_text())
        self.assertFalse(list(self.runtime.glob('session-*/alive')))
        self.assertFalse((self.runtime / 'cleanup-failure').exists(), (self.root / 'output').read_text())

    def test_adapter_rejects_an_unverified_parent(self):
        from sam.session_engine import process_start
        self.wait(self.ready)
        owner = (self.runtime / 'session-owner').read_bytes()
        environment = dict(self.env, SAM_ENGINE_OWNER_PID=str(os.getpid()),
                           SAM_ENGINE_OWNER_START=process_start(os.getpid()))
        result = subprocess.run(['bash', str(self.package / 'MiSTer_SAM_on.sh'), '--engine-adapter', 'snes'],
                                env=environment, capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 64)
        self.assertIn('invalid session adapter owner', result.stderr)
        self.assertEqual((self.runtime / 'session-owner').read_bytes(), owner)

    def test_public_play_completion_exits_without_an_extra_timer_request(self):
        import json
        self.wait(self.ready)
        result = subprocess.run(['python3', str(self.package / '.MiSTer_SAM/control/samctl.py'), 'play'],
                                env=self.env, capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(json.loads(result.stdout)['code'], 200)
        self.process.wait(timeout=3)
        self.assertEqual(self.process.returncode, 0, (self.root / 'output').read_text())
        self.assertFalse(list(self.runtime.glob('session-*/alive')))
        self.assertIn('game_kept=yes', (self.root / 'state').read_text())


if __name__ == '__main__':
    unittest.main()
