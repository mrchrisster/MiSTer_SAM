# SPDX-License-Identifier: GPL-3.0-or-later
# Foreground session state. PID/start records remain the MCP wire protocol.
# Locks cover transitions/cleanup only; no lock or subprocess on timer ticks.
sam_session_lock() {
    if [[ "${sam_session_lock_holder:-}" == "$BASHPID" && "${sam_session_lock_depth:-0}" -gt 0 ]]; then
        # TERM can interrupt between flock returning and the caller continuing.
        # Verify/reacquire this same open description, never open a second one.
        flock -n "$sam_session_lock_fd" || return 1
        sam_session_lock_depth=$((sam_session_lock_depth+1)); return 0
    fi
    command -v flock >/dev/null || {
        printf 'SAM: session ownership requires flock\n' >&2; return 1;
    }
    exec {sam_session_lock_fd}> "$mrsamtmp/session-owner.lock" || return 1
    sam_session_lock_holder=$BASHPID sam_session_lock_depth=1
    if flock -x -w 2 "$sam_session_lock_fd"; then return 0; fi
    sam_session_lock_holder= sam_session_lock_depth=0
    exec {sam_session_lock_fd}>&-
    printf 'SAM: session transition busy or lock unavailable\n' >&2
    return 1
}

sam_session_unlock() {
    sam_session_lock_depth=$((sam_session_lock_depth-1))
    ((sam_session_lock_depth == 0)) || return 0
    sam_session_lock_holder=
    # Closing the final open description releases flock. All transition
    # helpers have completed, and cleanup releases before spawning hooks.
    exec {sam_session_lock_fd}>&-
}

sam_session_read_owner() {
    local line
    sam_session_owner_pid= sam_session_owner_start=
    [[ -r "$mrsamtmp/session-owner" ]] || return 1
    while IFS= read -r line; do
        case "$line" in
            pid=*) sam_session_owner_pid=${line#*=} ;;
            start=*) sam_session_owner_start=${line#*=} ;;
        esac
    done < "$mrsamtmp/session-owner"
    [[ "$sam_session_owner_pid" =~ ^[1-9][0-9]*$ && "$sam_session_owner_start" =~ ^[0-9]+$ ]]
}

sam_session_is_current() {
    [[ -n "${sam_owner:-}" ]] || return 1
    sam_session_read_owner || return 1
    [[ "$sam_session_owner_pid:$sam_session_owner_start" == "$sam_owner" ]]
}

sam_session_write_phase() { # caller holds the transition lock
    local temp="$mrsamtmp/session-owner.tmp.$BASHPID"
    if ! printf 'pid=%s\nstart=%s\nphase=%s\nlaunch=%s\n' \
        "${sam_owner%%:*}" "${sam_owner#*:}" "$1" "$2" > "$temp" ||
        ! mv -f -- "$temp" "$mrsamtmp/session-owner"; then
        rm -f -- "$temp"; return 1
    fi
    sam_last_phase=$1 sam_launch_serial=$2
}

