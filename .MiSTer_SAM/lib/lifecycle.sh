# SPDX-License-Identifier: GPL-3.0-or-later
source "${BASH_SOURCE[0]%/*}/monitor.sh" || return 1
# Extracted compatibility implementation; see reference and attribution.

sam_menu_lock_active() {
    local path="${SAM_MENU_TMP_ROOT:-/tmp/.SAM_menu}/menu.lock" probe_fd held=0
    [[ -e "$path" || -L "$path" ]] || return 1
    [[ -f "$path" && ! -L "$path" ]] || return 0
    exec {probe_fd}< "$path" || return 0
    if flock -x -n "$probe_fd"; then flock -u "$probe_fd"; else held=1; fi
    exec {probe_fd}>&-
    ((held))
}

function sam_start() {
    local core="${1:-}" if_idle=0 command pane_pid= pane_start= start_lock_fd rc=0
    if [[ "$core" == --if-idle ]]; then if_idle=1; shift; core="${1:-}"; fi
    mkdir -p "$mrsamtmp" || return 1
    # Serialize start admission separately from owner cleanup/phase locks.
    # An automatic request must decide under the same lock as manual replacement.
    exec {start_lock_fd}> "$mrsamtmp/session-start.lock" || return 1
    if ! flock -x -w 15 "$start_lock_fd"; then
        exec {start_lock_fd}>&-
        echo 'SAM ERROR: Start admission is busy.' >&2
        return 1
    fi
    if sam_menu_lock_active; then
        flock -u "$start_lock_fd"
        exec {start_lock_fd}>&-
        if ((if_idle)); then
            echo 'SAM automatic start skipped: configuration menu is open.'
            return 0
        fi
        echo 'SAM menu is open. Close it before starting another session.' >&2
        return 1
    fi
    sam_start_admitted "$core" "$if_idle" || rc=$?
    # The tmux client and spawned shell may inherit this open description. Unlock
    # it explicitly so those copies cannot hold admission through gameplay.
    flock -u "$start_lock_fd" || rc=$?
    exec {start_lock_fd}>&-
    ((rc == 0)) || return "$rc"
    [[ -n "$pane_pid" ]] || return 0 # automatic request found an existing owner
    if [[ -n "$core" ]]; then
        sam_pid_start "$pane_pid" && pane_start=$sam_proc_start
        sam_wait_single_start "$core" "$pane_pid" "$pane_start"
    else echo 'SAM session started. Use m monitor to view it.'; fi
}

sam_start_admitted() { # caller holds session-start.lock; outputs caller-local pane_pid/core
    local requested_core=$1 if_idle=$2
    local have_owner=0 occupied_rc=0
    if sam_session_read_owner && sam_pid_start "$sam_session_owner_pid" &&
        [[ "$sam_proc_start" == "$sam_session_owner_start" ]]; then have_owner=1; fi
    if ((if_idle && have_owner)); then
        echo 'SAM is already running; automatic start skipped.'
        return 0
    fi
    if ((have_owner == 0)); then
        # A pane exists before its foreground publishes session-owner. Preserve
        # this startup window for auto requests; manual replacement needs proof
        # of ownership before it can stop that pane safely.
        if timeout 2 tmux has-session -t '=SAM' 2>/dev/null; then
            if ((if_idle)); then
                echo 'SAM startup/session is already occupying tmux; automatic start skipped.'
                return 0
            fi
            echo 'SAM ERROR: Session startup is still publishing its owner; retry shortly.' >&2
            return 1
        else occupied_rc=$?; fi
        if ((occupied_rc != 1)); then
            echo 'SAM ERROR: Could not establish start admission.' >&2
            return 1
        fi
    fi
    core=$requested_core
    if [[ -n "$core" ]]; then
        sam_core_id "$core" || { printf 'SAM ERROR: %s\n' "$sam_core_reason" >&2; return 1; }
        core=$sam_core_id_result
    fi
    if [[ -n "$core" ]]; then printf 'Starting SAM for %s (single core)...\n' "${CORE_PRETTY[$core]}"
    else printf 'Starting SAM...\n'; fi
    if [[ "${sam_module_config_dirty:-0}" == 1 ]]; then
        bash "${SAM_ENTRY:-$misterpath/Scripts/MiSTer_SAM_on.sh}" validate_start "$core" || return 1
    else
        sam_core_session_begin "$core" || { printf 'SAM ERROR: %s\n' "$sam_core_reason" >&2; return 1; }
    fi
    env_check || return 1
    there_can_be_only_one || return 1
    # An admitted, validated manual start requests one fresh attempt, including
    # reuse of safely validated catalog caches. Conditional starts retain the
    # RAM guard until settings or persistent catalog identity changes.
    if ((if_idle == 0)); then rm -f -- "$mrsamtmp/autostart-empty.json" || return 1; fi
    # Daemons must not retain admission if this launcher is cancelled before
    # its explicit unlock. Close only the inherited copy in spawned children.
    (exec {start_lock_fd}>&-; mcp_start)
    printf -v command 'exec %q loop_core %q' "${SAM_ENTRY:-$misterpath/Scripts/MiSTer_SAM_on.sh}" "$core"
    pane_pid=$(exec {start_lock_fd}>&-; tmux new-session -P -F '#{pane_pid}' -d -x 180 -y 40 -n 'SAM: next / previous / mute' -s SAM "$command") || {
        echo 'SAM ERROR: Could not create the SAM session.' >&2; return 1;
    }
    # Hold only for foreground ownership publication, never game preparation.
    # A following manual start can then verify and replace the just-created
    # automatic owner. After this bounded wait, the occupied-pane guard above
    # refuses an unverified late publication instead of issuing a second spawn.
    local check
    for ((check=0;check<60;check++)); do
        if sam_session_read_owner && [[ "$sam_session_owner_pid" == "$pane_pid" ]] &&
            sam_pid_start "$pane_pid" && [[ "$sam_proc_start" == "$sam_session_owner_start" ]]; then
            return 0
        fi
        sleep 0.05
    done
    echo 'SAM foreground started; owner publication is still pending.'

}

