"""Physical/virtual identity and deleted-node cache fixtures."""
import importlib.util
import asyncio
from pathlib import Path
from paths import PACKAGE
import unittest
from unittest.mock import AsyncMock, Mock, patch

PATH=PACKAGE / '.MiSTer_SAM/MiSTer_SAM_MCP.py'
spec=importlib.util.spec_from_file_location('mcp_hotplug_tests',PATH)
mcp=importlib.util.module_from_spec(spec);spec.loader.exec_module(mcp)

class HotplugFilterTests(unittest.TestCase):
    def test_seeded_virtual_delete_is_ignored_after_sysfs_disappears(self):
        filter=mcp.InputHotplugFilter(prime=False)
        filter.known['/dev/input/event4']=True
        with patch.object(filter,'classify',side_effect=AssertionError('deleted node queried')):
            self.assertFalse(filter.should_rescan('/dev/input/event4 DELETE'))
            self.assertFalse(filter.should_rescan('/dev/input/event4 DELETE'))

    def test_virtual_create_and_delete_do_not_trigger_rescan(self):
        filter=mcp.InputHotplugFilter(prime=False)
        with patch.object(filter,'classify',return_value=True):
            self.assertFalse(filter.should_rescan('/dev/input/event4 CREATE'))
        with patch.object(filter,'classify',return_value=None):
            self.assertFalse(filter.should_rescan('/dev/input/event4 DELETE'))

    def test_physical_bluetooth_nodes_create_and_delete_are_retained(self):
        filter=mcp.InputHotplugFilter(prime=False)
        with patch.object(filter,'classify',return_value=False):
            for name in ('event10','event11','js2'):
                self.assertTrue(filter.should_rescan('/dev/input/'+name+' CREATE'))
        with patch.object(filter,'classify',return_value=None):
            for name in ('event10','event11','js2'):
                self.assertTrue(filter.should_rescan('/dev/input/'+name+' DELETE'))

    def test_virtual_node_number_reused_for_physical_device_is_not_ignored(self):
        filter=mcp.InputHotplugFilter(prime=False)
        filter.known['/dev/input/event4']=True
        with patch.object(filter,'classify',return_value=False):
            self.assertTrue(filter.should_rescan('/dev/input/event4 CREATE'))
        self.assertTrue(filter.should_rescan('/dev/input/event4 DELETE'))

    def test_unknown_creation_is_retained_even_with_old_virtual_classification(self):
        filter=mcp.InputHotplugFilter(prime=False)
        filter.known['/dev/input/event4']=True
        with patch.object(filter,'classify',return_value=None):
            self.assertTrue(filter.should_rescan('/dev/input/event4 CREATE'))
            self.assertTrue(filter.should_rescan('/dev/input/event4 DELETE'))

    def test_bluetooth_uhid_below_virtual_misc_is_not_software_virtual(self):
        with patch.object(mcp.os.path,'exists',return_value=True), \
                patch.object(mcp.os.path,'realpath',return_value='/sys/devices/virtual/misc/uhid/0005:054C:09CC/input/input20'):
            self.assertFalse(mcp.InputHotplugFilter.classify('/dev/input/event11'))
        with patch.object(mcp.os.path,'exists',return_value=True), \
                patch.object(mcp.os.path,'realpath',return_value='/sys/devices/virtual/input/input20'):
            self.assertTrue(mcp.InputHotplugFilter.classify('/dev/input/event4'))

    def test_by_path_delete_uses_cached_target_identity(self):
        filter=mcp.InputHotplugFilter(prime=False)
        path='/dev/input/by-path/platform-fake-event-kbd'
        with patch.object(filter,'classify',return_value=True):
            self.assertFalse(filter.should_rescan(path+' CREATE'))
        with patch.object(filter,'classify',side_effect=AssertionError('removed symlink queried')):
            self.assertFalse(filter.should_rescan(path+' DELETE'))
        with patch.object(filter,'classify',return_value=False):
            self.assertTrue(filter.should_rescan(path+' CREATE'))
        self.assertTrue(filter.should_rescan(path+' DELETE'))

    def test_prime_caches_current_virtual_nodes_for_first_delete(self):
        def listdir(path):
            return ['event4','js0','input99'] if path=='/sys/class/input' else ['usb-test-event-joystick']
        def classify(path):
            return path=='/dev/input/event4'
        with patch.object(mcp.os,'listdir',side_effect=listdir), \
                patch.object(mcp.InputHotplugFilter,'classify',side_effect=classify):
            filter=mcp.InputHotplugFilter()
        self.assertFalse(filter.should_rescan('/dev/input/event4 DELETE'))
        self.assertTrue(filter.should_rescan('/dev/input/js0 DELETE'))
        self.assertTrue(filter.should_rescan('/dev/input/by-path/usb-test-event-joystick DELETE'))

    def test_unrelated_nodes_and_events_are_ignored(self):
        filter=mcp.InputHotplugFilter(prime=False)
        for line in ('/tmp/event4 CREATE','/dev/input/other CREATE','/dev/input/event4 ATTRIB','garbage', '/dev/input/by-path CREATE,ISDIR'):
            self.assertFalse(filter.should_rescan(line),line)

    def test_virtual_churn_does_not_schedule_or_delay_physical_rescan(self):
        async def exercise():
            filter=mcp.InputHotplugFilter(prime=False)
            filter.known['/dev/input/event4']=True
            process=Mock()
            process.wait=AsyncMock(return_value=0)
            lines=iter([
                b'/dev/input/event4 DELETE\n', b'/dev/input/event4 CREATE\n',
                b'/dev/input/js2 CREATE\n', b'/dev/input/event4 DELETE\n',
                b'/dev/input/event4 CREATE\n', b''])
            loop=Mock()
            timer=Mock();loop.call_later.return_value=timer
            async def readline():
                # Nothing may cancel the physical timer before stream shutdown.
                timer.cancel.assert_not_called()
                return next(lines)
            process.stdout.readline=AsyncMock(side_effect=readline)
            with patch.object(mcp,'InputHotplugFilter',return_value=filter), \
                    patch.object(filter,'classify',side_effect=lambda p: p.endswith('event4')), \
                    patch.object(mcp.asyncio,'create_subprocess_exec',AsyncMock(return_value=process)), \
                    patch('builtins.print'):
                await mcp.hotplug_monitor_native(Mock(),{}, {},loop)
            loop.call_later.assert_called_once()
            self.assertEqual(loop.call_later.call_args.args[0],2.0)
            timer.cancel.assert_called_once()  # Existing shutdown cleanup.
            process.wait.assert_awaited_once()
        asyncio.run(exercise())

if __name__=='__main__':unittest.main()
