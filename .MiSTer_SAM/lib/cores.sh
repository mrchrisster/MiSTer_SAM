# SPDX-License-Identifier: GPL-3.0-or-later
# Requested cores are session configuration; allowed cores are derived policy.
# __sam_* names are private so namerefs cannot shadow caller arrays.
declare -a sam_requested_cores=() sam_allowed_cores=()
declare -A sam_session_core_excluded=()
sam_core_policy_ready=0 sam_core_policy_version=0 sam_core_reason= sam_core_id_result=

sam_core_id() { # normalize one ID; 1=blank, 2=invalid
    local __sam_id="${1,,}"
    __sam_id="${__sam_id#"${__sam_id%%[![:space:]]*}"}"
    __sam_id="${__sam_id%"${__sam_id##*[![:space:]]}"}"
    sam_core_id_result=$__sam_id
    [[ -n "$__sam_id" ]] || return 1
    if [[ ! "$__sam_id" =~ ^[a-z0-9_]+$ || -z "${CORE_PRETTY[$__sam_id]-}" ]]; then
        sam_core_reason="Unknown core ID: $__sam_id"
        return 2
    fi
}

sam_normalize_cores() { # input/output indexed-array names; supports in-place use
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && "$2" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && "$1" != __sam_* && "$2" != __sam_* ]] || return 2
    local -n __sam_input="$1" __sam_output="$2"
    local __sam_value __sam_rc
    local -a __sam_values=()
    local -A __sam_seen=()
    for __sam_value in "${__sam_input[@]}"; do
        __sam_rc=0; sam_core_id "$__sam_value" || __sam_rc=$?
        (( __sam_rc != 1 )) || continue
        (( __sam_rc == 0 )) || return 2
        [[ -z "${__sam_seen[$sam_core_id_result]-}" ]] || continue
        __sam_seen[$sam_core_id_result]=1
        __sam_values+=("$sam_core_id_result")
    done
    __sam_output=("${__sam_values[@]}")
}

sam_core_rule_check() { # core [candidate|auxiliary]; 0=allow, 1=reject, 2=error
    local __sam_id __sam_hook __sam_rc
    sam_core_reason=
    case "${2:-candidate}" in
        candidate|auxiliary) ;;
        *) sam_core_reason="Unknown core role: $2"; return 2 ;;
    esac
    sam_core_id "$1" || { [[ -n "$sam_core_reason" ]] || sam_core_reason='Empty core ID'; return 2; }
    __sam_id=$sam_core_id_result
    for __sam_hook in ${SAM_HOOKS[core_allowed]-}; do
        __sam_rc=0
        "$__sam_hook" "$__sam_id" "${2:-candidate}" || __sam_rc=$?
        if (( __sam_rc == 1 )); then
            [[ -n "$sam_core_reason" ]] || sam_core_reason="$__sam_id rejected by $__sam_hook"
            return 1
        elif (( __sam_rc != 0 )); then
            sam_core_reason="Core rule $__sam_hook failed for $__sam_id (status $__sam_rc)"
            return 2
        fi
    done
    sam_core_id_result=$__sam_id
    return 0
}

sam_filter_cores() { # pure list transformation; input/output array names
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && "$2" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && "$1" != __sam_* && "$2" != __sam_* ]] || return 2
    local -n __sam_input="$1" __sam_output="$2"
    local __sam_value __sam_rc
    local -a __sam_values=()
    local -A __sam_seen=()
    for __sam_value in "${__sam_input[@]}"; do
        __sam_rc=0; sam_core_id "$__sam_value" || __sam_rc=$?
        (( __sam_rc != 1 )) || continue
        (( __sam_rc == 0 )) || return 2
        __sam_value=$sam_core_id_result
        [[ -z "${__sam_seen[$__sam_value]-}" ]] || continue
        __sam_seen[$__sam_value]=1
        __sam_rc=0; sam_core_rule_check "$__sam_value" || __sam_rc=$?
        (( __sam_rc != 1 )) || continue
        (( __sam_rc == 0 )) || return 2
        __sam_values+=("$__sam_value")
    done
    __sam_output=("${__sam_values[@]}")
    return 0
}