sam_wait_single_start() { # report the existing engine's result; no extra scanner
    local target="$1" pid="$2" ticks="$3" line phase owner_pid owner_start reason
    local timeout="${SAM_START_FEEDBACK_TIMEOUT:-180}" elapsed last_notice=0 started=$SECONDS
    [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=180
    while :; do
        phase= owner_pid= owner_start=
        if [[ -r "$mrsamtmp/session-owner" ]]; then
            while IFS= read -r line; do
                case "$line" in pid=*) owner_pid=${line#*=} ;; start=*) owner_start=${line#*=} ;; phase=*) phase=${line#*=} ;; esac
            done < "$mrsamtmp/session-owner"
        fi
        if [[ "$owner_pid" == "$pid" && ( -z "$ticks" || "$owner_start" == "$ticks" ) ]]; then
            ticks=$owner_start
            if [[ -r "$mrsamtmp/session-$pid:$ticks/error" ]]; then
                IFS= read -r reason < "$mrsamtmp/session-$pid:$ticks/error" || true
                printf 'SAM ERROR (%s): %s\n' "$target" "$reason" >&2; return 1
            fi
            if [[ "$phase" == playing || "$phase" == video ]]; then
                if sam_pid_start "$pid" && [[ "$sam_proc_start" == "$ticks" ]]; then
                    printf 'SAM running: %s. Use m monitor to view it.\n' "${CORE_PRETTY[$target]}"; return 0
                fi
            fi
        fi
        if ! sam_pid_start "$pid" || [[ -n "$ticks" && "$sam_proc_start" != "$ticks" ]]; then
            if [[ -r "$mrsamtmp/last-error.log" ]]; then
                IFS= read -r line < "$mrsamtmp/last-error.log" || true
                if [[ "$line" == "owner=$pid:"* && ( -z "$ticks" || "$line" == "owner=$pid:$ticks" ) ]]; then
                    { read -r line; IFS= read -r reason; } < "$mrsamtmp/last-error.log"
                    printf 'SAM ERROR (%s): %s\n' "$target" "$reason" >&2; return 1
                fi
            fi
            printf 'SAM ERROR (%s): Session exited before a game launched; check ROMs, pack prerequisites and filters.\n' "$target" >&2
            return 1
        fi
        elapsed=$((SECONDS-started))
        if ((elapsed >= timeout)); then
            printf 'SAM is still preparing %s. Use m monitor for progress and errors.\n' "${CORE_PRETTY[$target]}"; return 0
        fi
        if ((elapsed-last_notice >= 10)); then
            printf 'Still preparing %s...\n' "${CORE_PRETTY[$target]}"; last_notice=$elapsed
        fi
        sleep 0.2
    done
}


function boot_sleep() { #Wait for rtc sync
	unset end
	end=$((SECONDS+60))
	while [ $SECONDS -lt $end ]; do
		if [[ "$(date +%Y)" -gt "2020" ]]; then
			break
		else
			sleep 1
		fi
	done
}

function there_can_be_only_one() {
    sam_exit_trace stop_owner_begin
    local line old_pid= old_start= expected_pid="${1:-}" expected_start="${2:-}"
    local owned_tmux_session= owned_tmux_server= pane_session pane_pid pane_server panes pane_kill
    sam_exit_reload_path= sam_exit_expected_owner=
    sam_exit_menu_context_owner= sam_exit_menu_request_accepted=0
    sam_exit_menu_initial_main= sam_exit_menu_initial_fifo= sam_exit_menu_initial_marker=
    if sam_cleanup_failure_pending; then
        echo 'SAM: prior owned-job cleanup remains incomplete.' >&2; return 1
    fi
    # The gateway observed no live session. Never adopt one that appeared while
    # this command was initializing, nor remove an unverified tmux session.
    if [[ "$expected_pid:$expected_start" == 0:0 ]]; then
        if sam_session_read_owner && sam_pid_start "$sam_session_owner_pid" &&
            [[ "$sam_proc_start" == "$sam_session_owner_start" ]]; then return 1; fi
        sam_exit_expected_owner=0:0
        return 0
    fi
    if [[ -r "$mrsamtmp/session-owner" ]]; then
        while IFS= read -r line; do
            case "$line" in pid=*) old_pid="${line#*=}" ;; start=*) old_start="${line#*=}" ;; esac
        done < "$mrsamtmp/session-owner"
        if [[ -n "$expected_pid" && ( "$old_pid" != "$expected_pid" || "$old_start" != "$expected_start" ) ]]; then
            return 1
        fi
        if [[ -n "$expected_pid" ]]; then
            sam_pid_start "$old_pid" && [[ "$sam_proc_start" == "$old_start" ]] || return 1
        fi
        if [[ "${sam_exit_menu:-0}" == 1 ]]; then
            # Keep the pre-request generation even if Menu is dispatched while
            # the stopped owner finishes optional cleanup.
            sam_menu_delivery_begin
            sam_exit_menu_context_owner="$old_pid:$old_start"
            sam_exit_menu_initial_main=$sam_menu_initial_main
            sam_exit_menu_initial_fifo=$sam_menu_initial_fifo
            sam_exit_menu_initial_marker=$sam_menu_initial_marker
            # Publish before TERM: the owner's EXIT trap must leave audio muted.
            printf '%s:%s\n' "$old_pid" "$old_start" > "$mrsamtmp/menu-audio-owner.tmp.$BASHPID" &&
                mv -f "$mrsamtmp/menu-audio-owner.tmp.$BASHPID" "$mrsamtmp/menu-audio-owner" || return 1
            rm -f "$mrsamtmp/menu-audio-complete"
        fi
        if sam_pid_start "$old_pid" && [[ "$sam_proc_start" == "$old_start" && "$old_pid" != "$$" ]]; then
            # Resolve SAM once while its foreground PID/start is verified.
            # A session ID survives renames and cannot select a replacement SAM
            # created in the same tmux server after this owner exits.
            panes=$(timeout 2 tmux list-panes -t '=SAM' -F '#{session_id} #{pane_pid} #{pid}' 2>/dev/null) || panes=
            while read -r pane_session pane_pid pane_server; do
                [[ "$pane_session" =~ ^\$[0-9]+$ && "$pane_pid" == "$old_pid" && "$pane_server" =~ ^[1-9][0-9]*$ ]] || continue
                owned_tmux_session=$pane_session owned_tmux_server=$pane_server
                break
            done <<< "$panes"
            # Capture the actual owned launch command before EXIT deletes its
            # session. A global SAM_Game.mgl can belong to a previous console.
            if [[ -r "$mrsamtmp/session-$old_pid:$old_start/launch-path" ]]; then
                IFS= read -r sam_exit_reload_path < "$mrsamtmp/session-$old_pid:$old_start/launch-path" || true
            fi
            if sam_pid_start "$old_pid" && [[ "$sam_proc_start" == "$old_start" ]]; then
                kill -TERM "$old_pid"
                sam_exit_trace owner_signalled
            else
                # The process disappeared/reused its PID while tmux was queried.
                # Neither that process nor an unverified pane may be signalled.
                owned_tmux_session=
            fi
            # Menu is dispatched as soon as the launch barrier is ready. Allow
            # its remaining audio/owned-job cleanup to finish without treating
            # the old five-second startup budget as a Menu delivery deadline.
            # SECONDS truncates: the extra second preserves the full budget.
            local cleanup_budget=5
            [[ "${sam_exit_menu:-0}" != 1 ]] || cleanup_budget=10
            local deadline=$((SECONDS+cleanup_budget+1))
            while sam_pid_start "$old_pid" && [[ "$sam_proc_start" == "$old_start" ]] && ((SECONDS<deadline)); do
                if [[ "${sam_exit_menu:-0}" == 1 ]]; then sam_menu_dispatch_quiesced_owner "$old_pid" "$old_start"; fi
                sleep 0.1
            done
            if sam_pid_start "$old_pid" && [[ "$sam_proc_start" == "$old_start" ]]; then
                echo 'SAM: Previous session did not finish stopping before the timeout.' >&2; return 1
            fi
        fi
    fi
    if [[ -n "$expected_pid" && -z "$old_pid" ]]; then return 1; fi
    if sam_cleanup_failure_pending; then
        echo 'SAM: owned-job cleanup failed; Menu/start request refused.' >&2; return 1
    fi
    # A replacement started during cleanup must not lose its pane.
    if [[ -n "$expected_pid" ]] && [[ -r "$mrsamtmp/session-owner" ]]; then
        local current_pid= current_start=
        while IFS= read -r line; do
            case "$line" in pid=*) current_pid="${line#*=}" ;; start=*) current_start="${line#*=}" ;; esac
        done < "$mrsamtmp/session-owner"
        [[ "$current_pid" == "$expected_pid" && "$current_start" == "$expected_start" ]] || return 1
    fi
    if [[ -n "$owned_tmux_session" ]]; then
        # Session IDs can be reused after a tmux server restart. Verify server
        # identity and pane PID in the same connection that removes this ID.
        printf -v pane_kill "kill-session -t '%s'" "$owned_tmux_session"
        timeout 2 tmux if-shell -F -t "$owned_tmux_session" \
            "#{&&:#{==:#{pid},$owned_tmux_server},#{==:#{pane_pid},$old_pid}}" \
            "$pane_kill" 2>/dev/null || true
    fi
    if [[ "$old_pid:$old_start" =~ ^[1-9][0-9]*:[0-9]+$ ]]; then
        sam_exit_expected_owner="$old_pid:$old_start"
    else sam_exit_expected_owner=0:0; fi
}

