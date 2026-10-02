#!/usr/bin/env python3
import asyncio
import configparser
import os
import signal
import subprocess
import struct
import time
import json
import threading

# --- Configuration (from Script 1) ---
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
SAM_BASE_PATH = "/media/fat/Scripts/.MiSTer_SAM"
SAM_ON_SCRIPT = "/media/fat/Scripts/MiSTer_SAM_on.sh"
INI_FILE = "/media/fat/Scripts/MiSTer_SAM.ini"
CONTROLLER_CONFIG_FILE = os.path.join(SAM_BASE_PATH, "sam_controllers.json")
SAM_SESSION_NAME = "SAM"
SAM_OWNER_FILE = "/tmp/.SAM_tmp/session-owner"
CORENAME_FILE = "/tmp/CORENAME"
PROC_ROOT = "/proc"
SAM_STATE_FILE = "/tmp/SAM_state"
M82_PHASE_FILE = "/tmp/.SAM_tmp/m82_phase"  # "bios" or "game", written by pick_rom()

# --- Constants for jsX Polling (from Script 2) ---
JS_EVENT_FORMAT = "IhBB" # timestamp, value, type, number
JS_EVENT_SIZE = struct.calcsize(JS_EVENT_FORMAT)
JOY_POLL_RATE = 0.02 # 50 times per second for responsiveness
AXIS_DEADZONE = 2000
BUTTON_TYPE = 0x01
AXIS_TYPE = 0x02
# 0x80 is INIT event, we can filter for button/axis
JS_EVENT_TYPES = BUTTON_TYPE | AXIS_TYPE

tasks = {}
rescan_lock = None


class SamState:
    """
    A thread-safe class to hold the state of our monitor.
    """
    def __init__(self, timeout=120, menu_only=True):
        self.last_activity = time.monotonic()
        self.idle_timeout = timeout
        self.menu_only = menu_only
        self._sam_is_running = False
        # Add a flag to suppress "Activity detected" logs when SAM is not running
        self._is_stopping = False
        self._log_activity = False
        self._lock = threading.Lock() # A standard thread lock
        self._boot_complete = False
        self._sam_is_starting = False   # True from start_sam() until tmux confirmed
        self._pending_action = None     # Buffered action during startup window
        self._start_time = 0            # When start_sam() was triggered
        self.m82 = False
        self.ignore_when_skip = False
        self.listenjoy = True
        self.launcher = None
        self.menu_owner = None
        self.menu_armed = False
        self.menu_since = None

    def update_activity(self, log_event=True):
        """Call this to reset the idle timer. Thread-safe."""
        with self._lock:
            self.last_activity = time.monotonic()
            # Only log if the global log flag is on AND this specific event requests it
            if self._log_activity and log_event:
                print("MCP: Activity detected, idle timer reset.")

    def get_idle_time(self):
        """Returns the current number of idle seconds. Thread-safe."""
        with self._lock:
            return time.monotonic() - self.last_activity

    def set_sam_running(self, status: bool):
        """Set the running status. Thread-safe."""
        with self._lock:
            self._log_activity = status # Log activity only when SAM is running
            self._sam_is_running = status

    def is_sam_running(self) -> bool:
        """Get the running status. Thread-safe."""
        with self._lock:
            return self._sam_is_running

    def set_stopping(self, status: bool):
        """Set the stopping status. Thread-safe."""
        with self._lock:
            self._is_stopping = status

    def is_stopping(self) -> bool:
        """Check if we are in the process of stopping. Thread-safe."""
        with self._lock:
            return self._is_stopping

    def set_boot_complete(self):
        """Mark the initial boot sequence as finished."""
        with self._lock:
            self._boot_complete = True

    def is_boot_complete(self) -> bool:
        """Check if we have passed the initial boot phase."""
        with self._lock:
            return self._boot_complete

    def set_sam_starting(self, status: bool):
        """Mark SAM as starting up (between Popen and tmux confirmation). Thread-safe."""
        with self._lock:
            self._sam_is_starting = status
            if status:
                self._start_time = time.monotonic()
                self._pending_action = None  # Clear any stale action
            else:
                self._start_time = 0

    def is_sam_starting(self) -> bool:
        """Check if SAM is currently in the startup window. Thread-safe."""
        with self._lock:
            return self._sam_is_starting

    def set_pending_action(self, action: str):
        """Buffer a user action during the startup window. Thread-safe."""
        with self._lock:
            self._pending_action = action
            print(f"MCP: SAM is starting up. Buffered '{action}' action.")

    def consume_pending_action(self):
        """Atomically read and clear the pending action. Thread-safe."""
        with self._lock:
            action = self._pending_action
            self._pending_action = None
            return action

    def set_mode(self, m82: bool, ignore_when_skip: bool, listenjoy: bool):
        """Store SAM mode flags read from INI. Thread-safe."""
        with self._lock:
            self.m82 = m82
            self.ignore_when_skip = ignore_when_skip
            self.listenjoy = listenjoy
# --- Core SAM Functions (from Script 1) ---
# These are blocking and will be run in threads

