# SPDX-License-Identifier: GPL-3.0-or-later
# BGM is an external script. Never identify it by a substring in ps output:
# tmux, SAM and unrelated players may all mention that path in their arguments.
sam_bgm_script=${SAM_BGM_SCRIPT:-/media/fat/Scripts/bgm.sh}
sam_bgm_socket=${SAM_BGM_SOCKET:-/tmp/bgm.sock}
sam_bgm_proc=${SAM_BGM_PROC_ROOT:-/proc}
sam_bgm_owner_file=${SAM_BGM_OWNER_FILE:-${mrsamtmp:-/tmp/.SAM_tmp}/bgm-owner}

sam_bgm_pid_matches() {
    local pid=$1 exe arg index=0
    sam_bgm_record_matches "$pid" && return 0
    local -a argv=()
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    exe=$(readlink "$sam_bgm_proc/$pid/exe" 2>/dev/null) || return 1
    # Installed MiSTer BGM can be an ARM ELF executable despite its .sh name.
    # Exact executable identity is sufficient and must precede interpreter checks.
    [[ "$exe" == "$sam_bgm_script" ]] && return 0
    case "${exe##*/}" in bash|sh|dash|busybox|python|python[23]|python[23].[0-9]|python[23].[0-9][0-9]) ;; *) return 1;; esac
    while IFS= read -r -d '' arg; do argv+=( "$arg" ); done < "$sam_bgm_proc/$pid/cmdline" 2>/dev/null
    (( ${#argv[@]} >= 2 )) || return 1
    # BusyBox executable alone is not evidence of a shell invocation.
    if [[ "${exe##*/}" == busybox ]]; then
        case "${argv[0]##*/}" in sh|ash|bash) ;; *) return 1;; esac
    fi
    for ((index=1; index<${#argv[@]}; index++)); do
        arg=${argv[index]}
        case "$arg" in
            -c|--command|-*c*) return 1;;
            --) ((index+=1)); break;;
            -*) continue;;
            *) break;;
        esac
    done
    [[ "${argv[index]-}" == "$sam_bgm_script" ]]
}

