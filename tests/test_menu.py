"""Dialog fixtures, with no MiSTer devices, network or live storage."""
import os
from pathlib import Path
import subprocess
import unittest
from paths import PACKAGE


class Menu(unittest.TestCase):
    def shell(self, code):
        bash = os.environ.get("SAM_TEST_BASH", "bash")
        root = PACKAGE.as_posix()
        prelude = r'''source "$SAM_PACKAGE/.MiSTer_SAM/lib/menu.sh"
source "$SAM_PACKAGE/.MiSTer_SAM/MiSTer_SAM_menu.sh"
sam_menu_file=$(mktemp)
trap 'rm -f "$sam_menu_file"' EXIT
clear() { :; }
parse_cmd() { printf 'CMD:%s\n' "$*"; }
samini_mod() { printf 'INI:%s=%s\n' "$1" "$2"; }
MENU_LOADED=1
sam_menu_run() { "$@"; }
'''
        env = dict(os.environ, SAM_PACKAGE=root)
        result = subprocess.run([bash, "-c", prelude+code], env=env,
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_main_commands_and_cancel(self):
        for action in ("start", "stop", "next", "play", "ignore"):
            out = self.shell('sam_dialog() { printf "%s" "'+action+'" >&2; }; sam_menu')
            self.assertEqual(out.strip(), "CMD:"+action)
        out = self.shell("sam_dialog() { echo start >&2; return 1; }; sam_menu")
        self.assertEqual(out, "")

    def test_unknown_main_choice_is_not_dispatched(self):
        self.assertEqual(self.shell(r'''n=0; sam_dialog() { ((n+=1));
if ((n==1)); then echo exit_to_menu >&2; else return 255; fi; }; sam_menu'''), "")

    def test_group_choice_is_allowed_and_cancel_ignores_stale_output(self):
        out = self.shell(r'''n=0; sam_dialog() { ((n+=1)); case $n in
1) echo exit_to_menu >&2;; 2) echo menu_mute >&2;;
*) echo menu_autoplay >&2; return 1;; esac; }; menu_settings''')
        self.assertEqual(out.strip(), "CMD:menu_mute")

    def test_video_cancel_preserves_ini_and_no_exec(self):
        self.assertEqual(self.shell(r'''sam_dialog() { case " $* " in
*" --menu "*) echo 1 >&2; return 255;; *) return 0;; esac; }
reset_ini() { echo RESET; }; menu_preset_svc'''), "")

    def test_video_second_question_cancel_preserves_ini(self):
        self.assertEqual(self.shell(r'''counter=$(mktemp); echo 0 > "$counter"
sam_dialog() { case " $* " in
*" --menu "*) read -r n < "$counter"; ((n+=1)); echo "$n" > "$counter"; echo 1 >&2; ((n==1));; *) return 0;; esac; }
reset_ini() { echo RESET; }; menu_preset_svc; rm -f "$counter"'''), "")

    def test_reset_does_not_destroy_core_array(self):
        out = self.shell(r'''declare -A CORE_PRETTY=([nes]=NES [snes]=SNES)
corelistall=(nes snes); gamelistpathtmp=$(mktemp -d)
rmdir "$gamelistpathtmp"
mkdir() { :; }; rm() { :; }; reset_ini
[[ ${#corelistall[@]} == 2 ]] || exit 1''')
        self.assertIn("INI:corelist=nes,snes", out)

    def test_timer_rejects_arithmetic_expression(self):
        out = self.shell(r'''shown_timer=1; n=0; sam_dialog() {
case " $* " in *" --menu "*) ((n+=1));
if ((n==1)); then echo 'gametimer2+3' >&2; else return 1; fi;; *) :;; esac; }
menu_sam_timer''')
        self.assertEqual(out, "")

    def test_show_all_clears_both_orientation_filters(self):
        out = self.shell(r'''n=0; sam_dialog() { case " $* " in
*" --menu "*) ((n+=1)); if ((n==1)); then echo arcadedisable >&2; else return 1; fi;;
*) :;; esac; }; menu_filters''')
        self.assertEqual(out.splitlines(), ["INI:arcadepathfilter=", "INI:arcadeorient="])

    def test_ini_editor_saves_spaces_inside_values(self):
        out = self.shell(r'''samini_file=$(mktemp)
printf 'name="A B"\n' > "$samini_file"
sam_dialog() { case " $* " in
*" --editbox "*) printf 'name="AB"\n' >&2;; *) :;; esac; }
menu_inieditor; cat "$samini_file"; rm -f "$samini_file"''')
        self.assertEqual(out.strip(), 'name="AB"')

    def test_controller_explains_global_mapping_without_legacy_writes(self):
        out = self.shell(r'''sam_dialog() { printf '%s\n' "$*"; }
jq() { echo FORBIDDEN_JSON; }; samini_mod() { echo FORBIDDEN_INI; }
menu_controller''')
        self.assertIn("Define joystick buttons", out)
        self.assertIn("sam_input_debug.py", out)
        self.assertNotIn("FORBIDDEN", out)

    def test_bgm_creates_music_directory_before_playlist_and_config(self):
        out = self.shell(r'''fixture=$(mktemp -d)
trap 'rm -rf "$fixture" "$sam_menu_file"' EXIT
SAM_BGM_SCRIPT="$fixture/bgm.sh"; SAM_BGM_MUSIC_DIR="$fixture/music"
echo installed > "$SAM_BGM_SCRIPT"
get_samstuff() { [[ -d "$2" ]] || return 99; echo PLAYLIST; touch "$2/80s.pls"; }
exec() { printf 'START:%s\n' "$*"; }
enablebgm''')
        self.assertEqual(out.splitlines()[:3], ["PLAYLIST", "INI:mute=No", "INI:bgm=Yes"])
        self.assertTrue(out.splitlines()[3].startswith("START:"))
        self.assertTrue(out.splitlines()[3].endswith(" start"))

    def test_bgm_download_failure_preserves_configuration(self):
        out = self.shell(r'''fixture=$(mktemp -d)
trap 'rm -rf "$fixture" "$sam_menu_file"' EXIT
SAM_BGM_SCRIPT="$fixture/bgm.sh"; SAM_BGM_MUSIC_DIR="$fixture/music"
curl_download() { return 1; }; sam_dialog() { :; }
exec() { echo FORBIDDEN_START; }
if enablebgm; then exit 1; fi''')
        self.assertEqual(out, "")

    def test_bgm_playlist_failure_preserves_configuration(self):
        out = self.shell(r'''fixture=$(mktemp -d)
trap 'rm -rf "$fixture" "$sam_menu_file"' EXIT
SAM_BGM_SCRIPT="$fixture/bgm.sh"; SAM_BGM_MUSIC_DIR="$fixture/music"
echo installed > "$SAM_BGM_SCRIPT"
get_samstuff() { return 1; }; exec() { echo FORBIDDEN_START; }
if enablebgm; then exit 1; fi''')
        self.assertEqual(out, "")

    def test_disable_bgm_preserves_external_installation(self):
        out = self.shell(r'''shown_bgmmenu=1; n=0
rm() { echo FORBIDDEN_RM; }; sed() { echo FORBIDDEN_SED; }
bgm_stop() { printf 'STOP:%s\n' "$*"; }
sam_dialog() { case " $* " in
*" --menu "*) ((n+=1)); if ((n==1)); then echo disablebgm >&2; else return 1; fi;;
*) :;; esac; }
menu_addons
unset -f rm''')
        self.assertEqual(out.splitlines(), ["STOP:force", "INI:bgm=No"])

    def test_failed_preset_start_preserves_mcp_and_releases_ui(self):
        out = self.shell(r'''mcp_stop() { echo FORBIDDEN_MCP_STOP; }
sam_menu_release_for_exec() { echo RELEASE_UI; }
exec() { echo FAILED_START; return 9; }
if sam_preset_start; then exit 1; fi''')
        self.assertEqual(out.splitlines(), ["RELEASE_UI", "FAILED_START"])

    def test_reset_failure_restores_previously_running_mcp(self):
        out = self.shell(r'''tmux() { return 0; }
mcp_stop() { echo MCP_STOP; }; mcp_start() { echo MCP_RESTART; }
sam_menu_resetini_apply() { echo RESET_FAILED; return 7; }
menu_resetini; [[ $? == 7 ]]''')
        self.assertEqual(out.splitlines(), ["MCP_STOP", "RESET_FAILED", "MCP_RESTART"])

    def test_reset_does_not_delete_runtime_if_gateway_stop_fails(self):
        out = self.shell(r'''python3() { echo STOP_REFUSED; return 1; }
rm() { echo FORBIDDEN_DELETE; }
if sam_menu_resetini_apply; then exit 1; fi
unset -f rm''')
        self.assertEqual(out.strip(), "STOP_REFUSED")

    def test_reset_stops_owner_before_clearing_private_lists(self):
        out = self.shell(r'''python3() { echo OWNER_STOP; }
rm() { printf 'REMOVE:%s\n' "$*"; }
gamelistpathtmp=/isolated/lists; mrsamtmp=/isolated/runtime
samini_mod() { echo SAVE_INI; }
sam_menu_resetini_apply m82
unset -f rm''')
        self.assertEqual(out.splitlines(), ["OWNER_STOP", "REMOVE:-rf -- /isolated/lists", "REMOVE:-f -- /isolated/runtime/category-preset /isolated/runtime/gameroulette.ini", "SAVE_INI"])

    def test_failed_mcp_quiesce_restores_monitor_without_resetting(self):
        out = self.shell(r'''tmux() { return 0; }
mcp_stop() { echo MCP_STOP_FAILED; return 8; }
mcp_start() { echo MCP_RESTART; }
sam_menu_resetini_apply() { echo FORBIDDEN_RESET; }
menu_resetini; [[ $? == 8 ]]''')
        self.assertEqual(out.splitlines(), ["MCP_STOP_FAILED", "MCP_RESTART"])

    def test_reset_does_not_enable_previously_inactive_mcp(self):
        out = self.shell(r'''tmux() { return 1; }; python3() { return 1; }
mcp_stop() { echo MCP_QUIESCE; }; mcp_start() { echo FORBIDDEN_START; }
sam_menu_resetini_apply() { echo RESET; }
menu_resetini''')
        self.assertEqual(out.splitlines(), ["MCP_QUIESCE", "RESET"])


if __name__ == "__main__":
    unittest.main()
