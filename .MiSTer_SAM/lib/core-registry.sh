# SPDX-License-Identifier: GPL-3.0-or-later
# Session-private RAM readiness. Records are literal data, never shell input.
sam_core_registry_context() {
    [[ "${sam_session_started:-0}" == 1 && "${sam_owner:-}" =~ ^[1-9][0-9]*:[0-9]+$ &&
       "${sam_revision:-}" =~ ^[1-9][0-9]*$ && ${#sam_revision} -le 12 &&
       -d "${sam_session:-}" && ! -L "$sam_session" &&
       -f "$sam_session/alive" && ! -L "$sam_session/alive" ]] || return 1
    sam_session_is_current
}

sam_core_registry_binding() {
    [[ "${sam_core_registry_active:-0}" == 1 ]] && sam_core_registry_context || return 1
    local __sam_registry_line __sam_registry_key __sam_registry_value
    local -A __sam_registry_marker=()
    [[ -d "$sam_session/cores" && ! -L "$sam_session/cores" &&
       -f "$sam_session/cores/revision" && ! -L "$sam_session/cores/revision" ]] || return 1
    while IFS= read -r __sam_registry_line || [[ -n "$__sam_registry_line" ]]; do
        [[ "$__sam_registry_line" == *=* ]] || return 1
        __sam_registry_key=${__sam_registry_line%%=*} __sam_registry_value=${__sam_registry_line#*=}
        case "$__sam_registry_key" in owner|revision) ;; *) return 1 ;; esac
        [[ -z "${__sam_registry_marker[$__sam_registry_key]+present}" ]] || return 1
        __sam_registry_marker[$__sam_registry_key]=$__sam_registry_value
    done < "$sam_session/cores/revision"
    [[ ${#__sam_registry_marker[@]} == 2 && "${__sam_registry_marker[owner]-}" == "$sam_owner" &&
       "${__sam_registry_marker[revision]-}" == "$sam_revision" ]]
}

sam_core_registry_allowed() {
    local __sam_registry_allowed
    for __sam_registry_allowed in "${sam_allowed_cores[@]}"; do
        [[ "$__sam_registry_allowed" != "$1" ]] || return 0
    done
    return 1
}

sam_core_registry_fields_valid() { # core state count complete
    [[ "$1" =~ ^[a-z0-9_]+$ && "$3" =~ ^(0|[1-9][0-9]*)$ && ${#3} -le 12 &&
       ( "$4" == 0 || "$4" == 1 ) ]] || return 1
    case "$2" in
        pending) [[ "$3:$4" == 0:0 ]] ;;
        ready) [[ "$3" != 0 && ( "$4" == 1 || "$1" == arcade ) ]] ;;
        empty) [[ "$3:$4" == 0:1 ]] ;;
        *) return 1 ;;
    esac
}

sam_core_registry_write() { # target and literal record text; caller holds lock
    local __sam_registry_target=$1 __sam_registry_temp="$1.tmp.$BASHPID"
    [[ ! -L "$__sam_registry_target" && ( ! -e "$__sam_registry_target" || -f "$__sam_registry_target" ) ]] || return 1
    [[ ! -L "$__sam_registry_temp" && ( ! -e "$__sam_registry_temp" || -f "$__sam_registry_temp" ) ]] || return 1
    printf '%s' "$2" > "$__sam_registry_temp" || return 1
    if ! sam_core_registry_context || { [[ "${3:-}" == bound ]] && ! sam_core_registry_binding; } ||
        [[ -L "$__sam_registry_target" || ( -e "$__sam_registry_target" && ! -f "$__sam_registry_target" ) ]]; then
        rm -f -- "$__sam_registry_temp"; return 1
    fi
    mv -f -- "$__sam_registry_temp" "$__sam_registry_target" || {
        rm -f -- "$__sam_registry_temp"; return 1;
    }
}