sam_menu_dispatch_quiesced_owner() {
    [[ "${sam_exit_menu_request_accepted:-0}" != 1 ]] || return 0
    local expected="$1:$2" session="$mrsamtmp/session-$1:$2" tag=
    local line pid= ticks= phase= pending= accepted=0
    [[ "${sam_exit_menu_context_owner:-}" == "$expected" && -r "$session/quiesced" && ! -e "$session/alive" ]] || return 0
    IFS= read -r tag < "$session/quiesced" || return 0
    [[ "$tag" == "$expected" ]] || return 0
    sam_session_lock || return 0
    if [[ -r "$mrsamtmp/session-owner" ]]; then
        while IFS= read -r line; do
            case "$line" in pid=*) pid=${line#*=} ;; start=*) ticks=${line#*=} ;; phase=*) phase=${line#*=} ;; esac
        done < "$mrsamtmp/session-owner"
    fi
    IFS= read -r pending < "$mrsamtmp/menu-audio-owner" 2>/dev/null || pending=
    if [[ "$pid:$ticks" == "$expected" && "$phase" == stopping && "$pending" == "$expected" && ! -e "$session/alive" ]] &&
       sam_pid_start "$pid" && [[ "$sam_proc_start" == "$ticks" ]] && ! sam_cleanup_failure_pending; then
        IFS= read -r tag < "$session/quiesced" || tag=
        if [[ "$tag" == "$expected" ]] && timeout 0.2s sh -c "echo 'load_core /media/fat/menu.rbf' > /dev/MiSTer_cmd"; then
            accepted=1
        fi
    fi
    sam_session_unlock
    if ((accepted)); then sam_exit_menu_request_accepted=1; sam_exit_trace menu_command_accepted; fi
    return 0
}


