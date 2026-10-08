#!/usr/bin/env python3
import asyncio
import configparser
import math
import fcntl
import glob
import queue
import re
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


INPUT_KEY_EMU = 0x300

INPUT_SLOTS = ["Right", "Left", "Down", "Up", "A", "B", "X", "Y", "L", "R", "Select", "Start"]

INPUT_DB_CONTROLS = set("a b x y back start guide guide2 menuok menuesc leftshoulder rightshoulder leftstick rightstick lefttrigger righttrigger leftx lefty rightx righty asysx asysy dpup dpdown dpleft dpright misc1 paddle1 paddle2 paddle3 paddle4 touchpad".split())

INPUT_NAMES = {1: "KEY_ESC", 28: "KEY_ENTER", 57: "KEY_SPACE", 88: "KEY_F12",
         103: "KEY_UP", 105: "KEY_LEFT", 106: "KEY_RIGHT", 108: "KEY_DOWN",
         304: "BTN_SOUTH", 305: "BTN_EAST", 307: "BTN_NORTH", 308: "BTN_WEST",
         310: "BTN_TL", 311: "BTN_TR", 312: "BTN_TL2", 313: "BTN_TR2",
         314: "BTN_SELECT", 315: "BTN_START", 316: "BTN_MODE",
         317: "BTN_THUMBL", 318: "BTN_THUMBR", 544: "BTN_DPAD_UP",
         545: "BTN_DPAD_DOWN", 546: "BTN_DPAD_LEFT", 547: "BTN_DPAD_RIGHT"}

def input_code_text(code):
    if not code:
        return "unassigned"
    if code >= 0x10000:
        return "wide/flagged value; NOT truncated to 16 bits"
    if code >= INPUT_KEY_EMU:
        axis = (code - INPUT_KEY_EMU) // 2
        return "axis %d %s (synthetic edge)" % (axis, "+" if code & 1 else "-")
    return INPUT_NAMES.get(code, "KEY_%d" % code if code < 256 else "BTN_%d" % code)

def input_controller_guid(identity):
    # Main's GUID: four little-endian uint16 IDs, each padded to four bytes.
    return b"".join(struct.pack("<H", value) + b"\0\0" for value in identity).hex()

def input_db_binding(text, key_caps, abs_codes):
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

class InputControllerDB:
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
        self.core_specific = False
        guid = input_controller_guid(identity)
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
                    self.core_specific = True
                    log("  DB SKIP %s:%d core-specific entry: Main's internal core aliases are not verified by this diagnostic" % (path, number))
                    continue
                chosen = candidate
            if chosen is None:
                continue
            _, name, fields, number = chosen
            bindings = {}
            for control, text in fields:
                if control not in INPUT_DB_CONTROLS:
                    continue
                try:
                    bindings[control] = (text, input_db_binding(text, key_caps, abs_codes))
                except ValueError as exc:
                    log("  DB UNSUPPORTED %s:%d %s:%s: %s" % (path, number, control, text, exc))
            if bindings:
                log("  DB MATCH %s:%d name=%r GUID=%s" % (path, number, name, guid))
                return bindings
            log("  DB entry has no usable bindings; trying next database")
        log("  DB NO MATCH with usable generic bindings for GUID=%s; no name/VID-PID guesses" % guid)
        return None

# --- Cached MiSTer input definitions (no input grab or event-stream reader) ---
INPUT_CONFIG_DIR = '/media/fat/config'
INPUT_DB_DIR = '/media/fat/linux/gamecontrollerdb'


