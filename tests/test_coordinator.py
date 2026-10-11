"""Portable coordinator tests with injected platform operations; no hardware IO."""
import asyncio
from dataclasses import FrozenInstanceError
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import AsyncMock, Mock
from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / ".MiSTer_SAM"))
from sam.coordinator import CoordinatorDependencies, LifecycleCoordinator
from sam.session import SessionSnapshot, read_session, read_literal_file


class SessionTests(unittest.TestCase):
    def test_snapshot_is_immutable_and_detached(self):
        record = dict(pid="321", start="77", phase="playing", launch="1")
        snapshot = SessionSnapshot.from_record(record)
        record["start"] = "78"
        self.assertEqual(snapshot.key, ("321", "77"))
        with self.assertRaises(FrozenInstanceError):
            snapshot.start = "78"
        self.assertEqual(snapshot["phase"], "playing")

    def test_verification_rejects_reuse_and_zombie(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "321").mkdir()
            owner = root / "owner"
            owner.write_text("pid=321\nstart=77\nphase=playing\n")
            stat = root / "321" / "stat"
            fields = ["S"] + ["0"] * 18 + ["77"]
            stat.write_text("321 (worker (with) spaces) " + " ".join(fields))
            self.assertEqual(read_session(owner, tmp).key, ("321", "77"))
            fields[19] = "78"
            stat.write_text("321 (worker) " + " ".join(fields))
            self.assertIsNone(read_session(owner, tmp))
            fields[19], fields[0] = "77", "Z"
            stat.write_text("321 (worker) " + " ".join(fields))
            self.assertIsNone(read_session(owner, tmp))

    def test_bad_identity_and_oversized_records_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            owner = root / "owner"
            for record in ("pid=321\npid=322\nstart=77\n", "pid=321\nstart=٧٧\n", "pid=" + "3" * 100 + "\nstart=77\n", "pid=321\nstart=77\n" + "x" * 16384):
                owner.write_text(record, encoding="utf-8")
                self.assertIsNone(read_session(owner, tmp))
            self.assertEqual(read_literal_file(root), {})

    @unittest.skipUnless(hasattr(__import__("os"), "mkfifo"), "Linux FIFO behavior")
    def test_fifo_owner_returns_without_blocking(self):
        import os
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fifo"
            os.mkfifo(path)
            self.assertEqual(read_literal_file(path), {})


class State:
    def __init__(self):
        self._lock = threading.Lock()
    listenjoy = True
    m82 = False
    ignore_when_skip = False
    stopping = False
    starting = False
    busy_next_owner = None
    pending_menu_stop = False
    def update_activity(self, **kwargs): pass
    def is_sam_starting(self): return self.starting
    def is_stopping(self): return self.stopping
    def set_stopping(self, value): self.stopping = value
    def set_sam_running(self, value): self.running = value
    def set_pending_action(self, value): self.pending = value
    def set_busy_next_owner(self, owner):
        self.busy_next_owner, self.pending_menu_stop = owner, False
    def queue_busy_menu_stop(self):
        if self.busy_next_owner is None: return False
        self.pending_menu_stop = True
        return True
    def consume_busy_menu_stop(self):
        owner = self.busy_next_owner if self.pending_menu_stop else None
        self.busy_next_owner, self.pending_menu_stop = None, False
        return owner