function kill_all_sams() {
    there_can_be_only_one
}


function exit_sam() { # exit_sam [menu|game]
    local exit_mode=${1:-menu} # Default to menu if no argument
    local own_exit=0 line owner_pid= owner_start=
    if [[ "$exit_mode" == game && "${sam_owner:-}" == "$$:"* &&
          "${sam_session:-}" == "$mrsamtmp/session-${sam_owner:-}" ]]; then
        # Monitor Play runs inside the owner, rather than through the external
        # stop command. Validate/capture first, then cancel jobs before reload.
        [[ -r "$mrsamtmp/session-owner" ]] || return 1
        while IFS= read -r line; do
            case "$line" in pid=*) owner_pid=${line#*=} ;; start=*) owner_start=${line#*=} ;; esac
        done < "$mrsamtmp/session-owner"
        [[ "$owner_pid:$owner_start" == "$sam_owner" ]] || return 1
        sam_pid_start "$$" && [[ "$sam_proc_start" == "$owner_start" ]] || return 1
        sam_exit_reload_path=
        if [[ -r "$sam_session/launch-path" ]]; then
            IFS= read -r sam_exit_reload_path < "$sam_session/launch-path" || true
        fi
        sam_exit_reason=keep_game
        own_exit=1
    fi
    local external_lock=0 exit_rc=0 expected=${sam_exit_expected_owner:-0:0}
    if ((own_exit == 0)); then
        # Stopping the old owner and finalizing its display/audio are separate
        # operations. Admission must remain locked across the latter operation.
        sam_session_lock || return 1
        external_lock=1
        if sam_session_read_owner; then
            if sam_pid_start "$sam_session_owner_pid" &&
                [[ "$sam_proc_start" == "$sam_session_owner_start" ]]; then
                sam_session_unlock; return 1
            fi
            if [[ "$expected" != 0:0 && "$expected" != "$sam_session_owner_pid:$sam_session_owner_start" ]]; then
                sam_session_unlock; return 1
            fi
            # A retry after an owner died can finish its pending audio cleanup.
            # Admission is locked and liveness was checked above; never adopt
            # a new live session or an unrelated stale receipt.
            if [[ "$expected" == 0:0 && -r "$mrsamtmp/menu-audio-owner" ]]; then
                local pending_retry=
                IFS= read -r pending_retry < "$mrsamtmp/menu-audio-owner" || true
                if [[ "$pending_retry" == "$sam_session_owner_pid:$sam_session_owner_start" ]]; then
                    sam_exit_expected_owner=$pending_retry
                fi
            fi
        elif [[ "$expected" != 0:0 ]]; then
            sam_session_unlock; return 1
        fi
    fi
    sam_exit_finalize "$exit_mode" "$own_exit" || exit_rc=$?
    if ((external_lock)); then
        # Teardown hooks can leave bounded timeout helpers in the background.
        # Unlock the shared open description before closing our descriptor so
        # inherited copies cannot delay admission to the next session.
        flock -u "$sam_session_lock_fd" || exit_rc=$?
        sam_session_unlock
    fi
    return "$exit_rc"
}

