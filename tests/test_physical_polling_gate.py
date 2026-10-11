"""Menu-only resource gate never samples physical devices during manual games."""
import threading
import struct
import unittest
from unittest.mock import Mock, patch
import test_mcp as fixture
m = fixture.m


class PhysicalPolling(unittest.TestCase):
    def test_menuonly_manual_game_pauses_but_menu_sam_and_unknown_resume(self):
        state = m.SamState(menu_only=True)
        self.assertFalse(m.update_physical_polling(state, None, False))
        self.assertFalse(m.physical_polling_enabled(state))
        for owner, in_menu in ((None, True), ({'pid': '1'}, False), (None, None)):
            self.assertTrue(m.update_physical_polling(state, owner, in_menu))
        state.menu_only = False
        self.assertTrue(m.update_physical_polling(state, None, False))

    def test_sam_startup_immediately_overrides_cached_manual_game_gate(self):
        state = m.SamState(menu_only=True)
        state.physical_polling = False
        state.set_sam_starting(True)
        self.assertTrue(m.physical_polling_enabled(state))
        state.set_sam_starting(False); state.set_sam_running(True)
        self.assertTrue(m.physical_polling_enabled(state))

    def test_joystick_gate_does_not_open_or_read_device_snapshots(self):
        state = m.SamState(menu_only=True); state.physical_polling = False
        stop = threading.Event()
        binding = Mock(); binding.last_events = ['old']; binding.last_snapshot = {'held': 1}
        with patch.object(m, 'InputBindings', return_value=binding), patch('builtins.open') as opened, \
             patch.object(stop, 'wait', side_effect=lambda delay: stop.set()) as wait:
            m.joystick_poller_thread({'js_path': '/dev/input/js9'}, state, {}, Mock(), stop)
        opened.assert_not_called(); wait.assert_called_once_with(.25)
        self.assertIsNone(binding.last_events); self.assertEqual(binding.last_snapshot, {})

    def test_keyboard_and_mouse_gate_leave_no_open_reader(self):
        for reader in (m.keyboard_poller_thread, m.mouse_poller_thread):
            state = m.SamState(menu_only=True); state.physical_polling = False
            stop = threading.Event()
            with patch('builtins.open') as opened, patch.object(stop, 'wait', side_effect=lambda delay: stop.set()):
                reader('/dev/hidraw9', state, Mock(), stop)
            opened.assert_not_called()

    def test_resume_seeds_held_state_then_reports_only_a_fresh_press(self):
        state = m.SamState(menu_only=True); state.physical_polling = False
        state.samdebug = True; state.input_debug_output = Mock(); state.update_activity = Mock()
        binding = object.__new__(m.InputBindings)
        binding.device = {'js_path': '/dev/input/js9', 'name': 'Pad'}; binding.state = state
        binding.snapshot_bytes = 8; binding.last_events = None; binding.last_snapshot = {}
        binding.actions = {}; binding.role_axes = set(); binding.axes = []; binding.source = 'generic'
        binding.button_labels = {0: 'DOWN MiSTer=B DB=a js_button=0 Linux=304 BTN_SOUTH'}
        values = iter((1, 0, 1))
        handle = Mock(); handle.fileno.return_value = 12
        handle.read.side_effect = lambda size: struct.pack('IhBB', 0, next(values), 0x81, 0)
        opened = Mock(); opened.__enter__ = Mock(return_value=handle); opened.__exit__ = Mock(return_value=False)
        ticks = [0]
        stop = Mock(); stop.is_set.side_effect = lambda: ticks[0] >= 4
        def wait(delay):
            ticks[0] += 1
            if delay == .25: state.physical_polling = True
        stop.wait.side_effect = wait
        with patch.object(m, 'InputBindings', return_value=binding), patch('builtins.open', return_value=opened), patch.object(m.os, 'set_blocking'):
            m.joystick_poller_thread(binding.device, state, {}, Mock(), stop)
        self.assertEqual(handle.read.call_count, 3)
        state.update_activity.assert_called_once_with(log_event=False)
        self.assertEqual(state.input_debug_output.emit.call_count, 1)


if __name__ == '__main__': unittest.main()