sam_core_registry_begin_locked() {
    sam_core_registry_context || return 1
    local __sam_registry_core __sam_registry_text
    for __sam_registry_core in "${sam_allowed_cores[@]}"; do
        [[ "$__sam_registry_core" =~ ^[a-z0-9_]+$ ]] || return 2
    done
    [[ ! -L "$sam_session/cores" ]] || return 1
    if [[ ! -d "$sam_session/cores" ]]; then mkdir -m 700 -- "$sam_session/cores" || return 1; fi
    # Missing allowed-core records mean pending under this revision. Clear old
    # state in one operation instead of forking mv once per enabled core.
    rm -f -- "$sam_session/cores/"*.state || return 1
    printf -v __sam_registry_text 'owner=%s\nrevision=%s\n' "$sam_owner" "$sam_revision"
    sam_core_registry_write "$sam_session/cores/revision" "$__sam_registry_text" || return 1
    sam_core_registry_write "$sam_session/available-cores" '' || return 1
    sam_core_registry_active=1
}

sam_core_registry_begin() {
    unset sam_core_registry_active
    case "${sam_mode:-normal}" in normal|roulette) ;; *) return 0 ;; esac
    [[ "${sam_session_started:-0}" == 1 ]] || return 0
    # Session admission already holds this transition lock. Reuse it without a
    # second flock probe; children cannot borrow their parent's holder identity.
    if [[ "${sam_session_lock_holder:-}" == "$BASHPID" && "${sam_session_lock_depth:-0}" -gt 0 ]]; then
        sam_core_registry_begin_locked
        return $?
    fi
    sam_session_lock || return 1
    local __sam_registry_rc=0
    sam_core_registry_begin_locked || __sam_registry_rc=$?
    sam_session_unlock
    return "$__sam_registry_rc"
}

