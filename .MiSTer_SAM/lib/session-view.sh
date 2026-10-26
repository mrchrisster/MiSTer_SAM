#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# A tmux viewer is disposable; the platform child owns the actual session.
sam_view_owner_valid() { # root runtime pid start
    local root=$1 runtime=$2 pid=$3 ticks=$4 controller controller_start
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$ticks" =~ ^[0-9]+$ ]] || return 1
    sam_controller_read "$runtime/session-owner" || return 1
    [[ "${sam_controller_record[pid]-}:${sam_controller_record[start]-}" == "$pid:$ticks" ]] || return 1
    sam_controller_pid_start "$pid" && [[ "$sam_controller_ticks" == "$ticks" ]] || return 1
    sam_controller_read "$runtime/hosted-controller" || return 1
    [[ "${sam_controller_record[owner_pid]-}:${sam_controller_record[owner_start]-}" == "$pid:$ticks" &&
       "${sam_controller_record[log]-}" == "$runtime/command-host/session.log" ]] || return 1
    controller=${sam_controller_record[controller_pid]-}
    controller_start=${sam_controller_record[controller_start]-}
    sam_controller_host_valid "$controller" "$controller_start" "$root/MiSTer_SAM_MCP.py" || return 1
    sam_controller_read "$runtime/session-owner" || return 1
    [[ "${sam_controller_record[pid]-}:${sam_controller_record[start]-}" == "$pid:$ticks" ]]
}

sam_view_main() {
    (($# == 4)) || return 64
    local root=$1 runtime=$2 pid=$3 ticks=$4 key action tail_pid= tail_start= line fields=()
    sam_root=$root
    export SAM_TMP_ROOT=$runtime
    source "$root/lib/controller-client.sh" || return 1
    sam_view_owner_valid "$root" "$runtime" "$pid" "$ticks" || { echo 'SAM viewer: session ended or changed.'; return 1; }
    # A RAM-backed viewer must not add the default one-second polling lag.
    # This process exists only while a monitor pane is open.
    tail -n 60 -f -s 0.1 "$runtime/command-host/session.log" &
    tail_pid=$!
    sam_controller_pid_start "$tail_pid" && tail_start=$sam_controller_ticks
    sam_view_cleanup() {
        if [[ -n "$tail_start" ]] && sam_controller_pid_start "$tail_pid" && [[ "$sam_controller_ticks" == "$tail_start" ]]; then
            IFS= read -r line < "/proc/$tail_pid/stat" || return
            read -ra fields <<< "${line##*) }"
            [[ "${fields[1]}" != "$$" ]] || kill -TERM "$tail_pid" 2>/dev/null
        fi
        wait "$tail_pid" 2>/dev/null || true
    }
    trap sam_view_cleanup EXIT
    trap 'sam_view_cleanup; trap - EXIT; exit 0' TERM HUP
    while sam_view_owner_valid "$root" "$runtime" "$pid" "$ticks"; do
        if read -r -s -t 0.25 -n 1 key; then
            case "$key" in
                n|N) action=next ;;
                p|P) action=previous ;;
                m|M) action=mute ;;
                *) continue ;;
            esac
            # Never let this old view recapture a newly started session.
            sam_controller_try "$action" "$pid" "$ticks" || echo 'SAM viewer: command refused; session/loading state changed.'
        elif [[ ! -t 0 ]]; then break; fi
    done
    echo 'SAM viewer: session ended.'
    sam_view_cleanup
    trap - EXIT TERM HUP
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then sam_view_main "$@"; fi