sam_menu_audio_complete() {
    local receipt=
    [[ -n "$1" && -r "$mrsamtmp/menu-audio-complete" ]] || return 1
    IFS= read -r receipt < "$mrsamtmp/menu-audio-complete" || return 1
    [[ "$receipt" == "$1" ]]
}

sam_finish_audio_stop() { # mode, verified owner; completion is independent of Menu dispatch
    local mode=$1 owner=${2:-} temp="$mrsamtmp/menu-audio-complete.tmp.$BASHPID"
    local sam_bgm_policy_owner=$owner
    if [[ "$mode" == menu ]] && sam_menu_audio_complete "$owner"; then return 0; fi
    sam_exit_trace audio_stop_begin
    sam_emit audio_stop "$mode" || return 1
    sam_exit_trace audio_stop_finished
    if [[ "$mode" == menu && -n "$owner" ]]; then
        printf '%s\n' "$owner" > "$temp" && mv -f "$temp" "$mrsamtmp/menu-audio-complete" || return 1
    fi
}

sam_exit_finalize() { # caller owns the live session or holds admission lock
    local exit_mode=$1 own_exit=$2
    sam_emit display_off "$exit_mode"
    if ((own_exit)); then sam_session_cleanup || return 1; fi
    local sam_menu_delivery_active=0 sam_menu_deadline=
    if [[ "$exit_mode" == menu ]]; then
        sam_menu_delivery_active=1 sam_menu_deadline=$((SECONDS+20))
    fi
    # Owned cleanup may have logged an audio-service failure. Retry that
    # idempotent event once while replacement admission is still excluded.
    if ! sam_finish_audio_stop "$exit_mode" "${sam_exit_expected_owner:-}"; then
        echo 'SAM: Audio service cleanup failed; restoration remains pending.' >&2
        return 1
    fi
    if [[ "$exit_mode" == menu ]] && ((SECONDS >= sam_menu_deadline)); then
        echo 'SAM: Audio service cleanup exhausted the Menu completion budget.' >&2
        return 1
    fi
    if [[ "$exit_mode" == game ]]; then sam_restore_audio || return 1; fi

    if [[ "$exit_mode" == "menu" ]]; then
        echo "SAM stopped. Returning to menu..."
        local sam_menu_delivery_active=1 sam_menu_request_accepted=${sam_exit_menu_request_accepted:-0}
        local sam_menu_initial_main=${sam_exit_menu_initial_main:-}
        local sam_menu_initial_fifo=${sam_exit_menu_initial_fifo:-}
        local sam_menu_initial_marker=${sam_exit_menu_initial_marker:-}
        local sam_menu_bound_main= sam_menu_bound_fifo= sam_menu_bound_marker=
        # One budget covers both Menu convergence and audio acknowledgement.
        # A failed two-second restore must not multiply into 150 full waits.
        if [[ "${sam_exit_menu_context_owner:-}" != "${sam_exit_expected_owner:-}" || -z "${sam_exit_menu_context_owner:-}" ]]; then
            sam_menu_request_accepted=0
            sam_menu_delivery_begin
        fi
        local attempt check
        for ((attempt=0;attempt<15 && SECONDS<sam_menu_deadline;attempt++)); do
            if ! sam_menu_exit_guard; then
                echo 'SAM: Session changed; Menu request cancelled.' >&2
                return 1
            fi
            # Give the carried early request its first observation interval
            # before sending another load to an already-changing Main process.
            if ((attempt != 0 || sam_menu_request_accepted == 0)); then
                # Once Menu is fresh, leave Main running so its delayed volume
                # save can finish. Audio failure alone must not reload the core.
                if [[ -z "$sam_menu_bound_main" ]] || ! sam_menu_delivery_ready; then
                    if timeout 1s sh -c "echo 'load_core /media/fat/menu.rbf' > /dev/MiSTer_cmd"; then
                        sam_menu_request_accepted=1
                    fi
                fi
            fi
            ((SECONDS < sam_menu_deadline)) || break
            # The same Menu path serves MCP, CLI and menu commands. Poll the
            # cheap core marker every 100 ms, send load commands once a second.
            for ((check=0;check<10;check++)); do
                ((SECONDS < sam_menu_deadline)) || break
                sleep 0.1
                ((SECONDS < sam_menu_deadline)) || break
                sam_menu_exit_guard || return 1
                if sam_menu_audio_restore; then return 0; fi
                ((SECONDS < sam_menu_deadline)) || break
            done
        done
        if [[ -n "$sam_menu_bound_main" ]]; then
            echo 'SAM: Menu was observed, but audio restoration did not complete before the deadline; pending state retained.' >&2
        else
            echo 'SAM: Menu completion timed out; audio restoration remains pending.' >&2
        fi
        return 1
    elif [[ "$exit_mode" == "game" ]] && [[ "${mute}" == "core" ]]; then
        # BGM mode: _volume.cfg was bind-mounted to mute the core. MiSTer only
        # reads it on core load, so we must unmount it before reloading.
        # The owned session was stopped and its volume mounts removed before
        # this command. Reload only the launch path captured from that owner.
        local reload_path="${sam_exit_reload_path:-}"
        if [ -n "$reload_path" ]; then
            # Owner cleanup restored the real volume files before this reload.
            echo "SAM stopped. Reloading game with restored volume..."
            timeout 1s bash -c 'printf "load_core %s\n" "$1" > /dev/MiSTer_cmd' _ "$reload_path"
            # The verified owner's EXIT trap already stopped its services.
        else
            echo 'SAM: No verified game launch path; reload skipped.' >&2
            return 1
        fi
    else
        # Normal exit-to-game (no BGM mute): just clean up and leave the game running.
        sam_cleanup
        sam_emit display_shutdown
    fi
}