sam_core_registry_read_record() { # internal row read; caller fences the batch
    sam_registry_state= sam_registry_count= sam_registry_complete=
    [[ "$1" =~ ^[a-z0-9_]+$ ]] || return 1
    local __sam_registry_path="$sam_session/cores/$1.state"
    local __sam_registry_line __sam_registry_key __sam_registry_value
    local -A __sam_registry_record=()
    if [[ ! -e "$__sam_registry_path" && ! -L "$__sam_registry_path" ]]; then
        sam_core_registry_allowed "$1" || return 1
        sam_registry_state=pending sam_registry_count=0 sam_registry_complete=0
        return 0
    fi
    [[ -f "$__sam_registry_path" && ! -L "$__sam_registry_path" ]] || return 1
    while IFS= read -r -n 256 __sam_registry_line || [[ -n "$__sam_registry_line" ]]; do
        (( ${#__sam_registry_line} < 256 )) || return 1
        [[ "$__sam_registry_line" == *=* ]] || return 1
        __sam_registry_key=${__sam_registry_line%%=*} __sam_registry_value=${__sam_registry_line#*=}
        case "$__sam_registry_key" in owner|revision|core|state|count|complete) ;; *) return 1 ;; esac
        [[ -z "${__sam_registry_record[$__sam_registry_key]+present}" ]] || return 1
        __sam_registry_record[$__sam_registry_key]=$__sam_registry_value
    done < "$__sam_registry_path"
    [[ ${#__sam_registry_record[@]} == 6 && "${__sam_registry_record[owner]-}" == "$sam_owner" &&
       "${__sam_registry_record[revision]-}" == "$sam_revision" &&
       "${__sam_registry_record[core]-}" == "$1" ]] || return 1
    sam_core_registry_fields_valid "$1" "${__sam_registry_record[state]-}" \
        "${__sam_registry_record[count]-}" "${__sam_registry_record[complete]-}" || return 1
    sam_registry_state=${__sam_registry_record[state]} sam_registry_count=${__sam_registry_record[count]}
    sam_registry_complete=${__sam_registry_record[complete]}
}

sam_core_registry_read() { # scalar read keeps both context fences
    sam_registry_state= sam_registry_count= sam_registry_complete=
    sam_core_registry_binding || return 1
    sam_core_registry_read_record "$1" || return 1
    if ! sam_core_registry_binding; then
        sam_registry_state= sam_registry_count= sam_registry_complete=
        return 1
    fi
}

sam_core_registry_candidates() { # output array; preserve pending rotation members
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && "$1" != __sam_registry_* ]] || return 2
    local -n __sam_registry_output=$1
    __sam_registry_output=()
    sam_core_registry_binding || return 1
    local __sam_registry_core
    local -a __sam_registry_ready=()
    local -A __sam_registry_seen=()
    for __sam_registry_core in "${corelisttmp[@]}"; do
        [[ "$__sam_registry_core" =~ ^[a-z0-9_]+$ && -z "${__sam_registry_seen[$__sam_registry_core]-}" ]] || continue
        sam_core_registry_allowed "$__sam_registry_core" || continue
        sam_core_registry_read_record "$__sam_registry_core" || continue
        [[ "$sam_registry_state" == ready ]] || continue
        __sam_registry_ready+=("$__sam_registry_core"); __sam_registry_seen[$__sam_registry_core]=1
    done
    if (( ${#__sam_registry_ready[@]} == 0 )); then
        for __sam_registry_core in "${sam_allowed_cores[@]}"; do
            [[ "$__sam_registry_core" =~ ^[a-z0-9_]+$ && -z "${__sam_registry_seen[$__sam_registry_core]-}" ]] || continue
            sam_core_registry_read_record "$__sam_registry_core" || continue
            [[ "$sam_registry_state" == ready ]] || continue
            __sam_registry_ready+=("$__sam_registry_core"); __sam_registry_seen[$__sam_registry_core]=1
        done
    fi
    if ! sam_core_registry_binding; then
        sam_registry_state= sam_registry_count= sam_registry_complete=
        return 1
    fi
    __sam_registry_output=("${__sam_registry_ready[@]}")
}

sam_core_registry_snapshot() { # caller holds lock; informational, never sourced
    sam_core_registry_binding || return 1
    local __sam_registry_core __sam_registry_text=
    local -A __sam_registry_seen=()
    for __sam_registry_core in "${sam_allowed_cores[@]}"; do
        [[ "$__sam_registry_core" =~ ^[a-z0-9_]+$ && -z "${__sam_registry_seen[$__sam_registry_core]-}" ]] || continue
        __sam_registry_seen[$__sam_registry_core]=1
        sam_core_registry_read_record "$__sam_registry_core" || continue
        [[ "$sam_registry_state" != ready ]] || __sam_registry_text+="$__sam_registry_core"$'\n'
    done
    sam_core_registry_write "$sam_session/available-cores" "$__sam_registry_text" bound
}

sam_core_registry_publish_locked() {
    sam_core_registry_binding && sam_core_registry_allowed "$1" || return 1
    local __sam_registry_text
    printf -v __sam_registry_text 'owner=%s\nrevision=%s\ncore=%s\nstate=%s\ncount=%s\ncomplete=%s\n' \
        "$sam_owner" "$sam_revision" "$1" "$2" "$3" "$4"
    sam_core_registry_write "$sam_session/cores/$1.state" "$__sam_registry_text" bound || return 1
    sam_core_registry_snapshot || true
}

sam_core_registry_publish() { # core pending|ready|empty count [complete=1]
    sam_core_registry_fields_valid "$1" "$2" "$3" "${4:-1}" || return 2
    [[ "${sam_core_registry_active:-0}" == 1 ]] || return 1
    sam_session_lock || return 1
    local __sam_registry_rc=0
    sam_core_registry_publish_locked "$1" "$2" "$3" "${4:-1}" || __sam_registry_rc=$?
    sam_session_unlock
    return "$__sam_registry_rc"
}
