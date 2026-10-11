"""BGM process ownership and bounded command fixtures; no real music or kills."""
import ast
import os
import sys
from types import SimpleNamespace
from pathlib import Path
import subprocess
import unittest
from paths import PACKAGE


class BGM(unittest.TestCase):
    def test_policy_uses_supplied_cleanup_owner_and_active_session_owner(self):
        out = self.shell(r'''SAM_BGM_CLIENT="$sam_bgm_proc/client.py";touch "$SAM_BGM_CLIENT"
sam_bgm_record_matches(){ sam_bgm_owned_pid=101;sam_bgm_owned_start=77;sam_bgm_owned_socket=identity; }
sam_bgm_socket_owned(){ return 0; }
stat(){ printf identity; }
python3(){ while (($#));do if [[ "$1" == --owner ]];then printf 'OWNER:%s\n' "$2";break;fi;shift;done; }
sam_owner=123:456;sam_exit_expected_owner=222:333;sam_bgm_policy_owner=444:555
sam_bgm_policy menu
sam_bgm_policy active
unset sam_bgm_policy_owner
sam_bgm_policy game''')
        self.assertEqual(out.splitlines(), ['OWNER:444:555', 'OWNER:123:456', 'OWNER:222:333'])

    def test_modern_stage_ack_avoids_legacy_commands_and_status_queries(self):
        out = self.shell(r'''fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
sam_bgm_record_matches(){ return 0; }
sam_bgm_policy(){ printf 'POLICY:%s\n' "$1"; }
bgm=yes;bgmstop=no
bgm_start
sam_bgm_menu_prepare
bgm_stop menu
bgm_stop game''')
        self.assertEqual(out.splitlines(), ['POLICY:active', 'POLICY:menu', 'POLICY:menu', 'POLICY:game'])

    def test_failed_modern_policy_does_not_fall_back_to_legacy_mutations(self):
        out = self.shell(r'''fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
sam_bgm_record_matches(){ return 0; }
sam_bgm_policy(){ return 1; }
bgm=yes;bgmstop=no
if bgm_start;then exit 1;fi
if sam_bgm_menu_prepare;then exit 1;fi
if bgm_stop game;then exit 1;fi''')
        self.assertEqual(out, '')

    def shell(self, body):
        prelude = r'''sam_bgm_proc=$(mktemp -d)
mrsamtmp=$sam_bgm_proc
export SAM_BGM_PROC_ROOT="$sam_bgm_proc" SAM_BGM_OWNER_FILE="$sam_bgm_proc/owner" SAM_BGM_SOCKET="$sam_bgm_proc/socket"
trap 'rm -rf "$sam_bgm_proc"' EXIT
source "$SAM_PACKAGE/.MiSTer_SAM/modules/bgm-functions.sh"
sam_bgm_script=/media/fat/Scripts/bgm.sh
fakeproc() {
 local pid=$1 executable=$2; shift 2
 mkdir -p "$sam_bgm_proc/$pid"
 printf '%s' "$executable" > "$sam_bgm_proc/$pid/executable"
 printf '%s\0' "$@" > "$sam_bgm_proc/$pid/cmdline"
 { printf '%s (bgm) S' "$pid";for ((i=1;i<=18;i++));do printf ' 0';done;printf ' 77\n'; } > "$sam_bgm_proc/$pid/stat"
}
readlink() { cat "${1%/exe}/executable"; }
kill() { printf 'KILL:%s\n' "$*"; rm -f "$sam_bgm_proc/${@: -1}/stat"; }
sam_bgm_command() { printf 'COMMAND:%s\n' "$1"; }
sam_bgm_query() { case "$1" in 'get playback') printf random;;status) printf 'no\trandom\tnone\t';;'get playincore') printf no;;*) return 1;;esac; }
sed() { echo 'FORBIDDEN_SETTINGS_WRITE' >&2;return 99; } # Startup must never change user settings.
'''
        result = subprocess.run([os.environ.get("SAM_TEST_BASH", "bash"), "-c", prelude+body],
                                env=dict(os.environ, SAM_PACKAGE=PACKAGE.as_posix()),
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_exact_shell_script_identity(self):
        out = self.shell(r'''fakeproc 101 /bin/bash bash /media/fat/Scripts/bgm.sh
fakeproc 102 /usr/bin/tmux tmux bash /media/fat/Scripts/bgm.sh
fakeproc 103 /bin/bash bash -c '/media/fat/Scripts/bgm.sh'
fakeproc 104 /bin/bash bash /other/bgm.sh
fakeproc 105 /bin/bash bash /other/helper.sh /media/fat/Scripts/bgm.sh
fakeproc 106 /bin/bash bash -- /media/fat/Scripts/bgm.sh
fakeproc 107 /bin/busybox httpd /media/fat/Scripts/bgm.sh
fakeproc 108 /bin/busybox sh /media/fat/Scripts/bgm.sh
fakeproc 109 /usr/bin/python3.8 python3 /media/fat/Scripts/bgm.sh
fakeproc 110 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
fakeproc 111 /other/bgm.sh /media/fat/Scripts/bgm.sh
sam_bgm_pids''')
        self.assertEqual(out.splitlines(), ["101", "106", "108", "109", "110"])

    def test_stop_signals_only_revalidated_bgm(self):
        out = self.shell(r'''fakeproc 101 /bin/bash bash /media/fat/Scripts/bgm.sh
fakeproc 102 /usr/bin/mpg123 mpg123 music.mp3
fakeproc 103 /usr/bin/tmux tmux /media/fat/Scripts/bgm.sh
bgm=yes; bgmstop=yes; bgm_stop''')
        self.assertEqual(out.splitlines(), ["KILL:-TERM 101"])

    def test_old_dead_record_falls_back_only_to_new_installed_script(self):
        out = self.shell(r"""printf 'pid=999\nstart=77\nexe=/tmp/bgmalias\nsocket=old\nwrapper_pid=998\nwrapper_start=77\n' > "$sam_bgm_owner_file"
fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
fakeproc 102 /tmp/bgm.sh /tmp/bgm.sh exec
sam_bgm_pids""")
        self.assertEqual(out.splitlines(), ['101'])

    def test_dead_owned_record_stop_does_not_adopt_new_installed_service(self):
        out = self.shell(r"""printf 'pid=999\nstart=77\nexe=/tmp/bgmalias\nsocket=old\nwrapper_pid=998\nwrapper_start=77\n' > "$sam_bgm_owner_file"
fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
bgm=yes;bgmstop=yes;bgm_stop
[[ -f "$sam_bgm_proc/101/stat" ]]
# Discovery for a new start retains trusted installed-script compatibility.
sam_bgm_pids""")
        self.assertEqual(out.splitlines(), ['101'])

    def test_failed_term_of_live_instance_blocks_stop_success(self):
        out = self.shell(r"""fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
kill(){ return 1; }
bgm=yes;bgmstop=yes
if bgm_stop; then exit 1; fi""")
        self.assertEqual(out, '')

    def test_term_without_exit_blocks_stop_success_after_bounded_wait(self):
        out = self.shell(r"""fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
kill(){ :; };sleep(){ SECONDS=$((SECONDS+1));printf 'WAIT\n'; }
bgm=yes;bgmstop=yes
if bgm_stop; then exit 1; fi""")
        self.assertEqual(out.splitlines().count('WAIT'), 4)

    def test_pid_reuse_after_term_is_not_signalled_again(self):
        out = self.shell(r"""fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
kill(){ printf 'KILL:%s\n' "$*";line=$(<"$sam_bgm_proc/101/stat");printf '%s\n' "${line%77}78" > "$sam_bgm_proc/101/stat"; }
sleep(){ printf FORBIDDEN_WAIT;return 99; }
bgm=yes;bgmstop=yes;bgm_stop""")
        self.assertEqual(out.splitlines().count('KILL:-TERM 101'), 1)
        self.assertNotIn('FORBIDDEN_WAIT', out)

    def test_existing_player_has_no_startup_sleep_or_setup(self):
        out = self.shell(r'''fakeproc 101 /bin/bash bash /media/fat/Scripts/bgm.sh
sleep() { echo FORBIDDEN_SLEEP; return 1; }
bash() { echo FORBIDDEN_LAUNCH; return 1; }
sam_bgm_capture_daemon(){ :; } # healthy supported existing service
bgm=yes; bgm_start''')
        self.assertEqual(out.splitlines(), ["COMMAND:set playincore yes", "COMMAND:play"])

    def test_stopping_absent_player_does_not_touch_other_socket(self):
        self.assertEqual(self.shell("bgm=yes; bgmstop=yes; bgm_stop"), "")

    def test_menu_handoff_changes_policy_without_stopping_menu_playlist(self):
        out = self.shell(r'''fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
bgm=yes; bgmstop=no
sam_bgm_menu_prepare
bgm_stop menu''')
        self.assertEqual(out.splitlines(), ['COMMAND:set playincore no'] * 2)

    def test_keep_game_still_stops_persistent_music(self):
        out = self.shell(r'''fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
bgm=yes; bgmstop=no; bgm_stop game''')
        self.assertEqual(out.splitlines(), ['COMMAND:set playincore no', 'COMMAND:stop'])

    def test_failed_menu_policy_ack_blocks_handoff(self):
        out = self.shell(r'''fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
bgm=yes; bgmstop=no
sam_bgm_query(){ printf yes; }
if sam_bgm_menu_prepare; then exit 1; fi''')
        self.assertEqual(out.splitlines(), ['COMMAND:set playincore no'])

    def test_missing_script_fails_without_background_launch(self):
        out = self.shell(r'''sam_bgm_script=/does/not/exist; bgm=yes
bash() { echo FORBIDDEN_LAUNCH; }
if bgm_start; then exit 1; fi''')
        self.assertEqual(out, "")

    def test_bundled_player_stop_reaps_only_owned_child(self):
        tree = ast.parse((PACKAGE/".MiSTer_SAM/bgm.sh").read_text(encoding="utf-8"))
        cls = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "Player")
        methods = [node for node in cls.body if isinstance(node, ast.FunctionDef) and node.name in ("stop", "kill_player")]
        namespace = {"subprocess": subprocess}
        module = ast.Module(body=[ast.ClassDef(name="OwnedPlayer", bases=[], keywords=[], body=methods, decorator_list=[])], type_ignores=[])
        exec(compile(ast.fix_missing_locations(module), "bgm_owned_methods", "exec"), namespace)
        owned = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(20)"])
        unrelated = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(20)"])
        try:
            player = namespace["OwnedPlayer"]()
            player.player = owned
            player.playing = "fixture"
            player.stop()
            player.stop()
            self.assertIsNone(player.player)
            self.assertIsNotNone(owned.poll())
            self.assertIsNone(unrelated.poll())
        finally:
            for child in (owned, unrelated):
                if child.poll() is None:
                    child.kill()
                child.wait(timeout=2)

    def test_existing_native_player_is_reused(self):
        out = self.shell(r'''fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
sleep() { echo FORBIDDEN_SLEEP; return 1; }
sam_bgm_capture_daemon(){ :; } # healthy supported existing service
bgm=yes; bgm_start''')
        self.assertEqual(out.splitlines(), ["COMMAND:set playincore yes", "COMMAND:play"])

    def test_existing_playing_random_service_does_not_restart_playlist(self):
        out = self.shell(r"""fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
sam_bgm_capture_daemon(){ :; }
sam_bgm_query(){ case "$1" in 'get playback') printf random;;status) printf 'yes\trandom\tnone\t';;*) return 1;;esac; }
sleep(){ echo FORBIDDEN_SLEEP;return 99; }
bgm=yes;bgm_start""")
        self.assertEqual(out.splitlines(), ['COMMAND:set playincore yes'])

    def test_playback_change_queries_result_instead_of_redundant_play(self):
        out = self.shell(r"""fakeproc 101 /media/fat/Scripts/bgm.sh /media/fat/Scripts/bgm.sh
sam_bgm_capture_daemon(){ :; }
sam_bgm_query(){ case "$1" in 'get playback') printf loop;;status) printf 'yes\trandom\tnone\t';;*) return 1;;esac; }
bgm=yes;bgm_start""")
        self.assertEqual(out.splitlines(), ['COMMAND:set playincore yes','COMMAND:set playback random'])

    def test_bundled_watcher_is_reaped_on_systemexit(self):
        tree = ast.parse((PACKAGE/".MiSTer_SAM/bgm.sh").read_text(encoding="utf-8"))
        fn = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "wait_core_change")
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(20)"])
        closed = []
        class InterruptedStream:
            def readline(self):
                raise SystemExit()
            def close(self):
                closed.append(True)
        watcher = SimpleNamespace(poll=child.poll, kill=child.kill, wait=child.wait,
                                  stdout=InterruptedStream())
        fake_subprocess = SimpleNamespace(Popen=lambda *args, **kwargs: watcher,
                                         PIPE=-1, STDOUT=-2, TimeoutExpired=subprocess.TimeoutExpired)
        namespace = dict(subprocess=fake_subprocess, CORENAME_FILE="fixture", get_core=lambda: "MENU", log=lambda *args: None)
        exec(compile(ast.fix_missing_locations(ast.Module(body=[fn], type_ignores=[])), "bgm_watcher", "exec"), namespace)
        try:
            with self.assertRaises(SystemExit):
                namespace["wait_core_change"]()
            self.assertIsNotNone(child.poll())
            self.assertEqual(closed, [True])
        finally:
            if child.poll() is None:
                child.kill()
            child.wait(timeout=2)


if __name__ == "__main__":
    unittest.main()
