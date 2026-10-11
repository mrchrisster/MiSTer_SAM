"""Bounded, event-loop-driven hotkeys for the attached MCP terminal."""
import os
import sys

try:
    import fcntl
    import termios
    import tty
except ImportError:  # A terminal console is available only on Unix hosts.
    fcntl = termios = tty = None


HELP_TEXT = (
    "Hotkeys: k keyboard | j joystick | m mouse | d debug | "
    "r restore INI | h/? help | s scroll (tmux) | q/Ctrl-C detach"
)


class MCPConsole:
    """Call ``on_command`` with a single lowercase hotkey from a TTY.

    Callbacks run synchronously on the supplied loop; the owner schedules any
    asynchronous command work. ``on_close`` is called once after an active
    console closes, including terminal EOF/hangup. No signal handlers change.
    """

    def __init__(self, loop, on_command, stdin=None, on_close=None):
        self.loop = loop
        self.on_command = on_command
        self.stdin = sys.stdin if stdin is None else stdin
        self.on_close = on_close
        self.fd = None
        self.active = False
        self._attrs = None
        self._flags = None
        self._escape = None

    def start(self):
        """Register a TTY reader, returning False for unavailable terminals."""
        if self.active:
            return True
        if termios is None:
            return False
        try:
            fd = self.stdin if isinstance(self.stdin, int) else self.stdin.fileno()
            if not os.isatty(fd):
                return False
            self.fd = fd
            self._attrs = termios.tcgetattr(fd)
            self._flags = fcntl.fcntl(fd, fcntl.F_GETFL)
            # Raw mode makes Ctrl-C a detach key without replacing MCP's
            # external SIGINT/SIGTERM handlers or suspending it on Ctrl-Z.
            tty.setraw(fd, termios.TCSANOW)
            raw_attrs = termios.tcgetattr(fd)
            raw_attrs[1] = self._attrs[1]  # Keep normal newline/output handling.
            termios.tcsetattr(fd, termios.TCSANOW, raw_attrs)
            fcntl.fcntl(fd, fcntl.F_SETFL, self._flags | os.O_NONBLOCK)
            self.loop.add_reader(fd, self._read_ready)
        except (OSError, ValueError, AttributeError, NotImplementedError, RuntimeError):
            self._restore()
            return False
        self._escape = None
        self.active = True
        return True

    def close(self):
        """Unregister input and restore the original terminal and fd flags."""
        was_active = self.active
        self.active = False
        if was_active:
            try:
                self.loop.remove_reader(self.fd)
            except (OSError, ValueError, RuntimeError):
                pass  # Owner shutdown may already have closed the loop.
        self._restore()
        self._escape = None
        if was_active and self.on_close is not None:
            self.on_close()

    def _restore(self):
        if self.fd is not None:
            if self._attrs is not None:
                try:
                    termios.tcsetattr(self.fd, termios.TCSANOW, self._attrs)
                except (OSError, termios.error):
                    pass  # A hung-up terminal may no longer accept attributes.
            if self._flags is not None:
                try:
                    fcntl.fcntl(self.fd, fcntl.F_SETFL, self._flags)
                except OSError:
                    pass
        self.fd = self._attrs = self._flags = None

    def _read_ready(self):
        if not self.active:
            return
        try:
            data = os.read(self.fd, 256)
        except (BlockingIOError, InterruptedError):
            return
        except OSError:
            self.close()
            return
        if not data:
            self.close()
            return
        for byte in data:
            if not self.active:
                break
            command = self._key(byte)
            if command is not None:
                self.on_command(command)

    def _key(self, byte):
        # Consume complete ANSI control sequences, even across separate reads.
        # Their payload/final bytes (notably CSI ... m/d) are never hotkeys.
        state = self._escape
        if state == 'string':
            if byte in (7, 0x9c):
                self._escape = None
            elif byte == 27:
                self._escape = 'string_escape'
            return None
        if state == 'string_escape':
            self._escape = None if byte == ord('\\') else 'string'
            return None
        if byte == 27:
            self._escape = 'escape'
            return None
        if state == 'escape':
            if byte == ord('['):
                self._escape = 'csi'
            elif byte == ord('O'):
                self._escape = 'ss3'
            elif byte in (ord(']'), ord('P'), ord('X'), ord('^'), ord('_')):
                self._escape = 'string'
            elif 0x20 <= byte <= 0x2f:
                self._escape = 'escape'  # Charset/designation intermediates.
            else:
                self._escape = None
            return None
        if state in ('csi', 'ss3'):
            if 0x40 <= byte <= 0x7e and byte != ord('['):
                self._escape = None
            return None
        if byte in (0x9b, 0x8f):
            self._escape = 'csi' if byte == 0x9b else 'ss3'
            return None
        if byte in (0x90, 0x98, 0x9d, 0x9e, 0x9f):
            self._escape = 'string'
            return None
        if byte == 3:
            return 'q'
        if 65 <= byte <= 90:
            byte += 32
        if byte == ord('?'):
            return 'h'
        return chr(byte) if byte in b'kjmdrhq' else None
