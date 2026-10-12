"""Fixed-operation mode hooks use the real Bash timers without hardware I/O."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from paths import PACKAGE


class EngineModes(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sam-mode-hooks-", dir=PACKAGE)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bash = shutil.which("bash")
        if os.name == "nt":
            installed = Path("C:/Program Files/Git/bin/bash.exe")
            if installed.is_file():
                self.bash = str(installed)
        if not self.bash:
            self.skipTest("Bash is required")

    def shell(self, code):
        prelude = r'''
set -e
source "$SAM_ROOT/lib/state.sh"
source "$SAM_ROOT/modules/m82-functions.sh"
source "$SAM_ROOT/lib/engine-modes.sh"
mrsamtmp=$TEST_ROOT sam_session=$TEST_ROOT sam_revision=1 sam_generation=1
sam_owner=123:77 sam_launch_serial=7 sam_mode=normal
gametimer=21 m82_game_timer=180 rompath=/games/A.nes m82_bios_path=/games/BIOS.nes
sam_publish_phase(){ printf 'phase:%s\n' "$1" >> "$TEST_ROOT/events"; }
sam_emit(){ printf 'event:%s:%s:%s\n' "$1" "${2:-}" "${3:-}" >> "$TEST_ROOT/events"; }
sam_service(){ printf 'service:%s\n' "$1" >> "$TEST_ROOT/events"; }
sam_config_timer_update(){ :; }
sam_schedule_preparation(){ printf 'prepare\n' >> "$TEST_ROOT/events"; }
sam_session_ui_handoff_ready(){ printf 'handoff:%s\n' "$1" >> "$TEST_ROOT/events"; }
sam_request_next(){ SAM_ACTION=next; sam_emit controls_ready 0; sam_emit display_publish; }
sam_diagnostic(){ :; }
sam_restore_audio(){ printf 'restore\n' >> "$TEST_ROOT/events"; }
toggle_mute(){ printf 'mute\n' >> "$TEST_ROOT/events"; }
samdebug(){ :; }
sam_cancel_launch_job(){ :; }
# Freeze Bash's special elapsed clock for these explicit deadline fixtures.
# Slow ARM execution must not advance it between two same-time samples.
unset SECONDS
SECONDS=10
'''
        def bash_path(path):
            value = path.as_posix()
            if os.name == "nt" and len(value) > 2 and value[1] == ":":
                return "/" + value[0].lower() + value[2:]
            return value

        result = subprocess.run(
            [self.bash, "-c", prelude + code],
            env=dict(os.environ, SAM_ROOT=bash_path(PACKAGE / ".MiSTer_SAM"),
                     TEST_ROOT=bash_path(self.root)),
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)
        return (self.root / "events").read_text() if (self.root / "events").exists() else ""

    def test_m82_bios_does_not_restore_audio_or_ack_play(self):
        events = self.shell(r'''
sam_mode=m82 rompath=$m82_bios_path
sam_engine_mode_timer_begin
sam_engine_mode_timer_key y
[[ "$m82_play_triggered" == 0 && "$sam_engine_m82_phase" == bios ]]
grep -q '^phase=bios$' "$sam_session/m82-phase"
''')
        self.assertNotIn("restore\n", events)
        self.assertIn("event:controls_ready:1:", events)

    def test_builtin_programmes_register_shared_engine_services(self):
        for module in ('m82', 'video'):
            with self.subTest(module=module):
                self.shell('''
source "$SAM_ROOT/lib/modules.sh"
mrsampath=$SAM_ROOT
sam_engine_adapter_verified=1
sam_engine_normal_take(){ :; }
sam_engine_normal_launch(){ :; }
sam_bind engine_take sam_engine_normal_take
sam_bind engine_launch sam_engine_normal_launch
sam_load_module ''' + module + '''
[[ "${SAM_SERVICES[engine_take]}" == sam_engine_program_take ]]
[[ "${SAM_SERVICES[engine_launch]}" == sam_engine_program_launch ]]
''')

    def test_m82_audio_failure_retries_and_infinite_play_never_expires(self):
        events = self.shell(r'''
sam_mode=m82 m82_game_timer=0
sam_engine_mode_timer_begin
restores=0
sam_restore_audio(){ restores=$((restores+1)); ((restores > 1)); }
rc=0; sam_engine_mode_timer_key y || rc=$?
[[ "$rc" == 2 ]]
[[ "$m82_play_triggered" == 0 ]]
grep -q '^phase=game$' "$sam_session/m82-phase"
sam_engine_mode_timer_key y
sam_engine_mode_timer_key y
[[ "$restores" == 2 && "$m82_is_infinite" == 1 && "$sam_frozen" == 0 ]]
grep -q '^launch=7$' "$sam_session/m82-phase"
grep -q '^phase=play$' "$sam_session/m82-phase"
SECONDS=200000
sam_engine_mode_timer_tick
''')
        self.assertNotIn("event:controls_ready:0:", events)

    def test_m82_finite_game_expires_and_disables_controls(self):
        events = self.shell(r'''
sam_mode=m82 m82_game_timer=3
sam_engine_mode_timer_begin
sam_engine_mode_timer_key y
[[ "$end_time" == 13 ]]
SECONDS=13
rc=0; sam_engine_mode_timer_tick || rc=$?
[[ "$rc" == 1 ]]
''')
        self.assertEqual(events.count("restore\n"), 1)
        self.assertIn("event:controls_ready:0:", events)

    def test_pause_claim_at_expiry_preserves_current_game(self):
        self.shell(r'''
sam_mode=m82
sam_engine_mode_timer_begin
SECONDS=$end_time
sam_emit(){
    if [[ "$1" == countdown_tick ]]; then sam_paused=1 sam_frozen=4; fi
}
sam_engine_mode_timer_tick
[[ "$sam_paused" == 1 ]]
''')

    def test_video_loading_extends_deadline_and_syncs_once(self):
        events = self.shell(r'''
sam_mode=samvideo sv_nextcore=samvideo gametimer=0
sv_gametimer_file=$TEST_ROOT/video-time
sam_engine_mode_timer_begin
[[ "$video_synced" == no && "$end_time" == 70 ]]
SECONDS=68
printf invalid > "$sv_gametimer_file"
sam_engine_mode_timer_tick
[[ "$video_synced" == no && "$end_time" == 78 ]]
printf '08\n' > "$sv_gametimer_file"
sam_engine_mode_timer_tick
[[ "$video_synced" == yes && "$end_time" == 76 ]]
[[ ! -e "$sv_gametimer_file" ]]
SECONDS=76
rc=0; sam_engine_mode_timer_tick || rc=$?
[[ "$rc" == 1 ]]
''')
        self.assertEqual(events.count("handoff:1"), 1)
        self.assertIn("phase:video\n", events)
        self.assertNotIn("prepare\n", events)

    def test_synchronized_zero_video_advances_with_zero_game_interval(self):
        self.shell(r'''
sam_mode=samvideo sv_nextcore=samvideo gametimer=0
sv_gametimer_file=$TEST_ROOT/video-time
sam_engine_mode_timer_begin
printf '0\n' > "$sv_gametimer_file"
rc=0; sam_engine_mode_timer_tick || rc=$?
[[ "$rc" == 1 ]]
''')

    def test_normal_zero_is_indefinite_and_prepares_only_once_per_second(self):
        events = self.shell(r'''
gametimer=0
sam_engine_mode_timer_begin
sam_engine_mode_timer_tick
sam_engine_mode_timer_tick
SECONDS=200000
sam_engine_mode_timer_tick
sam_engine_mode_timer_tick
''')
        self.assertEqual(events.count("prepare\n"), 2)
        self.assertIn("service:timer_begin\n", events)
        self.assertIn("event:countdown_start:", events)

    def test_previous_next_and_mute_keys_have_fixed_results(self):
        events = self.shell(r'''
sam_engine_mode_timer_begin
sam_engine_mode_timer_key m
rc=0; sam_engine_mode_timer_key n || rc=$?
[[ "$rc" == 1 && "$SAM_ACTION" == next ]]
rc=0; sam_engine_mode_timer_key p || rc=$?
[[ "$rc" == 1 && "$SAM_ACTION" == previous ]]
''')
        self.assertIn("mute\n", events)

    def test_step_retry_and_fatal_results_preserve_next_for_m82_selector(self):
        self.shell(r'''
sam_mode=m82 SAM_ACTION=next sam_engine_m82_phase=game m82_play_triggered=0
next_core(){ [[ "$SAM_ACTION" == next ]]; return 1; }
rc=0; sam_engine_mode_step nes || rc=$?
[[ "$rc" == 1 && -z "$SAM_ACTION" ]]
[[ "$sam_engine_m82_phase" == loading ]]
sam_engine_mode_timer_key y
[[ ! -e "$sam_session/m82-phase" ]]
next_core(){ return 7; }
rc=0; sam_engine_mode_step nes || rc=$?
[[ "$rc" == 7 ]]
''')

    def test_video_selection_preserves_frequency_and_uses_owned_launch_job(self):
        events = self.shell(r'''
sam_job_spawn(){ printf 'owned:%s:%s\n' "$1" "$2" >> "$TEST_ROOT/events"; }
corelist=(nes snes) samvideo_freq=alternate sv_loadcounter=0
rc=0; sam_engine_mode_video_load || rc=$?
[[ "$rc" == 1 && "$sv_loadcounter" == 1 ]]
rc=0; sam_engine_mode_video_load || rc=$?
[[ "$rc" == 0 && "$sv_loadcounter" == 2 && -z "$sv_nextcore" ]]
samvideo_freq=core sv_loadcounter=1
rc=0; sam_engine_mode_video_load || rc=$?
[[ "$rc" == 1 && "$sv_loadcounter" == 0 ]]
samvideo_freq=only
sam_job_spawn(){ return 1; }
rc=0; sam_engine_mode_video_load || rc=$?
[[ "$rc" == 2 ]]
''')
        self.assertEqual(events.count("owned:sam_launch:samvideo_play\n"), 2)

    def test_m82_real_sequence_next_skips_bios_previous_replays_game(self):
        events = self.shell(r'''
source "$SAM_ROOT/modules/compat-selection.sh"
source "$SAM_ROOT/modules/compat-catalog.sh"
source "$SAM_ROOT/modules/compat-loop.sh"
sam_mode=m82 m82=yes samvideo=no
gamelistpath=$TEST_ROOT/master gamelistpathtmp=$TEST_ROOT/lists
mkdir -p "$gamelistpath" "$gamelistpathtmp"
m82_bios_path=$TEST_ROOT/BIOS.nes
printf '%s\n' "$m82_bios_path" "$TEST_ROOT/A.nes" "$TEST_ROOT/B.nes" > "$gamelistpath/nes_gamelist.txt"
printf 'A.nes\nB.nes\n' > "$gamelistpath/m82_list.txt"
ensure_list(){ :; }
sam_core_require(){ :; }
corelist_update(){ :; }
sam_is_excluded(){ return 1; }
check_rom(){ romname=${rompath##*/}; return 0; }
load_core(){ gamename=${3:-${2##*/}}; printf 'load:%s\n' "$2" >> "$TEST_ROOT/events"; }
coreretries=1 check_for_new_games=no cfgcore_configpath=
sam_engine_mode_step nes
[[ "$rompath" == "$m82_bios_path" ]]
sam_engine_mode_step nes
[[ "$rompath" == "$TEST_ROOT/A.nes" ]]
SAM_ACTION=next; sam_engine_mode_step nes
[[ "$rompath" == "$TEST_ROOT/B.nes" ]]
SAM_ACTION=previous; sam_engine_mode_step nes
[[ "$rompath" == "$TEST_ROOT/A.nes" ]]
''')
        self.assertEqual([Path(line[5:]).name for line in events.splitlines() if line.startswith("load:")],
                         ["BIOS.nes", "A.nes", "B.nes", "A.nes"])

    def test_config_reload_switches_infinite_m82_play_to_finite(self):
        self.shell(r'''
source "$SAM_ROOT/lib/config-reload.sh"
sam_config_read_update(){
    sam_reload_debug=no sam_reload_debuglog=no sam_reload_m82timer=$requested_timer
}
sam_mode=m82 m82_game_timer=0 requested_timer=0
sam_engine_mode_timer_begin
sam_engine_mode_timer_key y
SECONDS=200000 requested_timer=7
sam_engine_mode_timer_tick
[[ "$m82_is_infinite" == 0 && "$end_time" == 200007 && "$m82_game_timer" == 7 ]]
SECONDS=200007
rc=0; sam_engine_mode_timer_tick || rc=$?
[[ "$rc" == 1 ]]
''')

    def test_config_reload_keeps_global_normal_timer_deadline(self):
        self.shell(r'''
source "$SAM_ROOT/lib/config-reload.sh"
sam_config_read_update(){ sam_reload_debug=no sam_reload_debuglog=no sam_reload_timer=$requested_timer; }
gametimer=5 requested_timer=9
sam_engine_mode_timer_begin
sam_engine_mode_timer_tick
[[ "$end_time" == 19 && "$gametimer" == 9 ]]
SECONDS=19
rc=0; sam_engine_mode_timer_tick || rc=$?
[[ "$rc" == 1 ]]
''')


if __name__ == "__main__":
    unittest.main()
