#!/usr/bin/env python3
import asyncio
import configparser
import os
import signal
import subprocess
import struct
import time
import json
import threading # We need threading

# --- Configuration (from Script 1) ---
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
SAM_BASE_PATH = "/media/fat/Scripts/.MiSTer_SAM"
SAM_ON_SCRIPT = "/media/fat/Scripts/MiSTer_SAM_on.sh"
INI_FILE = "/media/fat/Scripts/MiSTer_SAM.ini"
CONTROLLER_CONFIG_FILE = os.path.join(SAM_BASE_PATH, "sam_controllers.json")
SAM_SESSION_NAME = "SAM"

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
rescan_lock = asyncio.Lock()


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
        self._stopping_since = 0
        self._log_activity = False 
        self._lock = threading.Lock() # A standard thread lock

    def update_activity(self, log_event=True):
        """Call this to reset the idle timer. Thread-safe."""
        with self._lock:
            self.last_activity = time.monotonic()
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
            if status:
                self._stopping_since = time.monotonic()
                print("MCP: State changed to 'stopping'. Ignoring new input.")
            else:
                print("MCP: State changed to 'idle'. Accepting new input.")

    def is_stopping(self) -> bool:
        """Check if we are in the process of stopping. Thread-safe."""
        with self._lock:
            if self._is_stopping:
                STOPPING_TIMEOUT = 30 # seconds
                if time.monotonic() - self._stopping_since > STOPPING_TIMEOUT:
                    print(f"MCP: WARNING: Stuck in 'stopping' state for over {STOPPING_TIMEOUT}s. Resetting lock.")
                    self._is_stopping = False
                    return False
                return True
            return False

# --- Core SAM Functions (from Script 1) ---
# These are blocking and will be run in threads

def is_sam_running():
    """Check if the SAM tmux session is active."""
    result = subprocess.run(
        ["tmux", "has-session", "-t", SAM_SESSION_NAME],
        capture_output=True
    )
    return result.returncode == 0

def start_sam():
    """Calls the main shell script to start SAM."""
    print("Idle timeout reached. Starting SAM...")
    # Popen is non-blocking, but the script it calls may run
    # Let's use 'run' to be cleaner
    subprocess.run([SAM_ON_SCRIPT, "start"])