sam_session_begin() {
    # BASHPID excludes preparation/background children, even though $$ is inherited.
    [[ "$BASHPID" == "$$" ]] || return 1
    sam_pid_start "$$" || return 1
    local owner="$$:$sam_proc_start" rc=0
    mkdir -p "$mrsamtmp" || return 1
    sam_session_lock || return 1
    if sam_cleanup_failure_pending; then
        echo 'SAM: prior owned-job cleanup is incomplete; start refused.' >&2
        sam_session_unlock; return 1
    fi
    if sam_session_read_owner && sam_pid_start "$sam_session_owner_pid" &&
        [[ "$sam_proc_start" == "$sam_session_owner_start" ]]; then
        printf 'SAM: a live session already owns the runtime\n' >&2
        sam_session_unlock; return 1
    fi
    sam_owner=$owner sam_session="$mrsamtmp/session-$owner"
    trap 'sam_session_exit "$?"' EXIT
    trap sam_session_term TERM
    sam_catalog_cache="$mrsamtmp/catalog-cache"
    sam_last_phase= sam_launch_serial=0 sam_generation=0
    sam_exit_reason= sam_exit_reported=0 sam_exit_snapshot_taken=0 sam_diagnostic_cleanup_status=0
    sam_session_cleaned=0 sam_cleanup_done=0 sam_session_stop_done=0 sam_audio_stop_done=0
    if mkdir -p "$sam_session/ready" "$sam_session/jobs" "$sam_session/consumed" "$sam_catalog_cache" &&
        : > "$sam_session/alive" && sam_session_write_phase preparing 0; then
        printf '%s\n' "${sam_config_ini_snapshot:-}" > "$sam_session/config.ini"
        printf '%s\n' "${sam_config_category_snapshot:-}" > "$sam_session/config-category"
        printf '%s\n' "${sam_config_roulette_snapshot:-}" > "$sam_session/config-roulette"
        [[ ! -f "$gamelistpath/.excludetags" ]] || cp -- "$gamelistpath/.excludetags" "$sam_session/config-tags"
        sam_session_started=1
        if declare -F sam_diagnostic >/dev/null; then
            sam_diagnostic session_start "mode=${sam_mode:-${SAM_MODE:-}} target=${SAM_TARGET_CORE:-}" "$sam_owner" || true
        fi
    else rc=1; fi
    sam_session_unlock
    return "$rc"
}

# Only foreground owner transitions are legal; loading is a new launch attempt.
# Compatibility video paths can enter video directly from preparing.
sam_publish_phase() {
    [[ "$BASHPID" == "$$" && "${sam_session_started:-0}" == 1 ]] || return 1
    case "${sam_last_phase:-}:$1" in
        preparing:preparing|loading:loading|playing:playing|video:video|stopping:stopping) ;;
        preparing:loading|preparing:video|preparing:playing|loading:playing|loading:video|loading:preparing|playing:preparing|video:preparing|playing:loading|video:loading|preparing:stopping|loading:stopping|playing:stopping|video:stopping) ;;
        *) return 1 ;;
    esac
    if [[ "$1" == "$sam_last_phase" && "$1" != loading ]]; then
        sam_session_is_current; return $?
    fi
    sam_session_lock || return 1
    local rc=0 serial=${sam_launch_serial:-0} changed=0
    if ! sam_session_is_current; then rc=1
    elif [[ "$1" != "$sam_last_phase" || "$1" == loading ]]; then
        [[ "$1" != loading ]] || serial=$((serial+1))
        if sam_session_write_phase "$1" "$serial"; then changed=1; else rc=1; fi
    fi
    sam_session_unlock
    if ((changed)) && declare -F sam_diagnostic >/dev/null; then
        sam_diagnostic phase_change "phase=$1 launch=$serial core=${core:-${nextcore:-}}" "$sam_owner" || true
    fi
    return "$rc"
}

sam_cleanup_preparation() {
    if sam_cancel_preparation; then sam_exit_trace preparation_cancelled; return 0; fi
    local reason="${sam_job_error:-Preparation cleanup failed}"
    sam_cleanup_failure_record sam_worker "$reason" || true
    printf '%s\n' "$reason" >> "$sam_session/cleanup-error"
    return 1
}

sam_record_empty_autostart() {
    # Called only by the foreground selection-failure branch, never EXIT/TERM
    # cleanup. The CLI rechecks owner identity and the selection snapshots.
    [[ "$BASHPID" == "$$" && -e "$sam_session/alive" && -r "$sam_session/outcome" ]] || return 1
    local -a outcome=()
    mapfile -t outcome < "$sam_session/outcome" || return 1
    [[ "${#outcome[@]}" == 2 && "${outcome[0]}" == reason=no_eligible_games &&
        "${outcome[1]}" == "revision=$sam_revision" ]] || return 1
    sam_session_is_current || return 1
    python3 "$mrsampath/sam/autostart.py" record --session "$sam_session" \
        --mode "$SAM_MODE" --target "${SAM_TARGET_CORE:-}" --ini "$samini_file" \
        --lists "$gamelistpath" --root "$mrsampath" --runtime "$mrsamtmp" --owner "$sam_owner" --revision "$sam_revision"
}

