"""Private Menu delivery fixtures; Main, writes and audio effects are mocked."""
import unittest
import test_shell


class MenuDelivery(unittest.TestCase):
    setUp = test_shell.Shell.setUp
    shell = test_shell.Shell.shell
    assertShell = test_shell.Shell.assertShell

    def context(self):
        return '''
SAM_CORENAME_FILE="$mrsamtmp/core"
printf 'MENU\\n' > "$SAM_CORENAME_FILE"
printf 'pid=321\\nstart=77\\n' > "$mrsamtmp/session-owner"
printf '321:77\\n' > "$mrsamtmp/menu-audio-owner"
printf '321:77\\n' > "$mrsamtmp/menu-audio-complete"
sam_pid_start(){ return 1; }
sam_menu_delivery_active=1 sam_menu_request_accepted=1
sam_menu_initial_main=10:100 sam_menu_initial_fifo=fifo-old sam_menu_initial_marker=marker-old
current_main=20:200 current_fifo=fifo-new current_marker=marker-new snapshot_valid=1
sam_menu_delivery_snapshot(){
    [[ "$snapshot_valid" == 1 && $(<"$SAM_CORENAME_FILE") == MENU ]] || return 1
    sam_menu_snapshot_main=$current_main
    sam_menu_snapshot_fifo=$current_fifo
    sam_menu_snapshot_marker=$current_marker
}
sam_restore_audio(){ printf restored >> "$mrsamtmp/restored"; }
'''

    def test_stale_menu_with_new_game_fifo_never_releases_audio(self):
        self.assertShell(self.context() + '''
current_marker=marker-old
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" && -e "$mrsamtmp/menu-audio-owner" ]]
printf 'dstlk\\n' > "$SAM_CORENAME_FILE"
current_marker=marker-game
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" ]]
''')

    def test_fresh_menu_marker_before_fifo_replacement_waits(self):
        self.assertShell(self.context() + '''
current_fifo=fifo-old
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" ]]
current_fifo=fifo-new
sam_menu_audio_restore 321 77
[[ $(<"$mrsamtmp/restored") == restored && ! -e "$mrsamtmp/menu-audio-owner" ]]
''')

    def test_fresh_fifo_marker_with_old_main_waits(self):
        self.assertShell(self.context() + '''
current_main=10:100
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" ]]
current_main=20:200
sam_menu_audio_restore 321 77
''')

    def test_fresh_menu_main_marker_waits_for_its_own_fifo_reader(self):
        self.assertShell(self.context() + '''
# Dark's FIFO is newer than the original Menu FIFO, but the new Menu Main
# has not opened it. Freshness alone must not release the mute resources.
current_main=30:300 current_fifo=fifo-dark current_marker=marker-new snapshot_valid=0
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" && -e "$mrsamtmp/menu-audio-owner" ]]
current_fifo=fifo-menu snapshot_valid=1
sam_menu_audio_restore 321 77
[[ $(<"$mrsamtmp/restored") == restored ]]
''')

    def test_main_restart_during_restore_is_not_reported_complete(self):
        self.assertShell(self.context() + '''
sam_restore_audio(){ current_main=30:300; }
! sam_menu_audio_restore 321 77
[[ -e "$mrsamtmp/menu-audio-owner" ]]
''')

    def test_fifo_timestamp_change_from_unmute_is_not_a_restart(self):
        self.assertShell(self.context() + '''
current_fifo='fifo-new|before-write'
sam_restore_audio(){ current_fifo='fifo-new|after-write'; }
sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/menu-audio-owner" ]]
''')

    def test_failed_menu_write_cannot_confirm_completion(self):
        self.assertShell(self.context() + '''
sam_menu_request_accepted=0
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" && -e "$mrsamtmp/menu-audio-owner" ]]
''')

    def test_failed_unmute_keeps_pending_completion(self):
        self.assertShell(self.context() + '''
sam_restore_audio(){ return 1; }
! sam_menu_audio_restore 321 77
[[ -e "$mrsamtmp/menu-audio-owner" ]]
''')

    def test_replacement_sam_owner_is_never_restored(self):
        self.assertShell(self.context() + '''
printf 'pid=322\\nstart=78\\n' > "$mrsamtmp/session-owner"
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" && -e "$mrsamtmp/menu-audio-owner" ]]
''')

    def test_absent_baseline_fifo_still_requires_fresh_menu_marker(self):
        self.assertShell(self.context() + '''
sam_menu_initial_fifo= sam_menu_initial_main=
current_marker=marker-old
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" ]]
current_marker=marker-new
sam_menu_audio_restore 321 77
''')

    def test_restart_before_unmute_prevents_fifo_write(self):
        self.assertShell('''
SAM_MOUNTS_FILE="$mrsamtmp/mounts"; : > "$SAM_MOUNTS_FILE"
sam_volume_record_write "$configpath/Volume.dat" 00 pending
mute=global sam_menu_delivery_active=1
sam_menu_delivery_still_current(){ return 1; }
timeout(){ echo unexpected-write >&2; return 99; }
! sam_restore_audio
''')

    def test_internal_play_does_not_reload_after_failed_owned_cleanup(self):
        self.assertShell('''
sam_emit(){ :; }
sam_session_cleanup(){ return 1; }
mute=core; sam_exit_reload_path=/games/Actual.mra
timeout(){ printf unexpected > "$mrsamtmp/reloaded"; }
! sam_exit_finalize game 1
[[ ! -e "$mrsamtmp/reloaded" ]]
''')

    def test_main_identity_requires_single_exact_executable_and_start(self):
        self.assertShell('''
pids='10 20'
pidof(){ printf '%s\\n' "$pids"; }
readlink(){ printf '%s\\n' "$expected_exe"; }
sam_pid_start(){ sam_proc_start=100; }
expected_exe="$misterpath/MiSTer"
! sam_menu_main_identity
pids=10; expected_exe=/other/MiSTer
! sam_menu_main_identity
expected_exe="$misterpath/MiSTer"
sam_menu_main_identity
[[ "$sam_menu_main_key" == 10:100 ]]
''')

    def test_real_fifo_snapshot_tracks_new_incarnation_and_marker(self):
        self.assertShell('''
SAM_COMMAND_FIFO="$mrsamtmp/command-fifo"; SAM_CORENAME_FILE="$mrsamtmp/core"
printf 'MENU\\n' > "$SAM_CORENAME_FILE"
mkfifo "$SAM_COMMAND_FIFO"
main_key=10:100
sam_menu_main_identity(){ sam_menu_main_key=$main_key; }
sam_pid_start(){ sam_proc_start=${main_key#*:}; }
fifo_opened=0
sam_menu_main_has_fifo(){ [[ "$fifo_opened" == 1 ]]; }
sam_menu_delivery_begin
sam_menu_request_accepted=1
! sam_menu_delivery_ready
main_key=20:200
printf 'MENU\\n' > "$SAM_CORENAME_FILE"
! sam_menu_delivery_ready
rm "$SAM_COMMAND_FIFO"; mkfifo "$SAM_COMMAND_FIFO"
! sam_menu_delivery_ready
fifo_opened=1
sam_menu_delivery_ready
sam_menu_delivery_still_current
main_key=30:300
! sam_menu_delivery_still_current
''')

    def test_fifo_reader_check_matches_exact_device_inode(self):
        self.assertShell('''
SAM_COMMAND_FIFO="$mrsamtmp/command-fifo"
mkfifo "$SAM_COMMAND_FIFO"
sam_menu_snapshot_main="$BASHPID:100"
sam_menu_snapshot_fifo=$(stat -Lc '%d:%i|%z' "$SAM_COMMAND_FIFO")
! sam_menu_main_has_fifo
exec {reader}<> "$SAM_COMMAND_FIFO"
sam_menu_main_has_fifo
rm "$SAM_COMMAND_FIFO"; mkfifo "$SAM_COMMAND_FIFO"
sam_menu_snapshot_fifo=$(stat -Lc '%d:%i|%z' "$SAM_COMMAND_FIFO")
! sam_menu_main_has_fifo
exec {reader}>&-
''')

    def quiesced_context(self):
        return '''
sam_exit_menu_context_owner=321:77 sam_exit_menu_request_accepted=0
session="$mrsamtmp/session-321:77"; mkdir -p "$session"
printf 'pid=321\\nstart=77\\nphase=stopping\\n' > "$mrsamtmp/session-owner"
printf '321:77\\n' > "$mrsamtmp/menu-audio-owner"
sam_pid_start(){ sam_proc_start=77; }
sam_cleanup_failure_pending(){ return 1; }
write_count=0
timeout(){ [[ "$1" == 0.2s && "$2" == sh ]]; write_count=$((write_count+1)); }
'''

    def test_early_menu_requires_quiescence_and_cancelled_core_jobs(self):
        self.assertShell(self.quiesced_context() + '''
sam_menu_dispatch_quiesced_owner 321 77
[[ "$write_count" == 0 ]]
printf '321:77\\n' > "$session/quiesced"; : > "$session/alive"
sam_menu_dispatch_quiesced_owner 321 77
[[ "$write_count" == 0 ]]
rm "$session/alive"
sam_cleanup_failure_pending(){ return 0; }
sam_menu_dispatch_quiesced_owner 321 77
[[ "$write_count" == 0 ]]
sam_cleanup_failure_pending(){ return 1; }
sam_menu_dispatch_quiesced_owner 321 77
sam_menu_dispatch_quiesced_owner 321 77
[[ "$write_count" == 1 && "$sam_exit_menu_request_accepted" == 1 ]]
''')

    def test_early_menu_rejects_stale_barrier_replacement_and_cancelled_intent(self):
        self.assertShell(self.quiesced_context() + '''
printf '999:88\\n' > "$session/quiesced"
sam_menu_dispatch_quiesced_owner 321 77
printf '321:77\\n' > "$session/quiesced"
printf 'pid=322\\nstart=78\\nphase=stopping\\n' > "$mrsamtmp/session-owner"
sam_menu_dispatch_quiesced_owner 321 77
printf 'pid=321\\nstart=77\\nphase=playing\\n' > "$mrsamtmp/session-owner"
sam_menu_dispatch_quiesced_owner 321 77
printf 'pid=321\\nstart=77\\nphase=stopping\\n' > "$mrsamtmp/session-owner"
printf '999:88\\n' > "$mrsamtmp/menu-audio-owner"
sam_menu_dispatch_quiesced_owner 321 77
[[ "$write_count" == 0 ]]
''')

    def test_finalizer_observes_accepted_early_request_before_another_load(self):
        self.assertShell(self.context() + '''
sam_exit_expected_owner=321:77 sam_exit_menu_context_owner=321:77
sam_exit_menu_request_accepted=1
sam_exit_menu_initial_main=10:100 sam_exit_menu_initial_fifo=fifo-old sam_exit_menu_initial_marker=marker-old
snapshot_valid=0 poll_count=0
sleep(){ poll_count=$((poll_count+1)); if ((poll_count == 3)); then snapshot_valid=1; fi; return 0; }
timeout(){ printf duplicate > "$mrsamtmp/duplicate-load"; return 1; }
sam_exit_finalize menu 0
[[ "$poll_count" == 3 && ! -e "$mrsamtmp/duplicate-load" && $(<"$mrsamtmp/restored") == restored ]]
''')

    def test_failed_early_write_uses_normal_retry_with_original_baseline(self):
        self.assertShell(self.context() + '''
sam_exit_expected_owner=321:77 sam_exit_menu_context_owner=321:77
sam_exit_menu_request_accepted=0
sam_exit_menu_initial_main=10:100 sam_exit_menu_initial_fifo=fifo-old sam_exit_menu_initial_marker=marker-old
timeout(){ [[ "$1" == 1s ]]; printf retry >> "$mrsamtmp/loads"; }
sleep(){ :; }
sam_exit_finalize menu 0
[[ $(<"$mrsamtmp/loads") == retry && $(<"$mrsamtmp/restored") == restored ]]
''')

    def test_keep_game_never_uses_early_menu_context(self):
        self.assertShell('''
sam_exit_menu_context_owner=321:77 sam_exit_menu_request_accepted=1
mute=no
sam_emit(){ :; }
sam_cleanup(){ printf cleaned > "$mrsamtmp/cleaned"; }
timeout(){ echo unexpected-menu >&2; return 99; }
sam_exit_finalize game 0
[[ $(<"$mrsamtmp/cleaned") == cleaned ]]
''')

    def test_menu_dispatched_while_owner_finishes_optional_cleanup(self):
        self.assertShell('''
cat > "$mrsamtmp/owner.sh" <<'OWNER'
source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
sam_session_begin || exit 1
critical(){ printf started > "$mrsamtmp/critical-started"; printf done > "$mrsamtmp/critical-done"; }
critical_audio(){
    printf started > "$mrsamtmp/audio-started"
    local i
    for ((i=0;i<300;i++)); do
        [[ ! -e "$mrsamtmp/early-menu" ]] || break
        sleep .01
    done
    [[ -e "$mrsamtmp/early-menu" ]] || return 1
    printf done > "$mrsamtmp/audio-done"
}
sam_register session_stop critical
sam_register audio_stop critical_audio
sam_cleanup(){
    printf started > "$mrsamtmp/optional-started"
    local i
    for ((i=0;i<300;i++)); do
        [[ ! -e "$mrsamtmp/early-menu" ]] || break
        sleep .01
    done
    printf done > "$mrsamtmp/optional-done"
}
trap sam_session_cleanup EXIT
trap 'exit 0' TERM
printf ready > "$mrsamtmp/owner-ready"
while :; do sleep .1; done
OWNER
bash "$mrsamtmp/owner.sh" & child=$!
trap 'kill -TERM "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true' EXIT
while [[ ! -e "$mrsamtmp/owner-ready" ]]; do sleep .01; done
sam_session_read_owner
owner_pid=$sam_session_owner_pid owner_start=$sam_session_owner_start
SAM_CORENAME_FILE="$mrsamtmp/core"; printf 'MENU\\n' > "$SAM_CORENAME_FILE"
sam_menu_delivery_begin(){
    [[ ! -e "$mrsamtmp/critical-started" ]] || return 1
    sam_menu_initial_main=10:100 sam_menu_initial_fifo=fifo-old sam_menu_initial_marker=marker-old
}
timeout(){
    if [[ "$1" == 0.2s && "$2" == sh ]]; then
        [[ -e "$mrsamtmp/critical-done" && ! -e "$mrsamtmp/audio-done" && ! -e "$mrsamtmp/optional-done" ]] || return 1
        printf menu > "$mrsamtmp/early-menu"
    elif [[ "$2" == tmux ]]; then return 0
    else printf duplicate > "$mrsamtmp/duplicate-menu"; return 1; fi
}
sam_exit_menu=1
there_can_be_only_one "$owner_pid" "$owner_start"
wait "$child"
[[ $(<"$mrsamtmp/early-menu") == menu && -e "$mrsamtmp/optional-done" ]]
sam_menu_delivery_snapshot(){
    sam_menu_snapshot_main=20:200 sam_menu_snapshot_fifo=fifo-new sam_menu_snapshot_marker=marker-new
}
sam_restore_audio(){ printf restored > "$mrsamtmp/restored"; }
exit_sam menu
[[ ! -e "$mrsamtmp/duplicate-menu" && $(<"$mrsamtmp/restored") == restored ]]
''')

    def finalizer_context(self):
        return self.context() + '''
sam_exit_expected_owner=321:77 sam_exit_menu_context_owner=321:77
sam_exit_menu_request_accepted=1
sam_exit_menu_initial_main=10:100 sam_exit_menu_initial_fifo=fifo-old sam_exit_menu_initial_marker=marker-old
unset SECONDS; SECONDS=0
sleep(){ :; }
'''

    def test_audio_failure_retries_without_reloading_fresh_menu(self):
        self.assertShell(self.finalizer_context() + '''
audio_calls=0 loads=0
sam_restore_audio(){ audio_calls=$((audio_calls+1)); SECONDS=$((SECONDS+1)); return 1; }
timeout(){ loads=$((loads+1)); return 0; }
! sam_exit_finalize menu 0 > "$mrsamtmp/result" 2>&1
[[ "$audio_calls" == 20 && "$loads" == 0 && "$SECONDS" == 20 ]]
[[ -e "$mrsamtmp/menu-audio-owner" ]]
grep -q 'Menu was observed, but audio restoration' "$mrsamtmp/result"
''')

    def test_slow_failed_audio_calls_share_one_completion_budget(self):
        self.assertShell(self.finalizer_context() + '''
audio_calls=0
sam_restore_audio(){
    [[ "$sam_menu_deadline" == 20 ]] || return 99
    audio_calls=$((audio_calls+1)); SECONDS=$((SECONDS+6)); return 1
}
timeout(){ echo unexpected-reload >&2; return 99; }
! sam_exit_finalize menu 0 > "$mrsamtmp/result" 2>&1
[[ "$audio_calls" == 4 && "$SECONDS" == 24 && -e "$mrsamtmp/menu-audio-owner" ]]
grep -q 'Menu was observed, but audio restoration' "$mrsamtmp/result"
''')

    def test_stale_menu_deadline_never_attempts_audio_release(self):
        self.assertShell(self.finalizer_context() + '''
snapshot_valid=0
sleep(){ SECONDS=$((SECONDS+5)); }
sam_restore_audio(){ printf unsafe > "$mrsamtmp/audio-attempted"; }
timeout(){ echo unexpected-reload >&2; return 99; }
! sam_exit_finalize menu 0 > "$mrsamtmp/result" 2>&1
[[ "$SECONDS" == 20 && ! -e "$mrsamtmp/audio-attempted" && -e "$mrsamtmp/menu-audio-owner" ]]
grep -q 'Menu completion timed out' "$mrsamtmp/result"
''')

    def test_expired_write_budget_stops_before_polling_or_audio(self):
        self.assertShell(self.finalizer_context() + '''
sam_exit_menu_request_accepted=0
loads=0
timeout(){ loads=$((loads+1)); SECONDS=$((SECONDS+20)); return 1; }
sleep(){ printf unsafe > "$mrsamtmp/polled"; }
sam_restore_audio(){ printf unsafe > "$mrsamtmp/audio-attempted"; }
! sam_exit_finalize menu 0 > "$mrsamtmp/result" 2>&1
[[ "$loads" == 1 && "$SECONDS" == 20 && ! -e "$mrsamtmp/polled" && ! -e "$mrsamtmp/audio-attempted" ]]
[[ -e "$mrsamtmp/menu-audio-owner" ]]
''')

    def test_core_config_unmounts_obey_shared_restore_budget(self):
        self.assertShell('''
SAM_MOUNTS_FILE="$mrsamtmp/mounts"
printf 'tmpfs %s/One_volume.cfg none rw 0 0\\ntmpfs %s/Two_volume.cfg none rw 0 0\\ntmpfs %s/Three_volume.cfg none rw 0 0\\n' "$configpath" "$configpath" "$configpath" > "$SAM_MOUNTS_FILE"
unset SECONDS; SECONDS=0
sam_menu_delivery_active=1 sam_menu_deadline=5 calls=0
sam_core_volume_source_for_target(){ sam_core_volume_resolved="$mrsamtmp/mock-owned-volume"; }
sam_core_volume_owned(){ return 0; }
sam_volume_is_mounted(){ return 1; }
timeout(){ calls=$((calls+1)); SECONDS=$((SECONDS+3)); }
global_unmute(){ printf unsafe > "$mrsamtmp/global-released"; }
! sam_restore_audio
[[ "$calls" == 2 && "$SECONDS" == 6 && ! -e "$mrsamtmp/global-released" ]]
''')

    def test_keep_game_failed_owned_unmount_never_reloads(self):
        self.assertShell('''
mute=core; sam_exit_reload_path=/games/Actual.mra
sam_emit(){ :; }; sam_cleanup(){ :; }
SAM_MOUNTS_FILE="$mrsamtmp/mounts"
printf 'tmpfs %s/One_volume.cfg none rw 0 0\\n' "$configpath" > "$SAM_MOUNTS_FILE"
sam_core_volume_source_for_target(){ sam_core_volume_resolved="$mrsamtmp/mock-owned-volume"; }
sam_core_volume_owned(){ return 0; }
timeout(){
    if [[ "$2" == umount ]]; then return 1; fi
    printf unsafe > "$mrsamtmp/reloaded"
}
! sam_exit_finalize game 0
[[ ! -e "$mrsamtmp/reloaded" ]]
''')

    def test_keep_game_global_ack_failure_retains_record(self):
        self.assertShell('''
mute=global; sam_emit(){ :; }; sam_cleanup(){ :; }
SAM_MOUNTS_FILE="$mrsamtmp/mounts"; : > "$SAM_MOUNTS_FILE"
printf pending > "$mrsamtmp/volume-restore"
global_unmute(){ return 1; }
! sam_exit_finalize game 0
[[ $(<"$mrsamtmp/volume-restore") == pending ]]
''')

    def test_failed_audio_service_retry_blocks_restoration_and_reload(self):
        self.assertShell('''
sam_emit(){ [[ "$1" != audio_stop ]]; }
sam_session_cleanup(){ :; }
sam_restore_audio(){ printf unsafe > "$mrsamtmp/restored"; }
timeout(){ printf unsafe > "$mrsamtmp/reloaded"; }
mute=core; sam_exit_reload_path=/games/Actual.mra
! sam_exit_finalize game 1
! sam_exit_finalize menu 0
[[ ! -e "$mrsamtmp/restored" && ! -e "$mrsamtmp/reloaded" ]]
''')

    def test_absent_audio_player_is_noop_and_callback_retries_once(self):
        self.assertShell('''
sam_load_module bgm
bgmstop=yes; sam_bgm_pids(){ :; }
sam_cleanup(){ :; }; sam_restore_audio(){ :; }
mute=no
sam_exit_finalize game 0
stop_calls=0
sam_emit(){
    if [[ "$1" == audio_stop ]]; then stop_calls=$((stop_calls+1)); fi
    return 0
}
sam_exit_finalize game 0
[[ "$stop_calls" == 1 ]]
''')

    def test_verified_early_menu_receipt_does_not_stop_menu_music_again(self):
        self.assertShell(self.finalizer_context() + '''
sam_emit(){ [[ "$1" != audio_stop ]]; }
timeout(){ echo duplicate-menu >&2; return 99; }
sam_exit_finalize menu 0
[[ $(<"$mrsamtmp/restored") == restored ]]
''')

    def test_failed_or_mismatched_early_receipt_still_retries_audio_stop(self):
        self.assertShell(self.finalizer_context() + '''
sam_emit(){ [[ "$1" != audio_stop ]]; }
sam_restore_audio(){ printf unsafe > "$mrsamtmp/restored"; }
rm -f "$mrsamtmp/menu-audio-complete"
! sam_exit_finalize menu 0
printf '999:88\\n' > "$mrsamtmp/menu-audio-complete"
! sam_exit_finalize menu 0
[[ ! -e "$mrsamtmp/restored" ]]
''')

    def test_menu_handoff_without_audio_completion_cannot_unmute(self):
        self.assertShell(self.context() + '''
rm -f "$mrsamtmp/menu-audio-complete"
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" ]]
printf '999:88\\n' > "$mrsamtmp/menu-audio-complete"
! sam_menu_audio_restore 321 77
[[ ! -e "$mrsamtmp/restored" ]]
printf '321:77\\n' > "$mrsamtmp/menu-audio-complete"
sam_menu_audio_restore 321 77
[[ $(<"$mrsamtmp/restored") == restored ]]
''')

    def test_dead_owner_retry_recovers_pending_audio_under_admission_lock(self):
        self.assertShell(self.context() + '''
rm -f "$mrsamtmp/menu-audio-complete"
sam_exit_expected_owner=0:0
sam_session_lock(){ retry_locked=1; sam_session_lock_fd=42; }
sam_session_unlock(){ retry_locked=0; }
flock(){ [[ "$retry_locked" == 1 ]]; }
sam_emit(){
    if [[ "$1" == audio_stop ]]; then
        [[ "$retry_locked" == 1 && "$2" == menu ]]
        printf retried > "$mrsamtmp/retried"
    fi
}
sam_exit_finalize(){
    [[ "$retry_locked" == 1 && "$sam_exit_expected_owner" == 321:77 ]]
    sam_finish_audio_stop "$1" "$sam_exit_expected_owner"
    sam_menu_audio_restore 321 77
}
exit_sam menu
[[ "$retry_locked" == 0 && $(<"$mrsamtmp/retried") == retried ]]
[[ $(<"$mrsamtmp/restored") == restored ]]
[[ ! -e "$mrsamtmp/menu-audio-owner" && ! -e "$mrsamtmp/menu-audio-complete" ]]
''')

    def deferred_preparation_context(self):
        return '''
sam_session_begin
printf '%s\\n' "$sam_owner" > "$mrsamtmp/menu-audio-owner"
sam_exit_menu_context_owner=$sam_owner sam_exit_menu_request_accepted=0
SAM_CORENAME_FILE="$mrsamtmp/core"; printf 'MENU\\n' > "$SAM_CORENAME_FILE"
sam_cancel_launch_job(){ printf launch-cancelled >> "$mrsamtmp/order"; }
sam_emit(){
    if [[ "$1" == audio_stop ]]; then
        [[ -e "$mrsamtmp/preparation-finished" ]]
        printf ':audio-stop' >> "$mrsamtmp/order"
    fi
    return 0
}
sam_cleanup(){ :; }
sam_restore_audio(){ printf unsafe > "$mrsamtmp/restored"; }
timeout(){
    [[ "$1" == 0.2s && "$2" == sh && ! -e "$mrsamtmp/preparation-finished" ]]
    printf ':menu' >> "$mrsamtmp/order"
    : > "$mrsamtmp/menu-dispatched"
}
'''

    def test_menu_dispatch_precedes_preparation_completion_and_audio_restore(self):
        self.assertShell(self.deferred_preparation_context() + '''
sam_cancel_preparation(){
    [[ ! -e "$sam_session/alive" && -r "$sam_session/quiesced" ]]
    sam_menu_dispatch_quiesced_owner "${sam_owner%%:*}" "${sam_owner#*:}"
    [[ -e "$mrsamtmp/menu-dispatched" && "$sam_exit_menu_request_accepted" == 1 ]]
    ! sam_menu_audio_restore "${sam_owner%%:*}" "${sam_owner#*:}"
    [[ ! -e "$mrsamtmp/restored" && ! -e "$mrsamtmp/menu-audio-complete" ]]
    printf ':preparation-finished' >> "$mrsamtmp/order"
    : > "$mrsamtmp/preparation-finished"
}
sam_session_cleanup
[[ $(<"$mrsamtmp/order") == launch-cancelled:menu:preparation-finished:audio-stop ]]
[[ $(<"$mrsamtmp/menu-audio-complete") == "$sam_owner" && ! -e "$mrsamtmp/restored" ]]
''')

    def test_preparation_failure_after_menu_retains_evidence_and_blocks_audio_and_start(self):
        self.assertShell(self.deferred_preparation_context() + '''
sam_worker_pid=999 sam_worker_start=77 sam_worker_group= sam_worker_sid=
sam_cancel_preparation(){
    sam_menu_dispatch_quiesced_owner "${sam_owner%%:*}" "${sam_owner#*:}"
    [[ -e "$mrsamtmp/menu-dispatched" ]]
    : > "$mrsamtmp/preparation-finished"
    sam_job_error='Preparation remains blocked'
    return 1
}
! sam_session_cleanup
[[ -d "$sam_session" && -r "$sam_session/cleanup-error" ]]
[[ $(<"$sam_session/cleanup-error") == 'Preparation remains blocked' ]]
[[ -r "$mrsamtmp/cleanup-failure" && ! -e "$mrsamtmp/menu-audio-complete" ]]
sam_pid_start(){ [[ "$1" == 999 ]] || return 1; sam_proc_start=77; }
sam_cleanup_failure_pending
! sam_menu_audio_restore "${sam_owner%%:*}" "${sam_owner#*:}"
[[ ! -e "$mrsamtmp/restored" ]]
! there_can_be_only_one 0 0
[[ -d "$sam_session" && -r "$mrsamtmp/cleanup-failure" ]]
trap - EXIT TERM
''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
