# SPDX-License-Identifier: GPL-3.0-or-later
"""Input lifecycle orchestration, independent of reader and platform backends."""
import asyncio
import time
from dataclasses import dataclass
from typing import Callable
from .session import SessionSnapshot, owner_key


@dataclass(frozen=True)
class CoordinatorDependencies:
    read_sam_owner: Callable
    is_in_menu: Callable
    session_is_m82: Callable
    skip_game: Callable
    ignore_game: Callable
    read_m82_phase: Callable
    play_m82_game: Callable
    unmute_sam: Callable
    stop_sam: Callable
    is_sam_running: Callable
    start_sam: Callable
    cancel_launcher: Callable
    kill_sam_processes: Callable
    menu_active: Callable = lambda: False
    empty_selection_blocked: Callable = lambda: False
    monitor_active: Callable = lambda: False
    diagnostic: Callable = None


class LifecycleCoordinator:
    def __init__(self, dependencies: CoordinatorDependencies):
        self.dependencies = dependencies

    def _diagnostic(self, event, owner=None, **fields):
        callback = self.dependencies.diagnostic
        if callback is None:
            return
        try:
            identity = owner_key(owner)
            callback("mcp", event, owner=":".join(identity) if identity else "",
                     phase=owner.get("phase", "") if owner else "", **fields)
        except Exception:
            pass

    def read_owner(self):
        record = self.dependencies.read_sam_owner()
        # Capture identity and phase once; never retain a mutable reader record.
        return SessionSnapshot.from_record(record) if record else None

    def handle_action(self, action, state, loop, source="keyboard"):
        if not action or (source == "joystick" and not state.listenjoy):
            return
        if source in {'keyboard','remote_keyboard'} and not getattr(state,'listenkeyboard',True):
            return
        if source=='mouse' and not getattr(state,'listenmouse',True):
            return
        state.update_activity()
        if source=='keyboard' and self.dependencies.monitor_active():
            self._diagnostic("input_suppressed", source=source, action=action, reason="monitor_active")
            return  # Physical console keys belong to the attached MCP monitor.
        # Query the dialog owner's kernel lock only for a real input event.
        # Reader snapshots retain their existing polling and activity behavior.
        if self.dependencies.menu_active():
            self._diagnostic("input_suppressed", source=source, action=action, reason="menu_active")
            return
        if action != 'next':
            with state._lock:
                if getattr(state, 'config_restart_pending', False):
                    state.config_restart_cancelled = True
        # Input during launch must reach cancellation even before an owner exists.
        if state.is_sam_starting():
            self._diagnostic("action_received", source=source, action=action, routing="startup_pending")
            state.set_pending_action(action)
            return
        if state.is_stopping():
            self._diagnostic("action_received", source=source, action=action, routing="busy")
            # Preserve a single Menu Stop only while an ordinary verified
            # Next/Ignore is awaiting delivery. Start/play, more Next requests,
            # M82 and ownership discovery retain their existing routing.
            if action in ("default", "exit"):
                state.queue_busy_menu_stop()
            return
        state.set_stopping(True)

        async def do_actions():
            owner = None
            try:
                owner = await asyncio.to_thread(self.read_owner)
                self._diagnostic("action_received", owner, source=source, action=action, routing="dispatch")
                if not owner:
                    self._diagnostic("owner_missing", source=source, action=action)
                    state.set_sam_running(False)
                    return
                state.set_sam_running(True)
                in_menu = await asyncio.to_thread(self.dependencies.is_in_menu, state)
                m82_session = self.dependencies.session_is_m82(owner, state.m82)
                if m82_session and not in_menu and owner.get("phase") not in {"preparing", "loading", "stopping"}:
                    if action == "next":
                        self._diagnostic("command_requested", owner, command="next")
                        result = await asyncio.to_thread(self.dependencies.skip_game, owner)
                        self._diagnostic("command_result", owner, command="next", result=result)
                    elif await asyncio.to_thread(self.dependencies.read_m82_phase) != "bios":
                        self._diagnostic("command_requested", owner, command="play")
                        result = await asyncio.to_thread(self.dependencies.play_m82_game, owner)
                        self._diagnostic("command_result", owner, command="play", result=result)
                elif action == "next":
                    if not m82_session:
                        state.set_busy_next_owner(owner_key(owner))
                    if state.ignore_when_skip and owner.get("phase") == "playing":
                        self._diagnostic("command_requested", owner, command="ignore")
                        result = await asyncio.to_thread(self.dependencies.ignore_game, owner)
                        self._diagnostic("command_result", owner, command="ignore", result=result)
                    else:
                        self._diagnostic("command_requested", owner, command="next")
                        result = await asyncio.to_thread(self.dependencies.skip_game, owner)
                        self._diagnostic("command_result", owner, command="next", result=result)
                else:
                    # Stop the owner before loading Menu. Never let Menu override a
                    # Next request or infer liveness from a stale core name.
                    keep = action in ("start", "zaparoo") and in_menu is False and owner.get("phase") in {"playing", "video"}
                    # A replaced session must not inherit an old input request,
                    # including its resource changes before cleanup.
                    if owner_key(await asyncio.to_thread(self.read_owner)) != owner_key(owner):
                        self._diagnostic("exit_rejected", owner, reason="owner_changed", action=action)
                        return
                    if action == "zaparoo" and keep:
                        await asyncio.to_thread(self.dependencies.unmute_sam, owner)
                    self._diagnostic("exit_requested", owner, action=action, play_current=keep)
                    result = await self.dependencies.stop_sam(state, play_current=keep, owner=owner)
                    self._diagnostic("exit_result", owner, action=action, play_current=keep, result=result)
                    state.set_sam_running(await asyncio.to_thread(self.dependencies.is_sam_running))
            except Exception as e:
                self._diagnostic("action_failed", owner, source=source, action=action, error=str(e))
                print(f"MCP: Error in handle_action: {e}")
            finally:
                pending_owner = state.consume_busy_menu_stop()
                try:
                    if pending_owner:
                        # Owner replacement must never turn old buffered input
                        # into a stop of the new session. The gateway validates
                        # identity again immediately before its side effects.
                        current = await asyncio.to_thread(self.read_owner)
                        if owner_key(current) == pending_owner:
                            self._diagnostic("exit_requested", current, action="exit", play_current=False, routing="busy_pending")
                            result = await self.dependencies.stop_sam(state, play_current=False, owner=current)
                            self._diagnostic("exit_result", current, action="exit", play_current=False, result=result)
                            state.set_sam_running(await asyncio.to_thread(self.dependencies.is_sam_running))
                except Exception as e:
                    self._diagnostic("exit_failed", reason="pending_menu_stop", error=str(e))
                    print(f"MCP: Error in pending Menu Stop: {e}")
                finally:
                    state.set_stopping(False)
        loop.create_task(do_actions())

    def menu_requires_stop(self, state, owner, in_menu, now=None):
        """Arm only after seeing a game for this launch; debounce external Menu."""
        now = time.monotonic() if now is None else now
        launch = (owner_key(owner), owner.get("launch", "0")) if owner else None
        if launch != state.menu_owner or not owner or owner.get("phase") != "playing":
            state.menu_owner, state.menu_armed, state.menu_since = launch, False, None
        if not owner or owner.get("phase") != "playing":
            return False
        if in_menu is None:
            state.menu_since = None
            return False
        if not in_menu:
            state.menu_armed, state.menu_since = True, None
        elif state.menu_armed:
            if state.menu_since is None:
                state.menu_since = now
            return now - state.menu_since >= 2
        return False

    async def launch_and_confirm(self, state, target=None):
        state.set_sam_starting(True)
        self._diagnostic("startup_requested", target=target)
        try:
            # Popen is short and occurs on the event loop: input cannot race between
            # process creation and storing its handle.
            if target is None:
                self.dependencies.start_sam(state)
            else:
                self.dependencies.start_sam(state, target)
            startup_next = False
            for _ in range(100):
                await asyncio.sleep(.1)
                pending = state.consume_pending_action()
                if pending == "next":
                    startup_next = True
                    pending = None
                if pending:
                    self._diagnostic("startup_cancelled", action=pending)
                    await self.dependencies.cancel_launcher(state)
                    # No launcher can create a session after this cleanup barrier.
                    owner = await asyncio.to_thread(self.read_owner)
                    if owner:
                        keep = pending in ('start', 'zaparoo') and owner.get('phase') in ('playing', 'video')
                        self._diagnostic("exit_requested", owner, action=pending, play_current=keep, routing="startup_cancel")
                        result = await self.dependencies.stop_sam(state, play_current=keep, owner=owner)
                        self._diagnostic("exit_result", owner, action=pending, play_current=keep, result=result)
                    else:
                        await asyncio.to_thread(self.dependencies.kill_sam_processes)
                    state.update_activity(log_event=False)
                    return
                owner = await asyncio.to_thread(self.read_owner)
                if (not owner and state.launcher.poll() == 0
                        and (self.dependencies.menu_active()
                             or await asyncio.to_thread(self.dependencies.empty_selection_blocked))):
                    # A fast empty session may finish between owner samples.
                    # Its typed result is terminal; do not call this a timeout
                    # or dispatch another Menu/core cleanup command.
                    self._diagnostic("startup_completed", outcome="quiet_no_owner")
                    state.launcher.wait()
                    state.launcher = None
                    state.set_sam_running(False)
                    state.update_activity(log_event=False)
                    return
                if not owner and state.launcher.poll() not in (None, 0):
                    self._diagnostic("startup_rejected", returncode=state.launcher.poll())
                    print("MCP: SAM start was rejected; see the launcher's error above.")
                    await self.dependencies.cancel_launcher(state)
                    state.update_activity(log_event=False)
                    return
                if owner and state.launcher.poll() is not None:
                    pending = state.consume_pending_action()
                    if pending and pending != "next":
                        self._diagnostic("startup_cancelled", owner, action=pending)
                        await self.dependencies.cancel_launcher(state)
                        # Re-read after the launcher barrier; never act on a replaced
                        # owner, and use ordinary Menu/audio ordering once it launched.
                        current = await asyncio.to_thread(self.read_owner)
                        if owner_key(current) == owner_key(owner):
                            keep = pending in ('start', 'zaparoo') and current.get('phase') in ('playing', 'video')
                            self._diagnostic("exit_requested", current, action=pending, play_current=keep, routing="startup_cancel")
                            result = await self.dependencies.stop_sam(state, play_current=keep, owner=current)
                            self._diagnostic("exit_result", current, action=pending, play_current=keep, result=result)
                        state.update_activity(log_event=False)
                        return
                    startup_next = startup_next or pending == "next"
                    state.launcher.wait()
                    state.launcher = None
                    state.set_sam_running(True)
                    self._diagnostic("startup_completed", owner, startup_next=startup_next)
                    if startup_next:
                        self._diagnostic("command_requested", owner, command="next")
                        result = await asyncio.to_thread(self.dependencies.skip_game, owner)
                        self._diagnostic("command_result", owner, command="next", result=result)
                    return
            self._diagnostic("startup_rejected", reason="timeout")
            print("MCP: SAM startup timed out; cancelling launcher and owner.")
            await self.dependencies.cancel_launcher(state)
            await asyncio.to_thread(self.dependencies.kill_sam_processes)
            state.update_activity(log_event=False)
        finally:
            state.set_sam_starting(False)
