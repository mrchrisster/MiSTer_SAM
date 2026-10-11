"""Lean normal/roulette engine integration using private state and mocked hardware.

Run on Linux/ARM alongside test_engine.py; no live hardware or installed state.
"""
import subprocess
import time
import unittest
from pathlib import Path
import test_engine


class NormalRuntime(test_engine.Engine):
    def ready(self):
        status = self.root / 'controls/status'
        if not status.exists():
            return False
        fields = dict(line.split('=', 1) for line in status.read_text().splitlines()
                      if '=' in line)
        return fields.get('ready') == '1' and fields.get('owner_pid') == str(self.proc.pid)

    def restart(self, overrides='', timer=0):
        self.stop()
        script = '''source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
sam_prep(){ :; }; disable_bootrom(){ :; }; sam_cleanup(){ :; }
load_core(){ printf '%s\\n' "$2" >> "$TEST_LOG"; sam_emit display_launch "$3" "$2" "$1" ''; sleep .05; }
''' + overrides + '\ngametimer=' + str(timer) + '\nloop_core snes\n'
        if self.log.exists():
            self.log.unlink()
        self.proc = subprocess.Popen(['bash', '-c', script], env=self.env,
                                     stdin=subprocess.PIPE, stdout=self.output,
                                     stderr=self.output)

    @staticmethod
    def alive(pid):
        try:
            fields = Path('/proc/%s/stat' % pid).read_text().rsplit(') ', 1)[1].split()
            return fields[0] not in {'Z', 'X', 'x'}
        except (OSError, IndexError):
            return False

    def test_zero_timer_never_automatically_advances(self):
        self.wait(self.ready)
        time.sleep(1.25)
        self.assertEqual(len(self.launches()), 1)
        self.key('n')
        self.wait(lambda: len(self.launches()) == 2)
        self.wait(self.ready)
        time.sleep(.5)
        self.assertEqual(len(self.launches()), 2)

    def test_pause_survives_deadline_and_duplicate_pause_resume(self):
        duration = 8
        self.restart(timer=duration)
        self.wait(self.ready)
        rc, reply = self.control('pause')
        self.assertEqual(rc, 0, str(reply) + '\n' + (self.root / 'output').read_text())
        paused = (self.root / 'controls/status').read_text()
        remaining = next(line for line in paused.splitlines() if line.startswith('remaining_seconds='))
        time.sleep(duration + .3)
        rc, reply = self.control('pause')
        self.assertEqual(reply['code'], 409, reply)
        self.assertNotEqual(rc, 0)
        self.assertIn(remaining, (self.root / 'controls/status').read_text())
        self.assertEqual(len(self.launches()), 1)
        self.assertIn('paused=1', (self.root / 'controls/status').read_text())
        rc, reply = self.control('resume')
        self.assertEqual(rc, 0, reply)
        rc, reply = self.control('resume')
        self.assertEqual(reply['code'], 409, reply)
        self.assertNotEqual(rc, 0)
        self.wait(lambda: len(self.launches()) == 2, timeout=duration + 4)

    def test_stop_during_blocked_preparation_reaps_owned_processes(self):
        self.restart('''
sam_prepare_worker(){
    printf '%s\\n' "$BASHPID" > "$mrsamtmp/blocked-worker"
    sleep 60
}
''')
        self.wait(lambda: (self.root / 'tmp/blocked-worker').exists())
        worker = int((self.root / 'tmp/blocked-worker').read_text())
        self.stop()
        self.assertFalse(self.alive(worker))
        self.assertEqual(self.launches(), [])
        self.assertFalse(list((self.root / 'tmp').glob('session-*/alive')))

    def test_term_during_worker_registration_reaps_without_force_kill(self):
        self.restart('''
sam_prepare_worker(){ sleep 60; }
# A deterministic signal inside the identity lookup exercises the formerly
# unprotected registration window without depending on scheduler timing.
sam_pid_start(){
    local line fields
    [[ -r "/proc/$1/stat" ]] || return 1
    IFS= read -r line < "/proc/$1/stat" || return 1
    read -ra fields <<< "${line##*) }"
    sam_proc_state=${fields[0]} sam_proc_start=${fields[19]} sam_proc_ppid=${fields[1]}
    sam_proc_group=${fields[2]} sam_proc_session=${fields[3]}
    if [[ "$1" == "${sam_worker_pid:-}" && "${registration_signalled:-0}" == 0 ]]; then
        registration_signalled=1
        printf '%s\\n' "$1" > "$mrsamtmp/registration-worker"
        kill -TERM "$$"
    fi
    [[ "$sam_proc_state" != Z && "$sam_proc_state" != X && "$sam_proc_state" != x ]]
}
''')
        self.proc.wait(timeout=4)
        worker = int((self.root / 'tmp/registration-worker').read_text())
        self.assertEqual(self.proc.returncode, 0, (self.root / 'output').read_text())
        self.assertFalse(self.alive(worker))
        self.assertEqual(self.launches(), [])
        self.assertFalse(list((self.root / 'tmp').glob('session-*/alive')))

    def test_playing_uses_no_persistent_timer_child(self):
        self.wait(self.ready)
        self.wait(lambda: bool(list((self.root / 'tmp').glob('session-*/ready/*.record'))))
        def children():
            child_file = Path('/proc/%s/task/%s/children' % (self.proc.pid, self.proc.pid))
            if child_file.exists():
                return child_file.read_text().split()
            result = []
            for stat in Path('/proc').glob('[0-9]*/stat'):
                try:
                    fields = stat.read_text().rsplit(') ', 1)[1].split()
                    if fields[1] == str(self.proc.pid) and fields[0] not in {'Z', 'X', 'x'}:
                        result.append(stat.parent.name)
                except (OSError, IndexError):
                    pass
            return result
        # Allow the next scheduled preparation check to reap its completed job.
        self.wait(lambda: not children())
        time.sleep(.3)
        self.assertEqual(children(), [])
        count = len(self.launches())
        self.stop()
        self.assertEqual(len(self.launches()), count)
        self.assertFalse(list((self.root / 'tmp').glob('session-*/alive')))
        self.assertIn('active=no', (self.root / 'state').read_text())

    def test_stale_candidate_cannot_reach_hardware(self):
        self.restart('''
sam_schedule_preparation(){
    if [[ ! -e "$mrsamtmp/stale-injected" ]]; then
        printf 'core=snes\\npath=%s\\nname=stale.sfc\\nowner=999:999\\nrevision=%s\\n' "$TEST_LOG" "$sam_revision" > "$sam_session/ready/stale.record"
        printf '%s\\n' "$sam_session/ready/stale.record" > "$mrsamtmp/stale-injected"
    fi
}
''')
        marker = self.root / 'tmp/stale-injected'
        self.wait(lambda: marker.exists() and not Path(marker.read_text().strip()).exists())
        time.sleep(.3)
        self.assertEqual(self.launches(), [])
        self.stop()
        self.assertFalse(list((self.root / 'tmp').glob('session-*/alive')))

    def test_failed_commit_stops_after_one_launch(self):
        self.restart('''
sam_failed_commit(){ return 7; }
sam_bind commit sam_failed_commit
''')
        self.proc.wait(timeout=8)
        self.assertNotEqual(self.proc.returncode, 0)
        self.assertEqual(len(self.launches()), 1)
        self.assertIn('commit failed (status 7)', (self.root / 'output').read_text())
        self.assertFalse(list((self.root / 'tmp').glob('session-*/alive')))

    def test_playing_phase_failure_stops_after_one_launch(self):
        self.restart('''
sam_publish_phase(){ [[ "$1" != playing ]]; }
''')
        self.proc.wait(timeout=8)
        self.assertNotEqual(self.proc.returncode, 0)
        self.assertEqual(len(self.launches()), 1)
        self.assertFalse(list((self.root / 'tmp').glob('session-*/alive')))

    def test_queued_pause_at_expiry_is_claimed_before_advancement(self):
        # Inject an already-expired deadline through Bash dynamic scope.
        # The real control handler claims the prequeued request; no sleeps
        # or scheduler timing determine whether the boundary is reached.
        script = '''source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
sam_status_enabled=no
gametimer=1
sam_publish_phase(){ :; }
sam_service(){ :; }
sam_control_ack(){ printf '%s %s\\n' "$1" "$2" > "$TEST_LOG"; }
python3(){ printf '12345678-1234-1234-1234-123456789abc pause\\n'; }
mkdir -p "$sam_control_root"
printf '{}' > "$sam_control_root/pending.json"
boundary_ticks=0
sam_emit(){
    if [[ "$1" == countdown_start ]]; then
        end_time=$SECONDS
    elif [[ "$1" == countdown_tick ]]; then
        boundary_ticks=$((boundary_ticks+1))
        if ((boundary_ticks == 1)); then
            sam_control_tick
            [[ "$sam_paused" == 1 && "$sam_frozen" == 0 ]] || return 9
        else
            [[ "$sam_paused" == 1 ]] || return 9
            return 1
        fi
    fi
}
run_countdown_timer
[[ "$boundary_ticks" == 2 && $(<"$TEST_LOG") == '12345678-1234-1234-1234-123456789abc 200' ]]
'''
        self.stop()
        result = subprocess.run(['bash', '-c', script], env=self.env,
                                stdin=subprocess.DEVNULL, text=True,
                                capture_output=True, timeout=4)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_previous_replays_while_waiting_for_preparation(self):
        self.restart('''
launch_count=0
load_core(){
    launch_count=$((launch_count+1))
    printf '%s\\n' "$2" >> "$TEST_LOG"
    sam_emit display_launch "$3" "$2" "$1" ''
    if ((launch_count == 2)); then
        sam_cancel_preparation
        sam_schedule_preparation(){ :; }
        local record
        for record in "$sam_session/ready/"*.record; do
            [[ "$record" == "$sam_selected_record" ]] || rm -f "$record"
        done
    fi
}
''')
        self.wait(self.ready)
        first = self.launches()[0]
        self.key('n')
        self.wait(lambda: len(self.launches()) == 2)
        self.wait(self.ready)
        self.key('n')
        owner = self.root / 'tmp/session-owner'
        self.wait(lambda: owner.exists() and 'phase=preparing' in owner.read_text())
        self.key('p')
        self.wait(lambda: len(self.launches()) == 3)
        self.assertEqual(self.launches()[2], first)

    def test_populated_key_survives_timeout_without_double_backoff(self):
        self.stop()
        script = '''source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
sam_publish_phase(){ :; }
sam_emit(){ :; }
sam_service(){ :; }
sam_schedule_preparation(){ :; }
gametimer=0
read_count=0 sleep_count=0
sleep(){ sleep_count=$((sleep_count+1)); [[ "$1" == 0.1 ]]; }
read(){
    read_count=$((read_count+1))
    case "$read_count" in
        1) key=; return 142 ;; # Ordinary timeout already waited.
        2) key=; return 1 ;;   # Empty EOF requires exactly one backoff.
        3) key=p; return 142 ;; # Delivered byte must survive nonzero status.
        *) return 99 ;;
    esac
}
run_countdown_timer
[[ "$SAM_ACTION" == previous && "$read_count" == 3 && "$sleep_count" == 1 ]]
'''
        result = subprocess.run(['bash', '-c', script], env=self.env,
                                stdin=subprocess.DEVNULL, text=True,
                                capture_output=True, timeout=4)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_navigation_loading_burst_coalesces_last_intent(self):
        self.stop()
        script = '''source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
read(){
    [[ -n "$burst" ]] || { key=; return 142; }
    key=${burst:0:1}; burst=${burst:1}; return 0
}
burst=nnnnnnnnnnnnnnnn; SAM_ACTION=
sam_loading_keys
[[ "$SAM_ACTION" == next ]] || exit 1
burst=nnnP; SAM_ACTION=
sam_loading_keys
[[ "$SAM_ACTION" == previous ]] || exit 1
burst=pppN; SAM_ACTION=
sam_loading_keys
[[ "$SAM_ACTION" == next ]]
'''
        result = subprocess.run(['bash', '-c', script], env=self.env,
                                text=True, capture_output=True, timeout=4)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_previous_received_during_loading_replays_once(self):
        self.restart('''
launch_count=0
load_core(){
    launch_count=$((launch_count+1))
    printf '%s\\n' "$2" >> "$TEST_LOG"
    sam_emit display_launch "$3" "$2" "$1" ''
    if ((launch_count == 2)); then
        printf loading > "$mrsamtmp/second-loading"
        while [[ ! -e "$mrsamtmp/release-loading" ]]; do sleep .01; done
    fi
}
''')
        self.wait(self.ready)
        first = self.launches()[0]
        self.key('n')
        self.wait(lambda: (self.root / 'tmp/second-loading').exists())
        self.key('p' * 20)
        (self.root / 'tmp/release-loading').touch()
        self.wait(lambda: len(self.launches()) == 3)
        self.wait(self.ready)
        self.assertEqual(self.launches()[2], first)
        time.sleep(.3)
        self.assertEqual(len(self.launches()), 3)


if __name__ == '__main__':
    unittest.main(verbosity=2)
