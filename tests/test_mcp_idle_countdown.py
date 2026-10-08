"""Countdown display and launch eligibility for the installed MCP variant."""
import asyncio
import contextlib
import importlib.util
import io
from pathlib import Path
from paths import PACKAGE
import unittest
from unittest.mock import AsyncMock, Mock, patch

PATH=PACKAGE / '.MiSTer_SAM/MiSTer_SAM_MCP.py'
spec=importlib.util.spec_from_file_location('installed_mcp_countdown',PATH)
mcp=importlib.util.module_from_spec(spec);spec.loader.exec_module(mcp)

class CountdownTests(unittest.TestCase):
    def test_updates_in_place_rounds_up_and_resets_after_activity(self):
        output=io.StringIO();display=mcp.IdleCountdownDisplay()
        with contextlib.redirect_stdout(output):
            display.update(10.8);display.update(10.2);display.update(9.9)
            display.update(60);display.update();display.update()
        text=output.getvalue()
        self.assertEqual(text.count('Starting SAM in'),3)
        self.assertIn('11s...',text);self.assertIn('10s...',text);self.assertIn('60s...',text)
        self.assertNotIn('\n',text)
        self.assertIsNone(display.previous)

    def exercise_checker(self, menu=True, menu_only=True, idle=5, owner=None, stopping=False):
        async def run():
            state=Mock(menu_only=menu_only,idle_timeout=60)
            state.is_stopping.return_value=stopping
            state.get_idle_time.return_value=idle
            display=Mock();launch=AsyncMock();cancel=AsyncMock()
            async def to_thread(fn,*args):
                if fn is mcp.read_sam_owner:return owner
                if fn is mcp.is_in_menu:return menu
                raise AssertionError('unexpected thread job')
            async def sleep(seconds):
                raise asyncio.CancelledError()
            with patch.object(mcp,'IdleCountdownDisplay',return_value=display), \
                    patch.object(mcp,'menu_requires_stop',return_value=False), \
                    patch.object(mcp,'launch_and_confirm',launch), \
                    patch.object(mcp,'cancel_launcher',cancel), \
                    patch.object(mcp.asyncio,'to_thread',side_effect=to_thread), \
                    patch.object(mcp.asyncio,'sleep',side_effect=sleep):
                with self.assertRaises(asyncio.CancelledError):
                    await mcp.idle_and_status_checker(state)
            return display,launch
        return asyncio.run(run())

    def test_idle_in_menu_displays_remaining_time(self):
        display,launch=self.exercise_checker()
        display.update.assert_any_call(55)
        launch.assert_not_awaited()

    def test_menu_only_blocks_countdown_in_game_or_unknown_core(self):
        for menu in (False,None):
            display,launch=self.exercise_checker(menu=menu)
            self.assertTrue(all(not call.args for call in display.update.call_args_list))
            launch.assert_not_awaited()

    def test_menu_only_disabled_can_count_down_in_game(self):
        display,launch=self.exercise_checker(menu=False,menu_only=False)
        display.update.assert_any_call(55)
        launch.assert_not_awaited()

    def test_running_or_stopping_sam_has_no_countdown(self):
        for args in ({'owner':{'pid':'100'}},{'stopping':True}):
            display,launch=self.exercise_checker(**args)
            self.assertTrue(all(not call.args for call in display.update.call_args_list))
            launch.assert_not_awaited()

    def test_expired_timer_clears_display_before_launch(self):
        display,launch=self.exercise_checker(idle=60.1)
        self.assertTrue(all(not call.args for call in display.update.call_args_list))
        launch.assert_awaited_once()

if __name__=='__main__':unittest.main()