class InputDebugOutput:
    """Bounded, nonblocking output; a slow terminal cannot block the poller."""
    def __init__(self, size=256):
        self.messages = queue.Queue(maxsize=size)
        self.dropped = 0
        self.thread = threading.Thread(target=self.run, name='sam-input-debug', daemon=True)
        self.thread.start()

    def emit(self, message):
        try:
            self.messages.put_nowait(message)
        except queue.Full:
            self.dropped += 1

    def run(self):
        while True:
            message = self.messages.get()
            if message is None:
                return
            try:
                if self.dropped:
                    count, self.dropped = self.dropped, 0
                    print('MCP-INPUT: debug output overflow; dropped=%d' % count, flush=True)
                print(message, flush=True)
            except (OSError, ValueError):
                return  # Terminal closure must not affect input/action handling.

    def close(self):
        self.emit(None)


def input_debug(state, message):
    output = getattr(state, 'input_debug_output', None)
    if output is not None:
        output.emit(message)


class InputBindings:
    """Per-reader immutable metadata; rebuild through MCP's existing hotplug path.

    Saved global maps are authoritative, including zero slots. DB definitions
    only drive actions when no saved definition exists. Unverified unique/mode
    choices and flagged action slots produce generic activity, not guessed actions.
    """
    def __init__(self, device, state):
        self.device, self.state = device, state
        self.buttons, self.axes, self.mapping, self.db = [], [], None, None
        self.source = 'generic'
        self.map_status = 'absent'
        self.button_labels, self.axis_labels = {}, {}
        self.actions = {}  # (kind, js number, direction) -> SAM action
        self.role_axes = set()
        self.db_core_specific = False
        self.last_events = None
        self.last_snapshot = {}
        self.setup()
        self.describe()

    def log(self, text):
        # Routine metadata belongs in the standalone diagnostic, not every restart.
        if text.lstrip().startswith(('CONTROLLERDB loaded ', 'CONTROLLERDB missing ',
                                    'DB GUID=', 'DB MATCH ', 'saved global map=',
                                    'action source=')):
            return
        input_debug(self.state, 'MCP-INPUT: %s: %s' % (self.device.get('name', 'Controller'), text))

    @staticmethod
    def ioctl(fd, kind, number, size):
        data = bytearray(size)
        fcntl.ioctl(fd, (2 << 30) | (size << 16) | (ord(kind) << 8) | number, data, True)
        return bytes(data)

    def setup(self):
        try:
            with open(self.device['js_path'], 'rb', buffering=0) as f:
                fd = f.fileno()
                nb = self.ioctl(fd, 'j', 0x12, 1)[0]
                na = self.ioctl(fd, 'j', 0x11, 1)[0]
                self.buttons = list(struct.unpack('=512H', self.ioctl(fd, 'j', 0x34, 1024))[:nb])
                self.axes = list(self.ioctl(fd, 'j', 0x32, 64)[:na])
        except OSError as exc:
            self.log('js metadata unavailable: %s; generic activity only' % exc)
            return
        self.read_map()
        if self.state.samdebug or (self.mapping is None and self.map_status == 'absent'):
            try:
                with open(self.device['event_path'], 'rb', buffering=0) as f:
                    fd = f.fileno()
                    identity = struct.unpack('=4H', self.ioctl(fd, 'E', 0x02, 8))
                    key_bits = self.ioctl(fd, 'E', 0x21, 96)
                    abs_bits = self.ioctl(fd, 'E', 0x23, 8)
                    keys = {i for i in range(768) if key_bits[i // 8] & (1 << (i % 8))}
                    axes = {i for i in range(64) if abs_bits[i // 8] & (1 << (i % 8))}
                # Main uses USB bcdDevice for these specific adapter families.
                bus, vid, pid, version = identity
                if bus == 3 and ((vid == 0x16d0 and pid in (0x127e, 0x1460)) or (vid == 0x1209 and pid == 0x595a)):
                    path = os.path.join('/sys', self.device.get('sysfs', '').lstrip('/'))
                    while path.startswith('/sys/'):
                        try:
                            with open(os.path.join(path, 'bcdDevice')) as f:
                                version = int(f.read(32).strip(), 16)
                            break
                        except (OSError, ValueError):
                            path = os.path.dirname(path)
                    identity = (bus, vid, pid, version)
                with self.state.input_metadata_lock:
                    if self.state.input_database is None:
                        self.state.input_database = InputControllerDB(INPUT_DB_DIR, self.log)
                    self.db = self.state.input_database.resolve(identity, keys, axes, self.log)
                    self.db_core_specific = self.state.input_database.core_specific
            except (OSError, KeyError, ValueError) as exc:
                self.log('controllerdb metadata unavailable: %s' % exc)
        self.build_labels()
        if self.mapping is not None:
            self.source = 'MiSTer-map'
            for slot, action in ((11, 'start'), (10, 'next')):
                value = self.mapping[slot]
                if value == 0:
                    self.log('%s explicitly unassigned; database fallback suppressed' % INPUT_SLOTS[slot])
                elif value < 768:
                    for number, code in enumerate(self.buttons):
                        if code == value:
                            self.actions.setdefault(('button', number, ''), action)
                elif 768 <= value < 896:
                    axis, half = (value - 768) // 2, '+' if value & 1 else '-'
                    for number, code in enumerate(self.axes):
                        if code == axis:
                            self.actions.setdefault(('axis', number, half), action)
                else:
                    self.log('%s unsupported flagged value 0x%x; generic activity only for this slot' % (INPUT_SLOTS[slot], value))
        elif self.map_status == 'absent' and self.db is not None and not self.db_core_specific:
            self.source = 'controllerdb'
            for control, action in (('start', 'start'), ('back', 'next')):
                if control not in self.db:
                    continue
                _, (kind, code, half, inverted) = self.db[control]
                indices = self.buttons if kind == 'button' else self.axes
                for number, actual in enumerate(indices):
                    if actual == code:
                        # A full axis used as a digital control activates its positive half.
                        direction = half or ('+' if kind == 'axis' else '')
                        if inverted:
                            direction = '-' if direction == '+' else '+'
                        self.actions.setdefault((kind, number, direction), action)
        self.role_axes = {number for kind, number, half in self.actions if kind == 'axis'}
        if self.mapping is None and self.db_core_specific:
            self.log('core-specific database identity unresolved; named actions suppressed')
        self.log('action source=%s; saved-map status=%s; enabled roles=%s' % (self.source, self.map_status, sorted(set(self.actions.values()))))

    def read_map(self):
        model = self.device.get('id', '')
        if not re.fullmatch('[0-9a-f]{4}_[0-9a-f]{4}', model):
            self.map_status = 'unsupported identity'
            self.log('saved map identity unsupported; generic actions')
            return
        dirs = [os.path.join(INPUT_CONFIG_DIR, 'inputs'), INPUT_CONFIG_DIR]
        normal = 'input_%s_v3.map' % model
        related = [p for d in dirs for p in glob.glob(os.path.join(d, 'input_%s*_v3.map' % model)) if os.path.basename(p) != normal]
        vid, pid = (int(x, 16) for x in model.split('_'))
        special = vid == 0x2341 or (vid == 0x16c0 and pid >> 8 == 4) or (vid == 0x16d0 and pid in (0x127e, 0x1460)) or (vid == 0x1209 and pid in (0x595a, 0xface, 0xfaca))
        if related or special:
            self.map_status = 'ambiguous identity/mode'
            self.log('unique/alternate/special identity needs verification; candidates=%s; generic actions' % related)
            return
        for directory in dirs:
            path = os.path.join(directory, normal)
            try:
                with open(path, 'rb') as f:
                    data = f.read(129)
            except FileNotFoundError:
                continue
            except OSError as exc:
                self.map_status = 'unreadable'
                self.log('saved map unreadable %s: %s; no database substitution' % (path, exc))
                return
            if len(data) != 128:
                self.map_status = 'invalid'
                self.log('saved map invalid size %s: %d; no database substitution' % (path, len(data)))
                return
            self.mapping = struct.unpack('<32I', data)
            self.map_status = 'loaded'
            self.log('saved global map=%s (ordinary identity; unique/merged Main quirks are not inferred)' % path)
            return

    def build_labels(self):
        for number, code in enumerate(self.buttons):
            mister = self.map_labels(code)
            db = self.db_labels('button', code)
            prefix = 'DOWN MiSTer=%s DB=%s' % (mister, db)
            if self.mapping is not None and mister == 'unmapped' and db in ('unmapped', 'unavailable'):
                prefix += ' Linux=%d %s' % (code, input_code_text(code))
            if self.mapping is None:
                prefix += ' js_button=%d Linux=%d %s' % (number, code, input_code_text(code))
            self.button_labels[number] = prefix
        for number, code in enumerate(self.axes):
            self.axis_labels[number] = self.db_labels('axis', code)

    def map_labels(self, code):
        if self.mapping is None:
            return 'unavailable'
        labels = [name for name, value in zip(INPUT_SLOTS, self.mapping) if value == code and code]
        labels += ['Menu%d' % (slot - 20) for slot in (21, 22) if self.mapping[slot] == code and code]
        return '+'.join(labels) or 'unmapped'

    def db_labels(self, kind, code):
        if self.db is None:
            return 'unavailable'
        labels = []
        for name, (_, (k, c, half, inverted)) in self.db.items():
            if (k, c) == (kind, code):
                suffix = '(%s%s)' % (half, '~' if inverted else '') if half or inverted else ''
                labels.append(name + suffix)
        return '+'.join(labels) or 'unmapped'

    def describe(self):
        labels = []
        if 'start' in self.actions.values():
            labels.append('Start')
        if 'next' in self.actions.values():
            labels.append('Select')
        self.log('Ready: %s' % ('/'.join(labels) if labels else 'generic input'))

    @staticmethod
    def snapshot(events):
        # INIT records are state; queued records must not replace that state.
        return {(event['type'] & 0x7f, event['number']): event['value']
                for event in events if event['type'] & 0x80}

    def changes(self, previous, current):
        old = self.last_snapshot if previous is self.last_events else self.snapshot(previous)
        new = self.snapshot(current)
        self.last_events, self.last_snapshot = current, new
        if old == new:
            return []
        changes = [(key, old[key], value) for key, value in new.items() if key in old and old[key] != value]
        return changes

    def action(self, previous, current, changes=None):
        # Quiet samples require no Python event-by-event action scan.
        if changes is None:
            changes = self.changes(previous, current)
        if not changes:
            return None
        # Retain generic activity semantics; only source of named actions changes.
        if self.role_axes:
            ordinary_previous = [e for e in previous if not (e['type'] & AXIS_TYPE and e['number'] in self.role_axes)]
            ordinary_current = [e for e in current if not (e['type'] & AXIS_TYPE and e['number'] in self.role_axes)]
        else:
            ordinary_previous, ordinary_current = previous, current
        fallback = get_js_activity(ordinary_previous, ordinary_current, {})
        if changes is None:
            changes = self.changes(previous, current)
        for (kind, number), before, after in changes:
            if kind == BUTTON_TYPE and after == 1:
                role = self.actions.get(('button', number, ''))
                if role:
                    return role
            if kind == AXIS_TYPE:
                for half, sign in (('+', 1), ('-', -1)):
                    # Joydev normalizes hats/sticks. Use a half-range digital edge;
                    # never interpret tiny analog noise as Start/Select.
                    if before * sign <= 16384 < after * sign:
                        role = self.actions.get(('axis', number, half))
                        if role:
                            return role
        return fallback

    def has_activity(self, previous, current, changes=None):
        if changes is None:
            changes = self.changes(previous, current)
        return any((kind == BUTTON_TYPE and after == 1) or
                   (kind == AXIS_TYPE and abs(after - before) > AXIS_DEADZONE)
                   for (kind, number), before, after in changes)

    def report(self, previous, current, changes=None):
        if changes is None:
            changes = self.changes(previous, current)
        for (kind, number), before, after in changes:
            if kind == BUTTON_TYPE and after == 1:
                text = self.button_labels.get(number, 'DOWN unknown button')
                action = self.actions.get(('button', number, ''), 'default')
                self.log('%s action=%s' % (text, action))
            elif kind == AXIS_TYPE and abs(after - before) > AXIS_DEADZONE:
                code = self.axes[number] if number < len(self.axes) else None
                edge = 768 + code * 2 + int(after > 0) if code is not None and abs(after) > 16384 else 0
                text = 'AXIS value=%d MiSTer=%s DB=%s' % (after, self.map_labels(edge), self.axis_labels.get(number, 'unavailable'))
                if self.mapping is None:
                    text += ' js_axis=%d ABS=%s' % (number, code)
                self.log(text)
# --- End cached input definitions ---


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
        self.samdebug = False
        self.input_debug_output = None
        self.input_database = None
        self.input_metadata_lock = threading.Lock()
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

    print(f"MCP-JS: Starting poller for {device_info.get('name', 'Unknown')} ({dev_path})")

    bindings = InputBindings(device_info, state)
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

                input_changes = bindings.changes(previous_events, current_events)
                if not previous_events:
                    previous_events = current_events
                    print(f"MCP-JS: Initial state captured for {dev_path}. Listening for changes...")
                else:
                    action = bindings.action(previous_events, current_events, input_changes)
                    if action:
                        if state.is_sam_running() or state.is_sam_starting():
                            # SAM is active — log and route through full action handler.
                            if not state.samdebug:
                                print(f"MCP-JS: Button action '{action}' detected on {dev_path}")
                            loop.call_soon_threadsafe(handle_action, action, state, loop, "joystick")
                        else:
                            # User is playing normally — just reset the idle timer
                            # so SAM doesn't launch on an active player.
                            state.update_activity(log_event=False)
                    elif bindings.has_activity(previous_events, current_events, input_changes):
                        # A mapped analog control is moving toward its digital edge.
                        state.update_activity(log_event=False)

                if state.samdebug and previous_events:
                    bindings.report(previous_events, current_events, input_changes)
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


class IdleCountdownDisplay:
    """One updating terminal line; no countdown while launch is disallowed."""
    def __init__(self):
        self.previous = None

    def update(self, remaining=None):
        if remaining is None:
            if self.previous is not None:
                print('\r' + ' ' * 48 + '\r', end='', flush=True)
            self.previous = None
            return
        seconds = max(0, math.ceil(remaining))
        if seconds != self.previous:
            print(('\rMCP: Starting SAM in %ds...' % seconds).ljust(48), end='', flush=True)
            self.previous = seconds


async def idle_and_status_checker(state):
    countdown = IdleCountdownDisplay()
    while True:
        try:
            owner = await asyncio.to_thread(read_sam_owner)
            if state.is_stopping():
                countdown.update()
                await asyncio.sleep(1)
                continue
            state.set_sam_running(owner is not None)
            if owner:
                countdown.update()
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
                    countdown.update()
                    await launch_and_confirm(state)
                elif can_start:
                    countdown.update(state.idle_timeout - idle_time)
                else:
                    countdown.update()
            await asyncio.sleep(1)
        except asyncio.CancelledError:
            countdown.update()
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
                        elif re.fullmatch(r'event\d+', handler):
                            current_device['event_path'] = f"/dev/input/{handler}"

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

class InputHotplugFilter:
    """Ignore software virtual input churn; retain classification for DELETE.

    Only direct /devices/virtual/input nodes are software virtual here. Bluetooth
    UHID can live below /devices/virtual/misc/uhid and must remain observable.
    A CREATE always rechecks identity, since event/js numbers can be reused.
    """
    node_pattern = re.compile(r'(?:event|js|mouse)\d+|mice')

    def __init__(self, prime=True):
        self.known = {}
        if prime:
            self.refresh()

    @classmethod
    def classify(cls, path):
        if path.startswith('/dev/input/by-path/'):
            path = os.path.realpath(path)
        name = os.path.basename(path)
        if os.path.dirname(path) != '/dev/input' or not cls.node_pattern.fullmatch(name):
            return None
        sysfs = '/sys/class/input/%s/device' % name
        if not os.path.exists(sysfs):
            return None  # Unknown/racing creation: preserve physical hotplug.
        target = os.path.realpath(sysfs)
        return target.startswith('/sys/devices/virtual/input/')

    def refresh(self):
        paths = []
        try:
            paths.extend('/dev/input/' + name for name in os.listdir('/sys/class/input')
                         if self.node_pattern.fullmatch(name))
        except OSError:
            pass
        try:
            paths.extend('/dev/input/by-path/' + name for name in os.listdir('/dev/input/by-path'))
        except OSError:
            pass
        for path in paths:
            classification = self.classify(path)
            if classification is not None:
                self.known[path] = classification

    def should_rescan(self, line):
        parts = line.split()
        if len(parts) < 2:
            return False
        path, event = parts[0], parts[1].split(',')[0]
        if event not in ('CREATE', 'DELETE'):
            return False
        direct = os.path.dirname(path) == '/dev/input' and self.node_pattern.fullmatch(os.path.basename(path))
        if not direct and not path.startswith('/dev/input/by-path/'):
            return False
        if event == 'CREATE':
            # Never apply an old virtual classification to a new physical node.
            self.known[path] = self.classify(path)
        elif path not in self.known:
            self.known[path] = self.classify(path)
        return self.known[path] is not True


async def hotplug_monitor_native(state, controller_config, listen_config, loop):
    """Monitors for device hotplug events using the 'inotifywait' utility."""
    print("MCP: Hot-plug monitor started (event-driven via inotifywait; software virtual nodes ignored).")

    # We watch /dev/input recursively and then filter for 'by-path' events in our loop.
    # This is the most reliable way to handle the 'by-path' directory being deleted and recreated.
    cmd = [
        'inotifywait', '-m', '-r', '-q', '--format', '%w%f %e',
        '-e', 'create', '-e', 'delete', '/dev/input'
    ]

    process = await asyncio.create_subprocess_exec(*cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    hotplug_filter = InputHotplugFilter()

    debounce_timer = None
    debounce_delay = 2.0  # seconds to wait after the last event

    async def rescan_after_physical_hotplug():
        hotplug_filter.refresh()
        await rescan_devices(state, controller_config, listen_config, loop)

    try:
        while True:
            try:
                # Asynchronously read a line of output from inotifywait
                line = await process.stdout.readline()
                if not line:
                    print("MCP: inotifywait process exited. Hotplug monitor stopping.")
                    break # Process has exited

                decoded_line = line.decode().strip()

                is_relevant = hotplug_filter.should_rescan(decoded_line)

                if is_relevant:
                    # A physical device change was detected. Trigger a debounced rescan.
                    if debounce_timer:
                        debounce_timer.cancel()
                    print(f"MCP: Hot-plug event detected ({decoded_line}). Scheduling rescan...")
                    debounce_timer = loop.call_later(debounce_delay, lambda: asyncio.create_task(rescan_after_physical_hotplug()))

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

    # Kept for existing watcher signatures; legacy js-index JSON no longer routes actions.
    controller_config = {}
    print("MCP: Controller definitions: MiSTer global map -> controllerdb -> generic activity.")

    # 2. Initialize state
    state = SamState(timeout=timeout, menu_only=menu_only)
    state.samdebug = config.get("DEFAULT", "samdebug", raw=True, fallback="no").strip('"\'').lower() in ("yes", "true", "1", "on")
    if state.samdebug:
        state.input_debug_output = InputDebugOutput()
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
    finally:
        if state.input_debug_output is not None:
            state.input_debug_output.close()

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
