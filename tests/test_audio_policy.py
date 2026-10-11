"""Saved-volume policy with fake binds/commands; no live MiSTer effects."""
import unittest
import test_shell


class AudioPolicy(unittest.TestCase):
    def setUp(self):
        self.fixture = test_shell.Shell()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def check(self, body):
        prelude = r'''
mkdir -p "$configpath" "$mrsamtmp"
export SAM_MOUNTS_FILE="$mrsamtmp/mounts"
: > "$SAM_MOUNTS_FILE"
sam_audio_set_live(){
    printf '%s\n' "$1" >> "$mrsamtmp/commands"
    [[ "${fail_delivery:-0}" != 1 ]] || return 1
    if [[ "${no_ack:-0}" != 1 ]] && sam_volume_owned_mount "$configpath/Volume.dat"; then
        local byte=$(xxd -p -l 1 "$mrsamtmp/Volume.dat") value
        value=$((0x$byte))
        if [[ "$1" == mute ]]; then value=$((value | 16)); else value=$((value & ~16)); fi
        printf -v byte '%02x' "$value"
        printf '%b' "\\x$byte" > "$mrsamtmp/Volume.dat"
    fi
}
mount(){
    [[ "$1" == --bind ]]
    cp "$3" "$mrsamtmp/original"
    rm "$3";ln "$2" "$3"
    printf 'tmpfs %s none rw 0 0\n' "$3" > "$SAM_MOUNTS_FILE"
}
umount(){
    [[ "$1" == -l ]]
    rm "$2";cp "$mrsamtmp/original" "$2"
    : > "$SAM_MOUNTS_FILE"
}
timeout(){ shift; "$@"; }
declare -f sam_audio_set_live > "$mrsamtmp/mock-live"
'''
        result = self.fixture.shell(prelude + body)
        self.assertEqual(result.returncode, 0, result.stderr + '\n' + result.stdout)

    def test_unmuted_user_restores_original_without_rewriting_file(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"
global_mute
[[ $(xxd -p "$configpath/Volume.dat") == 15 && $(xxd -p "$mrsamtmp/original") == 05 ]]
sam_restore_audio
[[ $(xxd -p "$configpath/Volume.dat") == 05 && $(<"$mrsamtmp/commands") == $'mute\nunmute' ]]
[[ ! -e "$mrsamtmp/volume-restore" ]]
sam_restore_audio
[[ $(wc -l < "$mrsamtmp/commands") == 2 ]]
''')

    def test_premuted_user_stays_muted(self):
        self.check(r'''
printf '\x15' > "$configpath/Volume.dat"
global_mute
sam_restore_audio
[[ $(xxd -p "$configpath/Volume.dat") == 15 && $(<"$mrsamtmp/commands") == mute ]]
''')

    def test_premuted_user_manual_unmute_requires_restore_ack(self):
        self.check(r'''
printf '\x15' > "$configpath/Volume.dat"; global_mute
printf '\x05' > "$mrsamtmp/Volume.dat"
sam_restore_audio
[[ $(<"$mrsamtmp/commands") == $'mute\nmute' && $(xxd -p "$configpath/Volume.dat") == 15 ]]
''')

    def test_no_sam_bind_means_no_volume_command_even_with_mute_ini(self):
        self.check(r'''
printf '\x15' > "$configpath/Volume.dat";mute=global
sam_restore_audio
global_unmute
[[ ! -e "$mrsamtmp/commands" && $(xxd -p "$configpath/Volume.dat") == 15 ]]
''')

    def test_bind_failure_never_mutes_live_or_changes_original(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"
mount(){ return 1; }
! global_mute
[[ ! -e "$mrsamtmp/commands" && ! -e "$mrsamtmp/volume-restore" ]]
[[ $(xxd -p "$configpath/Volume.dat") == 05 ]]
''')

    def test_foreign_bind_is_not_muted_or_unmounted(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"
printf '\x15' > "$mrsamtmp/Volume.dat"
printf 'tmpfs %s none rw 0 0\n' "$configpath/Volume.dat" > "$SAM_MOUNTS_FILE"
umount(){ echo unsafe-unmount >&2;return 99; }
! global_mute
! global_unmute
[[ ! -e "$mrsamtmp/commands" && $(xxd -p "$configpath/Volume.dat") == 05 ]]
''')

    def test_stale_record_cannot_adopt_a_foreign_bind(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"
printf '\x15' > "$mrsamtmp/Volume.dat"
sam_volume_record_write "$configpath/Volume.dat" 05 pending
printf 'tmpfs %s none rw 0 0\n' "$configpath/Volume.dat" > "$SAM_MOUNTS_FILE"
umount(){ echo unsafe-unmount >&2;return 99; }
! sam_restore_audio
[[ -e "$mrsamtmp/volume-restore" && ! -e "$mrsamtmp/commands" ]]
''')

    def test_failed_restore_delivery_retries_in_fresh_shell_with_bind_retained(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"
global_mute
fail_delivery=1
! sam_restore_audio
[[ -s "$SAM_MOUNTS_FILE" && -e "$mrsamtmp/volume-restore" ]]
fail_delivery=0
export -f sam_audio_set_live umount timeout
bash -c '
source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
# Restore the fixture command function after sourcing production helpers.
source "$mrsamtmp/mock-live"
sam_restore_audio
[[ ! -e "$mrsamtmp/volume-restore" ]]
'
[[ $(<"$mrsamtmp/commands") == $'mute\nunmute\nunmute' && $(xxd -p "$configpath/Volume.dat") == 05 ]]
''')

    def test_no_ack_retains_bind_original_and_record(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"; global_mute
no_ack=1
sleep(){ :; }
! sam_restore_audio
[[ -s "$SAM_MOUNTS_FILE" && -e "$mrsamtmp/volume-restore" ]]
[[ $(xxd -p "$mrsamtmp/original") == 05 ]]
''')

    def test_late_ack_is_received_before_unmount(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"; global_mute
no_ack=1; ticks=0
sleep(){ ticks=$((ticks+1)); [[ "$ticks" != 3 ]] || printf '\x05' > "$mrsamtmp/Volume.dat"; return 0; }
sam_restore_audio
[[ "$ticks" == 3 && ! -s "$SAM_MOUNTS_FILE" && $(xxd -p "$configpath/Volume.dat") == 05 ]]
''')

    def test_failed_unmount_retains_protection_and_record(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"; global_mute
umount(){ return 1; }
! sam_restore_audio
[[ -s "$SAM_MOUNTS_FILE" && -e "$mrsamtmp/volume-restore" && $(xxd -p "$mrsamtmp/original") == 05 ]]
''')

    def test_failed_unmount_then_new_session_reacquires_mute(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"; global_mute
saved_umount=$(declare -f umount)
umount(){ return 1; }
! sam_restore_audio
[[ $(xxd -p "$mrsamtmp/Volume.dat") == 05 ]]
only_mute_if_needed
[[ $(xxd -p "$mrsamtmp/Volume.dat") == 15 ]]
sam_volume_record_read; [[ "$sam_volume_saved" == 05 ]]
eval "$saved_umount"
sam_restore_audio
[[ $(xxd -p "$configpath/Volume.dat") == 05 && ! -e "$mrsamtmp/volume-restore" ]]
[[ $(<"$mrsamtmp/commands") == $'mute\nunmute\nmute\nunmute' ]]
''')

    def test_failed_reacquisition_retains_original_record_for_retry(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"; global_mute
umount(){ return 1; }; ! sam_restore_audio
fail_delivery=1
! only_mute_if_needed
sam_volume_record_read; [[ "$sam_volume_saved" == 05 && "$sam_volume_phase" == bound ]]
[[ $(xxd -p "$mrsamtmp/Volume.dat") == 05 && $(xxd -p "$mrsamtmp/original") == 05 ]]
fail_delivery=0; only_mute_if_needed
[[ $(xxd -p "$mrsamtmp/Volume.dat") == 15 ]]
''')

    def test_false_success_unmount_retains_record(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"; global_mute
umount(){ return 0; }
! sam_restore_audio
[[ -s "$SAM_MOUNTS_FILE" && -e "$mrsamtmp/volume-restore" ]]
''')

    def test_main_replacement_during_ack_retains_bind(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"; global_mute
sam_menu_delivery_active=1; no_ack=1
sam_menu_delivery_still_current(){ return 1; }
! sam_restore_audio
[[ -s "$SAM_MOUNTS_FILE" && -e "$mrsamtmp/volume-restore" ]]
''')

    def test_menu_deadline_expiry_during_ack_retains_bind(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"; global_mute
sam_menu_delivery_active=1; sam_menu_deadline=$((SECONDS+10)); no_ack=1
sam_menu_delivery_still_current(){ return 0; }
sleep(){ sam_menu_deadline=$SECONDS; }
! sam_restore_audio
[[ -s "$SAM_MOUNTS_FILE" && -e "$mrsamtmp/volume-restore" ]]
''')

    def test_owned_core_mount_false_success_is_failure(self):
        self.check(r'''
mkdir -p "$mrsamtmp/SAM_config"
printf '\x06' > "$mrsamtmp/SAM_config/SNES_volume.cfg"
ln "$mrsamtmp/SAM_config/SNES_volume.cfg" "$configpath/SNES_volume.cfg"
printf 'tmpfs %s/SNES_volume.cfg none rw 0 0\n' "$configpath" > "$SAM_MOUNTS_FILE"
umount(){ return 0; }
! sam_restore_audio
[[ -s "$SAM_MOUNTS_FILE" && ! -e "$mrsamtmp/commands" ]]
''')

    def test_owned_core_mount_failure_blocks_restore(self):
        self.check(r'''
mkdir -p "$mrsamtmp/SAM_config"
printf '\x06' > "$mrsamtmp/SAM_config/SNES_volume.cfg"
ln "$mrsamtmp/SAM_config/SNES_volume.cfg" "$configpath/SNES_volume.cfg"
printf 'tmpfs %s/SNES_volume.cfg none rw 0 0\n' "$configpath" > "$SAM_MOUNTS_FILE"
umount(){ return 1; }
! sam_restore_audio
[[ -s "$SAM_MOUNTS_FILE" && ! -e "$mrsamtmp/commands" ]]
''')

    def test_audio_protection_failure_is_fatal_before_dispatch(self):
        self.check(r'''
sam_cancel_launch_job(){ return 0; }
sam_core_require(){ return 0; }
sam_is_excluded(){ return 1; }
sam_publish_phase(){ return 0; }
sam_emit(){ [[ "$1" == launch_validate ]] || { echo unexpected-dispatch >&2; return 99; }; }
mute(){ return 1; }
timeout(){ echo unexpected-hardware >&2; return 99; }
rc=0
load_core x68k "$mrsamtmp/test.mgl" 2> "$mrsamtmp/error" || rc=$?
[[ "$rc" == 2 && "$sam_core_reason" == *'Audio protection failed'* ]]
grep -q 'Audio protection failed for x68k' "$mrsamtmp/error"
! grep -q unexpected "$mrsamtmp/error"
''')

    def test_canonical_case_mount_reuses_and_resolves_owned_source(self):
        self.check(r'''
mkdir -p "$mrsamtmp/SAM_config"
printf '\x06' > "$mrsamtmp/SAM_config/MEGADRIVE_volume.cfg"
# Hardlinks model the identity FAT exposes through either case spelling.
ln "$mrsamtmp/SAM_config/MEGADRIVE_volume.cfg" "$configpath/MEGADRIVE_volume.cfg"
ln "$configpath/MEGADRIVE_volume.cfg" "$configpath/MegaDrive_volume.cfg"
printf 'tmpfs %s/MegaDrive_volume.cfg none rw 0 0\n' "$configpath" > "$SAM_MOUNTS_FILE"
mount(){ echo duplicate-bind >&2; return 99; }
sam_volume_is_mounted "$configpath/MEGADRIVE_volume.cfg"
sam_core_volume_mute MEGADRIVE
sam_core_volume_mute MegaDrive
[[ "$sam_core_volume_source" == "$mrsamtmp/SAM_config/MEGADRIVE_volume.cfg" ]]
umount(){ [[ "$2" == "$configpath/MegaDrive_volume.cfg" ]]; : > "$SAM_MOUNTS_FILE"; }
sam_restore_audio
[[ ! -s "$SAM_MOUNTS_FILE" ]]
''')

    def test_canonical_case_foreign_bind_is_not_adopted(self):
        self.check(r'''
printf foreign > "$configpath/MegaDrive_volume.cfg"
ln "$configpath/MegaDrive_volume.cfg" "$configpath/MEGADRIVE_volume.cfg"
mkdir -p "$mrsamtmp/SAM_config"
printf '\x06' > "$mrsamtmp/SAM_config/MEGADRIVE_volume.cfg"
printf 'tmpfs %s/MegaDrive_volume.cfg none rw 0 0\n' "$configpath" > "$SAM_MOUNTS_FILE"
mount(){ return 99; }; umount(){ echo unsafe >&2; return 99; }
! sam_core_volume_mute MEGADRIVE
sam_restore_audio
[[ -s "$SAM_MOUNTS_FILE" && $(<"$configpath/MegaDrive_volume.cfg") == foreign ]]
''')

    def test_global_canonical_mount_spelling_uses_identity(self):
        self.check(r'''
printf '\x05' > "$configpath/Volume.dat"; global_mute
ln "$configpath/Volume.dat" "$configpath/VOLUME.DAT"
printf 'tmpfs %s/VOLUME.DAT none rw 0 0\n' "$configpath" > "$SAM_MOUNTS_FILE"
sam_volume_owned_mount "$configpath/Volume.dat"
sam_restore_audio
[[ ! -s "$SAM_MOUNTS_FILE" && $(xxd -p "$configpath/Volume.dat") == 05 ]]
''')

    def test_cross_config_core_mount_cleanup_requires_same_inode(self):
        self.check(r'''
mkdir -p "$mrsamtmp/SAM_config" "$mrsamtmp/old-config" "$mrsamtmp/foreign-config"
printf '\x06' > "$mrsamtmp/SAM_config/ARCADE_volume.cfg"
ln "$mrsamtmp/SAM_config/ARCADE_volume.cfg" "$mrsamtmp/old-config/ARCADE_volume.cfg"
printf 'foreign' > "$mrsamtmp/foreign-config/ARCADE_volume.cfg"
owned="$mrsamtmp/old-config/ARCADE_volume.cfg"
foreign="$mrsamtmp/foreign-config/ARCADE_volume.cfg"
printf 'tmpfs %s none rw 0 0\ntmpfs %s none rw 0 0\n' "$owned" "$foreign" > "$SAM_MOUNTS_FILE"
umount(){
    [[ "$2" == "$owned" ]] || return 99
    printf '%s\n' "$2" >> "$mrsamtmp/removed"
    printf 'tmpfs %s none rw 0 0\n' "$foreign" > "$SAM_MOUNTS_FILE"
}
unset sam_core_volume_target sam_core_volume_source
sam_core_volume_release_other "$configpath/SNES_volume.cfg"
[[ $(<"$mrsamtmp/removed") == "$owned" ]]
# Repeat through the final cleanup path in another config context.
printf 'tmpfs %s none rw 0 0\ntmpfs %s none rw 0 0\n' "$owned" "$foreign" > "$SAM_MOUNTS_FILE"
sam_restore_audio
[[ $(wc -l < "$mrsamtmp/removed") == 2 && -s "$SAM_MOUNTS_FILE" ]]
[[ $(<"$foreign") == foreign && ! -e "$mrsamtmp/commands" ]]
''')

    def test_core_volume_cleanup_does_not_authorize_global_unmute(self):
        self.check(r'''
printf '\x15' > "$configpath/Volume.dat";mute=core
printf 'tmpfs %s/SNES_volume.cfg none rw 0 0\n' "$configpath" > "$SAM_MOUNTS_FILE"
umount(){ printf '%s\n' "$2" > "$mrsamtmp/core-removed"; }
sam_restore_audio
[[ ! -e "$mrsamtmp/core-removed" && ! -e "$mrsamtmp/commands" && $(xxd -p "$configpath/Volume.dat") == 15 ]]
''')
