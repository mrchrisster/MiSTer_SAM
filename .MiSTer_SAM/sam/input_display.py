"""Latest physical input in MCP's tmux footer; no work in the sampling loop."""
import re
import subprocess
import time


def escape_format(text):
    return ''.join(c for c in str(text) if c >= ' ' and c != '\x7f').replace('#', '##')[:220]


def present_label(value):
    return value if value and value.lower() not in {'unmapped', 'unavailable', 'unassigned', 'unknown'} else ''


def format_activity(message):
    match = re.match(r'^MCP-INPUT: (.*?): DOWN MiSTer=(.*?) DB=(.*?) js_button=(\d+) Linux=(unknown|\d+)(?: ([A-Z][A-Z0-9_]+))?(?: |$)', message)
    if match:
        device, mister, database, index, code, linux = match.groups()
        mister, database = present_label(mister), present_label(database)
        label = (mister or database).upper()
        if label:
            label += ' BUTTON'
        else:
            label = linux or ('BTN_' + code if code != 'unknown' else 'BUTTON ' + index)
        suffix = ' (DB: ' + escape_format(database.upper()) + ')' if database else ''
        return 'MCP-INPUT: %s: #[bold]%s#[nobold] PUSHED%s' % (escape_format(device), escape_format(label), suffix)
    match = re.match(r'^MCP-INPUT: (.*?): AXIS value=([^ ]+)', message)
    if match:
        return 'MCP-INPUT: %s: AXIS MOVED (%s)' % tuple(escape_format(value) for value in match.groups())
    match = re.match(r'^MCP-INPUT: (Keyboard|Mouse) device=([^ ]+) report=([^ ]+)', message)
    if match:
        label, device, report = match.groups()
        # HID raw reports do not provide decoded key names. Do not invent one.
        return 'MCP-INPUT: %s: ACTIVITY (%s; raw %s)' % (label, escape_format(device), escape_format(report))
    return None


class LatestInputLine:
    def __init__(self, attached, runner=None, clock=None):
        self.attached = attached
        self.runner = runner or subprocess.run
        self.clock = clock or time.monotonic
        self.latest = None
        self.written = None
        self.target = None
        self.next_update = 0

    def update(self, message):
        text = format_activity(message)
        if text is None:
            return False
        self.latest = text
        return True

    def flush(self):
        now = self.clock()
        if self.latest is None or now < self.next_update:
            return
        self.next_update = now + .2
        if self.latest == self.written:
            return  # Stable footer: no tmux process or lock probe while idle.
        if not self.attached():
            self.target = None
            self.written = None
            return
        try:
            if self.target is None:
                result = self.runner(['tmux', 'display-message', '-p', '-t', 'MCP', '#{session_name} #{session_id}'],
                                     capture_output=True, text=True, timeout=.5)
                match = re.fullmatch(r'MCP (\$[0-9]+)\s*', result.stdout) if result.returncode == 0 else None
                if not match:
                    return
                self.target = match[1]
            result = self.runner(['tmux', 'set-option', '-t', self.target, '@sam-last-input', self.latest],
                                 capture_output=True, text=True, timeout=.5)
            if result.returncode == 0:
                self.written = self.latest
            else:
                self.target = None
        except (OSError, subprocess.TimeoutExpired):
            self.target = None  # Rendering cannot affect physical input actions.
