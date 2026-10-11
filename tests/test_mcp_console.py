"""Private PTYs exercise MCP hotkeys without input devices or live sessions."""
import asyncio
import importlib.util
import os
import signal
import sys
import unittest
from paths import PACKAGE

spec = importlib.util.spec_from_file_location(
    'mcp_console', PACKAGE / '.MiSTer_SAM/sam/mcp_console.py')
console_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(console_module)

if sys.platform != 'win32':
    import fcntl
    import pty
    import termios


@unittest.skipUnless(sys.platform != 'win32', 'Unix private PTYs')
class MCPConsoleTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.master, self.slave = pty.openpty()
        self.attrs = termios.tcgetattr(self.slave)
        self.flags = fcntl.fcntl(self.slave, fcntl.F_GETFL)
        self.commands = []
        self.closed = []
        self.console = console_module.MCPConsole(
            asyncio.get_running_loop(), self.commands.append, self.slave,
            on_close=lambda: self.closed.append(True))
        self.addCleanup(self.cleanup)

    def cleanup(self):
        self.console.close()
        for fd in (self.master, self.slave):
            if fd is not None:
                os.close(fd)

    async def send(self, data):
        os.write(self.master, data)
        # Two scheduling turns allow the selector callback to run.
        await asyncio.sleep(.01)

    async def test_hotkeys_casefold_help_ctrl_c_and_raw_no_echo(self):
        handlers = {sig: signal.getsignal(sig) for sig in
                    (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
        self.assertTrue(self.console.start())
        self.assertTrue(self.console.start())
        attrs = termios.tcgetattr(self.slave)
        self.assertFalse(attrs[3] & (termios.ECHO | termios.ICANON | termios.ISIG))
        self.assertEqual(attrs[1], self.attrs[1])
        await self.send(b'KjMdRh?Q\x03\x1a 12xyz\r\n\xff')
        self.assertEqual(self.commands, list('kjmdrhhqq'))
        self.assertEqual(handlers, {sig: signal.getsignal(sig) for sig in handlers})
        self.console.close()
        self.assertEqual(termios.tcgetattr(self.slave), self.attrs)
        self.assertEqual(fcntl.fcntl(self.slave, fcntl.F_GETFL), self.flags)
        self.assertEqual(self.closed, [True])
        self.console.close()
        self.assertEqual(self.closed, [True])

    async def test_escape_sequences_cannot_trigger_commands_across_reads(self):
        self.assertTrue(self.console.start())
        for sequence in (b'\x1b[A', b'\x1b[1;2D', b'\x1b[31m', b'\x1b[2d',
                         b'\x1bOd', b'\x1b[[D', b'\x1bd', b'\x1b(B',
                         b'\x1b]0;kjmdrhq\x07', b'\x1bPkjmdrhq\x1b\\',
                         b'\x9b31m', b'\x9dkjmdrhq\x9c'):
            for byte in sequence:
                await self.send(bytes((byte,)))
        self.assertEqual(self.commands, [])
        await self.send(b'dm')
        self.assertEqual(self.commands, ['d', 'm'])

    async def test_output_on_same_terminal_does_not_become_input(self):
        self.assertTrue(self.console.start())
        os.write(self.slave, b'\x1b[31mDebug: keyboard/mouse\x1b[0m\r\n')
        await self.send(b'j')
        self.assertEqual(self.commands, ['j'])

    async def test_hangup_unregisters_restores_flags_and_notifies_once(self):
        self.assertTrue(self.console.start())
        os.close(self.master)
        self.master = None
        for _ in range(10):
            if not self.console.active:
                break
            await asyncio.sleep(.01)
        self.assertFalse(self.console.active)
        self.assertEqual(self.closed, [True])
        self.assertEqual(fcntl.fcntl(self.slave, fcntl.F_GETFL), self.flags)

    async def test_close_in_callback_stops_remaining_buffered_commands(self):
        def command(key):
            self.commands.append(key)
            self.console.close()
        self.console.on_command = command
        self.assertTrue(self.console.start())
        await self.send(b'qdm')
        self.assertEqual(self.commands, ['q'])
        self.assertEqual(termios.tcgetattr(self.slave), self.attrs)

    async def test_non_tty_is_untouched(self):
        read_fd, write_fd = os.pipe()
        try:
            flags = fcntl.fcntl(read_fd, fcntl.F_GETFL)
            console = console_module.MCPConsole(
                asyncio.get_running_loop(), self.commands.append, read_fd)
            self.assertFalse(console.start())
            console.close()
            self.assertEqual(fcntl.fcntl(read_fd, fcntl.F_GETFL), flags)
            self.assertEqual(self.commands, [])
        finally:
            os.close(read_fd)
            os.close(write_fd)

    async def test_bounded_read_yields_and_preserves_nonblocking_flags(self):
        os.set_blocking(self.slave, False)
        flags = fcntl.fcntl(self.slave, fcntl.F_GETFL)
        self.assertTrue(self.console.start())
        await self.send(b'k' * 600)
        self.assertEqual(self.commands, ['k'] * 600)
        self.console.close()
        self.assertEqual(fcntl.fcntl(self.slave, fcntl.F_GETFL), flags)

    async def test_registration_failure_restores_terminal_and_flags(self):
        class UnavailableLoop:
            def add_reader(self, *args):
                raise NotImplementedError('no descriptor readers')
        self.console.loop = UnavailableLoop()
        self.assertFalse(self.console.start())
        self.assertEqual(termios.tcgetattr(self.slave), self.attrs)
        self.assertEqual(fcntl.fcntl(self.slave, fcntl.F_GETFL), self.flags)
        self.assertEqual(self.closed, [])


class MCPKeyParserTests(unittest.TestCase):
    def test_ansi_final_bytes_are_consumed(self):
        console = console_module.MCPConsole(None, None)
        sequence = (b'\x1b[A\x1b[31m\x1b[2d\x1bOd\x1b[[D'
                    b'\x1b]kjmdrhq\x07\x1bPkjmdrhq\x1b\\dm')
        commands = [key for byte in sequence
                    if (key := console._key(byte)) is not None]
        self.assertEqual(commands, ['d', 'm'])


if __name__ == '__main__':
    unittest.main()
