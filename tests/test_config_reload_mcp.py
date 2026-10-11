"""Structural reload uses owned stop and the existing cancellable launcher."""
import asyncio
import sys
import threading
import importlib.util
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch
if sys.platform.startswith('linux'):
    import test_mcp
    m = test_mcp.m
else:
    m = None


@unittest.skipUnless(m is not None, 'native Linux MCP required')
class ReloadCoordinator(unittest.TestCase):
    def test_quoted_initial_timeout_preserves_disabled_listeners_and_m82(self):
        with tempfile.TemporaryDirectory() as directory:
            ini = Path(directory) / 'SAM.ini'
            ini.write_text('samtimeout="3600"\ngametimer="180"\nlistenjoy="No"\nlistenkeyboard="No"\nlistenmouse="No"\nm82="Yes"\nmenuonly="No"\nignore_when_skip="Yes"\nsamdebug="Yes"\n')
            settings = m.read_initial_settings(str(ini), directory)
        self.assertEqual(settings['timeout'], 3600)
        self.assertEqual(settings['listen_config'], dict(listenjoy=False, listenkeyboard=False, listenmouse=False))
        self.assertTrue(settings['m82'])
        self.assertFalse(settings['menu_only'])
        self.assertTrue(settings['ignore_when_skip'])
        self.assertTrue(settings['samdebug'])

    def test_initial_roulette_overlay_overrides_only_its_literal_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            ini = Path(directory) / 'SAM.ini'
            ini.write_text('samtimeout="3600"\nlistenjoy="No"\nm82="No"\n')
            (Path(directory) / 'gameroulette.ini').write_text('samtimeout="15"\nm82="Yes"\n')
            settings = m.read_initial_settings(str(ini), directory)
        self.assertEqual(settings['timeout'], 15)
        self.assertFalse(settings['listen_config']['listenjoy'])
        self.assertTrue(settings['m82'])

    def test_mcp_public_path_overrides_match_shell_entry(self):
        overrides = dict(SAM_ROOT='/tmp/fixture/package', SAM_ENTRY='/tmp/fixture/on.sh',
                         SAM_INI='/tmp/fixture/settings.ini', SAM_TMP_ROOT='/tmp/fixture/runtime',
                         SAM_STATE_FILE='/tmp/fixture/state')
        with patch.dict(os.environ, overrides):
            spec = importlib.util.spec_from_file_location('sam_mcp_path_fixture', test_mcp.SOURCE)
            imported = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(imported)
        self.assertEqual(imported.SAM_BASE_PATH, overrides['SAM_ROOT'])
        self.assertEqual(imported.SAM_ON_SCRIPT, overrides['SAM_ENTRY'])
        self.assertEqual(imported.INI_FILE, overrides['SAM_INI'])
        self.assertEqual(imported.SAM_OWNER_FILE, '/tmp/fixture/runtime/session-owner')
        self.assertEqual(imported.M82_PHASE_FILE, '/tmp/fixture/runtime/m82_phase')
        self.assertEqual(imported.SAM_STATE_FILE, overrides['SAM_STATE_FILE'])

    def receipt(self, path):
        if path.endswith('config-boundary'):
            return dict(pid='321', start='77', target='nes', revision='a' * 64)
        return dict(structural='1', revision='a' * 64)

    def state(self):
        state = m.SamState()
        state.config_watcher = SimpleNamespace(values={'m82': 'yes'})
        return state

    def test_mode_boundary_stops_expected_owner_then_tracks_new_launch(self):
        async def run():
            state = self.state()
            gateway = SimpleNamespace(execute=lambda action, *args, **kwargs: True)
            launch = AsyncMock()
            with patch.object(m, 'read_literal_file', side_effect=self.receipt), patch.object(m, 'command_gateway', return_value=gateway), patch.object(m, 'read_sam_owner', side_effect=[test_mcp.OWNER, None]), patch.object(m, 'launch_and_confirm', launch):
                self.assertTrue(await m.restart_config_at_boundary(state, test_mcp.OWNER))
            launch.assert_awaited_once_with(state, 'nes')
            self.assertFalse(state.is_stopping())
        asyncio.run(run())

    def test_human_stop_during_cleanup_suppresses_automatic_restart(self):
        async def run():
            state = self.state()
            loop = asyncio.get_running_loop()
            def execute(action, *args, **kwargs):
                if action == 'stop':
                    delivered = threading.Event()
                    def human_stop():
                        try:
                            m.lifecycle_coordinator().handle_action('exit', state, loop)
                        finally:
                            delivered.set()
                    loop.call_soon_threadsafe(human_stop)
                    if not delivered.wait(2):
                        raise AssertionError('Human Stop did not reach the active coordinator')
                return True
            gateway = SimpleNamespace(execute=execute)
            launch = AsyncMock()
            with patch.object(m, 'read_literal_file', side_effect=self.receipt), patch.object(m, 'command_gateway', return_value=gateway), patch.object(m, 'read_sam_owner', side_effect=[test_mcp.OWNER, None]), patch.object(m, 'launch_and_confirm', launch):
                self.assertTrue(await m.restart_config_at_boundary(state, test_mcp.OWNER))
            launch.assert_not_awaited()
            self.assertTrue(state.config_restart_cancelled)
        asyncio.run(run())

    def test_rejected_mode_keeps_current_owner_without_stop(self):
        async def run():
            state = self.state()
            actions = []
            gateway = SimpleNamespace(execute=lambda action, *args, **kwargs: actions.append(action) or False)
            launch = AsyncMock()
            with patch.object(m, 'read_literal_file', side_effect=self.receipt), patch.object(m, 'command_gateway', return_value=gateway), patch.object(m, 'launch_and_confirm', launch):
                self.assertTrue(await m.restart_config_at_boundary(state, test_mcp.OWNER))
                self.assertTrue(await m.restart_config_at_boundary(state, test_mcp.OWNER))
            self.assertEqual(actions, ['validate_start'])
            launch.assert_not_awaited()
        asyncio.run(run())

    def test_open_menu_defers_mode_boundary_before_reading_or_stopping(self):
        async def run():
            state = self.state()
            with patch.object(m, 'menu_session_active', return_value=True), \
                    patch.object(m, 'read_literal_file') as read, \
                    patch.object(m, 'command_gateway') as gateway, \
                    patch.object(m, 'launch_and_confirm', AsyncMock()) as launch:
                self.assertFalse(await m.restart_config_at_boundary(state, test_mcp.OWNER))
                read.assert_not_called()
                gateway.assert_not_called()
                launch.assert_not_awaited()
        asyncio.run(run())


if __name__ == '__main__':
    unittest.main()
