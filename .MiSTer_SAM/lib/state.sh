# SPDX-License-Identifier: GPL-3.0-or-later
# Literal UTF-8 key=value records. Only known keys are accepted. No eval/source.
sam_record_read() {
    local file="$1" line key value
    sam_record_core= sam_record_path= sam_record_name= sam_record_setname=
    sam_record_generation= sam_record_owner= sam_record_revision= sam_record_amigapath= sam_record_amigacore= sam_record_cover= sam_record_reset= sam_record_policy=
    [[ -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}" value="${line#*=}"
        case "$key" in
            core|path|name|setname|generation|owner|revision|amigapath|amigacore|cover|reset|policy)
                printf -v "sam_record_$key" '%s' "$value" ;;
        esac
    done < "$file"
    [[ "$sam_record_core" =~ ^[a-z0-9_]+$ && -n "$sam_record_path" ]]
}

sam_record_write() { # file core path name setname revision
    local file="$1" key value var temp="$1.tmp.$BASHPID" locked=0 rc=0
    [[ "$3" != *$'\n'* && "$3" != *$'\r'* ]] || return 1
    if [[ "${sam_session_started:-0}" == 1 ]]; then
        sam_session_lock || return 1
        locked=1
        if [[ ! -e "$sam_session/alive" ]] || ! sam_session_is_current; then
            sam_session_unlock; return 1
        fi
    fi
    {
        printf 'core=%s\npath=%s\nname=%s\nsetname=%s\n' "$2" "$3" "$4" "$5"
        printf 'generation=%s\nowner=%s\nrevision=%s\namigapath=%s\ncover=%s\n' \
            "$sam_generation" "$sam_owner" "$6" "${amigapath:-}" "${sam_candidate_cover:-}"
        printf 'amigacore=%s\n' "${amigacore:-}"
        printf 'reset=%s\npolicy=%s\n' "${sam_candidate_reset:-no}" "${sam_candidate_policy:-}"
    } > "$temp" && mv -f -- "$temp" "$file" || rc=1
    ((locked == 0)) || sam_session_unlock
    ((rc == 0)) || rm -f -- "$temp"
    return "$rc"
}

sam_pid_start() { # PID; returns fields via variables, including zombie state
    local line fields IFS=$' \t\n'
    [[ "$1" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ -r "/proc/$1/stat" ]] || return 1
    { read -r line < "/proc/$1/stat"; } 2>/dev/null || return 1
    read -ra fields <<< "${line##*) }"
    sam_proc_state="${fields[0]}" sam_proc_start="${fields[19]}" sam_proc_ppid="${fields[1]}"
    sam_proc_group="${fields[2]}" sam_proc_session="${fields[3]}"
    [[ "$sam_proc_state" != Z && "$sam_proc_state" != X && "$sam_proc_state" != x && "$sam_proc_start" =~ ^[0-9]+$ ]]
}

# Private groups belong only to preparation/delayed-launch work, never the SAM
# owner, OLED or MCP. Children wait stopped until their identity is registered.
sam_job_spawn() { # sam_worker|sam_launch command [args...]
    local prefix=$1 saved_term saved_usr1 had_monitor=0 parent=$BASHPID parent_sid pid ticks= group= sid= registered=0 attempt
    shift
    [[ "$prefix" == sam_worker || "$prefix" == sam_launch ]] || return 1
    saved_term=$(trap -p TERM)
    local sam_job_stop_pending=0
    local sam_job_menu_stop_pending=0
    if [[ "${sam_engine_adapter_verified:-0}" == 1 ]]; then
        saved_usr1=$(trap -p USR1)
        trap 'sam_job_menu_stop_pending=1' USR1
    fi
    trap 'sam_job_stop_pending=1' TERM
    if ! sam_pid_start "$parent"; then
        [[ -z "$saved_term" ]] && trap - TERM || eval "$saved_term"
        if [[ "${sam_engine_adapter_verified:-0}" == 1 ]]; then
            [[ -z "$saved_usr1" ]] && trap - USR1 || eval "$saved_usr1"
        fi
        return 1
    fi
    parent_sid=$sam_proc_session
    [[ "$-" != *m* ]] || had_monitor=1
    set -m
    (
        set +m
        trap - EXIT INT
        trap 'exit 0' TERM
        # A fork can occur inside an owner's transition. Close, never unlock,
        # the inherited description so this job cannot retain the owner's flock.
        if [[ "${sam_session_lock_fd:-}" =~ ^[0-9]+$ ]]; then exec {sam_session_lock_fd}>&-; fi
        sam_session_lock_holder= sam_session_lock_depth=0
        kill -STOP "$BASHPID"
        local job_rc=0
        "$@" || job_rc=$?
        # Do not let a normally finishing shell abandon direct async helpers.
        wait || true
        exit "$job_rc"
    ) < /dev/null &
    pid=$!
    ((had_monitor)) || set +m
    printf -v "${prefix}_pid" '%s' "$pid"
    for ((attempt=0;attempt<20;attempt++)); do
        if sam_pid_start "$pid"; then
            ticks=$sam_proc_start group=$sam_proc_group sid=$sam_proc_session
            if [[ "$sam_proc_ppid" == "$parent" && "$group" == "$pid" && "$sid" == "$parent_sid" &&
                  ( "$sam_proc_state" == T || "$sam_proc_state" == t ) ]]; then registered=1; break; fi
        else break; fi
        sleep 0.01
    done
    printf -v "${prefix}_start" '%s' "$ticks"
    printf -v "${prefix}_group" '%s' "$group"
    printf -v "${prefix}_sid" '%s' "$sid"
    if ((registered)); then
        kill -CONT "$pid" || registered=0
    elif [[ -n "$ticks" ]] && sam_pid_start "$pid" && [[ "$sam_proc_start" == "$ticks" && "$sam_proc_ppid" == "$parent" ]]; then
        # The callback has not passed its STOP barrier; no descendants exist.
        kill -KILL "$pid" 2>/dev/null || true
    fi
    # saved_term comes only from Bash's own trap table, never a file/user record.
    [[ -z "$saved_term" ]] && trap - TERM || eval "$saved_term"
    if [[ "${sam_engine_adapter_verified:-0}" == 1 ]]; then
        [[ -z "$saved_usr1" ]] && trap - USR1 || eval "$saved_usr1"
        ((sam_job_menu_stop_pending == 0)) || kill -USR1 "$parent"
    fi
    if ((sam_job_stop_pending)); then kill -TERM "$parent"; fi
    ((registered)) || { echo 'SAM: owned job registration failed.' >&2; return 1; }
}

sam_job_group_members() { # group SID; fills caller-private indexes, skips completed tasks
    local stat line pid
    local -a fields
    sam_job_members=() sam_job_children=()
    for stat in /proc/[0-9]*/stat; do
        [[ -r "$stat" ]] || continue
        { IFS= read -r line < "$stat"; } 2>/dev/null || continue
        read -ra fields <<< "${line##*) }"
        [[ "${fields[2]}" == "$1" && "${fields[3]}" == "$2" ]] || continue
        sam_job_state_live "${fields[0]}" "${fields[17]}" || continue
        pid=${stat%/stat}; pid=${pid##*/}
        sam_job_members[$pid]=${fields[19]}
        sam_job_children[${fields[1]}]+=" $pid"
    done
}

sam_job_state_live() { # process leader state, number of retained threads
    case "$1" in
        Z) [[ "$2" =~ ^[0-9]+$ ]] && (( $2 > 1 )) ;;
        X|x) return 1 ;;
        *) return 0 ;;
    esac
}

