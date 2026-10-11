#!/usr/bin/env python3
import asyncio
import math
import fcntl
import glob
import queue
import re
import os
import signal
import select
import subprocess
import struct
import time
import json
import threading
import sys

# Also support import-by-path integrations that do not add this directory.
SCRIPT_IMPORT_DIR = os.path.dirname(os.path.realpath(__file__))
if SCRIPT_IMPORT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_IMPORT_DIR)
from sam import session as session_records
from sam.coordinator import CoordinatorDependencies, LifecycleCoordinator
from sam.commands import CommandGateway
from sam.config_reload import IniWatcher, bounded_bytes, parse_ini
from sam.menu_session import active as menu_session_active
from sam.autostart import EmptySelectionGuard
from sam.input_options import InputOptions
from sam.mcp_console import MCPConsole, HELP_TEXT as MCP_HELP_TEXT
from sam.diagnostics import DiagnosticLog

# --- Configuration (from Script 1) ---
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
SAM_BASE_PATH = os.environ.get('SAM_ROOT', '/media/fat/Scripts/.MiSTer_SAM')
SAM_ON_SCRIPT = os.environ.get('SAM_ENTRY', '/media/fat/Scripts/MiSTer_SAM_on.sh')
INI_FILE = os.environ.get('SAM_INI', '/media/fat/Scripts/MiSTer_SAM.ini')
CONTROLLER_CONFIG_FILE = os.path.join(SAM_BASE_PATH, "sam_controllers.json")
SAM_SESSION_NAME = "SAM"
SAM_RUNTIME_ROOT = os.environ.get('SAM_TMP_ROOT', '/tmp/.SAM_tmp')
SAM_OWNER_FILE = os.path.join(SAM_RUNTIME_ROOT, 'session-owner')
CORENAME_FILE = "/tmp/CORENAME"
PROC_ROOT = "/proc"
SAM_STATE_FILE = os.environ.get('SAM_STATE_FILE', '/tmp/SAM_state')
_empty_selection_guard = None
_empty_selection_announced = None
_monitor_was_attached = False
_monitor_keyboard_until = 0
_diagnostic_log = None


def empty_selection_blocked():
    global _empty_selection_guard, _empty_selection_announced
    if _empty_selection_guard is None:
        _empty_selection_guard = EmptySelectionGuard(
            INI_FILE, os.path.join(os.environ.get('SAM_LIST_ROOT', '/media/fat/SAM'), 'Gamelists'),
            SAM_BASE_PATH, SAM_RUNTIME_ROOT)
    blocked = _empty_selection_guard.poll()
    if blocked and _empty_selection_announced != _empty_selection_guard.marker:
        print('MCP: No eligible games. Autostart suspended until settings/catalogues change or m start is used.')
        _empty_selection_announced = _empty_selection_guard.marker
    elif not blocked:
        _empty_selection_announced = None
    return blocked


def mcp_monitor_active():
    global _monitor_was_attached, _monitor_keyboard_until
    attached=menu_session_active(os.path.join(SAM_RUNTIME_ROOT,'mcp-console-keyboard.lock'))
    if _monitor_was_attached and not attached:
        _monitor_keyboard_until=time.monotonic()+1.2
    _monitor_was_attached=attached
    return attached or time.monotonic()<_monitor_keyboard_until


def diagnostic_event(component,event,owner='',**fields):
    if _diagnostic_log is not None:
        _diagnostic_log.emit(component,event,owner,**fields)
M82_PHASE_FILE = os.path.join(SAM_RUNTIME_ROOT, 'm82_phase')  # "bios" or "game", written by pick_rom()

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
        self.closed = threading.Event()
        self.drop_lock = threading.Lock()
        self.thread = threading.Thread(target=self.run, name='sam-input-debug', daemon=True)
        self.thread.start()

    def emit(self, message):
        if self.closed.is_set():
            return
        try:
            self.messages.put_nowait(message)
        except queue.Full:
            with self.drop_lock:
                self.dropped += 1

    def is_alive(self):
        return not self.closed.is_set() and self.thread.is_alive()

    def run(self):
        while not self.closed.is_set():
            try:
                message = self.messages.get(timeout=.25)
            except queue.Empty:
                continue
            if message is None:
                return
            try:
                with self.drop_lock:
                    count, self.dropped = self.dropped, 0
                if count:
                    print('MCP-INPUT: debug output overflow; dropped=%d' % count, flush=True)
                print(message, flush=True)
            except (OSError, ValueError):
                self.closed.set()
                return  # Terminal closure must not affect input/action handling.

    def close(self):
        # A full queue cannot discard the close request and strand this thread.
        self.closed.set()


