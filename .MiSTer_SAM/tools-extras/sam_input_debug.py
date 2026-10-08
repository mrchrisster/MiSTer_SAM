#!/usr/bin/env python3
"""Read-only comparison of SAM js snapshots, evdev state and MiSTer v3 maps.

Python standard library only. No grabs, injected input, configuration writes,
SAM commands or MiSTer commands. The only file written is the diagnostic log.
"""

import argparse
import collections
import datetime
import fcntl
import glob
import json
import os
import platform
import re
import struct
import sys
import time

JS_EVENT = struct.Struct("=IhBB")
INPUT_EVENT = struct.Struct("@llHHi")  # 16 bytes on MiSTer's 32-bit ARM
KEY_BYTES = 96  # KEY_CNT=768
KEY_EMU = 0x300
SLOTS = ["Right", "Left", "Down", "Up", "A", "B", "X", "Y", "L", "R", "Select", "Start"]
DB_CONTROLS = set("a b x y back start guide guide2 menuok menuesc leftshoulder rightshoulder leftstick rightstick lefttrigger righttrigger leftx lefty rightx righty asysx asysy dpup dpdown dpleft dpright misc1 paddle1 paddle2 paddle3 paddle4 touchpad".split())
NAMES = {1: "KEY_ESC", 28: "KEY_ENTER", 57: "KEY_SPACE", 88: "KEY_F12",
         103: "KEY_UP", 105: "KEY_LEFT", 106: "KEY_RIGHT", 108: "KEY_DOWN",
         304: "BTN_SOUTH", 305: "BTN_EAST", 307: "BTN_NORTH", 308: "BTN_WEST",
         310: "BTN_TL", 311: "BTN_TR", 312: "BTN_TL2", 313: "BTN_TR2",
         314: "BTN_SELECT", 315: "BTN_START", 316: "BTN_MODE",
         317: "BTN_THUMBL", 318: "BTN_THUMBR", 544: "BTN_DPAD_UP",
         545: "BTN_DPAD_DOWN", 546: "BTN_DPAD_LEFT", 547: "BTN_DPAD_RIGHT"}


def ior(kind, number, size):
    """Linux generic/ARM _IOC(_IOC_READ, type, number, size)."""
    return (2 << 30) | (size << 16) | (ord(kind) << 8) | number


def ioctl_bytes(fd, request, size):
    data = bytearray(size)
    fcntl.ioctl(fd, request, data, True)
    return bytes(data)


