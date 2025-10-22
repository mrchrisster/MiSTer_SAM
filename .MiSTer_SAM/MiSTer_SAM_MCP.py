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
POLL_RATE = 0.1
JOY_POLL_RATE = 0.02 # 50 times per second for responsiveness
AXIS_DEADZONE = 2000
BUTTON_TYPE = 0x01
AXIS_TYPE = 0x02
# 0x80 is INIT event, we can filter for button/axis
JS_EVENT_TYPES = BUTTON_TYPE | AXIS_TYPE

tasks = {}


class SamState:
    """
    A thread-safe class to hold the state of our monitor.
    """
    def __init__(self, timeout=120, menu_only=True):
        self.last_activity = time.monotonic()
        self.idle_timeout = timeout
        self.menu_only = menu_only
        self._sam_is_running = False
        self._lock = threading.Lock() # A standard thread lock

    def update_activity(self):
        """Call this to reset the idle timer. Thread-safe."""
        with self._lock:
            self.last_activity = time.monotonic()
        print("MCP: Activity detected, idle timer reset.")

    def get_idle_time(self):
        """Returns the current number of idle seconds. Thread-safe."""
        with self._lock:
            return time.monotonic() - self.last_activity

    def set_sam_running(self, status: bool):
        """Set the running status. Thread-safe."""
        with self._lock:
            self._sam_is_running = status
    
    def is_sam_running(self) -> bool:
        """Get the running status. Thread-safe."""
        with self._lock:
            return self._sam_is_running

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

def stop_sam(play_current=False):
    """Calls the main shell script to stop SAM."""
    if play_current:
        print("User pressed 'Start'. Exiting to play current game...")
        command = "playcurrent"
    else:
        print("User activity detected. Stopping SAM and returning to menu...")
        command = "stop"
    # Popen is non-blocking, which is fine
    subprocess.Popen([SAM_ON_SCRIPT, command])

def skip_game():
    """Sends a skip command to the running SAM session."""
    print("User pressed 'Next'. Skipping to next game...")
    subprocess.Popen(["tmux", "send-keys", "-t", SAM_SESSION_NAME, "C-c", "ENTER"])

def is_in_menu():
    """Check if the current core is the Menu."""
    try:
        with open("/tmp/CORENAME", "r") as f:
            return "MENU" in f.read()
    except FileNotFoundError:
        return False

# --- Joystick Polling Logic (from Script 2, adapted) ---

def get_js_activity(
    prev: list[dict[str, int]], next: list[dict[str, int]], controller_config
) -> str:
    """
    Compares two js state lists (as per original joy script) 
    and returns an action string or None.
    """
    if len(prev) != len(next):
        return None

    button_map = controller_config.get("button", {})
    axis_map = controller_config.get("axis", {})

    # This simplified logic just checks for any significant event change
    for prev_event, next_event in zip(prev, next):
        is_button = next_event["type"] & BUTTON_TYPE
        is_axis = next_event["type"] & AXIS_TYPE

        if is_button and prev_event["value"] != next_event["value"] and next_event["value"] == 1:
            button_num = next_event["number"]
            if button_num == button_map.get("start"): return "start"
            if button_num == button_map.get("next"): return "next"
            return "default"

        if is_axis and abs(prev_event["value"] - next_event["value"]) > AXIS_DEADZONE:
            axis_num = next_event["number"]
            axis_val = next_event["value"]
            next_config = axis_map.get("next", {})
            if axis_num == next_config.get("code") and axis_val == next_config.get("value"):
                return "next"
            return "default"

    return None

def handle_action(action, state):
    """Processes a joystick action string."""
    if not action:
        return

    state.update_activity()

    if state.is_sam_running():
        if action == "start":
            stop_sam(play_current=True)
        elif action == "next":
            skip_game()
        elif action == "default":
            stop_sam(play_current=False)

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

    while not stop_event.is_set():
        try:
            with open(dev_path, "rb") as f:
                os.set_blocking(f.fileno(), False)
                data = f.read(512)

            if data:
                current_events = [dict(zip(("timestamp", "value", "type", "number"), struct.unpack(JS_EVENT_FORMAT, data[i:i+JS_EVENT_SIZE]))) for i in range(0, len(data), JS_EVENT_SIZE) if len(data[i:i+JS_EVENT_SIZE]) == JS_EVENT_SIZE]
                
                # On the very first read, just establish the baseline state.
                if not previous_events:
                    previous_events = current_events
                    state.update_activity() # Register activity on plug-in
                    print(f"MCP-JS: Initial state captured for {dev_path}. Listening for changes...")
                else:
                    action = get_js_activity(previous_events, current_events, device_config)
                    if action:
                        # Use call_soon_threadsafe to safely call the async function from this thread
                        loop.call_soon_threadsafe(handle_action, action, state)
                
                previous_events = current_events
        except (BlockingIOError, FileNotFoundError):
            pass # Expected behavior
        except Exception as e:
            print(f"MCP-JS: Error in poller for {dev_path}: {e}")
            break
        time.sleep(JOY_POLL_RATE)
    
    print(f"MCP-JS: Poller for {dev_path} stopped.")

async def watch_joystick_device(device_info, state, controller_config, loop):
    stop_event = threading.Event()
    tasks[device_info['js_path']] = (asyncio.create_task(asyncio.to_thread(
        joystick_poller_thread, device_info, state, controller_config, loop, stop_event
    )), stop_event)
    
    try:
        task, _ = tasks[device_info['js_path']]
        await task
    except asyncio.CancelledError:
        print(f"MCP-JS: Watcher for {device_info['js_path']} cancelled.")
        stop_event.set()

