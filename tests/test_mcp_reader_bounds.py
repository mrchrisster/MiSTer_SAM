"""Grab-compatible snapshot coverage and bounded byte-reader cancellation."""
import os
import struct
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from test_mcp import m, event


class ReaderBounds(unittest.TestCase):
    def test_metadata_sizes_complete_startup_snapshot(self):
        def ioctl(fd, kind, number, size):
            return {0x12: bytes([70]), 0x11: bytes([4]),
                    0x34: struct.pack('=512H', *range(512)),
                    0x32: bytes(range(64))}[number]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'js0'
            path.write_bytes(b'')
            with patch.object(m.InputBindings, 'ioctl', side_effect=ioctl),                  patch.object(m.InputBindings, 'read_map', autospec=True,
                              side_effect=lambda obj: setattr(obj, 'map_status', 'invalid')),                  patch.object(m.InputBindings, 'describe'):
                bindings = m.InputBindings({'js_path': str(path)}, m.SamState())
            self.assertEqual(bindings.snapshot_bytes, 74 * m.JS_EVENT_SIZE)

    def test_button_beyond_first_64_records_is_detected(self):
        # Metadata failure also needs complete coverage; startup axes precede
        # buttons, and the old 512-byte sample never reached button 65.
        def snapshot(pressed):
            return b''.join(struct.pack(m.JS_EVENT_FORMAT, 0,
                                       int(pressed and number == 65), 0x81, number)
                            for number in range(80))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'js0'
            path.write_bytes(snapshot(False))
            stop = threading.Event()
            state = m.SamState()
            state.set_sam_running(True)
            calls = []
            class Loop:
                def call_soon_threadsafe(self, *args):
                    calls.append(args)
                    stop.set()
            waits = 0
            original_wait = stop.wait
            def wait(timeout):
                nonlocal waits
                waits += 1
                if waits == 1:
                    path.write_bytes(snapshot(True))
                    return False
                stop.set()
                return original_wait(0)
            with patch.object(m.InputBindings, 'setup'),                  patch.object(m.InputBindings, 'describe'),                  patch.object(stop, 'wait', side_effect=wait):
                m.joystick_poller_thread({'js_path': str(path)}, state, {}, Loop(), stop)
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][1], 'default')

    def test_generic_action_uses_keyed_init_not_queued_or_reordered_records(self):
        with patch.object(m.InputBindings, 'setup'), patch.object(m.InputBindings, 'describe'):
            bindings = m.InputBindings({}, m.SamState())
        before = [event(0x81, 1, 0), event(0x81, 2, 0)]
        after = [event(0x81, 2, 0), event(0x81, 1, 1), event(1, 99, 1)]
        self.assertEqual(bindings.action(before, after), 'default')
        # A queued press without a changed INIT state cannot replay old input.
        self.assertIsNone(bindings.action(before, before + [event(1, 99, 1)]))

    def test_activity_does_not_write_terminal_or_hold_lock_during_debug(self):
        state = m.SamState()
        state.set_sam_running(True)
        class Debug:
            def emit(self, message):
                self.assert_unlocked = state._lock.acquire(blocking=False)
                if self.assert_unlocked:
                    state._lock.release()
        debug = Debug()
        state.input_debug_output = debug
        with patch('builtins.print', side_effect=AssertionError('synchronous terminal output')):
            state.update_activity()
            state.set_pending_action('default')
            state.samdebug = True
            state.update_activity()
            state.set_pending_action('next')
        self.assertTrue(debug.assert_unlocked)
        self.assertEqual(state.consume_pending_action(), 'next')

    def pipe_reader(self, function, send=False):
        read_fd, write_fd = os.pipe()
        stop = threading.Event()
        opened = threading.Event()
        routed = threading.Event()
        handles = []
        def open_device(*args, **kwargs):
            handle = os.fdopen(os.dup(read_fd), 'rb', buffering=0)
            handles.append(handle)
            opened.set()
            return handle
        class Loop:
            def call_soon_threadsafe(self, *args):
                routed.set()
                stop.set()
        thread = threading.Thread(target=function,
                                  args=('fake-device', m.SamState(), Loop(), stop))
        try:
            with patch.object(m, 'open', create=True, side_effect=open_device):
                thread.start()
                self.assertTrue(opened.wait(1))
                if send:
                    started = time.monotonic()
                    os.write(write_fd, b'\x01')
                    self.assertTrue(routed.wait(.2), 'readiness must wake before cancellation timeout')
                    self.assertLess(time.monotonic() - started, .2)
                stop.set()
                thread.join(.6)
                self.assertFalse(thread.is_alive(), 'silent reader must exit after cancellation')
            self.assertTrue(all(handle.closed for handle in handles))
            self.assertEqual(routed.is_set(), send)
        finally:
            stop.set()
            os.close(write_fd)
            thread.join(1)
            os.close(read_fd)

    def test_silent_keyboard_cancellation_closes_descriptor(self):
        self.pipe_reader(m.keyboard_poller_thread)

    def test_silent_mouse_cancellation_closes_descriptor(self):
        self.pipe_reader(m.mouse_poller_thread)

    def test_keyboard_report_wakes_immediately_and_debounce_is_interruptible(self):
        self.pipe_reader(m.keyboard_poller_thread, send=True)

    def test_mouse_report_wakes_immediately_and_debounce_is_interruptible(self):
        self.pipe_reader(m.mouse_poller_thread, send=True)


if __name__ == '__main__':
    unittest.main()