# Preserve selection before explicit cleanup removes records or changes phase.
sam_session_exit_snapshot() {
    [[ "${sam_exit_snapshot_taken:-0}" != 1 ]] || return 0
    sam_exit_phase=${sam_last_phase:-}
    sam_exit_core=${core:-${nextcore:-}}
    sam_exit_game=${gamename:-${romname:-}}
    sam_exit_rom=${rompath:-}
    sam_exit_error=
    if [[ -n "${sam_session:-}" && -r "$sam_session/error" ]]; then
        IFS= read -r sam_exit_error < "$sam_session/error" || true
    fi
    sam_exit_snapshot_taken=1
}

sam_session_term() {
    [[ -n "${sam_exit_reason:-}" ]] || sam_exit_reason=term
    exit 0
}

sam_session_exit() {
    local status=${1:-0} cleanup_status=0 reason=${sam_exit_reason:-}
    [[ "$BASHPID" == "$$" ]] || return "$status"
    sam_session_exit_snapshot
    # Error files contain supplied evidence; absence leaves the cause unknown.
    local reported=${sam_exit_reported:-0} error=${sam_exit_error:-}
    if [[ -n "${sam_session:-}" && -r "$sam_session/error" ]]; then
        IFS= read -r error < "$sam_session/error" || true
    fi
    [[ -n "$reason" || -z "$error" ]] || reason=$error
    sam_session_cleanup || cleanup_status=$?
    (( ${sam_diagnostic_cleanup_status:-0} == 0 )) || cleanup_status=$sam_diagnostic_cleanup_status
    if [[ -z "$reason" ]]; then
        if ((status)); then reason=unexplained_exit; else reason=completed; fi
    fi
    if ((status != 0 && reported == 0)) && [[ "$reason" == unexplained_exit ]]; then
        printf 'SAM ERROR: session ended unexpectedly (status %s). Check RAM diagnostics.\n' "$status" >&2
    fi
    if declare -F sam_diagnostic_exit >/dev/null; then
        sam_diagnostic_exit "$status" "$reason" "$cleanup_status" "$sam_exit_phase" \
            "$sam_exit_core" "$sam_exit_game" "$sam_exit_rom" || true
    fi
    return "$status"
}

sam_session_cleanup() {
    [[ "$BASHPID" == "$$" ]] || return 1
    sam_session_exit_snapshot
    local rc=0
    sam_session_cleanup_impl || rc=$?
    ((rc == 0)) || sam_diagnostic_cleanup_status=$rc
    return "$rc"
}