def input_debug(state, message):
    output = getattr(state, 'input_debug_output', None)
    if state.samdebug and output is not None:
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
        # Up to 255 buttons and 255 axes fit the joydev count ioctls. A
        # conservative fallback still captures all startup records if metadata
        # querying fails; the kernel only copies records actually available.
        self.snapshot_bytes = 510 * JS_EVENT_SIZE
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
        # Setup carries exact map/DB identity once; press labels are cached.
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
                self.snapshot_bytes = max(JS_EVENT_SIZE, (nb + na) * JS_EVENT_SIZE)
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
            prefix = 'DOWN MiSTer=%s DB=%s js_button=%d Linux=%d %s' % (
                mister, db, number, code, input_code_text(code))
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
        # Compare keyed INIT state, not positional records: an extra queued
        # event or reordered sample must not hide a real button transition.
        # Only changed controls need scanning, even on large adapters.
        fallback = 'default' if any(
            (kind == BUTTON_TYPE and after == 1) or
            (kind == AXIS_TYPE and number not in self.role_axes and
             abs(after - before) > AXIS_DEADZONE)
            for (kind, number), before, after in changes) else None
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
                text = self.button_labels.get(number,
                    'DOWN MiSTer=unavailable DB=unavailable js_button=%d Linux=unknown' % number)
                action = self.actions.get(('button', number, ''), 'default')
                self.log('%s source=%s action=%s detection=%s' %
                         (text, self.source, action, 'enabled' if self.state.listenjoy else 'disabled'))
            elif kind == AXIS_TYPE and abs(after - before) > AXIS_DEADZONE:
                code = self.axes[number] if number < len(self.axes) else None
                edge = 768 + code * 2 + int(after > 0) if code is not None and abs(after) > 16384 else 0
                text = 'AXIS value=%d MiSTer=%s DB=%s' % (after, self.map_labels(edge), self.axis_labels.get(number, 'unavailable'))
                action = 'activity'
                for half, sign in (('+', 1), ('-', -1)):
                    if before * sign <= 16384 < after * sign:
                        action = self.actions.get(('axis', number, half), action)
                if action == 'activity' and number not in self.role_axes:
                    action = 'default'
                text += ' js_axis=%d ABS=%s source=%s action=%s' % (number, code, self.source, action)
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
        self._busy_next_owner = None    # Only a verified ordinary Next/Ignore
        self._pending_menu_stop = False # Coalesced Stop while that command runs
        self._start_time = 0            # When start_sam() was triggered
        self.m82 = False
        self.ignore_when_skip = False
        self.listenjoy = True
        self.listenkeyboard = True
        self.listenmouse = True
        self.input_options = None
        self.console_lock = None
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
            log_activity = self._log_activity and log_event
        # Slow terminal output must never hold the state lock or delay Stop.
        if log_activity:
            input_debug(self, "MCP: Activity detected, idle timer reset.")

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
        input_debug(self, f"MCP: SAM is starting up. Buffered '{action}' action.")

    def consume_pending_action(self):
        """Atomically read and clear the pending action. Thread-safe."""
        with self._lock:
            action = self._pending_action
            self._pending_action = None
            return action

    def set_busy_next_owner(self, owner):
        """Permit one higher-priority Menu Stop for this verified command."""
        with self._lock:
            self._busy_next_owner = owner
            self._pending_menu_stop = False

    def queue_busy_menu_stop(self):
        with self._lock:
            if self._busy_next_owner is None:
                return False
            self._pending_menu_stop = True
            return True

    def consume_busy_menu_stop(self):
        """Clear every command token, returning only a requested Stop owner."""
        with self._lock:
            owner = self._busy_next_owner if self._pending_menu_stop else None
            self._busy_next_owner = None
            self._pending_menu_stop = False
            return owner

    def set_mode(self, m82: bool, ignore_when_skip: bool, listenjoy: bool):
        """Store SAM mode flags read from INI. Thread-safe."""
        with self._lock:
            self.m82 = m82
            self.ignore_when_skip = ignore_when_skip
            self.listenjoy = listenjoy
