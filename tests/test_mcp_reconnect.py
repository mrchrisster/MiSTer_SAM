"""Physical node generations survive coalesced Bluetooth disconnect/reconnect."""
import asyncio
import errno
from pathlib import Path
import struct
import tempfile
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from test_mcp import m


class Reconnect(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.state = m.SamState()
        self.readers = []
        self.closed = []
        self.device = dict(js_path='/dev/input/js0', event_path='/dev/input/event10',
                           sysfs='/devices/virtual/misc/uhid/input100', name='Bluetooth Pad',
                           proc_phys='bluetooth-pad/input0', id='054c_0268')
        self.generation = 1
        self.inventory = dict(joysticks=[self.device], keyboards=[], mice=[])
        real_stat = m.os.stat
        def stat(path, *args, **kwargs):
            if str(path).startswith('/dev/input/js'):
                return SimpleNamespace(st_dev=1, st_ino=self.generation,
                                       st_rdev=13, st_ctime_ns=self.generation)
            return real_stat(path, *args, **kwargs)
        self.patches = [patch.dict(m.tasks, {}, clear=True),
                        patch.object(m, 'get_input_devices', side_effect=lambda: self.inventory),
                        patch.object(m.os, 'stat', side_effect=stat),
                        patch.object(m, 'watch_joystick_device', side_effect=self.watch),
                        patch('builtins.print')]
        for item in self.patches:
            item.start()
        self.addCleanup(lambda: [item.stop() for item in reversed(self.patches)])

    async def asyncTearDown(self):
        for task, stop in list(m.tasks.values()):
            stop.set()
            task.cancel()
        await asyncio.gather(*(task for task, _ in m.tasks.values()), return_exceptions=True)

    async def watch(self, device, state, config, loop):
        if self.readers:
            # A replacement must finish the old reader before starting anew.
            self.assertTrue(self.readers[-1][1].cancelled())
            self.assertIn(self.readers[-1][0], self.closed)
        path = device['js_path']
        async def reader():
            try:
                await asyncio.Event().wait()
            finally:
                self.closed.append(path)
        task = asyncio.create_task(reader())
        stop = threading.Event()
        m.tasks[path] = (task, stop)
        self.readers.append((path, task, stop, device.copy()))

    async def scan(self):
        await m._rescan_devices_impl(self.state, {}, {}, asyncio.get_running_loop())
        await asyncio.sleep(0)

    async def test_unchanged_device_keeps_reader_and_cached_bindings(self):
        await self.scan()
        first = self.readers[0]
        await self.scan()
        self.assertEqual(len(self.readers), 1)
        self.assertFalse(first[1].done())
        self.assertFalse(first[2].is_set())

    async def test_reconnect_same_js_number_refreshes_changed_event_and_sysfs(self):
        await self.scan()
        self.inventory['joysticks'] = [dict(self.device, event_path='/dev/input/event12',
                                          sysfs='/devices/virtual/misc/uhid/input101')]
        await self.scan()
        self.assertEqual(len(self.readers), 2)
        self.assertTrue(self.readers[0][2].is_set())
        self.assertEqual(self.readers[1][3]['event_path'], '/dev/input/event12')
        self.assertEqual(set(m.tasks), {'/dev/input/js0'})

    async def test_reconnect_identical_proc_record_but_new_node_rebuilds_reader(self):
        await self.scan()
        self.generation += 1
        await self.scan()
        self.assertEqual(len(self.readers), 2)
        self.assertTrue(self.readers[0][2].is_set())

    async def test_reconnect_changed_js_number_removes_old_reader(self):
        await self.scan()
        self.inventory['joysticks'] = [dict(self.device, js_path='/dev/input/js2',
                                          event_path='/dev/input/event12')]
        await self.scan()
        self.assertEqual(len(self.readers), 2)
        self.assertEqual(set(m.tasks), {'/dev/input/js2'})
        self.assertTrue(self.readers[0][2].is_set())

    async def test_disconnected_reader_is_recreated_even_when_identity_unchanged(self):
        await self.scan()
        old = self.readers[0][1]
        old.cancel()
        await asyncio.gather(old, return_exceptions=True)
        await self.scan()
        self.assertEqual(len(self.readers), 2)


class DisconnectedSnapshot(unittest.TestCase):
    def test_physical_queue_captures_epoch_only_for_a_new_action(self):
        state = m.SamState()
        state.set_sam_running(True)
        stop = threading.Event()
        loop = Mock()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'js0'
            path.write_bytes(struct.pack('IhBB', 0, 0, 0x81, 0))
            ticks = 0
            def wait(delay):
                nonlocal ticks
                ticks += 1
                if ticks == 2:
                    path.write_bytes(struct.pack('IhBB', 0, 1, 0x81, 0))
                if ticks == 3:
                    stop.set()
            with patch.object(m.InputBindings, 'setup'), patch.object(m.InputBindings, 'describe'), \
                    patch.object(m.time, 'time', return_value=1234.5) as clock, \
                    patch.object(stop, 'wait', side_effect=wait), patch('builtins.print'):
                m.joystick_poller_thread({'js_path': str(path)}, state, {}, loop, stop)
        clock.assert_called_once_with()
        loop.call_soon_threadsafe.assert_called_once_with(
            m.handle_action, 'default', state, loop, 'joystick', str(path), 1234.5)

    def test_compatibility_wrapper_preserves_observation_time_and_device(self):
        state, loop = Mock(), Mock()
        with patch.object(m, 'lifecycle_coordinator') as coordinator:
            m.handle_action('default', state, loop, 'joystick', '/dev/input/js0', 1234.5)
        coordinator.assert_called_once_with('/dev/input/js0')
        coordinator.return_value.handle_action.assert_called_once_with(
            'default', state, loop, 'joystick', event_time=1234.5)

    def test_missing_or_disconnected_node_ends_reader_for_fresh_discovery(self):
        for error in (FileNotFoundError(), OSError(errno.ENODEV, 'removed'),
                      OSError(errno.ENXIO, 'removed')):
            with self.subTest(error=error), patch.object(m, 'InputBindings') as binding, \
                    patch('builtins.open', side_effect=error), patch('builtins.print'):
                stop = threading.Event()
                with patch.object(stop, 'wait') as wait:
                    loop = Mock()
                    m.joystick_poller_thread({'js_path': '/dev/input/js0'}, m.SamState(), {}, loop, stop)
                wait.assert_not_called()
                loop.call_soon_threadsafe.assert_not_called()
                binding.assert_called_once()

    def test_cancellation_during_snapshot_cannot_publish_old_reader_input(self):
        stop = threading.Event()
        handle = Mock()
        handle.fileno.return_value = 12
        def read(size):
            stop.set()
            return b'old snapshot'
        handle.read.side_effect = read
        opened = Mock(__enter__=Mock(return_value=handle), __exit__=Mock(return_value=False))
        with patch.object(m, 'InputBindings') as binding, patch('builtins.open', return_value=opened), \
                patch.object(m.os, 'set_blocking'), patch('builtins.print'):
            m.joystick_poller_thread({'js_path': '/dev/input/js0'}, m.SamState(), {}, Mock(), stop)
        binding.return_value.changes.assert_not_called()


if __name__ == '__main__':
    unittest.main()
