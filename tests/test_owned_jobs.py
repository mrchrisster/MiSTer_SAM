"""Native private-job groups; no production paths, core loads, or broad kills."""
import unittest
from pathlib import Path
import test_shell


@unittest.skipUnless(Path('/proc/self/stat').exists(), 'Linux procfs required')
class OwnedJobs(test_shell.Shell):
    # Run only this class's tests; inherited Shell tests are tested separately.
    def test_group_registration_restores_monitor_and_traps_and_excludes_other_jobs(self):
        self.assertShell(r'''
trap ':' TERM
original=$(trap -p TERM)
sleep 60 & other=$!
sam_pid_start "$other"; other_start=$sam_proc_start; other_group=$sam_proc_group
job(){ printf '%s\n' "$-" > "$mrsamtmp/child-flags";sleep 60; }
sam_job_spawn sam_launch job
[[ "$-" != *m* && "$(trap -p TERM)" == "$original" ]]
[[ "$sam_launch_group" == "$sam_launch_pid" && "$sam_launch_group" != "$other_group" ]]
[[ $(readlink "/proc/$sam_launch_pid/fd/0") == /dev/null ]]
sam_cancel_launch_job
sam_pid_start "$other"; [[ "$sam_proc_start" == "$other_start" ]]
[[ $(<"$mrsamtmp/child-flags") != *m* ]]
kill -TERM "$other";wait "$other" || true
set -m
sam_job_spawn sam_launch sleep 60
[[ "$-" == *m* ]]
set +m
sam_cancel_launch_job
''')

    def test_active_forks_leave_no_group_members_after_cancel(self):
        self.assertShell(r'''
record_pid(){ local pid=$1; if sam_pid_start "$pid";then printf '%s %s\n' "$pid" "$sam_proc_start" >> "$mrsamtmp/pids";fi; }
active_job(){
    for ((i=0;i<20;i++));do
        (sleep 60 & record_pid "$!";wait) & record_pid "$!"
        printf ready > "$mrsamtmp/ready"
        sleep 0.01
    done
    wait
}
sam_job_spawn sam_worker active_job
for ((i=0;i<100;i++));do [[ ! -e "$mrsamtmp/ready" ]] || break;sleep 0.01;done
started=$SECONDS
sam_cancel_preparation
((SECONDS-started < 5))
while read -r pid ticks;do
    if sam_pid_start "$pid";then [[ "$sam_proc_start" != "$ticks" ]];fi
done < "$mrsamtmp/pids"
''')

    def test_grouped_callbacks_do_not_keep_the_owner_transition_flock(self):
        self.assertShell(r'''
sam_session_lock
sam_job_spawn sam_launch sleep 60
sam_session_unlock
flock -n "$mrsamtmp/session-owner.lock" true
sam_cancel_launch_job
''')

    def test_term_handler_late_fork_and_ignored_term_are_killed(self):
        self.assertShell(r'''
job(){
    (
        trap 'sleep 60 & printf "%s\n" "$!" > "$mrsamtmp/handler-child"' TERM
        printf ready > "$mrsamtmp/ready"
        while :;do sleep 0.1;done
    ) &
    (trap '' TERM; sleep 60) &
    wait
}
sam_job_spawn sam_worker job
for ((i=0;i<100;i++));do [[ ! -e "$mrsamtmp/ready" ]] || break;sleep 0.01;done
group=$sam_worker_group;sid=$sam_worker_sid
sam_cancel_preparation
[[ -s "$mrsamtmp/handler-child" ]]
read -r child < "$mrsamtmp/handler-child"
! sam_pid_start "$child"
declare -A sam_job_members=() sam_job_children=()
sam_job_group_members "$group" "$sid"
[[ ${#sam_job_members[@]} == 0 ]]
''')

    def test_dead_leader_with_unknown_survivor_refuses_signals(self):
        self.assertShell(r'''
job(){ sleep 60 & printf '%s\n' "$!" > "$mrsamtmp/child";wait; }
sam_job_spawn sam_launch job
for ((i=0;i<100;i++));do [[ ! -s "$mrsamtmp/child" ]] || break;sleep 0.01;done
read -r child < "$mrsamtmp/child"
sam_pid_start "$child";child_start=$sam_proc_start
kill -KILL "$sam_launch_pid";wait "$sam_launch_pid" || true
! sam_cancel_launch_job
[[ "$sam_job_error" == *unproven* && -n "$sam_launch_pid" ]]
sam_pid_start "$child";[[ "$sam_proc_start" == "$child_start" ]]
kill -KILL "$child"
for ((i=0;i<100;i++));do sam_pid_start "$child" || break;sleep 0.01;done
sam_cancel_launch_job
''')

    def test_wrong_start_or_group_or_sid_never_signals_job(self):
        self.assertShell(r'''
sam_job_spawn sam_launch sleep 60
! sam_job_cancel "$sam_launch_pid" "$((sam_launch_start+1))" "$sam_launch_group" "$sam_launch_sid"
! sam_job_cancel "$sam_launch_pid" "$sam_launch_start" "$((sam_launch_group+1))" "$sam_launch_sid"
! sam_job_cancel "$sam_launch_pid" "$sam_launch_start" "$sam_launch_group" "$((sam_launch_sid+1))"
sam_pid_start "$sam_launch_pid";[[ "$sam_proc_start" == "$sam_launch_start" ]]
sam_cancel_launch_job
''')

    def test_uninterruptible_group_failure_is_bounded_without_wait(self):
        self.assertShell(r'''
signals=;sleeps=0
sam_pid_start(){
    sam_proc_start=77;sam_proc_group=9101;sam_proc_session=5000;sam_proc_state=D
    [[ "$1" != "$BASHPID" ]] || sam_proc_group=5000
    return 0
}
sam_job_group_members(){ sam_job_members=([9101]=77);sam_job_children=(); }
sleep(){ sleeps=$((sleeps+1)); }
kill(){ signals+=" $*"; }
! sam_job_cancel 9101 77 9101 5000
[[ "$sam_job_error" == *uninterruptible* && "$signals" == *'-KILL -- -9101'* && "$sleeps" -le 40 ]]
''')

    def test_session_failure_preserves_evidence_without_audio_or_mount_cleanup(self):
        self.assertShell(r'''
sam_session_begin
sam_worker_pid=9101;sam_worker_start=77;sam_worker_group=9101;sam_worker_sid=5000
sam_cancel_preparation(){ sam_job_error='simulated blocked I/O';return 1; }
sam_cleanup(){ echo unsafe-cleanup >&2;return 99; }
sam_emit(){ echo unsafe-hook >&2;return 99; }
! sam_session_cleanup
[[ "$sam_session_cleaned" == 0 && -d "$sam_session" && -s "$sam_session/cleanup-error" ]]
[[ -s "$mrsamtmp/cleanup-failure" && -s "$mrsamtmp/last-error.log" ]]
grep -q 'simulated blocked I/O' "$mrsamtmp/last-error.log"
trap - EXIT TERM
''')

    def test_failed_cleanup_vetoes_admission_until_owned_job_is_gone(self):
        self.assertShell(r'''
sam_job_spawn sam_worker sleep 60
sam_cleanup_failure_record sam_worker 'simulated cleanup refusal'
! sam_session_begin
[[ ! -e "$mrsamtmp/session-owner" ]]
sam_cancel_preparation
sam_cleanup(){ :; };sam_emit(){ :; }
sam_session_begin
[[ ! -e "$mrsamtmp/cleanup-failure" ]]
sam_session_cleanup
''')

    def test_menu_quiescence_follows_critical_hooks_and_precedes_optional_cleanup(self):
        self.assertShell(r'''
sam_session_begin
printf '%s\n' "$sam_owner" > "$mrsamtmp/menu-audio-owner"
sam_emit(){
    printf '%s\n' "$1" >> "$mrsamtmp/events"
    if [[ "$1" == audio_stop || "$1" == display_shutdown ]];then
        [[ -s "$sam_session/quiesced" && $(<"$sam_session/quiesced") == "$sam_owner" ]]
    fi
}
sam_session_cleanup
[[ $(<"$mrsamtmp/events") == $'session_stop\nmenu_prepare\naudio_stop\ndisplay_shutdown\ndisplay_exit' ]]
[[ "$sam_session_stop_done" == 1 && "$sam_audio_stop_done" == 1 ]]
''')

    def test_critical_hook_failure_never_publishes_quiescence_or_repeats_hooks(self):
        self.assertShell(r'''
sam_session_begin
printf '%s\n' "$sam_owner" > "$mrsamtmp/menu-audio-owner"
sam_emit(){
    printf '%s\n' "$1" >> "$mrsamtmp/events"
    if [[ "$1" == display_shutdown ]];then [[ ! -e "$sam_session/quiesced" ]];fi
    [[ "$1" != session_stop ]]
}
sam_session_cleanup
[[ $(<"$mrsamtmp/events") == $'session_stop\nmenu_prepare\naudio_stop\ndisplay_shutdown\ndisplay_exit' ]]
''')

    def test_zombie_leader_is_live_only_while_other_threads_remain(self):
        self.assertShell(r'''
sam_job_state_live Z 2
sam_job_state_live Z 4
! sam_job_state_live Z 1
! sam_job_state_live Z 0
! sam_job_state_live X 4
sam_job_state_live D 1
sam_job_state_live S 1
''')

    def test_zombie_leader_blocked_thread_keeps_cleanup_failure_pending(self):
        self.assertShell(r'''
root_alive=1;signals=
sam_pid_start(){
    sam_proc_start=77;sam_proc_group=9101;sam_proc_session=5000;sam_proc_state=T
    [[ "$1" != "$BASHPID" ]] || { sam_proc_group=5000;return 0; }
    [[ "$1" == 9101 && "$root_alive" == 1 ]]
}
sam_job_group_members(){
    sam_job_members=();sam_job_children=()
    if ((root_alive));then sam_job_members[9101]=77;fi
    # Model a main thread already Z while a worker thread cannot leave I/O.
    if sam_job_state_live Z 2;then sam_job_members[9102]=78;fi
}
sam_job_member_valid(){ [[ "$1" == 9102 ]] && sam_job_state_live Z 2; }
sleep(){ :; }
kill(){ signals+=" $*";if [[ "$1" == -KILL ]];then root_alive=0;fi; }
! sam_job_cancel 9101 77 9101 5000
[[ "$sam_job_error" == *uninterruptible* && "$signals" == *'-KILL -- -9101'* ]]
sam_worker_pid=9101;sam_worker_start=77;sam_worker_group=9101;sam_worker_sid=5000
sam_cleanup_failure_record sam_worker "$sam_job_error"
sam_cleanup_failure_pending
[[ -s "$mrsamtmp/cleanup-failure" ]]
''')


# Avoid repeating inherited Shell methods through unittest's class loader.
for _name in tuple(dir(test_shell.Shell)):
    if _name.startswith('test_') and _name not in OwnedJobs.__dict__:
        setattr(OwnedJobs, _name, None)
