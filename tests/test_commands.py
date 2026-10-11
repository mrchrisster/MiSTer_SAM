"""Shared command routing fixtures without hardware or a live tmux server."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
import sys
import tempfile
from unittest.mock import Mock, patch

from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))

spec = importlib.util.spec_from_file_location('sam_commands_test', PACKAGE / '.MiSTer_SAM/sam/commands.py')
commands = importlib.util.module_from_spec(spec)
spec.loader.exec_module(commands)


class Commands(unittest.TestCase):
    def setUp(self):
        self.owner = {'pid': '123', 'start': '45', 'phase': 'playing'}
        self.calls = []
        self.panes = [('%8', '123')]
        def run(argv, **kwargs):
            self.calls.append(argv)
            return SimpleNamespace(returncode=0)
        self.gateway = commands.CommandGateway(
            owner_reader=lambda: self.owner, runner=run,
            pane_reader=lambda: self.panes, process_verifier=lambda pid, start: True,
            entrypoint='/scripts/MiSTer_SAM_on.sh')

    def test_keys_target_verified_pane(self):
        for action, key in [('next', 'n'), ('previous', 'p'), ('mute', 'm'), ('m82_play', 'y')]:
            self.assertTrue(self.gateway.execute(action, owner=dict(self.owner)))
            self.assertEqual(self.calls[-1], ['tmux', 'send-keys', '-t', '%8', key])

    def test_menu_countdown_is_transient_and_binds_complete_selection(self):
        selection = dict(owner_pid='123', owner_start='45', start_time='10',
                         rom_path='/games/a.sfc', generation='123:45:1')
        identity = {key: value for key, value in selection.items() if key != 'generation'}
        transport = Mock()
        current = dict(identity=identity, generation=selection['generation'], ready=True)
        transport.status.return_value = current
        transport.submit.return_value = (200, {'ok': True})
        self.gateway._control_client = SimpleNamespace(transport=transport)
        self.assertTrue(self.gateway.menu_countdown('pause', selection))
        request = transport.submit.call_args.args[0]
        self.assertEqual(request['action'], 'pause')
        self.assertEqual(request['game_path'], selection['rom_path'])
        self.assertIsNone(request['expected_seq'])
        self.assertEqual(transport.submit.call_args.kwargs, dict(expected=current, journaled=False))
        transport.submit.reset_mock()
        for key in selection:
            changed = dict(selection, **{key: selection[key] + 'changed'})
            self.assertFalse(self.gateway.menu_countdown('pause', changed))
        transport.submit.assert_not_called()
        transport.submit.return_value = (503, {'ok': False})
        self.assertFalse(self.gateway.menu_countdown('resume', selection))
        with self.assertRaises(ValueError):
            self.gateway.menu_countdown('next', selection)

    def test_stale_owner_never_targets_replacement(self):
        expected = dict(self.owner)
        self.owner = {'pid': '124', 'start': '46'}
        self.panes = [('%9', '124')]
        self.assertFalse(self.gateway.execute('next', owner=expected))
        self.assertFalse(self.gateway.execute('exit_to_game', owner=expected))
        self.assertEqual(self.calls, [])

    def test_m82_play_rejects_loading_and_changed_selection(self):
        self.owner.update(phase='playing', launch='1')
        expected = dict(self.owner)
        self.owner['phase'] = 'loading'
        self.assertFalse(self.gateway.execute('m82_play', owner=expected))
        self.owner.update(phase='playing', launch='2')
        self.assertFalse(self.gateway.execute('m82_play', owner=expected))
        self.assertEqual(self.calls, [])
        self.owner['launch'] = '1'
        def change():
            self.owner['launch'] = '2'
            return self.panes
        self.gateway.pane_reader = change
        self.assertFalse(self.gateway.execute('m82_play', owner=expected))
        self.assertEqual(self.calls, [])

    def test_historical_positional_binding_rejects_stale_owner(self):
        self.assertFalse(self.gateway.execute('exit_to_game', '999', '45'))
        self.assertFalse(self.gateway.execute('stop', '999', '45'))
        self.assertEqual(self.calls, [])

    def test_unowned_and_wrong_pane_inputs_rejected(self):
        self.panes = [('%9', '999')]
        self.assertFalse(self.gateway.execute('next'))
        self.owner = None
        self.assertFalse(self.gateway.execute('mute'))
        self.assertEqual(self.calls, [])

    def test_replacement_between_pane_query_and_send_is_rejected(self):
        def panes():
            self.owner = {'pid': '124', 'start': '46'}
            return [('%8', '123')]
        self.gateway.pane_reader = panes
        self.assertFalse(self.gateway.execute('next'))
        self.assertEqual(self.calls, [])

    def test_dead_owner_rejected(self):
        self.gateway.process_verifier = lambda pid, start: False
        self.assertFalse(self.gateway.execute('next'))
        self.assertFalse(self.gateway.execute('stop_owner', owner=self.owner))

    def test_stop_retains_menu_audio_backend_with_binding(self):
        self.assertTrue(self.gateway.execute('stop'))
        self.assertEqual(self.calls[-1], ['bash', '/scripts/MiSTer_SAM_on.sh', '--gateway-backend', 'stop', '123', '45'])

    def test_menu_audio_restore_passes_dead_original_binding(self):
        expected = dict(self.owner)
        self.owner = None
        self.assertTrue(self.gateway.execute('menu_audio_restore', owner=expected))
        self.assertEqual(self.calls[-1][-3:], ['menu_audio_restore', '123', '45'])

    def test_inactive_stop_has_no_permission_for_late_owner(self):
        self.owner = None
        self.assertTrue(self.gateway.execute('stop'))
        self.assertEqual(self.calls[-1][-3:], ['stop', '0', '0'])
        self.assertFalse(self.gateway.execute('stop', owner={'pid': '123', 'start': '45'}))
        self.assertEqual(len(self.calls), 1)

    def test_unmute_binds_owner_and_rejects_replacement(self):
        expected = dict(self.owner)
        self.assertTrue(self.gateway.execute('unmute', owner=expected))
        self.assertEqual(self.calls[-1][-3:], ['unmute', '123', '45'])
        self.owner = {'pid': '124', 'start': '46'}
        self.assertFalse(self.gateway.execute('unmute', owner=expected))
        self.assertEqual(len(self.calls), 1)

    def test_inactive_unmute_uses_sentinel(self):
        self.owner = None
        self.assertTrue(self.gateway.execute('unmute'))
        self.assertEqual(self.calls[-1][-3:], ['unmute', '0', '0'])

    def test_start_is_private_and_launcher_is_trackable(self):
        sentinel = object()
        def launch(argv, **kwargs):
            self.calls.append(argv)
            self.assertTrue(kwargs['start_new_session'])
            return sentinel
        self.gateway.launcher = launch
        self.assertIs(self.gateway.launch_start(), sentinel)
        self.assertEqual(self.calls[-1][-2:], ['--gateway-backend', 'start'])

    def test_automatic_start_uses_idle_admission_flag(self):
        calls = []
        self.gateway.launcher = lambda argv, **kwargs: calls.append(argv)
        self.gateway.launch_start(if_idle=True)
        self.assertEqual(calls[0][-3:], ['--gateway-backend', 'start', '--if-idle'])
        self.gateway.execute('start', 'snes')
        self.assertEqual(self.calls[-1][-3:], ['--gateway-backend', 'start', 'snes'])

    def test_bare_ignore_remains_exclusion_only(self):
        self.assertTrue(self.gateway.execute('ignore'))
        self.assertEqual(self.calls[-1][-2:], ['--gateway-backend', 'ignore'])

    def test_unknown_command_rejected(self):
        with self.assertRaises(ValueError):
            self.gateway.execute('shell')

    def test_control_loads_its_exact_file_despite_samctl_name_collision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'control').mkdir()
            (root / 'control' / 'samctl.py').write_text('def main(argv):\n    return 0 if argv == ["status"] else 1\n')
            self.gateway.root = root
            fake = SimpleNamespace(main=lambda argv: self.fail('Imported wrong samctl module'))
            with patch.dict(sys.modules, {'samctl': fake}), patch.object(sys, 'path', list(sys.path)):
                self.assertEqual(self.gateway.control(['status']), 0)
                client = self.gateway._control_client
                self.assertEqual(self.gateway.control(['status']), 0)
                self.assertIs(self.gateway._control_client, client)

    def test_control_input_keeps_captured_owner_binding(self):
        received = []
        self.gateway.control = lambda args: received.append(args) or 0
        self.assertTrue(self.gateway.execute('control', 'ignore', owner=dict(self.owner)))
        self.assertEqual(received, [['ignore', '--owner-pid', '123', '--owner-start', '45']])
        self.assertFalse(self.gateway.execute('play', owner={'pid': '999', 'start': '45'}))
        self.assertEqual(len(received), 1)

    def test_control_uuid_replay_defers_to_existing_journal_before_owner_check(self):
        received = []
        self.gateway.control = lambda args: received.append(args) or 0
        self.owner = None
        expected = {'pid': '123', 'start': '45'}
        request_id = '11111111-1111-1111-1111-111111111111'
        self.assertTrue(self.gateway.execute('control', 'next', '--request-id', request_id, owner=expected))
        self.assertEqual(received, [['next', '--request-id', request_id, '--owner-pid', '123', '--owner-start', '45']])


if __name__ == '__main__':
    unittest.main()