class CoordinatorTests(unittest.IsolatedAsyncioTestCase):
    def dependencies(self, **overrides):
        callbacks = {name: Mock() for name in CoordinatorDependencies.__annotations__}
        callbacks.update(read_sam_owner=Mock(return_value=dict(pid="321", start="77", phase="playing", launch="1")), is_in_menu=Mock(return_value=False), session_is_m82=Mock(return_value=False), stop_sam=AsyncMock(), is_sam_running=Mock(return_value=False), menu_active=Mock(return_value=False), empty_selection_blocked=Mock(return_value=False),monitor_active=Mock(return_value=False))
        callbacks.update(overrides)
        return CoordinatorDependencies(**callbacks)

    async def drain(self, state):
        for _ in range(100):
            if not state.stopping: return
            await asyncio.sleep(.002)
        self.fail("Action did not finish")

    async def test_physical_monitor_keys_update_activity_without_stopping_game(self):
        state=State();state.update_activity=Mock()
        deps=self.dependencies(monitor_active=Mock(return_value=True))
        LifecycleCoordinator(deps).handle_action('default',state,asyncio.get_running_loop(),source='keyboard')
        state.update_activity.assert_called_once()
        deps.stop_sam.assert_not_awaited()
        self.assertFalse(state.stopping)

    async def test_monitor_suppression_diagnostic_explains_gate(self):
        diagnostic = Mock()
        dependencies = self.dependencies(monitor_active=Mock(return_value=True), diagnostic=diagnostic)
        state = State()
        LifecycleCoordinator(dependencies).handle_action('default', state, asyncio.get_running_loop())
        diagnostic.assert_called_once_with('mcp', 'input_suppressed', owner='', phase='', source='keyboard', action='default', reason='monitor_active')
        dependencies.read_sam_owner.assert_not_called()
        dependencies.stop_sam.assert_not_awaited()

    async def test_diagnostic_failure_cannot_prevent_dispatch(self):
        diagnostic = Mock(side_effect=RuntimeError('logging failed'))
        dependencies = self.dependencies(diagnostic=diagnostic)
        state = State()
        LifecycleCoordinator(dependencies).handle_action('default', state, asyncio.get_running_loop(), source='remote_keyboard')
        await self.drain(state)
        dependencies.stop_sam.assert_awaited_once()
        self.assertFalse(state.stopping)

    async def test_exit_events_use_captured_owner_and_result(self):
        diagnostic = Mock()
        dependencies = self.dependencies(diagnostic=diagnostic)
        state = State()
        LifecycleCoordinator(dependencies).handle_action('default', state, asyncio.get_running_loop(), source='remote_keyboard')
        await self.drain(state)
        records = [(call.args[1], call.kwargs) for call in diagnostic.call_args_list]
        request = next(fields for event, fields in records if event == 'exit_requested')
        result = next(fields for event, fields in records if event == 'exit_result')
        self.assertEqual(request['owner'], '321:77')
        self.assertEqual(result['owner'], request['owner'])
        self.assertEqual(result['phase'], request['phase'])

    async def test_disabled_keyboard_mouse_and_joystick_do_not_dispatch(self):
        for source in ('keyboard','remote_keyboard','mouse','joystick'):
            state=State();state.listenkeyboard=False;state.listenmouse=False;state.listenjoy=False
            state.update_activity=Mock()
            deps=self.dependencies()
            LifecycleCoordinator(deps).handle_action('default',state,asyncio.get_running_loop(),source=source)
            state.update_activity.assert_not_called();deps.stop_sam.assert_not_awaited()

    async def test_fast_empty_or_menu_skipped_launcher_never_times_out_or_dispatches_menu(self):
        for empty,menu in ((True,False),(False,True)):
            with self.subTest(empty=empty,menu=menu):
                state=Mock()
                state.consume_pending_action.return_value=None
                launcher=Mock()
                launcher.poll.return_value=0
                state.launcher=launcher
                deps=self.dependencies(read_sam_owner=Mock(return_value=None),
                                       empty_selection_blocked=Mock(return_value=empty),
                                       menu_active=Mock(return_value=menu),cancel_launcher=AsyncMock())
                await LifecycleCoordinator(deps).launch_and_confirm(state)
                self.assertIsNone(state.launcher)
                launcher.wait.assert_called_once()
                deps.cancel_launcher.assert_not_awaited()
                deps.kill_sam_processes.assert_not_called()
                state.set_sam_running.assert_called_once_with(False)

    async def test_replaced_owner_does_not_receive_stop(self):
        reader = Mock(side_effect=[dict(pid="321", start="77"), dict(pid="321", start="78")])
        dependencies = self.dependencies(read_sam_owner=reader)
        state = State()
        LifecycleCoordinator(dependencies).handle_action("start", state, asyncio.get_running_loop())
        await self.drain(state)
        dependencies.stop_sam.assert_not_called()

    async def test_menu_input_updates_activity_without_dispatch_or_restart_cancellation(self):
        for action in ('default', 'exit', 'start', 'next', 'zaparoo'):
            dependencies = self.dependencies(menu_active=Mock(return_value=True))
            state = State()
            state._lock = threading.Lock()
            state.config_restart_pending = True
            state.config_restart_cancelled = False
            state.update_activity = Mock()
            LifecycleCoordinator(dependencies).handle_action(action, state, asyncio.get_running_loop())
            state.update_activity.assert_called_once_with()
            dependencies.menu_active.assert_called_once_with()
            dependencies.read_sam_owner.assert_not_called()
            dependencies.skip_game.assert_not_called()
            dependencies.stop_sam.assert_not_called()
            self.assertFalse(state.stopping)
            self.assertFalse(state.config_restart_cancelled)

    async def test_menu_guard_is_not_queried_for_absent_or_disabled_joystick_input(self):
        dependencies = self.dependencies(menu_active=Mock(return_value=True))
        state = State()
        state.listenjoy = False
        coordinator = LifecycleCoordinator(dependencies)
        coordinator.handle_action(None, state, asyncio.get_running_loop())
        coordinator.handle_action('next', state, asyncio.get_running_loop(), 'joystick')
        dependencies.menu_active.assert_not_called()

    async def test_loading_m82_input_cannot_stop_the_session(self):
        dependencies = self.dependencies(read_sam_owner=Mock(return_value=dict(pid="321", start="77", phase="loading")), session_is_m82=Mock(return_value=True))
        state = State()
        LifecycleCoordinator(dependencies).handle_action("default", state, asyncio.get_running_loop())
        await self.drain(state)
        dependencies.play_m82_game.assert_not_called()
        dependencies.stop_sam.assert_not_awaited()
        dependencies.skip_game.assert_not_called()

    async def test_startup_input_buffers_before_owner_or_commands(self):
        dependencies = self.dependencies()
        state = State()
        state.starting = True
        LifecycleCoordinator(dependencies).handle_action("default", state, asyncio.get_running_loop())
        self.assertEqual(state.pending, "default")
        dependencies.read_sam_owner.assert_not_called()
        dependencies.stop_sam.assert_not_called()

    async def test_next_keeps_captured_owner_for_gateway_validation(self):
        record = dict(pid="321", start="77", phase="loading", launch="1")
        dependencies = self.dependencies(read_sam_owner=Mock(return_value=record))
        state = State()
        LifecycleCoordinator(dependencies).handle_action("next", state, asyncio.get_running_loop())
        await self.drain(state)
        snapshot = dependencies.skip_game.call_args.args[0]
        self.assertIsInstance(snapshot, SessionSnapshot)
        self.assertEqual(snapshot.key, ("321", "77"))
        record["start"] = "78"
        self.assertEqual(snapshot.key, ("321", "77"))

    async def test_zaparoo_replacement_prevents_unmute(self):
        dependencies = self.dependencies(read_sam_owner=Mock(side_effect=[dict(pid="321", start="77", phase="playing"), dict(pid="321", start="78", phase="playing")]))
        state = State()
        LifecycleCoordinator(dependencies).handle_action("zaparoo", state, asyncio.get_running_loop())
        await self.drain(state)
        dependencies.unmute_sam.assert_not_called()
        dependencies.stop_sam.assert_not_called()

    async def test_start_during_preparation_does_not_keep_previous_game(self):
        dependencies = self.dependencies(read_sam_owner=Mock(return_value=dict(pid="321", start="77", phase="preparing")))
        state = State()
        LifecycleCoordinator(dependencies).handle_action("start", state, asyncio.get_running_loop())
        await self.drain(state)
        self.assertFalse(dependencies.stop_sam.call_args.kwargs["play_current"])

    async def test_zaparoo_preparation_keeps_menu_cleanup_muted(self):
        dependencies = self.dependencies(read_sam_owner=Mock(return_value=dict(pid="321", start="77", phase="preparing")))
        state = State()
        LifecycleCoordinator(dependencies).handle_action("zaparoo", state, asyncio.get_running_loop())
        await self.drain(state)
        dependencies.unmute_sam.assert_not_called()
        self.assertFalse(dependencies.stop_sam.call_args.kwargs["play_current"])