sam_core_session_begin() { # optional explicit core; configuration read once
    sam_core_policy_ready=0
    sam_session_core_excluded=()
    sam_core_reason=
    sam_normalize_cores corelist sam_requested_cores || return 2
    sam_emit core_requested sam_requested_cores || { sam_core_reason='Module core-request hook failed'; return 2; }
    sam_normalize_cores sam_requested_cores sam_requested_cores || return 2
    SAM_MODE=ALL; SAM_TARGET_CORE=
    if [[ -n "${1:-}" ]]; then
        sam_core_id "$1" || return 2
        SAM_MODE=SINGLE; SAM_TARGET_CORE=$sam_core_id_result
        sam_requested_cores=("$SAM_TARGET_CORE")
    fi
    export SAM_MODE SAM_TARGET_CORE
    sam_emit session_validate || { [[ -n "$sam_core_reason" ]] || sam_core_reason='Module rejected this session configuration'; return 2; }
    corelisttmp=()
    sam_core_policy_ready=1
    sam_core_policy_refresh
}

sam_core_policy_refresh() {
    if [[ "$sam_core_policy_ready" != 1 ]]; then
        local -a initial_remaining=("${corelisttmp[@]}")
        sam_core_session_begin "${SAM_TARGET_CORE:-}" || return $?
        # Library callers may already have a rotation in progress. Preserve its
        # allowed members; real session_begin still starts a fresh full cycle.
        if (( ${#initial_remaining[@]} )); then
            corelisttmp=("${initial_remaining[@]}")
            sam_core_policy_refresh
            return $?
        fi
        return 0
    fi
    local -a policy_cores=() policy_remaining=()
    local __sam_id __sam_old_key="${sam_allowed_cores[*]}"
    local -A __sam_allowed=() __sam_old=() __sam_seen=()
    sam_filter_cores sam_requested_cores policy_cores || return 2
    for __sam_id in "${sam_allowed_cores[@]}"; do __sam_old[$__sam_id]=1; done
    sam_allowed_cores=()
    for __sam_id in "${policy_cores[@]}"; do
        [[ -z "${sam_session_core_excluded[$__sam_id]-}" ]] || continue
        sam_allowed_cores+=("$__sam_id"); __sam_allowed[$__sam_id]=1
    done
    for __sam_id in "${corelisttmp[@]}"; do
        [[ "$__sam_id" =~ ^[a-z0-9_]+$ ]] || continue
        [[ -n "${__sam_allowed[$__sam_id]-}" && -z "${__sam_seen[$__sam_id]-}" ]] || continue
        policy_remaining+=("$__sam_id"); __sam_seen[$__sam_id]=1
    done
    for __sam_id in "${sam_allowed_cores[@]}"; do
        if (( ${#__sam_old[@]} > 0 )) && [[ -z "${__sam_old[$__sam_id]-}" && -z "${__sam_seen[$__sam_id]-}" ]]; then
            policy_remaining+=("$__sam_id"); __sam_seen[$__sam_id]=1
        fi
    done
    (( ${#policy_remaining[@]} )) || policy_remaining=("${sam_allowed_cores[@]}")
    corelist=("${sam_allowed_cores[@]}"); corelisttmp=("${policy_remaining[@]}")
    if [[ "$__sam_old_key" != "${sam_allowed_cores[*]}" ]]; then
        sam_core_policy_version=$((sam_core_policy_version+1))
    fi
    if (( ${#sam_allowed_cores[@]} == 0 )); then
        sam_core_reason="No allowed cores remain for the requested systems${sam_core_reason:+: $sam_core_reason}"
        return 1
    fi
    sam_core_reason=
    return 0
}

sam_core_require() { # selected game core; also used for prepared/replayed games
    sam_core_rule_check "$1" || return $?
    local __sam_id=$sam_core_id_result __sam_allowed
    [[ "$sam_core_policy_ready" == 1 ]] || return 0
    for __sam_allowed in "${sam_allowed_cores[@]}"; do
        [[ "$__sam_id" != "$__sam_allowed" ]] || return 0
    done
    sam_core_reason="$__sam_id is outside this session's allowed core list"
    return 1
}
