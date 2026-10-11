"""Menu/audio command ordering; all hardware and waits are mocked."""
import asyncio
import subprocess
import threading
import time
import types
import unittest
from unittest.mock import AsyncMock, Mock, patch
from paths import PACKAGE

# Import the actual compatibility entrypoint and extracted coordinator.
# Windows substitutes only the unavailable ioctl module; lifecycle never calls it.
import importlib.util
import os
import sys
source = PACKAGE / '.MiSTer_SAM/MiSTer_SAM_MCP.py'
spec = importlib.util.spec_from_file_location('menu_audio_fixture', source)
m = importlib.util.module_from_spec(spec)
with patch.dict(sys.modules, {'fcntl': types.ModuleType('fcntl')} if os.name == 'nt' else {}):
    spec.loader.exec_module(m)
m.SAM_ON_SCRIPT = '/fixture/SAM.sh'
OWNER = dict(pid='321', start='77', phase='playing', launch='1')


class MenuAudio(unittest.IsolatedAsyncioTestCase):
    async def test_menu_stop_delegates_one_owner_bound_command(self):
        gateway = Mock()
        gateway.execute.return_value = True
        with patch.object(m, 'command_gateway', return_value=gateway), patch.object(m, 'is_in_menu') as menu:
            self.assertTrue(await m.exit_to_menu_with_retry(m.SamState(), owner=OWNER))
        gateway.execute.assert_called_once_with('stop', owner=OWNER)
        menu.assert_not_called()

    async def test_failed_menu_stop_reports_failure_without_resource_commands(self):
        gateway = Mock()
        gateway.execute.return_value = False
        with patch.object(m, 'command_gateway', return_value=gateway):
            self.assertFalse(await m.stop_sam(m.SamState(), owner=OWNER))
        gateway.execute.assert_called_once_with('stop', owner=OWNER)

    async def test_keep_game_delegates_targeted_cleanup(self):
        gateway = Mock()
        gateway.execute.return_value = True
        with patch.object(m, 'command_gateway', return_value=gateway):
            self.assertTrue(await m.stop_sam(m.SamState(), play_current=True, owner=OWNER))
        gateway.execute.assert_called_once_with('exit_to_game', owner=OWNER)

    async def test_gateway_error_reports_failure(self):
        gateway = Mock()
        gateway.execute.side_effect = OSError('backend unavailable')
        with patch.object(m, 'command_gateway', return_value=gateway):
            self.assertFalse(await m.stop_sam(m.SamState(), owner=OWNER))

    def test_start_retains_shared_backend_launcher(self):
        gateway = Mock()
        state = m.SamState()
        with patch.object(m, 'command_gateway', return_value=gateway):
            m.start_sam(state)
        gateway.launch_start.assert_called_once_with(if_idle=True)
        self.assertIs(state.launcher, gateway.launch_start.return_value)

    def test_owner_cleanup_uses_shared_gateway(self):
        gateway = Mock()
        gateway.execute.return_value = True
        with patch.object(m, 'command_gateway', return_value=gateway):
            self.assertTrue(m.kill_sam_processes(OWNER))
        gateway.execute.assert_called_once_with('stop_owner', owner=OWNER)

    async def startup_action(self, action, phase='playing', during_read=False, replaced=False):
        state = m.SamState()
        order = []
        class Process:
            def poll(self): return 0
            def wait(self): return 0
        def start(s):
            s.launcher = Process()
            if not during_read: s.set_pending_action(action)
        async def cancel(s):
            order.append('cancel'); s.launcher = None
        reads = 0
        def owner():
            nonlocal reads
            reads += 1
            if during_read and reads == 1: state.set_pending_action(action)
            return dict(OWNER, phase=phase, pid='322' if replaced and reads > 1 else '321')
        async def stop(*args, **kwargs): order.append('stop')
        async def no_wait(_): pass
        with patch.object(m, 'start_sam', side_effect=start), \
             patch.object(m, 'cancel_launcher', side_effect=cancel), \
             patch.object(m, 'read_sam_owner', side_effect=owner), \
             patch.object(m, 'stop_sam', side_effect=stop) as stopped, \
             patch.object(m, 'kill_sam_processes') as kill, \
             patch.object(m, 'skip_game') as skip, \
             patch.object(m.asyncio, 'sleep', side_effect=no_wait):
            await m.launch_and_confirm(state)
        self.assertFalse(state.is_sam_starting())
        return state, order, stopped, kill, skip

    async def test_startup_ordinary_input_uses_menu_stop_after_launcher_barrier(self):
        state, order, stopped, kill, _ = await self.startup_action('default')
        self.assertEqual(order, ['cancel', 'stop'])
        self.assertFalse(stopped.call_args.kwargs['play_current'])
        kill.assert_not_called()

    async def test_startup_start_only_keeps_an_actual_running_game(self):
        for phase in ('preparing', 'loading', 'playing'):
            _, order, stopped, _, _ = await self.startup_action('start', phase=phase)
            self.assertEqual(order, ['cancel', 'stop'])
            self.assertEqual(stopped.call_args.kwargs['play_current'], phase == 'playing')

    async def test_input_during_owner_read_never_stops_a_replacement(self):
        _, order, stopped, kill, _ = await self.startup_action('default', during_read=True, replaced=True)
        self.assertEqual(order, ['cancel'])
        stopped.assert_not_called(); kill.assert_not_called()

    async def test_startup_next_still_coalesces(self):
        state, order, stopped, kill, skip = await self.startup_action('next')
        self.assertEqual(order, [])
        self.assertTrue(state.is_sam_running())
        skip.assert_called_once(); stopped.assert_not_called(); kill.assert_not_called()
