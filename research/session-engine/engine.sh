#!/usr/bin/env bash
# Isolated RESEARCH mock. No production library, hardware path, or physical input.
set -u
umask 077
SCRIPT_DIR=${BASH_SOURCE[0]%/*}
[[ "$SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR=.
root=${TMP_ROOT:?Set TMP_ROOT to a private /tmp/sam-session-research-* fixture}
[[ "$root" =~ ^/tmp/sam-session-research-[A-Za-z0-9_-]+$ && ! -L "$root" &&
   -f "$root/RESEARCH_MOCK_ONLY" && $(<"$root/RESEARCH_MOCK_ONLY") == SAM_SESSION_RESEARCH_V1 ]] || exit 64
mode=${1:-normal}; prep_delay=${2:-3}; launch_delay=${3:-0}
case "$mode" in normal|m82|commercial) ;; *) exit 64 ;; esac
for delay in "$prep_delay" "$launch_delay"; do
    [[ "$delay" =~ ^([0-9]|[12][0-9]|30)(\.[0-9]{1,3})?$ ]] || exit 64
    [[ "$delay" != 30.* || "$delay" =~ ^30\.0{1,3}$ ]] || exit 64
done
source "$SCRIPT_DIR/worker.sh"
shopt -s nullglob

pid_identity() {
    local line; local -a fields
    [[ "$1" =~ ^[1-9][0-9]*$ && -r /proc/$1/stat ]] || return 1
    { IFS= read -r line < "/proc/$1/stat"; } 2>/dev/null || return 1
    read -ra fields <<< "${line##*) }"
    proc_ticks=${fields[19]:-}; proc_group=${fields[2]:-}; proc_sid=${fields[3]:-}; proc_state=${fields[0]:-Z}
    [[ ${fields[0]:-Z} != Z && ${fields[0]:-X} != X && "$proc_ticks" =~ ^[0-9]+$ ]]
}
# Validate fixed declarative policy before admitting/publishing an owner.
demo_timer=0; play_timer=0; ui_policy=continue; allowed_cores=; valid_items=0
declare -A mode_context=() dispatch_plan=() closed_leases=()
while IFS=$'\t' read -r tag key value item_title; do
    if [[ "$tag" == item ]]; then
        if [[ "$key" == game || "$key" == bios || "$key" == clip ]] && [[ ",$allowed_cores," == *",$value,"* && "$item_title" =~ ^Fixture_[A-Za-z0-9_]+$ ]]; then ((valid_items+=1)); fi
        continue
    fi
    [[ "$tag" == policy ]] || continue
    case "$key" in
        cores) allowed_cores=$value ;;
        demo_timer) demo_timer=$value ;;
        play_timer) play_timer=$value ;;
        input_transition|input_demo|input_play)
            case "$value" in ignore|stop|play|advance) mode_context[$key]=$value ;; *) exit 64 ;; esac ;;
        ui) case "$value" in pause|continue) ui_policy=$value ;; *) exit 64 ;; esac ;;
    esac
done < "$SCRIPT_DIR/modes/$mode.tsv"
for key in input_transition input_demo input_play; do [[ -n ${mode_context[$key]:-} ]] || exit 64; done
[[ "$demo_timer" =~ ^[0-9]{1,6}$ && "$play_timer" =~ ^[0-9]{1,6}$ ]] || exit 64
if [[ -n ${PLAY_SECONDS:-} ]]; then
    [[ "$PLAY_SECONDS" =~ ^[0-9]{1,6}$ ]] || exit 64
    play_timer=$((10#$PLAY_SECONDS))
fi
pid_identity "$BASHPID" || exit 69
owner=$BASHPID; owner_ticks=$proc_ticks; owner_sid=$proc_sid
token="$owner-$owner_ticks-$RANDOM-$RANDOM"
# mkdir is the sole owner admission lock; a live or abandoned fixture is never stolen.
mkdir "$root/engine.lock" 2>/dev/null || exit 75
mkdir -p "$root/inbox" "$root/ready" "$root/receipts" || exit 74
[[ ! -e "$root/clock.fifo" ]] || { rmdir "$root/engine.lock"; exit 75; }
mkfifo "$root/clock.fifo" || exit 74
exec {clock_fd}<> "$root/clock.fifo"
printf '%s\t%s\t%s\t0\n' "$owner" "$owner_ticks" "$token" > "$root/owner"
: > "$root/events.tsv"

epoch=0; active=0; phase=standby; selection=-; ready_count=0; current_kind=-
ui_open=0; ui_lease=-; ui_pid=0; ui_ticks=0; paused=0; pause_pending=-
worker_pid=0; worker_start=0; worker_group=0; worker_sid=0
launch_pid=0; launch_start=0; launch_group=0; launch_sid=0
launch_expected_epoch=0; launch_expected_selection=-
input_role=ignore
next_pending=0; running=1; dirty=1; stop_turn=0; cleanup_blocked=0
declare -a next_ids=() cleanup_pids=() closed_lease_order=() claimed_files=()
# Named literal context/plan arrays: only the owner can turn a candidate into a plan.

event() { printf '%s\t%s\t%s\t%s\t%s\n' "${EPOCHREALTIME:-$SECONDS}" "$1" "$epoch" "$selection" "${2:--}" >> "$root/events.tsv"; }
receipt() { printf '%s\t%s\t%s\n' "${EPOCHREALTIME:-$SECONDS}" "$3" "$4" > "$root/receipts/$1.$2"; }
owner_write() { printf '%s\t%s\t%s\t%s\n' "$owner" "$owner_ticks" "$token" "$epoch" > "$root/.owner.tmp"; mv -f "$root/.owner.tmp" "$root/owner"; }
state_write() {
    {
        printf 'engine_pid\t%s\nengine_start\t%s\nsession_token\t%s\nsession_epoch\t%s\n' "$owner" "$owner_ticks" "$token" "$epoch"
        printf 'mode\t%s\nactive\t%s\nphase\t%s\nselection\t%s\nready_count\t%s\n' "$mode" "$active" "$phase" "$selection" "$ready_count"
        printf 'ui_open\t%s\nui_lease\t%s\npaused\t%s\ninput_role\t%s\ndemo_timer\t%s\nplay_timer\t%s\n' "$ui_open" "$ui_lease" "$paused" "$input_role" "$demo_timer" "$play_timer"
        printf 'worker_pid\t%s\nworker_start\t%s\nlaunch_pid\t%s\nlaunch_start\t%s\n' "$worker_pid" "$worker_start" "$launch_pid" "$launch_start"
        printf 'cleanup_blocked\t%s\n' "$cleanup_blocked"
    } > "$root/.state.tmp"
    mv -f "$root/.state.tmp" "$root/state.tsv"
    dirty=0
}
job_spawn() { # fixed trusted function name and literal args; private process group
    local prefix=$1 pid attempt; shift
    set -m
    (set +m; trap - EXIT INT TERM; kill -STOP "$BASHPID"; "$@") < /dev/null &
    pid=$!
    set +m
    # Child inherits the FIFO description and uses only timed reads while delayed.
    for ((attempt=0;attempt<50;attempt++)); do
        if pid_identity "$pid" && [[ "$proc_group" == "$pid" && "$proc_sid" == "$owner_sid" && "$proc_state" == T ]]; then
            printf -v "${prefix}_pid" '%s' "$pid"
            printf -v "${prefix}_start" '%s' "$proc_ticks"
            printf -v "${prefix}_group" '%s' "$proc_group"
            printf -v "${prefix}_sid" '%s' "$proc_sid"
            kill -CONT "$pid"
            return
        fi
        IFS= read -r -t .001 -u "$clock_fd" unused || true
    done
    if pid_identity "$pid" && [[ "$proc_group" == "$pid" && "$proc_sid" == "$owner_sid" ]]; then kill -KILL -- "-$pid" 2>/dev/null || true; fi
    event job_registration_failed "$prefix"
    return 1
}
job_cancel() { # prefix comes only from fixed worker/launch call sites
    local prefix=$1 pid_var="${1}_pid" ticks_var="${1}_start" group_var="${1}_group" sid_var="${1}_sid"
    local pid=${!pid_var} ticks=${!ticks_var} group=${!group_var} sid=${!sid_var}
    if ((pid > 0)) && pid_identity "$pid"; then
        if [[ "$proc_ticks" != "$ticks" || "$proc_group" != "$group" || "$proc_sid" != "$sid" || "$group" != "$pid" ]]; then
            event cleanup_identity_rejected "$prefix"; return 1
        fi
        # Mock jobs contain no user callback or persistent subprocess. Kill cancels
        # builtin waits immediately; group scope also covers the brief atomic mv.
        if ! kill -KILL -- "-$group" 2>/dev/null; then event cleanup_signal_failed "$prefix"; return 1; fi
        cleanup_pids+=("$pid:$ticks")
        event cleanup_signaled "$prefix"
    elif ((pid > 0)); then
        # Only this fixed mock function can prove all synchronous children joined.
        # Missing/mismatched proof still requires the conservative group scan.
        local proof_epoch proof_token proof_selection proof_pid proof_ticks proof_group proof_sid proof_extra proven=0
        local proof_file="$root/launch.finished.$pid"
        if [[ "$prefix" == launch && -f "$proof_file" && ! -L "$proof_file" ]]; then
            IFS=$'\t' read -r -n 513 proof_epoch proof_token proof_selection proof_pid proof_ticks proof_group proof_sid proof_extra < "$proof_file" || true
            if [[ "$proof_epoch" == "$launch_expected_epoch" && "$proof_token" == "$token" &&
                  "$proof_selection" == "$launch_expected_selection" && "$proof_pid" == "$pid" &&
                  "$proof_ticks" == "$ticks" && "$proof_group" == "$group" && "$proof_sid" == "$sid" &&
                  -z "$proof_extra" ]]; then proven=1; fi
        fi
        # A dead leader is insufficient proof if anything still occupies its
        # former group. Refuse signals/admission until that ambiguity is gone.
        local stat_file stat_line; local -a stat_fields
        if ((proven == 0)); then
            for stat_file in /proc/[0-9]*/stat; do
                { IFS= read -r stat_line < "$stat_file"; } 2>/dev/null || continue
                read -ra stat_fields <<< "${stat_line##*) }"
                if [[ ${stat_fields[2]:-} == "$group" && ${stat_fields[3]:-} == "$sid" && ${stat_fields[0]:-Z} != Z ]]; then
                    event cleanup_identity_rejected "$prefix:dead_leader"; return 1
                fi
            done
        fi
    fi
    [[ "$prefix" != launch ]] || claimed_files+=("$root/launch.finished.$pid")
    printf -v "${prefix}_pid" '%s' 0
    printf -v "${prefix}_start" '%s' 0
}
stop_session() {
    local id
    ((epoch+=1)); printf '%s:%s\n' "$epoch" "$token" > "$root/session"
    next_pending=0; paused=0; pause_pending=-; input_role=ignore
    for id in "${next_ids[@]}"; do receipt "$id" applied rejected canceled_by_stop; done
    next_ids=()
    if ! job_cancel launch; then
        active=1; phase=stopping; cleanup_blocked=1; dirty=1
        event sim_menu_withheld unproven_dispatch_cleanup
        owner_write
        job_cancel worker || true
        return 1
    fi
    # Invalidated mock dispatch can no longer apply a completion. Menu intent
    # happens before slow preparation cleanup/reaping.
    active=0; phase=stopped; cleanup_blocked=0
    event sim_menu_intent "$1"
    owner_write
    if ! job_cancel worker; then cleanup_blocked=1; dirty=1; return 1; fi
    rm -f "$root"/ready/*.tsv "$root"/ready/.*.tmp "$root/launch.done"
    ready_count=0; dirty=1
}
owner_cleanup() {
    trap - EXIT INT TERM
    if ((active || worker_pid > 0 || launch_pid > 0)); then stop_session engine_exit || true; fi
    for entry in "${cleanup_pids[@]}"; do wait "${entry%%:*}" 2>/dev/null || true; done
    if [[ -r "$root/owner" && $(<"$root/owner") == "$owner"$'\t'"$owner_ticks"$'\t'"$token"$'\t'"$epoch" ]]; then rm -f "$root/owner"; fi
    rm -f "$root/clock.fifo" "$root"/launch.finished.* "$root"/.launch.finished.*.tmp "${claimed_files[@]}"
    rmdir "$root/engine.lock" 2>/dev/null || true
}
trap owner_cleanup EXIT
trap 'running=0' TERM INT

mock_dispatch() {
    local launch_epoch=$1 launch_token=$2 launch_selection=$3 line
    trap - EXIT
    IFS= read -r -t "$launch_delay" -u "$clock_fd" line || true
    [[ -f "$root/session" && $(<"$root/session") == "$launch_epoch:$launch_token" ]] || return
    printf '%s\t%s\t%s\n' "$launch_epoch" "$launch_token" "$launch_selection" > "$root/.launch.$launch_epoch.tmp"
    mv -f "$root/.launch.$launch_epoch.tmp" "$root/launch.done" || return
    wait || return
    if pid_identity "$BASHPID"; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$launch_epoch" "$launch_token" "$launch_selection" "$BASHPID" "$proc_ticks" "$proc_group" "$proc_sid" > "$root/.launch.finished.$BASHPID.tmp"
        mv -f "$root/.launch.finished.$BASHPID.tmp" "$root/launch.finished.$BASHPID"
    fi
}
DriverEngine() { # Named owner-built plan, never an arbitrary shell command.
    local -n plan=$1
    [[ ${plan[selection]} == "$selection" && ${plan[epoch]} == "$epoch" && ${plan[token]} == "$token" ]] || return 1
    job_cancel launch || return 1
    event mock_dispatch "${plan[kind]}:${plan[core]}:${plan[title]}"
    phase=dispatching; input_role=${mode_context[input_transition]}; dirty=1
    launch_expected_epoch=$epoch; launch_expected_selection=$selection
    job_spawn launch mock_dispatch "$epoch" "$token" "$selection"
}
prepare_start() {
    if ! job_cancel worker || ! job_cancel launch; then cleanup_blocked=1; dirty=1; return 1; fi
    cleanup_blocked=0
    if ((valid_items == 0)); then active=0; phase=failed; dirty=1; event preparation_failed empty_fixture; return 1; fi
    rm -f "$root"/ready/*.tsv "$root/launch.done" "$root/preparation.failed"
    ((epoch+=1)); printf '%s:%s\n' "$epoch" "$token" > "$root/session"; owner_write
    active=1; phase=preparing; selection=-; current_kind=-; input_role=${mode_context[input_transition]}
    next_pending=1; ready_count=0; dirty=1
    ((ui_open == 0)) || pause_pending=$ui_lease
    event session_started "$mode"
    job_spawn worker research_worker "$root" "$epoch" "$token" "$prep_delay" "$mode"
}
launch_next() {
    local file ce ct index cs kind core title extra best_file= best_index=2147483647
    for file in "$root"/ready/*.tsv; do
        if [[ ! -f "$file" || -L "$file" ]]; then rm -f "$file"; event candidate_path_rejected nonregular_or_symlink; continue; fi
        IFS=$'\t' read -r -n 513 ce ct index cs kind core title extra < "$file" || continue
        if [[ "$ce" != "$epoch" || "$ct" != "$token" || ! "$index" =~ ^[0-9]{1,8}$ ||
              "$cs" != "$ce:$index" || -n "$extra" ]]; then rm -f "$file"; continue; fi
        [[ ",$allowed_cores," == *",$core,"* && ${#title} -le 96 && "$title" =~ ^Fixture_[A-Za-z0-9_]+$ ]] || continue
        case "$kind" in game|bios|clip) ;; *) continue ;; esac
        ((index < best_index)) || continue
        best_index=$index; best_file=$file
        dispatch_plan=([epoch]="$ce" [token]="$ct" [selection]="$cs" [kind]="$kind" [core]="$core" [title]="$title")
    done
    [[ -n "$best_file" ]] || return
    rm -f "$best_file"
    selection=${dispatch_plan[selection]}; current_kind=${dispatch_plan[kind]}
    event first_ready "${dispatch_plan[kind]}:${dispatch_plan[core]}:${dispatch_plan[title]}"
    if DriverEngine dispatch_plan; then
        next_pending=0
        for id in "${next_ids[@]}"; do receipt "$id" applied ok "$selection"; done
        next_ids=()
    fi
}
mode_decision() { # explicit phase context, bounded builtin policy callback
    mode_context[phase]=$phase; mode_context[event]=$1
    decision=ignore
    if [[ "$1" == timer ]]; then
        [[ "$phase" != playing || "$play_timer" != 0 ]] || return
        decision=advance; return
    fi
    case "$phase" in
        preparing|dispatching) decision=${mode_context[input_transition]} ;;
        demonstration|commercial) decision=${mode_context[input_demo]} ;;
        playing) decision=${mode_context[input_play]} ;;
    esac
}
process_request() {
    local file=$1 line id rp rt tok expected_epoch action a b c extra extra_line old_lease has_extra=0 valid=1
    # Reject paths before opening: read timeout does not protect opening a FIFO.
    if [[ ! -f "$file" || -L "$file" ]]; then claimed_files+=("$file"); event request_path_rejected nonregular_or_symlink; return; fi
    {
        IFS= read -r -n 513 line || true
        if IFS= read -r -n 1 extra_line; then has_extra=1; fi
    } < "$file"
    claimed_files+=("$file")
    ((${#line} <= 512)) || return
    IFS=$'\t' read -r id rp rt tok expected_epoch action a b c extra <<< "$line"
    [[ "$id" =~ ^[A-Za-z0-9_-]{1,96}$ ]] || return
    if ((has_extra)); then receipt "$id" accepted rejected malformed_record; receipt "$id" applied rejected malformed_record; return; fi
    if [[ "$rp" != "$owner" || "$rt" != "$owner_ticks" || "$tok" != "$token" || -n "$extra" ]]; then
        receipt "$id" accepted rejected stale_owner; receipt "$id" applied rejected stale_owner; event command_rejected "$id:stale_owner"; return
    fi
    if [[ "$expected_epoch" != "$epoch" ]]; then receipt "$id" accepted rejected stale_epoch; receipt "$id" applied rejected stale_epoch; event command_rejected "$id:stale_epoch"; return; fi
    case "$action" in
        start|next|stop|status|shutdown|input|timer|menu-observed) [[ "$a:$b:$c" == -:-:- ]] || valid=0 ;;
        launch|ui-close) [[ "$a" =~ ^[A-Za-z0-9_.:-]{1,96}$ && "$b:$c" == -:- ]] || valid=0 ;;
        ui-open) [[ "$a" =~ ^[A-Za-z0-9_.:-]{1,96}$ && "$b" =~ ^[1-9][0-9]*$ && "$c" =~ ^[0-9]+$ ]] || valid=0 ;;
        *) receipt "$id" accepted rejected unknown_action; receipt "$id" applied rejected unknown_action; return ;;
    esac
    if ((valid == 0)); then receipt "$id" accepted rejected invalid_arguments; receipt "$id" applied rejected invalid_arguments; return; fi
    receipt "$id" accepted ok "$action"; event accepted "$id:$action"
    if ((cleanup_blocked)); then
        case "$action" in
            start|next|launch|input|timer) receipt "$id" applied rejected cleanup_unproven; return ;;
        esac
    fi
    if ((stop_turn)); then
        case "$action" in
            start|next|launch|input|timer) receipt "$id" applied rejected stop_priority; return ;;
        esac
    fi
    case "$action" in
        start)
            if ((active)); then receipt "$id" applied ok already_active
            elif prepare_start; then receipt "$id" applied ok preparing
            else receipt "$id" applied rejected preparation_or_cleanup_failed; fi ;;
        next)
            if ((active && ${#next_ids[@]} < 32)); then next_pending=1; next_ids+=("$id"); event next_coalesced "$id"
            elif ((active)); then receipt "$id" applied rejected pending_next_full
            else receipt "$id" applied rejected inactive; fi ;;
        stop|shutdown)
            stop_turn=1
            if stop_session "$action"; then receipt "$id" applied ok sim_menu_intent; [[ "$action" != shutdown ]] || running=0
            else receipt "$id" applied rejected cleanup_unproven; fi ;;
        menu-observed)
            stop_turn=1; event sim_menu_observed "$id"
            if stop_session external_menu; then receipt "$id" applied ok menu_observed
            else receipt "$id" applied rejected cleanup_unproven; fi ;;
        status) receipt "$id" applied ok "$phase" ;;
        launch)
            if ((active)) && [[ "$a" == "$selection" && "$phase" != dispatching ]]; then DriverEngine dispatch_plan; receipt "$id" applied ok dispatching
            else receipt "$id" applied rejected stale_selection; fi ;;
        input|timer)
            mode_decision "$action"; event "mock_$action" "$decision"
            case "$decision" in
                stop) if ! stop_session mock_input; then receipt "$id" applied rejected cleanup_unproven; return; fi ;;
                play) phase=playing; input_role=${mode_context[input_play]}; dirty=1; event play_entered "$play_timer" ;;
                advance) ((active == 0)) || next_pending=1 ;;
            esac
            receipt "$id" applied ok "$decision" ;;
        ui-open)
            if [[ ${closed_leases[$a]:-0} == 1 ]]; then
                receipt "$id" applied rejected closed_lease
            elif pid_identity "$b" && [[ "$proc_ticks" == "$c" ]]; then
                ui_open=1; ui_lease=$a; ui_pid=$b; ui_ticks=$c
                pause_pending=$a; paused=0; dirty=1; event ui_visible "$a"; receipt "$id" applied ok ui_visible
            else receipt "$id" applied rejected dead_ui_client; fi ;;
        ui-close)
            # Directory claim order is not arrival order. Remember a bounded set
            # of closed unique leases so a queued late open cannot strand pause.
            if [[ ${closed_leases[$a]:-0} != 1 ]]; then
                closed_leases[$a]=1; closed_lease_order+=("$a")
                if ((${#closed_lease_order[@]} > 32)); then
                    old_lease=${closed_lease_order[0]}; unset "closed_leases[$old_lease]"
                    closed_lease_order=("${closed_lease_order[@]:1}")
                fi
            fi
            if [[ "$a" == "$ui_lease" ]]; then ui_open=0; ui_lease=-; pause_pending=-; paused=0; dirty=1; event ui_closed "$a"; receipt "$id" applied ok closed
            else receipt "$id" applied rejected stale_lease; fi ;;
    esac
}

event engine_ready "$mode"
state_write
while ((running)); do
    # Standby has no job/result/state work. One mailbox glob plus one timed
    # builtin read keeps readiness without the ordinary active-session loop.
    if ((active == 0 && worker_pid == 0 && launch_pid == 0 && ui_open == 0 &&
          ${#cleanup_pids[@]} == 0 && dirty == 0)) && [[ "$pause_pending" == - ]]; then
        pending_files=("$root"/inbox/*.req)
        if ((${#pending_files[@]} == 0)); then IFS= read -r -t .05 -u "$clock_fd" unused || true; continue; fi
    fi
    # Apply the previous turn's pause lease before claims; a close claimed in this
    # turn cancels it again before launching. No expensive work enters this path.
    if [[ "$pause_pending" != - ]]; then
        if ((ui_open)) && [[ "$pause_pending" == "$ui_lease" && "$ui_policy" == pause ]]; then paused=1; event ui_pause_applied "$ui_lease"; fi
        pause_pending=-; dirty=1
    fi
    batch=0; stop_turn=0
    for file in "$root"/inbox/urgent.*.req; do process_request "$file"; ((batch+=1)); ((batch < 32 && running)) || break; done
    if ((running && batch < 32)); then
        for file in "$root"/inbox/control.*.req; do process_request "$file"; ((batch+=1)); ((batch < 32 && running)) || break; done
    fi
    if ((ui_open)) && { ! pid_identity "$ui_pid" || [[ "$proc_ticks" != "$ui_ticks" ]]; }; then
        event ui_client_gone "$ui_lease"; ui_open=0; ui_lease=-; paused=0; pause_pending=-; dirty=1
    fi
    if [[ -e "$root/launch.done" && ( ! -f "$root/launch.done" || -L "$root/launch.done" ) ]]; then
        rm -f "$root/launch.done"; event launch_result_rejected nonregular_or_symlink
    fi
    if [[ -f "$root/launch.done" ]]; then
        IFS=$'\t' read -r le lt ls extra < "$root/launch.done" || true
        rm -f "$root/launch.done"
        if ((active)) && [[ "$le" == "$epoch" && "$lt" == "$token" && "$ls" == "$selection" && -z "$extra" ]]; then
            case "$current_kind" in
                bios) phase=bios; input_role=ignore ;;
                clip) phase=commercial; input_role=${mode_context[input_demo]} ;;
                game) phase=demonstration; input_role=${mode_context[input_demo]} ;;
            esac
            event mock_launch_applied "$phase"; dirty=1
        else event launch_result_rejected stale_selection; fi
    fi
    if ((launch_pid > 0)) && ! pid_identity "$launch_pid"; then
        old_launch_pid=$launch_pid
        if job_cancel launch; then wait "$old_launch_pid" 2>/dev/null || true; dirty=1
        else cleanup_blocked=1; phase=stopping; active=1; dirty=1; fi
    fi
    if [[ -e "$root/preparation.failed" && ( ! -f "$root/preparation.failed" || -L "$root/preparation.failed" ) ]]; then
        rm -f "$root/preparation.failed"; event preparation_result_rejected nonregular_or_symlink
    fi
    if [[ -f "$root/preparation.failed" ]]; then
        IFS=$'\t' read -r pe pt reason < "$root/preparation.failed" || true
        rm -f "$root/preparation.failed"
        if ((active)) && [[ "$pe:$pt" == "$epoch:$token" ]]; then
            active=0; phase=failed; next_pending=0; dirty=1; event preparation_failed "$reason"
            for id in "${next_ids[@]}"; do receipt "$id" applied rejected preparation_failed; done
            next_ids=()
        fi
    fi
    if ((active && worker_pid > 0 && !cleanup_blocked)) && ! pid_identity "$worker_pid" && [[ "$phase" == preparing ]]; then
        files=("$root"/ready/*.tsv)
        if ((${#files[@]} == 0)); then
            active=0; phase=failed; next_pending=0; dirty=1; event preparation_failed worker_exited_without_candidate
            for id in "${next_ids[@]}"; do receipt "$id" applied rejected preparation_failed; done
            next_ids=()
        fi
    fi
    if ((active && next_pending && !paused)) && [[ "$phase" != dispatching ]]; then launch_next; fi
    files=("$root"/ready/*.tsv)
    if ((${#files[@]} != ready_count)); then ready_count=${#files[@]}; dirty=1; fi
    # Cleanup observation is async: only wait on an already-dead owned child.
    retained=()
    for entry in "${cleanup_pids[@]}"; do
        cp=${entry%%:*}; cs=${entry#*:}
        if pid_identity "$cp" && [[ "$proc_ticks" == "$cs" ]]; then retained+=("$entry")
        else wait "$cp" 2>/dev/null || true; event cleanup_reaped "$cp"; fi
    done
    cleanup_pids=("${retained[@]}")
    if ((${#claimed_files[@]} > 0)); then rm -f "${claimed_files[@]}"; claimed_files=(); fi
    ((dirty == 0)) || state_write
    IFS= read -r -t .05 -u "$clock_fd" unused || true
done