sam_job_member_valid() { # job-specific liveness; owner zombie rules stay unchanged
    local pid=$1 line
    local -a fields
    [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/stat" ]] || return 1
    { IFS= read -r line < "/proc/$pid/stat"; } 2>/dev/null || return 1
    read -ra fields <<< "${line##*) }"
    [[ "${fields[19]}" == "${sam_job_members[$pid]-}" && "${fields[2]}" == "$sam_job_group" &&
       "${fields[3]}" == "$sam_job_sid" ]] || return 1
    # pthread_exit/SYS_exit can leave a zombie main thread while other threads
    # are alive or blocked in I/O. Such a process still owns memory/descriptors.
    sam_job_state_live "${fields[0]}" "${fields[17]}"
}

sam_job_signal_children() { # postorder, original group/start membership checked
    local pid=$1 child
    [[ -z "${sam_job_seen[$pid]-}" ]] || return 0
    sam_job_seen[$pid]=1
    for child in ${sam_job_children[$pid]-}; do sam_job_signal_children "$child"; done
    [[ "$pid" != "$sam_job_anchor" ]] || return 0
    if sam_job_member_valid "$pid"; then
        sam_job_anchor_valid || return 1
        kill -TERM "$pid" 2>/dev/null || true
        if sam_job_member_valid "$pid"; then
            sam_job_anchor_valid || return 1
            kill -CONT "$pid" 2>/dev/null || true
        fi
    fi
}

sam_job_anchor_valid() {
    sam_pid_start "$sam_job_anchor" && [[ "$sam_proc_start" == "$sam_job_ticks" &&
        "$sam_proc_group" == "$sam_job_group" && "$sam_proc_session" == "$sam_job_sid" &&
        ( "$sam_proc_state" == T || "$sam_proc_state" == t || "$sam_proc_state" == D ) ]]
}

sam_job_cancel() { # PID start private-group SID; zero only when nothing remains
    local sam_job_anchor=$1 sam_job_ticks=$2 sam_job_group=$3 sam_job_sid=$4
    local own_group pid attempt stopped=0 remaining=0
    local -A sam_job_members=() sam_job_children=() sam_job_seen=()
    sam_job_error=
    [[ "$sam_job_anchor" =~ ^[1-9][0-9]*$ && "$sam_job_group" == "$sam_job_anchor" &&
       "$sam_job_ticks" =~ ^[0-9]+$ && "$sam_job_sid" =~ ^[1-9][0-9]*$ &&
       "$sam_job_anchor" != "$$" && "$sam_job_anchor" != "$BASHPID" ]] || {
        sam_job_error='Private job identity is invalid'; return 1;
    }
    sam_pid_start "$BASHPID" || return 1
    own_group=$sam_proc_group
    [[ "$sam_job_group" != "$own_group" ]] || { sam_job_error='Job shares the caller group'; return 1; }
    if ! sam_pid_start "$sam_job_anchor" || [[ "$sam_proc_start" != "$sam_job_ticks" ]]; then
        # Completed/reaped job groups are normally already empty. An orphaned
        # group without its original leader cannot be adopted by numeric ID.
        kill -0 -- "-$sam_job_group" 2>/dev/null || return 0
        sam_job_group_members "$sam_job_group" "$sam_job_sid"
        ((${#sam_job_members[@]} == 0)) && return 0
        sam_job_error='Job leader disappeared; remaining group identity is unproven'; return 1
    fi
    [[ "$sam_proc_group" == "$sam_job_group" && "$sam_proc_session" == "$sam_job_sid" ]] || {
        sam_job_error='Job group identity changed'; return 1;
    }
    kill -STOP "$sam_job_anchor" 2>/dev/null || true
    for ((attempt=0;attempt<20;attempt++)); do
        if sam_job_anchor_valid && [[ "$sam_proc_state" == T || "$sam_proc_state" == t ]]; then stopped=1; break; fi
        sleep 0.01
    done
    sam_job_group_members "$sam_job_group" "$sam_job_sid"
    if ((stopped)); then
        # Leader remains frozen throughout grace, preventing PID/group reuse.
        sam_job_signal_children "$sam_job_anchor"
        for pid in "${!sam_job_members[@]}"; do sam_job_signal_children "$pid"; done
        for ((attempt=0;attempt<20;attempt++)); do
            remaining=0
            for pid in "${!sam_job_members[@]}"; do
                [[ "$pid" != "$sam_job_anchor" ]] || continue
                if sam_job_member_valid "$pid"; then remaining=1; break; fi
            done
            ((remaining)) || break
            sleep 0.01
        done
    fi
    # Group KILL includes the frozen leader and late forks/TERM-handler forks.
    # D-state leaders get a pending KILL; Linux cannot reclaim them before I/O.
    if sam_job_anchor_valid; then
        kill -KILL -- "-$sam_job_group" 2>/dev/null || true
    else
        sam_job_error='Job anchor disappeared during cancellation'; return 1
    fi
    for ((attempt=0;attempt<20;attempt++)); do
        remaining=0
        for pid in "${!sam_job_members[@]}"; do
            if sam_job_member_valid "$pid"; then remaining=1; break; fi
        done
        ((remaining)) || break
        sleep 0.01
    done
    # One final bounded scan includes children forked after initial discovery.
    sam_job_group_members "$sam_job_group" "$sam_job_sid"
    ((${#sam_job_members[@]} == 0)) && return 0
    sam_job_error='Owned job remains after KILL (possibly uninterruptible I/O)'
    return 1
}

sam_cleanup_failure_record() { # retain RAM evidence across owner EXIT
    local prefix=$1 reason=$2 temp="$mrsamtmp/cleanup-failure.tmp.$BASHPID" prior_owner= line
    if [[ -r "$mrsamtmp/cleanup-failure" ]]; then
        IFS= read -r prior_owner < "$mrsamtmp/cleanup-failure" || true
    fi
    local pidvar=${prefix}_pid ticksvar=${prefix}_start groupvar=${prefix}_group sidvar=${prefix}_sid
    {
        printf 'owner=%s\n' "${sam_owner:-}"
        if [[ "$prior_owner" == "owner=${sam_owner:-}" ]]; then
            while IFS= read -r line; do [[ "$line" == owner=* ]] || printf '%s\n' "$line"; done < "$mrsamtmp/cleanup-failure"
        fi
        printf 'job=%s:%s:%s:%s\nreason=%s\n' "${!pidvar}" "${!ticksvar}" "${!groupvar:-}" "${!sidvar:-}" "$reason"
    } > "$temp" && mv -f "$temp" "$mrsamtmp/cleanup-failure"
}

sam_cleanup_failure_pending() { # true only while evidence still blocks admission
    [[ -r "$mrsamtmp/cleanup-failure" ]] || return 1
    local line pid ticks group sid jobs=0
    local -A sam_job_members=() sam_job_children=()
    while IFS= read -r line; do
        [[ "$line" == job=* ]] || continue
        jobs=$((jobs+1)); IFS=: read -r pid ticks group sid <<< "${line#job=}"
        [[ "$pid" =~ ^[1-9][0-9]*$ && "$ticks" =~ ^[0-9]+$ ]] || return 0
        if sam_pid_start "$pid"; then
            [[ "$sam_proc_start" != "$ticks" ]] || return 0
            # A reused leader PID proves the old group no longer reserves it.
            continue
        fi
        if [[ "$group" =~ ^[1-9][0-9]*$ && "$sid" =~ ^[1-9][0-9]*$ ]]; then
            sam_job_group_members "$group" "$sid"
            ((${#sam_job_members[@]} == 0)) || return 0
        fi
    done < "$mrsamtmp/cleanup-failure"
    ((jobs > 0)) || return 0
    rm -f "$mrsamtmp/cleanup-failure"
    return 1
}

sam_kill_tree() { # an owned preparation process and descendants, never ps patterns
    local pid="$1" children child ticks stat line fields candidate
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$pid" != "$$" && "$pid" != "$BASHPID" ]] || return 1
    sam_pid_start "$pid" || return 0
    [[ -z "${2:-}" || "$sam_proc_start" == "$2" ]] || return 0
    ticks=$sam_proc_start
    if [[ -r "/proc/$pid/task/$pid/children" ]]; then
        read -r children < "/proc/$pid/task/$pid/children" || true
    else
        # MiSTer kernels may omit CONFIG_PROC_CHILDREN. Scan only on shutdown,
        # using builtin reads and correct /proc stat parsing, never ps patterns.
        for stat in /proc/[0-9]*/stat; do
            [[ -r "$stat" ]] || continue
            { IFS= read -r line < "$stat"; } 2>/dev/null || continue
            read -ra fields <<< "${line##*) }"
            [[ "${fields[1]}" == "$pid" ]] || continue
            candidate="${stat%/stat}"; candidate="${candidate##*/}"
            children+=" $candidate"
        done
    fi
    for child in $children; do
        sam_pid_start "$pid" && [[ "$sam_proc_start" == "$ticks" ]] || return 0
        sam_pid_start "$child" && [[ "$sam_proc_ppid" == "$pid" ]] || continue
        sam_kill_tree "$child" "$sam_proc_start"
    done
    sam_pid_start "$pid" && [[ "$sam_proc_start" == "$ticks" ]] || return 0
    kill -TERM "$pid" 2>/dev/null || true
}
