"""Native Bash reload fences and timer adjustment; no hardware commands."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from paths import PACKAGE


@unittest.skipUnless(sys.platform.startswith('linux'), 'native Linux Bash required')
class ReloadShell(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        ini = root / 'SAM.ini'
        ini.write_text('corelist="snes,nes"\ncorelistall="snes,nes"\ngametimer=180\n')
        self.env = dict(os.environ, SAM_ROOT=str(PACKAGE / '.MiSTer_SAM'), SAM_MODULES_OVERRIDE='',
                        SAM_INI=str(ini), SAM_TMP_ROOT=str(root / 'runtime'),
                        SAM_LIST_ROOT=str(root / 'lists'), SAM_SESSION_LIST_ROOT=str(root / 'session-lists'),
                        SAM_STATE_FILE=str(root / 'state'), SAM_CONFIG_ROOT=str(root / 'config'),
                        SAM_MISTER_ROOT=str(root / 'media'))

    def shell(self, code):
        prelude = '''set -e
source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
sam_session_begin
sam_emit(){ :; }
write_marker(){
    printf 'pid=%s\\nstart=%s\\nrevision=%064d\\nstructural=0\\nselection=%s\\ngametimer=%s\\nsetting_corelist=nes\\nsetting_corelistall=nes\\nsetting_rating=yes\\nexclude_0=read me\\nexclude_1=bios\\n' "$$" "${sam_owner#*:}" 1 "$1" "$2" > "$sam_session/config-update"
}
'''
        result = subprocess.run(['bash', '-c', prelude + code], env=self.env, text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def test_timer_adjusts_remaining_and_pause_without_restarting_game(self):
        self.shell('''test_timer(){
local end_time=$((SECONDS+100)) sam_paused=1 sam_frozen=90
gametimer=180; write_marker 0 120
sam_config_timer_update
[[ "$gametimer" == 120 && "$sam_frozen" == 30 && "$end_time" == "$((SECONDS+40))" ]]
write_marker 0 0; sam_config_timer_update
[[ "$gametimer" == 0 && "$sam_frozen" == 0 ]]
write_marker 0 50; sam_config_timer_update
[[ "$gametimer" == 50 && "$sam_frozen" == 50 ]]
}; test_timer
''')

    def test_selection_cancels_preparer_then_discards_old_proposals(self):
        self.shell('''write_marker 1 180
printf old > "$sam_session/ready/00000010.record"
printf 'reason=no_eligible_games\nrevision=%s\n' "$sam_revision" > "$sam_session/outcome"
printf 'No eligible games found\n' > "$sam_session/error"
sam_cancel_preparation(){ printf cancelled > "$sam_session/cancelled"; }
old_revision=$sam_revision
sam_config_game_boundary
[[ -f "$sam_session/cancelled" && ! -f "$sam_session/ready/00000010.record" ]]
[[ ! -e "$sam_session/outcome" && ! -e "$sam_session/error" ]]
[[ "$sam_revision" == "$((old_revision+1))" && "${corelist[*]}" == nes && "$rating" == yes ]]
[[ "${exclude[0]}" == 'read me' && "${exclude[1]}" == bios ]]
sam_config_game_boundary
[[ "$sam_revision" == "$((old_revision+1))" ]]
''')

    def test_stale_owner_marker_cannot_change_timer_or_policy(self):
        self.shell('''write_marker 1 20
sed -i 's/^pid=.*/pid=999999/' "$sam_session/config-update"
test_timer(){ local end_time=$((SECONDS+180)) sam_paused=0 sam_frozen=0; sam_config_timer_update; }
test_timer; sam_config_game_boundary
[[ "$gametimer" == 180 && "${corelist[*]}" == 'snes nes' ]]
''')

    def test_m82_play_timer_reload_updates_pause_and_published_counter(self):
        self.shell('''test_m82(){
local end_time=$((SECONDS+100)) sam_paused=1 sam_frozen=90 m82_play_triggered=1 m82_is_infinite=0
sam_mode=m82; gametimer=21; m82_game_timer=180
sam_emit(){ [[ "$1" != display_publish ]] || printf '%s:%s\\n' "$2" "$3" > "$sam_session/timer-published"; }
write_marker 0 180; printf 'm82timer=120\\n' >> "$sam_session/config-update"
sam_config_timer_update
[[ "$gametimer" == 21 && "$m82_game_timer" == 120 && "$sam_frozen" == 30 && "$end_time" == "$((SECONDS+40))" ]]
IFS=: read -r published deadline < "$sam_session/timer-published"
[[ "$published" == 30 && "$deadline" == "$((EPOCHSECONDS+30))" ]]
write_marker 0 180; printf 'm82timer=0\\n' >> "$sam_session/config-update"
sam_config_timer_update
[[ "$m82_game_timer" == 0 && "$m82_is_infinite" == 1 && "$sam_frozen" == 86400 ]]
IFS=: read -r published deadline < "$sam_session/timer-published"
[[ "$published" == 0 ]]
write_marker 0 180; printf 'm82timer=50\\n' >> "$sam_session/config-update"
sam_config_timer_update
[[ "$m82_game_timer" == 50 && "$m82_is_infinite" == 0 && "$sam_frozen" == 50 && "$end_time" == "$((SECONDS+50))" ]]
IFS=: read -r published deadline < "$sam_session/timer-published"
[[ "$published" == 50 && "$deadline" == "$((EPOCHSECONDS+50))" ]]
}; test_m82
''')

    def test_m82_demo_timer_stays_fixed_until_play(self):
        self.shell('''test_m82_demo(){
local end_time=$((SECONDS+21)) sam_paused=0 sam_frozen=0 m82_play_triggered=0 m82_is_infinite=0
local expected_deadline=$end_time
sam_mode=m82; gametimer=21; m82_game_timer=180
sam_emit(){ [[ "$1" != display_publish ]] || { echo unexpected-publish >&2; return 99; }; }
write_marker 0 10; printf 'm82timer=60\\n' >> "$sam_session/config-update"
sam_config_timer_update
[[ "$gametimer" == 21 && "$m82_game_timer" == 60 && "$end_time" == "$expected_deadline" ]]
}; test_m82_demo
''')

    def test_video_generic_interval_updates_only_at_game_boundary(self):
        self.shell('''test_video(){
local end_time=$((SECONDS+42)) sam_paused=0 sam_frozen=0
local expected_deadline=$end_time
sam_mode=samvideo; gametimer=180
sam_cancel_preparation(){ printf cancelled > "$sam_session/unexpected-cancellation"; }
write_marker 0 60
sam_config_timer_update
[[ "$gametimer" == 180 && "$end_time" == "$expected_deadline" ]]
old_revision=$sam_revision
sam_config_game_boundary
[[ "$gametimer" == 60 && "$end_time" == "$expected_deadline" && "$sam_revision" == "$old_revision" ]]
[[ ! -f "$sam_session/config-boundary" ]]
[[ ! -f "$sam_session/unexpected-cancellation" ]]
}; test_video
''')


if __name__ == '__main__':
    unittest.main()