class PendingMenuStopTests(unittest.IsolatedAsyncioTestCase):
    dependencies = CoordinatorTests.dependencies
    drain = CoordinatorTests.drain
    async def run_busy_next(self, actions, *, ignore=False, m82=False, replaced=False, failure=None, phase="playing"):
        started, release = threading.Event(), threading.Event()
        state = State()
        state.ignore_when_skip = ignore
        owner = dict(pid="321", start="77", phase=phase, launch="1")
        read_owner = Mock(return_value=owner)
        def gateway(snapshot):
            started.set()
            if not release.wait(2): raise AssertionError("fixture gateway was not released")
            if isinstance(failure, Exception): raise failure
            return failure if failure is not None else True
        dependencies = self.dependencies(read_sam_owner=read_owner,
                                         session_is_m82=Mock(return_value=m82),
                                         skip_game=Mock(side_effect=gateway),
                                         ignore_game=Mock(side_effect=gateway))
        loop = asyncio.get_running_loop()
        LifecycleCoordinator(dependencies).handle_action("next", state, loop)
        try:
            self.assertTrue(await asyncio.to_thread(started.wait, 1))
            # Production creates a fresh coordinator for each reader callback.
            # Deliver callbacks through the actual event-loop thread-safe entry.
            for action in actions:
                loop.call_soon_threadsafe(LifecycleCoordinator(dependencies).handle_action,
                                          action, state, loop)
            await asyncio.sleep(.01)
            if replaced:
                read_owner.return_value = dict(owner, start="78")
        finally:
            release.set()
        await self.drain(state)
        self.assertIsNone(state.busy_next_owner)
        self.assertFalse(state.pending_menu_stop)
        return dependencies

    async def test_stop_during_next_coalesces_across_fresh_coordinators(self):
        dependencies = await self.run_busy_next(["default", "exit", "default", "next", "start", "zaparoo"])
        dependencies.skip_game.assert_called_once()
        dependencies.stop_sam.assert_awaited_once()
        self.assertFalse(dependencies.stop_sam.call_args.kwargs["play_current"])
        self.assertEqual(dependencies.stop_sam.call_args.kwargs["owner"].key, ("321", "77"))
        dependencies.unmute_sam.assert_not_called()

    async def test_stop_during_ignore_is_preserved(self):
        dependencies = await self.run_busy_next(["exit"], ignore=True)
        dependencies.ignore_game.assert_called_once()
        dependencies.skip_game.assert_not_called()
        dependencies.stop_sam.assert_awaited_once()

    async def test_pending_stop_rejects_replaced_or_reused_owner(self):
        dependencies = await self.run_busy_next(["default"], replaced=True)
        dependencies.stop_sam.assert_not_called()

    async def test_m82_next_is_gameplay_not_a_skip_or_stop(self):
        for phase in ("playing", "loading", "preparing"):
            state = State()
            dependencies = self.dependencies(read_sam_owner=Mock(return_value=dict(pid='321', start='77', phase=phase, launch='1')),
                session_is_m82=Mock(return_value=True), read_m82_phase=Mock(return_value='game'), play_m82_game=Mock(return_value=True))
            LifecycleCoordinator(dependencies).handle_action('next', state, asyncio.get_running_loop(), 'joystick')
            await self.drain(state)
            dependencies.skip_game.assert_not_called()
            dependencies.stop_sam.assert_not_called()
            self.assertEqual(dependencies.play_m82_game.call_count, int(phase == 'playing'))

    async def test_failed_next_does_not_lose_already_requested_stop(self):
        for failure in (False, RuntimeError("simulated delivery failure")):
            dependencies = await self.run_busy_next(["default"], failure=failure)
            dependencies.skip_game.assert_called_once()
            dependencies.stop_sam.assert_awaited_once()

    async def test_busy_next_does_not_repeat_next_or_keep_game_requests(self):
        dependencies = await self.run_busy_next(["next", "next", "start", "zaparoo"])
        dependencies.skip_game.assert_called_once()
        dependencies.stop_sam.assert_not_called()
        dependencies.unmute_sam.assert_not_called()
