"""MCP observation/gating fixtures; these do not prove physical input coverage."""
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
import test_mcp_input_mapping as mapping

mcp, events = mapping.mcp, mapping.events


class InputDebugTests(unittest.TestCase):
    def resolver(self, root, values=None, state=None):
        return mapping.MappingTests().resolver(root, values, state)

    def output(self, state):
        return mapping.MappingTests().output(state)

    def test_all_observed_presses_include_saved_and_db_labels_and_raw_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = [0] * 32
            values[11] = 314
            binding, state = self.resolver(Path(tmp), values)
            state.input_debug_output.reset_mock()
            binding.report(events(), events((1, 1, 1)))
            log = self.output(state)
            self.assertEqual(log.count(' DOWN '), 3)
            self.assertIn('MiSTer=unmapped DB=start js_button=0 Linux=315 BTN_START source=MiSTer-map action=default', log)
            self.assertIn('MiSTer=Start DB=back js_button=1 Linux=314 BTN_SELECT source=MiSTer-map action=start', log)
            self.assertIn('MiSTer=unmapped DB=unmapped js_button=2 Linux=312 BTN_TL2 source=MiSTer-map action=default', log)
            self.assertNotIn('DB MATCH', log)

    def test_unknown_button_metadata_still_reports_observed_number(self):
        state = mcp.SamState()
        state.samdebug = True
        state.input_debug_output = Mock()
        with patch.object(mcp.InputBindings, 'setup'):
            binding = mcp.InputBindings({}, state)
        state.input_debug_output.reset_mock()
        binding.report(events(), events((0, 0, 1)))
        self.assertIn('js_button=2 Linux=unknown source=generic action=default', self.output(state))

    def test_debug_off_remains_silent_with_existing_output_queue(self):
        with tempfile.TemporaryDirectory() as tmp:
            binding, state = self.resolver(Path(tmp))
            state.input_debug_output.reset_mock()
            state.samdebug = False
            binding.report(events(), events((1, 1, 1)))
            binding.describe()
            binding.log('DB MATCH cached')
            state.input_debug_output.emit.assert_not_called()

    def test_debug_rescan_adds_db_labels_to_existing_saved_map(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = mcp.SamState()
            state.input_debug_output = Mock()
            values = [0] * 32
            values[11] = 314
            before, _ = self.resolver(Path(tmp), values, state)
            self.assertIsNone(before.db)
            self.assertIsNone(state.input_database)
            state.samdebug = True
            after, _ = self.resolver(Path(tmp), values, state)
            self.assertIsNotNone(after.db)
            self.assertEqual(after.actions, before.actions)
            state.input_debug_output.reset_mock()
            after.report(events(), events((0, 1, 0)))
            self.assertIn('MiSTer=Start DB=back', self.output(state))

    def poll_joy(self, running):
        with tempfile.TemporaryDirectory() as tmp:
            binding, state = self.resolver(Path(tmp))
            state.listenjoy = False
            state.set_sam_running(running)
            state.update_activity = Mock()
            state.input_debug_output.reset_mock()
            samples = iter([events(), events((1, 1, 1)), events((1, 1, 1)), events()])
            file = Mock()
            file.fileno.return_value = 12
            file.read.side_effect = lambda size: b''.join(struct.pack('IhBB', 0, e['value'], e['type'], e['number']) for e in next(samples))
            opened = Mock()
            opened.__enter__ = Mock(return_value=file)
            opened.__exit__ = Mock(return_value=False)
            stop, loop = Mock(), Mock()
            ticks = 0
            def wait(interval):
                nonlocal ticks
                self.assertEqual(interval, .02)
                ticks += 1
            stop.wait.side_effect = wait
            stop.is_set.side_effect = lambda: ticks >= 4
            with patch.object(mcp, 'InputBindings', return_value=binding), patch('builtins.open', return_value=opened), patch.object(mcp.os, 'set_blocking'), patch('builtins.print'):
                mcp.joystick_poller_thread(binding.device, state, {}, loop, stop)
            loop.call_soon_threadsafe.assert_not_called()
            state.update_activity.assert_not_called()
            log = self.output(state)
            self.assertEqual(log.count(' DOWN '), 3)
            self.assertEqual(log.count('detection=disabled'), 3)

    def test_disabled_joystick_actions_still_report_during_sam(self):
        self.poll_joy(True)

    def test_disabled_joystick_does_not_reset_idle_while_reporting(self):
        self.poll_joy(False)

    def test_raw_keyboard_debug_observes_without_disabled_action_dispatch(self):
        state = mcp.SamState()
        state.samdebug = True
        state.listenkeyboard = False
        state.input_debug_output = Mock()
        loop, stop, handle = Mock(), Mock(), Mock()
        handle.read.return_value = b'\x00\x00\x04\x00\x00\x00\x00\x00'
        handle.__enter__ = Mock(return_value=handle)
        handle.__exit__ = Mock(return_value=False)
        stop.is_set.side_effect = [False, False, False, True]
        with patch('builtins.open', return_value=handle), patch.object(mcp.os, 'set_blocking'), patch.object(mcp.select, 'select', return_value=([handle], [], [])), patch('builtins.print'):
            mcp.keyboard_poller_thread('/dev/hidraw9', state, loop, stop)
        loop.call_soon_threadsafe.assert_not_called()
        handle.read.assert_called_once_with(64)
        log = self.output(state)
        self.assertIn('Keyboard device=/dev/hidraw9 report=0000040000000000', log)
        self.assertIn('detection=disabled', log)
        self.assertIn('key/button names unavailable', log)
        self.assertNotIn('KEY_A', log)

    def test_closed_output_rejects_messages_even_if_queue_was_full(self):
        with patch.object(mcp.threading, 'Thread'):
            output = mcp.InputDebugOutput(size=1)
        output.emit('one')
        output.close()
        output.emit('two')
        self.assertFalse(output.is_alive())
        self.assertEqual(output.messages.get_nowait(), 'one')
        self.assertTrue(output.messages.empty())

    def test_broken_terminal_marks_queue_dead_for_debug_enable_recovery(self):
        with patch.object(mcp.threading, 'Thread'):
            output = mcp.InputDebugOutput()
        output.emit('press')
        with patch('builtins.print', side_effect=BrokenPipeError):
            output.run()
        self.assertFalse(output.is_alive())
        output.emit('later')
        self.assertTrue(output.messages.empty())


if __name__ == '__main__':
    unittest.main()
