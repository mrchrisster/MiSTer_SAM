"""Preset transitions preserve canceled choices and honor the selected INI."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from paths import PACKAGE


class Presets(unittest.TestCase):
    def run_case(self, body):
        with tempfile.TemporaryDirectory(prefix='sam-presets-', dir=PACKAGE/'tests') as directory:
            env = dict(os.environ, SAM_PACKAGE=PACKAGE.as_posix(), FIXTURE=Path(directory).as_posix())
            code = '''
source "$SAM_PACKAGE/.MiSTer_SAM/lib/config.sh"
source "$SAM_PACKAGE/.MiSTer_SAM/MiSTer_SAM_menu.sh"
samini_file="$FIXTURE/SAM.ini"
mrsampath="$SAM_PACKAGE/.MiSTer_SAM"
mrsamtmp="$FIXTURE/runtime"
sam_menu_file="$FIXTURE/choice"
mkdir -p "$mrsamtmp"
printf 'corelist="snes"\nmute="No"\nm82="yes"\n' > "$samini_file"
declare -A CORE_PRETTY=([nes]=NES [snes]=SNES)
clear(){ :; }
''' + body
            return subprocess.run([os.environ.get('SAM_TEST_BASH', 'bash'), '-c', code],
                                  env=env, capture_output=True, text=True, timeout=15)

    def assert_pass(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_ini_editor_uses_active_file_and_explicit_target(self):
        self.assert_pass(self.run_case('''
samini_mod mute Yes
grep -qx 'mute="Yes"' "$samini_file" || exit 1
printf 'mute="No"\n' > "$FIXTURE/other.ini"
samini_mod mute No "$FIXTURE/other.ini"
grep -qx 'mute="Yes"' "$samini_file" && grep -qx 'mute="No"' "$FIXTURE/other.ini"
'''))

    def test_special_mode_effective_artwork_override_does_not_rewrite_ini(self):
        for mode in ('m82','samvideo'):
            with self.subTest(mode=mode):
                self.assert_pass(self.run_case('''
SAM_INI="$samini_file" SAM_ROOT="$mrsampath" SAM_TMP_ROOT="$mrsamtmp" init_vars
printf 'Artwork_only="Yes"\n'''+mode+'''="Yes"\n' > "$samini_file"
cp "$samini_file" "$FIXTURE/before"
read_samini || exit 1
[[ "${Artwork_only,,}" == no ]] && cmp "$samini_file" "$FIXTURE/before"
'''))

    def test_m82_preset_persists_artwork_off(self):
        self.assert_pass(self.run_case('''
sam_dialog(){ :; }; sam_preset_start(){ :; }; m82_game_timer=180
menu_preset_m82_mode
grep -qx 'Artwork_only="No"' "$samini_file"
'''))

    def test_kids_corelist_uses_only_present_nonempty_whitelists(self):
        self.assert_pass(self.run_case('''
ratedpath="$FIXTURE/Rated"; mkdir -p "$ratedpath"
printf 'Mario\n' > "$ratedpath/nes_rated.txt"
printf 'Mature\n' > "$ratedpath/tgfx16cd_mature.txt"
: > "$ratedpath/psx_rated.txt"
sam_dialog(){ :; }; sam_preset_start(){ :; }
menu_preset_kids
grep -qx 'corelist="nes"' "$samini_file"
'''))

    def test_reset_clears_roulette_without_deleting_shared_state(self):
        self.assert_pass(self.run_case('''
touch "$mrsamtmp/gameroulette.ini" "$mrsamtmp/session-owner"
reset_ini
[[ ! -e "$mrsamtmp/gameroulette.ini" && -f "$mrsamtmp/session-owner" ]]
'''))

    def test_cancel_roulette_preserves_ini_and_current_roulette(self):
        self.assert_pass(self.run_case('''
cp "$samini_file" "$FIXTURE/before"
printf 'gametimer=17\n' > "$mrsamtmp/gameroulette.ini"
sam_dialog(){ case " $* " in *" --menu "*) return 1;; *) return 0;; esac; }
menu_preset_roulette_mode
cmp "$samini_file" "$FIXTURE/before" && grep -qx 'gametimer=17' "$mrsamtmp/gameroulette.ini"
'''))

    def test_roulette_rejects_expression_without_configuration_change(self):
        self.assert_pass(self.run_case('''
cp "$samini_file" "$FIXTURE/before"
n=0
sam_dialog(){ case " $* " in *" --menu "*) ((n+=1)); if ((n==1)); then echo 'Roulette2+3' >&2; else return 1; fi;; *) return 0;; esac; }
menu_preset_roulette_mode
cmp "$samini_file" "$FIXTURE/before" && [[ ! -e "$mrsamtmp/gameroulette.ini" ]]
'''))

    def test_80s_does_not_start_after_bgm_setup_failure(self):
        self.assert_pass(self.run_case('''
enablebgm(){ return 29; }
exec(){ echo BAD_START; }
rc=0; menu_preset_80s || rc=$?
[[ "$rc" == 29 ]]
'''))

    def test_uncached_artwork_system_has_a_valid_stamp(self):
        self.assert_pass(self.run_case('''
mrsampath="$SAM_PACKAGE/.MiSTer_SAM"
source "$mrsampath/artwork/sam_artwork.sh"
sam_artwork_root="$FIXTURE/missing-artwork"
sam_artwork_resolver="$sam_artwork_root/resolver.py"
gamelistpath="$FIXTURE/missing-lists"
Artwork_source=database
sam_artwork_stamp 3do > "$FIXTURE/stamp" || exit 1
grep -q 'source=database' "$FIXTURE/stamp"
'''))

    def test_goat_rejects_unlisted_cores_and_uses_custom_list(self):
        self.assert_pass(self.run_case('''
source "$SAM_PACKAGE/.MiSTer_SAM/lib/modules.sh"
gamelistpath="$FIXTURE"
printf '[NEOGEO]\ngarou\n' > "$gamelistpath/sam_goat_list.txt"
printf '[SNES]\r\nSuper Metroid\r\n[NES]\r\n' > "$gamelistpath/sam_goat_list_custom.txt"
mrsampath="$SAM_PACKAGE/.MiSTer_SAM"
sam_load_module curated
sam_curated_core_allowed snes || exit 1
! sam_curated_core_allowed neogeo && ! sam_curated_core_allowed nes
'''))

    def test_rating_whitelists_normalize_crlf_and_ignore_empty_lines(self):
        for rating in ('kids','mature'):
            with self.subTest(rating=rating):
                self.assert_pass(self.run_case('''
source "$SAM_PACKAGE/.MiSTer_SAM/lib/filter.sh"
mrsampath="$SAM_PACKAGE/.MiSTer_SAM"
ratedpath="$FIXTURE"
tmpfilefilter="$FIXTURE/result"
rating='''+rating+'''
suffix=rated; [[ "$rating" != mature ]] || suffix=mature
printf 'Alpha\r\n\r\nBeta\r\n' > "$ratedpath/nes_$suffix.txt"
printf '/roms/Alpha (USA).nes\n/roms/Beta (USA).nes\n/roms/Other.nes\n' > "$FIXTURE/candidates"
apply_ratings_filter nes "$FIXTURE/candidates" || exit 1
[[ $(wc -l < "$FIXTURE/candidates") == 2 ]] && ! grep -q Other "$FIXTURE/candidates"
'''))

    def test_m82_preserves_crlf_slots_and_final_line_without_global_sync(self):
        self.assert_pass(self.run_case('''
source "$SAM_PACKAGE/.MiSTer_SAM/modules/compat-catalog.sh"
gamelistpath="$FIXTURE"
gamelistpathtmp="$FIXTURE/session-lists"
mkdir -p "$gamelistpathtmp"
printf '/roms/M82 Game.nes\n/roms/Alpha.nes\n/roms/Beta.nes\n' > "$gamelistpath/nes_gamelist.txt"
printf 'Alpha\r\nBeta' > "$gamelistpath/m82_list.txt"
ensure_list(){ return 0; }
samdebug(){ :; }
sync(){ echo FORBIDDEN_SYNC; return 99; }
m82=yes;sam_goat_list=no;SAM_ACTION=
check_list nes || exit 1
[[ $(wc -l < "$gamelistpathtmp/nes_gamelist.txt") == 4 ]] && grep -qx '/roms/Beta.nes' "$gamelistpathtmp/nes_gamelist.txt"
'''))

    def test_preset_launch_preserves_mcp_and_releases_ui(self):
        result=self.run_case('''
mcp_stop(){ echo STOP_MCP; }
exec(){ echo "START:$*"; }
SAM_ENTRY=fixture-entry
sam_preset_start
''')
        self.assert_pass(result)
        self.assertEqual(result.stdout.splitlines(),['START:fixture-entry start'])

    def test_preset_does_not_depend_on_mcp_shutdown(self):
        self.assert_pass(self.run_case('''
mcp_stop(){ return 31; }
exec(){ echo FORBIDDEN_START; }
rc=0;sam_preset_start || rc=$?
[[ "$rc" == 0 ]]
'''))

    def test_confirmed_mature_ecw_console_versions_are_not_kids_candidates(self):
        for core in ('psx','n64'):
            with self.subTest(core=core):
                self.assert_pass(self.run_case('''
source "$SAM_PACKAGE/.MiSTer_SAM/lib/filter.sh"
ratedpath="$SAM_PACKAGE/SAM/Rated"
tmpfilefilter="$FIXTURE/result"
rating=kids
printf '/games/ECW Hardcore Revolution (USA).chd\n/games/ECW - Hardcore Revolution (USA).chd\n' > "$FIXTURE/candidates"
rc=0;apply_ratings_filter '''+core+''' "$FIXTURE/candidates" || rc=$?
[[ "$rc" == 1 && ! -s "$FIXTURE/candidates" ]]
'''))


if __name__ == '__main__':
    unittest.main()