# --- Core SAM Functions (from Script 1) ---
# These are blocking and will be run in threads

def read_literal_file(path):
    return session_records.read_literal_file(path)


def read_sam_owner():
    snapshot = session_records.read_session(SAM_OWNER_FILE, PROC_ROOT)
    return snapshot.as_record() if snapshot else None


def owner_key(owner):
    return session_records.owner_key(owner)


def session_is_m82(owner, configured):
    return session_records.session_is_m82(owner, configured, read_literal_file(SAM_STATE_FILE))


def lifecycle_coordinator(input_device=None):
    """Bind platform callbacks at the compatibility boundary, never in readers."""
    def report(component,event,owner='',**fields):
        # Routine idle activity is not a session failure or command decision.
        if event=='owner_missing' or (event=='action_received' and not owner and fields.get('routing')=='dispatch'):
            return
        if input_device:
            fields['device']=input_device
        diagnostic_event(component,event,owner,**fields)
    return LifecycleCoordinator(CoordinatorDependencies(
        read_sam_owner=read_sam_owner,
        is_in_menu=is_in_menu,
        session_is_m82=session_is_m82,
        skip_game=skip_game,
        ignore_game=ignore_game,
        read_m82_phase=read_m82_phase,
        play_m82_game=play_m82_game,
        unmute_sam=unmute_sam,
        stop_sam=stop_sam,
        is_sam_running=is_sam_running,
        start_sam=start_sam,
        cancel_launcher=cancel_launcher,
        kill_sam_processes=kill_sam_processes,
        menu_active=menu_session_active,
        empty_selection_blocked=empty_selection_blocked,
        monitor_active=mcp_monitor_active,
        diagnostic=report,
    ))


def is_sam_running():
    return read_sam_owner() is not None


def start_sam(state, target=None):
    """Keep the launcher so cancellation is a barrier against late starts."""
    print("Idle timeout reached. Starting SAM...")
    state.launcher = command_gateway().launch_start(*([target] if target else []), if_idle=True)


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


async def exit_to_menu_with_retry(state, owner=None):
    """Compatibility boundary: the shared shell lifecycle owns Menu/audio retries."""
    result = await asyncio.to_thread(command_gateway().execute, "stop", owner=owner)
    if not result:
        print("MCP: Menu stop refused or failed; audio restoration remains owned by SAM.")
    return result


async def stop_sam(state, play_current=False, owner=None):
    """Use the shared gateway; leave hardware ordering to the owned backend."""
    try:
        if play_current:
            result = await asyncio.to_thread(command_gateway().execute, "exit_to_game", owner=owner)
            if not result:
                print("MCP: Keep-game stop refused or failed.")
            return result
        return await exit_to_menu_with_retry(state, owner=owner)
    except Exception as error:
        print(f"MCP: Error during stop_sam: {error}")
        return False


def command_gateway():
    return CommandGateway(owner_reader=read_sam_owner, entrypoint=SAM_ON_SCRIPT, root=SAM_BASE_PATH)


def skip_game(owner=None):
    """Sends a skip command to the running SAM session."""
    print("User pressed 'Next'. Skipping to next game...")
    return command_gateway().execute("next", owner=owner)

def ignore_game(owner=None):
    """Adds the current game to the ignore list."""
    print("MCP: Ignoring current game...")
    return command_gateway().execute("control", "ignore", owner=owner)

def unmute_sam(owner=None):
    """Calls the SAM unmute routine."""
    if owner is not None and owner_key(read_sam_owner()) != owner_key(owner):
        return False
    print("MCP: Unmuting...")
    return command_gateway().execute("unmute", owner=owner)

def read_m82_phase() -> str:
    """Returns 'bios', 'game', or 'unknown' based on the phase file written by pick_rom()."""
    try:
        with open(M82_PHASE_FILE, 'r') as f:
            return f.read().strip()
    except Exception:
        return "unknown"

def play_m82_game(owner=None):
    """Signals M82 to enter play mode: extends the countdown timer and unmutes audio."""
    print("MCP-M82: Sending play signal ('y') to SAM session...")
    return command_gateway().execute("m82_play", owner=owner)

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
    return command_gateway().execute("stop_owner", owner=owner)