sam_unmute_owner() { # verified PID/start, or 0/0 if gateway observed no owner
    local expected="${1:-}:${2:-}" rc=1
    [[ "$expected" =~ ^[0-9]+:[0-9]+$ ]] || return 1
    sam_session_lock || return 1
    if sam_session_read_owner && sam_pid_start "$sam_session_owner_pid" &&
        [[ "$sam_proc_start" == "$sam_session_owner_start" ]]; then
        [[ "$expected" != "$sam_session_owner_pid:$sam_session_owner_start" ]] || rc=0
    elif [[ "$expected" == 0:0 ]]; then rc=0; fi
    if ((rc == 0)); then
        # Bounded restore while admission/phase publication is locked. A late
        # replacement cannot be unmuted by an input for the preceding session.
        sam_restore_audio || rc=$?
    fi
    sam_session_unlock
    return "$rc"
}

function exit_sam_fast() {
    sam_emit display_off
    # Menu dispatch may precede audio termination. Retry a failed owner hook
    # once, and leave protection in place if the service is still not settled.
    sam_finish_audio_stop menu "${sam_exit_expected_owner:-}"
}

sam_menu_exit_guard() {
    local line pid= ticks= pending=
    if [[ -r "$mrsamtmp/session-owner" ]]; then
        while IFS= read -r line; do
            case "$line" in pid=*) pid=${line#*=} ;; start=*) ticks=${line#*=} ;; esac
        done < "$mrsamtmp/session-owner"
    fi
    if [[ -r "$mrsamtmp/menu-audio-owner" ]]; then
        IFS= read -r pending < "$mrsamtmp/menu-audio-owner" || return 1
        [[ -z "$pid" || "$pid:$ticks" == "$pending" ]] || return 1
    fi
    if sam_pid_start "$pid" && [[ "$sam_proc_start" == "$ticks" ]]; then return 1; fi
    [[ -z "$pending" ]] || sam_menu_audio_complete "$pending" || return 1
    return 0
}

sam_menu_main_identity() {
    local pid exe
    sam_menu_main_key=
    pid=$(pidof MiSTer) || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    exe=$(readlink "/proc/$pid/exe") || return 1
    [[ "$exe" == "${misterpath%/}/MiSTer" ]] || return 1
    sam_pid_start "$pid" || return 1
    sam_menu_main_key="$pid:$sam_proc_start"
}

sam_menu_delivery_begin() {
    # Capture before requesting Menu. CORENAME can still say MENU while the
    # preceding core is loading; its replacement FIFO appears even later.
    sam_menu_initial_main=
    sam_menu_initial_fifo=$(stat -Lc '%d:%i|%z' "${SAM_COMMAND_FIFO:-/dev/MiSTer_cmd}" 2>/dev/null) || sam_menu_initial_fifo=
    sam_menu_initial_marker=$(stat -Lc '%d:%i|%z' "${SAM_CORENAME_FILE:-/tmp/CORENAME}" 2>/dev/null) || sam_menu_initial_marker=
    if sam_menu_main_identity; then sam_menu_initial_main=$sam_menu_main_key; fi
    return 0
}

sam_menu_main_has_fifo() { # verified Main identity and current FIFO device/inode
    local descriptors object path
    descriptors=$(stat -Lc '%d:%i %n' "/proc/${sam_menu_snapshot_main%%:*}/fd/"* 2>/dev/null) || true
    while read -r object path; do
        [[ "$object" != "${sam_menu_snapshot_fifo%%|*}" ]] || return 0
    done <<< "$descriptors"
    return 1
}

