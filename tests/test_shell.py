"""Native Linux fixtures; never use the live SAM folders or hardware commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
from paths import PACKAGE


class Shell(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-refactor-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        ini = self.root / 'SAM.ini'
        ini.write_text('corelist="arcade,snes"\ncorelistall="arcade,snes"\nrating="no"\n')
        self.env = dict(os.environ, SAM_MODULES_OVERRIDE="", SAM_ROOT=str(PACKAGE/'.MiSTer_SAM'), SAM_INI=str(ini),
                        SAM_LIST_ROOT=str(self.root/'lists'), SAM_TMP_ROOT=str(self.root/'tmp'),
                        SAM_SESSION_LIST_ROOT=str(self.root/'session-lists'), SAM_STATE_FILE=str(self.root/'SAM_state'),
                        SAM_CONFIG_ROOT=str(self.root/'config'), SAM_MISTER_ROOT=str(self.root/'media'))

    def shell(self, code):
        prelude = 'set -e\nsource "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only\n'
        try:
            return subprocess.run(['bash','-c',prelude+code],env=self.env,text=True,capture_output=True,timeout=15)
        except subprocess.TimeoutExpired as error:
            self.fail('Shell fixture timed out: '+repr((error.stderr or b'')[-5000:]))

    def assertShell(self, code):
        result = self.shell(code)
        self.assertEqual(result.returncode,0,result.stderr+'\n'+result.stdout)
        return result.stdout

    def test_disabled_modules_are_unloaded(self):
        self.assertShell('[[ ${#SAM_MODULES[@]} == 0 ]]; ! declare -F sam_artwork_filter; ! declare -F sam_display_write; ! declare -F bgm_start; ! declare -F tty_start; ! declare -F samvideo_play\n')

    def test_debug_off_does_not_start_date(self):
        self.assertShell('date() { echo forbidden >&2; return 99; }; samdebug=no; samdebuglog=no; samdebug hello\n')

    def test_public_list_paths(self):
        self.assertShell('[[ "$gamelistpath" == "$SAM_LIST_ROOT/Gamelists" && "$ignorepath" == "$SAM_LIST_ROOT/Ignore" && "$blacklistpath" == "$SAM_LIST_ROOT/Blacklists" && "$ratedpath" == "$SAM_LIST_ROOT/Rated" ]]\n')

    def test_generic_indexer_runs_once_without_sleep_and_preserves_failure(self):
        self.assertShell('''
mkdir -p "$SAM_TMP_ROOT/scanner" "$SAM_TMP_ROOT/output"
cat > "$SAM_TMP_ROOT/scanner/samindex" <<'SH'
#!/bin/bash
printf 'call\\n' >> "$SAM_TMP_ROOT/calls"
[[ "$SAM_INDEX_RC" != 2 ]] || exit 2
printf '/games/A.nes\\n' > "$5/nes_gamelist.txt"
exit "$SAM_INDEX_RC"
SH
chmod +x "$SAM_TMP_ROOT/scanner/samindex"
mrsampath="$SAM_TMP_ROOT/scanner"
sleep() { echo unexpected-sleep >&2; return 99; }
export SAM_INDEX_RC=0
build_gamelist nes "$SAM_TMP_ROOT/output"
[[ $(wc -l < "$SAM_TMP_ROOT/calls") == 1 ]]
export SAM_INDEX_RC=2
rc=0; build_gamelist nes "$SAM_TMP_ROOT/output" || rc=$?
[[ "$rc" == 2 && $(<"$SAM_TMP_ROOT/output/nes_gamelist.txt") == '/games/A.nes' ]]
''')

    def test_generic_failed_scan_does_not_publish_old_staging_list(self):
        self.assertShell('''
sam_session="$SAM_TMP_ROOT/session";sam_job="$SAM_TMP_ROOT/job"
mkdir -p "$sam_session" "$sam_job/build-nes";: > "$sam_session/alive"
printf 'old-stage\\n' > "$sam_job/build-nes/nes_gamelist.txt"
printf 'valid-published\\n' > "$gamelistpath/nes_gamelist.txt"
build_gamelist(){ return 2; }
rc=0;sam_build_catalog nes || rc=$?
[[ "$rc" == 2 && $(<"$gamelistpath/nes_gamelist.txt") == valid-published ]]
''')

    def test_literal_record_and_unknown_keys(self):
        self.assertShell('''sam_generation=3; sam_owner=test; sam_candidate_cover=''; sam_candidate_reset=no
path='/games/$(touch /tmp/SAM_EVAL_FORBIDDEN) = Pokémon.chd'
sam_record_write "$SAM_TMP_ROOT/test.record" snes "$path" 'Game = title' '' 3
printf 'unknown=$(exit 99)\n' >> "$SAM_TMP_ROOT/test.record"
sam_record_read "$SAM_TMP_ROOT/test.record"
[[ "$sam_record_path" == "$path" && "$sam_record_name" == 'Game = title' && "$sam_record_revision" == 3 ]]
''')

    def test_random_range(self):
        self.assertShell('for n in 1 2 42 11335 65537; do for ((i=0;i<100;i++)); do sam_random_below "$n"; ((sam_random>=0 && sam_random<n)); done; done\n')

    def test_bootstrap_respects_enabled_cores_and_single_mode(self):
        self.assertShell('''SAM_MODE=ALL; corelisttmp=(snes); sam_bootstrap=1
sam_normal_choose_core; [[ "$nextcore" == snes ]]
corelisttmp=(snes arcade); sam_bootstrap=1; sam_normal_choose_core; [[ "$nextcore" == arcade ]]
SAM_MODE=SINGLE; SAM_TARGET_CORE=snes; sam_bootstrap=1; sam_normal_choose_core; [[ "$nextcore" == snes ]]
''')

    def test_ignore_lists_are_literal_and_visible(self):
        self.assertShell('''sam_session="$SAM_TMP_ROOT/test-session"; mkdir -p "$sam_session"
printf '/games/A = Pokémon.sfc\n/games/B.sfc\n' > "$gamelistpathtmp/snes_gamelist.txt"
ignoregame snes '/games/A = Pokémon.sfc'
sam_is_excluded snes '/other/A = Pokémon.sfc'
! sam_is_excluded snes '/games/B.sfc'
[[ "$(<"$ignorepath/snes_excludelist.txt")" == '/games/A = Pokémon.sfc' ]]
[[ "$(<"$gamelistpathtmp/snes_gamelist.txt")" == '/games/B.sfc' ]]
''')

    def test_no_repeat_commits_only_after_launch(self):
        self.assertShell('''sam_session="$SAM_TMP_ROOT/test-session"; mkdir -p "$sam_session/consumed"
: > "$sam_session/consumed/snes"; corelisttmp=(snes arcade); norepeat=yes
[[ ! -s "$sam_session/consumed/snes" ]]
sam_normal_commit snes '/games/A.sfc' no
[[ "$(<"$sam_session/consumed/snes")" == '/games/A.sfc' ]]
sam_normal_commit snes '/games/B.sfc' yes
[[ "$(<"$sam_session/consumed/snes")" == '/games/B.sfc' ]]
''')

    def test_registry_rejects_arbitrary_callback_text(self):
        self.assertShell('! sam_register tick "echo injected"; ! sam_bind choose_core "$(exit 0)"; ! sam_load_module ../artwork\n')

    def test_preparation_fills_two_choices_without_consuming_history(self):
        self.assertShell('''SAM_MODE=SINGLE; SAM_TARGET_CORE=snes; corelist=(snes); corelisttmp=(snes); norepeat=yes
# This fixture has a complete synthetic catalog; real samindex discovery is
# covered separately and must not read the device's collections here.
check_for_new_games=no
sam_owner=test; sam_generation=8; sam_revision=2; sam_job_serial=1
sam_session="$SAM_TMP_ROOT/test-session"; sam_catalog_cache="$SAM_TMP_ROOT/cache"
mkdir -p "$sam_session/ready" "$sam_session/jobs" "$sam_session/consumed" "$sam_catalog_cache"
: > "$sam_session/alive"
touch "$SAM_TMP_ROOT/A.sfc" "$SAM_TMP_ROOT/B.sfc"
printf '%s\\n' "$SAM_TMP_ROOT/A.sfc" "$SAM_TMP_ROOT/B.sfc" > "$gamelistpath/snes_gamelist.txt"
(sam_prepare_worker)
sam_queue_files; [[ ${#sam_queue[@]} == 2 ]]
[[ ! -s "$sam_session/consumed/snes" && "$sam_generation" == 8 ]]
sam_record_read "${sam_queue[0]}"; first="$sam_record_path"
sam_record_read "${sam_queue[1]}"; [[ "$first" != "$sam_record_path" ]]
sam_take_prepared; [[ "$nextcore" == snes && -f "$rompath" ]]
''')

    def test_ready_choice_rejects_old_owner_and_new_ignore(self):
        self.assertShell('''sam_session="$SAM_TMP_ROOT/test-session"; mkdir -p "$sam_session/ready"
sam_owner=old; sam_revision=1; sam_generation=1
touch "$SAM_TMP_ROOT/A.sfc"
sam_record_write "$sam_session/ready/1.record" snes "$SAM_TMP_ROOT/A.sfc" A.sfc '' 1
sam_owner=new; ! sam_take_prepared; [[ ! -e "$sam_session/ready/1.record" ]]
sam_record_write "$sam_session/ready/2.record" snes "$SAM_TMP_ROOT/A.sfc" A.sfc '' 1
printf '%s\\n' "$SAM_TMP_ROOT/A.sfc" > "$ignorepath/snes_excludelist.txt"
! sam_take_prepared; [[ ! -e "$sam_session/ready/2.record" ]]
''')

    def test_cached_filter_results_are_reused(self):
        self.assertShell('''sam_session="$SAM_TMP_ROOT/test-session"; sam_job="$sam_session/job"; sam_catalog_cache="$SAM_TMP_ROOT/cache"; sam_revision=1
mkdir -p "$sam_job/lists" "$sam_catalog_cache"
gamelistpathtmp="$sam_job/lists"; tmpfile="$sam_job/filter"; tmpfilefilter="$sam_job/rating"
printf '/games/A.sfc\\n/games/B.sfc\\n' > "$gamelistpath/snes_gamelist.txt"
sam_catalog_ready snes
filter_list() { echo 'unexpected rebuild' >&2; return 99; }
sam_catalog_ready snes
''')

    def test_empty_filters_never_restore_excluded_games(self):
        self.assertShell('''printf '/games/A.sfc\\n' > "$gamelistpath/snes_gamelist.txt"
cp "$gamelistpath/snes_gamelist.txt" "$gamelistpathtmp/snes_gamelist.txt"
PATHFILTER[snes]=absent; ! filter_list snes
[[ ! -s "$gamelistpathtmp/snes_gamelist.txt" ]]
PATHFILTER[snes]=; cp "$gamelistpath/snes_gamelist.txt" "$gamelistpathtmp/snes_gamelist.txt"
printf 'A\\n' > "$blacklistpath/snes_blacklist.txt"; ! filter_list snes
[[ ! -s "$gamelistpathtmp/snes_gamelist.txt" ]]
''')

    def test_ratings_refine_ignore_and_path_filters(self):
        self.assertShell('''printf '/games/A.sfc\\n/games/B.sfc\\n' > "$gamelistpath/snes_gamelist.txt"
cp "$gamelistpath/snes_gamelist.txt" "$gamelistpathtmp/snes_gamelist.txt"
printf 'A\\nB\\n' > "$ratedpath/snes_rated.txt"
printf '/games/A.sfc\\n' > "$ignorepath/snes_excludelist.txt"
rating=kids; filter_list snes
[[ "$(<"$gamelistpathtmp/snes_gamelist.txt")" == /games/B.sfc ]]
''')

    def test_m82_order_and_next_skips_bios(self):
        self.assertShell('''m82_muted=yes; sam_load_module m82; m82=yes
printf '/games/M82 Game.nes\\n/games/A.nes\\n/games/B.nes\\n' > "$gamelistpath/nes_gamelist.txt"
printf 'A.nes\\nB.nes\\n' > "$gamelistpath/m82_list.txt"
SAM_ACTION=; check_list nes
mapfile -t ordered < "$gamelistpathtmp/nes_gamelist.txt"
[[ "${ordered[*]}" == '/games/M82 Game.nes /games/A.nes /games/M82 Game.nes /games/B.nes' ]]
check_list nes; [[ "$(head -n1 "$gamelistpathtmp/nes_gamelist.txt")" == /games/A.nes ]]
SAM_ACTION=next; check_list nes
[[ "$(head -n1 "$gamelistpathtmp/nes_gamelist.txt")" == /games/B.nes ]]
''')

    def test_video_status_keeps_wire_mode_for_games(self):
        self.assertShell('''sam_load_module controls; sam_load_module video
[[ "$sam_mode" == samvideo ]]
sam_emit display_start
[[ "$(sed -n 's/^mode=//p' "$SAM_STATE_FILE")" == samvideo ]]
printf rom > "$SAM_TMP_ROOT/game.sfc"
sam_emit display_launch 'Matching game' "$SAM_TMP_ROOT/game.sfc" snes ''
sam_emit display_publish 42 "$((EPOCHSECONDS + 42))"
[[ "$(sed -n 's/^mode=//p' "$SAM_STATE_FILE")" == samvideo ]]
[[ "$(sed -n 's/^active=//p' "$SAM_STATE_FILE")" == yes ]]
''')

    def test_video_alternate_policy_stays_inside_module(self):
        self.assertShell('''sam_load_module video; samvideo_freq=alternate; sv_loadcounter=0
samvideo_play(){ printf played > "$SAM_TMP_ROOT/video-played"; }
! load_samvideo; wait; [[ -f "$SAM_TMP_ROOT/video-played" ]]
load_samvideo; [[ "$sv_loadcounter" == 2 ]]
''')

    def test_video_assets_download_published_player_and_make_it_executable(self):
        self.assertShell('''sam_load_module video
 mrsampath="$SAM_TMP_ROOT/player-assets"; mkdir -p "$mrsampath"
raw_base=https://example.invalid/test
check_and_update(){
    [[ "$1" == "$raw_base/.MiSTer_SAM/mplayer" && "$2" == /tmp/sam-mplayer && "$3" == "$mrsampath/mplayer" ]] || return 1
    printf '#!/bin/sh\\nexit 0\\n' > "$3"
    return 2
}
sam_video_assets
[[ -x "$mrsampath/mplayer" ]]
''')

    def test_video_assets_failure_does_not_replace_existing_player(self):
        self.assertShell('''sam_load_module video
 mrsampath="$SAM_TMP_ROOT/player-assets"; mkdir -p "$mrsampath"
printf 'existing player' > "$mrsampath/mplayer"
chmod +x "$mrsampath/mplayer"
check_and_update(){ return 1; }
! sam_video_assets
[[ "$(cat "$mrsampath/mplayer")" == 'existing player' ]]
''')

    def test_xml_paths_and_configuration_are_literal(self):
        self.assertShell('''sam_xml_escape '/games/A & B "<.sfc'
[[ "$sam_xml" == '/games/A &amp; B &quot;&lt;.sfc' ]]
mkdir -p "$misterpath"
printf 'cfgcore_subfolder="test folder"\\ncfgarcade_subfolder="arcade"\\n' > "$ini_file"
sam_config_paths
[[ "$configpath" == "$SAM_CONFIG_ROOT/test folder" && "$cfgarcade_configpath" == "$SAM_CONFIG_ROOT/arcade" ]]
''')

    def test_cover_download_failure_stops_preparation(self):
        self.assertShell('''SAM_MODE=SINGLE; SAM_TARGET_CORE=snes; corelist=(snes); corelisttmp=(snes)
sam_owner=test; sam_revision=1; sam_job_serial=1
sam_session="$SAM_TMP_ROOT/test-session"; sam_catalog_cache="$SAM_TMP_ROOT/cache"
mkdir -p "$sam_session/ready" "$sam_session/jobs" "$sam_session/consumed" "$sam_catalog_cache"
: > "$sam_session/alive"
touch "$SAM_TMP_ROOT/A.sfc"
printf '%s\\n' "$SAM_TMP_ROOT/A.sfc" > "$gamelistpath/snes_gamelist.txt"
fail_download(){ return 3; }; sam_register candidate_prepare fail_download
(sam_prepare_worker)
[[ -s "$sam_session/error" ]]; sam_queue_files; [[ ${#sam_queue[@]} == 0 ]]
''')

    def test_progressive_arcade_batch_is_completed_in_background(self):
        self.assertShell('''sam_owner=test; sam_revision=1; sam_session="$SAM_TMP_ROOT/seed-session"; sam_job="$sam_session/job"
mkdir -p "$sam_job" "$misterpath/_Arcade"; : > "$sam_session/alive"
for ((n=0;n<70;n++)); do touch "$misterpath/_Arcade/$n.mra"; done
sam_build_catalog arcade
[[ "$(wc -l < "$gamelistpath/arcade_gamelist.txt")" == 64 && -f "$gamelistpath/arcade.partial" ]]
sam_catalog_background_step
[[ "$(wc -l < "$gamelistpath/arcade_gamelist.txt")" == 70 && ! -f "$gamelistpath/arcade.partial" ]]
''')

    def test_roulette_settings_load_only_with_the_module(self):
        self.assertShell('''printf 'gametimer=42\\n' > "$mrsamtmp/gameroulette.ini"
[[ "$gametimer" != 42 ]]
sam_load_module roulette; [[ "$gametimer" == 42 && "$sam_mode" == roulette ]]
''')

    def test_plugin_has_its_own_simple_enable_switch(self):
        self.assertShell('''mrsampath="$SAM_TMP_ROOT/pluginroot"; mkdir -p "$mrsampath/modules" "$mrsampath/modules.d"
printf 'name=example\\nenabled_by=Example_enable\\n' > "$mrsampath/modules.d/example.module"
printf 'example_hook(){ :; }; sam_register session_start example_hook\\n' > "$mrsampath/modules/example.sh"
Example_enable=No; sam_load_plugins; ! declare -F example_hook
Example_enable=Yes; sam_load_plugins; declare -F example_hook >/dev/null
[[ "${SAM_MODULES[example]}" == 1 ]]
printf 'name=../bad\\nenabled_by=Example_enable\\n' > "$mrsampath/modules.d/example.module"
! sam_load_plugins
''')

    def test_amiga_shared_copy_happens_before_launch(self):
        self.assertShell('''sam_session="$SAM_TMP_ROOT/amiga-session"; amigapath="$SAM_TMP_ROOT/amiga"; amigacore="$SAM_TMP_ROOT/Minimig.rbf"
mkdir -p "$sam_session" "$amigapath/shared"; touch "$amigapath/MegaAGS.hdf" "$amigacore"
printf 'data\\n' > "$amigapath/shared/example"; rompath='Amiga title'
check_rom amiga; [[ -f "$sam_session/Amiga_shared/example" ]]
cp(){ echo unexpected-copy >&2; return 99; }; du(){ echo unexpected-du >&2; return 99; }
mountpoint(){ return 1; }; sam_mount_bind(){ [[ "$1" == "$sam_session/Amiga_shared" && "$2" == "$amigapath/shared" ]]; }
sam_amiga_mount; [[ "$sam_amiga_mounted" == 1 ]]
''')

    def test_runtime_phase_is_atomic_and_old_owner_cannot_overwrite(self):
        self.assertShell('''mkdir -p "$mrsamtmp"; sam_pid_start "$$"; sam_owner="$$:$sam_proc_start"
sam_publish_phase preparing; grep -q 'phase=preparing' "$mrsamtmp/session-owner"
sam_publish_phase loading; grep -q 'launch=1' "$mrsamtmp/session-owner"
sam_publish_phase playing; grep -q 'phase=playing' "$mrsamtmp/session-owner"
printf 'pid=2\\nstart=999\\nphase=playing\\n' > "$mrsamtmp/session-owner"
! sam_publish_phase stopping; grep -q 'pid=2' "$mrsamtmp/session-owner"
''')

    def test_targeted_stop_rejects_replaced_and_reused_owner(self):
        self.assertShell('''mkdir -p "$mrsamtmp"; printf 'pid=321\\nstart=77\\n' > "$mrsamtmp/session-owner"
tmux(){ touch "$SAM_TMP_ROOT/unexpected-tmux"; return 99; }
! there_can_be_only_one 321 78
sam_pid_start(){ sam_proc_start=78; return 0; }
! there_can_be_only_one 321 77
[[ ! -e "$SAM_TMP_ROOT/unexpected-tmux" ]]
''')

    def test_stop_treats_zombie_and_reused_pid_as_exited(self):
        self.assertShell('''mkdir -p "$mrsamtmp"; printf 'pid=321\\nstart=77\\n' > "$mrsamtmp/session-owner"
checks=0; sam_pid_start(){ checks=$((checks+1)); sam_proc_start=77; ((checks<3)); }
kill(){ :; }; tmux(){ touch "$SAM_TMP_ROOT/pane-closed"; }
there_can_be_only_one 321 77; [[ -e "$SAM_TMP_ROOT/pane-closed" ]]
rm "$SAM_TMP_ROOT/pane-closed"; checks=0
sam_pid_start(){ checks=$((checks+1)); if ((checks<3)); then sam_proc_start=77; else sam_proc_start=78; fi; }
there_can_be_only_one 321 77; [[ -e "$SAM_TMP_ROOT/pane-closed" ]]
''')

    def test_owned_tree_cancellation_reaches_blocking_grandchildren(self):
        self.assertShell('''(trap 'exit 0' TERM; sleep 60 & wait) & worker=$!
sleep 0.1; sam_pid_start "$worker"; sam_kill_tree "$worker"
wait "$worker" || true; ! sam_pid_start "$worker"
''')

    def test_tree_cancellation_rejects_wrong_root_start_ticks(self):
        self.assertShell('''sleep 60 & worker=$!; sam_pid_start "$worker"; original=$sam_proc_start
sam_kill_tree "$worker" "$((original+1))"; sam_pid_start "$worker"; [[ "$sam_proc_start" == "$original" ]]
kill -TERM "$worker"; wait "$worker" || true
''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
