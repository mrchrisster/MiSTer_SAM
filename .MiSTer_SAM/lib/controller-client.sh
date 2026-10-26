# SPDX-License-Identifier: GPL-3.0-or-later
# Literal RAM requests to an already running MCP host. Never evaluate records.
# 125 means no request was published and the existing caller may fall back.
sam_controller_pid_start() {
    local line fields=()
    sam_controller_ticks=
    [[ "$1" =~ ^[1-9][0-9]*$ ]] || return 1
    { IFS= read -r line < "/proc/$1/stat"; } 2>/dev/null || return 1
    read -ra fields <<< "${line##*) }"
    [[ "${fields[0]:-}" != Z && "${fields[0]:-}" != X && "${fields[19]:-}" =~ ^[0-9]+$ ]] || return 1
    sam_controller_ticks=${fields[19]}
}

sam_controller_read() {
    local path=$1 line key value count=0 size=0
    declare -gA sam_controller_record=()
    [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        count=$((count+1))
        size=$((size+${#line}+1))
        ((count <= 64 && ${#line} <= 8256 && size <= 16384)) || return 1
        [[ "$line" == *=* ]] || return 1
        key=${line%%=*} value=${line#*=}
        [[ "$key" =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ && -z "${sam_controller_record[$key]+x}" ]] || return 1
        sam_controller_record[$key]=$value
    done < "$path"
}

sam_controller_host_valid() {
    local pid=$1 ticks=$2 mcp=$3 arg found=0 argv=()
    sam_controller_pid_start "$pid" && [[ "$sam_controller_ticks" == "$ticks" ]] || return 1
    { mapfile -d '' -t argv < "/proc/$pid/cmdline"; } 2>/dev/null || return 1
    [[ "${argv[0]##*/}" == python* ]] || return 1
    for arg in "${argv[@]}"; do [[ "$arg" != "$mcp" ]] || found=1; done
    ((found))
}

sam_controller_probe() {
    local root=$1 endpoint=$2
    sam_controller_host_pid= sam_controller_host_start= sam_controller_host_mcp= sam_controller_menu_leases=0
    sam_controller_read "$endpoint" || return 1
    [[ "${sam_controller_record[version]-}" == 1 && "${sam_controller_record[root]-}" == "$root" ]] || return 1
    [[ "${sam_controller_record[mcp]-}" == "$root/MiSTer_SAM_MCP.py" ]] || return 1
    sam_controller_host_valid "${sam_controller_record[pid]-}" "${sam_controller_record[start]-}" "${sam_controller_record[mcp]-}" || return 1
    sam_controller_host_pid=${sam_controller_record[pid]}
    sam_controller_host_start=${sam_controller_record[start]}
    sam_controller_host_mcp=${sam_controller_record[mcp]}
    sam_controller_menu_leases=${sam_controller_record[menu_leases]-0}
}

sam_controller_menu_available() {
    [[ "${SAM_ENGINE:-python}" != legacy ]] || return 1
    local root=${sam_root:-${SAM_ROOT:-/media/fat/Scripts/.MiSTer_SAM}} runtime=${SAM_TMP_ROOT:-/tmp/.SAM_tmp}
    sam_controller_probe "$root" "$runtime/command-host/endpoint" && [[ "$sam_controller_menu_leases" == 1 ]]
}

sam_controller_bootstrap_allowed() {
    [[ "$1" == /media/fat/Scripts/.MiSTer_SAM && "$2" == /tmp/.SAM_tmp ]]
}

sam_controller_try() {
    local action=${1,,} root=${sam_root:-${SAM_ROOT:-/media/fat/Scripts/.MiSTer_SAM}}
    local runtime=${SAM_TMP_ROOT:-/tmp/.SAM_tmp} target= if_idle=0 duration=180
    local endpoint host_pid host_start host_mcp owner_pid=0 owner_start=0 launch=0 caller_start caller_pid=$BASHPID
    local pending_id= pending_epoch=0 bound=0
    local id request temporary receipt key value deadline state message error rc=1
    shift
    [[ "${SAM_ENGINE:-python}" != legacy ]] || return 125
    case "$action" in
        start|restart)
            if [[ "${1:-}" == --if-idle ]]; then if_idle=1; shift; fi
            (($# <= 1)) || return 125
            target=${1:-}
            [[ ${#target} -le 64 && "$target" != *$'\n'* && "$target" != *$'\r'* ]] || return 125
            target=${target,,}
            target=${target#"${target%%[![:space:]]*}"}
            target=${target%"${target##*[![:space:]]}"}
            [[ -z "$target" || "$target" =~ ^[a-z0-9_]{1,32}$ ]] || return 125
            ;;
        next|previous|mute|m82_play|pause|resume|play|ignore)
            if (($# == 2)) && [[ "$1:$2" =~ ^[0-9]+:[0-9]+$ ]]; then
                owner_pid=$1 owner_start=$2 bound=1
            elif (($# != 0)); then return 125; fi ;;
        stop|kill|exit_to_menu|exit_to_game)
            if (($# == 2)); then owner_pid=$1 owner_start=$2 bound=1
            elif (($# != 0)); then return 125; fi ;;
        menu_hold) (($# == 0)) || return 125 ;;
        menu_release)
            (($# == 1)) || return 125
            target=$1
            [[ ${#target} -le 8192 && "$target" =~ ^[A-Za-z0-9_=-]+$ ]] || return 125
            [[ "$target" != - ]] || return 0
            ;;
        *) return 125 ;;
    esac
    endpoint="$runtime/command-host/endpoint"
    if ! sam_controller_probe "$root" "$endpoint"; then
        if [[ "$action" != start && "$action" != restart ]] || ! sam_controller_bootstrap_allowed "$root" "$runtime"; then return 125; fi
        # Cold admission loads only the MCP lifecycle helper, not SAM's runtime
        # configuration, catalog tables or optional session modules. A stale
        # dead-host endpoint is never unlinked or treated as a live host.
        local mrsampath=$root
        source "$root/lib/monitor.sh" || return 125
        mcp_start || return 125
        deadline=$((SECONDS+15))
        while ! sam_controller_probe "$root" "$endpoint"; do
            ((SECONDS < deadline)) || return 125
            sleep .05
        done
    fi
    if [[ "$action" == menu_hold || "$action" == menu_release ]]; then
        [[ "$sam_controller_menu_leases" == 1 ]] || return 125
    fi
    [[ -d "$runtime/command-host" && ! -L "$runtime/command-host" &&
       -d "$runtime/command-host/requests" && ! -L "$runtime/command-host/requests" &&
       -d "$runtime/command-host/receipts" && ! -L "$runtime/command-host/receipts" ]] || return 125
    host_pid=$sam_controller_host_pid host_start=$sam_controller_host_start host_mcp=$sam_controller_host_mcp
    if [[ "$action" == start || "$action" == restart ]]; then
        sam_controller_read "$runtime/command-host/generation" || return 125
        [[ "${sam_controller_record[host_pid]-}:${sam_controller_record[host_start]-}" == "$host_pid:$host_start" ]] || return 125
        pending_epoch=${sam_controller_record[epoch]-}
        [[ "$pending_epoch" =~ ^[0-9]+$ ]] || return 125
    fi
    if [[ "$action" != start && "$action" != restart ]]; then
        if [[ "$owner_pid:$owner_start" == 0:0 ]]; then
            if sam_controller_read "$runtime/session-owner"; then
                owner_pid=${sam_controller_record[pid]-} owner_start=${sam_controller_record[start]-}
                launch=${sam_controller_record[launch]-0}
            elif [[ "$action" == menu_hold || "$action" == menu_release ]]; then
                : # An inactive menu needs no pause/resume lease.
            elif [[ "$action" == stop || "$action" == kill || "$action" == exit_to_menu ]]; then
                sam_controller_read "$runtime/command-host/pending" || return 125
                [[ "${sam_controller_record[host_pid]-}:${sam_controller_record[host_start]-}" == "$host_pid:$host_start" ]] || return 1
                pending_id=${sam_controller_record[id]-} pending_epoch=${sam_controller_record[epoch]-}
                [[ "$pending_id" =~ ^[0-9a-f]{32}$ && "$pending_epoch" =~ ^[0-9]+$ ]] || return 1
            else return 125; fi
        else
            sam_controller_read "$runtime/session-owner" || return 1
            [[ "${sam_controller_record[pid]-}:${sam_controller_record[start]-}" == "$owner_pid:$owner_start" ]] || return 1
            launch=${sam_controller_record[launch]-0}
        fi
        if [[ "$owner_pid" != 0 ]]; then
            if ! sam_controller_pid_start "$owner_pid" || [[ "$sam_controller_ticks" != "$owner_start" ]]; then
                if [[ "$action" == menu_hold || "$action" == menu_release ]]; then
                    owner_pid=0 owner_start=0 launch=0
                else
                    ((bound == 0)) || return 1
                    return 125
                fi
            fi
        fi
    fi
    [[ "$owner_pid" =~ ^[0-9]+$ && "$owner_start" =~ ^[0-9]+$ && "$launch" =~ ^[0-9]+$ ]] || return 125
    duration=${SAM_START_FEEDBACK_TIMEOUT:-180}
    [[ "$duration" =~ ^[0-9]{1,3}$ ]] && ((10#$duration <= 480)) || return 125
    duration=$((10#$duration))
    [[ "$action" == start || "$action" == restart ]] || duration=0
    sam_controller_pid_start "$caller_pid" || return 125
    caller_start=$sam_controller_ticks
    local -a env_keys=(SAM_INI SAM_LIST_ROOT SAM_SESSION_LIST_ROOT SAM_EXIT_TRACE SAM_ENTRY
        SAM_START_FROM_UI SAM_START_FEEDBACK_TIMEOUT SAM_CONFIG_ROOT SAM_MISTER_ROOT SAM_STATE_FILE SAM_GAME_LOG)
    [[ "$action" != menu_hold && "$action" != menu_release ]] || env_keys=()
    for key in "${env_keys[@]}"; do
        [[ -n "${!key+x}" ]] || continue
        value=${!key}
        [[ ${#value} -le 2048 && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 125
    done
    printf -v id '%08x%08x%08x%08x' "$BASHPID" "$RANDOM" "$RANDOM" "$RANDOM"
    request="$runtime/command-host/requests/req-$id"
    temporary="$request.tmp.$BASHPID"
    receipt="$runtime/command-host/receipts/ack-$id"
    [[ ! -e "$temporary" && ! -L "$temporary" && ! -e "$request" && ! -L "$request" ]] || return 125
    (
        umask 077
        set -o noclobber
        {
            printf 'version=1\nid=%s\naction=%s\ntarget=%s\nif_idle=%s\n' "$id" "$action" "$target" "$if_idle"
            printf 'owner_pid=%s\nowner_start=%s\nlaunch=%s\n' "$owner_pid" "$owner_start" "$launch"
            printf 'pending_id=%s\npending_epoch=%s\n' "$pending_id" "$pending_epoch"
            printf 'host_pid=%s\nhost_start=%s\nclient_pid=%s\nclient_start=%s\nexpires=%s\n' \
                "$host_pid" "$host_start" "$caller_pid" "$caller_start" "$((EPOCHSECONDS+duration+120))"
            for key in "${env_keys[@]}"; do
                [[ -z "${!key+x}" ]] || printf 'env_%s=%s\n' "$key" "${!key}"
            done
        } > "$temporary"
    ) || return 125
    mv -f -- "$temporary" "$request" || { rm -f -- "$temporary"; return 125; }
    # From this point a timeout/failure is a result, never permission to submit
    # the same action through the legacy launcher or another session owner.
    if sam_controller_pid_start "$host_pid" && [[ "$sam_controller_ticks" == "$host_start" ]]; then
        kill -s USR2 "$host_pid" 2>/dev/null || true
    fi
    deadline=$((SECONDS+duration+120))
    if [[ "$action" != start && "$action" != restart ]]; then deadline=$((SECONDS+30)); fi
    while ((SECONDS < deadline)); do
        if sam_controller_read "$receipt" && [[ "${sam_controller_record[id]-}" == "$id" &&
            "${sam_controller_record[host_pid]-}:${sam_controller_record[host_start]-}" == "$host_pid:$host_start" ]]; then
            state=${sam_controller_record[state]-}
            if [[ "$state" == applied || "$state" == failed ]]; then
                message=${sam_controller_record[message]-} error=${sam_controller_record[error]-}
                if [[ "$state" == applied && "${sam_controller_record[ok]-}" == 1 ]]; then
                    if [[ "$action" == menu_hold ]]; then
                        value=${sam_controller_record[token]-}
                        [[ ${#value} -le 8192 && "$value" =~ ^[A-Za-z0-9_=-]+$ ]] || {
                            rm -f -- "$receipt" "$request"; return 1;
                        }
                        printf '%s\n' "$value"
                    elif [[ "$action" != menu_release && -n "$message" ]]; then printf '%s\n' "$message"; fi
                    rc=0
                else
                    printf 'SAM: %s\n' "${error:-Command failed}" >&2
                fi
                rm -f -- "$receipt" "$request"
                return "$rc"
            fi
        fi
        sam_controller_pid_start "$host_pid" && [[ "$sam_controller_ticks" == "$host_start" && -f "$endpoint" ]] || break
        sleep .05
    done
    rm -f -- "$request" "$receipt"
    echo 'SAM: controller completion was not received; check m monitor or diagnostics.' >&2
    return 1
}
