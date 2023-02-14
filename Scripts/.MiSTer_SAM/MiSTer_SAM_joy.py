#!/usr/bin/env python

import struct
import time
import sys
import os
import json


ACTIVITY_FILE = "/tmp/.SAM_Joy_Activity"
POLL_RATE = 0.2
AXIS_DEADZONE = 2000

# these values will be written to the activity file
ACTIVITIES = {"start": "Start", "default": "Button pushed"}
# each key in the button/axis sections should match back to an activity key
with open("controllers.json", "r") as f:
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
) -> str:
    if len(prev) != len(next):
        return

    activity = None

    # this doesn't handle multiple activities in a single check
    # in practice it shouldn't really matter
    for i in range(len(prev)):
        pe = prev[i]
        np = next[i]
        event_type = None

        if pe["type"] & BUTTON == BUTTON:
            # button depresses count as an activity currently
            if pe["value"] != np["value"]:
                if "start" in ARGS:
                    print(format(pe["number"]))
                    sys.exit(1)
                event_type = "button"
                activity = ACTIVITIES["default"]
                break
        elif pe["type"] & AXIS == AXIS:
            if abs(pe["value"] - np["value"]) > AXIS_DEADZONE:
                event_type = "axis"
                activity = ACTIVITIES["default"]
                break

    if event_type and device_id in CONTROLLERS:
        controller = CONTROLLERS[device_id]
        for k, v in controller[event_type].items():
            if v == np["number"]:
                activity = ACTIVITIES[k]
                break

    return activity


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
        print("Usage: {} /dev/input/jsX".format(sys.argv[0]))
        sys.exit(1)

    events = []
    device_id = None
    try:
        events = read_state(sys.argv[1])
        device_id = get_device_id(sys.argv[1])
        if "id" in ARGS:
            print(format(device_id))
            sys.exit(1)
            
    except FileNotFoundError:
        print("Joystick does not exist: {}".format(sys.argv[1]))
        sys.exit(1)

    while True:
        try:
            next_events = read_state(sys.argv[1])
        except FileNotFoundError:
            print("Joystick disconnected: {}".format(sys.argv[1]))
            sys.exit(1)

        activity = get_activity(events, next_events, device_id)
        if activity:
            with open(ACTIVITY_FILE, "w") as f:
                f.write(activity)

        events = next_events
        time.sleep(POLL_RATE)