def read_literal_file(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = f.read(16385)
        if len(data) > 16384:
            return {}
        return dict(line.split("=", 1) for line in data.splitlines() if "=" in line)
    except (OSError, UnicodeError):
        return {}


def read_sam_owner():
    """A tmux pane alone is not proof of a live SAM session."""
    record = read_literal_file(SAM_OWNER_FILE)
    pid, ticks = record.get("pid", ""), record.get("start", "")
    if not pid.isascii() or not pid.isdecimal() or int(pid) <= 1 or not ticks.isdecimal():
        return None
    try:
        with open(os.path.join(PROC_ROOT, pid, "stat")) as f:
            fields = f.read().rsplit(") ", 1)[1].split()
        if fields[0] in ("Z", "X", "x") or fields[19] != ticks:
            return None
    except (OSError, IndexError):
        return None
    return record


def owner_key(owner):
    return (owner["pid"], owner["start"]) if owner else None


def session_is_m82(owner, configured):
    """Mode changes apply to the current verified session without an MCP restart."""
    status = read_literal_file(SAM_STATE_FILE)
    if owner and status.get("active") == "yes" and (
        status.get("owner_pid"), status.get("owner_start")
    ) == owner_key(owner) and status.get("mode") in {"normal", "roulette", "m82", "samvideo"}:
        return status["mode"] == "m82"
    return configured


def is_sam_running():
    return read_sam_owner() is not None


def start_sam(state):
    """Keep the launcher so cancellation is a barrier against late starts."""
    print("Idle timeout reached. Starting SAM...")
    state.launcher = subprocess.Popen([SAM_ON_SCRIPT, "start"], start_new_session=True)


async def cancel_launcher(state):
    process = state.launcher
    if process is None:
        return
    # The group belongs only to this MCP launch. Stop it before session cleanup.
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            await asyncio.to_thread(process.wait, 2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            await asyncio.to_thread(process.wait)
    else:
        process.wait()
    state.launcher = None


async def exit_to_menu_with_retry(state, max_wait=15, owner=None):
    """
    Attempts to load the menu core, retrying if MiSTer is busy.
    """
    t0 = time.monotonic()
    def elapsed():
        return f"{time.monotonic() - t0:.2f}s"

    print(f"[{elapsed()}] exit_to_menu_with_retry: starting (max_wait={max_wait}s)")

    # Run cleanup and wait for it to finish before loading the menu core.
    # Using Popen (non-blocking) here caused a race where load_core fired
    # before sam_cleanup could unmount Volume.dat, leaving audio muted.
    # Run the fast exit: unmounts Volume.dat synchronously (audio-critical),
    # then backgrounds BGM/tty cleanup so we can load the menu immediately.
    print(f"[{elapsed()}] MCP: Running fast cleanup (unmute + background BGM/tty)...")
    target = list(owner_key(owner)) if owner else []
    result = await asyncio.to_thread(subprocess.run, [SAM_ON_SCRIPT, "exit_to_menu_fast", *target])
    if result.returncode:
        print("MCP: Owner changed or cleanup failed; menu request cancelled.")
        return
    print(f"[{elapsed()}] MCP: Fast cleanup done.")

    for attempt in range(max_wait):
        print(f"[{elapsed()}] Attempt {attempt + 1}/{max_wait}: checking if menu is loaded...")

        # Always send the load_core command on the first attempt to prevent sticky state aborts
        if attempt > 0:
            in_menu = await asyncio.to_thread(is_in_menu, state)
            if in_menu:
                print(f"[{elapsed()}] ✅ SUCCESS: Menu core is now loaded.")
                return

        print(f"[{elapsed()}] Menu not loaded. Sending 'load_core' command...")
        await asyncio.to_thread(subprocess.run,
            ["timeout", "1", "sh", "-c",
             "printf '%s\\n' 'load_core /media/fat/menu.rbf' > /dev/MiSTer_cmd"])
        print(f"[{elapsed()}] load_core command sent. Sleeping 1s...")
        await asyncio.sleep(1)

    print(f"[{elapsed()}] ❌ FAILED: Timed out after {max_wait} seconds. Menu core did not load.")

async def stop_sam(state, play_current=False, owner=None):
    """Stops SAM and all related services directly from Python."""
    t0 = time.monotonic()
    print(f"[+0.00s] stop_sam: starting (play_current={play_current})")
    try:
        if play_current:
            print(f"[+{time.monotonic()-t0:.2f}s] stop_sam: launching exit_to_game...")
            await asyncio.to_thread(subprocess.run, [SAM_ON_SCRIPT, "exit_to_game", *(owner_key(owner) or ())])
            print(f"[+{time.monotonic()-t0:.2f}s] stop_sam: exit_to_game launched.")
        else:
            await exit_to_menu_with_retry(state, owner=owner)
    except Exception as e:
        print(f"MCP: Error during stop_sam: {e}")
    print(f"[+{time.monotonic()-t0:.2f}s] stop_sam: done.")
def skip_game():
    """Sends a skip command to the running SAM session."""
    print("User pressed 'Next'. Skipping to next game...")
    subprocess.Popen(["tmux", "send-keys", "-t", SAM_SESSION_NAME, "n"])

def ignore_game():
    """Adds the current game to the ignore list."""
    print("MCP: Ignoring current game...")
    subprocess.run([SAM_ON_SCRIPT, "control", "ignore"], check=False)

def unmute_sam():
    """Calls the SAM unmute routine."""
    print("MCP: Unmuting...")
    subprocess.run([SAM_ON_SCRIPT, "unmute"])

def read_m82_phase() -> str:
    """Returns 'bios', 'game', or 'unknown' based on the phase file written by pick_rom()."""
    try:
        with open(M82_PHASE_FILE, 'r') as f:
            return f.read().strip()
    except Exception:
        return "unknown"

def play_m82_game():
    """Signals M82 to enter play mode: extends the countdown timer and unmutes audio."""
    print("MCP-M82: Sending play signal ('y') to SAM session...")
    subprocess.Popen(["tmux", "send-keys", "-t", SAM_SESSION_NAME, "y"])

def is_in_menu(state):
    """
    Check if the MiSTer process is currently running the menu.rbf core.
    """
    try:
        if os.path.exists(CORENAME_FILE):
            with open(CORENAME_FILE, 'r') as f:
                corename = f.read().strip()
                if corename == 'MENU':
                    if not state.is_boot_complete():
                        print("MCP: Boot Detection - Menu found via CORENAME.")
                        state.set_boot_complete()
                    return True
                elif corename:
                    if not state.is_boot_complete():
                        print(f"MCP: Boot Detection - Found active core '{corename}'.")
                        state.set_boot_complete()
                    return False
    except Exception:
        pass
    return None  # unavailable is not evidence that a game core was loaded

# --- Joystick Polling Logic (from Script 2, adapted) ---

def get_js_activity(
    prev: list[dict[str, int]], next_events: list[dict[str, int]], controller_config
) -> str:
    """
    Compares two js state lists (as per original joy script)
    and returns an action string or None.
    """
    if len(prev) != len(next_events):
        return None

    button_map = controller_config.get("button", {})
    axis_map = controller_config.get("axis", {})

    # This simplified logic just checks for any significant event change
    for prev_event, next_event in zip(prev, next_events):
        is_button = next_event["type"] & BUTTON_TYPE
        is_axis = next_event["type"] & AXIS_TYPE

        if is_button and prev_event["value"] != next_event["value"] and next_event["value"] == 1:
            button_num = next_event["number"]
            if button_num == button_map.get("start"): return "start"
            if button_num == button_map.get("next"): return "next"
            if button_num == button_map.get("exit"): return "exit"
            return "default"

        if is_axis and abs(prev_event["value"] - next_event["value"]) > AXIS_DEADZONE:
            axis_num = next_event["number"]
            axis_val = next_event["value"]
            next_config = axis_map.get("next", {})
            if axis_num == next_config.get("code") and axis_val == next_config.get("value"):
                return "next"
            return "default"

    return None

def kill_sam_processes(owner=None):
    """Ask SAM to stop its verified owner and owned jobs, including cleanup."""
    subprocess.run([SAM_ON_SCRIPT, "stop_owner", *(owner_key(owner) or ())], stderr=subprocess.DEVNULL)


def handle_action(action, state, loop, source="keyboard"):
    if not action or (source == "joystick" and not state.listenjoy):
        return
    state.update_activity()
    # Input during launch must reach cancellation even before an owner exists.
    if state.is_sam_starting():
        state.set_pending_action(action)
        return
    if state.is_stopping():
        return
    state.set_stopping(True)

    async def do_actions():
        try:
            owner = await asyncio.to_thread(read_sam_owner)
            if not owner:
                state.set_sam_running(False)
                return
            state.set_sam_running(True)
            in_menu = await asyncio.to_thread(is_in_menu, state)
            if session_is_m82(owner, state.m82) and not in_menu:
                if action == "next":
                    await asyncio.to_thread(skip_game)
                elif await asyncio.to_thread(read_m82_phase) != "bios":
                    await asyncio.to_thread(play_m82_game)
            elif action == "next":
                if state.ignore_when_skip and owner.get("phase") == "playing":
                    await asyncio.to_thread(ignore_game)
                else:
                    await asyncio.to_thread(skip_game)
            else:
                # Stop the owner before loading Menu. Never let Menu override a
                # Next request or infer liveness from a stale core name.
                keep = action in ("start", "zaparoo") and in_menu is False
                if action == "zaparoo":
                    await asyncio.to_thread(unmute_sam)
                # A replaced session must not inherit an old input request.
                if owner_key(await asyncio.to_thread(read_sam_owner)) != owner_key(owner):
                    return
                await stop_sam(state, play_current=keep, owner=owner)
                state.set_sam_running(await asyncio.to_thread(is_sam_running))
        except Exception as e:
            print(f"MCP: Error in handle_action: {e}")
        finally:
            state.set_stopping(False)
    loop.create_task(do_actions())


def joystick_poller_thread(device_info, state, controller_config, loop, stop_event):
    """
    This function runs in a separate thread and uses a non-blocking polling
    loop that is state-aware, exactly like the original working script.
    """
    dev_path = device_info['js_path']
    device_id = device_info.get('id', 'default')
    device_config = controller_config.get(device_id, controller_config.get("default", {}))

    print(f"MCP-JS: Starting poller for {device_info.get('name', 'Unknown')} ({dev_path})")

    previous_events = []
    sam_was_running = state.is_sam_running()

    while not stop_event.is_set():
        # When SAM transitions from running → stopped, reset joystick state.
        # This prevents a button held across the stop boundary from re-firing.
        sam_is_running = state.is_sam_running()
        if sam_was_running and not sam_is_running:
            print(f"MCP-JS: SAM stopped. Resetting input state for {dev_path}.")
            previous_events = []
        sam_was_running = sam_is_running

        try:
            with open(dev_path, "rb") as f:
                os.set_blocking(f.fileno(), False)
                data = f.read(512)
            if data:
                current_events = [dict(zip(("timestamp", "value", "type", "number"), struct.unpack(JS_EVENT_FORMAT, data[i:i+JS_EVENT_SIZE]))) for i in range(0, len(data), JS_EVENT_SIZE) if len(data[i:i+JS_EVENT_SIZE]) == JS_EVENT_SIZE]

                if not previous_events:
                    previous_events = current_events
                    print(f"MCP-JS: Initial state captured for {dev_path}. Listening for changes...")
                else:
                    action = get_js_activity(previous_events, current_events, device_config)
                    if action:
                        if state.is_sam_running() or state.is_sam_starting():
                            # SAM is active — log and route through full action handler.
                            print(f"MCP-JS: Button action '{action}' detected on {dev_path}")
                            loop.call_soon_threadsafe(handle_action, action, state, loop, "joystick")
                        else:
                            # User is playing normally — just reset the idle timer
                            # so SAM doesn't launch on an active player.
                            state.update_activity(log_event=False)

                previous_events = current_events
        except (BlockingIOError, FileNotFoundError):
            pass # This is expected on a non-blocking read with no data.
        except Exception as e:
            print(f"MCP-JS: Transient error in poller for {dev_path}: {e}")
            stop_event.wait(1)
            continue
        stop_event.wait(JOY_POLL_RATE)

    print(f"MCP-JS: Poller for {dev_path} stopped.")

def keyboard_poller_thread(device_path, state, loop, stop_event):
    """
    This function runs in a separate thread and polls a keyboard hidraw device.
    Any data read from it is considered activity.
    """
    print(f"MCP-Keyboard: Starting blocking poller for {device_path}")
    while not stop_event.is_set():
        try:
            # Use a blocking read, which is more efficient.
            # The thread will sleep until data is available.
            with open(device_path, "rb") as f:
                if f.read(1): # Read at least one byte, this will block until data is ready
                    loop.call_soon_threadsafe(handle_action, "default", state, loop)
                    time.sleep(1) # After triggering, sleep for a second to "debounce".
        except FileNotFoundError:
            print(f"MCP-Keyboard: Device {device_path} disconnected. Stopping poller.")
            break # Exit the loop immediately.
        except Exception as e:
            print(f"MCP-Keyboard: Error in poller for {device_path}: {e}")
            break
    print(f"MCP-Keyboard: Poller for {device_path} stopped.")

def mouse_poller_thread(device_path, state, loop, stop_event):
    """Wrapper for the generic poller for mice."""
    # The logic is identical to the keyboard poller, just with different logging.
    print(f"MCP-Mouse: Starting poller for {device_path}")
    while not stop_event.is_set():
        try:
            with open(device_path, "rb") as f:
                if f.read(1): # This will block until the mouse moves
                    loop.call_soon_threadsafe(handle_action, "default", state, loop)
                    time.sleep(1) # Debounce to prevent event floods
        except FileNotFoundError:
            print(f"MCP-Mouse: Device {device_path} disconnected. Stopping poller.")
            break # Exit the loop immediately.
        except Exception as e:
            print(f"MCP-Mouse: Error in poller for {device_path}: {e}")
            break
    print(f"MCP-Mouse: Poller for {device_path} stopped.")

def remote_log_poller_thread(log_path, state, loop, stop_event):
    """
    Tails the remote.log file and triggers activity on specific log entries.
    Runs in a separate thread.
    """
    print(f"MCP-RemoteLog: Starting poller for {log_path}")

    while not stop_event.is_set():
        # If the file doesn't exist yet, just wait for it.
        if not os.path.exists(log_path):
            stop_event.wait(1)
            continue

        try:
            with open(log_path, "r") as f:
                # Seek to the end immediately so we only react to NEW network inputs
                f.seek(0, os.SEEK_END)

                while not stop_event.is_set():
                    line = f.readline()
                    if not line:
                        # If EOF, check if the file was deleted/rotated
                        try:
                            current, opened = os.stat(log_path), os.fstat(f.fileno())
                            if (current.st_dev, current.st_ino) != (opened.st_dev, opened.st_ino):
                                break
                            if current.st_size < f.tell():
                                f.seek(0)
                        except OSError:
                            break
                        stop_event.wait(0.5) # Wait briefly for new data
                        continue

                    # Check for our specific trigger phrase
                    if "kbd" in line:
                        # Send the "default" action to wake up SAM/reset idle timers
                        loop.call_soon_threadsafe(handle_action, "default", state, loop)

                        # Debounce for 1 second to prevent event floods from mashing
                        stop_event.wait(1)

                        # After waking up, jump to the end of the file again
                        # to discard any queued inputs that piled up during sleep
                        f.seek(0, os.SEEK_END)

        except Exception as e:
            print(f"MCP-RemoteLog: Transient error tailing {log_path}: {e}")
            time.sleep(1)

    print(f"MCP-RemoteLog: Poller for {log_path} stopped.")

def zaparoo_poller_thread(activity_file, state, loop, stop_event):
    """
    Polls the SAM_Joy_Activity file for zaparoo NFC tap events.
    Zaparoo is an external service that writes "zaparoo" into this file when
    a tag is scanned. We read it, truncate it, and fire the zaparoo action.
    """
    print(f"MCP-Zaparoo: Starting poller for {activity_file}")
    while not stop_event.is_set():
        try:
            if os.path.exists(activity_file) and os.path.getsize(activity_file) > 0:
                with open(activity_file, "r+") as f:
                    content = f.read().strip()
                    f.seek(0)
                    f.truncate()
                if content == "zaparoo":
                    print("MCP-Zaparoo: NFC tap detected.")
                    loop.call_soon_threadsafe(handle_action, "zaparoo", state, loop)
        except Exception as e:
            print(f"MCP-Zaparoo: Error reading activity file: {e}")
        stop_event.wait(0.5)
    print(f"MCP-Zaparoo: Poller stopped.")

async def run_input_reader(function, args, stop_event):
    """Long-lived device reads must not exhaust asyncio's command executor."""
    loop = asyncio.get_running_loop()
    done = loop.create_future()
    def finish():
        if not done.done():
            done.set_result(None)
    def read():
        try:
            function(*args, stop_event)
        finally:
            try:
                loop.call_soon_threadsafe(finish)
            except RuntimeError:
                pass  # interpreter shutdown after the loop has closed
    thread = threading.Thread(target=read, daemon=True, name="SAM-input")
    thread.start()
    try:
        await asyncio.shield(done)
    finally:
        stop_event.set()
        # Sleep/read loops all observe this event within at most one second.
        try:
            await asyncio.wait_for(asyncio.shield(done), 1.5)
        except (asyncio.TimeoutError, asyncio.CancelledError):
            pass


def register_input_reader(path, function, args):
    stop_event = threading.Event()
    tasks[path] = (asyncio.create_task(run_input_reader(function, args, stop_event)), stop_event)


async def watch_zaparoo(activity_file, state, loop):
    os.makedirs(os.path.dirname(activity_file), exist_ok=True)
    if not os.path.exists(activity_file):
        open(activity_file, 'w').close()
    register_input_reader(activity_file, zaparoo_poller_thread, (activity_file, state, loop))


async def watch_joystick_device(device_info, state, controller_config, loop):
    register_input_reader(device_info['js_path'], joystick_poller_thread,
                          (device_info, state, controller_config, loop))


async def watch_keyboard_device(device_path, state, loop):
    if device_path:
        register_input_reader(device_path, keyboard_poller_thread, (device_path, state, loop))


async def watch_mouse_device(device_path, state, loop):
    if device_path:
        register_input_reader(device_path, mouse_poller_thread, (device_path, state, loop))


async def watch_remote_log(log_path, state, loop):
    register_input_reader(log_path, remote_log_poller_thread, (log_path, state, loop))


def menu_requires_stop(state, owner, in_menu, now=None):
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


async def launch_and_confirm(state):
    state.set_sam_starting(True)
    try:
        # Popen is short and occurs on the event loop: input cannot race between
        # process creation and storing its handle.
        start_sam(state)
        startup_next = False
        for _ in range(100):
            await asyncio.sleep(.1)
            pending = state.consume_pending_action()
            if pending == "next":
                startup_next = True
                pending = None
            if pending:
                await cancel_launcher(state)
                # No launcher can create a session after this cleanup barrier.
                await asyncio.to_thread(kill_sam_processes)
                state.update_activity(log_event=False)
                return
            owner = await asyncio.to_thread(read_sam_owner)
            if owner and state.launcher.poll() is not None:
                pending = state.consume_pending_action()
                if pending and pending != "next":
                    await cancel_launcher(state)
                    await asyncio.to_thread(kill_sam_processes, owner)
                    state.update_activity(log_event=False)
                    return
                startup_next = startup_next or pending == "next"
                state.launcher.wait()
                state.launcher = None
                state.set_sam_running(True)
                if startup_next:
                    await asyncio.to_thread(skip_game)
                return
        print("MCP: SAM startup timed out; cancelling launcher and owner.")
        await cancel_launcher(state)
        await asyncio.to_thread(kill_sam_processes)
        state.update_activity(log_event=False)
    finally:
        state.set_sam_starting(False)


async def idle_and_status_checker(state):
    while True:
        try:
            owner = await asyncio.to_thread(read_sam_owner)
            if state.is_stopping():
                await asyncio.sleep(1)
                continue
            state.set_sam_running(owner is not None)
            in_menu = await asyncio.to_thread(is_in_menu, state)
            if menu_requires_stop(state, owner, in_menu):
                state.set_stopping(True)
                try:
                    # Menu is already loaded: cleanup must not load it again.
                    print("MCP: External Menu detected; stopping verified SAM owner.")
                    await asyncio.to_thread(kill_sam_processes, owner)
                    state.set_sam_running(False)
                    state.update_activity(log_event=False)
                finally:
                    state.set_stopping(False)
            elif not owner and not state.is_stopping():
                idle_time = state.get_idle_time()
                can_start = not state.menu_only or in_menu
                if can_start and idle_time > state.idle_timeout:
                    await launch_and_confirm(state)
            await asyncio.sleep(1)
        except asyncio.CancelledError:
            await cancel_launcher(state)
            raise
        except Exception as e:
            print(f"MCP: Error in idle checker: {e}")
            await asyncio.sleep(5)


def get_hidraw_for_keyboard(phys_addr):
    """
    Finds the /dev/hidrawX device that matches a keyboard's physical address.
    """
    if not phys_addr:
        return None

    try:
        for hidraw_name in os.listdir('/sys/class/hidraw'):
            uevent_path = f'/sys/class/hidraw/{hidraw_name}/device/uevent'
            if os.path.exists(uevent_path):
                with open(uevent_path, 'r') as f:
                    for line in f:
                        if line.startswith('HID_PHYS='):
                            hidraw_phys = line.strip().split('=')[1].strip('"')
                            if hidraw_phys == phys_addr:
                                return f"/dev/{hidraw_name}"
    except FileNotFoundError:
        # /sys/class/hidraw might not exist if no HID devices are present
        pass
    except Exception as e:
        print(f"MCP: Error finding hidraw device: {e}")
    return None

def get_input_devices():
    """
    Scans /proc/bus/input/devices to find jsX handlers and keyboard hidraw devices.
    """
    all_devices = []
    current_device = {}

    try:
        with open('/proc/bus/input/devices', 'r') as f:
            for line in f:
                line = line.strip()
                if line == '':
                    if current_device:
                        all_devices.append(current_device)
                    current_device = {}
                    continue

                try:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip('"') # Strip quotes from all values
                except ValueError:
                    continue # Skips lines without '='

                if key == 'N: Name':
                    current_device['name'] = value
                elif key == 'P: Phys':
                    # This is the physical address we need to match
                    current_device['proc_phys'] = value
                elif key == 'S: Sysfs':
                    current_device['sysfs'] = value
                elif key == 'I: Bus':
                    parts = {}
                    for p in value.split():
                        try:
                            k, v = p.split('=')
                            parts[k] = v
                        except ValueError:
                            pass
                    vendor = int(parts.get('Vendor', '0'), 16)
                    product = int(parts.get('Product', '0'), 16)
                    current_device['id'] = f"{vendor:04x}_{product:04x}"
                elif key == 'H: Handlers':
                    handlers = value.split()
                    # Find the 'js' handler
                    for handler in handlers:
                        if handler.startswith('js'):
                            current_device['js_path'] = f"/dev/input/{handler}"

                    # Check for the 'kbd' handler to identify a keyboard
                    if 'kbd' in handlers:
                        current_device['is_keyboard'] = True

    except FileNotFoundError:
        print("MCP: Error - /proc/bus/input/devices not found.")
        return {'joysticks': [], 'keyboards': [], 'has_mouse': False}
    except Exception as e:
        print(f"MCP: Error parsing /proc/bus/input/devices: {e}")

    if current_device: # Add the last device
        all_devices.append(current_device)

    # --- Process the raw device list ---

    joysticks = [
        d for d in all_devices
        if 'js_path' in d
        and "motion sensors" not in d.get('name', '').lower()
        and "zaparoo" not in d.get('name', '').lower()
    ]

    # --- Find keyboards and their corresponding hidraw devices ---
    # USB HID gamepads enumerate with a 'kbd' handler alongside their joystick interface.
    # Their hidraw device sends continuous HID reports, which would constantly reset the
    # idle timer. Exclude any keyboard device that shares the same USB parent as a joystick.
    # Both interfaces share the same P: Phys prefix, e.g. "usb-xxx/input0" vs "usb-xxx/input2".
    def _usb_parent(phys: str) -> str:
        return phys.rsplit('/', 1)[0] if phys and '/' in phys else phys

    joystick_usb_parents = {_usb_parent(d.get('proc_phys', '')) for d in joysticks}

    keyboards = []
    for d in all_devices:
        # A real keyboard: has 'is_keyboard', is not virtual, and is not from the same
        # USB device as any detected joystick.
        if d.get('is_keyboard') and 'virtual' not in d.get('sysfs', '') \
                and _usb_parent(d.get('proc_phys', '')) not in joystick_usb_parents:

            # Get the physical address from 'P: Phys='
            phys_addr = d.get('proc_phys')

            if phys_addr:
                # Find the matching hidraw device
                hidraw_path = get_hidraw_for_keyboard(phys_addr)
                if hidraw_path:
                    d['hidraw_path'] = hidraw_path
                    keyboards.append(d)

    has_mouse = any('mouse' in d.get('name', '').lower() for d in all_devices)

    return {'joysticks': joysticks, 'keyboards': keyboards, 'has_mouse': has_mouse}

async def rescan_devices(state, controller_config, listen_config, loop):
    """Scans all devices and starts/stops monitors as needed."""
    # Use a lock to ensure only one rescan happens at a time.
    global rescan_lock
    if rescan_lock is None:
        rescan_lock = asyncio.Lock()  # bind to the actual asyncio.run loop on Python 3.9
    async with rescan_lock:
        await _rescan_devices_impl(state, controller_config, listen_config, loop)

async def _rescan_devices_impl(state, controller_config, listen_config, loop):
    print("MCP: Rescanning all input devices...")
    try:
        all_current_devices = await asyncio.to_thread(get_input_devices)

        # --- Build sets of current and monitored devices ---
        current_js = set()
        if listen_config.get("listenjoy", True):
            current_js = {d['js_path'] for d in all_current_devices['joysticks']}

        current_kbds = set()
        if listen_config.get("listenkeyboard", True):
            current_kbds = {d['hidraw_path'] for d in all_current_devices['keyboards']}

        current_mouse = set()
        if listen_config.get("listenmouse", True) and os.path.exists("/dev/input/mice"):
            current_mouse = {"/dev/input/mice"}

        all_current_devs = current_js.union(current_kbds).union(current_mouse)
        for path, (task, stop_event) in list(tasks.items()):
            if path.startswith(('/dev/input/', '/dev/hidraw')) and task.done():
                tasks.pop(path)
        all_monitored_devs = {path for path in tasks if path.startswith(('/dev/input/', '/dev/hidraw'))}

        # --- Determine which devices to add or remove ---
        added_devices = all_current_devs - all_monitored_devs
        removed_devices = all_monitored_devs - all_current_devs

        # --- Handle removed devices ---
        for dev_path in removed_devices:
            print(f"MCP: Hot-plug REMOVED: {dev_path}")
            if dev_path in tasks:
                task, stop_event = tasks.pop(dev_path)
                if stop_event:
                    stop_event.set()
                task.cancel()

        # --- Handle added devices ---
        for dev_path in added_devices:
            if dev_path.startswith('/dev/input/js'):
                device_info = next((d for d in all_current_devices['joysticks'] if d['js_path'] == dev_path), None)
                if device_info:
                    print(f"MCP-JS: Hot-plug ADDED: {dev_path}")
                    await watch_joystick_device(device_info, state, controller_config, loop)
            elif dev_path.startswith('/dev/hidraw'):
                print(f"MCP-Keyboard: Hot-plug ADDED: {dev_path}")
                await watch_keyboard_device(dev_path, state, loop)
            elif dev_path == '/dev/input/mice':
                print(f"MCP-Mouse: Hot-plug ADDED: {dev_path}")
                await watch_mouse_device(dev_path, state, loop)
    except Exception as e:
        print(f"MCP: Error during device rescan: {e}")

async def hotplug_monitor_native(state, controller_config, listen_config, loop):
    """Monitors for device hotplug events using the 'inotifywait' utility."""
    print("MCP: Hot-plug monitor started (event-driven via inotifywait).")

    # We watch /dev/input recursively and then filter for 'by-path' events in our loop.
    # This is the most reliable way to handle the 'by-path' directory being deleted and recreated.
    cmd = [
        'inotifywait', '-m', '-r', '-q', '--format', '%w%f %e',
        '-e', 'create', '-e', 'delete', '/dev/input'
    ]

    process = await asyncio.create_subprocess_exec(*cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    debounce_timer = None
    debounce_delay = 2.0  # seconds to wait after the last event

    try:
        while True:
            try:
                # Asynchronously read a line of output from inotifywait
                line = await process.stdout.readline()
                if not line:
                    print("MCP: inotifywait process exited. Hotplug monitor stopping.")
                    break # Process has exited

                decoded_line = line.decode().strip()

                # Trigger a rescan on:
                #   - by-path symlink events (USB devices)
                #   - direct jsX node creation (Bluetooth / wireless controllers that skip by-path)
                parts = decoded_line.split()
                event_path = parts[0] if parts else ''
                event_type = parts[1] if len(parts) > 1 else ''
                is_relevant = (
                    '/dev/input/by-path/' in event_path
                    or event_path.startswith(('/dev/input/js', '/dev/input/event', '/dev/input/mice'))
                )

                if is_relevant:
                    # A physical device change was detected. Trigger a debounced rescan.
                    if debounce_timer:
                        debounce_timer.cancel()
                    print(f"MCP: Hot-plug event detected ({decoded_line}). Scheduling rescan...")
                    debounce_timer = loop.call_later(debounce_delay, lambda: asyncio.create_task(rescan_devices(state, controller_config, listen_config, loop)))

            except asyncio.CancelledError:
                print("MCP: Hot-plug monitor cancelled.")
                raise
            except Exception as e:
                print(f"MCP: Error in hotplug monitor: {e}")
                await asyncio.sleep(5) # Wait before retrying
    finally:
        if debounce_timer:
            debounce_timer.cancel()
        if process.returncode is None:
            try:
                process.terminate()
            except ProcessLookupError:
                pass
        await process.wait()

def shutdown(loop):
    print("MCP: Shutting down...")
    # This function can be called from a signal handler, so we use thread-safe calls.
    for path, (task, stop_event) in tasks.items():
        if stop_event:
            # This is a joystick poller thread, signal it to stop
            stop_event.set()
        if task:
            loop.call_soon_threadsafe(task.cancel)
    for task in asyncio.all_tasks(loop):
        loop.call_soon_threadsafe(task.cancel)

async def main():
    # 1. Read configuration (same as your script)
    config = configparser.ConfigParser(inline_comment_prefixes=('#', ';'), strict=False)
    listen_config = {"listenjoy": True, "listenkeyboard": True, "listenmouse": True}

    try:
        with open(INI_FILE, 'r') as f:
            ini_content = f.read()

        import os
        gameroulette_ini = "/tmp/.SAM_tmp/gameroulette.ini"
        if os.path.exists(gameroulette_ini):
            with open(gameroulette_ini, 'r') as f:
                ini_content += "\n" + f.read()

        config.read_string("[DEFAULT]\n" + ini_content)

        menu_only_raw = config.get("DEFAULT", "menuonly", fallback="yes")
        menu_only = menu_only_raw.strip('"\'').lower() in ['yes', 'true', '1', 'on']
        timeout = config.getint("DEFAULT", "samtimeout", fallback=60)

        # Load listen configs
        listen_config["listenjoy"] = config.get("DEFAULT", "listenjoy", fallback="yes").strip('"\'').lower() in ['yes', 'true', '1', 'on']
        listen_config["listenkeyboard"] = config.get("DEFAULT", "listenkeyboard", fallback="yes").strip('"\'').lower() in ['yes', 'true', '1', 'on']
        listen_config["listenmouse"] = config.get("DEFAULT", "listenmouse", fallback="yes").strip('"\'').lower() in ['yes', 'true', '1', 'on']

        # Load mode flags
        m82 = config.get("DEFAULT", "m82", fallback="no").strip('"\'').lower() in ['yes', 'true', '1', 'on']
        ignore_when_skip = config.get("DEFAULT", "ignore_when_skip", fallback="no").strip('"\'').lower() in ['yes', 'true', '1', 'on']
        # M82 mode needs joystick monitoring for phase-aware button handling.
        # listenjoy is respected from the INI as-is — do NOT force it off for M82.

    except Exception as e:
        print(f"MCP: Warning - Could not read or parse INI file: {e}")
        print("MCP: Using default values for timeout (60s) and menu_only (True).")
        timeout = 60
        menu_only = True
        m82 = False
        ignore_when_skip = False

    # Load controller configuration
    controller_config = {}
    config_file = os.path.join(SCRIPT_DIR, "sam_controllers.custom.json")
    if not os.path.exists(config_file):
        config_file = os.path.join(SCRIPT_DIR, "sam_controllers.json")

    try:
        with open(config_file, 'r') as f:
            controller_config = json.load(f)
        print(f"MCP: Successfully loaded controller configuration from {os.path.basename(config_file)}.")
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"MCP: Warning - Could not load or parse controller config: {e}")

    # 2. Initialize state
    state = SamState(timeout=timeout, menu_only=menu_only)
    state.set_mode(m82=m82, ignore_when_skip=ignore_when_skip, listenjoy=listen_config["listenjoy"])
    print(f"MCP started. Idle timeout: {state.idle_timeout}s, Menu-only: {state.menu_only}")
    print(f"MCP Listen Config: Joy={listen_config['listenjoy']}, Kbd={listen_config['listenkeyboard']}, Mouse={listen_config['listenmouse']}")

    # 3. Setup asyncio tasks
    tasks['checker'] = (asyncio.create_task(idle_and_status_checker(state)), None)

    loop = asyncio.get_running_loop()

    # 4. Initial scan for existing devices and start monitoring them
    # The new rescan function handles the initial scan perfectly.
    await rescan_devices(state, controller_config, listen_config, loop)

    # 4.5 Start the remote.log monitor for virtual network inputs
    if listen_config["listenkeyboard"]:
        await watch_remote_log("/tmp/remote.log", state, loop)

    # 4.6 Start the zaparoo NFC tap monitor
    await watch_zaparoo("/tmp/.SAM_tmp/SAM_Joy_Activity", state, loop)

    # 5. Start the hot-plug monitor task
    tasks['hotplug'] = (asyncio.create_task(hotplug_monitor_native(state, controller_config, listen_config, loop)), None)

    # 6. Setup signal handlers for graceful shutdown
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        loop.add_signal_handler(sig, shutdown, loop)

    # 6. Run all tasks until completion
    try:
        await asyncio.gather(*[t for t, e in tasks.values()], return_exceptions=True)
    except asyncio.CancelledError:
        print("MCP: Main task group cancelled.")

if __name__ == "__main__":
    try:
        # Wait for /media/fat to be mounted
        while not os.path.exists('/media/fat/Scripts'):
            print("MCP: Waiting for /media/fat/Scripts to be mounted...")
            time.sleep(1)

        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nMCP stopped by user.")
    except Exception as e:
        print(f"MCP: A critical error occurred: {e}")
    finally:
        print("MCP: Shutting down.")