def handle_action(action, state, loop, source="keyboard", input_device=None):
    return lifecycle_coordinator(input_device).handle_action(action, state, loop, source)


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
            with open(dev_path, "rb", buffering=0) as f:
                os.set_blocking(f.fileno(), False)
                data = f.read(bindings.snapshot_bytes)
            if data:
                current_events = [dict(zip(("timestamp", "value", "type", "number"), struct.unpack(JS_EVENT_FORMAT, data[i:i+JS_EVENT_SIZE]))) for i in range(0, len(data), JS_EVENT_SIZE) if len(data[i:i+JS_EVENT_SIZE]) == JS_EVENT_SIZE]

                input_changes = bindings.changes(previous_events, current_events)
                if not previous_events:
                    previous_events = current_events
                    print(f"MCP-JS: Initial state captured for {dev_path}. Listening for changes...")
                else:
                    action = bindings.action(previous_events, current_events, input_changes)
                    if action and state.listenjoy:
                        if state.is_sam_running() or state.is_sam_starting():
                            # SAM is active — log and route through full action handler.
                            loop.call_soon_threadsafe(handle_action, action, state, loop, "joystick", dev_path)
                        else:
                            # User is playing normally — just reset the idle timer
                            # so SAM doesn't launch on an active player.
                            state.update_activity(log_event=False)
                    elif state.listenjoy and bindings.has_activity(previous_events, current_events, input_changes):
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

def byte_activity_poller_thread(device_path, state, loop, stop_event, label):
    """Observe the existing hidraw/mouse byte interface without stuck readers.

    select observes report readiness immediately; its timeout only bounds idle
    cancellation. No exclusive grab or evdev event backend is introduced.
    """
    print(f"MCP-{label}: Starting poller for {device_path}")
    while not stop_event.is_set():
        try:
            with open(device_path, "rb", buffering=0) as f:
                os.set_blocking(f.fileno(), False)
                while not stop_event.is_set():
                    ready, _, _ = select.select([f], [], [], .25)
                    if not ready:
                        continue
                    # Cancellation may race readiness. Never dispatch an input
                    # from a removed reader after a replacement was registered.
                    if stop_event.is_set():
                        break
                    try:
                        report = f.read(64 if label == 'Keyboard' and state.samdebug else 1)
                    except BlockingIOError:
                        continue
                    if report is None:
                        continue
                    if not report:
                        return  # disconnected/EOF, not a busy retry loop
                    gate = 'listenkeyboard' if label == 'Keyboard' else 'listenmouse'
                    enabled = getattr(state, gate, True)
                    if enabled:
                        loop.call_soon_threadsafe(handle_action, "default", state, loop,
                                                 'keyboard' if label=='Keyboard' else 'mouse', device_path)
                    if state.samdebug:
                        input_debug(state, 'MCP-INPUT: %s device=%s report=%s source=generic action=default detection=%s (raw activity; key/button names unavailable)' %
                                    (label, device_path, report[:64].hex(), 'enabled' if enabled else 'disabled'))
                    # Retain the existing flood debounce and reopen semantics,
                    # but allow cancellation to interrupt the wait.
                    stop_event.wait(1)
                    break
        except FileNotFoundError:
            print(f"MCP-{label}: Device {device_path} disconnected. Stopping poller.")
            break
        except Exception as e:
            print(f"MCP-{label}: Error in poller for {device_path}: {e}")
            break
    print(f"MCP-{label}: Poller for {device_path} stopped.")


def keyboard_poller_thread(device_path, state, loop, stop_event):
    byte_activity_poller_thread(device_path, state, loop, stop_event, "Keyboard")


def mouse_poller_thread(device_path, state, loop, stop_event):
    byte_activity_poller_thread(device_path, state, loop, stop_event, "Mouse")


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
                        if state.listenkeyboard:
                            loop.call_soon_threadsafe(handle_action, "default", state, loop,'remote_keyboard')

                        # Debounce for 1 second to prevent event floods from mashing
                        stop_event.wait(1)

                        # After waking up, jump to the end of the file again
                        # to discard any queued inputs that piled up during sleep
                        f.seek(0, os.SEEK_END)

        except Exception as e:
            print(f"MCP-RemoteLog: Transient error tailing {log_path}: {e}")
            stop_event.wait(1)

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
                    loop.call_soon_threadsafe(handle_action, "zaparoo", state, loop,'zaparoo')
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
    return lifecycle_coordinator().menu_requires_stop(state, owner, in_menu, now)


