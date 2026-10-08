"""Host-side fixtures; live ioctl compatibility still needs MiSTer hardware."""
import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
from paths import PACKAGE
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch

SCRIPT = PACKAGE / '.MiSTer_SAM/tools-extras/sam_input_debug.py'
spec = importlib.util.spec_from_file_location('sam_input_debug', SCRIPT)
debug = importlib.util.module_from_spec(spec)
spec.loader.exec_module(debug)


class InputDebugTests(unittest.TestCase):
    def test_database_guid_distinguishes_bus_and_version(self):
        self.assertEqual(debug.controller_guid((3, 0x0e8f, 0x3013, 0x110)),
                         '030000008f0e00001330000010010000')
        self.assertEqual(debug.controller_guid((5, 0x054c, 0x0268, 0x8100)),
                         '050000004c0500006802000000810000')
        self.assertNotEqual(debug.controller_guid((3, 0x0e8f, 0x3013, 0x101)),
                            debug.controller_guid((3, 0x0e8f, 0x3013, 0x110)))

    def test_database_binding_uses_capabilities_for_buttons_axes_and_hats(self):
        keys, axes = {30, 315, 288, 314}, {0, 2, 5, 16, 17}
        self.assertEqual(debug.db_binding('b0', keys, axes), ('button', 288, '', False))
        self.assertEqual(debug.db_binding('b3', keys, axes), ('button', 30, '', False))
        self.assertEqual(debug.db_binding('a1', keys, axes), ('axis', 2, '', False))
        self.assertEqual(debug.db_binding('-a2~', keys, axes), ('axis', 5, '-', True))
        self.assertEqual(debug.db_binding('h0.1', keys, axes), ('axis', 17, '-', False))
        self.assertEqual(debug.db_binding('h0.2', keys, axes), ('axis', 16, '+', False))
        for text in ('b4', 'a3', 'h0.3', 'h1.1', 'h4.1', 'b-1', '+b0', 'a-1'):
            with self.assertRaises(ValueError, msg=text):
                debug.db_binding(text, keys, axes)

    def test_database_user_priority_last_entry_and_exact_identity(self):
        identity = (3, 0x1234, 0x5678, 0x111)
        guid = debug.controller_guid(identity)
        other = debug.controller_guid((3, 0x1234, 0x5678, 0x112))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'gamecontrollerdb.txt').write_text(guid + ',Default,start:b0,platform:Linux,\n')
            user = root / 'gamecontrollerdb_user.txt'
            user.write_text('# comment\nmalformed line\n' + guid + ',Old,start:b0,platform:Linux,\n'
                            + guid + ',Override,start:b1,back:b0,platform:MiSTer,\n'
                            + guid + ',Wrong platform,start:b0,platform:Windows,\n'
                            + guid + ',Core only,start:b0,mistercore:SNES,platform:MiSTer,\n'
                            + other + ',Wrong version,start:b0,platform:Linux,\n')
            log = []
            db = debug.ControllerDB(tmp, log.append)
            found = db.resolve(identity, {314, 315}, set(), log.append)
            self.assertEqual(found['start'], ('b1', ('button', 315, '', False)))
            self.assertTrue(any("name='Override'" in line for line in log))
            self.assertTrue(any('core-specific' in line for line in log))
            self.assertIsNone(db.resolve((5, 0x1234, 0x5678, 0x111), {314, 315}, set(), log.append))
            user.write_text(guid + ',Broken,start:b99,platform:Linux,\n')
            found = debug.ControllerDB(tmp, log.append).resolve(identity, {314, 315}, set(), log.append)
            self.assertEqual(found['start'][1][1], 314)
            self.assertTrue(any('DB UNSUPPORTED' in line for line in log))

    def test_database_pressure_axis_does_not_invent_button_assignment(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = [0] * 32
            values[11] = 314  # Saved reassignment differs from DB Start.
            monitor, log = self.make_monitor(Path(tmp), values)
            monitor.input_id = (5, 0x054c, 0x0268, 0x8100)
            monitor.key_caps = {312, 314, 315}
            monitor.abs_codes = {0, 1, 2, 16, 17}
            monitor.buttons = [315, 312, 314]  # Actual joydev order differs from DB.
            monitor.axes = [2, 0, 1, 16, 17]
            guid = debug.controller_guid(monitor.input_id)
            (Path(tmp) / 'gamecontrollerdb.txt').write_text(
                guid + ',PS3,start:b2,back:b1,lefttrigger:a2,dpup:h0.1,platform:Linux,\n')
            monitor.args.controller_database = debug.ControllerDB(tmp, log.append)
            monitor.read_controller_db()
            self.assertEqual(monitor.db_labels('button', 312), 'unmapped')
            self.assertEqual(monitor.db_labels('axis', 2), 'lefttrigger')
            self.assertEqual(monitor.db_labels('axis', 17), 'dpup(-)')
            self.assertEqual(monitor.db_labels('button', 315), 'start')
            self.assertEqual(debug.labels(314, monitor.mapping), 'Start')
            self.assertEqual(debug.labels(315, monitor.mapping), 'unmapped')
            self.assertTrue(any('DB start' in line and 'js_buttons=[0]' in line for line in log))
            monitor.state_fd = 123
            monitor.previous_keys = set()
            monitor.previous_abs = {2: (0, 0, 255, 0, 0, 0)}
            bits = bytearray(96)
            bits[312 // 8] |= 1 << (312 % 8)
            with patch.object(monitor, 'sample_js', return_value=None), \
                    patch.object(monitor, 'read_stream'), \
                    patch.object(debug, 'ioctl_bytes', return_value=bytes(bits)), \
                    patch.object(monitor, 'sample_abs', return_value={2: (255, 0, 255, 0, 0, 0)}):
                monitor.poll()
            self.assertTrue(any('Linux=312 BTN_TL2 MiSTer=unmapped DB=unmapped' in line for line in log))
            self.assertTrue(any('EVIOCGABS axis=2' in line and 'DB=lefttrigger' in line for line in log))

    def test_hotplug_add_remove_and_reused_node_gets_fresh_reader(self):
        log = []
        args = argparse.Namespace(devices=[])
        first = dict(js='/dev/input/js0', event='/dev/input/event8', name='Pad',
                     id='1234_5678', phys='usb-1', uniq='', sysfs='/devices/input100')
        second = dict(first, js='/dev/input/js2', event='/dev/input/event11', name='PS3',
                      id='054c_0268', sysfs='/devices/input101')
        def new_monitor(device, args, log):
            return Mock(d=device.copy())
        with patch.object(debug, 'Monitor', side_effect=new_monitor) as constructor:
            registry = debug.DeviceRegistry(args, log.append)
            registry.sync([])
            self.assertTrue(registry.waiting)
            registry.sync([first])
            old = registry.current[first['js']]
            registry.sync([first, second])
            self.assertEqual(constructor.call_count, 2)
            self.assertIs(registry.current[first['js']], old)
            registry.sync([dict(first, sysfs='/devices/input102'), second])
            old.close.assert_called_once()
            self.assertIsNot(registry.current[first['js']], old)
            self.assertEqual(constructor.call_count, 3)
            ps3 = registry.current[second['js']]
            registry.sync([first])
            ps3.summary.assert_called_once()
            ps3.close.assert_called_once()
            self.assertNotIn(second['js'], registry.current)
            registry.close()
        self.assertTrue(any('HOTPLUG ADDED /dev/input/js2' in line for line in log))

    def test_explicit_paths_do_not_expand_to_unselected_gamepads(self):
        selected = dict(js='/dev/input/js0', event='/dev/input/event8')
        added = dict(js='/dev/input/js2', event='/dev/input/event11')
        self.assertEqual(debug.select_devices([selected, added], ['/dev/input/js0']), [selected])
        self.assertEqual(debug.select_devices([selected, added], ['/dev/input/event11']), [added])
        self.assertEqual(debug.select_devices([selected, added], []), [selected, added])

    def test_ioctl_requests_match_linux_arm_headers(self):
        self.assertEqual(debug.ior('E', 0x18, 96), 0x80604518)
        self.assertEqual(debug.ior('j', 0x34, 1024), 0x84006a34)
        self.assertEqual(debug.ior('j', 0x32, 64), 0x80406a32)
        self.assertEqual(debug.ior('E', 0x40, 24), 0x80184540)

    def test_ioctl_mutates_and_returns_state_buffer(self):
        def fake(fd, request, data, mutate):
            self.assertEqual(fd, 123)
            self.assertTrue(mutate)
            data[39] = 8  # Linux BTN_START=315
            return 0
        with patch.object(debug.fcntl, 'ioctl', side_effect=fake):
            bits = debug.ioctl_bytes(123, debug.ior('E', 0x18, 96), 96)
        self.assertEqual(debug.bit_codes(bits), {315})

    def test_pairs_nodes_from_same_proc_block_not_matching_name(self):
        text = ('I: Bus=0003 Vendor=054c Product=0ce6 Version=0111\n'
                'N: Name="Identical pads"\nP: Phys=usb-1/input0\nU: Uniq=unit-one\n'
                'H: Handlers=event3 js0 \n\n'
                'I: Bus=0003 Vendor=054c Product=0ce6 Version=0111\n'
                'N: Name="Identical pads"\nP: Phys=usb-2/input0\n'
                'H: Handlers=kbd event7 js1\n\n'
                'I: Bus=0003 Vendor=1234 Product=5678 Version=0111\n'
                'N: Name="Keyboard encoder"\nH: Handlers=kbd event8\n')
        devices = debug.parse_proc_devices(text)
        self.assertEqual([(d['js'], d['event']) for d in devices],
                         [('/dev/input/js0', '/dev/input/event3'),
                          ('/dev/input/js1', '/dev/input/event7'), (None, '/dev/input/event8')])
        self.assertEqual(devices[0]['id'], '054c_0ce6')
        self.assertEqual(devices[0]['uniq'], 'unit-one')

    def test_map_preserves_reassigned_start_unassigned_and_wide_values(self):
        values = [0] * 32
        values[10], values[11], values[23] = 315, 314, 304 | (305 << 16)
        values[4], values[5] = 800, 0x100013b
        mapping = debug.decode_map(struct.pack('<32I', *values))
        self.assertEqual(debug.labels(314, mapping), 'Start')
        self.assertEqual(debug.labels(315, mapping), 'Select')
        self.assertEqual(debug.labels(0, mapping), 'unmapped')
        self.assertEqual(mapping[5], 0x100013b)
        self.assertIn('axis 16 -', debug.code_text(800))
        self.assertIn('NOT truncated', debug.code_text(mapping[5]))
        for size in (0, 44, 127, 129):
            with self.assertRaises(ValueError):
                debug.decode_map(bytes(size))

    def test_js_init_snapshot_ignores_queued_events_and_order(self):
        data = (debug.JS_EVENT.pack(0, 0, 0x81, 0) + debug.JS_EVENT.pack(0, 1, 0x81, 1)
                + debug.JS_EVENT.pack(0, -32767, 0x82, 0) + debug.JS_EVENT.pack(1, 0, 1, 1))
        records, snapshot = debug.decode_js(data)
        self.assertEqual(len(records), 4)
        self.assertEqual(snapshot, {(1, 0): 0, (1, 1): 1, (2, 0): -32767})
        self.assertEqual(debug.changed_values({(1, 1): 0, (1, 0): 0}, snapshot), [((1, 1), 0, 1)])
        with self.assertRaises(ValueError):
            debug.decode_js(b'partial')

    def test_small_hat_ranges_remain_visible(self):
        self.assertEqual(debug.abs_log_threshold((0, -1, 1, 0, 0, 0), 2000), 1)
        self.assertEqual(debug.abs_log_threshold((0, -32768, 32767, 0, 0, 0), 2000), 2000)
        self.assertEqual(debug.abs_log_threshold((0, 0, 255, 0, 0, 0), 2000), 63)

    def make_monitor(self, root, values):
        (root / 'inputs').mkdir()
        path = root / 'inputs/input_1234_5678_v3.map'
        path.write_bytes(struct.pack('<32I', *values))
        log = []
        args = argparse.Namespace(config_dir=str(root), sam_dir=str(root), map=None, axis_delta=2000)
        device = dict(js='/dev/input/js0', event='/dev/input/event3', id='1234_5678',
                      name='Test pad', phys='usb-1', uniq='', handlers=['event3', 'js0'])
        with patch.object(debug.Monitor, 'open_event'), patch.object(debug.Monitor, 'read_js_maps'):
            monitor = debug.Monitor(device, args, log.append)
        monitor.buttons = [315, 314]
        monitor.key_caps = {315, 314}
        return monitor, log

    def test_preferred_invalid_map_is_reported_not_silently_replaced(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            values = [0] * 32
            values[11] = 315
            monitor, log = self.make_monitor(root, values)
            (root / 'input_1234_5678_v3.map').write_bytes(struct.pack('<32I', *values))
            (root / 'inputs/input_1234_5678_v3.map').write_bytes(b'bad')
            monitor.mapping = None
            monitor.read_mister_map()
            self.assertIsNone(monitor.mapping)
            self.assertTrue(any('expected 128 bytes' in line for line in log))

    def test_grabbed_stream_can_be_empty_while_both_snapshots_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = [0] * 32
            values[10], values[11] = 315, 314
            monitor, log = self.make_monitor(Path(tmp), values)
            monitor.state_fd = 123
            samples = iter([{(1, 0): 0, (1, 1): 0}, {(1, 0): 0, (1, 1): 1},
                            {(1, 0): 0, (1, 1): 0}])
            states = iter([set(), {314}, set()])
            def fake_ioctl(fd, request, size):
                bits = bytearray(96)
                for code in next(states):
                    bits[code // 8] |= 1 << (code % 8)
                return bytes(bits)
            with patch.object(monitor, 'sample_js', side_effect=lambda: next(samples)), \
                    patch.object(monitor, 'read_stream'), \
                    patch.object(debug, 'ioctl_bytes', side_effect=fake_ioctl):
                for _ in range(3):
                    monitor.poll()
            self.assertEqual(monitor.stats['EVIOCGKEY changes'], 2)
            self.assertEqual(monitor.stats['JS button changes'], 2)
            self.assertEqual(monitor.stats['raw events'], 0)
            self.assertEqual(monitor.observed, {314})
            self.assertTrue(any('JS DOWN button=1 Linux=314 MiSTer=Start' in line for line in log))

    def test_persistent_disagreement_is_distinguished_from_one_sample_race(self):
        with tempfile.TemporaryDirectory() as tmp:
            monitor, log = self.make_monitor(Path(tmp), [0] * 32)
            monitor.state_fd = 123
            with patch.object(monitor, 'sample_js', return_value={(1, 0): 1, (1, 1): 0}), \
                    patch.object(monitor, 'read_stream'), \
                    patch.object(debug, 'ioctl_bytes', return_value=bytes(96)):
                monitor.poll()
                self.assertFalse(any('DISAGREE' in line for line in log))
                monitor.poll()
                monitor.poll()
            self.assertEqual(monitor.stats['persistent button disagreements'], 1)

    def test_raw_event_parser_handles_partial_buffers(self):
        with tempfile.TemporaryDirectory() as tmp:
            monitor, log = self.make_monitor(Path(tmp), [0] * 32)
            monitor.stream_fd = 99
            event = debug.INPUT_EVENT.pack(12, 345, 1, 315, 1)
            with patch.object(debug.os, 'read', side_effect=[event[:5], BlockingIOError(),
                                                          event[5:], BlockingIOError()]):
                monitor.read_stream()
                self.assertEqual(monitor.stats['raw events'], 0)
                monitor.read_stream()
            self.assertEqual(monitor.stats['raw events'], 1)
            self.assertTrue(any('STREAM type=1 code=315 value=1' in line for line in log))

    def test_complete_cli_produces_map_state_and_summary_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'inputs').mkdir()
            values = [0] * 32
            values[10], values[11] = 315, 314
            (root / 'inputs/input_1234_5678_v3.map').write_bytes(struct.pack('<32I', *values))
            (root / 'sam_controllers.json').write_text('{"default":{"button":{"start":1,"next":0}}}')
            guid = debug.controller_guid((3, 0x1234, 0x5678, 0x111))
            (root / 'gamecontrollerdb.txt').write_text(guid + ',Test pad,start:b0,back:b1,platform:Linux,\n')
            proc = ('I: Bus=0003 Vendor=1234 Product=5678 Version=0111\n'
                    'N: Name="Test pad"\nP: Phys=usb-1/input0\n'
                    'H: Handlers=event3 js0\n')
            actual_open = open
            sample = 0
            def fake_open(path, *args, **kwargs):
                if path == '/proc/bus/input/devices':
                    return io.StringIO(proc)
                if path == '/tmp/CORENAME':
                    return io.StringIO('NES')
                return actual_open(path, *args, **kwargs)
            def fake_ioctl(fd, request, size):
                if request == debug.ior('j', 0x12, 1):
                    return b'\x02'
                if request == debug.ior('j', 0x11, 1):
                    return b'\x00'
                if request == debug.ior('j', 0x34, 1024):
                    return struct.pack('=512H', 315, 314, *([0] * 510))
                if request == debug.ior('j', 0x32, 64):
                    return bytes(64)
                if request == debug.ior('E', 0x02, 8):
                    return struct.pack('=4H', 3, 0x1234, 0x5678, 0x111)
                if request == debug.ior('E', 0x23, 8):
                    return bytes(8)
                bits = bytearray(96)
                if request == debug.ior('E', 0x21, 96):
                    for code in (314, 315):
                        bits[code // 8] |= 1 << (code % 8)
                elif request == debug.ior('E', 0x18, 96) and sample > 1:
                    bits[314 // 8] |= 1 << (314 % 8)
                return bytes(bits)
            def fake_read(fd, size):
                nonlocal sample
                if fd == 102:
                    sample += 1
                    return debug.JS_EVENT.pack(0, 0, 0x81, 0) + debug.JS_EVENT.pack(0, int(sample > 1), 0x81, 1)
                raise BlockingIOError()
            with patch.object(debug.sys, 'platform', 'linux'), \
                    patch('builtins.open', side_effect=fake_open), \
                    patch.object(debug.os, 'open', side_effect=lambda path, flags: 102 if 'js' in path else 101), \
                    patch.object(debug.os, 'close'), patch.object(debug.os, 'read', side_effect=fake_read), \
                    patch.object(debug, 'ioctl_bytes', side_effect=fake_ioctl), \
                    contextlib.redirect_stdout(io.StringIO()):
                result = debug.main(['/dev/input/js0', '--config-dir', str(root), '--sam-dir', str(root),
                                     '--controllerdb-dir', str(root),
                                     '--duration', '0.035', '--interval', '0.01', '--log', str(root / 'log.txt')])
            log = (root / 'log.txt').read_text()
            self.assertEqual(result, 0)
            self.assertIn('DECODED MAP', log)
            self.assertIn("CORENAME='NES'", log)
            self.assertIn('EVIOCGKEY DOWN Linux=314', log)
            self.assertIn('JS DOWN button=1 Linux=314 MiSTer=Start SAM=start EVIOCGKEY=1', log)
            self.assertIn('EVIOCGKEY DOWN Linux=314 BTN_SELECT MiSTer=Start DB=start', log)
            self.assertIn('DB MATCH', log)
            self.assertIn('SUMMARY js0', log)
            self.assertNotIn('DISAGREE', log)


if __name__ == '__main__':
    unittest.main()
