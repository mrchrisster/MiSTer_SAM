# SPDX-License-Identifier: GPL-3.0-or-later
# A hosted adapter owns a unique session; MCP is its verified controller only.
sam_engine_hosted_parent_valid() {
    local line fields=() args=()
    [[ "${SAM_ENGINE_CONTROLLER_PID:-}" =~ ^[1-9][0-9]*$ &&
       "$SAM_ENGINE_CONTROLLER_PID" == "$PPID" &&
       "${SAM_ENGINE_CONTROLLER_START:-}" =~ ^[0-9]+$ ]] || return 1
    IFS= read -r line < "/proc/$PPID/stat" || return 1
    read -ra fields <<< "${line##*) }"
    [[ "${fields[19]:-}" == "$SAM_ENGINE_CONTROLLER_START" &&
       "${fields[0]}" != Z && "${fields[0]}" != X ]] || return 1
    mapfile -d '' -t args < "/proc/$PPID/cmdline" || return 1
    [[ "${args[0]##*/}" == python* && "${args[1]:-}" == "$sam_root/MiSTer_SAM_MCP.py" ]] || return 1
    # A resident MCP PID is not a session identity. This child owns a unique
    # PID/start lease and must not inherit standalone-engine ownership fields.
    unset SAM_ENGINE_OWNER_PID SAM_ENGINE_OWNER_START
    sam_engine_adapter_verified=1 sam_engine_hosted=1
}

sam_engine_controller_alive() {
    [[ "${sam_engine_hosted:-0}" == 1 && "${sam_engine_adapter_verified:-0}" == 1 &&
       "${SAM_ENGINE_CONTROLLER_PID:-}" =~ ^[1-9][0-9]*$ &&
       "${SAM_ENGINE_CONTROLLER_START:-}" =~ ^[0-9]+$ ]] || return 1
    sam_pid_start "$SAM_ENGINE_CONTROLLER_PID" &&
        [[ "$sam_proc_start" == "$SAM_ENGINE_CONTROLLER_START" ]]
}

sam_engine_guardian_begin() {
    sam_engine_controller_alive && sam_session_is_current || return 1
    [[ -f "$sam_root/sam/controller_guardian.py" && -r "$sam_root/sam/controller_guardian.py" &&
       ! -L "$sam_root/sam/controller_guardian.py" ]] || return 1
    sam_pid_start "$$" || return 1
    local adapter_start=$sam_proc_start
    if [[ -n "${sam_guardian_pid:-}" ]]; then
        sam_pid_start "$sam_guardian_pid" && [[ "$sam_proc_start" == "$sam_guardian_start" ]] || return 1
        printf 'pid=%s\nstart=%s\ngroup=%s\nsid=%s\nowner=%s\n' \
            "$sam_guardian_pid" "$sam_guardian_start" "$sam_guardian_group" \
            "$sam_guardian_sid" "$sam_owner" > "$sam_session/controller-guardian"
        return $?
    fi
    # The existing private-group STOP barrier registers the guardian before
    # any callback executes. Python startup occurs asynchronously afterward.
    sam_job_spawn sam_guardian python3 -S "$sam_root/sam/controller_guardian.py" \
        "$SAM_ENGINE_CONTROLLER_PID" "$SAM_ENGINE_CONTROLLER_START" \
        "$$" "$adapter_start" "$mrsamtmp" "$sam_session" 3>&- || return 1
    printf 'pid=%s\nstart=%s\ngroup=%s\nsid=%s\nowner=%s\n' \
        "$sam_guardian_pid" "$sam_guardian_start" "$sam_guardian_group" \
        "$sam_guardian_sid" "$sam_owner" > "$sam_session/controller-guardian"
}

sam_engine_guardian_preflight_begin() {
    sam_engine_controller_alive || return 1
    sam_pid_start "$$" || return 1
    [[ "$sam_proc_group" == "$$" && "$sam_proc_session" == "$$" ]] || return 1
    local adapter_start=$sam_proc_start
    sam_guardian_runtime="${SAM_TMP_ROOT:-/tmp/.SAM_tmp}"
    mkdir -p "$sam_guardian_runtime" || return 1
    [[ -f "$sam_root/sam/controller_guardian.py" && ! -L "$sam_root/sam/controller_guardian.py" ]] || return 1
    sam_job_spawn sam_guardian python3 -S "$sam_root/sam/controller_guardian.py" \
        "$SAM_ENGINE_CONTROLLER_PID" "$SAM_ENGINE_CONTROLLER_START" "$$" "$adapter_start" \
        "$sam_guardian_runtime" "$sam_guardian_runtime/session-$$:$adapter_start" "$$" "$$" 3>&-
}

sam_engine_guardian_preflight_exit() {
    local rc=${1:-0}
    if ! sam_engine_guardian_cancel; then
        local mrsamtmp=${sam_guardian_runtime:-${SAM_TMP_ROOT:-/tmp/.SAM_tmp}}
        sam_cleanup_failure_record sam_guardian "${sam_job_error:-Preflight guardian cleanup failed}" || true
        rc=1
    fi
    trap - EXIT
    exit "$rc"
}

sam_engine_guardian_cancel() {
    [[ -n "${sam_guardian_pid:-}" ]] || return 0
    sam_job_cancel "$sam_guardian_pid" "$sam_guardian_start" \
        "$sam_guardian_group" "$sam_guardian_sid" || return 1
    if sam_pid_start "$sam_guardian_pid" && [[ "$sam_proc_start" == "$sam_guardian_start" ]]; then
        sam_job_error='Controller guardian did not exit'; return 1
    fi
    wait "$sam_guardian_pid" 2>/dev/null || true
    sam_guardian_pid= sam_guardian_start= sam_guardian_group= sam_guardian_sid=
}
