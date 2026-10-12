"""Isolated runnable engine research; mock events are not physical inputs."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
try:
    import fcntl
except ImportError:
    fcntl = None
from paths import PACKAGE

PROTOTYPE = PACKAGE / 'research/session-engine'


def ticks(pid):
    return Path('/proc', str(pid), 'stat').read_text().rsplit(') ', 1)[1].split()[19]


class Fixture:
    def __init__(self, mode='normal', prep='3', launch='0', play=None, source=None, engine_file='engine.sh'):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-session-research-', dir='/tmp')
        self.root = Path(self.temp.name)
        (self.root / 'RESEARCH_MOCK_ONLY').write_text('SAM_SESSION_RESEARCH_V1\n')
        self.source = source or PROTOTYPE
        self.env = dict(os.environ, TMP_ROOT=str(self.root))
        if play is not None:
            self.env['PLAY_SECONDS'] = str(play)
        self.output = open(self.root / 'output.log', 'w')
        self.started = time.monotonic()
        interpreter = sys.executable if engine_file.endswith('.py') else 'bash'
        self.process = subprocess.Popen([interpreter, str(self.source / engine_file), mode, str(prep), str(launch)],
                                        env=self.env, stdout=self.output, stderr=self.output,
                                        start_new_session=True)
        self.closed = False
        try:
            self.wait(lambda: (self.root / 'state.tsv').exists())
            self.engine_ticks = ticks(self.process.pid)
        except Exception:
            self.close()
            raise

    def wait(self, condition, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if condition():
                return
            if self.process.poll() is not None:
                raise AssertionError('Engine exited: ' + (self.root / 'output.log').read_text())
            time.sleep(.005)
        raise AssertionError('Timed out: ' + (self.root / 'output.log').read_text() + '\n' + str(self.state()))

    def state(self):
        try:
            return dict(line.split('\t', 1) for line in (self.root / 'state.tsv').read_text().splitlines())
        except (OSError, ValueError):
            return {}

    def events(self):
        return [line.split('\t', 4) for line in (self.root / 'events.tsv').read_text().splitlines()]

    def command(self, action, *args, wait=True):
        begin = time.monotonic()
        result = subprocess.run(['bash', str(self.source / 'command.sh'), action, *map(str, args)],
                                env=self.env, text=True, capture_output=True, timeout=3)
        if result.returncode:
            raise AssertionError('CLI rejected %s: %s %s' % (action, result.stdout, result.stderr))
        request = result.stdout.strip()
        if not wait:
            return request
        self.wait(lambda: self.reply(request) is not None)
        reply = self.reply(request)
        return reply, time.monotonic() - begin

    def reply(self, request):
        try:
            text = (self.root / 'receipts' / (request + '.applied')).read_text()
        except OSError:
            return None
        fields = text.rstrip('\n').split('\t', 2)
        if text.endswith('\n') and len(fields) == 3 and fields[1] in ('ok', 'rejected'):
            return fields
        return None

    def enqueue(self, request, action, owner=None, epoch=None, args=('-', '-', '-'), urgent=False):
        state = self.state()
        values = owner or (state['engine_pid'], state['engine_start'], state['session_token'])
        selected_epoch = state['session_epoch'] if epoch is None else str(epoch)
        data = '\t'.join((request, *values, selected_epoch, action, *args)) + '\n'
        temp = self.root / 'inbox' / ('.' + request + '.tmp')
        temp.write_text(data)
        temp.replace(self.root / 'inbox' / (('urgent.' if urgent else 'control.') + request + '.req'))

    def applied(self, request):
        self.wait(lambda: self.reply(request) is not None)
        return self.reply(request)

    def start(self):
        self.command('start')
        self.wait(lambda: self.state().get('phase') in ('demonstration', 'bios', 'commercial', 'playing'))

    def close(self):
        if self.closed:
            return
        self.closed = True
        try:
            if self.process.poll() is None:
                try:
                    self.command('shutdown')
                    self.process.wait(timeout=3)
                except (AssertionError, subprocess.TimeoutExpired):
                    self.process.terminate()
                    try:
                        self.process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        self.process.kill()
                        self.process.wait()
        finally:
            self.output.close()
            self.temp.cleanup()


@unittest.skipUnless(os.name == 'posix' and Path('/proc').exists(), 'Bash/Linux isolated process fixtures')
class EngineResearchTests(unittest.TestCase):
    engine_file = 'engine.sh'

    def fixture(self, **options):
        value = Fixture(engine_file=self.engine_file, **options)
        self.addCleanup(value.close)
        return value

    def test_slow_preparation_does_not_delay_first_item_or_stop(self):
        f = self.fixture(prep='3')
        begin = time.monotonic()
        f.start()
        self.assertLess(time.monotonic() - begin, 1.5)
        reply, elapsed = f.command('stop')
        self.assertEqual(reply[1], 'ok')
        self.assertLess(elapsed, .75)
        f.wait(lambda: f.state().get('active') == '0')
        self.assertTrue(any(row[1] == 'sim_menu_intent' for row in f.events()))

    def test_stop_during_mock_loading_prevents_late_application(self):
        f = self.fixture(launch='1')
        f.command('start')
        f.wait(lambda: f.state().get('phase') == 'dispatching')
        f.command('stop')
        count = sum(row[1] == 'mock_launch_applied' for row in f.events())
        time.sleep(1.1)
        self.assertEqual(sum(row[1] == 'mock_launch_applied' for row in f.events()), count)
        self.assertEqual(f.state()['active'], '0')

    def test_default_input_during_loading_takes_urgent_exit_policy(self):
        f = self.fixture(launch='2')
        f.command('start')
        f.wait(lambda: f.state().get('phase') == 'dispatching')
        reply, elapsed = f.command('input')
        self.assertEqual(reply[2], 'stop')
        self.assertLess(elapsed, .75)
        f.wait(lambda: f.state().get('active') == '0')

    def test_stop_admission_bypasses_busy_ordinary_writer(self):
        f = self.fixture()
        f.start()
        with open(f.root / 'control-writer.lock', 'a') as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            reply, elapsed = f.command('stop')
            self.assertEqual(reply[1], 'ok')
            self.assertLess(elapsed, .75)

    def test_close_before_open_and_dead_ui_client_do_not_pause(self):
        f = self.fixture()
        f.start()
        f.command('ui-close', 'closed-before-open')
        reply, _ = f.command('ui-open', 'closed-before-open', os.getpid(), ticks(os.getpid()))
        self.assertEqual(reply[1], 'rejected')
        reply, _ = f.command('ui-open', 'dead-client', 999999999, 1)
        self.assertEqual(reply[1:], ['rejected', 'dead_ui_client'])
        self.assertEqual(f.state()['paused'], '0')

    def test_unproven_launch_cleanup_withholds_menu_until_job_is_gone(self):
        with tempfile.TemporaryDirectory() as directory:
            clone = Path(directory) / 'prototype'
            shutil.copytree(PROTOTYPE, clone)
            path = clone / 'engine.sh'
            source = path.read_text()
            needle = 'if ! job_cancel launch; then'
            self.assertIn(needle, source)
            # Trusted fixture fault: corrupt the remembered start ticks only.
            # No arbitrary command is accepted through the mailbox.
            path.write_text(source.replace(needle, '((launch_start+=1))\n    ' + needle, 1))
            f = self.fixture(source=clone, launch='3')
            f.command('start')
            f.wait(lambda: f.state().get('phase') == 'dispatching')
            job = int(f.state()['launch_pid'])
            original_ticks = ticks(job)
            reply, _ = f.command('stop')
            self.assertEqual(reply[1:], ['rejected', 'cleanup_unproven'])
            f.wait(lambda: f.state().get('cleanup_blocked') == '1')
            self.assertFalse(any(row[1] == 'sim_menu_intent' for row in f.events()))
            self.assertTrue(any(row[1] == 'sim_menu_withheld' for row in f.events()))
            # Reclaim only the exact mock job whose private group was observed
            # while the fixture owner remains alive as its SID anchor.
            if ticks(job) == original_ticks and os.getpgid(job) == job and os.getsid(job) == f.process.pid:
                os.killpg(job, signal.SIGKILL)
            f.command('stop')
            f.wait(lambda: f.state().get('cleanup_blocked') == '0')

    def test_urgent_stop_wins_over_next_and_start_in_same_turn(self):
        f = self.fixture(prep='3')
        f.start()
        os.kill(f.process.pid, signal.SIGSTOP)
        try:
            f.enqueue('pending-next', 'next')
            f.enqueue('pending-start', 'start')
            f.enqueue('priority-stop', 'stop', urgent=True)
        finally:
            os.kill(f.process.pid, signal.SIGCONT)
        self.assertEqual(f.applied('priority-stop')[1], 'ok')
        self.assertEqual(f.applied('pending-next')[1], 'rejected')
        self.assertEqual(f.applied('pending-start')[1], 'rejected')
        f.wait(lambda: f.state().get('active') == '0')

    def test_stale_owner_and_same_owner_old_session_requests_are_rejected(self):
        f = self.fixture()
        f.start()
        old_epoch = f.state()['session_epoch']
        f.enqueue('wrong-owner', 'stop', owner=('2', '3', 'wrong'))
        self.assertEqual(f.applied('wrong-owner')[1:], ['rejected', 'stale_owner'])
        self.assertEqual(f.state()['active'], '1')
        f.command('stop')
        f.start()
        f.enqueue('old-session', 'next', epoch=old_epoch)
        self.assertEqual(f.applied('old-session')[1:], ['rejected', 'stale_epoch'])

    def test_old_launch_selection_does_not_dispatch_again(self):
        f = self.fixture(prep='0.1')
        f.start()
        old = f.state()['selection']
        f.command('next')
        f.wait(lambda: f.state().get('selection') != old and f.state().get('phase') == 'demonstration')
        dispatches = sum(row[1] == 'mock_dispatch' for row in f.events())
        reply, _ = f.command('launch', old)
        self.assertEqual(reply[1:], ['rejected', 'stale_selection'])
        self.assertEqual(sum(row[1] == 'mock_dispatch' for row in f.events()), dispatches)

    def test_ui_open_close_same_batch_never_strands_pause(self):
        f = self.fixture()
        f.start()
        os.kill(f.process.pid, signal.SIGSTOP)
        try:
            f.enqueue('a-open', 'ui-open', args=('lease1', str(os.getpid()), ticks(os.getpid())))
            f.enqueue('b-close', 'ui-close', args=('lease1', '-', '-'))
        finally:
            os.kill(f.process.pid, signal.SIGCONT)
        self.assertEqual(f.applied('a-open')[1], 'ok')
        self.assertEqual(f.applied('b-close')[1], 'ok')
        f.wait(lambda: f.state().get('ui_open') == '0' and f.state().get('paused') == '0')
        time.sleep(.12)
        self.assertEqual(f.state()['paused'], '0')

    def test_old_ui_close_cannot_release_newer_lease(self):
        f = self.fixture()
        f.start()
        f.command('ui-open', 'first', os.getpid(), ticks(os.getpid()))
        f.command('ui-open', 'second', os.getpid(), ticks(os.getpid()))
        reply, _ = f.command('ui-close', 'first')
        self.assertEqual(reply[1:], ['rejected', 'stale_lease'])
        self.assertEqual(f.state()['ui_lease'], 'second')
        f.command('ui-close', 'second')

    def test_m82_bios_demo_play_and_menu_policies(self):
        f = self.fixture(mode='m82', prep='0.1', play=0)
        f.start()
        self.assertEqual(f.state()['phase'], 'bios')
        reply, _ = f.command('input')
        self.assertEqual(reply[2], 'ignore')
        f.command('timer')
        f.wait(lambda: f.state().get('phase') == 'demonstration')
        f.command('input')
        f.wait(lambda: f.state().get('phase') == 'playing')
        self.assertEqual(f.command('input')[0][2], 'ignore')
        selection = f.state()['selection']
        f.command('timer')
        self.assertEqual(f.state()['selection'], selection)
        f.command('menu-observed')
        f.wait(lambda: f.state().get('active') == '0')

    def test_commercial_clip_then_game_use_the_same_engine(self):
        f = self.fixture(mode='commercial', prep='0.1')
        f.start()
        self.assertEqual(f.state()['phase'], 'commercial')
        f.command('timer')
        f.wait(lambda: f.state().get('phase') == 'demonstration')
        details = [row[4] for row in f.events() if row[1] == 'mock_dispatch']
        self.assertTrue(details[0].startswith('clip:NES:'))
        self.assertTrue(details[1].startswith('game:NES:'))

    def test_mailbox_data_is_never_executed(self):
        f = self.fixture()
        marker = f.root / 'should-not-exist'
        f.enqueue('bad-action', '$(touch ' + str(marker) + ')')
        self.assertEqual(f.applied('bad-action')[1], 'rejected')
        self.assertFalse(marker.exists())

    def test_fifo_and_symlink_requests_cannot_block_or_modify_target(self):
        f = self.fixture()
        os.mkfifo(f.root / 'inbox/control.fifo.req')
        target = f.root / 'unchanged-target'
        target.write_text('unchanged\n')
        (f.root / 'inbox/control.symlink.req').symlink_to(target)
        f.wait(lambda: sum(row[1] == 'request_path_rejected' for row in f.events()) >= 2)
        self.assertEqual(target.read_text(), 'unchanged\n')
        self.assertEqual(f.command('status')[0][1], 'ok')

    def test_invalid_mode_policy_rejected_before_owner_admission(self):
        with tempfile.TemporaryDirectory() as directory:
            clone = Path(directory) / 'prototype'
            shutil.copytree(PROTOTYPE, clone)
            mode = clone / 'modes/normal.tsv'
            mode.write_text(mode.read_text().replace('input_transition\tstop', 'input_transition\tmisspelled'))
            with tempfile.TemporaryDirectory(prefix='sam-session-research-', dir='/tmp') as private:
                root = Path(private)
                (root / 'RESEARCH_MOCK_ONLY').write_text('SAM_SESSION_RESEARCH_V1\n')
                interpreter = sys.executable if self.engine_file.endswith('.py') else 'bash'
                result = subprocess.run([interpreter, str(clone / self.engine_file), 'normal', '3', '0'],
                                        env=dict(os.environ, TMP_ROOT=private), capture_output=True, timeout=3)
                self.assertEqual(result.returncode, 64)
                self.assertFalse((root / 'owner').exists())
                self.assertFalse((root / 'engine.lock').exists())

    def test_empty_preparation_reports_failure_without_retry_loop(self):
        with tempfile.TemporaryDirectory() as directory:
            clone = Path(directory) / 'prototype'
            shutil.copytree(PROTOTYPE, clone)
            path = clone / 'modes/normal.tsv'
            path.write_text('\n'.join(line for line in path.read_text().splitlines() if not line.startswith('item\t')) + '\n')
            f = self.fixture(source=clone)
            f.command('start')
            f.wait(lambda: f.state().get('phase') == 'failed')
            self.assertTrue(any(row[1] == 'preparation_failed' for row in f.events()))
            events = len(f.events())
            time.sleep(.15)
            self.assertEqual(len(f.events()), events)


@unittest.skipUnless((PROTOTYPE / 'python_owner.py').exists(), 'Alternative research owner not present')
class PythonOwnerResearchTests(EngineResearchTests):
    engine_file = 'python_owner.py'

    def test_unproven_launch_cleanup_withholds_menu_until_job_is_gone(self):
        with tempfile.TemporaryDirectory() as directory:
            clone = Path(directory) / 'prototype'
            shutil.copytree(PROTOTYPE, clone)
            path = clone / self.engine_file
            source = path.read_text()
            needle = '        if not self.cancel("launch"):'
            self.assertIn(needle, source)
            path.write_text(source.replace(needle,
                '        if self.launch:\n            self.launch.start = str(int(self.launch.start) + 1)\n' + needle, 1))
            f = self.fixture(source=clone, launch='3')
            f.command('start')
            f.wait(lambda: f.state().get('phase') == 'dispatching')
            job = int(f.state()['launch_pid'])
            original_ticks = ticks(job)
            reply, _ = f.command('stop')
            self.assertEqual(reply[1:], ['rejected', 'cleanup_unproven'])
            f.wait(lambda: f.state().get('cleanup_blocked') == '1')
            self.assertFalse(any(row[1] == 'sim_menu_intent' for row in f.events()))
            self.assertTrue(any(row[1] == 'sim_menu_withheld' for row in f.events()))
            if ticks(job) == original_ticks and os.getpgid(job) == job and os.getsid(job) == job:
                os.killpg(job, signal.SIGKILL)
            f.command('stop')
            f.wait(lambda: f.state().get('cleanup_blocked') == '0')
