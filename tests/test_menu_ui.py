"""Linux menu lifetime, terminal/result isolation and startup admission fixtures."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from paths import PACKAGE


@unittest.skipUnless(sys.platform.startswith('linux'), 'Linux Bash/flock required')
class MenuUI(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='sam-menu-ui-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = dict(os.environ, SAM_PACKAGE=PACKAGE.as_posix(),
                        SAM_MENU_TMP_ROOT=str(self.root/'ui'), FIXTURE=str(self.root))
        self.prelude = r'''
source "$SAM_PACKAGE/.MiSTer_SAM/lib/menu.sh"
source "$SAM_PACKAGE/.MiSTer_SAM/lib/lifecycle.sh"
MENU_LOADED=1
mrsampath="$SAM_PACKAGE/.MiSTer_SAM"
mrsamtmp="$FIXTURE/runtime"
python3(){ case "$2" in hold) printf -- '-\n';; release) :;; *) command python3 "$@";; esac; }
'''

    def run_code(self, code):
        return subprocess.run(['bash','-c',self.prelude+code], env=self.env,
                              capture_output=True,text=True,timeout=8)

    def test_concurrent_menu_refuses_before_reading_or_drawing(self):
        first = subprocess.Popen(['bash','-c',self.prelude+r'''
body(){ touch "$FIXTURE/entered"; read -r key; printf 'KEY:%s\n' "$key"; }
sam_menu_run body
'''], env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE,text=True)
        try:
            until=time.monotonic()+3
            while not (self.root/'entered').exists() and time.monotonic()<until: time.sleep(.01)
            self.assertTrue((self.root/'entered').exists())
            second=self.run_code('body(){ echo FORBIDDEN_DRAW; read -r key; }; sam_menu_run body')
            self.assertEqual(second.returncode,2,second.stderr)
            self.assertEqual(second.stdout,'')
            self.assertIn('already open',second.stderr)
            output,error=first.communicate('keep\n',timeout=3)
            self.assertEqual(first.returncode,0,error)
            self.assertEqual(output.strip(),'KEY:keep')
            third=self.run_code('body(){ echo OPENED; }; sam_menu_run body')
            self.assertEqual(third.returncode,0,third.stderr)
            self.assertEqual(third.stdout.strip(),'OPENED')
            self.assertEqual([p.name for p in (self.root/'ui').iterdir()],['menu.lock'])
        finally:
            if first.poll() is None: first.kill();first.communicate(timeout=3)

    def test_dialog_result_fd_is_separate_from_diagnostics(self):
        result=self.run_code(r'''
dialog(){ [[ "$1:$2" == --output-fd:3 ]] || return 9; printf 'next\n' >&3; }
body(){ sam_dialog --menu test 0 0 0 next Next 2> "$sam_menu_file"; cat "$sam_menu_file"; }
sam_menu_run body
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.strip(),'next')
        self.assertEqual(result.stderr,'')

    def test_dialog_error_is_reported_and_does_not_become_a_choice(self):
        result=self.run_code(r'''
dialog(){ echo 'bad dialog option' >&2; return 254; }
body(){ sam_dialog --bad-option 2> "$sam_menu_file"; [[ ! -s "$sam_menu_file" ]]; }
sam_menu_run body
''')
        self.assertEqual(result.returncode,2,result.stderr)
        self.assertIn('SAM dialog failed',result.stderr)
        self.assertIn('bad dialog option',result.stderr)
        self.assertEqual(result.stdout,'')

    def test_escape_without_diagnostics_is_clean_cancellation(self):
        result=self.run_code(r'''
dialog(){ return 255; }
body(){ sam_dialog --menu test 0 0 0; :; }
sam_menu_run body
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stderr,'')

    def test_warning_does_not_turn_escape_into_a_dialog_failure(self):
        result=self.run_code(r'''
dialog(){ echo 'libgpm: harmless terminal warning' >&2; return 255; }
body(){ sam_dialog --menu test 0 0 0; :; }
sam_menu_run body
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stderr,'')

    def test_release_before_exec_and_automatic_start_admission(self):
        result=self.run_code(r'''
sam_start_admitted(){ echo FORBIDDEN_START; }
body(){ sam_start --if-idle || return; sam_menu_release_for_exec || return; sam_menu_lock_active && return 7; }
sam_menu_run body
''')
        # The final lock probe returns 1 (unlocked), which is also body's result.
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertIn('automatic start skipped',result.stdout)
        self.assertNotIn('FORBIDDEN_START',result.stdout)
        self.assertEqual([p.name for p in (self.root/'ui').iterdir()],['menu.lock'])

    def test_explicit_action_unlocks_without_resuming_until_completion(self):
        result=self.run_code(r'''
mkdir -p "$mrsamtmp"; printf owner > "$mrsamtmp/session-owner"
python3(){ case "$2" in hold) echo lease;; release) echo RELEASED;; esac; }
body(){ sam_menu_detach_for_action || return; sam_menu_lock_active && return 7; echo ACTION; }
sam_menu_run body
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.splitlines(),['ACTION','RELEASED'])

    def test_no_owner_needs_no_pause_or_resume_process(self):
        result=self.run_code(r'''
python3(){ echo FORBIDDEN_PYTHON; return 99; }
body(){ echo OPENED; }
sam_menu_run body
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.strip(),'OPENED')

    def test_manual_start_refused_without_stopping_current_session(self):
        result=self.run_code(r'''
sam_start_admitted(){ echo FORBIDDEN_START; }
body(){ sam_start; }
sam_menu_run body
''')
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertIn('Close it before starting',result.stderr)
        self.assertNotIn('FORBIDDEN_START',result.stdout)


if __name__=='__main__': unittest.main()