async def launch_and_confirm(state, target=None):
    if target is None:
        return await lifecycle_coordinator().launch_and_confirm(state)
    return await lifecycle_coordinator().launch_and_confirm(state, target)


async def reload_live_config(state, owner):
    watcher = getattr(state, 'config_watcher', None)
    if watcher is None:
        return
    try:
        values = await asyncio.to_thread(watcher.poll, owner)
        state.config_reload_error = None
    except (OSError, ValueError, UnicodeError, TypeError) as error:
        message = str(error)
        if getattr(state, 'config_reload_error', None) != message:
            print('MCP: INI reload deferred: ' + message)
            state.config_reload_error = message
        return
    if values is None:
        return
    enabled = lambda key, default='yes': str(values.get(key, default)).lower() in ('yes', 'true', '1', 'on')
    base = {key: enabled(key) for key in ('listenjoy', 'listenkeyboard', 'listenmouse')}
    base['samdebug']=enabled('samdebug','no')
    if state.input_options is None:state.input_options=InputOptions(base)
    else:state.input_options.update_ini(base)
    with state._lock:
        state.idle_timeout = int(values.get('samtimeout', '60'))
        state.menu_only = enabled('menuonly')
        state.ignore_when_skip = enabled('ignore_when_skip', 'no')
        if owner is None:
            state.m82 = enabled('m82', 'no')
    await apply_input_options(state)


async def apply_input_options(state, refresh=False):
    effective=state.input_options.effective()
    old_debug=state.samdebug
    changed=any(getattr(state,key)!=effective[key] for key in effective)
    with state._lock:
        for key,value in effective.items():setattr(state,key,value)
    output=state.input_debug_output
    recover=state.samdebug and (output is None or not output.is_alive())
    if recover:state.input_debug_output=InputDebugOutput()
    elif not state.samdebug and output is not None:
        output.close();state.input_debug_output=None
    if changed or refresh or recover:
        state.config_listeners.update({key:effective[key] for key in ('listenjoy','listenkeyboard','listenmouse')})
        rebuild=refresh or (state.samdebug and not old_debug) or recover
        if rebuild:
            with state.input_metadata_lock:state.input_database=None
        loop=asyncio.get_running_loop()
        if rebuild:await rescan_devices(state,state.config_controllers,state.config_listeners,loop,rebuild_joysticks=True)
        else:await rescan_devices(state,state.config_controllers,state.config_listeners,loop)
        remote = tasks.get('/tmp/remote.log')
        if (state.listenkeyboard or state.samdebug) and (remote is None or remote[0].done()):
            await watch_remote_log('/tmp/remote.log', state, loop)
        elif not state.listenkeyboard and not state.samdebug and remote:
            task, event = tasks.pop('/tmp/remote.log')
            if event: event.set()
            task.cancel()


def console_status(state):
    show=lambda key:'ON' if getattr(state,key) else 'OFF'
    print('MCP monitor: Keyboard=%s Joystick=%s Mouse=%s Debug=%s | temporary=%s' %
          (show('listenkeyboard'),show('listenjoy'),show('listenmouse'),show('samdebug'),
           ','.join({'listenkeyboard':'keyboard','listenjoy':'joystick','listenmouse':'mouse','samdebug':'debug'}[key]
                    for key in sorted(state.input_options.overrides)) or 'none'),flush=True)
    readers=[path for path,(task,_) in tasks.items() if path.startswith('/dev/') and not task.done()]
    print('Physical MCP readers: joystick=%d keyboard=%d mouse=%d. Debug can observe devices whose detection is OFF.' %
          (sum(path.startswith('/dev/input/js') for path in readers),
           sum(path.startswith('/dev/hidraw') for path in readers),
           sum(re.fullmatch(r'/dev/input/mouse\d+',path) is not None for path in readers)),flush=True)
    print('Physical keyboard actions: %s.' % ('reserved for local console monitor' if mcp_monitor_active()
                                            else 'enabled when detection is ON; SSH monitor does not suppress them'),flush=True)


