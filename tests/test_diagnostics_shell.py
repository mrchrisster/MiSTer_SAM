"""Bash/Python history interoperability, failure retention and bounded RAM IO."""
import json
from pathlib import Path
import sys
import unittest
import test_shell
from paths import PACKAGE
sys.path.insert(0, str(PACKAGE/'.MiSTer_SAM'))
from sam.diagnostics import DiagnosticLog, render_history


class ShellDiagnostics(unittest.TestCase):
    def setUp(self):
        self.fixture = test_shell.Shell()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.directory = self.fixture.root/'tmp/diagnostics'

    def test_failure_remains_after_later_success_and_quoted_data_is_literal(self):
        self.fixture.assertShell(r'''
sam_owner=123:77;sam_mode=samvideo
sam_diagnostic_exit 7 'literal "quote" $(false)' 0 video megacd 'Name with "quotes"' '/ROMs/game.chd'
sam_owner=124:88
sam_diagnostic_exit 0 keep_game 0 playing psx 'Next game' '/ROMs/next.chd'
''')
        failure = json.loads((self.directory/'last-failure.json').read_text())
        latest = json.loads((self.directory/'last-exit.json').read_text())
        self.assertEqual(failure['owner'], '123:77')
        self.assertEqual(failure['fields']['status'], 7)
        self.assertEqual(failure['fields']['reason'], 'literal "quote" $(false)')
        self.assertEqual(latest['owner'], '124:88')
        self.assertIn('reason=keep_game', render_history(self.fixture.root/'tmp'))

    def test_bash_rotation_and_python_append_share_schema_and_lock(self):
        self.directory.mkdir(parents=True)
        seed = (json.dumps(dict(timestamp=0,component='fixture',event='seed',owner='123:77',fields={'detail':'x'*512}))+'\n').encode()
        (self.directory/'events.jsonl').write_bytes(seed*(131072//len(seed)))
        self.fixture.assertShell('''
printf -v detail '%600s' ' ';detail=${detail// /x}
for ((n=0;n<8;n++));do sam_diagnostic decision "$detail" 123:77;done
''')
        inode = (self.directory/'events.lock').stat().st_ino
        self.assertTrue(DiagnosticLog(self.fixture.root/'tmp').emit('mcp', 'input', '123:77', source='keyboard'))
        self.assertEqual((self.directory/'events.lock').stat().st_ino, inode)
        for name in ('events.jsonl', 'events.1.jsonl'):
            data = (self.directory/name).read_bytes()
            self.assertLessEqual(len(data), 131072)
            for line in data.splitlines():
                self.assertLessEqual(len(line)+1, 4096)
                json.loads(line)

    def test_sd_root_and_symlink_failure_do_not_change_session_or_stderr(self):
        result = self.fixture.shell('''
mrsamtmp=/media/fat/forbidden-diagnostic-test
sam_diagnostic decision literal 123:77
printf 'still-running\\n' >&2
''')
        self.assertEqual(result.returncode, 0)
        self.assertIn('still-running', result.stderr)
        self.assertFalse(self.directory.exists())

    def test_debug_uses_bounded_ram_files_and_viewer_opt_in(self):
        self.directory.mkdir(parents=True)
        seed=b'[fixture] debug seed '+b'x'*1000+b'\n'
        (self.directory/'debug.log').write_bytes(seed*(131072//len(seed)))
        self.fixture.assertShell('''
samdebug=no;samdebuglog=yes
printf -v detail '%1800s' ' ';detail=${detail// /x}
for ((n=0;n<8;n++));do samdebug "$detail";done
''')
        for name in ('debug.log', 'debug.1.log'):
            self.assertLessEqual((self.directory/name).stat().st_size, 131072)
        self.assertNotIn('Recent verbose SAM debug', render_history(self.fixture.root/'tmp'))
        self.assertIn('Recent verbose SAM debug', render_history(self.fixture.root/'tmp', verbose=True))

    def test_cleanup_failure_is_retained_even_with_successful_exit_status(self):
        self.fixture.assertShell('sam_owner=123:77;sam_diagnostic_exit 0 term 9 playing nes Game /ROMs/game.nes')
        value = json.loads((self.directory/'last-failure.json').read_text())
        self.assertEqual(value['fields']['cleanup_status'], 9)