async def idle_and_status_checker(state):
    """Periodically checks idle time and SAM running status."""
    while True:
        # Run blocking I/O in a thread to not block the loop
        running = await asyncio.to_thread(is_sam_running)
        state.set_sam_running(running)

        if not state.is_sam_running():
            idle_time = state.get_idle_time()

            # Run blocking file I/O in a thread
            in_menu = await asyncio.to_thread(is_in_menu)
            
            should_start = (
                idle_time > state.idle_timeout and
                (not state.menu_only or (state.menu_only and in_menu))
            )

            if should_start:
                # Run blocking subprocess in a thread
                await asyncio.to_thread(start_sam)
                await asyncio.sleep(2) # Give it a moment to start
                running_after_start = await asyncio.to_thread(is_sam_running)
                state.set_sam_running(running_after_start)
                state.update_activity() # Reset timer after starting

        await asyncio.sleep(5) # Check every 5 seconds

def get_input_devices():
    """
    Scans /proc/bus/input/devices to find jsX handlers and their IDs.
    """
    devices = []
    current_device = {}
    with open('/proc/bus/input/devices', 'r') as f:
        for line in f:
            line = line.strip()
            if line == '':
                # Add device only if it has a js_path and an ID
                # AND is not a motion sensor or a Zaparoo device.
                is_motion_sensor = "motion sensors" in current_device.get('name', '').lower()
                is_zaparoo = "zaparoo" in current_device.get('name', '').lower()
                if 'js_path' in current_device and 'id' in current_device and not is_motion_sensor and not is_zaparoo:
                    devices.append(current_device)
                current_device = {}
                continue

            key, value = line.split('=', 1)
            key = key.strip()
            if line.startswith('N: Name='):
                current_device['name'] = value.strip('"')
            elif line.startswith('I: Bus='):
                parts = {p.split('=')[0]: p.split('=')[1] for p in line.split()[1:]}
                bus = int(parts.get('Bus', '0'), 16)
                vendor = int(parts.get('Vendor', '0'), 16)
                product = int(parts.get('Product', '0'), 16)
                current_device['id'] = f"{vendor:04x}_{product:04x}"
            elif line.startswith('H: Handlers='):
                handlers = value.split()
                for handler in handlers:
                    if handler.startswith('js'):
                        current_device['js_path'] = f"/dev/input/{handler}"
                        break # Found what we need
                        
    if 'js_path' in current_device and 'id' in current_device: # Add the last device
        devices.append(current_device)

    # Process the last device in the file if it exists
    if 'js_path' in current_device and 'id' in current_device and not is_motion_sensor and not is_zaparoo:
        devices.append(current_device)

    return devices

async def hotplug_monitor(state, controller_config, loop):
    """Periodically scans for new or removed devices."""
    while True:
        try:
            # Run blocking scan in a thread
            current_devices_list = await asyncio.to_thread(get_input_devices)
            current_devices = {d['js_path']: d for d in current_devices_list}
            monitored_devices = {path for path in tasks if path.startswith('/dev/input/js')}

            added_paths = set(current_devices.keys()) - monitored_devices
            removed_paths = monitored_devices - set(current_devices.keys())

            for dev_path in added_paths:
                print(f"MCP: Hot-plug ADDED: {dev_path}")
                device_info = current_devices[dev_path]
                if device_info:
                    # This will create the task and add it to the tasks dict
                    await watch_joystick_device(device_info, state, controller_config, loop)

            for dev_path in removed_paths:
                print(f"MCP: Hot-plug REMOVED: {dev_path}")
                if dev_path in tasks:
                    task, stop_event = tasks[dev_path]
                    stop_event.set() # 1. Tell thread to stop
                    task.cancel()    # 2. Cancel the asyncio wrapper
                    try:
                        await task # Wait for it to clean up
                    except asyncio.CancelledError:
                        pass # Expected
                    del tasks[dev_path]
        
        except Exception as e:
            print(f"MCP: Error in hotplug monitor: {e}")

        await asyncio.sleep(10) # Scan for changes every 10 seconds

async def shutdown(loop):
    print("MCP: Shutting down...")
    for task, stop_event in tasks.values():
        task.cancel()
        if stop_event:
            stop_event.set()
    await asyncio.gather(*[t for t, e in tasks.values()], return_exceptions=True)
    loop.stop()

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
    tasks['checker'] = asyncio.create_task(idle_and_status_checker(state))

    loop = asyncio.get_running_loop()

    # 4. Initial scan for existing devices and start monitoring them
    all_devices = await asyncio.to_thread(get_input_devices) # Run in thread
    print(f"MCP: Found {len(all_devices)} joystick device(s).")
    for device in all_devices:
        await watch_joystick_device(device, state, controller_config, loop)

    # 5. Start the hot-plug monitor task
    tasks['hotplug'] = asyncio.create_task(hotplug_monitor(state, controller_config, loop))
    print("MCP: Hot-plug monitor started (polling).")

    # 6. Setup signal handlers for graceful shutdown
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(shutdown(loop)))

    # 6. Run all tasks until completion
    try:
        await asyncio.gather(*[t for t, e in tasks.values()])
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