async def console_command(state,key):
    async with state.console_lock:
        state.update_activity(log_event=False)
        if key=='q':
            try:
                result=await asyncio.to_thread(subprocess.run,
                    ['tmux','detach-client','-s','=MCP'],capture_output=True,text=True,timeout=2)
                if result.returncode:print('MCP: No attached monitor to detach; MCP keeps running.',flush=True)
            except (OSError,subprocess.TimeoutExpired) as error:print('MCP: Detach failed: '+str(error),flush=True)
            return
        if key in ('h','?'):
            print(MCP_HELP_TEXT,flush=True)
            print('Toggles last until MCP restarts, R restores INI; changing that INI option also replaces its temporary override.',flush=True)
            console_status(state);return
        if key=='r':
            values=await asyncio.to_thread(read_ini_values,INI_FILE,SAM_RUNTIME_ROOT)
            enabled=lambda name,default='yes':str(values.get(name,default)).lower() in ('yes','true','1','on')
            base={name:enabled(name) for name in ('listenjoy','listenkeyboard','listenmouse')}
            base['samdebug']=enabled('samdebug','no')
            state.input_options.update_ini(base);state.input_options.reset()
            await apply_input_options(state,refresh=True)
        else:
            option={'k':'listenkeyboard','j':'listenjoy','m':'listenmouse','d':'samdebug'}.get(key)
            if option is None:return
            state.input_options.toggle(option)
            await apply_input_options(state)
        console_status(state)


def read_ini_values(ini,runtime):
    values=parse_ini(bounded_bytes(ini))
    values.update(parse_ini(bounded_bytes(os.path.join(runtime,'gameroulette.ini'))))
    return values


