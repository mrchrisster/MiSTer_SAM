#!/usr/bin/env python3
import asyncio
import configparser
import os
import subprocess
import struct
import time
import json
import threading # We need threading

# --- Configuration (from Script 1) ---
SAM_BASE_PATH = "/media/fat/Scripts/.MiSTer_SAM"
SAM_ON_SCRIPT = "/media/fat/Scripts/MiSTer_SAM_on.sh"
INI_FILE = "/media/fat/Scripts/MiSTer_SAM.ini"
CONTROLLER_CONFIG_FILE = os.path.join(SAM_BASE_PATH, "sam_controllers.json")
SAM_SESSION_NAME = "SAM"

# --- Constants for jsX Polling (from Script 2) ---
JS_EVENT_FORMAT = "IhBB" # timestamp, value, type, number
JS_EVENT_SIZE = struct.calcsize(JS_EVENT_FORMAT)
POLL_RATE = 0.1
AXIS_DEADZONE = 2000
BUTTON_TYPE = 0x01
AXIS_TYPE = 0x02
# 0x80 is INIT event, we can filter for button/axis
JS_EVENT_TYPES = BUTTON_TYPE | AXIS_TYPE


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

def read_js_event(buf: list[bytes]) -> dict[str, int]:
    """Parses a js_event struct."""
    timestamp, value, type_, number = struct.unpack(JS_EVENT_FORMAT, buf)
    return {
        "timestamp": timestamp,
        "value": value,
        "type": type_,
        "number": number,
    }

def read_js_state(dev_path: str) -> list[dict[str, int]]:
    """Reads a fixed-size chunk from a jsX device, based on original joy script."""
    events = []
    try:
        with open(dev_path, "rb") as f:
            os.set_blocking(f.fileno(), False)
            # Read a fixed-size buffer, assuming a complete state report.
            buf = f.read(512)
            # Parse the buffer into 8-byte event chunks.
            for i in range(0, len(buf), JS_EVENT_SIZE):
                event_buf = buf[i : i + JS_EVENT_SIZE]
                if len(event_buf) == JS_EVENT_SIZE:
                    event = read_js_event(event_buf)
                    # We only care about button or axis events, ignore others.
                    if event["type"] & JS_EVENT_TYPES:
                         events.append(event)
    except (FileNotFoundError, BlockingIOError):
        # Ignore errors if device is disconnected or not ready
        pass
    return events


def get_js_activity(
    prev: list[dict[str, int]], next: list[dict[str, int]], controller_config
) -> str:
    """
    Compares two js state lists (as per original joy script) 
    and returns an action string or None.
    """
    if len(prev) != len(next):
        # This logic is from the original joy script. It assumes a fixed-size state report.
        return None

    button_map = controller_config.get("button", {})
    axis_map = controller_config.get("axis", {})

    for i in range(len(prev)):
        pe = prev[i]
        ne = next[i]

        # Handle button events based on value change
        if (pe["type"] & BUTTON_TYPE) and pe["value"] != ne["value"]:
            # We only care about "press down" (value 1)
            if ne["value"] == 1:
                if ne["number"] == button_map.get("start"):
                    return "start"
                elif ne["number"] == button_map.get("next"):
                    return "next"
                else:
                    return "default"  # Any other button press

        # Handle axis events based on value change
        elif (pe["type"] & AXIS_TYPE) and abs(pe["value"] - ne["value"]) > AXIS_DEADZONE:
            # A significant change in axis value occurred.
            # Check if the new position corresponds to a "next" command.
            if "next" in axis_map:
                axis_config = axis_map["next"]
                if ne["number"] == axis_config.get("code") and ne["value"] == axis_config.get("value"):
                    return "next"
            
            # Any other significant axis movement is a default action
            return "default"

    return None

