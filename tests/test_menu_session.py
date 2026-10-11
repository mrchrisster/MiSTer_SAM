"""Menu leases bind acknowledged pause/resume to one verified selection."""
import base64
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch
from paths import PACKAGE

sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
with patch.dict(sys.modules, {'fcntl': types.ModuleType('fcntl')} if os.name == 'nt' else {}):
    from sam import menu_session as menu


class MenuLeaseTests(unittest.TestCase):
    def setUp(self):
        self.owner = dict(pid='321', start='77', phase='playing', launch='1')
        identity = dict(owner_pid='321', owner_start='77', start_time='123', rom_path='/games/a "quoted".zip')
        self.status = dict(active=True, state=dict(identity, mode='normal'),
                           control=dict(identity, generation='321:77:1', ready=True, paused=False))
        self.gateway = Mock()
        def execute(action, command, *args, **kwargs):
            print('{"ok":true,"code":200}')
            self.status['control']['paused'] = command == 'pause'
            return True
        self.gateway.execute.side_effect = execute
        self.session = menu.MenuSession(self.gateway, lambda: self.owner, lambda: copy.deepcopy(self.status))

    def test_acknowledged_pause_has_clean_token_and_exact_resume(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            token = self.session.hold()
            self.session.release(token)
        self.assertEqual(output.getvalue(), '')
        decoded = json.loads(base64.urlsafe_b64decode(token + '=' * (-len(token) % 4)))
        self.assertEqual(decoded['rom_path'], self.status['state']['rom_path'])
        self.assertEqual(decoded['generation'], '321:77:1')
        self.assertEqual(self.gateway.execute.call_count, 2)
        for call, command in zip(self.gateway.execute.call_args_list, ('pause', 'resume')):
            self.assertEqual(call.args, ('control', command, '--generation', '321:77:1',
                                         '--game-path', self.status['state']['rom_path']))
            self.assertEqual(call.kwargs['owner'], dict(pid='321', start='77'))
        self.assertFalse(self.status['control']['paused'])

    def test_inactive_and_already_paused_leave_no_resume_lease(self):
        self.owner = None
        self.assertEqual(self.session.hold(), '-')
        self.owner = dict(pid='321', start='77', phase='playing')
        self.status['control']['paused'] = True
        self.assertEqual(self.session.hold(), '-')
        self.session.release('-')
        self.gateway.execute.assert_not_called()

    def test_loading_preparing_or_nonready_pause_protocol_refuses_menu(self):
        for field, value in [('phase', 'loading'), ('phase', 'preparing'),
                             ('ready', False), ('mode', 'unknown')]:
            with self.subTest(field=field, value=value):
                owner, status = copy.deepcopy(self.owner), copy.deepcopy(self.status)
                target = owner if field == 'phase' else status['state' if field == 'mode' else 'control']
                target[field] = value
                session = menu.MenuSession(self.gateway, lambda: owner, lambda: status)
                with self.assertRaisesRegex(menu.MenuSessionError, 'Retry'):
                    session.hold()
        self.gateway.execute.assert_not_called()

    def test_special_modes_open_menu_without_pause_or_resume(self):
        for mode in ('m82', 'samvideo', 'video'):
            for phase in ('playing', 'loading', 'preparing'):
                with self.subTest(mode=mode, phase=phase):
                    self.owner['phase'] = phase
                    self.status['state']['mode'] = mode
                    self.status['control'] = {}
                    self.assertEqual(self.session.hold(), '-')
                    self.session.release('-')
        self.gateway.execute.assert_not_called()

    def test_special_mode_rejects_stale_or_inactive_display_state(self):
        self.status['state']['mode'] = 'samvideo'
        for field, value in (('owner_pid', '322'), ('owner_start', '78')):
            with self.subTest(field=field):
                status = copy.deepcopy(self.status)
                status['state'][field] = value
                session = menu.MenuSession(self.gateway, lambda: self.owner, lambda: status)
                with self.assertRaisesRegex(menu.MenuSessionError, 'changed'):
                    session.hold()
        self.status['active'] = False
        with self.assertRaisesRegex(menu.MenuSessionError, 'changed'):
            self.session.hold()
        self.gateway.execute.assert_not_called()

    def test_special_mode_owner_replacement_never_creates_resume_lease(self):
        self.status['state']['mode'] = 'samvideo'
        for replacement in (None, dict(self.owner, start='78')):
            with self.subTest(replacement=replacement):
                owners = iter((self.owner, replacement))
                session = menu.MenuSession(self.gateway, lambda: next(owners), lambda: self.status)
                with self.assertRaisesRegex(menu.MenuSessionError, 'changed'):
                    session.hold()
        self.gateway.execute.assert_not_called()

    def test_failed_or_uncertain_pause_never_returns_token(self):
        self.gateway.execute.side_effect = None
        self.gateway.execute.return_value = False
        with self.assertRaisesRegex(menu.MenuSessionError, 'acknowledge'):
            self.session.hold()
        self.gateway.execute.return_value = True
        with self.assertRaisesRegex(menu.MenuSessionError, 'uncertain'):
            self.session.hold()

    def test_pause_ack_for_changed_selection_is_rejected(self):
        def changed(*args, **kwargs):
            self.status['control'].update(paused=True, generation='321:77:2')
            return True
        self.gateway.execute.side_effect = changed
        with self.assertRaisesRegex(menu.MenuSessionError, 'uncertain'):
            self.session.hold()

    def test_replaced_stopped_next_resumed_or_nonready_owner_is_never_resumed(self):
        for change in ('replacement', 'stop', 'next', 'resumed', 'nonready', 'rom'):
            self.setUp()
            token = self.session.hold()
            self.gateway.execute.reset_mock()
            if change == 'replacement': self.owner['start'] = '78'
            elif change == 'stop': self.owner = None
            elif change == 'next': self.status['control']['generation'] = '321:77:2'
            elif change == 'resumed': self.status['control']['paused'] = False
            elif change == 'nonready': self.status['control']['ready'] = False
            else: self.status['state']['rom_path'] = '/games/b.zip'
            self.session.release(token)
            self.gateway.execute.assert_not_called()

    def test_failed_resume_reports_only_if_same_selection_still_paused(self):
        token = self.session.hold()
        self.gateway.execute.side_effect = None
        self.gateway.execute.return_value = False
        with self.assertRaisesRegex(menu.MenuSessionError, 'Resume'):
            self.session.release(token)
        def replaced(*args, **kwargs):
            self.owner = None
            return False
        self.gateway.execute.side_effect = replaced
        self.session.release(token)

    def test_token_is_literal_and_bounded(self):
        for token in ('$(touch /tmp/bad)', '{}', 'a' * 8193, base64.urlsafe_b64encode(b'{}').decode()):
            with self.assertRaises(menu.MenuSessionError): self.session.release(token)
        self.gateway.execute.assert_not_called()


@unittest.skipUnless(sys.platform.startswith('linux'), 'Linux kernel flock required')
class MenuLockTests(unittest.TestCase):
    def test_existing_unlocked_and_dead_holder_are_inactive_without_unlink(self):
        with tempfile.TemporaryDirectory() as directory:
            lock = Path(directory) / 'menu.lock'
            self.assertFalse(menu.active(lock))
            self.assertFalse(lock.exists())
            lock.touch()
            self.assertFalse(menu.active(lock))
            inode = lock.stat().st_ino
            code = 'import fcntl,sys; f=open(sys.argv[1],"r"); fcntl.flock(f,fcntl.LOCK_EX); print("held",flush=True); sys.stdin.read()'
            holder = subprocess.Popen([sys.executable, '-c', code, str(lock)],
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(holder.stdout.readline().strip(), 'held')
                self.assertTrue(menu.active(lock))
                holder.kill()
                holder.wait(timeout=3)
                self.assertFalse(menu.active(lock))
                self.assertEqual(lock.stat().st_ino, inode)
            finally:
                if holder.poll() is None: holder.kill(); holder.wait(timeout=3)
                holder.stdin.close(); holder.stdout.close()

    def test_symlink_nonregular_or_unavailable_lock_blocks_conservatively(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'regular'; target.touch()
            link = root / 'link'; link.symlink_to(target)
            self.assertTrue(menu.active(link))
            self.assertTrue(menu.active(root))
            with patch.object(menu.os, 'open', side_effect=PermissionError()):
                self.assertTrue(menu.active(target))


if __name__ == '__main__': unittest.main()