sam_bgm_pids() {
    local entry pid emitted=0 mode=${1:-}
    if [[ -e "$sam_bgm_owner_file" ]]; then
        if sam_bgm_record_matches ""; then printf '%s\n' "$sam_bgm_owned_pid";emitted=1;fi
        if [[ "$sam_bgm_owned_wrapper" != "$sam_bgm_owned_pid" && "$sam_bgm_owned_wrapper" =~ ^[1-9][0-9]*$ ]] &&
           sam_bgm_process_start "$sam_bgm_owned_wrapper" && [[ "$sam_bgm_process_ticks" == "$sam_bgm_owned_wrapper_start" ]] &&
           sam_bgm_pid_matches "$sam_bgm_owned_wrapper"; then printf '%s\n' "$sam_bgm_owned_wrapper";emitted=1;fi
        [[ "$mode" != owned ]] || return 0
        ((emitted == 0)) || return 0
    fi
    for entry in "$sam_bgm_proc"/[0-9]*; do
        [[ -d "$entry" ]] || continue
        pid=${entry##*/}
        sam_bgm_pid_matches "$pid" && printf '%s\n' "$pid"
    done
    return 0
}

sam_bgm_socket_owned() { # kernel listener inode must belong to the captured PID
    local pid=$1 num refs protocol flags type state inode path socket_inode= object
    [[ -r "$sam_bgm_proc/net/unix" ]] || return 1
    while read -r num refs protocol flags type state inode path; do
        [[ "$path" != "$sam_bgm_socket" ]] || { socket_inode=$inode;break; }
    done < "$sam_bgm_proc/net/unix"
    [[ "$socket_inode" =~ ^[0-9]+$ ]] || return 1
    local objects
    objects=$(LC_ALL=C stat -Lc '%F:%i' "$sam_bgm_proc/$pid/fd/"* 2>/dev/null) || true
    while IFS= read -r object;do [[ "$object" != "socket:$socket_inode" ]] || return 0;done <<< "$objects"
    return 1
}

sam_bgm_query() { # supported readonly reply; never interpret it as shell code
    [[ -S "$sam_bgm_socket" ]] || return 1
    if [[ -e "$sam_bgm_owner_file" ]];then
        sam_bgm_record_matches "" || return 1
        [[ "$(stat -Lc '%d:%i|%z' "$sam_bgm_socket" 2>/dev/null)" == "$sam_bgm_owned_socket" ]] || return 1
        sam_bgm_socket_owned "$sam_bgm_owned_pid" || return 1
    fi
    printf '%s' "$1" | timeout -k 0.2s 3s socat -t 4 - "UNIX-CONNECT:$sam_bgm_socket" 2>/dev/null
}

sam_bgm_command() {
    [[ -S "$sam_bgm_socket" ]] || return 1
    if [[ -e "$sam_bgm_owner_file" ]]; then
        sam_bgm_record_matches "" || return 1
        [[ "$(stat -Lc '%d:%i|%z' "$sam_bgm_socket" 2>/dev/null)" == "$sam_bgm_owned_socket" ]] || return 1
        sam_bgm_socket_owned "$sam_bgm_owned_pid" || return 1
    fi
    printf '%s' "$1" | timeout -k 0.2s 3s socat -t 4 - "UNIX-CONNECT:$sam_bgm_socket" >/dev/null 2>&1
}

sam_bgm_policy() { # 0 applied, 3 legacy; all other failures block the audio barrier
    local mode=$1 owner=${sam_bgm_policy_owner:-${sam_exit_expected_owner:-${sam_owner:-}}}
    local helper=${SAM_BGM_CLIENT:-${mrsampath:-}/sam_bgm_client.py}
    [[ "$mode" != active ]] || owner=${sam_owner:-}
    [[ -r "$helper" ]] || return 3
    # Capability cache and revisions are bound to this exact captured service,
    # never to a socket pathname alone. Keep the same proof as legacy commands.
    sam_bgm_record_matches "" || return 3
    [[ "$(stat -Lc '%d:%i|%z' "$sam_bgm_socket" 2>/dev/null)" == "$sam_bgm_owned_socket" ]] || return 1
    sam_bgm_socket_owned "$sam_bgm_owned_pid" || return 1
    python3 "$helper" --socket "$sam_bgm_socket" --state "$sam_bgm_owner_file.policy" \
        --identity "$sam_bgm_owned_pid:$sam_bgm_owned_start:$sam_bgm_owned_socket" \
        --owner "$owner" --mode "$mode"
}

sam_bgm_process_start() { # verified live instance; bounded /proc data only
    local pid=$1 line
    local -a fields=()
    sam_bgm_process_ticks= sam_bgm_process_parent=
    [[ "$pid" =~ ^[1-9][0-9]*$ && -r "$sam_bgm_proc/$pid/stat" ]] || return 1
    { IFS= read -r line < "$sam_bgm_proc/$pid/stat"; } 2>/dev/null || return 1
    [[ "$line" == "$pid ("* && ${#line} -le 4096 ]] || return 1
    read -ra fields <<< "${line##*) }"
    [[ "${fields[0]}" != Z && "${fields[0]}" != X && "${fields[0]}" != x &&
       "${fields[19]:-}" =~ ^[0-9]+$ ]] || return 1
    sam_bgm_process_ticks=${fields[19]} sam_bgm_process_parent=${fields[1]}
}

sam_bgm_record_matches() { # optional expected PID; literal RAM record
    local expected=$1 line key value exe
    sam_bgm_owned_pid= sam_bgm_owned_start= sam_bgm_owned_exe= sam_bgm_owned_socket= sam_bgm_owned_wrapper= sam_bgm_owned_wrapper_start=
    [[ -f "$sam_bgm_owner_file" && -r "$sam_bgm_owner_file" ]] || return 1
    while IFS= read -r line; do
        key=${line%%=*} value=${line#*=}
        case "$key" in
            pid) [[ -z "$sam_bgm_owned_pid" ]] || return 1;sam_bgm_owned_pid=$value;;
            start) [[ -z "$sam_bgm_owned_start" ]] || return 1;sam_bgm_owned_start=$value;;
            exe) [[ -z "$sam_bgm_owned_exe" ]] || return 1;sam_bgm_owned_exe=$value;;
            socket) [[ -z "$sam_bgm_owned_socket" ]] || return 1;sam_bgm_owned_socket=$value;;
            wrapper_pid) [[ -z "$sam_bgm_owned_wrapper" ]] || return 1;sam_bgm_owned_wrapper=$value;;
            wrapper_start) [[ -z "$sam_bgm_owned_wrapper_start" ]] || return 1;sam_bgm_owned_wrapper_start=$value;;
        esac
    done < "$sam_bgm_owner_file"
    [[ -z "$expected" || "$expected" == "$sam_bgm_owned_pid" ]] || return 1
    [[ "$sam_bgm_owned_start" =~ ^[0-9]+$ && "$sam_bgm_owned_exe" == /* ]] || return 1
    sam_bgm_process_start "$sam_bgm_owned_pid" && [[ "$sam_bgm_process_ticks" == "$sam_bgm_owned_start" ]] || return 1
    exe=$(readlink "$sam_bgm_proc/$sam_bgm_owned_pid/exe" 2>/dev/null) || return 1
    [[ "$exe" == "$sam_bgm_owned_exe" ]]
}

sam_bgm_capture_daemon() { # exact SAM-spawned wrapper PID/start
    local wrapper=$1 wrapper_start=$2 daemon ancestor parent attempt exe socket_identity temp query_budget="${3:-3s}"
    [[ "$query_budget" =~ ^[1-3]s$ ]] || return 1 # timeout 0 would disable its deadline
    [[ -S "$sam_bgm_socket" ]] || return 1
    daemon=$(printf pid | timeout -k 0.2s "$query_budget" socat -t 4 - "UNIX-CONNECT:$sam_bgm_socket" 2>/dev/null) || return 1
    [[ "$daemon" =~ ^[1-9][0-9]*$ ]] || return 1
    ancestor=$daemon
    for ((attempt=0;attempt<20;attempt++)); do
        sam_bgm_process_start "$ancestor" || return 1
        if [[ "$ancestor" == "$wrapper" ]]; then
            [[ "$sam_bgm_process_ticks" == "$wrapper_start" ]] || return 1
            break
        fi
        parent=$sam_bgm_process_parent
        [[ "$parent" =~ ^[1-9][0-9]*$ && "$parent" != "$ancestor" ]] || return 1
        ancestor=$parent
    done
    [[ "$ancestor" == "$wrapper" ]] || return 1
    # Identity is now proven through the trusted launched wrapper, not through
    # an arbitrary /tmp/bgm.sh name or a socket server's claimed numeric PID.
    sam_bgm_process_start "$daemon" && sam_bgm_socket_owned "$daemon" || return 1
    local daemon_start=$sam_bgm_process_ticks
    exe=$(readlink "$sam_bgm_proc/$daemon/exe" 2>/dev/null) || return 1
    [[ "$exe" == /* && "$exe" != *$'\n'* && "$exe" != *$'\r'* ]] || return 1
    socket_identity=$(stat -Lc '%d:%i|%z' "$sam_bgm_socket") || return 1
    mkdir -p "${sam_bgm_owner_file%/*}" || return 1
    temp="$sam_bgm_owner_file.tmp.$BASHPID"
    printf 'pid=%s\nstart=%s\nexe=%s\nsocket=%s\nwrapper_pid=%s\nwrapper_start=%s\n' "$daemon" "$daemon_start" "$exe" "$socket_identity" "$wrapper" "$wrapper_start" > "$temp" &&
        mv -f "$temp" "$sam_bgm_owner_file" || return 1
    sam_bgm_record_matches "$daemon"
}

sam_bgm_abort_spawn() { # only the verified SAM-spawned wrapper and its children
    local wrapper=$1 ticks=$2 entry pid attempt alive=1 deadline
    local -A owned=()
    sam_bgm_process_start "$wrapper" && [[ "$sam_bgm_process_ticks" == "$ticks" ]] || return 1
    owned[$wrapper]=$ticks
    for entry in "$sam_bgm_proc"/[0-9]*/stat;do
        pid=${entry%/stat};pid=${pid##*/}
        sam_bgm_process_start "$pid" || continue
        [[ "$sam_bgm_process_parent" != "$wrapper" ]] || owned[$pid]=$sam_bgm_process_ticks
    done
    # Children may be the extracted daemon. Signal them before the wrapper so
    # reparenting cannot erase the ancestry proof. No name or process-group kill.
    for pid in "${!owned[@]}";do
        [[ "$pid" != "$wrapper" ]] || continue
        sam_bgm_process_start "$pid" && [[ "$sam_bgm_process_ticks" == "${owned[$pid]}" ]] && kill -TERM "$pid" 2>/dev/null || true
    done
    sam_bgm_process_start "$wrapper" && [[ "$sam_bgm_process_ticks" == "$ticks" ]] && kill -TERM "$wrapper" 2>/dev/null || true
    deadline=$((SECONDS+4))
    while ((SECONDS<deadline));do
        alive=0
        for pid in "${!owned[@]}";do
            sam_bgm_process_start "$pid" && [[ "$sam_bgm_process_ticks" == "${owned[$pid]}" ]] && alive=1
        done
        ((alive)) || break
        sleep .05
    done
    if sam_bgm_process_start "$wrapper" && [[ "$sam_bgm_process_ticks" == "$ticks" ]];then
        return 1 # never turn a bounded cleanup into an unbounded wait
    fi
    wait "$wrapper" 2>/dev/null || true
    ((alive == 0))
}

function bgm_start() {
    [[ "${bgm,,}" == yes ]] || { bgm_stop force; return; }
    local pids attempt wrapper= wrapper_start= verified=0 deadline pid ticks playback status
    pids=$(sam_bgm_pids)
    if [[ -z "$pids" ]]; then
        # A pre-existing unverified endpoint is not permission to launch over
        # or control someone else's service, including an arbitrary /tmp copy.
        if [[ -e "$sam_bgm_socket" ]];then
            sam_bgm_record_matches "" || true
            if [[ -n "$sam_bgm_owned_pid" && -n "$sam_bgm_owned_socket" ]] &&
               ! sam_bgm_process_start "$sam_bgm_owned_pid" &&
               [[ "$(stat -Lc '%d:%i|%z' "$sam_bgm_socket" 2>/dev/null)" == "$sam_bgm_owned_socket" ]];then
                rm -f -- "$sam_bgm_socket" || return 1
            else echo 'SAM BGM: socket has no verified owner.' >&2;return 1;fi
        fi
        [[ -r "$sam_bgm_script" ]] || { echo "BGM script is missing: $sam_bgm_script" >&2; return 1; }
        (
            trap - EXIT TERM INT
            if [[ "${sam_session_lock_fd:-}" =~ ^[0-9]+$ ]]; then exec {sam_session_lock_fd}>&-;fi
            # Both the bundled script and the installed ARM ELF implement
            # `exec` as the service interface. No-argument mode is interactive;
            # its background stdin EOF can abandon a detached child before
            # ownership is captured.
            if [[ "${sam_owner:-}" =~ ^[1-9][0-9]*:[0-9]+$ ]]; then
                export BGM_SAM_OWNER=$sam_owner
            fi
            exec "$sam_bgm_script" exec
        ) >/dev/null 2>&1 &
        wrapper=$!
        for ((attempt=0;attempt<10;attempt++)); do
            if sam_bgm_process_start "$wrapper";then wrapper_start=$sam_bgm_process_ticks;break;fi
            sleep .01
        done
        sam_bgm_spawn_pid=$wrapper sam_bgm_spawn_start=$wrapper_start
        # A socket pathname alone is not readiness. Share one absolute budget
        # across PID queries, ancestry verification and brief retry waits.
        deadline=$((SECONDS+6))
        while ((SECONDS<deadline));do
            local query_seconds=$((deadline-SECONDS))
            ((query_seconds <= 3)) || query_seconds=3
            if [[ -n "$wrapper_start" ]] && sam_bgm_capture_daemon "$wrapper" "$wrapper_start" "${query_seconds}s";then verified=1;break;fi
            sleep .05
        done
        if ((verified == 0));then
            if [[ -n "$wrapper_start" ]] && sam_bgm_abort_spawn "$wrapper" "$wrapper_start";then
                sam_bgm_spawn_pid= sam_bgm_spawn_start=
            fi
            echo 'SAM BGM: daemon ownership/PID protocol could not be verified.' >&2
            return 1
        fi
    elif ! sam_bgm_record_matches "";then
        # Existing exact installed-script instances remain supported. Resolve
        # their daemon by ancestry too; an arbitrary /tmp basename is insufficient.
        deadline=$((SECONDS+6))
        while ((SECONDS<deadline));do
            while IFS= read -r pid;do
                sam_bgm_process_start "$pid" || continue;ticks=$sam_bgm_process_ticks
                local query_seconds=$((deadline-SECONDS))
                ((query_seconds <= 3)) || query_seconds=3
                if sam_bgm_capture_daemon "$pid" "$ticks" "${query_seconds}s";then verified=1;break;fi
            done <<< "$pids"
            ((verified == 0)) || break
            sleep .05
        done
        ((verified)) || return 1
    fi
    # The durable RAM record now owns the verified service. Transient launch
    # tracking is only for failed/interrupted startup, not a later repeated Stop.
    sam_bgm_spawn_pid= sam_bgm_spawn_start=
    local policy_rc=0
    sam_bgm_policy active || policy_rc=$?
    case "$policy_rc" in 0) return 0;;3) ;;*) return "$policy_rc";;esac
    # Metadata is available when the user enabled external BGM logging. SAM
    # must not rewrite the user's persistent music configuration to enable it.
    sam_bgm_command 'set playincore yes' || return 1
    playback=$(sam_bgm_query 'get playback') || return 1
    [[ -n "$playback" ]] || return 1
    # Changing playback restarts the installed native playlist, as does play.
    # Avoid doing both redundantly when the daemon is already ready/playing.
    if [[ "$playback" != random ]];then sam_bgm_command 'set playback random' || return 1;fi
    status=$(sam_bgm_query status) || return 1
    case "${status%%$'\t'*}" in yes) return 0;;no) sam_bgm_command play;;*) return 1;;esac
}

