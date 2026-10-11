"""Private core-volume bind emulation and BGM policy; never real mounts/audio."""
import unittest
import test_catalog_runtime as harness


class CoreAudioPolicy(unittest.TestCase):
    def setUp(self):
        self.fixture = harness.CatalogRuntime()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def shell(self, body):
        self.fixture.shell(r"""
# All paths and mount effects are private fixture data.
configpath="$sam_session/config";mkdir -p "$configpath" "$mrsamtmp/SAM_config" "$sam_session/originals"
export SAM_MOUNTS_FILE="$sam_session/mounts"
export SAM_BGM_SOCKET="$sam_session/bgm.sock" SAM_BGM_OWNER_FILE="$mrsamtmp/bgm-owner"
: > "$SAM_MOUNTS_FILE";: > "$sam_session/mount-log";: > "$sam_session/live-commands"
mute=core;prevcore=;samdebug=no;samdebuglog=no
sam_audio_set_live(){ printf '%s\n' "$1" >> "$sam_session/live-commands"; }
sleep(){ :; }
sync(){ echo forbidden-global-sync >&2; return 99; }
mount(){
    if (($#==0)); then
        while read -r source target kind rest; do printf '%s on %s type %s (%s)\n' "$source" "$target" "$kind" "$rest";done < "$SAM_MOUNTS_FILE"
        return 0
    fi
    [[ "$1" == --bind && $(xxd -p "$2") == 06 ]] || return 99
    printf '%s\n' "$3" >> "$sam_session/mount-log"
    [[ "${FAIL_BIND:-no}" != yes ]] || return 1
    [[ -f "$sam_session/originals/${3##*/}" ]] || cp "$3" "$sam_session/originals/${3##*/}"
    rm "$3";ln "$2" "$3"
    printf '%s %s none rw 0 0\n' "$2" "$3" >> "$SAM_MOUNTS_FILE"
}
umount(){
    [[ "${FAIL_UMOUNT:-}" != "$1" ]] || return 1
    cp "$sam_session/originals/${1##*/}" "$1.restore"
    rm "$1";mv "$1.restore" "$1"
    awk -v target="$1" '$2!=target' "$SAM_MOUNTS_FILE" > "$SAM_MOUNTS_FILE.next"
    mv "$SAM_MOUNTS_FILE.next" "$SAM_MOUNTS_FILE"
}
timeout(){
    local duration=$1;shift
    if [[ "$1" == umount ]]; then shift;[[ "$1" != -l ]] || shift;umount "$@"
    else "$@";fi
}
""" + body)

    def test_core_bind_masks_volume_and_restores_original_byte(self):
        self.shell(r"""
printf '\x03' > "$configpath/NES_volume.cfg"
mute NES
[[ $(xxd -p "$configpath/NES_volume.cfg") == 06 ]]
[[ $(xxd -p "$sam_session/originals/NES_volume.cfg") == 03 ]]
sam_restore_audio
[[ $(xxd -p "$configpath/NES_volume.cfg") == 03 && ! -s "$SAM_MOUNTS_FILE" ]]
""")

    def test_same_core_does_not_add_another_bind(self):
        self.shell(r"""
printf '\x03' > "$configpath/NES_volume.cfg"
mute NES;mute NES
[[ $(wc -l < "$sam_session/mount-log") == 1 && $(wc -l < "$SAM_MOUNTS_FILE") == 1 ]]
""")

    def test_transition_unmounts_previous_core_and_keeps_its_original(self):
        self.shell(r"""
printf '\x03' > "$configpath/NES_volume.cfg"
printf '\x02' > "$configpath/SNES_volume.cfg"
mute NES;mute SNES
[[ $(xxd -p "$configpath/NES_volume.cfg") == 03 && $(xxd -p "$configpath/SNES_volume.cfg") == 06 ]]
[[ $(wc -l < "$SAM_MOUNTS_FILE") == 1 && "$prevcore" == SNES ]]
sam_restore_audio
[[ $(xxd -p "$configpath/SNES_volume.cfg") == 02 ]]
""")

    def test_initial_user_global_mute_is_preserved_with_core_mute(self):
        self.shell(r"""
printf '\x15' > "$configpath/Volume.dat"
printf '\x03' > "$configpath/NES_volume.cfg"
mute NES;sam_restore_audio
[[ $(xxd -p "$configpath/Volume.dat") == 15 && ! -s "$sam_session/live-commands" ]]
""")

    def test_missing_core_file_is_created_without_overwriting_other_config(self):
        self.shell(r"""
printf untouched > "$configpath/Other_volume.cfg"
mute NES
[[ $(xxd -p "$configpath/NES_volume.cfg") == 06 && $(<"$configpath/Other_volume.cfg") == untouched ]]
sam_restore_audio
[[ -f "$configpath/NES_volume.cfg" && ! -s "$configpath/NES_volume.cfg" ]]
""")

    def test_bind_failure_must_not_report_success_or_advance_prevcore(self):
        self.shell(r"""
printf '\x03' > "$configpath/NES_volume.cfg"
FAIL_BIND=yes;rc=0;mute NES || rc=$?
[[ $rc != 0 && -z "$prevcore" && $(xxd -p "$configpath/NES_volume.cfg") == 03 ]]
""")

    def test_previous_unmount_failure_must_not_stack_another_muted_core(self):
        self.shell(r"""
printf '\x03' > "$configpath/NES_volume.cfg"
printf '\x02' > "$configpath/SNES_volume.cfg"
mute NES;FAIL_UMOUNT="$configpath/NES_volume.cfg"
rc=0;mute SNES || rc=$?
[[ $rc != 0 && "$prevcore" == NES && $(wc -l < "$SAM_MOUNTS_FILE") == 1 ]]
""")

    def test_similar_mount_path_must_not_replace_required_exact_target(self):
        self.shell(r"""
printf '\x03' > "$configpath/NES_volume.cfg"
printf 'foreign %s/NES_volumeXcfg none rw 0 0\n' "$configpath" > "$SAM_MOUNTS_FILE"
mute NES
[[ $(xxd -p "$configpath/NES_volume.cfg") == 06 && $(wc -l < "$sam_session/mount-log") == 1 ]]
""")

    def test_foreign_exact_target_mount_is_not_adopted(self):
        self.shell(r"""
printf '\x03' > "$configpath/NES_volume.cfg"
printf 'foreign %s/NES_volume.cfg none rw 0 0\n' "$configpath" > "$SAM_MOUNTS_FILE"
rc=0;mute NES || rc=$?
[[ $rc != 0 && ! -s "$sam_session/mount-log" && $(xxd -p "$configpath/NES_volume.cfg") == 03 ]]
""")

    def test_failed_global_restore_aborts_core_mute(self):
        self.shell(r"""
printf '\x03' > "$configpath/NES_volume.cfg"
printf pending > "$mrsamtmp/volume-restore"
only_unmute_if_needed(){ return 1; }
rc=0;mute NES || rc=$?
[[ $rc != 0 && ! -s "$sam_session/mount-log" && -z "$prevcore" ]]
""")

    def test_bgm_persistent_player_stop_failure_blocks_critical_hook(self):
        self.shell(r"""
sam_load_module bgm;bgmstop=no
sam_bgm_pids(){ printf '123\n'; }
sam_bgm_command(){ return 1; }
kill(){ printf forbidden-kill >&2;return 99; }
rc=0;sam_emit audio_stop || rc=$?
[[ $rc != 0 ]]
""")

    def test_bgm_persistent_player_success_does_not_kill_user_service(self):
        self.shell(r"""
sam_load_module bgm;bgmstop=no
sam_bgm_pids(){ printf '123\n'; }
sam_bgm_command(){ printf '%s\n' "$1" >> "$sam_session/bgm-commands"; }
sam_bgm_query(){ case "$1" in status) printf 'no\tdisabled';; 'get playincore') printf no;;esac; }
kill(){ printf forbidden-kill >&2;return 99; }
sam_emit audio_stop
[[ $(wc -l < "$sam_session/bgm-commands") == 2 ]]
""")

    def test_fresh_launch_shell_without_prevcore_releases_owned_previous_bind(self):
        self.shell(r"""
printf '\x03' > "$configpath/NES_volume.cfg"
printf '\x02' > "$configpath/SNES_volume.cfg"
(mute NES)
[[ -z "$prevcore" ]]
(mute SNES)
[[ $(xxd -p "$configpath/NES_volume.cfg") == 03 && $(xxd -p "$configpath/SNES_volume.cfg") == 06 ]]
[[ $(wc -l < "$SAM_MOUNTS_FILE") == 1 ]]
""")

    def test_launch_refuses_dispatch_when_mute_fails(self):
        self.shell(r"""
launch_source=$(<"$mrsampath/lib/launch.sh")
launch_source=${launch_source//\/tmp\//$sam_session/}
source /dev/stdin <<< "$launch_source"
sam_cancel_launch_job(){ :; };sam_core_require(){ :; };sam_is_excluded(){ return 1; }
sam_emit(){ :; };sam_publish_phase(){ :; }
grep(){ printf 'Fake.rbf\n'; }
mute(){ printf called > "$sam_session/mute-called";return 1; }
timeout(){ printf forbidden > "$sam_session/dispatched";return 99; }
printf '<mistergamedescription><rbf>Fake.rbf</rbf></mistergamedescription>\n' > "$sam_session/Game.mgl"
rc=0;load_core mgls "$sam_session/Game.mgl" Game || rc=$?
[[ $rc != 0 && -f "$sam_session/mute-called" && ! -e "$sam_session/dispatched" ]]
""")

    def test_bgm_excludes_unsupported_cores_but_keeps_requested_configuration(self):
        self.shell(r"""
sam_load_module bgm;corelist=(n64 nes psx snes saturn)
sam_core_session_begin
[[ "${sam_allowed_cores[*]}" == 'nes snes' && "${sam_requested_cores[*]}" == 'n64 nes psx snes saturn' ]]
""")

    def test_bgm_stops_before_menu_quiescence_is_published(self):
        self.shell(r"""
sam_session_begin
printf '%s\n' "$sam_owner" > "$mrsamtmp/menu-audio-owner"
sam_cancel_preparation(){ :; };sam_cancel_launch_job(){ :; }
sam_cleanup(){ :; }
verify_audio_stop(){ [[ ! -f "$sam_session/quiesced" ]];printf stopped > "$mrsamtmp/audio-stopped"; }
verify_display_shutdown(){ [[ -f "$sam_session/quiesced" && -f "$mrsamtmp/audio-stopped" ]]; }
sam_register audio_stop verify_audio_stop
sam_register display_shutdown verify_display_shutdown
sam_session_cleanup
[[ -f "$mrsamtmp/audio-stopped" ]]
""")


if __name__ == '__main__':
    unittest.main()
