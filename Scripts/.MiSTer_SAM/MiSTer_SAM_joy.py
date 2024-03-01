#!/usr/bin/env python

import struct
import time
import sys
import os
import json


ACTIVITY_FILE = "/tmp/.SAM_tmp/SAM_Joy_Activity"
POLL_RATE = 0.1
AXIS_DEADZONE = 2000

script_path = os.path.abspath(__file__)
json_file_path = os.path.join(os.path.dirname(script_path), "sam_controllers.json")

# these values will be written to the activity file
ACTIVITIES = {"start": "Start", "default": "Button pushed", "next": "Next"}
# each key in the button/axis sections should match back to an activity key
with open(json_file_path, "r") as f:
    CONTROLLERS = json.load(f)

BUTTON = 0x01
AXIS = 0x02
INIT = 0x80
ARGS = sys.argv[1:] 


def read_event(buf: list[bytes]) -> dict[str, int]:
    timestamp, value, type_, number = struct.unpack("IhBB", buf)
    return {
        "timestamp": timestamp,
        "value": value,
        "type": type_,
        "number": number,
    }


def read_state(dev_path: str) -> list[dict[str, int]]:
    events = []
    with open(dev_path, "rb") as f:
        os.set_blocking(f.fileno(), False)
        # better to calculate the size but this works up to a 64 button joystick
        buf = f.read(512)
        for i in range(0, len(buf), 8):
            events.append(read_event(buf[i : i + 8]))
    return events


def get_activity(
    prev: list[dict[str, int]], next: list[dict[str, int]], device_id: str = None
) -> tuple[str, str]:
    if len(prev) != len(next):
        return None, None

    activity = None
    action = None
    global CONTROLLERS  # Assuming CONTROLLERS is defined globally

    # Use the specific controller config if available, otherwise fall back to default
    controller_config = CONTROLLERS.get(device_id, CONTROLLERS["default"])

    for i in range(len(prev)):
        pe = prev[i]
        np = next[i]

        # Handle button events
        if pe["type"] & BUTTON == BUTTON and pe["value"] != np["value"]:
            if "button" in ARGS:
                print(format(pe["number"]))
                sys.exit(0)  # Exit after printing the device ID
   
            # Set to default initially
            activity = ACTIVITIES["default"]
            action = "default"
            # Iterate through the button mappings in the controller_config
            for activity_key, button_number in controller_config["button"].items():
                if np["number"] == button_number:
                    activity = ACTIVITIES.get(activity_key)
                    action = activity_key
                    break  # Break if a specific activity is found

        # Handle axis events
        elif pe["type"] & AXIS == AXIS and abs(pe["value"] - np["value"]) > AXIS_DEADZONE:
            # Set to default initially for axis movement
            activity = ACTIVITIES["default"]
            action = "default"
            # Check if there are specific mappings for axis in the controller_config
            if "axis" in controller_config:
                for activity_key, axis_number in controller_config["axis"].items():
                    if np["number"] == axis_number:
                        activity = ACTIVITIES.get(activity_key, "Axis movement")
                        action = activity_key
                        break  # Break if a specific activity is found

    return activity, action

def get_device_id(dev_path: str) -> str:
    i = None
    device_id = None
    dev_file = os.path.basename(dev_path)

    with open("/proc/bus/input/devices", "r") as f:
        for line in f.readlines():
            if line.startswith("I:"):
                i = line
            elif line.startswith("H:"):
                if dev_file in line:
                    break

    if i:
        vendor = None
        product = None
        for part in i.split():
            if part.startswith("Vendor"):
                vendor = part.split("=")[1]
            elif part.startswith("Product"):
                product = part.split("=")[1]
        if vendor and product:
            device_id = "{}_{}".format(vendor, product)

    return device_id


if __name__ == "__main__":
    if len(sys.argv) <= 1:
        print(f"Usage: {sys.argv[0]} /dev/input/jsX [--id]")
        sys.exit(1)

    dev_path = sys.argv[1]
    ARGS = sys.argv[2:]  # Capture additional arguments beyond the device path

    # Attempt to read the device state and get the device ID
    try:
        events = read_state(dev_path)
        device_id = get_device_id(dev_path)
    except FileNotFoundError:
        print(f"Joystick does not exist: {dev_path}")
        sys.exit(1)

    # Check if the "id" argument is provided and print the device ID if so
    if "id" in ARGS:
        print(device_id)
        sys.exit(0)  # Exit after printing the device ID

     
    # Your existing activity monitoring loop here...
    while True:
        try:
            next_events = read_state(dev_path)
        except FileNotFoundError:
            print(f"Joystick disconnected: {dev_path}")
            sys.exit(1)

        activity, action = get_activity(events, next_events, device_id)
        if activity:
                # This includes handling for axis movements or other button activities
                with open(ACTIVITY_FILE, "w") as f:
                    f.write(activity)
                print(f"Activity '{activity}' triggered. Written to file.")

        events = next_events
        time.sleep(POLL_RATE)