async def restart_config_at_boundary(state, owner):
    if not owner or state.is_stopping() or state.is_sam_starting() or menu_session_active():
        return False
    root = os.path.dirname(SAM_OWNER_FILE)
    path = os.path.join(root, 'session-%s:%s' % owner_key(owner), 'config-boundary')
    receipt = await asyncio.to_thread(read_literal_file, path)
    if (receipt.get('pid'), receipt.get('start')) != owner_key(owner):
        return False
    target = receipt.get('target', '')
    if target and not re.fullmatch('[a-z0-9_]+', target):
        return False
    update = await asyncio.to_thread(read_literal_file, os.path.join(os.path.dirname(path), 'config-update'))
    if update.get('structural') != '1' or update.get('revision') != receipt.get('revision'):
        return False
    if getattr(state, 'config_boundary_error', None) == receipt.get('revision'):
        return True
    with state._lock:
        state.config_restart_pending = True
        state.config_restart_cancelled = False
    validated = await asyncio.to_thread(command_gateway().execute, 'validate_start', *([target] if target else []))
    if not validated:
        state.config_restart_pending = False
        if getattr(state, 'config_boundary_error', None) != receipt.get('revision'):
            print('MCP: New INI mode/module configuration rejected; current game retained.')
            state.config_boundary_error = receipt.get('revision')
        return True
    if state.is_stopping() or state.config_restart_cancelled or menu_session_active() or owner_key(await asyncio.to_thread(read_sam_owner)) != owner_key(owner):
        state.config_restart_pending = False
        return True
    state.set_stopping(True)
    try:
        stopped = await asyncio.to_thread(command_gateway().execute, 'stop', owner=owner)
    finally:
        state.set_stopping(False)
    # Human Stop/Play arriving during cleanup overrides automatic replacement;
    # ordinary activity/Next does not erase a pending mode change.
    if not stopped or read_sam_owner() is not None:
        state.config_restart_pending = False
        return True
    with state._lock:
        human_input = state.config_restart_cancelled
        state.config_restart_pending = False
    if human_input or menu_session_active():
        state.update_activity(log_event=False)
        return True
    state.m82 = str(state.config_watcher.values.get('m82', 'no')).lower() in ('yes', 'true', '1', 'on')
    await launch_and_confirm(state, target or None)
    return True


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
    observed_running = False
    while True:
        try:
            owner = await asyncio.to_thread(read_sam_owner)
            mcp_monitor_active()  # RAM focus probe, never inside the input poller.
            await reload_live_config(state, owner)
            if state.is_stopping():
                countdown.update()
                await asyncio.sleep(1)
                continue
            # Once per existing checker tick, suppress autostart, external Menu
            # cleanup and mode handoff while the dialog owns the lock.
            if menu_session_active():
                state.update_activity(log_event=False)
                countdown.update()
                await asyncio.sleep(1)
                continue
            if await restart_config_at_boundary(state, owner):
                await asyncio.sleep(1)
                continue
            # CLI stops do not pass through input activity. Give the observed
            # live-to-stopped transition a fresh ordinary inactivity interval.
            # Keep this observation independent of callbacks updating state.
            if observed_running and owner is None:
                state.update_activity(log_event=False)
            observed_running = owner is not None
            state.set_sam_running(observed_running)
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
                if await asyncio.to_thread(empty_selection_blocked):
                    countdown.update()
                    await asyncio.sleep(1)
                    continue
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
                        elif re.fullmatch(r'mouse\d+',handler):
                            current_device['mouse_path']=f'/dev/input/{handler}'

                    # Check for the 'kbd' handler to identify a keyboard
                    if 'kbd' in handlers:
                        current_device['is_keyboard'] = True

    except FileNotFoundError:
        print("MCP: Error - /proc/bus/input/devices not found.")
        return {'joysticks': [], 'keyboards': [], 'mice':[], 'has_mouse': False}
    except Exception as e:
        print(f"MCP: Error parsing /proc/bus/input/devices: {e}")

    if current_device: # Add the last device
        all_devices.append(current_device)

    # --- Process the raw device list ---

    def physical(device):
        # Bluetooth UHID under virtual/misc is physical. Software uinput
        # devices are specifically under virtual/input, not every virtual path.
        return '/devices/virtual/input/' not in device.get('sysfs','')

    joysticks = [
        d for d in all_devices
        if 'js_path' in d
        and "motion sensors" not in d.get('name', '').lower()
        and "zaparoo" not in d.get('name', '').lower()
        and physical(d)
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
        if d.get('is_keyboard') and physical(d) \
                and _usb_parent(d.get('proc_phys', '')) not in joystick_usb_parents:

            # Get the physical address from 'P: Phys='
            phys_addr = d.get('proc_phys')

            if phys_addr:
                # Find the matching hidraw device
                hidraw_path = get_hidraw_for_keyboard(phys_addr)
                if hidraw_path:
                    d['hidraw_path'] = hidraw_path
                    keyboards.append(d)

    mice=[d for d in all_devices if physical(d) and 'mouse_path' in d
          and _usb_parent(d.get('proc_phys','')) not in joystick_usb_parents]
    has_mouse=bool(mice)

    return {'joysticks': joysticks, 'keyboards': keyboards, 'mice':mice,'has_mouse': has_mouse}

async def rescan_devices(state, controller_config, listen_config, loop, rebuild_joysticks=False):
    """Scans all devices and starts/stops monitors as needed."""
    # Use a lock to ensure only one rescan happens at a time.
    global rescan_lock
    if rescan_lock is None:
        rescan_lock = asyncio.Lock()  # bind to the actual asyncio.run loop on Python 3.9
    async with rescan_lock:
        if rebuild_joysticks:
            cancelled=[]
            for path,(task,stop_event) in list(tasks.items()):
                if path.startswith('/dev/input/js'):
                    tasks.pop(path)
                    if stop_event:stop_event.set()
                    task.cancel();cancelled.append(task)
            if cancelled:await asyncio.gather(*cancelled,return_exceptions=True)
        await _rescan_devices_impl(state, controller_config, listen_config, loop)

async def _rescan_devices_impl(state, controller_config, listen_config, loop):
    print("MCP: Rescanning all input devices...")
    try:
        all_current_devices = await asyncio.to_thread(get_input_devices)

        # --- Build sets of current and monitored devices ---
        current_js = set()
        if listen_config.get("listenjoy", True) or state.samdebug:
            current_js = {d['js_path'] for d in all_current_devices['joysticks']}

        current_kbds = set()
        if listen_config.get("listenkeyboard", True) or state.samdebug:
            current_kbds = {d['hidraw_path'] for d in all_current_devices['keyboards']}

        current_mouse = set()
        if listen_config.get('listenmouse',True) or state.samdebug:
            current_mouse={device['mouse_path'] for device in all_current_devices.get('mice',())}

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
            elif dev_path in current_mouse:
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

def initial_settings(values):
    enabled = lambda key, default='yes': str(values.get(key, default)).lower() in ('yes', 'true', '1', 'on')
    return dict(timeout=int(values.get('samtimeout', '60')), menu_only=enabled('menuonly'),
                listen_config={key: enabled(key) for key in ('listenjoy', 'listenkeyboard', 'listenmouse')},
                m82=enabled('m82', 'no'), ignore_when_skip=enabled('ignore_when_skip', 'no'),
                samdebug=enabled('samdebug', 'no'))


def read_initial_settings(ini_path=None, runtime_root=None):
    """Startup uses the same bounded literal parser as live reload.

    Menu helpers write quoted numbers; decoding the literal before int() keeps
    the accompanying mode/listener switches intact. No INI code is executed.
    """
    ini_path = INI_FILE if ini_path is None else ini_path
    runtime_root = SAM_RUNTIME_ROOT if runtime_root is None else runtime_root
    data = bounded_bytes(ini_path, missing=None)
    if data is None:
        raise FileNotFoundError(ini_path)
    values = parse_ini(data)
    values.update(parse_ini(bounded_bytes(os.path.join(runtime_root, 'gameroulette.ini'))))
    return initial_settings(values)


async def main():
    global _diagnostic_log
    _diagnostic_log = DiagnosticLog(SAM_RUNTIME_ROOT)
    try:
        import hashlib
        code_hash=hashlib.sha256(open(__file__,'rb').read(256*1024)).hexdigest()
    except OSError:
        code_hash='unavailable'
    diagnostic_event('mcp','service_start',pid=os.getpid(),code_sha256=code_hash)
    try:
        settings = read_initial_settings()
    except (OSError, ValueError, UnicodeError, TypeError) as error:
        print(f"MCP: Warning - Could not read or parse INI file: {error}")
        print("MCP: Using default values for timeout (60s) and menu_only (True).")
        settings = initial_settings({})
    listen_config = settings['listen_config']

    # Kept for existing watcher signatures; legacy js-index JSON no longer routes actions.
    controller_config = {}
    print("MCP: Controller definitions: MiSTer global map -> controllerdb -> generic activity.")

    # 2. Initialize state
    state = SamState(timeout=settings['timeout'], menu_only=settings['menu_only'])
    state.samdebug = settings['samdebug']
    if state.samdebug:
        state.input_debug_output = InputDebugOutput()
    state.set_mode(m82=settings['m82'], ignore_when_skip=settings['ignore_when_skip'], listenjoy=listen_config["listenjoy"])
    state.config_watcher = IniWatcher(INI_FILE, os.path.dirname(SAM_OWNER_FILE),
                                      os.path.join(os.environ.get('SAM_LIST_ROOT', '/media/fat/SAM'), 'Gamelists'))
    state.config_listeners = listen_config
    state.config_controllers = controller_config
    state.listenkeyboard=listen_config['listenkeyboard']
    state.listenmouse=listen_config['listenmouse']
    state.input_options=InputOptions(dict(listen_config,samdebug=state.samdebug))
    state.console_lock=asyncio.Lock()
    print(f"MCP started. Idle timeout: {state.idle_timeout}s, Menu-only: {state.menu_only}")
    print(f"MCP Listen Config: Joy={listen_config['listenjoy']}, Kbd={listen_config['listenkeyboard']}, Mouse={listen_config['listenmouse']}")

    # 3. Setup asyncio tasks
    tasks['checker'] = (asyncio.create_task(idle_and_status_checker(state)), None)

    loop = asyncio.get_running_loop()
    console_tasks=set()
    def submit_console(key):
        async def command():
            try:await console_command(state,key)
            except Exception as error:print('MCP monitor: '+str(error),flush=True)
        task=loop.create_task(command());console_tasks.add(task)
        task.add_done_callback(console_tasks.discard)
    console=MCPConsole(loop,submit_console)
    if console.start():print(MCP_HELP_TEXT,flush=True)

    # 4. Initial scan for existing devices and start monitoring them
    # The new rescan function handles the initial scan perfectly.
    await rescan_devices(state, controller_config, listen_config, loop)

    # 4.5 Start the remote.log monitor for virtual network inputs
    if listen_config["listenkeyboard"]:
        await watch_remote_log("/tmp/remote.log", state, loop)

    # 4.6 Start the zaparoo NFC tap monitor
    await watch_zaparoo(os.path.join(SAM_RUNTIME_ROOT, 'SAM_Joy_Activity'), state, loop)

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
        console.close()
        for task in tuple(console_tasks):task.cancel()
        if console_tasks:await asyncio.gather(*console_tasks,return_exceptions=True)
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