async def exit_to_menu_with_retry(max_wait=15):
    """
    Attempts to load the menu core, retrying if MiSTer is busy.
    This prevents failures when a core is still loading.
    """
    print(f"Attempting to return to menu with a {max_wait}-second timeout...")
    
    # 1. Kill all SAM processes right away.
    print("MCP: Forcefully terminating SAM processes...")
    await asyncio.to_thread(subprocess.run, ["tmux", "kill-session", "-t", SAM_SESSION_NAME], capture_output=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Terminate SAM helper processes by iterating through /proc
    sam_proc_substrings = ['MiSTer_SAM_on.sh', 'MiSTer_SAM_tty2oled', 'bgm.sh']
    mcp_pid = os.getpid()
    try:
        for pid_str in os.listdir('/proc'):
            if not pid_str.isdigit():
                continue
            pid = int(pid_str)
            if pid == mcp_pid:
                continue
            try:
                with open(f'/proc/{pid}/cmdline', 'rb') as f:
                    cmdline = f.read().decode(errors='ignore')
                
                if any(substr in cmdline for substr in sam_proc_substrings):
                    print(f"MCP: Killing process {pid} ({cmdline.replace(chr(0), ' ')})")
                    os.kill(pid, signal.SIGKILL)
            except FileNotFoundError:
                # Process disappeared before we could read it
                continue
    except Exception as e:
        print(f"MCP: Error terminating processes via /proc: {e}")

    # 2. Try to load the menu core, with retries.
    menu_rbf_path = "/media/fat/menu.rbf"
    load_menu_command = f"load_core {menu_rbf_path}"
    for attempt in range(max_wait):
        in_menu = await asyncio.to_thread(is_in_menu)
        if in_menu:
            print("✅ SUCCESS: Menu core is now loaded.")
            
            # 3. Unmute the audio, with a timeout.
            print("MCP: Unmuting audio...")
            try:
                await asyncio.to_thread(subprocess.run, [SAM_ON_SCRIPT, "unmute"], timeout=10, check=True)
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
                print(f"MCP: WARNING: 'unmute' script failed or timed out: {e}")

            # 4. Run final exit cleanup, with a timeout.
            print("MCP: Running final cleanup tasks...")
            try:
                await asyncio.to_thread(subprocess.run, [SAM_ON_SCRIPT, "exit_to_menu"], timeout=10, check=True)
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
                print(f"MCP: WARNING: 'exit_to_menu' script failed or timed out: {e}")

            return

        print(f"Attempt {attempt + 1}/{max_wait}: Menu not loaded. Sending 'load_core' command...")
        cmd = ['timeout', '1', 'sh', '-c', f"echo '{load_menu_command}' > /dev/MiSTer_cmd"]
        await asyncio.to_thread(subprocess.run, cmd, capture_output=False)
        await asyncio.sleep(1)

    print(f"❌ FAILED: Timed out after {max_wait} seconds. Menu core did not load.")

async def stop_sam(play_current=False):
    """Stops SAM and all related services directly from Python."""
    # This function is now a wrapper that manages the 'stopping' state.
    try:
        print("User activity detected. Stopping SAM...")
        if play_current:
            print("User pressed 'Start'. Exiting to play current game...")
            # The shell script will handle all cleanup (BGM, TTY, unmute, etc.)
            await asyncio.to_thread(subprocess.run, [SAM_ON_SCRIPT, "exit_to_game"])
        else:
            # Use the new robust exit logic.
            await exit_to_menu_with_retry()
    except Exception as e:
        print(f"MCP: Error during stop_sam: {e}")
    finally:
        # IMPORTANT: Always reset the stopping flag, even if an error occurs.
        # We need to find the 'state' object. We can get it from the running loop's context
        # but a cleaner way is to pass it down. For now, let's assume we can get it.
        # A better refactor is needed, but this will work.
        pass # The flag is reset inside handle_action's do_actions

async def shutdown_mcp(loop):
    """Gracefully shuts down the entire MCP script."""
    print("MCP: Shutdown requested. Cleaning up all tasks...")
    for path, (task, stop_event) in list(tasks.items()):
        if stop_event:
            stop_event.set()
        if task and not task.done():
            task.cancel()
    # Give tasks a moment to cancel
    await asyncio.sleep(0.1)
    loop.stop()

def skip_game():
    """Sends a skip command to the running SAM session."""
    print("User pressed 'Next'. Skipping to next game...")
    subprocess.run(["tmux", "send-keys", "-t", SAM_SESSION_NAME, "C-c", "ENTER"])

def is_in_menu():
    """
    Check if the MiSTer process is currently running the menu.rbf core
    by inspecting /proc.
    """
    try:
        for pid in os.listdir('/proc'):
            if not pid.isdigit():
                continue
            try:
                with open(f'/proc/{pid}/cmdline', 'rb') as f:
                    cmdline_bytes = f.read()
                # cmdline is null-byte separated
                cmdline_args = [arg.decode() for arg in cmdline_bytes.split(b'\0') if arg]
                if cmdline_args and 'MiSTer' in cmdline_args[0] and '/media/fat/menu.rbf' in cmdline_args:
                    return True
            except (FileNotFoundError, IndexError):
                # Process may have disappeared, or cmdline is empty
                continue
        return False
    except Exception as e:
        print(f"MCP: Error checking for menu process via /proc: {e}")
        return False

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
            if button_num == button_map.get("select"): return "next"
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

def handle_action(action, state, loop):
    """Processes a joystick action string."""
    if not action:
        return

    # Always update activity to reset the idle timer, even if an action is already in progress.
    # This ensures the countdown always resets on input.
    state.update_activity()

    # If we are already in the process of stopping, ignore starting a new stop action.
    if state.is_stopping():
        return

    # Only proceed to the async actions if SAM is actually running.
    if state.is_sam_running():
        # This function is called from a thread, so we need to run async code
        # via the loop's call_soon_threadsafe method.
        async def do_actions():
            try:
                # Double-check the stopping flag inside the async context
                if state.is_stopping(): return

                state.set_stopping(True) # Set the lock
                print(f"MCP-JS: Action '{action}' detected while SAM is running.")
                if action == "start": await stop_sam(play_current=True)
                elif action == "next": await asyncio.to_thread(skip_game)
                elif action == "exit":
                    print("MCP: Exit action received. Shutting down MCP.")
                    await stop_sam(play_current=False)
                    await shutdown_mcp(loop)
                else: await stop_sam(play_current=False)
            finally:
                # IMPORTANT: Always release the lock when the action is complete.
                state.set_stopping(False)
        
        asyncio.run_coroutine_threadsafe(do_actions(), loop)

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
    sam_was_running = state.is_sam_running() # Track SAM's state to detect transitions

    while not stop_event.is_set():
        # Check if SAM has transitioned from running to stopped.
        # If so, reset the joystick's internal state to prevent "stuck" inputs.
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
                        loop.call_soon_threadsafe(handle_action, action, state, loop)
                
                previous_events = current_events
        except (BlockingIOError, FileNotFoundError):
            pass # This is expected on a non-blocking read with no data.
        except Exception as e:
            print(f"MCP-JS: Transient error in poller for {dev_path}: {e}")
            time.sleep(1)
        time.sleep(JOY_POLL_RATE)
    
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

async def watch_joystick_device(device_info, state, controller_config, loop):
    """Creates and registers a polling task for a single joystick device."""
    stop_event = threading.Event()
    task = asyncio.create_task(asyncio.to_thread(
        joystick_poller_thread, device_info, state, controller_config, loop, stop_event
    ))
    tasks[device_info['js_path']] = (task, stop_event)

async def watch_keyboard_device(device_path, state, loop):
    """Creates and registers a polling task for a keyboard hidraw device."""
    if not device_path:
        return
    stop_event = threading.Event()
    task = asyncio.create_task(asyncio.to_thread(
        keyboard_poller_thread, device_path, state, loop, stop_event
    ))
    tasks[device_path] = (task, stop_event)

async def watch_mouse_device(device_path, state, loop):
    """Creates and registers a polling task for a mouse device."""
    if not device_path:
        return
    stop_event = threading.Event()
    task = asyncio.create_task(asyncio.to_thread(
        mouse_poller_thread, device_path, state, loop, stop_event
    ))
    tasks[device_path] = (task, stop_event)

async def idle_and_status_checker(state):
    """Periodically checks idle time and SAM running status."""
    while True:
        try:
            # Run blocking I/O in a thread to not block the loop
            running = await asyncio.to_thread(is_sam_running)
            state.set_sam_running(running)

            if not state.is_sam_running():
                idle_time = state.get_idle_time()
                time_left = state.idle_timeout - idle_time

                # Run blocking file I/O in a thread
                in_menu = await asyncio.to_thread(is_in_menu)
                
                can_start = not state.menu_only or (state.menu_only and in_menu)

                if can_start and time_left > 0:
                    # Show the countdown for the entire duration.
                    line = f"MCP: Starting SAM in {int(time_left)} second(s)..."
                    print(line.ljust(50), end='\r') # Pad to clear previous line
                
                if can_start and idle_time > state.idle_timeout:
                    # Clear the countdown line before printing the next message
                    print(" " * 50, end='\r')
                    # Run blocking subprocess in a thread
                    await asyncio.to_thread(start_sam)
                    await asyncio.sleep(2) # Give it a moment to start
                    running_after_start = await asyncio.to_thread(is_sam_running)
                    state.set_sam_running(running_after_start)
                    state.update_activity(log_event=False) # Reset timer silently after starting

            # Check every second for a responsive countdown
            await asyncio.sleep(1)
        except Exception as e:
            print(f"MCP: Error in idle checker: {e}")
            await asyncio.sleep(5) # Wait a bit longer on error

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
    keyboards = []
    for d in all_devices:
        # A real keyboard has the 'is_keyboard' flag AND is not virtual
        if d.get('is_keyboard') and 'virtual' not in d.get('sysfs', ''):
            
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

async def rescan_devices(state, controller_config, loop):
    """Scans all devices and starts/stops monitors as needed."""
    # Use a lock to ensure only one rescan happens at a time.
    async with rescan_lock:
        await _rescan_devices_impl(state, controller_config, loop)

async def _rescan_devices_impl(state, controller_config, loop):
    print("MCP: Rescanning all input devices...")
    try:
        all_current_devices = await asyncio.to_thread(get_input_devices)
        
        # --- Build sets of current and monitored devices ---
        current_js = {d['js_path'] for d in all_current_devices['joysticks']}
        current_kbds = {d['hidraw_path'] for d in all_current_devices['keyboards']}
        current_mouse = {"/dev/input/mice"} if os.path.exists("/dev/input/mice") else set()
        
        all_current_devs = current_js.union(current_kbds).union(current_mouse)
        all_monitored_devs = {path for path in tasks if path.startswith('/dev/input/')}

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

async def hotplug_monitor_native(state, controller_config, loop):
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

    while True:
        try:
            # Asynchronously read a line of output from inotifywait
            line = await process.stdout.readline()
            if not line:
                print("MCP: inotifywait process exited. Hotplug monitor stopping.")
                break # Process has exited
            
            decoded_line = line.decode().strip()
            
            # Only react to events related to physical device symlinks.
            if '/dev/input/by-path/' in decoded_line:
                # A physical device change was detected. Trigger a debounced rescan.
                if debounce_timer:
                    debounce_timer.cancel()
                
                debounce_timer = loop.call_later(debounce_delay, lambda: asyncio.create_task(rescan_devices(state, controller_config, loop)))

        except asyncio.CancelledError:
            print("MCP: Hot-plug monitor cancelled.")
            process.terminate()
            await process.wait()
            break
        except Exception as e:
            print(f"MCP: Error in hotplug monitor: {e}")
            await asyncio.sleep(5) # Wait before retrying

def shutdown(loop):
    print("MCP: Shutting down...")
    # This function can be called from a signal handler, so we use thread-safe calls.
    for path, (task, stop_event) in tasks.items():
        if stop_event:
            # This is a joystick poller thread, signal it to stop
            stop_event.set() 
        if task:
            loop.call_soon_threadsafe(task.cancel)
def signal_handler(loop):
    """A thread-safe signal handler to stop the event loop."""
    print("\nMCP: Signal received, initiating shutdown.")
    asyncio.run_coroutine_threadsafe(shutdown_mcp(loop), loop)
    loop.call_soon_threadsafe(loop.stop)

async def main():
    # 1. Read configuration (same as your script)
    config = configparser.ConfigParser(inline_comment_prefixes=('#', ';'))
    try:
        with open(INI_FILE, 'r') as f:
            ini_content = f.read()
        config.read_string("[DEFAULT]\n" + ini_content)
        
        menu_only_raw = config.get("DEFAULT", "menuonly", fallback="yes")
        menu_only = menu_only_raw.strip('"\'').lower() in ['yes', 'true', '1', 'on']
        timeout = config.getint("DEFAULT", "samtimeout", fallback=60)
    except Exception as e:
        print(f"MCP: Warning - Could not read or parse INI file: {e}")
        print("MCP: Using default values for timeout (60s) and menu_only (True).")
        timeout = 60
        menu_only = True

    # Load controller configuration
    controller_config = {}
    try:
        with open(os.path.join(SCRIPT_DIR, "sam_controllers.json"), 'r') as f:
            controller_config = json.load(f)
        print("MCP: Successfully loaded controller configuration.")
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"MCP: Warning - Could not load or parse controller config: {e}")

    # 2. Initialize state
    state = SamState(timeout=timeout, menu_only=menu_only)
    print(f"MCP started. Idle timeout: {state.idle_timeout}s, Menu-only: {state.menu_only}")

    # 3. Setup asyncio tasks
    tasks['checker'] = (asyncio.create_task(idle_and_status_checker(state)), None)

    loop = asyncio.get_running_loop()

    # 4. Initial scan for existing devices and start monitoring them
    # The new rescan function handles the initial scan perfectly.
    await rescan_devices(state, controller_config, loop)

    # 5. Start the hot-plug monitor task
    tasks['hotplug'] = (asyncio.create_task(hotplug_monitor_native(state, controller_config, loop)), None)

    # 6. Setup signal handlers for graceful shutdown
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, shutdown, loop)
        loop.add_signal_handler(sig, signal_handler, loop)

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