sam_bgm_menu_prepare() {
    [[ "${bgm,,}" == yes && "${bgmstop,,}" != yes ]] || return 0
    [[ -n "$(sam_bgm_pids owned)" ]] || return 0
    local policy_rc=0
    sam_bgm_policy menu || policy_rc=$?
    case "$policy_rc" in 0) return 0;;3) ;;*) return "$policy_rc";;esac
    # Acknowledge policy before CORENAME changes. Do not stop the decoder:
    # Menu's watcher will select its playlist, and stopping afterwards races it.
    sam_bgm_command 'set playincore no' || return 1
    [[ "$(sam_bgm_query 'get playincore')" == no ]]
}

function bgm_stop() {
    [[ "${bgm,,}" == yes || "${1:-}" == force ]] || return 0
    local pid pids ticks attempt deadline command_failed=0 terminate_failed=0
    local -A signalled=()
    if [[ -n "${sam_bgm_spawn_pid:-}" && -n "${sam_bgm_spawn_start:-}" ]] && ! sam_bgm_record_matches "";then
        sam_bgm_capture_daemon "$sam_bgm_spawn_pid" "$sam_bgm_spawn_start" || {
            if sam_bgm_abort_spawn "$sam_bgm_spawn_pid" "$sam_bgm_spawn_start";then
                sam_bgm_spawn_pid= sam_bgm_spawn_start=
                return 0
            fi
            return 1
        }
        sam_bgm_spawn_pid= sam_bgm_spawn_start=
    fi
    pids=$(sam_bgm_pids owned)
    [[ -n "$pids" ]] || return 0
    if [[ "${bgmstop,,}" == yes ]]; then
        while IFS= read -r pid; do
            # Revalidate immediately before signalling; never kill a player
            # merely because it is named mpg123. BGM owns its child cleanup.
            sam_bgm_pid_matches "$pid" || continue
            sam_bgm_process_start "$pid" || {
                sam_bgm_pid_matches "$pid" && terminate_failed=1
                continue
            }
            ticks=$sam_bgm_process_ticks
            if ! sam_bgm_pid_matches "$pid" || ! sam_bgm_process_start "$pid" || [[ "$sam_bgm_process_ticks" != "$ticks" ]]; then
                continue
            fi
            if ! kill -TERM "$pid" 2>/dev/null; then
                if sam_bgm_process_start "$pid" && [[ "$sam_bgm_process_ticks" == "$ticks" ]]; then terminate_failed=1; fi
                continue
            fi
            signalled[$pid]=$ticks
        done <<< "$pids"
        # Signal all captured instances before waiting (wrapper plus daemon).
        # SECONDS has integer resolution: +4 guarantees at least three seconds,
        # with one shared absolute deadline instead of accumulated loop sleeps.
        deadline=$((SECONDS+4))
        while ((SECONDS<deadline)); do
            local remaining=0
            for pid in "${!signalled[@]}"; do
                if sam_bgm_process_start "$pid" && [[ "$sam_bgm_process_ticks" == "${signalled[$pid]}" ]]; then remaining=1;fi
            done
            ((remaining)) || break
            sleep 0.05
        done
        for pid in "${!signalled[@]}";do
            if sam_bgm_process_start "$pid" && [[ "$sam_bgm_process_ticks" == "${signalled[$pid]}" ]];then terminate_failed=1;fi
        done
        ((terminate_failed == 0)) || return 1
    fi
    # With an intentionally persistent BGM process there is no termination
    # fallback. A failed stop cannot authorize the early Menu/audio barrier.
    if [[ "${bgmstop,,}" != yes ]]; then
        local policy_mode=game policy_rc=0
        [[ "${1:-}" != menu ]] || policy_mode=menu
        sam_bgm_policy "$policy_mode" || policy_rc=$?
        case "$policy_rc" in 0) return 0;;3) ;;*) return "$policy_rc";;esac
        sam_bgm_command 'set playincore no' || return 1
        if [[ "${1:-}" == menu ]]; then
            [[ "$(sam_bgm_query 'get playincore')" == no ]]
            return
        fi
        sam_bgm_command stop || return 1
        local status playincore
        status=$(sam_bgm_query status) && playincore=$(sam_bgm_query 'get playincore') || return 1
        [[ "${status%%$'\t'*}" == no && "$playincore" == no ]] || return 1
    fi
    return 0
}