def poll_joystick_blocking(device_info, state, controller_config, stop_event):
    """
    A BLOCKING function that polls a single jsX device.
    This is intended to be run in a separate thread.
    """
    dev_path = device_info['js_path']
    device_id = device_info.get('id', 'default')
    
    device_config = controller_config.get(device_id, controller_config.get("default", {}))

    print(f"MCP-JS: Polling device: {device_info.get('name', 'Unknown')} ({dev_path})")
    
    try:
        # Get initial state.
        prev_events = read_js_state(dev_path)
        state.update_activity() # Register activity on plug-in

        while not stop_event.is_set():
            try:
                # Read all new events since last poll
                new_events = read_js_state(dev_path)
            except (FileNotFoundError, IOError):
                print(f"MCP-JS: Device {dev_path} disconnected.")
                break # Exit thread
                
            if new_events: # Only process if we read something
                action = get_js_activity(prev_events, new_events, device_config)

                if action:
                    # 1. Always update the idle timer
                    state.update_activity()

                    # 2. Check state and perform actions (this is thread-safe)
                    if state.is_sam_running(): 
                        if action == "start":
                            stop_sam(play_current=True)
                        elif action == "next":
                            skip_game()
                        elif action == "default":
                            stop_sam(play_current=False)
                
                prev_events = new_events # Update state for next poll

            # Use event.wait() for a sleep that can be interrupted
            stop_event.wait(POLL_RATE)

    except Exception as e:
        if not stop_event.is_set():
            print(f"MCP-JS: An error occurred with {dev_path}: {e}")
    finally:
        print(f"MCP-JS: Stopping poll for {dev_path}")


# --- Async Task Functions (Modified for Threading) ---

async def watch_joystick_device(device_info, state, controller_config, stop_event):
    """
    Asynchronously monitors a jsX device by running
    the blocking poll function in a separate thread.
    """
    try:
        # This will run the blocking function in asyncio's default thread pool
        await asyncio.to_thread(
            poll_joystick_blocking, 
            device_info, 
            state, 
            controller_config, 
            stop_event
        )
    except asyncio.CancelledError:
        print(f"MCP-JS: Watcher for {device_info['js_path']} cancelled.")
        # The stop_event should have already been set by the monitor
        raise

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

            if line.startswith('N: Name='):
                current_device['name'] = line.split('=', 1)[1].strip('"')
            elif line.startswith('I: Bus='):
                parts = {p.split('=')[0]: p.split('=')[1] for p in line.split()[1:]}
                bus = int(parts.get('Bus', '0'), 16)
                vendor = int(parts.get('Vendor', '0'), 16)
                product = int(parts.get('Product', '0'), 16)
                current_device['id'] = f"{bus:04x}:{vendor:04x}:{product:04x}"
            elif line.startswith('H: Handlers='):
                handlers = line.split('=', 1)[1].split()
                for handler in handlers:
                    if handler.startswith('js'):
                        current_device['js_path'] = f"/dev/input/{handler}"
                        break # Found what we need
                        
    if 'js_path' in current_device and 'id' in current_device: # Add the last device
        devices.append(current_device)
        
    return devices

async def hotplug_monitor(tasks, state, controller_config):
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
                    stop_event = threading.Event() # Create the event
                    task = asyncio.create_task(
                        watch_joystick_device(device_info, state, controller_config, stop_event)
                    )
                    tasks[dev_path] = (task, stop_event) # Store tuple

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
        with open(CONTROLLER_CONFIG_FILE, 'r') as f:
            controller_config = json.load(f)
        print("MCP: Successfully loaded controller configuration.")
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"MCP: Warning - Could not load or parse controller config: {e}")

    # 2. Initialize state
    state = SamState(timeout=timeout, menu_only=menu_only)
    print(f"MCP started. Idle timeout: {state.idle_timeout}s, Menu-only: {state.menu_only}")

    # 3. Setup asyncio tasks
    # Tasks dict now holds (task, stop_event) tuples
    tasks = {
        'checker': (asyncio.create_task(idle_and_status_checker(state)), None)
    }

    # 4. Initial scan for existing devices and start monitoring them
    all_devices = await asyncio.to_thread(get_input_devices) # Run in thread
    print(f"MCP: Found {len(all_devices)} joystick device(s).")
    for device in all_devices:
        stop_event = threading.Event()
        task = asyncio.create_task(
            watch_joystick_device(device, state, controller_config, stop_event)
        )
        tasks[device['js_path']] = (task, stop_event)

    # 5. Start the hot-plug monitor task
    tasks['hotplug'] = (asyncio.create_task(hotplug_monitor(tasks, state, controller_config)), None)
    print("MCP: Hot-plug monitor started (polling).")

    # 6. Run all tasks until completion
    try:
        await asyncio.gather(*[task for task, event in tasks.values()])
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