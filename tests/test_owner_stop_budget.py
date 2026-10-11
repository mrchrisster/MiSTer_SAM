"""Stop completion retains a full five-second budget and exact owner safety."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from paths import PACKAGE


class OwnerStopBudget(unittest.TestCase):
    def run_fixture(self, body):
        with tempfile.TemporaryDirectory(prefix='sam-stop-budget-') as directory:
            root = Path(directory)
            (root / 'session-owner').write_bytes(b'pid=321\nstart=77\n')
            prelude = '''
source "$SAM_TEST_LIFECYCLE"
sam_exit_trace(){ :; }
sam_cleanup_failure_pending(){ return 1; }
timeout(){ return 1; }
kill(){ [[ "$*" == '-TERM 321' ]] || return 99; signals=$((signals+1)); }
sleep(){ SECONDS=$((SECONDS+1)); polls=$((polls+1)); }
signals=0 polls=0 SECONDS=0
'''
            env = dict(os.environ, mrsamtmp=root.as_posix(),
                       SAM_TEST_LIFECYCLE=(PACKAGE / '.MiSTer_SAM/lib/lifecycle.sh').as_posix())
            return subprocess.run([os.environ.get('SAM_TEST_BASH', 'bash'), '-c',
                                   'set -e\n' + prelude + body], env=env,
                                  text=True, capture_output=True, timeout=10)

    def test_owner_finishing_in_rounding_second_is_not_reported_timed_out(self):
        result = self.run_fixture('''
# Model starting near the end of a second: the owner exits after the old
# rounded-down boundary, while still within five real seconds of TERM.
sam_pid_start(){ sam_proc_start=77; ((SECONDS<6)); }
there_can_be_only_one 321 77
[[ "$signals:$polls:$sam_exit_expected_owner" == 1:6:321:77 ]]
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_nonexiting_owner_still_has_bounded_wait_and_stop_specific_error(self):
        result = self.run_fixture('''
sam_pid_start(){ sam_proc_start=77; }
! there_can_be_only_one 321 77
[[ "$signals:$polls" == 1:6 ]]
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('did not finish stopping before the timeout', result.stderr)
        self.assertNotIn('start refused', result.stderr)

    def test_pid_reuse_during_wait_does_not_signal_the_replacement(self):
        result = self.run_fixture('''
sam_pid_start(){ if ((SECONDS<2)); then sam_proc_start=77; else sam_proc_start=78; fi; }
there_can_be_only_one 321 77
[[ "$signals:$polls" == 1:2 ]]
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_menu_is_dispatched_while_longer_owned_cleanup_finishes(self):
        result = self.run_fixture('''
sam_exit_menu=1 dispatches=0
sam_menu_delivery_begin(){ :; }
sam_menu_dispatch_quiesced_owner(){ dispatches=$((dispatches+1)); }
sam_pid_start(){ sam_proc_start=77; ((SECONDS<8)); }
there_can_be_only_one 321 77
[[ "$signals:$polls:$dispatches" == 1:8:8 ]]
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_menu_cleanup_budget_remains_bounded(self):
        result = self.run_fixture('''
sam_exit_menu=1
sam_menu_delivery_begin(){ :; }
sam_menu_dispatch_quiesced_owner(){ :; }
sam_pid_start(){ sam_proc_start=77; }
! there_can_be_only_one 321 77
[[ "$signals:$polls" == 1:11 ]]
''')
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
