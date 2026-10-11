"""Typed catalog exhaustion and explicit retry admission in isolated Bash."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from paths import PACKAGE


class AutostartEmptyShell(unittest.TestCase):
    def setUp(self):
        # Keep the fixture under the workspace so Git Bash sees the same
        # canonical writable path as the Windows sandbox (no short temp alias).
        temp = tempfile.TemporaryDirectory(prefix='sam-empty-', dir=PACKAGE)
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        ini = self.root / 'SAM.ini'
        ini.write_bytes(b'corelist="snes"\ncorelistall="snes"\nrating="no"\n')
        self.env = dict(os.environ, SAM_MODULES_OVERRIDE='', SAM_ROOT=(PACKAGE / '.MiSTer_SAM').as_posix(),
                        SAM_INI=ini.as_posix(), SAM_LIST_ROOT=(self.root / 'lists').as_posix(),
                        SAM_TMP_ROOT=(self.root / 'runtime').as_posix(), SAM_SESSION_LIST_ROOT=(self.root / 'session-lists').as_posix(),
                        SAM_STATE_FILE=(self.root / 'state').as_posix(), SAM_CONFIG_ROOT=(self.root / 'config').as_posix(),
                        SAM_MISTER_ROOT=(self.root / 'media').as_posix(), SAM_GAME_LOG=(self.root / 'games.log').as_posix(),
                        SAM_MENU_TMP_ROOT=(self.root / 'menu').as_posix())

    def check(self, code):
        prelude = '''set -e
source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
# These tests exercise typed outcomes and admission policy. Kernel flock and
# procfs identity behavior have separate native fixtures.
flock(){ :; }
sam_pid_start(){ sam_proc_start=77; }
'''
        result = subprocess.run([os.environ.get('SAM_TEST_BASH', 'bash'), '-c', prelude + code],
                                env=self.env, text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr + '\n' + result.stdout)

    worker = r'''
sam_session_begin
: > "$sam_session/preparation.log"
sam_job_serial=1
sam_core_policy_refresh(){ corelist=(snes); corelisttmp=(snes); sam_allowed_cores=(snes); }
sam_service(){
    case "$1" in choose_core) nextcore=snes;; pick_candidate) return "${candidate_rc:-1}";; esac
}
delete_from_corelist(){ :; }
sam_catalog_background_step(){ return "${discovery_rc:-0}"; }
sam_catalog_pending(){ return "${pending_rc:-1}"; }
'''

    def test_only_exhausted_empty_queue_has_atomic_typed_outcome(self):
        self.check(self.worker + r'''
(sam_prepare_worker)
[[ $(<"$sam_session/outcome") == $'reason=no_eligible_games\nrevision=1' ]]
[[ $(<"$sam_session/error") == 'No eligible games found for the enabled cores and filters' ]]
shopt -s nullglob
unfinished=("$sam_session/"*.tmp.*)
[[ ${#unfinished[@]} == 0 ]]
''')

    def test_pending_catalog_and_existing_queue_are_not_final_empty(self):
        self.check(self.worker + r'''
pending_rc=0; (sam_prepare_worker)
[[ ! -e "$sam_session/outcome" && ! -e "$sam_session/error" ]]
pending_rc=1
printf unparseable > "$sam_session/ready/00000010.record"
(sam_prepare_worker)
[[ ! -e "$sam_session/outcome" && ! -e "$sam_session/error" ]]
''')

    def test_download_and_infrastructure_failures_are_untyped(self):
        self.check(self.worker + r'''
for candidate_rc in 2 3; do
    printf 'reason=no_eligible_games\nrevision=1\n' > "$sam_session/outcome"
    (sam_prepare_worker)
    [[ -f "$sam_session/error" && ! -e "$sam_session/outcome" ]]
    rm -f "$sam_session/error"
done
candidate_rc=1 discovery_rc=7; (sam_prepare_worker)
[[ $(<"$sam_session/error") == *'Background catalog discovery failed'* && ! -e "$sam_session/outcome" ]]
''')

    def test_cancelled_discovery_cannot_publish_final_empty(self):
        self.check(self.worker + r'''
sam_catalog_background_step(){ rm -f -- "$sam_session/alive"; }
(sam_prepare_worker)
[[ ! -e "$sam_session/outcome" && ! -e "$sam_session/error" ]]
''')

    def test_foreground_empty_failure_invokes_cli_before_cleanup(self):
        self.check(r'''
sam_prep(){ :; }; disable_bootrom(){ :; }; sam_cleanup(){ :; }; sam_emit(){ :; }
sam_config_game_boundary(){ :; }
sam_schedule_preparation(){
    : > "$sam_session/preparation.log"
    printf 'reason=no_eligible_games\nrevision=%s\n' "$sam_revision" > "$sam_session/outcome"
    printf 'No eligible games found\n' > "$sam_session/error"
}
python3(){ printf '%s\n' "$@" > "$mrsamtmp/record-call"; }
rc=0; loop_core snes || rc=$?
[[ "$rc" == 1 && -e "$sam_session/alive" ]]
mapfile -t call < "$mrsamtmp/record-call"
[[ "${call[0]}" == "$mrsampath/sam/autostart.py" && "${call[1]}" == record ]]
[[ "${call[2]}" == --session && "${call[3]}" == "$sam_session" ]]
[[ "${call[4]}" == --mode && "${call[5]}" == SINGLE && "${call[6]}" == --target && "${call[7]}" == snes ]]
[[ "${call[8]}" == --ini && "${call[9]}" == "$samini_file" && "${call[10]}" == --lists && "${call[11]}" == "$gamelistpath" ]]
[[ "${call[12]}" == --root && "${call[13]}" == "$mrsampath" && "${call[14]}" == --runtime && "${call[15]}" == "$mrsamtmp" ]]
[[ "${call[16]}" == --owner && "${call[17]}" == "$sam_owner" && ${#call[@]} == 20 ]]
[[ "${call[18]}" == --revision && "${call[19]}" == "$sam_revision" ]]
''')

    def test_stale_malformed_replaced_and_cancelled_results_do_not_record(self):
        self.check(r'''
sam_session_begin; SAM_MODE=SINGLE; SAM_TARGET_CORE=snes
python3(){ printf called > "$mrsamtmp/record-call"; }
printf 'reason=no_eligible_games\nrevision=0\n' > "$sam_session/outcome"
! sam_record_empty_autostart
printf 'reason=no_eligible_games\nrevision=1\nextra=yes\n' > "$sam_session/outcome"
! sam_record_empty_autostart
printf 'reason=no_eligible_games\nrevision=1\n' > "$sam_session/outcome"
rm -f "$sam_session/alive"; ! sam_record_empty_autostart
: > "$sam_session/alive"
sam_session_is_current(){ return 1; }; ! sam_record_empty_autostart
[[ ! -e "$mrsamtmp/record-call" ]]
''')

    def test_cleanup_does_not_record_cached_empty_result(self):
        self.check(r'''
sam_session_begin; SAM_MODE=SINGLE
: > "$sam_session/preparation.log"
printf 'reason=no_eligible_games\nrevision=1\n' > "$sam_session/outcome"
printf 'No eligible games found\n' > "$sam_session/error"
python3(){ printf called > "$mrsamtmp/record-call"; }
sam_emit(){ :; }; sam_cleanup(){ :; }; sam_cancel_launch_job(){ :; }
sam_session_cleanup
[[ ! -e "$mrsamtmp/record-call" && ! -d "$sam_session" ]]
''')

    admission = r'''
sam_session_read_owner(){ return 1; }
tmux(){ [[ "$1" != has-session ]] || return 1; return 99; }
timeout(){ shift; "$@"; }
env_check(){ :; }
there_can_be_only_one(){ printf reached > "$mrsamtmp/replacement"; }
mcp_start(){ :; }
printf '{}' > "$mrsamtmp/autostart-empty.json"
'''

    def test_validated_manual_start_clears_guard_but_conditional_start_keeps_it(self):
        self.check(self.admission + r'''
! sam_start --if-idle snes
[[ -e "$mrsamtmp/replacement" && -e "$mrsamtmp/autostart-empty.json" ]]
rm -f "$mrsamtmp/replacement"
! sam_start snes
[[ -e "$mrsamtmp/replacement" && ! -e "$mrsamtmp/autostart-empty.json" ]]
''')

    def test_rejected_core_and_open_menu_preserve_guard(self):
        self.check(self.admission + r'''
! sam_start unknown_core
[[ -e "$mrsamtmp/autostart-empty.json" && ! -e "$mrsamtmp/replacement" ]]
sam_menu_lock_active(){ return 0; }
! sam_start snes
sam_start --if-idle snes
[[ -e "$mrsamtmp/autostart-empty.json" && ! -e "$mrsamtmp/replacement" ]]
''')

    def test_failed_old_owner_cleanup_preserves_manual_retry_guard(self):
        self.check(self.admission + r'''
there_can_be_only_one(){ return 1; }
! sam_start snes
[[ -e "$mrsamtmp/autostart-empty.json" ]]
''')


if __name__ == '__main__':
    unittest.main()