sam_session_cleanup_impl() {
    [[ "${sam_session_cleaned:-0}" != 1 ]] || return 0
    [[ "$BASHPID" == "$$" ]] || return 1
    trap ':' TERM
    sam_exit_trace cleanup_begin
    # Cancel private jobs even if ownership has been replaced. Never restore
    # global audio or stop replacement services without owning the record.
    [[ -z "${sam_session:-}" ]] || rm -f "$sam_session/alive"
    local cleanup_failed=0 reason= pending= critical_rc=0 defer_preparation=0
    if [[ -r "$mrsamtmp/menu-audio-owner" ]]; then
        IFS= read -r pending < "$mrsamtmp/menu-audio-owner" || true
    fi
    if [[ "$pending" == "$sam_owner" ]] && sam_session_is_current; then
        # Preparers cannot launch or change live hardware. Revoking alive above
        # closes publication; reap their process tree while Menu loads instead
        # of keeping the game visible during those /proc scans and grace waits.
        defer_preparation=1
    else
        sam_cleanup_preparation || cleanup_failed=1
    fi
    if ! sam_cancel_launch_job; then
        reason="${sam_job_error:-Launch cleanup failed}"
        sam_cleanup_failure_record sam_launch "$reason" || true
        printf '%s\n' "$reason" >> "$sam_session/cleanup-error"
        cleanup_failed=1
    fi
    sam_exit_trace launch_cancelled
    if ((cleanup_failed)) && sam_session_is_current; then
        # A blocked worker may itself hold the transition lock. Preserve the
        # diagnostic before attempting that bounded lock, without erasing jobs.
        { printf 'owner=%s\n' "$sam_owner"; cat "$sam_session/cleanup-error"; } > "$mrsamtmp/last-error.log"
    fi
    sam_session_lock || {
        ((defer_preparation == 0)) || sam_cleanup_preparation || true
        trap sam_session_term TERM; return 1;
    }
    if sam_session_is_current; then
        sam_session_write_phase stopping "${sam_launch_serial:-0}" || true
        if ((cleanup_failed)); then
            ((defer_preparation == 0)) || sam_cleanup_preparation || true
            { printf 'owner=%s\n' "$sam_owner"; cat "$sam_session/cleanup-error"; } > "$mrsamtmp/last-error.log"
            sam_session_lock_depth=1; sam_session_unlock
            echo 'SAM: owned-job cleanup incomplete; evidence preserved and audio held.' >&2
            trap sam_session_term TERM
            return 1
        fi
        # Admission refuses a live PID/start even in stopping phase. Release
        # the transition lock before hooks so background helpers cannot inherit
        # it, and run callbacks here so their variables/jobs remain available.
        sam_session_lock_depth=1
        sam_session_unlock
        if [[ -r "$mrsamtmp/menu-audio-owner" ]]; then
            IFS= read -r pending < "$mrsamtmp/menu-audio-owner" || true
        fi
        if [[ "$pending" == "$sam_owner" ]]; then
            # Restore video/INI before loading Menu. Audio services get a small
            # policy handoff; their slow termination follows the launch barrier.
            sam_emit session_stop || critical_rc=$?
            sam_session_stop_done=1
            sam_emit menu_prepare || critical_rc=$?
            sam_exit_trace menu_prepared
            if ((critical_rc == 0)); then
                if sam_session_lock; then
                    pending=
                    if [[ -r "$mrsamtmp/menu-audio-owner" ]]; then
                        IFS= read -r pending < "$mrsamtmp/menu-audio-owner" || true
                    fi
                    if sam_session_is_current && [[ "$pending" == "$sam_owner" ]]; then
                        local quiesced_temp="$sam_session/quiesced.tmp.$BASHPID"
                        printf '%s\n' "$sam_owner" > "$quiesced_temp" && mv -f "$quiesced_temp" "$sam_session/quiesced" || true
                        sam_exit_trace launch_barrier_published
                    fi
                    sam_session_unlock
                fi
            else
                sam_diagnostic_cleanup_status=$critical_rc
                echo 'SAM: critical cleanup hook failed; early Menu handoff disabled.' >&2
            fi
            if ((defer_preparation)); then
                sam_cleanup_preparation || cleanup_failed=1
                defer_preparation=0
            fi
            # Menu can now load while BGM and optional displays finish. The
            # separate receipt proves audio cleanup; quiesced proves only that
            # this owner can no longer load a game.
            if ((cleanup_failed == 0)); then sam_finish_audio_stop menu "$sam_owner" || true
            else sam_emit audio_stop menu || true; fi
            sam_audio_stop_done=1
        fi
        sam_cleanup || true
        if [[ "$sam_audio_stop_done" != 1 ]]; then sam_emit audio_stop || true; sam_audio_stop_done=1; fi
        sam_emit display_shutdown || true
        sam_emit display_exit || true
    else
        sam_session_lock_depth=1
        sam_session_unlock
    fi
    ((defer_preparation == 0)) || sam_cleanup_preparation || cleanup_failed=1
    if ((cleanup_failed)); then trap sam_session_term TERM; return 1; fi
    sam_session_cleaned=1
    sam_exit_trace cleanup_finished
    if [[ -n "${sam_session:-}" && "$sam_session" == "$mrsamtmp/session-$sam_owner" ]]; then
        if [[ -f "$sam_session/error" ]] && sam_session_is_current; then
            { printf 'owner=%s\n' "$sam_owner"; cat "$sam_session/error"; cat "$sam_session/preparation.log"; } > "$mrsamtmp/last-error.log"
        fi
        rm -rf -- "$sam_session"
    fi
    # Keep stopping record for Menu audio restoration and startup feedback.
    trap sam_session_term TERM
}
