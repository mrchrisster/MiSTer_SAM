"""The command caller never initializes a session just to open a UI."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from paths import PACKAGE


@unittest.skipUnless(os.name == 'posix', 'Bash caller integration requires Linux')
class Caller(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-caller-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sam = self.root / '.MiSTer_SAM'
        self.library = self.sam / 'lib'
        self.library.mkdir(parents=True)
        for name in ('caller', 'config', 'core-names', 'menu', 'dispatch', 'monitor',
                     'modules', 'common', 'diagnostics', 'cores'):
            shutil.copyfile(PACKAGE / '.MiSTer_SAM/lib' / (name + '.sh'), self.library / (name + '.sh'))
        (self.library / 'runtime.sh').write_text('echo UNEXPECTED_RUNTIME >&2; return 99\n')
        (self.library / 'data.sh').write_text('echo UNEXPECTED_DATA >&2; return 98\n')
        shutil.copyfile(PACKAGE / 'MiSTer_SAM_on.sh', self.root / 'MiSTer_SAM_on.sh')
        shutil.copyfile(PACKAGE / '.MiSTer_SAM/MiSTer_SAM_menu.sh', self.sam / 'MiSTer_SAM_menu.sh')
        self.ini = self.root / 'MiSTer_SAM.ini'
        self.ini.write_text('gametimer=75\nsamtimeout=15\ncorelist="nes,snes"\n'
                            'm82=Yes\nsamvideo=No\nbgm=Yes\nArtwork_only=Yes\n')
        # Any accidental runtime-volume-path parsing would block on this FIFO.
        os.mkfifo(self.root / 'MiSTer.ini')
        self.env = dict(os.environ, SAM_ROOT=str(self.sam), SAM_INI=str(self.ini),
                        SAM_MISTER_ROOT=str(self.root), SAM_TMP_ROOT=str(self.root / 'ram'),
                        SAM_MENU_TMP_ROOT=str(self.root / 'ui'),
                        SAM_LIST_ROOT=str(self.root / 'lists'), SAM_EXIT_TRACE=str(self.root / 'trace'))
        # Functions work on hosts mounting /tmp noexec. The entry's exec-python
        # gateway path is separately exercised with a real Python fixture.
        self.functions = self.root / 'functions.sh'
        self.env['BASH_ENV'] = str(self.functions)
        (self.sam / 'samctl.py').write_text('import sys; print("GATEWAY:" + " ".join(sys.argv[1:]))\n')
        self.program('tmux', '''case "$1" in
display-message) echo 'SAM $1';;
attach-session) echo ATTACHED;;
*) :;; esac
''')
        self.program('python3', '''case "$1" in
*/menu_session.py) [[ "$2" != hold ]] || echo -;;
*/samctl.py) printf 'GATEWAY:%s\\n' "${*:2}";;
*) :;; esac
''')
        self.program('dialog', 'echo DIALOG_READY >&2; exit 1\n')
        self.program('clear', ':\n')
        with self.functions.open('a') as output:
            output.write('exec(){ if [[ "$1" == tmux ]]; then "$@"; else builtin exec "$@"; fi; }\n')

    def program(self, name, body):
        with self.functions.open('a') as output:
            output.write(name + '(){ (\n' + body + '\n); }\n')

    def run_entry(self, *args, input=None):
        result = subprocess.run(['bash', str(self.root / 'MiSTer_SAM_on.sh'), *args],
                                env=self.env, text=True, input=input, capture_output=True, timeout=5)
        self.assertNotIn('UNEXPECTED_', result.stdout + result.stderr)
        return result

    def test_help_skips_ini_runtime_and_tables(self):
        self.ini.write_text('echo BAD_INI >&2; exit 96\n')
        result = self.run_entry('help')
        self.assertEqual(result.returncode, 2)
        self.assertIn('start -', result.stdout)
        self.assertNotIn('BAD_INI', result.stderr)

    def test_monitor_skips_ini_and_preserves_attachment_route(self):
        self.ini.write_text('echo BAD_INI >&2; exit 96\n')
        result = self.run_entry('monitor')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ATTACHED', result.stdout)
        self.assertNotIn('BAD_INI', result.stderr)
        self.assertIn('monitor_ready', (self.root / 'trace').read_text())

    def test_control_submission_skips_ini_and_runtime(self):
        self.ini.write_text('echo BAD_INI >&2; exit 96\n')
        result = self.run_entry('next')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), 'GATEWAY:next')

    def test_menu_opens_with_unavailable_optional_modules_and_no_mister_ini_read(self):
        result = self.run_entry('menu')
        self.assertEqual(result.returncode, 0, result.stderr)
        trace = (self.root / 'trace').read_text()
        self.assertIn('ui_ready', trace)
        self.assertNotIn('modules_loaded', trace)
        self.assertNotIn('data_initialized', trace)
        self.assertFalse((self.root / 'lists').exists())

    def test_premenu_uses_preferences_and_up_opens_ui_without_session(self):
        result = self.run_entry(input='A')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Start after 15 sec.', result.stdout)
        self.assertIn('Show each game for 75 sec.', result.stdout)
        self.assertNotIn('GATEWAY:start', result.stdout)

    def test_single_core_goes_to_gateway_without_runtime_tables(self):
        self.ini.write_text('echo BAD_INI >&2; exit 96\n')
        result = self.run_entry('nes')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), 'GATEWAY:start nes')

    def test_premenu_and_down_load_configuration_once_without_runtime(self):
        with self.ini.open('a') as config:
            config.write('echo CONFIG_LOADED >&2\n')
        result = self.run_entry(input='B')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Show each game for 75 sec.', result.stdout)
        self.assertIn('GATEWAY:start', result.stdout)
        self.assertEqual(result.stderr.count('CONFIG_LOADED'), 1)
        self.assertIn('ui_ready', (self.root / 'trace').read_text())

    def test_premenu_preserves_trusted_includes_exports_and_conditions(self):
        included = self.root / 'included.ini'
        included.write_text('gametimer=93\n')
        self.ini.write_text('export samtimeout=08\n  source "' + str(included) + '"\n'
                            'if true; then menuonly=No; fi\ncorelist="nes,snes"\n')
        result = self.run_entry(input='A')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Start after 08 sec.', result.stdout)
        self.assertIn('Show each game for 93 sec.', result.stdout)
        self.assertIn('Start only on the menu: No', result.stdout)

    def test_arrow_prefixes_do_not_decrement_countdown(self):
        result = self.run_entry(input='\x1b[A')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Starting SAM in 10 secs.', result.stdout)
        self.assertNotIn('Starting SAM in 9 secs.', result.stdout)
        trace = (self.root / 'trace').read_text()
        self.assertIn('premenu_input_ready', trace)
        self.assertIn('premenu_action_menu', trace)

    def test_closed_input_does_not_start(self):
        result = self.run_entry(input='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('GATEWAY:start', result.stdout)

    def test_complex_preference_uses_trusted_ini_fallback(self):
        self.ini.write_text('gametimer=$((30+45))\nsamtimeout=15\ncorelist="nes,snes"\n')
        result = self.run_entry(input='A')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Show each game for 75 sec.', result.stdout)

    def test_runtime_load_failure_is_returned_for_explicit_maintenance(self):
        result = subprocess.run(['bash', '-c',
            'sam_root=$SAM_ROOT; source "$SAM_ROOT/lib/caller.sh"; sam_caller_paths; sam_caller_require_runtime'],
            env=self.env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 99)
        self.assertIn('UNEXPECTED_RUNTIME', result.stderr)


if __name__ == '__main__': unittest.main()
