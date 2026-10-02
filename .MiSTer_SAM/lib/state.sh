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
    local file="$1" key value var temp="$1.tmp.$BASHPID"
    [[ "$3" != *$'\n'* && "$3" != *$'\r'* ]] || return 1
    {
        printf 'core=%s\npath=%s\nname=%s\nsetname=%s\n' "$2" "$3" "$4" "$5"
        printf 'generation=%s\nowner=%s\nrevision=%s\namigapath=%s\ncover=%s\n' \
            "$sam_generation" "$sam_owner" "$6" "${amigapath:-}" "${sam_candidate_cover:-}"
        printf 'amigacore=%s\n' "${amigacore:-}"
        printf 'reset=%s\npolicy=%s\n' "${sam_candidate_reset:-no}" "${sam_candidate_policy:-}"
    } > "$temp" && mv -f -- "$temp" "$file"
}

sam_pid_start() { # PID; returns fields via variables, including zombie state
    local line fields
    [[ "$1" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ -r "/proc/$1/stat" ]] || return 1
    { read -r line < "/proc/$1/stat"; } 2>/dev/null || return 1
    read -ra fields <<< "${line##*) }"
    sam_proc_state="${fields[0]}" sam_proc_start="${fields[19]}" sam_proc_ppid="${fields[1]}"
    [[ "$sam_proc_state" != Z && "$sam_proc_state" != X && "$sam_proc_state" != x && "$sam_proc_start" =~ ^[0-9]+$ ]]
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

# MCP observes lifecycle independently of optional Monitor/artwork modules.
# Publish only at transitions, never per countdown tick.
sam_publish_phase() {
    [[ -n "${sam_owner:-}" ]] || return 0
    [[ "$1" != "${sam_last_phase:-}" || "$1" == loading ]] || return 0
    local line current_pid= current_start=
    if [[ -n "${sam_last_phase:-}" && -r "$mrsamtmp/session-owner" ]]; then
        while IFS= read -r line; do
            case "$line" in pid=*) current_pid="${line#*=}" ;; start=*) current_start="${line#*=}" ;; esac
        done < "$mrsamtmp/session-owner"
        [[ "$current_pid:$current_start" == "$sam_owner" ]] || return 1
    fi
    sam_last_phase=$1
    local temp="$mrsamtmp/session-owner.tmp.$BASHPID"
    if [[ "$1" == loading ]]; then sam_launch_serial=$(( ${sam_launch_serial:-0} + 1 )); fi
    printf 'pid=%s\nstart=%s\nphase=%s\nlaunch=%s\n' \
        "$$" "${sam_owner#*:}" "$1" "${sam_launch_serial:-0}" > "$temp" &&
        mv -f "$temp" "$mrsamtmp/session-owner"
}