sam_menu_delivery_snapshot() {
    local core= identities fifo=${SAM_COMMAND_FIFO:-/dev/MiSTer_cmd}
    local marker=${SAM_CORENAME_FILE:-/tmp/CORENAME}
    sam_menu_snapshot_main= sam_menu_snapshot_fifo= sam_menu_snapshot_marker=
    [[ -p "$fifo" && -r "$marker" ]] || return 1
    IFS= read -r core < "$marker" || true
    [[ "${core%$'\r'}" == MENU ]] || return 1
    sam_menu_main_identity || return 1
    sam_menu_snapshot_main=$sam_menu_main_key
    identities=$(stat -Lc '%d:%i|%z' "$fifo" "$marker" 2>/dev/null) || return 1
    [[ "$identities" == *$'\n'* ]] || return 1
    sam_menu_snapshot_fifo=${identities%%$'\n'*}
    sam_menu_snapshot_marker=${identities#*$'\n'}
    [[ "$sam_menu_snapshot_marker" != *$'\n'* ]] || return 1
    # A new Menu process publishes CORENAME before opening its new FIFO.
    # Require that exact process to hold this inode, not a predecessor's FIFO.
    sam_menu_main_has_fifo || return 1
    [[ "$(stat -Lc '%d:%i|%z' "$fifo" "$marker" 2>/dev/null)" == "$identities" ]] || return 1
    sam_pid_start "${sam_menu_snapshot_main%%:*}" &&
        [[ "$sam_proc_start" == "${sam_menu_snapshot_main#*:}" ]] || return 1
    IFS= read -r core < "$marker" || true
    [[ "${core%$'\r'}" == MENU ]]
}

sam_menu_delivery_ready() {
    [[ "$sam_menu_request_accepted" == 1 ]] || return 1
    sam_menu_delivery_snapshot || return 1
    [[ -z "$sam_menu_initial_main" || "$sam_menu_snapshot_main" != "$sam_menu_initial_main" ]] || return 1
    [[ -z "$sam_menu_initial_fifo" || "$sam_menu_snapshot_fifo" != "$sam_menu_initial_fifo" ]] || return 1
    [[ -z "$sam_menu_initial_marker" || "$sam_menu_snapshot_marker" != "$sam_menu_initial_marker" ]] || return 1
    sam_menu_bound_main=$sam_menu_snapshot_main
    sam_menu_bound_fifo=$sam_menu_snapshot_fifo
    sam_menu_bound_marker=$sam_menu_snapshot_marker
}

sam_menu_delivery_still_current() {
    sam_menu_delivery_snapshot || return 1
    [[ "$sam_menu_snapshot_main" == "$sam_menu_bound_main" &&
       "${sam_menu_snapshot_fifo%%|*}" == "${sam_menu_bound_fifo%%|*}" &&
       "$sam_menu_snapshot_marker" == "$sam_menu_bound_marker" ]]
}

sam_menu_audio_restore() { # [expected PID start]; never restore a replacement's audio
    local pending= line pid= ticks= core= expected="${1:-}:${2:-}"
    if [[ -r "$mrsamtmp/menu-audio-owner" ]]; then
        IFS= read -r pending < "$mrsamtmp/menu-audio-owner" || return 1
    fi
    [[ "$expected" == : || ( -n "$pending" && "$pending" == "$expected" ) ]] || return 1
    if [[ -r "$mrsamtmp/session-owner" ]]; then
        while IFS= read -r line; do
            case "$line" in pid=*) pid=${line#*=} ;; start=*) ticks=${line#*=} ;; esac
        done < "$mrsamtmp/session-owner"
    fi
    [[ -z "$pending" || "$pid:$ticks" == "$pending" ||
       ( "$expected" == : && -z "$pid" && -z "$ticks" ) ]] || return 1
    # An alive owner may still launch. Never unmute it even if CORENAME is stale.
    if sam_pid_start "$pid" && [[ "$sam_proc_start" == "$ticks" ]]; then return 1; fi
    [[ -z "$pending" ]] || sam_menu_audio_complete "$pending" || return 1
    [[ -r "${SAM_CORENAME_FILE:-/tmp/CORENAME}" ]] || return 1
    IFS= read -r core < "${SAM_CORENAME_FILE:-/tmp/CORENAME}" || true
    core=${core%$'\r'}
    [[ "${core,,}" == menu ]] || return 1
    if [[ "${sam_menu_delivery_active:-0}" == 1 ]]; then sam_menu_delivery_ready || return 1; fi
    sam_restore_audio || return 1
    if [[ "${sam_menu_delivery_active:-0}" == 1 ]]; then sam_menu_delivery_still_current || return 1; fi
    rm -f "$mrsamtmp/menu-audio-owner" "$mrsamtmp/menu-audio-complete"
    sam_exit_trace audio_restored
}

sam_restore_audio() {
    local target source kind rest failed=0
    # Verify RAM inode ownership even when FAT reports a different path spelling.
    while IFS=' ' read -r source target kind rest; do
        target=${target//\\040/ }; target=${target//\\011/$'\t'}; target=${target//\\134/\\}
        [[ "$target" == *_volume.cfg ]] || continue
        sam_core_volume_source_for_target "$target" || continue
        sam_core_volume_owned "$target" "$sam_core_volume_resolved" || continue
        sam_audio_restore_in_budget || return 1
        if ! timeout 1s umount -l "$target" >/dev/null 2>&1; then failed=1
        elif sam_volume_is_mounted "$target"; then failed=1; fi
    done < "${SAM_MOUNTS_FILE:-/proc/mounts}"
    ((failed == 0)) || return 1
    # Restore only SAM's actual global bind/pending delivery. Core-only mute
    # never authorizes a global volume command, regardless of the current INI.
    global_unmute
}











function sam_prep() {
    mkdir -p "$mrsamtmp/SAM_config" "$misterpath/video"
    local pending=
    if [[ -n "${sam_owner:-}" && -r "$mrsamtmp/menu-audio-owner" ]]; then
        IFS= read -r pending < "$mrsamtmp/menu-audio-owner" || true
        # A failed old Menu return cannot defer a replacement's eventual cleanup.
        [[ "$pending" == "$sam_owner" ]] || rm -f "$mrsamtmp/menu-audio-owner"
    fi
    [[ "$kids_safe" != yes ]] || rating=kids
    [[ "$mute" == no ]] || only_mute_if_needed
    sam_emit session_setup
}


function sam_cleanup() {
    [[ "${sam_cleanup_done:-0}" != 1 ]] || return 0
    sam_cleanup_done=1
	# Clean up by umounting any mount binds
	#[ -f "${configpath}/Volume.dat" ] && [ ${mute} == "yes" ] && rm "${configpath}/Volume.dat"
    local defer_audio=0 pending=
    if [[ -n "${sam_owner:-}" && -r "$mrsamtmp/menu-audio-owner" ]]; then
        IFS= read -r pending < "$mrsamtmp/menu-audio-owner" || true
        [[ "$pending" != "$sam_owner" ]] || defer_audio=1
    fi
    if ((defer_audio == 0)); then sam_restore_audio || true; fi
    local mount_index
    for ((mount_index=${#SAM_OWNED_MOUNTS[@]}-1;mount_index>=0;mount_index--)); do
        if ((defer_audio)) && [[ "${SAM_OWNED_MOUNTS[mount_index]}" == "${configpath%/}/Volume.dat" ||
            "${SAM_OWNED_MOUNTS[mount_index]}" == "${configpath%/}/"*_volume.cfg ]]; then continue; fi
        timeout 3s umount -l "${SAM_OWNED_MOUNTS[mount_index]}" || true
    done
    SAM_OWNED_MOUNTS=()

    if [[ "${sam_session_stop_done:-0}" != 1 ]]; then
        sam_emit session_stop
        sam_session_stop_done=1
    fi
	samdebug "Cleanup done."
}

function sam_enable() { # Enable autoplay
	echo -n " Enabling MiSTer SAM Autoplay..."

	# Awaken daemon
	# Check for and delete old fashioned scripts to prefer /media/fat/linux/user-startup.sh
	# (https://misterfpga.org/viewtopic.php?p=32159#p32159)

	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	fi

	# Add new startup way
	if [ ! -e "${userstartup}" ] && [ -e /etc/init.d/S99user ]; then
		if [ -e "${userstartuptpl}" ]; then
			echo "Copying ${userstartuptpl} to ${userstartup}"
			cp "${userstartuptpl}" "${userstartup}"
			sleep 1
		else
			echo "Building ${userstartup}"
		fi
	fi
	if [ "$(grep -ic "mister_sam" ${userstartup})" = "0" ]; then
		echo -e "Adding SAM to ${userstartup}\n"
		echo -e "\n# Startup MiSTer_SAM - Super Attract Mode" >>${userstartup}
		echo -e "[[ -e ${mrsampath}/MiSTer_SAM_init ]] && ${mrsampath}/MiSTer_SAM_init \$1 &" >>"${userstartup}"
	fi
	echo "SAM install complete."
	echo -e "\n\n\n"
	source "${samini_file}"
	echo -ne "\e[1m" SAM will start ${samtimeout} sec. after boot"\e[0m"
	if [ "${menuonly,,}" == "yes" ]; then
		echo -ne "\e[1m" in the main menu"\e[0m"
	else
		echo -ne "\e[1m" whenever controller is not in use"\e[0m"
	fi
	echo -e "\e[1m" and show each game for ${gametimer} sec."\e[0m"
	echo -ne "\e[1m" First run will take some time to compile game list... please wait."\e[0m"
	echo -e "\n\n\n"
	sleep 5

	"${misterpath}/Scripts/MiSTer_SAM_on.sh" start

	exit
}

function sam_disable() { # Disable autoplay

	echo -n " Disabling SAM autoplay..."
	# Clean out existing processes to ensure we can update

	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	fi

	there_can_be_only_one
	sed -i '/MiSTer_SAM/d' ${userstartup}
	sync
	echo " Done."
}

function env_check() {
	# Check if we've been installed
	if [ ! -f "${mrsampath}/samindex" ]; then
		echo " SAM required files not found."
		echo " Installing now."
		sam_update_assets autoconfig
		echo " Setup complete."
	fi
	#Probably offline or update_all install
	if [ ! -f "${configpath}/inputs/GBA_input_1234_5678_v3.map" ]; then
		if [ -f "${mrsampath}/inputs/GBA_input_1234_5678_v3.map" ]; then
			cp "${mrsampath}/inputs/GBA_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/NES_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/TGFX16_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/SATURN_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/MegaCD_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/NEOGEO_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
		else
			get_inputmap
		fi
	fi
}
