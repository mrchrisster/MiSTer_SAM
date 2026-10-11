"""Session transitions and concurrent admission; no hardware or live folders."""
import unittest
import test_shell


class Session(unittest.TestCase):
    def setUp(self):
        self.fixture = test_shell.Shell()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def check(self, code):
        result = self.fixture.shell('sam_cleanup(){ :; }; sam_emit(){ :; }\n'+code)
        self.assertEqual(result.returncode, 0, result.stderr + '\n' + result.stdout)

    def test_transitions_generations_and_worker_rejection(self):
        self.check('''sam_session_begin
[[ "$sam_last_phase:$sam_launch_serial" == preparing:0 ]]
! sam_publish_phase nonsense
sam_publish_phase loading
sam_publish_phase loading
[[ "$sam_launch_serial" == 2 ]]
sam_publish_phase playing
sam_publish_phase playing
[[ "$sam_launch_serial" == 2 ]]
! (sam_publish_phase stopping)
[[ "$(<"$mrsamtmp/session-owner")" == *phase=playing* ]]
sam_publish_phase preparing
sam_publish_phase video
sam_publish_phase preparing
sam_publish_phase stopping
! sam_publish_phase loading
''')

    def test_live_owner_refuses_second_session_and_dead_owner_recovers(self):
        self.check('''sam_session_begin
before=$(<"$mrsamtmp/session-owner")
! bash -c 'source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only; sam_cleanup(){ :; }; sam_emit(){ :; }; sam_session_begin'
[[ "$(<"$mrsamtmp/session-owner")" == "$before" ]]
printf 'pid=99999999\\nstart=1\\nphase=playing\\n' > "$mrsamtmp/session-owner"
sam_session_begin
[[ "$sam_last_phase:$sam_launch_serial" == preparing:0 ]]
''')

    def test_replaced_owner_cannot_publish_or_cleanup_global_state(self):
        self.check('''sam_session_begin
sam_cleanup(){ touch "$SAM_TMP_ROOT/unsafe-cleanup"; }
sam_emit(){ touch "$SAM_TMP_ROOT/unsafe-event"; }
printf 'pid=99999999\\nstart=1\\nphase=playing\\n' > "$mrsamtmp/session-owner"
! sam_publish_phase loading
sam_session_cleanup
[[ ! -e "$SAM_TMP_ROOT/unsafe-cleanup" && ! -e "$SAM_TMP_ROOT/unsafe-event" ]]
[[ ! -d "$sam_session" && "$(<"$mrsamtmp/session-owner")" == *pid=99999999* ]]
''')

    def test_cleanup_once_and_preserves_stopping_wire_record(self):
        self.check('''sam_session_begin
sam_cleanup(){ printf cleanup >> "$SAM_TMP_ROOT/cleanup"; }
sam_emit(){ :; }
sam_session_cleanup
sam_session_cleanup
[[ "$(<"$SAM_TMP_ROOT/cleanup")" == cleanup ]]
[[ ! -d "$sam_session" && "$(<"$mrsamtmp/session-owner")" == *phase=stopping* ]]
''')

    def test_simultaneous_begin_has_one_winner(self):
        self.check('''mkdir -p "$mrsamtmp"
for index in 1 2; do
    INDEX=$index bash -c '
        source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
        sam_cleanup(){ :; }; sam_emit(){ :; }
        while [[ ! -e "$SAM_TMP_ROOT/go" ]]; do sleep 0.01; done
        if sam_session_begin; then
            : > "$SAM_TMP_ROOT/winner-$INDEX"
            sleep 1
        fi
    ' &
done
: > "$SAM_TMP_ROOT/go"
wait
winners=("$SAM_TMP_ROOT"/winner-*)
[[ "${#winners[@]}" == 1 && -f "${winners[0]}" ]]
''')

    def test_signal_during_transition_releases_resources_and_lock(self):
        self.check('''sam_session_begin
sam_cleanup(){ : > "$SAM_TMP_ROOT/cleaned"; }
sam_emit(){ :; }
sam_session_write_phase(){
    if [[ "$1" == loading ]]; then kill -TERM "$$"; fi
    local temp="$mrsamtmp/session-owner.tmp.$BASHPID"
    printf 'pid=%s\\nstart=%s\\nphase=%s\\nlaunch=%s\\n' "${sam_owner%%:*}" "${sam_owner#*:}" "$1" "$2" > "$temp"
    mv "$temp" "$mrsamtmp/session-owner"
}
# TERM exits this shell; an EXIT assertion verifies cleanup ran and unlocked.
trap 'sam_session_cleanup; [[ -e "$SAM_TMP_ROOT/cleaned" ]]; flock -n "$mrsamtmp/session-owner.lock" true' EXIT
sam_publish_phase loading
''')

    def test_stop_targets_captured_session_id_across_replacement(self):
        self.check('''mkdir -p "$mrsamtmp"
printf 'pid=321\\nstart=77\\n' > "$mrsamtmp/session-owner"
alive=1
sam_pid_start(){ sam_proc_start=77; [[ "$1" == 321 && "$alive" == 1 ]]; }
kill(){ alive=0; }
timeout(){ shift; "$@"; }
tmux(){
    case "$1" in
        list-panes) [[ "$3" == '=SAM' ]]; printf '$7 321 900\\n' ;;
        if-shell)
            # A replacement can appear after the final owner-file check.
            printf 'pid=322\\nstart=78\\n' > "$mrsamtmp/session-owner"
            [[ "$4" == '$7' && "$5" == '#{&&:#{==:#{pid},900},#{==:#{pane_pid},321}}' && "$6" == *"$4"* ]] || return 99
            : > "$SAM_TMP_ROOT/captured-pane-closed"
            ;;
        *) return 99 ;;
    esac
}
there_can_be_only_one 321 77
[[ -e "$SAM_TMP_ROOT/captured-pane-closed" ]]
''')

    def test_stop_never_removes_unverified_named_pane(self):
        self.check('''mkdir -p "$mrsamtmp"
printf 'pid=321\\nstart=77\\n' > "$mrsamtmp/session-owner"
alive=1
sam_pid_start(){ sam_proc_start=77; [[ "$1" == 321 && "$alive" == 1 ]]; }
kill(){ alive=0; }
timeout(){ shift; "$@"; }
tmux(){
    case "$1" in
        list-panes) printf '$8 322 900\\n' ;;
        *) : > "$SAM_TMP_ROOT/unsafe-pane-kill"; return 99 ;;
    esac
}
there_can_be_only_one 321 77
[[ ! -e "$SAM_TMP_ROOT/unsafe-pane-kill" ]]
rm "$mrsamtmp/session-owner"
there_can_be_only_one
[[ ! -e "$SAM_TMP_ROOT/unsafe-pane-kill" ]]
''')

    def test_video_phase_rejection_cannot_start_player(self):
        self.check('''source "$mrsampath/modules/video-functions.sh"
samvideo_freq=only
sam_publish_phase(){ return 1; }
samvideo_play(){ : > "$SAM_TMP_ROOT/unsafe-player"; }
rc=0; load_samvideo || rc=$?
[[ "$rc" == 2 ]]
wait
[[ ! -e "$SAM_TMP_ROOT/unsafe-player" ]]
''')

    def test_video_sentinel_and_fatal_status_remain_distinct(self):
        self.check('''source "$mrsampath/modules/video-functions.sh"
samvideo_freq=only
sam_publish_phase(){ return 0; }
samvideo_play(){ : > "$SAM_TMP_ROOT/player"; }
rc=0; load_samvideo || rc=$?
[[ "$rc" == 1 ]]
wait
[[ -e "$SAM_TMP_ROOT/player" ]]
source "$mrsampath/modules/compat-loop.sh"
corelist_update(){ :; }; sam_core_require(){ :; }
samvideo=yes
load_samvideo(){ return 2; }
sv_nextcore=
rc=0; next_core '' || rc=$?
[[ "$rc" == 2 && -z "$sv_nextcore" ]]
load_samvideo(){ return 1; }
next_core ''
[[ "$sv_nextcore" == samvideo ]]
''')

    def test_stop_reused_session_id_is_guarded_by_tmux_server_identity(self):
        self.check('''mkdir -p "$mrsamtmp"
printf 'pid=321\\nstart=77\\n' > "$mrsamtmp/session-owner"
alive=1
sam_pid_start(){ sam_proc_start=77; [[ "$1" == 321 && "$alive" == 1 ]]; }
kill(){ alive=0; }
timeout(){ shift; "$@"; }
tmux(){
    case "$1" in
        list-panes) printf '$0 321 900\\n' ;;
        if-shell)
            # Same ID now belongs to a new server/pane; the atomic predicate
            # must still compare the captured server and old foreground PID.
            [[ "$4" == '$0' && "$5" == '#{&&:#{==:#{pid},900},#{==:#{pane_pid},321}}' ]]
            : > "$SAM_TMP_ROOT/guarded-pane-command"
            ;;
        kill-session) : > "$SAM_TMP_ROOT/unsafe-pane-kill"; return 99 ;;
        *) return 99 ;;
    esac
}
there_can_be_only_one 321 77
[[ -e "$SAM_TMP_ROOT/guarded-pane-command" && ! -e "$SAM_TMP_ROOT/unsafe-pane-kill" ]]
''')

    def test_phase_transitions_use_one_lock_helper_and_ticks_use_none(self):
        self.check('''flock(){
    printf '%s\\n' "$*" >> "$SAM_TMP_ROOT/lock-calls"
    command flock "$@"
}
sam_session_begin
sam_publish_phase preparing
sam_publish_phase loading
sam_publish_phase playing
for tick in 1 2 3 4 5; do sam_publish_phase playing; done
! (sam_publish_phase stopping)
count=0
while IFS= read -r line; do
    [[ "$line" == '-x -w 2 '* ]]
    count=$((count+1))
done < "$SAM_TMP_ROOT/lock-calls"
[[ "$count" == 3 ]]
# The latest transition's FD was closed rather than retained across ticks.
command flock -n "$mrsamtmp/session-owner.lock" true
''')

    def test_replacement_before_exit_finalization_has_no_resource_actions(self):
        self.check('''mkdir -p "$mrsamtmp"
sam_exit_expected_owner=321:77
printf 'pid=322\\nstart=78\\nphase=playing\\n' > "$mrsamtmp/session-owner"
sam_pid_start(){ sam_proc_start=78; return 0; }
sam_emit(){ : > "$SAM_TMP_ROOT/unsafe-resource"; }
sam_cleanup(){ : > "$SAM_TMP_ROOT/unsafe-resource"; }
timeout(){ : > "$SAM_TMP_ROOT/unsafe-resource"; }
mute=core; sam_exit_reload_path=/games/Old.mra
! exit_sam game
! exit_sam menu
[[ ! -e "$SAM_TMP_ROOT/unsafe-resource" ]]
# A replacement that has already stopped still invalidates the old request.
sam_pid_start(){ return 1; }
! exit_sam game
[[ ! -e "$SAM_TMP_ROOT/unsafe-resource" ]]
command flock -n "$mrsamtmp/session-owner.lock" true
''')

    def test_inactive_exit_rejects_late_live_owner_before_display_off(self):
        self.check('''mkdir -p "$mrsamtmp"
sam_exit_expected_owner=0:0
printf 'pid=322\\nstart=78\\n' > "$mrsamtmp/session-owner"
sam_pid_start(){ sam_proc_start=78; return 0; }
sam_emit(){ : > "$SAM_TMP_ROOT/unsafe-resource"; }
sam_cleanup(){ : > "$SAM_TMP_ROOT/unsafe-resource"; }
! exit_sam game
[[ ! -e "$SAM_TMP_ROOT/unsafe-resource" ]]
''')

    def test_ownerless_menu_finalization_holds_admission_until_restored(self):
        self.check('''mkdir -p "$mrsamtmp"
sam_exit_expected_owner=0:0
sam_emit(){
    ! command flock -n "$mrsamtmp/session-owner.lock" true
}
sam_menu_exit_guard(){
    ! command flock -n "$mrsamtmp/session-owner.lock" true
}
sam_menu_audio_restore(){
    ! command flock -n "$mrsamtmp/session-owner.lock" true
}
timeout(){ :; }; sleep(){ :; }
exit_sam menu
command flock -n "$mrsamtmp/session-owner.lock" true
''')

    def test_external_exit_unlocks_descriptors_inherited_by_background_hook(self):
        self.check('''mkdir -p "$mrsamtmp"
sam_exit_expected_owner=0:0
mute=no
sam_cleanup(){ :; }
sam_emit(){
    if [[ "$1" == display_shutdown ]]; then
        sleep 3 &
        teardown_helper=$!
    fi
    return 0
}
exit_sam game
kill -0 "$teardown_helper"
# Helper is still alive with an inherited FD; explicit external-finalization
# unlock must make the shared lock immediately available anyway.
command flock -n "$mrsamtmp/session-owner.lock" true
kill -TERM "$teardown_helper"
wait "$teardown_helper" || true
''')
