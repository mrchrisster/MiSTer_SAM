"""Only a Scripts-origin foreground owner can complete its first-launch gate."""
import unittest
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from paths import PACKAGE
import test_shell as fixture


class UiStartShell(unittest.TestCase):
    setUp = fixture.Shell.setUp
    shell = fixture.Shell.shell
    assertShell = fixture.Shell.assertShell

    def test_scripts_origin_is_forwarded_to_foreground_but_not_mcp(self):
        self.assertShell('''
sam_session_read_owner(){
    [[ -e "$mrsamtmp/spawned" ]] || return 1
    sam_session_owner_pid=999; sam_session_owner_start=123
}
sam_pid_start(){ sam_proc_start=123; }
sam_core_session_begin(){ :; }; env_check(){ :; }; there_can_be_only_one(){ :; }
timeout(){ shift; "$@"; }
mcp_start(){ printf '%s' "${SAM_START_FROM_UI-unset}" > "$mrsamtmp/mcp-origin"; }
tmux(){
    case "$1" in
        has-session) return 1 ;;
        new-session) printf '%s' "${*: -1}" > "$mrsamtmp/spawn-command"; touch "$mrsamtmp/spawned"; echo 999 ;;
    esac
}
export SAM_START_FROM_UI=1
exec {start_lock_fd}> "$mrsamtmp/test-start.lock"
sam_start_admitted '' 0 || exit 1
[[ $(<"$mrsamtmp/mcp-origin") == unset ]] || exit 2
[[ $(<"$mrsamtmp/spawn-command") == 'SAM_START_FROM_UI=1 exec '* ]] || exit 3
[[ $SAM_START_FROM_UI == 1 ]] || exit 4
''')

    def test_ui_gate_waits_for_real_countdown_and_never_rearms(self):
        self.assertShell('''
sam_session="$mrsamtmp/ui-test"; mkdir -p "$sam_session"
sam_owner="$$:123"; sam_session_started=1; SAM_START_FROM_UI=1
sam_session_ui_handoff_begin || exit 1
grep -q '^state=pending$' "$sam_session/ui-start" || exit 2
video_synced=no; sam_session_ui_handoff_ready 1 || exit 3
grep -q '^state=pending$' "$sam_session/ui-start" || exit 4
video_synced=yes; sam_session_ui_handoff_ready 0 || exit 5
grep -q '^state=pending$' "$sam_session/ui-start" || exit 6
sam_session_ui_handoff_ready 1 || exit 7
grep -q '^state=ready$' "$sam_session/ui-start" || exit 8
original=$(<"$sam_session/ui-start")
sam_session_ui_handoff_ready 0; sam_session_ui_handoff_ready 1
[[ $(<"$sam_session/ui-start") == "$original" ]] || exit 9
''')

    def test_ordinary_start_has_no_gate(self):
        self.assertShell('''
sam_session="$mrsamtmp/ui-test"; mkdir -p "$sam_session"
sam_owner="$$:123"; sam_session_started=1; SAM_START_FROM_UI=0
sam_session_ui_handoff_begin; sam_session_ui_handoff_ready 1
[[ ! -e "$sam_session/ui-start" ]]
''')

    def test_mcp_cannot_inherit_scripts_origin_from_tmux_server(self):
        self.assertShell('''
SAM_START_FROM_UI=1; export SAM_START_FROM_UI
mcp_stop(){ :; }
tmux(){ case "$1" in has-session) return 1;; new-session) printf '%s\\n' "${!#}";; *) return 1;; esac; }
command=$(mcp_start) || exit 1
[[ "$command" == 'SAM_START_FROM_UI=0 exec '* ]]
''')

    def test_scripts_wrapper_marks_only_its_start_command(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'start').write_text('import os; print("ORIGIN=" + os.environ.get("SAM_START_FROM_UI", "missing"))\n')
            result = subprocess.run(['bash', str(PACKAGE / 'MiSTer_SAM_start.sh')],
                                    env=dict(os.environ, SAM_ENTRY=sys.executable), cwd=directory,
                                    text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ORIGIN=1', result.stdout)
