"""Optional OLED FIFO delivery must never orphan an owner shell."""
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest
from paths import PACKAGE


class TTYDelivery(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-tty-delivery-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fifo = self.root / 'pipe with spaces and \" quote'
        os.mkfifo(self.fifo)
        self.env = dict(os.environ, TTY_TEST_PIPE=str(self.fifo),
                        TTY_TEST_ROOT=str(self.root), TTY_HELPER=str(PACKAGE / '.MiSTer_SAM/modules/tty-functions.sh'))

    def shell(self, code, helper=None):
        prelude = ('source "$TTY_HELPER"\n' if helper is None else helper + '\n')
        result = subprocess.run(['bash', '-c', prelude + 'TTY_cmd_pipe="$TTY_TEST_PIPE"\n' + code],
                                env=self.env, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr + '\n' + result.stdout)
        return result

    def test_no_receiver_is_bounded_and_silent(self):
        started = time.monotonic()
        result = self.shell('write_to_TTY_cmd_pipe display_info\n')
        self.assertLess(time.monotonic() - started, 3.5)
        self.assertEqual(result.stdout + result.stderr, '')

    def test_missing_fifo_is_optional_success(self):
        self.fifo.unlink()
        result = self.shell('write_to_TTY_cmd_pipe display_info\n')
        self.assertEqual(result.stdout + result.stderr, '')

    def test_real_receiver_gets_literal_payload_and_quoted_path(self):
        messages = []
        def reader():
            with self.fifo.open('r') as stream:
                messages.append(stream.readline())
        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        try:
            self.shell("write_to_TTY_cmd_pipe display_info 'A $HOME; $(touch nope) and spaces'\n")
            thread.join(2)
            self.assertFalse(thread.is_alive())
            self.assertEqual(messages, ['display_info A $HOME; $(touch nope) and spaces\n'])
        finally:
            if thread.is_alive():
                fd = os.open(self.fifo, os.O_WRONLY | os.O_NONBLOCK)
                os.close(fd)
                thread.join(1)

    def test_background_writer_does_not_run_owner_exit_trap(self):
        result = self.shell("""
trap 'printf "%s\n" "$BASHPID" >> "$TTY_TEST_ROOT/exit-trap"' EXIT
printf '%s\n' "$BASHPID"
write_to_TTY_cmd_pipe display_info &
writer=$!;wait "$writer" || true
""")
        self.assertEqual((self.root / 'exit-trap').read_text().strip(), result.stdout.strip())

    def test_missing_fifo_background_does_not_run_owner_cleanup(self):
        self.fifo.unlink()
        result = self.shell("""
trap 'printf "%s\n" "$BASHPID" >> "$TTY_TEST_ROOT/exit-trap"' EXIT
printf '%s\n' "$BASHPID"
write_to_TTY_cmd_pipe display_info &
wait "$!" || true
""")
        self.assertEqual((self.root / 'exit-trap').read_text().strip(), result.stdout.strip())

    def test_background_writer_closes_lock_without_unlocking_owner(self):
        self.shell("""
exec {sam_session_lock_fd}> "$TTY_TEST_ROOT/lock"
flock -x "$sam_session_lock_fd"
write_to_TTY_cmd_pipe display_info &
writer=$!
sleep .1
# The child must not explicitly unlock the shared open-file description.
! flock -n "$TTY_TEST_ROOT/lock" true || exit 1
exec {sam_session_lock_fd}>&-
# A inherited copy must not retain admission while the optional write waits.
flock -w .3 "$TTY_TEST_ROOT/lock" true || exit 1
wait "$writer" || true
""")

    def prepare_shutdown_tmux(self, *, absent=False, replace_marker=False, receiver=True):
        binary = self.root / 'bin'
        binary.mkdir()
        tmux = binary / 'tmux'
        tmux.write_text("""#!/bin/bash
case "$1" in
    list-panes)
        [[ "$TTY_TEST_ABSENT" != yes ]] || exit 1
        printf '$7 1234 9999\n';;
    if-shell)
        printf '%s\n' "$@" > "$TTY_TEST_ROOT/tmux-arguments"
        if [[ "$TTY_TEST_REPLACE" == yes ]]; then
            rm -f "$TTY_TEST_ROOT/sleep marker"
            printf replacement > "$TTY_TEST_ROOT/sleep marker"
        fi
        sleep .2
        : > "$TTY_TEST_ROOT/kill-done";;
    *) exit 99;;
esac
""")
        tmux.chmod(0o755)
        self.env['PATH'] = str(binary) + os.pathsep + self.env['PATH']
        self.env['TTY_TEST_ABSENT'] = 'yes' if absent else 'no'
        self.env['TTY_TEST_REPLACE'] = 'yes' if replace_marker else 'no'
        if not absent and receiver:
            def stop_reader():
                with self.fifo.open('r') as stream:
                    if stream.readline() == 'stop\n':
                        (self.root / 'stop-done').write_text('done')
            thread = threading.Thread(target=stop_reader, daemon=True)
            thread.start()
            def finish_reader():
                if thread.is_alive():
                    fd = os.open(self.fifo, os.O_WRONLY | os.O_NONBLOCK)
                    os.close(fd)
                    thread.join(1)
            self.addCleanup(finish_reader)

    def shutdown_code(self):
        return """
ttyenable=yes;tty_sleepfile="$TTY_TEST_ROOT/sleep marker"
printf original > "$tty_sleepfile"
sam_tty_oled_process_matches(){ [[ "$1" == 1234 ]]; }
"""

    def test_absent_oled_shutdown_does_not_wait_on_stale_fifo(self):
        self.prepare_shutdown_tmux(absent=True)
        started = time.monotonic()
        self.shell(self.shutdown_code() + """
write_to_TTY_cmd_pipe(){ echo unexpected-pipe-write >&2;return 99; }
tty_exit
[[ ! -e "$tty_sleepfile" && ! -e "$TTY_TEST_ROOT/kill-done" ]]
""")
        self.assertLess(time.monotonic() - started, 1)

    def test_shutdown_waits_owned_helpers_and_targets_exact_session(self):
        self.prepare_shutdown_tmux()
        self.shell(self.shutdown_code() + """
tty_exit
[[ -f "$TTY_TEST_ROOT/stop-done" && -f "$TTY_TEST_ROOT/kill-done" && ! -e "$tty_sleepfile" ]]
""")
        arguments = (self.root / 'tmux-arguments').read_text().splitlines()
        self.assertEqual(arguments[:4], ['if-shell', '-F', '-t', '$7'])
        self.assertIn('#{pid},9999', arguments[4])
        self.assertIn('#{pane_pid},1234', arguments[4])
        self.assertEqual(arguments[5], "kill-session -t '$7'")

    def test_missing_stop_receiver_has_short_budget_before_owned_kill(self):
        self.prepare_shutdown_tmux(receiver=False)
        started = time.monotonic()
        self.shell(self.shutdown_code() + """
tty_exit
[[ -f "$TTY_TEST_ROOT/kill-done" && ! -f "$TTY_TEST_ROOT/stop-done" ]]
""")
        self.assertLess(time.monotonic() - started, .9)

    def test_shutdown_preserves_replaced_sleep_marker(self):
        self.prepare_shutdown_tmux(replace_marker=True)
        self.shell(self.shutdown_code() + """
tty_exit
[[ $(<"$tty_sleepfile") == replacement ]]
""")

    def test_term_interrupt_does_not_abandon_shutdown_helpers(self):
        self.prepare_shutdown_tmux()
        self.shell(self.shutdown_code() + """
trap ':' TERM
(sleep .05; kill -TERM "$$") &
tty_exit
[[ -f "$TTY_TEST_ROOT/stop-done" && -f "$TTY_TEST_ROOT/kill-done" ]]
""")

    def test_shutdown_does_not_wait_for_unrelated_async_jobs(self):
        self.prepare_shutdown_tmux(absent=True)
        started = time.monotonic()
        self.shell(self.shutdown_code() + """
sleep 2 >/dev/null 2>&1 &
unrelated=$!
tty_exit
kill "$unrelated";wait "$unrelated" || true
""")
        self.assertLess(time.monotonic() - started, 1)

    def test_standalone_oled_uses_same_bounded_delivery(self):
        text = (PACKAGE / '.MiSTer_SAM/MiSTer_SAM_tty2oled').read_text()
        start = text.index('function write_to_TTY_cmd_pipe()')
        end = text.index('\n}', start) + 2
        helper = text[start:end]
        module = (PACKAGE / '.MiSTer_SAM/modules/tty-functions.sh').read_text()
        module_start = module.index('function write_to_TTY_cmd_pipe()')
        self.assertEqual(helper.strip(), module[module_start:].strip())
        started = time.monotonic()
        self.shell('write_to_TTY_cmd_pipe update_counter\n', helper=helper)
        self.assertLess(time.monotonic() - started, 3.5)


if __name__ == '__main__':
    unittest.main()
