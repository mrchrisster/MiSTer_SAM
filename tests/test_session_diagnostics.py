"""Foreground EXIT evidence without hardware, process waits or persistent writes."""
import unittest
import test_shell


class SessionDiagnostics(unittest.TestCase):
    def setUp(self):
        self.fixture = test_shell.Shell()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def run_session(self, code):
        result = self.fixture.shell(r'''
 sam_cleanup(){ :; }; sam_emit(){ :; }
 sam_diagnostic(){ printf '%s|%s|%s\n' "$@" >> "$SAM_TMP_ROOT/events"; }
 sam_diagnostic_exit(){ printf '%s\n' "$@" > "$SAM_TMP_ROOT/exit"; }
 sam_session_begin
 sam_publish_phase playing
 core=snes gamename='Example Game' rompath='/ROMs/example.sfc'
''' + code)
        record = self.fixture.root / 'tmp' / 'exit'
        return result, record.read_text().splitlines() if record.exists() else []

    def test_unexplained_failure_preserves_original_status_and_selection(self):
        result, record = self.run_session('exit 7')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(record, ['7', 'unexplained_exit', '0', 'playing', 'snes', 'Example Game', '/ROMs/example.sfc'])
        self.assertIn('session ended unexpectedly (status 7)', result.stderr)
        self.assertIn('session_start|mode=', (self.fixture.root/'tmp'/'events').read_text())

    def test_term_is_normal_and_cleanup_does_not_erase_snapshot(self):
        result, record = self.run_session('kill -TERM "$$"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(record[:4], ['0', 'term', '0', 'playing'])
        self.assertNotIn('unexpectedly', result.stderr)

    def test_explicit_cleanup_and_keep_game_are_idempotent(self):
        result, record = self.run_session('sam_exit_reason=keep_game; sam_session_cleanup; sam_session_cleanup; exit 0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(record[:4], ['0', 'keep_game', '0', 'playing'])
        self.assertEqual(record[4:], ['snes', 'Example Game', '/ROMs/example.sfc'])

    def test_cleanup_failure_preserves_exit_status(self):
        result, record = self.run_session('sam_session_cleanup_impl(){ return 9; }; exit 3')
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(record[:3], ['3', 'unexplained_exit', '9'])

    def test_reported_failure_avoids_generic_message(self):
        result, record = self.run_session('sam_exit_reported=1; printf "Specific evidence\\n" > "$sam_session/error"; exit 2')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(record[:3], ['2', 'Specific evidence', '0'])
        self.assertNotIn('unexpectedly', result.stderr)

    def test_child_wrapper_never_records_or_cleans_foreground(self):
        result, record = self.run_session('(sam_session_exit 4) || :; [[ -e "$sam_session/alive" ]]; [[ ! -e "$SAM_TMP_ROOT/exit" ]]; exit 0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(record[:3], ['0', 'completed', '0'])

    def test_failed_diagnostic_helper_cannot_change_exit_status(self):
        result, record = self.run_session('sam_diagnostic_exit(){ return 8; }; exit 6')
        self.assertEqual(result.returncode, 6, result.stderr)
        self.assertEqual(record, [])

    def test_cleanup_failure_remains_visible_after_successful_retry(self):
        result, record = self.run_session('sam_session_cleanup_impl(){ return 9; }; sam_session_cleanup || :; sam_session_cleanup_impl(){ return 0; }; exit 0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(record[:3], ['0', 'completed', '9'])