def bit_codes(data):
    return {i for i in range(len(data) * 8) if data[i // 8] & (1 << (i % 8))}


def parse_proc_devices(text):
    devices = []
    for block in text.strip().split("\n\n"):
        ids = re.search(r"Vendor=([0-9a-fA-F]+) Product=([0-9a-fA-F]+)", block)
        handlers = re.search(r"^H: Handlers=(.*)$", block, re.M)
        if not ids or not handlers:
            continue
        d = {"id": "%04x_%04x" % tuple(int(v, 16) for v in ids.groups()),
             "handlers": handlers.group(1).split()}
        for prefix, key in [("N: Name=", "name"), ("P: Phys=", "phys"), ("U: Uniq=", "uniq"), ("S: Sysfs=", "sysfs")]:
            line = next((s[len(prefix):] for s in block.splitlines() if s.startswith(prefix)), "")
            d[key] = line.strip('"')
        for prefix, key in [("js", "js"), ("event", "event")]:
            handler = next((h for h in d["handlers"] if re.fullmatch(prefix + r"\d+", h)), None)
            d[key] = "/dev/input/" + handler if handler else None
        devices.append(d)
    return devices


def read_devices():
    with open("/proc/bus/input/devices") as f:
        return parse_proc_devices(f.read())


def select_devices(devices, paths):
    if not paths:
        return [d for d in devices if d["js"]]
    return [d for d in devices if d["js"] in paths or d["event"] in paths]


def device_identity(device):
    # inputN in sysfs changes when a disconnected node number is reused, even
    # for another unit of the same model on the same USB port.
    return tuple(device.get(k, "") for k in ("id", "name", "phys", "uniq", "sysfs", "js", "event"))


def decode_map(data):
    if len(data) != 128:
        raise ValueError("expected 128 bytes (32 little-endian uint32 entries), got %d" % len(data))
    return struct.unpack("<32I", data)


def map_paths(config_dir, device_id):
    name = "input_" + device_id + "_v3.map"
    return [os.path.join(config_dir, "inputs", name), os.path.join(config_dir, name)]


def code_text(code):
    if not code:
        return "unassigned"
    if code >= 0x10000:
        return "wide/flagged value; NOT truncated to 16 bits"
    if code >= KEY_EMU:
        axis = (code - KEY_EMU) // 2
        return "axis %d %s (synthetic edge)" % (axis, "+" if code & 1 else "-")
    return NAMES.get(code, "KEY_%d" % code if code < 256 else "BTN_%d" % code)


def labels(code, mapping):
    if mapping is None:
        return "map unavailable"
    found = [name for name, value in zip(SLOTS, mapping) if value == code and code]
    found += ["Menu%d" % (i - 20) for i in (21, 22) if mapping[i] == code and code]
    return "+".join(found) or "unmapped"


def decode_js(data):
    if len(data) % JS_EVENT.size:
        raise ValueError("js read returned a partial record: %d bytes" % len(data))
    records = [JS_EVENT.unpack_from(data, i) for i in range(0, len(data), JS_EVENT.size)]
    # Keep INIT separately: this is the snapshot SAM relies on. Later queued
    # events must not silently replace it or disturb positional comparisons.
    snapshot = {(kind & 0x7f, number): value for _, value, kind, number in records if kind & 0x80}
    return records, snapshot


def changed_values(previous, current):
    return [(key, previous[key], current[key]) for key in sorted(previous.keys() & current.keys())
            if previous[key] != current[key]]


def abs_log_threshold(info, requested):
    # Hats often have range [-1,1]; an analog threshold of 2000 would hide them.
    return min(requested, max(1, (info[2] - info[1]) // 4))


def controller_guid(identity):
    # Main's GUID: four little-endian uint16 IDs, each padded to four bytes.
    return b"".join(struct.pack("<H", value) + b"\0\0" for value in identity).hex()


def db_binding(text, key_caps, abs_codes):
    """Return (kind, Linux code, axis half, inverted), using Main enumeration.

    DB bN is not a joydev number. Axes below ABS_HAT0X form Main's aN list;
    hats refer directly to ABS_HAT0X + 2*N. No input thresholds are inferred.
    """
    buttons = sorted(c for c in key_caps if c >= 0x120) + sorted(c for c in key_caps if c < 0x120)
    axes = sorted(c for c in abs_codes if c < 16)
    match = re.fullmatch(r"b(\d+)", text)
    if match:
        index = int(match[1])
        if index < len(buttons):
            return ("button", buttons[index], "", False)
        raise ValueError("button index exceeds EV_KEY capabilities")
    match = re.fullmatch(r"([+-]?)a(\d+)(~?)", text)
    if match:
        index = int(match[2])
        if index < len(axes):
            return ("axis", axes[index], match[1], bool(match[3]))
        raise ValueError("axis index exceeds Main's non-hat EV_ABS capabilities")
    match = re.fullmatch(r"h(\d+)\.(\d+)", text)
    if match:
        hat, mask = int(match[1]), int(match[2])
        if hat > 3 or mask not in (1, 2, 4, 8):
            raise ValueError("unsupported hat number/direction (Main uses cardinal masks)")
        code = 16 + hat * 2 + int(mask in (1, 4))
        if code not in abs_codes:
            raise ValueError("hat axis absent from EV_ABS capabilities")
        return ("axis", code, "+" if mask in (2, 4) else "-", False)
    raise ValueError("unsupported binding syntax")


class ControllerDB:
    """Read once; retain file order so the last matching entry wins like Main."""
    def __init__(self, directory, log):
        self.files = []
        for filename in ("gamecontrollerdb_user.txt", "gamecontrollerdb.txt"):
            path = os.path.join(directory, filename)
            entries = []
            try:
                with open(path, encoding="utf-8-sig") as f:
                    for number, line in enumerate(f, 1):
                        parts = line.strip().split(",")
                        if not parts or not re.fullmatch(r"[0-9a-fA-F]{32}", parts[0]) or len(parts) < 3:
                            continue
                        fields = [tuple(p.split(":", 1)) for p in parts[2:] if ":" in p]
                        entries.append((parts[0].lower(), parts[1], fields, number))
                log("CONTROLLERDB loaded %s entries=%d" % (path, len(entries)))
            except FileNotFoundError:
                log("CONTROLLERDB missing %s" % path)
            except (OSError, UnicodeError) as exc:
                log("CONTROLLERDB ERROR %s: %s" % (path, exc))
            self.files.append((path, entries))

    def resolve(self, identity, key_caps, abs_codes, log):
        guid = controller_guid(identity)
        log("  DB GUID=%s (exact Main bus/vendor/product/version identity)" % guid)
        for path, entries in self.files:
            chosen = None
            for candidate in entries:
                entry_guid, name, fields, number = candidate
                if entry_guid != guid:
                    continue
                metadata = dict(fields)
                platform_name = metadata.get("platform", "").lower()
                if platform_name not in ("linux", "mister"):
                    log("  DB SKIP %s:%d platform=%r" % (path, number, platform_name))
                    continue
                if platform_name == "mister" and any(k.lower() == "mistercore" for k, _ in fields):
                    log("  DB SKIP %s:%d core-specific entry: Main's internal core aliases are not verified by this diagnostic" % (path, number))
                    continue
                chosen = candidate
            if chosen is None:
                continue
            _, name, fields, number = chosen
            bindings = {}
            for control, text in fields:
                if control not in DB_CONTROLS:
                    continue
                try:
                    bindings[control] = (text, db_binding(text, key_caps, abs_codes))
                except ValueError as exc:
                    log("  DB UNSUPPORTED %s:%d %s:%s: %s" % (path, number, control, text, exc))
            if bindings:
                log("  DB MATCH %s:%d name=%r GUID=%s" % (path, number, name, guid))
                return bindings
            log("  DB entry has no usable bindings; trying next database")
        log("  DB NO MATCH with usable generic bindings for GUID=%s; no name/VID-PID guesses" % guid)
        return None


class Log:
    def __init__(self, path):
        self.file = open(path, "w", buffering=1) if path else None
        self.start = time.monotonic()

    def __call__(self, message):
        line = "[%8.3f] %s" % (time.monotonic() - self.start, message)
        print(line, flush=True)
        if self.file:
            self.file.write(line + "\n")

    def close(self):
        if self.file:
            self.file.close()


class Monitor:
    def __init__(self, device, args, log):
        self.d, self.args, self.log = device, args, log
        self.tag = os.path.basename(device["js"] or device["event"])
        self.stats = collections.Counter()
        self.observed = set()
        self.errors = {}
        self.mapping = None
        self.buttons, self.axes = [], []
        self.state_fd = self.stream_fd = None
        self.previous_js = self.previous_keys = self.previous_abs = None
        self.first_shape = None
        self.disagreements = collections.Counter()
        self.stream_buffer = b""
        self.abs_codes = set()
        self.key_caps = set()
        self.sam_buttons = {}
        self.input_id = None
        self.db = None
        log("DEVICE %s: %s id=%s js=%s event=%s" %
            (self.tag, device["name"], device["id"], device["js"], device["event"]))
        log("  phys=%r uniq=%r handlers=%s" % (device["phys"], device["uniq"], device["handlers"]))
        self.open_event()
        self.read_js_maps()
        self.read_controller_db()
        self.read_mister_map()
        self.read_sam_config()

    def error(self, source, exc):
        self.stats[source + " errors"] += 1
        message = str(exc)
        if self.errors.get(source) != message:
            self.log("%s ERROR %s: %s" % (self.tag, source, message))
            self.errors[source] = message

    def open_event(self):
        path = self.d["event"]
        if not path:
            self.log("  NO paired event node: EVIOCGKEY comparison unavailable")
            return
        try:
            self.state_fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            # A second descriptor keeps EVIOCGKEY's queue flushing from changing
            # the raw-event observer's queue. Neither descriptor grabs input.
            self.stream_fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            self.key_caps = bit_codes(ioctl_bytes(self.state_fd, ior("E", 0x21, KEY_BYTES), KEY_BYTES))
            self.abs_codes = bit_codes(ioctl_bytes(self.state_fd, ior("E", 0x23, 8), 8))
            raw_id = ioctl_bytes(self.state_fd, ior("E", 0x02, 8), 8)
            bus, vendor, product, version = struct.unpack("=4H", raw_id)
            self.input_id = (bus, vendor, product, version)
            self.log("  EVIOCGID bus=%04x vendor=%04x product=%04x version=%04x" %
                     (bus, vendor, product, version))
            self.log("  EV_KEY capability codes=%s; EV_ABS axes=%s" %
                     (sorted(self.key_caps), sorted(self.abs_codes)))
        except OSError as exc:
            self.error("event setup", exc)

    def read_js_maps(self):
        if not self.d["js"]:
            return
        try:
            fd = os.open(self.d["js"], os.O_RDONLY | os.O_NONBLOCK)
            try:
                nb = ioctl_bytes(fd, ior("j", 0x12, 1), 1)[0]
                na = ioctl_bytes(fd, ior("j", 0x11, 1), 1)[0]
                raw = ioctl_bytes(fd, ior("j", 0x34, 1024), 1024)
                self.buttons = list(struct.unpack("=512H", raw)[:nb])
                self.axes = list(ioctl_bytes(fd, ior("j", 0x32, 64), 64)[:na])
                self.log("  JSIOCGBTNMAP: %d buttons; JSIOCGAXMAP: %d axes" % (nb, na))
                for number, code in enumerate(self.buttons):
                    self.log("    js button %-3d -> Linux %-4d 0x%03x %s" % (number, code, code, code_text(code)))
                for number, code in enumerate(self.axes):
                    self.log("    js axis   %-3d -> ABS %-3d" % (number, code))
                if nb + na > 64:
                    self.log("  WARNING: %d INIT records exceed MCP's single 512-byte read" % (nb + na))
            finally:
                os.close(fd)
        except OSError as exc:
            self.error("js mapping ioctls", exc)

    def read_controller_db(self):
        database = getattr(self.args, "controller_database", None)
        if database is None:
            database = ControllerDB(getattr(self.args, "controllerdb_dir", "/media/fat/linux/gamecontrollerdb"), self.log)
            self.args.controller_database = database
        if self.input_id is None:
            self.log("  DB unavailable: EVIOCGID/capabilities could not be queried")
            return
        self.db = database.resolve(self.input_id, self.key_caps, self.abs_codes, self.log)
        if self.db is not None:
            for control, (text, (kind, code, half, inverted)) in self.db.items():
                if kind == "button":
                    detail = "Linux=%d %s js_buttons=%s" % (code, code_text(code), [n for n, c in enumerate(self.buttons) if c == code])
                else:
                    detail = "ABS=%d half=%s inverted=%s js_axes=%s" % (code, half or "full", inverted, [n for n, c in enumerate(self.axes) if c == code])
                self.log("    DB %-14s %s -> %s" % (control, text, detail))

    def db_labels(self, kind, code):
        if self.db is None:
            return "unavailable"
        found = []
        for control, (_, (binding_kind, binding_code, half, inverted)) in self.db.items():
            if kind == binding_kind and code == binding_code:
                suffix = ("(%s%s)" % (half, "~" if inverted else "")) if half or inverted else ""
                found.append(control + suffix)
        return "+".join(found) or "unmapped"

    def read_mister_map(self):
        candidates = map_paths(self.args.config_dir, self.d["id"])
        related = set()
        for directory in (os.path.join(self.args.config_dir, "inputs"), self.args.config_dir):
            related.update(glob.glob(os.path.join(directory, "*input_" + self.d["id"] + "*_v3.map")))
        for path in sorted(related):
            self.log("  MAP CANDIDATE %s" % path)
        self.log("  Global map search order: %s" % " -> ".join(candidates))
        chosen = self.args.map or next((p for p in candidates if os.path.exists(p)), None)
        if not chosen:
            self.log("  NO ordinary global v3 map. Related files may be unique-device, alternate-mode or per-core maps; use --map to inspect one explicitly.")
            return
        self.log("  DECODED MAP %s%s" % (chosen, " (explicit --map)" if self.args.map else " (ordinary global candidate; Main's active choice is not verified)"))
        try:
            with open(chosen, "rb") as f:
                data = f.read(129)
            self.mapping = decode_map(data)
        except (OSError, ValueError) as exc:
            self.error("map decode", exc)
            return
        for index, value in enumerate(self.mapping):
            name = SLOTS[index] if index < 12 else {21: "Menu1", 22: "Menu2", 23: "MENU_OK/BACK", 24: "Stick1_X", 25: "Stick1_Y", 26: "Stick2_X", 27: "Stick2_Y", 28: "Menu_X", 29: "Menu_Y"}.get(index, "slot_%d" % index)
            detail = code_text(value)
            if index == 23:
                detail = "packed OK=%d BACK=%d" % (value & 0xffff, value >> 16)
            elif 24 <= index <= 29:
                detail = "axis field: low16=%d high16=0x%04x; zero may mean unset" % (value & 0xffff, value >> 16)
            elif index < 12 or index in (21, 22):
                js = [str(n) for n, code in enumerate(self.buttons) if code == value and value]
                detail += "; js button=" + (",".join(js) or "NONE")
                if value and value < KEY_EMU:
                    detail += "; event capability=" + ("YES" if value in self.key_caps else "NO/unknown")
                if KEY_EMU <= value < 0x10000:
                    detail += "; axis capability=" + ("YES" if (value - KEY_EMU) // 2 in self.abs_codes else "NO/unknown")
            self.log("    [%02d] %-12s decimal=%-10d hex=0x%08x %s" % (index, name, value, value, detail))

    def read_sam_config(self):
        directory = self.args.sam_dir
        path = os.path.join(directory, "sam_controllers.custom.json")
        if not os.path.exists(path):
            path = os.path.join(directory, "sam_controllers.json")
        try:
            with open(path) as f:
                config = json.load(f)
            selection = self.d["id"] if self.d["id"] in config else "default"
            selected = config.get(selection, {})
            self.sam_buttons = selected.get("button", {})
            self.log("  SAM CONFIG %s entry=%s buttons=%s axes=%s" %
                     (path, selection, self.sam_buttons, selected.get("axis", {})))
        except (OSError, ValueError, AttributeError) as exc:
            self.error("SAM config", exc)

    def sample_js(self):
        if not self.d["js"]:
            return None
        fd = os.open(self.d["js"], os.O_RDONLY | os.O_NONBLOCK)
        try:
            data = os.read(fd, 512)  # The exact read size used by MCP
            records, snapshot = decode_js(data)
            shape = tuple((kind, number) for _, _, kind, number in records)
            if self.first_shape is None:
                self.first_shape = shape
                self.log("%s JS baseline: bytes=%d INIT=%d shape(type,number)=%s values=%s" %
                         (self.tag, len(data), len(snapshot), shape, sorted(snapshot.items())))
            elif shape != self.first_shape:
                self.stats["JS shape differences"] += 1
                if self.stats["JS shape differences"] <= 3:
                    self.log("%s WARNING JS list shape changed: %s; MCP compares by position and rejects unequal lengths" % (self.tag, shape))
            expected = len(self.buttons) + len(self.axes)
            if len(snapshot) < expected:
                self.stats["incomplete JS snapshots"] += 1
            self.stats["JS samples"] += 1
            return snapshot
        finally:
            os.close(fd)

    def sample_abs(self):
        return {axis: struct.unpack("=6i", ioctl_bytes(self.state_fd, ior("E", 0x40 + axis, 24), 24))
                for axis in self.abs_codes}

    def read_stream(self):
        if self.stream_fd is None:
            return
        # Bounded drain prevents a noisy device from starving state polling.
        for _ in range(4):
            try:
                data = os.read(self.stream_fd, INPUT_EVENT.size * 64)
            except BlockingIOError:
                break
            if not data:
                break
            self.stream_buffer += data
            while len(self.stream_buffer) >= INPUT_EVENT.size:
                sec, usec, kind, code, value = INPUT_EVENT.unpack_from(self.stream_buffer)
                self.stream_buffer = self.stream_buffer[INPUT_EVENT.size:]
                self.stats["raw events"] += 1
                if kind in (1, 3) or (kind == 0 and code == 3):
                    self.log("%s STREAM type=%d code=%d value=%d kernel_time=%d.%06d %s DB=%s" %
                             (self.tag, kind, code, value, sec, usec, labels(code, self.mapping) if kind == 1 else "",
                              self.db_labels("button" if kind == 1 else "axis", code) if kind in (1, 3) else "n/a"))

    def poll(self):
        js = keys = axes = None
        try:
            js = self.sample_js()
        except (OSError, ValueError) as exc:
            self.error("JS snapshot", exc)
        if self.state_fd is not None:
            try:
                self.read_stream()
            except OSError as exc:
                self.error("event stream", exc)
            try:
                keys = bit_codes(ioctl_bytes(self.state_fd, ior("E", 0x18, KEY_BYTES), KEY_BYTES))
                self.stats["EVIOCGKEY samples"] += 1
                if self.previous_keys is None:
                    self.log("%s EVIOCGKEY baseline held=%s" % (self.tag, sorted(keys)))
                else:
                    for code in sorted(keys ^ self.previous_keys):
                        down = code in keys
                        self.stats["EVIOCGKEY changes"] += 1
                        if down:
                            self.observed.add(code)
                        self.log("%s EVIOCGKEY %s Linux=%d %s MiSTer=%s DB=%s" %
                                 (self.tag, "DOWN" if down else "UP", code, code_text(code), labels(code, self.mapping), self.db_labels("button", code)))
                self.previous_keys = keys
            except OSError as exc:
                self.error("EVIOCGKEY", exc)
            try:
                axes = self.sample_abs()
                if self.previous_abs is None:
                    self.log("%s EVIOCGABS baseline (value,min,max,fuzz,flat,resolution)=%s" % (self.tag, axes))
                else:
                    for axis, old, new in changed_values(self.previous_abs, axes):
                        if abs(new[0] - old[0]) >= abs_log_threshold(new, self.args.axis_delta):
                            self.log("%s EVIOCGABS axis=%d value=%d -> %d range=[%d,%d] DB=%s" %
                                     (self.tag, axis, old[0], new[0], new[1], new[2], self.db_labels("axis", axis)))
                # Retain the last printed value so gradual movement accumulates.
                if self.previous_abs is None:
                    self.previous_abs = axes.copy()
                else:
                    for axis, value in axes.items():
                        if axis not in self.previous_abs or abs(value[0] - self.previous_abs[axis][0]) >= abs_log_threshold(value, self.args.axis_delta):
                            self.previous_abs[axis] = value
            except OSError as exc:
                self.error("EVIOCGABS", exc)
        if js is not None:
            if self.previous_js is not None:
                for (kind, number), old, new in changed_values(self.previous_js, js):
                    if kind == 1:
                        code = self.buttons[number] if number < len(self.buttons) else None
                        actions = [name for name, n in self.sam_buttons.items() if n == number]
                        self.stats["JS button changes"] += 1
                        self.log("%s JS %s button=%d Linux=%s MiSTer=%s SAM=%s EVIOCGKEY=%s DB=%s" %
                                 (self.tag, "DOWN" if new else "UP", number, code,
                                  labels(code, self.mapping) if code is not None else "unknown",
                                  "+".join(actions) or "default", "unavailable" if keys is None or code is None else int(code in keys), self.db_labels("button", code)))
                    elif kind == 2 and abs(new - old) >= self.args.axis_delta:
                        code = self.axes[number] if number < len(self.axes) else None
                        self.log("%s JS axis=%d ABS=%s value=%d -> %d EVIOCGABS=%s DB=%s" %
                                 (self.tag, number, code, old, new, axes.get(code) if axes else "unavailable", self.db_labels("axis", code)))
            self.previous_js = js
            if keys is not None:
                for number, code in enumerate(self.buttons):
                    if (1, number) not in js:
                        continue
                    if bool(js[(1, number)]) != (code in keys):
                        self.disagreements[number] += 1
                        if self.disagreements[number] == 3:
                            self.stats["persistent button disagreements"] += 1
                            self.log("%s DISAGREE for 3 samples: js button=%d code=%d JS=%d EVIOCGKEY=%d" %
                                     (self.tag, number, code, js[(1, number)], code in keys))
                    else:
                        self.disagreements[number] = 0

    def summary(self):
        self.log("SUMMARY %s counts=%s" % (self.tag, dict(self.stats)))
        for code in sorted(self.observed):
            self.log("  observed Linux=%d %s MiSTer=%s js_buttons=%s DB=%s" %
                     (code, code_text(code), labels(code, self.mapping),
                      [n for n, c in enumerate(self.buttons) if c == code], self.db_labels("button", code)))
        if not self.stats["raw events"]:
            self.log("  No raw stream events received. This is consistent with Main's grab; it does not by itself prove a grab.")
        if not self.stats["EVIOCGKEY changes"] and not self.stats["JS button changes"]:
            self.log("  No button changes observed: verify the selected node, hold buttons longer, and check the ERROR lines.")

    def close(self):
        for fd in (self.state_fd, self.stream_fd):
            if fd is not None:
                os.close(fd)


class DeviceRegistry:
    def __init__(self, args, log):
        self.args, self.log = args, log
        self.current = {}
        self.waiting = False

    def sync(self, devices):
        desired = {d["js"] or d["event"]: d for d in select_devices(devices, self.args.devices)}
        for path, monitor in list(self.current.items()):
            if path not in desired or device_identity(monitor.d) != device_identity(desired[path]):
                self.log("HOTPLUG REMOVED %s %s" % (path, monitor.d["name"]))
                monitor.summary()
                monitor.close()
                del self.current[path]
        for path, device in desired.items():
            if path not in self.current:
                self.log("HOTPLUG ADDED %s %s; capturing a fresh baseline" % (path, device["name"]))
                self.current[path] = Monitor(device, self.args, self.log)
        if not self.current and not self.waiting:
            self.log("WAITING for a matching input device; rescanning every two seconds")
        self.waiting = not self.current

    def close(self):
        for monitor in self.current.values():
            monitor.summary()
            monitor.close()
        self.current.clear()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("devices", nargs="*", help="restrict to these jsX/eventX paths; default: all current and newly connected js devices")
    parser.add_argument("--list", action="store_true", help="list input devices without monitoring")
    parser.add_argument("--map", help="explicit v3 map to inspect; requires one selected device")
    parser.add_argument("--config-dir", default="/media/fat/config")
    parser.add_argument("--sam-dir", default="/media/fat/Scripts/.MiSTer_SAM")
    parser.add_argument("--controllerdb-dir", default="/media/fat/linux/gamecontrollerdb", help="directory with gamecontrollerdb_user.txt and gamecontrollerdb.txt")
    parser.add_argument("--interval", type=float, default=0.02, help="poll seconds, default 0.02")
    parser.add_argument("--duration", type=float, default=0, help="stop after N seconds; default: Ctrl+C")
    parser.add_argument("--axis-delta", type=int, default=2000, help="axis log threshold; use 1 for hats/small ranges")
    parser.add_argument("--log", default="/tmp/SAM-input-debug-%s.log" % datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    args = parser.parse_args(argv)
    if args.interval <= 0 or args.duration < 0 or args.axis_delta < 1:
        parser.error("interval and axis-delta must be positive; duration must be nonnegative")
    if sys.platform != "linux":
        parser.error("live input diagnostics must run on Linux/MiSTer")
    try:
        log = Log(args.log)
    except OSError as exc:
        parser.error("cannot create log: %s" % exc)
    registry = DeviceRegistry(args, log)
    try:
        log("SAM input diagnostic v3 (hotplug + controllerdb); log=%s" % args.log)
        log("Python=%s machine=%s kernel=%s event_record_bytes=%d interval=%.3fs" %
            (platform.python_version(), platform.machine(), platform.release(), INPUT_EVENT.size, args.interval))
        log("Read-only input access; no EVIOCGRAB, no injection, no SAM/core/config changes.")
        log("DB labels describe database bindings; MiSTer labels come only from the inspected saved map. Axis halves/inversion are binding metadata, not detected digital actions.")
        devices = read_devices()
        for d in devices:
            log("INVENTORY id=%s js=%s event=%s name=%r" % (d["id"], d["js"], d["event"], d["name"]))
        if args.list:
            return 0
        selected = select_devices(devices, args.devices)
        if args.devices:
            for path in args.devices:
                if not any(path in (d["js"], d["event"]) for d in devices):
                    raise ValueError("%s not found in /proc/bus/input/devices; use --list" % path)
        if args.map and (not args.devices or len(selected) != 1):
            raise ValueError("--map requires exactly one explicitly selected device")
        log("WATCH %s; hotplug rescan every two seconds" %
            (", ".join(args.devices) if args.devices else "all current and newly connected js devices"))
        registry.sync(devices)
        log("TEST: press physical Start, Select, A, B and Menu separately; hold each for one second and release. Then move the stick/d-pad.")
        log("MiSTer labels above are predictions from the decoded file. Note if a physical button prints the wrong label.")
        log("Repeat with a game core running and in Menu. SAM/Main still receive your presses normally. Reconnected devices reload their maps; restart after remapping a connected device.")
        begin = heartbeat = last_scan = time.monotonic()
        last_core = None
        while not args.duration or time.monotonic() - begin < args.duration:
            tick = time.monotonic()
            if tick - last_scan >= 2:
                try:
                    registry.sync(read_devices())
                except OSError as exc:
                    log("HOTPLUG SCAN ERROR: %s" % exc)
                last_scan = tick
            try:
                with open("/tmp/CORENAME") as f:
                    core = f.read(256).strip()
            except OSError:
                core = "unavailable"
            if core != last_core:
                log("CORENAME=%r (map tables reflect each device's last connection)" % core)
                last_core = core
            for monitor in registry.current.values():
                monitor.poll()
            if tick - heartbeat >= 10:
                for monitor in registry.current.values():
                    log("HEARTBEAT %s %s" % (monitor.tag, dict(monitor.stats)))
                heartbeat = tick
            time.sleep(max(0, args.interval - (time.monotonic() - tick)))
        return 0
    except KeyboardInterrupt:
        log("Stopped by Ctrl+C.")
        return 0
    except (OSError, ValueError) as exc:
        log("ERROR: %s" % exc)
        return 1
    finally:
        registry.close()
        log("Diagnostic complete. Log: %s" % args.log)
        log.close()


if __name__ == "__main__":
    sys.exit(main())
