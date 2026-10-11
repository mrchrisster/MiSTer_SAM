"""Console options, physical-only discovery and live debug reader rebuilding."""
import asyncio
import contextlib
import io
import threading
import unittest
from unittest.mock import AsyncMock,Mock,patch
import test_mcp
m=test_mcp.m


class MonitorOptions(unittest.IsolatedAsyncioTestCase):
    def state(self):
        state=m.SamState()
        state.input_options=m.InputOptions(dict(listenjoy=True,listenkeyboard=True,listenmouse=True,samdebug=False))
        state.config_listeners=dict(listenjoy=True,listenkeyboard=True,listenmouse=True)
        state.config_controllers={}
        state.console_lock=asyncio.Lock()
        return state

    async def test_toggle_disable_keeps_debug_observation_and_never_changes_ini(self):
        state=self.state()
        with patch.object(m,'rescan_devices',AsyncMock()) as scan, \
             patch.object(m,'InputDebugOutput') as output, \
             patch.object(m,'watch_remote_log',AsyncMock()),contextlib.redirect_stdout(io.StringIO()):
            output.return_value.is_alive.return_value=True
            await m.console_command(state,'d')
            self.assertTrue(state.samdebug)
            self.assertTrue(scan.call_args.kwargs['rebuild_joysticks'])
            await m.console_command(state,'j')
            self.assertFalse(state.listenjoy);self.assertTrue(state.samdebug)
            self.assertFalse(state.input_options.overrides['listenjoy'])
            self.assertTrue(state.input_options.base['listenjoy'])

    async def test_debug_output_recovers_after_terminal_failure(self):
        state=self.state();state.samdebug=True
        state.input_options.toggle('samdebug')
        old=Mock();old.is_alive.return_value=False;state.input_debug_output=old
        with patch.object(m,'InputDebugOutput') as output,patch.object(m,'rescan_devices',AsyncMock()) as scan, \
             patch.object(m,'watch_remote_log',AsyncMock()):
            await m.apply_input_options(state)
            self.assertIs(state.input_debug_output,output.return_value)
            self.assertTrue(scan.call_args.kwargs['rebuild_joysticks'])

    async def test_live_debug_enable_refreshes_metadata_without_reconnect(self):
        state=self.state()
        state.config_watcher=Mock()
        state.config_watcher.poll.return_value=dict(samdebug='Yes',samtimeout='60',listenjoy='Yes',listenkeyboard='Yes',listenmouse='Yes')
        with patch.object(m,'InputDebugOutput') as output,patch.object(m,'rescan_devices',AsyncMock()) as scan, \
             patch.object(m,'watch_remote_log',AsyncMock()):
            output.return_value.is_alive.return_value=True
            await m.reload_live_config(state,None)
            self.assertTrue(state.samdebug)
            self.assertTrue(scan.call_args.kwargs['rebuild_joysticks'])

    async def test_reset_rereads_ini_and_clears_temporary_overrides(self):
        state=self.state();state.input_options.toggle('listenkeyboard')
        with patch.object(m,'read_ini_values',return_value=dict(listenjoy='Yes',listenkeyboard='Yes',listenmouse='No',samdebug='No')), \
             patch.object(m,'rescan_devices',AsyncMock()) as scan, \
             patch.object(m,'watch_remote_log',AsyncMock()),contextlib.redirect_stdout(io.StringIO()):
            await m.console_command(state,'r')
            self.assertFalse(state.listenmouse);self.assertTrue(state.listenkeyboard)
            self.assertEqual(state.input_options.overrides,{})
            self.assertTrue(scan.call_args.kwargs['rebuild_joysticks'])

    async def test_debug_off_closes_unused_output(self):
        state=self.state();state.samdebug=True;state.input_debug_output=Mock()
        old=state.input_debug_output
        with patch.object(m,'rescan_devices',AsyncMock()),patch.object(m,'watch_remote_log',AsyncMock()):
            await m.apply_input_options(state)
            old.close.assert_called_once();self.assertIsNone(state.input_debug_output)

    async def test_only_individual_physical_mouse_nodes_are_admitted(self):
        state=self.state()
        inventory=dict(joysticks=[],keyboards=[],mice=[dict(mouse_path='/dev/input/mouse2')],has_mouse=True)
        with patch.object(m,'get_input_devices',return_value=inventory),patch.object(m,'watch_mouse_device',AsyncMock()) as watch, \
             patch.dict(m.tasks,{},clear=True),contextlib.redirect_stdout(io.StringIO()):
            await m._rescan_devices_impl(state,{},state.config_listeners,asyncio.get_running_loop())
            self.assertEqual(watch.call_args.args[0],'/dev/input/mouse2')


class PhysicalInventory(unittest.TestCase):
    def test_virtual_devices_are_excluded_bluetooth_uhid_and_physical_mouse_kept(self):
        records='''I: Bus=0003 Vendor=1234 Product=0001 Version=0001
N: Name="Physical Pad"
P: Phys=usb-1/input0
S: Sysfs=/devices/platform/usb/input1
H: Handlers=js0 event1

I: Bus=0003 Vendor=1234 Product=0002 Version=0001
N: Name="Virtual Pad"
P: Phys=virtual
S: Sysfs=/devices/virtual/input/input2
H: Handlers=js1 event2

I: Bus=0005 Vendor=1234 Product=0003 Version=0001
N: Name="Bluetooth Pad"
P: Phys=bluetooth-1/input0
S: Sysfs=/devices/virtual/misc/uhid/input3
H: Handlers=js2 event3

I: Bus=0003 Vendor=1234 Product=0004 Version=0001
N: Name="Mouse"
P: Phys=usb-2/input0
S: Sysfs=/devices/platform/usb/input4
H: Handlers=mouse0 event4

I: Bus=0003 Vendor=1234 Product=0005 Version=0001
N: Name="Virtual Mouse"
P: Phys=virtual
S: Sysfs=/devices/virtual/input/input5
H: Handlers=mouse1 event5

'''
        with patch('builtins.open',return_value=io.StringIO(records)):
            found=m.get_input_devices()
        self.assertEqual([d['js_path'] for d in found['joysticks']],['/dev/input/js0','/dev/input/js2'])
        self.assertEqual([d['mouse_path'] for d in found['mice']],['/dev/input/mouse0'])


if __name__=='__main__':unittest.main()
