"""Resolver/action fixtures; hardware reconnect and grab behavior need live tests."""
import contextlib
import importlib.util
import io
from pathlib import Path
from paths import PACKAGE
import queue
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
PATH = PACKAGE / '.MiSTer_SAM/MiSTer_SAM_MCP.py'
spec = importlib.util.spec_from_file_location('mcp_input_tests', PATH)
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)


def events(buttons=(0, 0, 0), axis=0):
    return [dict(timestamp=0, value=value, type=0x81, number=i) for i, value in enumerate(buttons)] + [dict(timestamp=0, value=axis, type=0x82, number=0)]


class MappingTests(unittest.TestCase):
    def resolver(self, root, values=None, state=None):
        (root / 'inputs').mkdir(exist_ok=True)
        if values is not None:
            (root / 'inputs/input_1234_5678_v3.map').write_bytes(struct.pack('<32I', *values))
        guid = mcp.input_controller_guid((3, 0x1234, 0x5678, 0x111))
        (root / 'gamecontrollerdb.txt').write_text(guid + ',Fixture,start:b2,back:b1,lefttrigger:a0,platform:Linux,\n')
        if state is None:
            state = mcp.SamState()
            state.samdebug = True
            state.input_debug_output = Mock()
        device = dict(js_path='/dev/input/js0', event_path='/dev/input/event8', id='1234_5678', name='Pad', sysfs='/devices/input1')
        def ioctl(fd, kind, number, size):
            if kind == 'j':
                if number == 0x12: return b'\x03'
                if number == 0x11: return b'\x01'
                if number == 0x34: return struct.pack('=512H', 315, 314, 312, *([0] * 509))
                if number == 0x32: return bytes(64)
            if number == 0x02: return struct.pack('=4H', 3, 0x1234, 0x5678, 0x111)
            bits = bytearray(size)
            for code in ({312, 314, 315} if number == 0x21 else {0}):
                bits[code // 8] |= 1 << (code % 8)
            return bytes(bits)
        real_open = open
        def fake_open(path, *args, **kwargs):
            if path in (device['js_path'], device['event_path']):
                file = Mock()
                file.fileno.return_value = 12
                context = Mock()
                context.__enter__ = Mock(return_value=file)
                context.__exit__ = Mock(return_value=False)
                return context
            return real_open(path, *args, **kwargs)
        with patch.object(mcp, 'INPUT_CONFIG_DIR', str(root)), patch.object(mcp, 'INPUT_DB_DIR', str(root)), \
                patch.object(mcp.InputBindings, 'ioctl', side_effect=ioctl), patch('builtins.open', side_effect=fake_open):
            result = mcp.InputBindings(device, state)
        return result, state

    def output(self, state):
        return '\n'.join(call.args[0] for call in state.input_debug_output.emit.call_args_list)

    def test_saved_reassignment_drives_actions_and_hides_js_indices(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = [0] * 32
            values[10], values[11], values[4] = 315, 314, 312
            binding, state = self.resolver(Path(tmp), values)
            self.assertEqual(binding.action(events(), events((0, 1, 0))), 'start')
            self.assertEqual(binding.action(events(), events((1, 0, 0))), 'next')
            self.assertEqual(binding.action(events(), events((0, 0, 1))), 'default')
            state.input_debug_output.reset_mock()
            binding.report(events(), events((0, 1, 0)))
            log = self.output(state)
            self.assertIn('MiSTer=Start DB=back', log)
            self.assertIn('action=start', log)
            self.assertNotIn('source=', log)
            self.assertEqual(log.count('Pad'), 1)
            self.assertNotIn('js_button', log)
            self.assertNotIn('js_axis', log)

    def test_startup_is_concise_and_deep_metadata_is_not_repeated(self):
        with tempfile.TemporaryDirectory() as tmp:
            values=[0]*32
            values[10],values[11]=315,314
            binding,state=self.resolver(Path(tmp),values)
            log=self.output(state)
            self.assertIn('Pad: Ready: Start/Select',log)
            for fragment in ('binding ', 'DB MATCH', 'DB GUID', 'saved global map=', 'source='):
                self.assertNotIn(fragment,log)

    def test_saved_unassigned_and_flagged_slots_never_fall_back_to_db(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = [0] * 32
            binding, state = self.resolver(Path(tmp), values)
            self.assertEqual(binding.source, 'MiSTer-map')
            self.assertEqual(binding.action(events(), events((1, 0, 0))), 'default')
            self.assertEqual(binding.actions, {})
            values[11] = 0x100013b
            binding, state = self.resolver(Path(tmp), values)
            self.assertEqual(binding.actions, {})
            self.assertIn('unsupported flagged value', self.output(state))

    def test_database_fallback_translates_actual_joydev_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            binding, state = self.resolver(Path(tmp))
            self.assertEqual(binding.source, 'controllerdb')
            self.assertEqual(binding.action(events(), events((1, 0, 0))), 'start')
            self.assertEqual(binding.action(events(), events((0, 1, 0))), 'next')
            binding.report(events(), events((1, 0, 0)))
            self.assertIn('DB=start js_button=0 Linux=315', self.output(state))

    def test_invalid_and_ambiguous_maps_use_generic_not_db_actions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'inputs').mkdir()
            (root / 'inputs/input_1234_5678_v3.map').write_bytes(b'bad')
            binding, _ = self.resolver(root)
            self.assertEqual(binding.source, 'generic')
            self.assertEqual(binding.action(events(), events((1, 0, 0))), 'default')
            (root / 'inputs/input_1234_5678_m_v3.map').write_bytes(bytes(128))
            binding, _ = self.resolver(root)
            self.assertEqual(binding.map_status, 'ambiguous identity/mode')
            self.assertEqual(binding.actions, {})

    def test_axis_role_crosses_threshold_once_without_premature_exit(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = [0] * 32
            values[11] = 769  # ABS0 positive edge as Start.
            binding, state = self.resolver(Path(tmp), values)
            self.assertIsNone(binding.action(events(axis=0), events(axis=8000)))
            self.assertTrue(binding.has_activity(events(axis=0), events(axis=8000)))
            self.assertEqual(binding.action(events(axis=8000), events(axis=32767)), 'start')
            self.assertIsNone(binding.action(events(axis=32767), events(axis=32767)))
            self.assertIsNone(binding.action(events(axis=32767), events(axis=0)))
            self.assertEqual(binding.action(events((0, 0, 0), axis=32767), events((0, 0, 1), axis=32767)), 'default')

    def test_baselines_held_buttons_releases_and_queued_records_do_not_fire(self):
        with tempfile.TemporaryDirectory() as tmp:
            binding, state = self.resolver(Path(tmp))
            self.assertIsNone(binding.action([], events((1, 0, 0))))
            self.assertIsNone(binding.action(events((1, 0, 0)), events((1, 0, 0))))
            self.assertIsNone(binding.action(events((1, 0, 0)), events()))
            queued = events() + [dict(timestamp=1, value=1, type=1, number=0)]
            self.assertNotIn((1, 0, ''), binding.actions)
            self.assertEqual(binding.changes(events(), queued), [])
            state.input_debug_output.reset_mock()
            binding.report(events((1, 0, 0)), events((1, 0, 0)))
            self.assertEqual(self.output(state), '')
            binding.report(events(), events((1, 1, 0)))
            self.assertEqual(self.output(state).count(' DOWN '), 2)

    def test_press_path_uses_only_cached_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            binding, state = self.resolver(Path(tmp))
            with patch('builtins.open', side_effect=AssertionError('I/O in press path')), \
                    patch.object(mcp.fcntl, 'ioctl', side_effect=AssertionError('ioctl in press path')):
                for _ in range(100):
                    self.assertEqual(binding.action(events(), events((1, 0, 0))), 'start')
                    binding.report(events(), events((1, 0, 0)))

    def test_quiet_sample_reuses_previous_state_and_skips_action_scan(self):
        with tempfile.TemporaryDirectory() as tmp:
            binding, _ = self.resolver(Path(tmp))
            first, second = events(), events()
            binding.changes([], first)
            with patch.object(binding, 'snapshot', wraps=binding.snapshot) as snapshot, \
                    patch.object(mcp, 'get_js_activity', side_effect=AssertionError('quiet action scan')):
                changes = binding.changes(first, second)
                self.assertEqual(changes, [])
                self.assertIsNone(binding.action(first, second, changes))
                self.assertFalse(binding.has_activity(first, second, changes))
            self.assertEqual(snapshot.call_count, 1)

    def test_core_specific_db_identity_does_not_guess_generic_start(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            guid = mcp.input_controller_guid((3, 0x1234, 0x5678, 0x111))
            (root / 'gamecontrollerdb_user.txt').write_text(
                guid + ',Core definition,start:b0,mistercore:SNES,platform:MiSTer,\n')
            binding, state = self.resolver(root)
            self.assertTrue(binding.db_core_specific)
            self.assertEqual(binding.source, 'generic')
            self.assertEqual(binding.action(events(), events((1, 0, 0))), 'default')
            self.assertIn('named actions suppressed', self.output(state))

    def test_recreated_reader_reloads_map_and_preserves_shared_database(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            values = [0] * 32
            values[11] = 314
            first, state = self.resolver(root, values)
            database = state.input_database
            values[11] = 315
            second, state = self.resolver(root, values, state)
            self.assertIs(state.input_database, database)
            self.assertEqual(first.action(events(), events((0, 1, 0))), 'start')
            self.assertEqual(second.action(events(), events((1, 0, 0))), 'start')
            self.assertIsNone(second.action([], events((1, 0, 0))))

    def test_debug_queue_never_blocks_when_full(self):
        with patch.object(mcp.threading, 'Thread'):
            output = mcp.InputDebugOutput(size=1)
        output.emit('one')
        output.emit('two')
        self.assertEqual(output.messages.get_nowait(), 'one')
        self.assertEqual(output.dropped, 1)

    def test_debug_off_does_not_emit_mapping_or_press_messages(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = mcp.SamState()
            self.assertFalse(state.samdebug)
            with patch('builtins.print') as printed:
                binding, _ = self.resolver(Path(tmp), state=state)
                binding.report(events(), events((1, 0, 0)))
            printed.assert_not_called()
            self.assertEqual(binding.action(events(), events((1, 0, 0))), 'start')

    def test_poller_dispatches_before_debug_and_does_not_repeat_held_press(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = [0] * 32
            values[11] = 314
            binding, state = self.resolver(Path(tmp), values)
            state.set_sam_running(True)
            trace = []
            state.input_debug_output.emit.side_effect = lambda text: trace.append(('debug', text))
            loop = Mock()
            loop.call_soon_threadsafe.side_effect = lambda *args: trace.append(('action', args[1]))
            samples = iter([events(), events((0, 1, 0)), events((0, 1, 0)),
                            events(), events((0, 1, 0))])
            file = Mock()
            file.fileno.return_value = 12
            file.read.side_effect = lambda size: b''.join(struct.pack('IhBB', 0, e['value'], e['type'], e['number']) for e in next(samples))
            opened = Mock()
            opened.__enter__ = Mock(return_value=file)
            opened.__exit__ = Mock(return_value=False)
            stop = Mock()
            ticks = 0
            def wait(interval):
                nonlocal ticks
                self.assertEqual(interval, 0.02)
                ticks += 1
            stop.wait.side_effect = wait
            stop.is_set.side_effect = lambda: ticks >= 5
            with patch.object(mcp, 'InputBindings', return_value=binding), \
                    patch('builtins.open', return_value=opened), \
                    patch.object(mcp.os, 'set_blocking'), patch('builtins.print'):
                mcp.joystick_poller_thread(binding.device, state, {}, loop, stop)
            self.assertEqual([item for item in trace if item[0] == 'action'],
                             [('action', 'start'), ('action', 'start')])
            self.assertEqual([item[0] for item in trace], ['action', 'debug', 'action', 'debug'])

    def test_discovery_pairs_event_and_joystick_in_same_block(self):
        proc = ('I: Bus=0003 Vendor=1234 Product=5678 Version=0111\n'
                'N: Name="Same name"\nP: Phys=usb-1\nH: Handlers=js0 event8\n\n'
                'I: Bus=0005 Vendor=1234 Product=5678 Version=0111\n'
                'N: Name="Same name"\nP: Phys=bt-1\nH: Handlers=event11 js2\n')
        with patch('builtins.open', return_value=io.StringIO(proc)):
            devices = mcp.get_input_devices()['joysticks']
        self.assertEqual([(d['js_path'], d['event_path']) for d in devices],
                         [('/dev/input/js0', '/dev/input/event8'), ('/dev/input/js2', '/dev/input/event11')])


if __name__ == '__main__':
    unittest.main()
