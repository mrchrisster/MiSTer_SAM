"""M82 owns physical gameplay while MCP retains menu/idle supervision."""
import asyncio
from pathlib import Path
import sys
import time
import tempfile
import unittest
from unittest.mock import Mock, patch
from paths import PACKAGE
import test_coordinator as fixture
State = fixture.State
import test_mcp as mcp_fixture
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam.coordinator import LifecycleCoordinator


class M82Input(unittest.IsolatedAsyncioTestCase):
    dependencies = fixture.CoordinatorTests.dependencies
    drain = fixture.CoordinatorTests.drain

    async def test_all_physical_game_buttons_activate_once_then_stay_in_game(self):
        state = State(); state.m82 = True
        deps = self.dependencies(session_is_m82=Mock(return_value=True), read_m82_phase=Mock(return_value='game'),
                                 play_m82_game=Mock(return_value=True))
        def accept(owner):
            deps.read_m82_phase.return_value = 'play'
            return True
        deps.play_m82_game.side_effect = accept
        for source in ('joystick', 'keyboard', 'mouse'):
            for action in ('default', 'next', 'start', 'exit'):
                LifecycleCoordinator(deps).handle_action(action, state, asyncio.get_running_loop(), source)
                await self.drain(state)
        deps.play_m82_game.assert_called_once()
        deps.skip_game.assert_not_called(); deps.stop_sam.assert_not_called()
        deps.read_m82_phase.return_value = 'play'
        state.m82_play_pending = None
        LifecycleCoordinator(deps).handle_action('next', state, asyncio.get_running_loop(), 'joystick')
        await self.drain(state)
        deps.play_m82_game.assert_called_once()

    async def test_new_launch_accepts_play_and_failed_delivery_can_retry(self):
        state = State()
        owner = dict(pid='321', start='77', phase='playing', launch='1')
        deps = self.dependencies(read_sam_owner=Mock(return_value=owner), session_is_m82=Mock(return_value=True),
                                 read_m82_phase=Mock(return_value='game'), play_m82_game=Mock(side_effect=[False, True, True]))
        for index, launch in enumerate(('1', '1', '2')):
            if index == 1:
                state.m82_play_pending = (state.m82_play_pending[0], time.monotonic() - 2)
            owner['launch'] = launch
            LifecycleCoordinator(deps).handle_action('default', state, asyncio.get_running_loop())
            await self.drain(state)
        self.assertEqual(deps.play_m82_game.call_count, 3)
        deps.stop_sam.assert_not_called()

    async def test_startup_buttons_do_not_cancel_m82_launcher(self):
        state = State(); state.m82 = True; state.starting = True
        deps = self.dependencies()
        for action in ('default', 'next', 'start', 'exit'):
            LifecycleCoordinator(deps).handle_action(action, state, asyncio.get_running_loop(), 'joystick')
        self.assertFalse(hasattr(state, 'pending'))
        deps.read_sam_owner.assert_not_called()

    def test_menu_stops_m82_after_a_core_was_seen_and_requires_menu_for_autostart(self):
        from types import SimpleNamespace
        state = SimpleNamespace(m82=True, menu_only=False, menu_owner=None, menu_armed=False, menu_since=None)
        deps = self.dependencies(session_is_m82=Mock(return_value=True))
        coordinator = LifecycleCoordinator(deps)
        owner = dict(pid='321', start='77', phase='loading', launch='1')
        self.assertFalse(coordinator.menu_requires_stop(state, owner, True))
        owner['phase'] = 'playing'
        self.assertFalse(coordinator.menu_requires_stop(state, owner, False))
        owner['launch'] = '2'; owner['phase'] = 'loading'
        self.assertFalse(coordinator.menu_requires_stop(state, owner, True))
        owner['phase'] = 'playing'
        self.assertTrue(coordinator.menu_requires_stop(state, owner, True))
        self.assertFalse(coordinator.can_autostart(state, False))
        self.assertFalse(coordinator.can_autostart(state, None))
        self.assertTrue(coordinator.can_autostart(state, True))
        owner['start'] = '78'
        self.assertFalse(coordinator.menu_requires_stop(state, owner, True))

    def test_phase_ack_is_bound_to_owner_and_launch(self):
        m = mcp_fixture.m
        owner = dict(pid='321', start='77', launch='4', phase='playing')
        with tempfile.TemporaryDirectory() as directory, patch.object(m, 'SAM_RUNTIME_ROOT', directory):
            path = Path(directory) / 'session-321:77/m82-phase'
            path.parent.mkdir()
            path.write_text('launch=4\nphase=play\n')
            self.assertEqual(m.read_m82_phase(owner), 'play')
            self.assertEqual(m.read_m82_phase(dict(owner, launch='5')), 'unknown')
            path.write_text('launch=4\nphase=$(bad)\n')
            self.assertEqual(m.read_m82_phase(owner), 'unknown')


if __name__ == '__main__': unittest.main()
