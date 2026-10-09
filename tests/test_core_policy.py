"""Shared core policy against the real shell source; all lists/hardware isolated."""
import unittest
import shlex
import shutil
import subprocess
import time
import test_shell


class CorePolicy(unittest.TestCase):
    def setUp(self):
        self.fixture = test_shell.Shell()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def check(self, code):
        result = self.fixture.shell(code)
        self.assertEqual(result.returncode, 0, result.stderr + '\n' + result.stdout)
        return result.stdout

    def test_normalize_in_place_and_names_that_used_to_shadow_namerefs(self):
        self.check('''target=(' N64 ' PSX '' snes snes '  ')
sam_normalize_cores target target
[[ "${target[*]}" == 'n64 psx snes' ]]
candidate=(snes NES); accepted=()
sam_filter_cores candidate accepted
[[ "${accepted[*]}" == 'snes nes' ]]
''')

    def test_unknown_input_reports_error_without_partial_output(self):
        self.check('''target=(snes unknown); accepted=(nes)
rc=0; sam_normalize_cores target accepted || rc=$?
[[ "$rc" == 2 && "${accepted[*]}" == nes && "$sam_core_reason" == *unknown* ]]
! sam_filter_cores 'target[0]' accepted
rc=0; sam_core_rule_check snes unknown_role || rc=$?
[[ "$rc" == 2 && "$sam_core_reason" == *role* ]]
''')

    def test_disabled_bgm_has_no_effect_and_enabled_bgm_preserves_requests(self):
        self.check('''corelist=(n64 psx snes); sam_core_session_begin
[[ "${sam_allowed_cores[*]}" == 'n64 psx snes' ]]
sam_load_module bgm; sam_core_policy_refresh
[[ "${sam_requested_cores[*]}" == 'n64 psx snes' && "${sam_allowed_cores[*]}" == snes ]]
corelisttmp=(); sam_normal_choose_core; [[ "$nextcore" == snes ]]
''')

    def test_all_module_rules_must_approve_and_empty_never_falls_back(self):
        self.check('''corelist=(n64 snes); sam_load_module bgm
reject_snes(){ [[ "$1" != snes ]]; }; sam_register core_allowed reject_snes
rc=0; sam_core_session_begin || rc=$?
[[ "$rc" == 1 && ${#sam_allowed_cores[@]} == 0 && ${#corelisttmp[@]} == 0 ]]
corelistall=(arcade); nextcore=stale
rc=0; sam_normal_choose_core || rc=$?
[[ "$rc" == 1 && -z "$nextcore" ]]
''')

    def test_rule_errors_propagate_from_picker(self):
        self.check('''corelist=(nes); broken_rule(){ return 7; }
sam_register core_allowed broken_rule
rc=0; sam_normal_choose_core || rc=$?
[[ "$rc" == 2 && -z "$nextcore" && "$sam_core_reason" == *broken_rule* ]]
''')

    def test_explicit_target_cannot_bypass_rule_or_stop_existing_session(self):
        self.check('''sam_load_module bgm; corelist=(snes); stopped=no
there_can_be_only_one(){ stopped=yes; }; mcp_start(){ exit 99; }
! sam_start ' N64 '
[[ "$stopped" == no && "$sam_core_reason" == *BGM* ]]
''')

    def test_explicit_allowed_target_overrides_configured_systems(self):
        self.check('''corelist=(snes); sam_core_session_begin ' NES '
[[ "$SAM_MODE" == SINGLE && "$SAM_TARGET_CORE" == nes && "${sam_allowed_cores[*]}" == nes ]]
sam_normal_choose_core; [[ "$nextcore" == nes ]]
''')

    def test_configuration_reload_marks_registry_for_fresh_start_validation(self):
        self.check('''[[ "$sam_module_config_dirty" == 0 ]]
read_samini
[[ "$sam_module_config_dirty" == 1 ]]
''')

    def test_menu_start_validates_changed_switches_in_fresh_registry(self):
        self.check('''sam_load_module bgm
printf 'corelist="n64"\\ncorelistall="n64"\\nbgm="No"\\nrating="no"\\n' > "$samini_file"
read_samini
SAM_ENTRY="$SAM_ROOT/../MiSTer_SAM_on.sh"
export SAM_MODULES_OVERRIDE=auto
env_check(){ :; }
checked=no; there_can_be_only_one(){ checked=yes; return 1; }
! sam_start n64
[[ "$checked" == yes ]]
printf 'corelist="n64"\\ncorelistall="n64"\\nbgm="Yes"\\nrating="no"\\n' > "$samini_file"
read_samini; checked=no
! sam_start n64
[[ "$checked" == no ]]
''')

    def test_m82_requests_nes_and_rejects_conflicting_explicit_target(self):
        self.check('''sam_load_module m82; corelist=(snes psx)
sam_core_session_begin
[[ "${sam_requested_cores[*]}" == nes && "${sam_allowed_cores[*]}" == nes ]]
corelist=(snes psx); rc=0; sam_core_session_begin psx || rc=$?
[[ "$rc" == 1 && "$sam_core_reason" == *M82* ]]
''')

    def test_m82_setup_preserves_ordered_list_timing_and_requested_config(self):
        self.check('''corelist=(snes); sam_load_module m82
sam_emit config_loaded; sam_core_session_begin
printf '/games/M82 Game.nes\\n/games/A.nes\\n/games/B.nes\\n' > "$gamelistpath/nes_gamelist.txt"
printf 'A.nes\\nB.nes\\n' > "$gamelistpath/m82_list.txt"
only_unmute_if_needed(){ :; }
sam_emit session_setup
[[ "$gametimer" == 21 && ! -f "$corelistfile" && "${sam_allowed_cores[*]}" == nes ]]
SAM_ACTION=; check_list nes
mapfile -t ordered < "$gamelistpathtmp/nes_gamelist.txt"
[[ "${ordered[*]}" == '/games/M82 Game.nes /games/A.nes /games/M82 Game.nes /games/B.nes' ]]
''')

    def test_incompatible_mode_rejected_before_session_setup(self):
        self.check('''sam_load_module m82; sam_load_module artwork
corelist=(nes); rc=0; sam_core_session_begin || rc=$?
[[ "$rc" == 2 && "$sam_core_reason" == *auxiliary* ]]
''')

    def test_rotation_resets_from_allowed_list_only(self):
        self.check('''sam_load_module bgm; corelist=(n64 snes nes)
sam_core_session_begin; corelisttmp=(n64 nes nes)
sam_core_policy_refresh; [[ "${corelisttmp[*]}" == nes ]]
delete_from_corelist nes tmp; sam_core_policy_refresh
[[ "${corelisttmp[*]}" == 'snes nes' ]]
[[ "${sam_requested_cores[*]}" == 'n64 snes nes' ]]
''')

    def test_session_exclusion_keeps_original_requested_cores(self):
        self.check('''corelist=(snes nes); sam_core_session_begin
delete_from_corelist snes
[[ "${sam_requested_cores[*]}" == 'snes nes' && "${sam_allowed_cores[*]}" == nes ]]
rc=0; delete_from_corelist nes || rc=$?
[[ "$rc" == 1 && ${#sam_allowed_cores[@]} == 0 && ! -f "$corelistfile" ]]
''')

    def test_blank_compatibility_list_stops_without_defaults_or_bad_subscript(self):
        self.check('''sam_load_module video; samvideo_tvc=no
corelist=(snes); sam_core_session_begin
printf '\\n  \\n' > "$corelistfile"
rc=0; corelist_update || rc=$?
[[ "$rc" == 1 && ${#sam_allowed_cores[@]} == 0 && "$sam_core_reason" == *'No allowed cores'* ]]
corelistall=(arcade); load_samvideo(){ exit 99; }
rc=0; next_core '' || rc=$?
[[ "$rc" == 2 && ${#corelist[@]} == 0 ]]
''')

    def test_compatibility_explicit_target_rejected_before_list_or_video(self):
        self.check('''sam_load_module video; samvideo_tvc=no; sam_load_module bgm
corelist=(snes); sam_core_session_begin
check_list(){ exit 99; }; load_samvideo(){ exit 99; }
rc=0; next_core n64 || rc=$?
[[ "$rc" == 2 && "$sam_core_reason" == *BGM* ]]
''')

    def test_compatibility_weights_drop_removed_cores_and_refresh_counts(self):
        self.check('''sam_load_module video; samvideo_tvc=no
corelist=(snes); sam_core_session_begin
COREWEIGHT_INITIALIZED=1; COREP[n64]=9000; TOTAL_GAME_COUNT=9000
printf 'A\\n' > "$gamelistpath/snes_gamelist.txt"
pick_core_weighted; [[ "$nextcore" == snes && -z "${COREP[n64]-}" && "${COREP[snes]}" == 1 ]]
printf 'A\\nB\\nC\\n' > "$gamelistpath/snes_gamelist.txt"
pick_core_weighted; [[ "$nextcore" == snes && "${COREP[snes]}" == 3 ]]
''')

    def test_empty_weight_counts_use_allowed_cores_without_discovery(self):
        self.check('''sam_load_module video; samvideo_tvc=no; corelist=(snes)
sam_core_session_begin; ensure_list(){ exit 99; }
pick_core_weighted; [[ "$nextcore" == snes ]]
''')

    def test_video_weights_restrict_cache_to_current_allowed_mapping(self):
        self.check('''sam_load_module video; samvideo_tvc=yes; sam_load_module bgm
corelist=(n64 snes); sam_core_session_begin
core_count_file="$SAM_TMP_ROOT/counts"; choices=(n64 snes)
printf 'n64=9000\\nsnes=0\\ntotal_count=9000\\n' > "$core_count_file"
jq(){ printf '0\\n'; }
pick_core_samvideo choices
[[ "$nextcore" == snes && -z "${SAMVC[n64]-}" && "$SAMVTOTAL" == 0 ]]
''')

    def test_video_mapping_and_auxiliary_resource_are_distinct(self):
        self.check('''sam_load_module video; samvideo_tvc=yes; corelist=(snes)
sam_core_session_begin
sam_core_rule_check cdi auxiliary
SV_TVC[snes]=; rc=0; sam_core_policy_refresh || rc=$?
[[ "$rc" == 1 && "$sam_core_reason" == *mapping* ]]
''')

    def test_original_core_is_checked_before_mgl_replay_launch(self):
        self.check('''sam_load_module bgm; corelist=(snes); sam_core_session_begin
sam_publish_phase(){ exit 99; }
! load_core mgls "$SAM_TMP_ROOT/replay.mgl" Game n64 "$SAM_TMP_ROOT/Game.n64"
[[ "$sam_core_reason" == *BGM* ]]
''')

    def test_queued_rule_error_is_fatal_instead_of_silent_discard(self):
        self.check('''corelist=(snes); sam_core_session_begin
sam_owner=audit; sam_revision=1; sam_session="$SAM_TMP_ROOT/session"
mkdir -p "$sam_session/ready"; touch "$SAM_TMP_ROOT/game.sfc"
sam_record_write "$sam_session/ready/1.record" snes "$SAM_TMP_ROOT/game.sfc" Game '' 1
broken_rule(){ return 2; }; sam_register core_allowed broken_rule
rc=0; sam_take_prepared || rc=$?
[[ "$rc" == 2 && -s "$sam_session/error" && -f "$sam_session/ready/1.record" ]]
''')

    def test_all_rejected_worker_stops_before_picking_or_discovery(self):
        self.check('''corelist=(n64); sam_load_module bgm
sam_owner=audit; sam_session="$SAM_TMP_ROOT/session"; sam_job_serial=1
mkdir -p "$sam_session/ready" "$sam_session/jobs"; touch "$sam_session/alive"
pick_never(){ exit 99; }; sam_bind pick_candidate pick_never
sam_catalog_background_step(){ exit 99; }
(sam_prepare_worker)
[[ -s "$sam_session/error" && "$(<"$sam_session/error")" == *'No allowed cores'* ]]
''')

    def test_custom_selector_cannot_prepare_an_outside_core(self):
        self.check('''corelist=(snes); sam_core_session_begin
sam_owner=audit; sam_session="$SAM_TMP_ROOT/session"; sam_job_serial=1
mkdir -p "$sam_session/ready" "$sam_session/jobs"; touch "$sam_session/alive"
rogue(){ nextcore=n64; }; sam_bind choose_core rogue
pick_never(){ exit 99; }; sam_bind pick_candidate pick_never
(sam_prepare_worker)
[[ -s "$sam_session/error" && "$(<"$sam_session/error")" == *rejected* ]]
''')

    def test_normal_empty_catalog_exits_event_loop_without_launch(self):
        self.check('''corelist=(snes); check_for_new_games=no
: > "$gamelistpath/snes_gamelist.txt"
sam_prep(){ :; }; disable_bootrom(){ :; }; sam_cleanup(){ :; }
load_core(){ exit 99; }
! loop_core snes
sam_session_cleanup
[[ -s "$mrsamtmp/last-error.log" && "$(<"$mrsamtmp/last-error.log")" == *'No eligible games'* ]]
''')

    def test_owned_mode_setup_command_is_cancelled_with_its_parent(self):
        self.check('''marker="$SAM_TMP_ROOT/setup-child"
(
    trap 'sam_cancel_launch_job; exit 0' TERM
    sam_run_owned_command bash -c 'printf "%s\\n" "$$" > "$1"; sleep 30' _ "$marker"
) &
parent=$!
for ((i=0;i<100;i++)); do [[ ! -s "$marker" ]] || break; sleep 0.01; done
[[ -s "$marker" ]]; read -r child < "$marker"
sam_pid_start "$child"
kill -TERM "$parent"; wait "$parent"
! sam_pid_start "$child"
''')

    def test_cancelled_m82_index_does_not_publish_partial_catalog(self):
        self.check('''sam_load_module m82
mrsampath="$SAM_TMP_ROOT/fake-tools"; mkdir -p "$mrsampath"
export M82_INDEX_STARTED="$SAM_TMP_ROOT/index-started"
cat > "$mrsampath/samindex" <<'SH'
#!/bin/bash
while [[ "$1" != -o ]]; do shift; done
shift
printf '/games/Partial.nes\\n' > "$1/nes_gamelist.txt"
printf '%s\\n' "$$" > "$M82_INDEX_STARTED"
sleep 30
SH
chmod +x "$mrsampath/samindex"
(
    trap 'sam_cancel_launch_job; sam_m82_cleanup_index; exit 0' TERM
    build_m82_list
) &
parent=$!
for ((i=0;i<100;i++)); do [[ ! -s "$M82_INDEX_STARTED" ]] || break; sleep 0.01; done
[[ -s "$M82_INDEX_STARTED" ]]
kill -TERM "$parent"; wait "$parent"
[[ ! -f "$gamelistpath/nes_gamelist.txt" ]]
! compgen -G "$mrsamtmp/m82-index.*"
''')

    @unittest.skipUnless(shutil.which('tmux'), 'native tmux required')
    def test_loading_burst_is_coalesced_on_a_private_tmux_terminal(self):
        ready = self.fixture.root / 'ready'
        result = self.fixture.root / 'result'
        script = self.fixture.root / 'burst.sh'
        script.write_text('''source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
printf ready > "$BURST_READY"
sleep 0.3
sam_loading_keys
if read -r -s -t 0.05 -n 1 key; then pending=leftover; else pending=empty; fi
printf '%s:%s' "$SAM_ACTION" "$pending" > "$BURST_RESULT"
''')
        env = dict(self.fixture.env, BURST_READY=str(ready), BURST_RESULT=str(result))
        command = ['tmux', '-S', str(self.fixture.root / 'socket')]
        subprocess.run(command + ['new-session', '-d', '-s', 'burst', 'bash ' + shlex.quote(str(script))], env=env, check=True)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline: time.sleep(.01)
            self.assertTrue(ready.exists())
            subprocess.run(command + ['send-keys', '-t', 'burst', 'n' * 40], check=True)
            while not result.exists() and time.monotonic() < deadline: time.sleep(.01)
            self.assertTrue(result.exists())
            self.assertEqual(result.read_text(), 'next:empty')
        finally:
            subprocess.run(command + ['kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    unittest.main(verbosity=2)
