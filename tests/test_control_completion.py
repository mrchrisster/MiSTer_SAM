"""Bounded completion waits preserve command expiry and journal replay."""
import importlib.util
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from paths import PACKAGE

CONTROL = PACKAGE / '.MiSTer_SAM/control'
spec = importlib.util.spec_from_file_location('sam_control_completion_test', CONTROL / 'sam_control.py')
control = importlib.util.module_from_spec(spec)
try:
    import fcntl
except ImportError:
    fcntl = SimpleNamespace(LOCK_EX=2, flock=lambda *_: None)
with patch.dict(sys.modules, {'fcntl': fcntl}), patch.object(sys, 'path', [str(CONTROL), *sys.path]):
    spec.loader.exec_module(control)


class ControlCompletion(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='sam-completion-test-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.now = 100.0
        self.request = dict(action='play', expected_seq=None, game_path='/games/Test.mra',
                            request_id='11111111-1111-1111-1111-111111111111')
        self.start_patch(patch.object(control, 'ROOT', root / 'commands'))
        self.start_patch(patch.object(control, 'STORE', root / 'journal'))
        self.current = self.start_patch(patch.object(control, 'check_current', return_value=(
            200, dict(generation='1', identity={'owner_pid': '321', 'owner_start': '77'}))))
        self.start_patch(patch.object(control.fcntl, 'flock'))
        self.start_patch(patch.object(control.time, 'monotonic', side_effect=lambda: self.now))
        self.start_patch(patch.object(control.time, 'sleep', side_effect=self.sleep))

    def start_patch(self, patcher):
        value = patcher.start()
        self.addCleanup(patcher.stop)
        return value

    def sleep(self, duration):
        self.now += duration

    def test_play_accepts_success_after_the_old_five_second_deadline(self):
        def read_ack(_):
            if self.now >= 108:
                return dict(code=200, body={'ok': True})
        with patch.object(control, 'read_json', side_effect=read_ack):
            self.assertEqual(control.submit(self.request), (200, {'ok': True}))
        self.assertGreaterEqual(self.now, 108)
        self.assertLess(self.now, 120)

    def test_quick_commands_retain_five_second_completion_window(self):
        for action in ('next', 'ignore', 'pause', 'resume'):
            with self.subTest(action=action):
                request = dict(self.request, action=action,
                               request_id=f'11111111-1111-1111-1111-11111111111{control.ACTIONS.index(action)}')
                started = self.now
                with patch.object(control, 'read_json', return_value=None):
                    code, body = control.submit(request)
                self.assertEqual(code, 503)
                self.assertIn('did not finish', body['error'])
                self.assertAlmostEqual(self.now - started, 5, delta=.051)

    def test_play_timeout_is_bounded_and_duplicate_does_not_dispatch_again(self):
        with patch.object(control, 'read_json', return_value=None):
            result = control.submit(self.request)
        self.assertEqual(result[0], 503)
        self.assertAlmostEqual(self.now, 120, delta=.051)
        self.assertFalse((control.ROOT / 'pending.json').exists())
        with patch.object(control, 'atomic') as dispatch:
            self.assertEqual(control.submit(self.request), result)
            dispatch.assert_not_called()
        self.current.assert_called_once()

    def test_long_play_wait_does_not_extend_claim_expiration(self):
        envelopes = []
        original_atomic = control.atomic
        def capture(path, value):
            envelopes.append(value)
            original_atomic(path, value)
        with patch.object(control, 'atomic', side_effect=capture), patch.object(
                control, 'read_json', return_value=dict(code=200, body={'ok': True})):
            self.assertEqual(control.submit(self.request)[0], 200)
        self.assertEqual(envelopes[0]['expires'], 104)


if __name__ == '__main__':
    unittest.main()
