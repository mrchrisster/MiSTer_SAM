# SPDX-License-Identifier: GPL-3.0-or-later
# One foreground owner. At most one owned background preparation job.
sam_worker_pid= sam_worker_start= sam_worker_group= sam_worker_sid= sam_job_serial=0 sam_generation=0 sam_revision=1
SAM_ACTION=

sam_request_next() {
    SAM_ACTION=next
    sam_emit controls_ready 0
    sam_emit display_publish
}

sam_cancel_preparation() {
    [[ -n "$sam_worker_pid" ]] || return 0
    if [[ -n "${sam_worker_group:-}" ]]; then
        sam_job_cancel "$sam_worker_pid" "$sam_worker_start" "$sam_worker_group" "$sam_worker_sid" || return 1
    elif sam_pid_start "$sam_worker_pid" && [[ "$sam_proc_start" == "$sam_worker_start" ]]; then
        sam_kill_tree "$sam_worker_pid" "$sam_worker_start"
    fi
    if sam_pid_start "$sam_worker_pid" && [[ "$sam_proc_start" == "$sam_worker_start" ]]; then
        sam_job_error='Preparation process did not exit'; return 1
    fi
    wait "$sam_worker_pid" 2>/dev/null || true
    if [[ "${sam_worker_request_fd:-}" =~ ^[0-9]+$ ]]; then exec {sam_worker_request_fd}>&-; fi
    sam_worker_request_fd=
    sam_worker_pid= sam_worker_start= sam_worker_group= sam_worker_sid=
    sam_worker_persistent=0 sam_worker_revision=
}

sam_queue_files() {
    sam_queue=("$sam_session/ready/"*.record)
    [[ -f "${sam_queue[0]}" ]] || sam_queue=()
}

sam_preparation_error() {
    # A generic failure must never inherit the typed final-empty result.
    rm -f -- "$sam_session/outcome"
    printf '%s\n' "$1" > "$sam_session/error.tmp.$BASHPID"
    mv -f "$sam_session/error.tmp.$BASHPID" "$sam_session/error"
}

sam_preparation_discovery_error() {
    local context=
    if [[ -n "${sam_catalog_failure_core:-}" ]]; then
        context=" core=$sam_catalog_failure_core stage=${sam_catalog_failure_stage:-unknown}"
    fi
    [[ -z "${sam_artwork_error_context:-}" ]] || context+=" artwork=[$sam_artwork_error_context]"
    sam_preparation_error "Background catalog discovery failed (status $1)$context"
}

sam_preparation_background_priority() {
    renice 10 -p "$BASHPID" >/dev/null 2>&1 || true
    ionice -c 3 -p "$BASHPID" >/dev/null 2>&1 || true
    if [[ -n "${sam_artwork_service_pid:-}" && "${sam_artwork_service_background:-0}" != 1 ]] &&
        sam_pid_start "$sam_artwork_service_pid" && [[ "$sam_proc_start" == "$sam_artwork_service_start" && "$sam_proc_group" == "$BASHPID" ]]; then
        renice 10 -p "$sam_artwork_service_pid" >/dev/null 2>&1 || true
        ionice -c 3 -p "$sam_artwork_service_pid" >/dev/null 2>&1 || true
        sam_artwork_service_background=1
    fi
}

sam_prepare_batch() {
    sam_preparing=1
    sam_job="$sam_session/jobs/$sam_job_serial"
    mkdir -p "$sam_job/lists" "$sam_job/lists/.checked"
    sam_core_policy_refresh || { sam_preparation_error "$sam_core_reason"; return 0; }
    sam_exit_trace worker_policy_ready
    gamelistpathtmp="$sam_job/lists"
    tmpfile="$sam_job/filter" tmpfilefilter="$sam_job/rating"
    corelistfile="$sam_job/corelist"
    # Candidate records use policy revision; control generation advances only
    # on a real launch and must not invalidate an already prepared successor.
    sam_generation=$sam_revision
    local c record path i attempts rc existing reset number priority_deferred=0 discovery_done=0 defer_arcade=0 seed_status=
    local enabled_count=${#corelist[@]} prepared=0 bootstrap_core=
    local bootstrap_active=${sam_bootstrap:-0}
    sam_queue_files
    existing=${#sam_queue[@]}
    if [[ "${sam_core_registry_active:-0}" == 1 && "$bootstrap_active" == 1 &&
          "${SAM_MODE:-ALL}" != SINGLE && "${sam_launch_serial:-0}" == 0 ]] && ((existing == 0)); then
        for c in "${sam_allowed_cores[@]}"; do
            [[ "$c" == arcade ]] || continue
            if [[ ! -e "$sam_session/bootstrap-attempted-arcade" ]] &&
                { ! sam_core_registry_read arcade || [[ "$sam_registry_state" == pending ]]; }; then
                : > "$sam_session/bootstrap-attempted-arcade" || return 1
                rc=0; sam_bootstrap_catalog arcade || rc=$?
                printf '%s\n' "$rc" > "$sam_session/bootstrap-attempted-arcade" || return 1
                if ((rc > 1)); then sam_preparation_error 'Arcade startup catalog failed'; return 0; fi
            fi
            if [[ -r "$sam_session/bootstrap-attempted-arcade" ]]; then
                IFS= read -r seed_status < "$sam_session/bootstrap-attempted-arcade" || true
                [[ "$seed_status" != 1 ]] || defer_arcade=1
            fi
            break
        done
    fi
    # The first playable record is startup work. Inherit the owner's ordinary
    # priorities until it is published; queue refill and discovery remain idle.
    if [[ "${sam_launch_serial:-0}" == 0 ]] && ((existing == 0)); then
        priority_deferred=1
    else
        sam_preparation_background_priority
    fi
    # Ready successors take priority over discovery. A slow catalogue scan must
    # not start before a depleted queue has been refilled from available cores.
    if { [[ "${sam_engine_adapter_verified:-0}" != 1 ]] || ((existing >= 2)); } &&
        [[ "${sam_core_registry_active:-0}" == 1 && "${sam_launch_serial:-0}" != 0 ]] &&
        sam_core_registry_read arcade && [[ "$sam_registry_state:$sam_registry_complete" == ready:0 ]]; then
        for c in "${corelist[@]}"; do
            [[ "$c" != arcade ]] || continue
            if sam_core_registry_read "$c" && [[ "$sam_registry_complete" == 1 ]]; then continue; fi
            discovery_done=1
            rc=0; sam_catalog_background_step 1 || rc=$?
            if ((rc > 1)); then sam_preparation_discovery_error "$rc"; return 0; fi
            break
        done
    fi
    for record in "${sam_queue[@]}"; do
        sam_record_read "$record" || continue
        printf '%s\n' "$sam_record_path" >> "$sam_job/reserved-$sam_record_core"
        delete_from_corelist "$sam_record_core" tmp
    done
    (( ${#corelisttmp[@]} )) || corelisttmp=("${sam_allowed_cores[@]}")
    local queue_target=2
    # Publish the first seed immediately, then retain two successors while the
    # worker builds full catalogues. This does not delay first-game consumption.
    if [[ "${sam_engine_adapter_verified:-0}" == 1 && "$bootstrap_active" == 1 ]]; then queue_target=3; fi
    for ((i=existing; i<queue_target; i++)); do
        attempts=0
        while (( attempts < enabled_count + 3 )); do
            [[ -e "$sam_session/alive" ]] || return 0
            if [[ "${sam_core_registry_active:-0}" != 1 && "$bootstrap_active" == 1 && -n "$bootstrap_core" ]]; then nextcore=$bootstrap_core
            else
                rc=0; sam_service choose_core || rc=$?
                if (( rc > 1 )); then sam_preparation_error "${sam_core_reason:-Core selection failed (status $rc)}"; return 0; fi
                if ((rc != 0)); then
                    if [[ "${sam_core_registry_active:-0}" == 1 ]] && ((discovery_done == 0)) && sam_catalog_pending; then
                        discovery_done=1
                        rc=0; sam_catalog_background_step "$defer_arcade" || rc=$?
                        if ((rc > 1)); then sam_preparation_discovery_error "$rc"; return 0; fi
                        continue
                    fi
                    break
                fi
            fi
            c=$nextcore
            rc=0; sam_core_require "$c" || rc=$?
            if (( rc > 1 )); then sam_preparation_error "$sam_core_reason"; return 0; fi
            if (( rc == 1 )); then
                sam_preparation_error "Selector proposed a rejected core: $sam_core_reason"; return 0
            fi
            if [[ "${sam_core_registry_active:-0}" == 1 ]]; then
                if ! sam_core_registry_read "$c" || [[ "$sam_registry_state" != ready ]]; then
                    attempts=$((attempts+1))
                    delete_from_corelist "$c" tmp
                    continue
                fi
            fi
            : >> "$sam_session/consumed/$c"
            : >> "$sam_job/reserved-$c"
            sam_candidate_cover= sam_candidate_reset=no sam_candidate_policy= sam_candidate_mgl= sam_candidate_setname=
            rc=0
            sam_exit_trace "candidate_pick_begin:$c"
            if sam_service pick_candidate "$c"; then
                sam_exit_trace "candidate_pick_end:$c:0"
                sam_exit_trace "candidate_validate_begin:$c"
                if check_rom "$c" && sam_emit candidate_prepare "$c" "$rompath"; then
                    sam_exit_trace "candidate_validate_end:$c:0"
                    number=$((sam_job_serial * 10 + i))
                    printf -v record '%s/ready/%08d.record' "$sam_session" "$number"
                    [[ -e "$sam_session/alive" ]] || return 0
                    [[ "$bootstrap_active" != 1 || "${sam_core_registry_active:-0}" == 1 ]] || bootstrap_core=$c
                    prepared=$((prepared+1))
                    sam_record_write "$record" "$c" "$rompath" "${rompath##*/}" "${sam_candidate_setname:-}" "$sam_revision" || return 1
                    sam_exit_trace "candidate_published:$c"
                    if ((priority_deferred)); then
                        sam_preparation_background_priority
                        priority_deferred=0
                    fi
                    printf '%s\n' "$rompath" >> "$sam_job/reserved-$c"
                    delete_from_corelist "$c" tmp
                    (( ${#corelisttmp[@]} )) || corelisttmp=("${sam_allowed_cores[@]}")
                    break
                else
                    rc=$?
                    if (( rc == 3 )); then
                        sam_preparation_error "Cover download or validation failed for $c"
                        return 0
                    fi
                fi
            else rc=$?; sam_exit_trace "candidate_pick_end:$c:$rc"; fi
            if ((rc == 3)); then
                sam_preparation_error "Artwork catalog or cover download failed for $c"
                return 0
            elif ((rc > 1)); then
                sam_preparation_error "Candidate preparation failed for $c (status $rc)"; return 0
            fi
            attempts=$((attempts+1))
            delete_from_corelist "$c" tmp
            (( ${#corelisttmp[@]} )) || corelisttmp=("${sam_allowed_cores[@]}")
        done
        # Legacy callers retain the one-seed handoff. Resident workers continue
        # filling successors; each record is visible immediately on publication.
        if [[ "${sam_engine_adapter_verified:-0}" != 1 && "${sam_core_registry_active:-0}" == 1 && "$bootstrap_active" == 1 ]] && ((prepared > 0)); then break; fi
    done
    # Extend discovery only after filling the small ready queue. This job exits
    # after one catalog; the next event schedules more work, never another daemon.
    rc=0
    if ((discovery_done == 0)); then sam_catalog_background_step "$defer_arcade" || rc=$?; fi
    if ((rc > 1)); then
        sam_preparation_discovery_error "$rc"; return 0
    fi
    sam_queue_files
    if (( prepared == 0 && existing == 0 && ${#sam_queue[@]} == 0 )) && ! sam_catalog_pending; then
        [[ -e "$sam_session/alive" ]] || return 0
        # Publish typed data before the error observed by the foreground. Only
        # exhausted discovery can suppress automatic retries; other failures
        # and cancelled workers have no final-empty outcome.
        printf 'reason=no_eligible_games\nrevision=%s\n' "$sam_revision" > "$sam_session/outcome.tmp.$BASHPID" &&
            mv -f -- "$sam_session/outcome.tmp.$BASHPID" "$sam_session/outcome" || return 1
        printf 'No eligible games found for the enabled cores and filters\n' > "$sam_session/error.tmp.$BASHPID" &&
            mv -f -- "$sam_session/error.tmp.$BASHPID" "$sam_session/error"
    fi
}

# Legacy/source-only callers retain one-shot preparation and its completion
# receipt. Warm adapters keep the same registered worker for a policy revision.
sam_prepare_worker() {
    trap - EXIT INT
    trap 'exit 0' TERM
    local rc=0
    sam_prepare_batch || rc=$?
    printf done > "$sam_job/done"
    return "$rc"
}

sam_prepare_persistent() {
    local request serial revision launch bootstrap rotation extra c allowed
    local policy_revision=$sam_revision last_serial=0
    trap 'exit 0' TERM
    while IFS= read -r -n 4097 request; do
        [[ ${#request} -le 4096 && -e "$sam_session/alive" ]] || return 1
        IFS=$'\t' read -r serial revision launch bootstrap rotation extra <<< "$request"
        [[ "$serial" =~ ^[1-9][0-9]{0,11}$ && "$revision" == "$policy_revision" &&
           "$launch" =~ ^[0-9]{1,12}$ && "$bootstrap" == [01] && -z "$extra" &&
           "$rotation" =~ ^[a-z0-9_,]*$ ]] || return 1
        ((serial > last_serial)) || return 1
        corelisttmp=()
        IFS=, read -ra corelisttmp <<< "$rotation"
        for c in "${corelisttmp[@]}"; do
            allowed=0
            for nextcore in "${sam_allowed_cores[@]}"; do [[ "$nextcore" != "$c" ]] || allowed=1; done
            ((allowed)) || return 1
        done
        last_serial=$serial sam_job_serial=$serial sam_launch_serial=$launch sam_bootstrap=$bootstrap
        sam_prepare_batch || { sam_preparation_error 'Persistent preparation failed'; return 1; }
        printf done > "$sam_job/done"
    done
}

sam_prepare_persistent_begin() {
    local saved_term saved_usr1 parent=$BASHPID parent_sid had_monitor=0 registered=0
    local sam_job_stop_pending=0 sam_job_menu_stop_pending=0
    saved_term=$(trap -p TERM); saved_usr1=$(trap -p USR1)
    trap 'sam_job_stop_pending=1' TERM
    trap 'sam_job_menu_stop_pending=1' USR1
    if ! sam_pid_start "$parent"; then
        [[ -z "$saved_term" ]] && trap - TERM || eval "$saved_term"
        [[ -z "$saved_usr1" ]] && trap - USR1 || eval "$saved_usr1"
        return 1
    fi
    parent_sid=$sam_proc_session
    [[ "$-" != *m* ]] || had_monitor=1
    set -m
    coproc SAM_PREPARER {
        set +m
        trap - EXIT INT
        trap 'exit 0' TERM
        trap '' PIPE
        exec 3>&-
        if [[ "${sam_session_lock_fd:-}" =~ ^[0-9]+$ ]]; then exec {sam_session_lock_fd}>&-; fi
        sam_session_lock_holder= sam_session_lock_depth=0
        kill -STOP "$BASHPID"
        sam_worker_persistent=1
        sam_prepare_persistent >&2
    }
    local pid=$SAM_PREPARER_PID pipe_read=${SAM_PREPARER[0]} pipe_write=${SAM_PREPARER[1]}
    ((had_monitor)) || set +m
    local channel_ok=0
    exec {sam_worker_request_fd}>&"$pipe_write" && channel_ok=1
    exec {pipe_read}<&- {pipe_write}>&-
    sam_job_register sam_worker "$pid" "$parent" "$parent_sid" && registered=1
    if ((registered && !channel_ok)); then
        sam_job_cancel "$sam_worker_pid" "$sam_worker_start" "$sam_worker_group" "$sam_worker_sid" || true
        registered=0
    fi
    sam_worker_persistent=1 sam_worker_revision=$sam_revision
    [[ -z "$saved_term" ]] && trap - TERM || eval "$saved_term"
    [[ -z "$saved_usr1" ]] && trap - USR1 || eval "$saved_usr1"
    ((sam_job_menu_stop_pending == 0)) || kill -USR1 "$parent"
    ((sam_job_stop_pending == 0)) || kill -TERM "$parent"
    ((registered))
}

sam_schedule_preparation() {
    if [[ -n "$sam_worker_pid" ]]; then
        if [[ ! -f "$sam_session/jobs/$sam_job_serial/done" ]]; then
            if sam_pid_start "$sam_worker_pid" && [[ "$sam_proc_start" == "$sam_worker_start" ]]; then return 0; fi
            sam_preparation_error 'Preparation worker exited unexpectedly'
        fi
        if [[ "${sam_worker_persistent:-0}" != 1 || "${sam_worker_revision:-}" != "$sam_revision" ]] ||
            ! sam_pid_start "$sam_worker_pid" || [[ "$sam_proc_start" != "$sam_worker_start" ]]; then
            sam_cancel_preparation || { sam_preparation_error "${sam_job_error:-Preparation cleanup failed}"; return 1; }
        fi
    fi
    [[ ! -f "$sam_session/error" ]] || return 0
    sam_queue_files
    # Once all lists are built and the queue is full, no preparation process is
    # needed. The foreground countdown only performs built-in existence checks.
    if (( ${#sam_queue[@]} >= 2 )); then
        sam_catalog_pending || return 0
    fi
    # Retain completion while the full queue needs no refill. Deleting it before
    # this decision makes an idle persistent worker look permanently busy.
    [[ "$sam_job_serial" == 0 ]] || rm -rf -- "$sam_session/jobs/$sam_job_serial"
    sam_job_serial=$((sam_job_serial+1))
    if [[ "${sam_engine_adapter_verified:-0}" == 1 && "${sam_mode:-normal}" != m82 && "${sam_mode:-normal}" != samvideo ]]; then
        [[ "${sam_worker_persistent:-0}" == 1 ]] || sam_prepare_persistent_begin > "$sam_session/preparation.log" 2>&1 || {
            sam_preparation_error 'Persistent preparation registration failed'; return 1;
        }
        local rotation= rotation_core
        for rotation_core in "${corelisttmp[@]}"; do rotation+="${rotation:+,}$rotation_core"; done
        local saved_pipe write_rc=0
        saved_pipe=$(trap -p PIPE)
        trap '' PIPE
        printf '%s\t%s\t%s\t%s\t%s\n' "$sam_job_serial" "$sam_revision" \
            "${sam_launch_serial:-0}" "${sam_bootstrap:-0}" "$rotation" >&"$sam_worker_request_fd" || write_rc=1
        [[ -z "$saved_pipe" ]] && trap - PIPE || eval "$saved_pipe"
        if ((write_rc)); then
            sam_preparation_error 'Persistent preparation request failed'; return 1;
        fi
        return 0
    fi
    # Defer owner termination only across fork/identity registration. Cleanup
    # must never observe a live owned worker without its verified PID/start.
    sam_job_spawn sam_worker sam_prepare_worker > "$sam_session/preparation.log" 2>&1 || {
        sam_preparation_error 'Preparation job registration failed'; return 1;
    }
}

sam_take_prepared() {
    local record c found=0 rule_rc=0
    sam_queue_files
    for record in "${sam_queue[@]}"; do
        if ! sam_record_read "$record" || [[ "$sam_record_owner" != "$sam_owner" || "$sam_record_revision" != "$sam_revision" ]]; then
            rm -f "$record"; continue
        fi
        c=$sam_record_core
        rule_rc=0; sam_core_require "$c" || rule_rc=$?
        if (( rule_rc > 1 )); then sam_preparation_error "$sam_core_reason"; return 2; fi
        if (( rule_rc == 1 )); then rm -f "$record"; continue; fi
        found=0
        for nextcore in "${corelist[@]}"; do [[ "$nextcore" != "$c" ]] || found=1; done
        if (( !found )) || sam_is_excluded "$c" "$sam_record_path"; then rm -f "$record"; continue; fi
        # These are cheap launch-boundary checks; heavy validation was completed
        # by the preparer. ZIP-member existence means its containing ZIP exists.
        if [[ "$c" != amiga ]]; then
            local path="$sam_record_path"
            if [[ ! -f "$path" ]]; then
                while [[ "$path" == */* && "${path,,}" != *.zip ]]; do path="${path%/*}"; done
                [[ "${path,,}" == *.zip && -f "$path" ]] || { rm -f "$record"; continue; }
            fi
        fi
        sam_candidate_cover=$sam_record_cover
        sam_candidate_mgl=$sam_record_mgl
        sam_candidate_setname=$sam_record_setname
        sam_prepared_core=$c sam_prepared_path=$sam_record_path
        sam_emit launch_validate "$c" "$sam_record_path" || return $?
        sam_selected_record=$record
        nextcore=$c rompath=$sam_record_path romname=$sam_record_name gamename="${sam_record_name%.*}" core=$c
        [[ -z "$sam_record_amigapath" ]] || amigapath=$sam_record_amigapath
        [[ -z "$sam_record_amigacore" ]] || amigacore=$sam_record_amigacore
        return 0
    done
    return 1
}

sam_loading_keys() { # coalesce navigation into one pending action; last wins
    local key
    # A 1 ms timeout can expire under CPU load despite queued input, leaving
    # part of a burst for the next game. Allow a short bounded quiet interval.
    while read -r -s -t 0.05 -n 1 key; do
        case "$key" in
            n|N) SAM_ACTION=next ;;
            p|P) SAM_ACTION=previous ;;
        esac
    done
}

run_countdown_timer() {
    sam_publish_phase playing || return 1
    local countdown=$gametimer sam_paused=0 sam_frozen=0
    local start_time=$SECONDS end_time=$((SECONDS + gametimer)) current_rem key last_output=-1 last_schedule=-1
    sam_emit display_publish "$countdown" "$((EPOCHSECONDS + countdown))"
    sam_emit countdown_start
    sam_service timer_begin
    while :; do
        if ((SECONDS != last_schedule)); then sam_config_timer_update; fi
        # Claim queued controls before expiry: a pause already waiting at the
        # deadline must freeze this game rather than advance to its successor.
        sam_emit countdown_tick || return 0
        sam_service timer_tick || return 0
        if (( !sam_paused && gametimer != 0 && SECONDS >= end_time )); then break; fi
        # SECONDS is a builtin elapsed-session clock with whole-second
        # resolution. Zero is an indefinite timer, including after resume.
        current_rem=$((end_time - SECONDS))
        (( gametimer != 0 )) || current_rem=0
        (( !sam_paused )) || current_rem=$sam_frozen
        (( current_rem >= 0 )) || current_rem=0
        if [[ "$current_rem:$sam_paused" != "$last_output" ]]; then
            if (( sam_paused )); then printf 'Paused: %s seconds remaining...\033[0K\r' "$current_rem"
            else printf 'Next in %s seconds...\033[0K\r' "$current_rem"; fi
            last_output="$current_rem:$sam_paused"
        fi
        if (( SECONDS != last_schedule )); then sam_schedule_preparation; last_schedule=$SECONDS; fi
        # A builtin timed read handles keyboard immediately and bounds file
        # command latency. No sleep/date/stat/Python on an idle timer tick.
        # Bash can leave a delivered byte in key when a timed read is
        # interrupted. Handle that byte even if the read status is nonzero.
        read -r -s -t 0.1 -n 1 key || {
            # Timeout is >128; only empty EOF needs a headless backoff.
            [[ $? != 1 || -n "$key" ]] || sleep 0.1
        }
        case "$key" in
            n|N) sam_request_next; return 0 ;;
            p|P) SAM_ACTION=previous; sam_emit controls_ready 0; sam_emit display_publish; return 0 ;;
            m|M) toggle_mute ;;
            '') ;;
            *) sam_service mode_key "$key" || true ;;
        esac
    done
    sam_emit controls_ready 0
    sam_emit display_publish
}

sam_normal_loop() {
    sam_session_begin || return 1
    trap 'tmux detach-client' INT
    sam_emit display_start
    sam_prep || return 1
    disable_bootrom
    local startup_rc=0 startup_error
    sam_emit session_start || startup_rc=$?
    if ((startup_rc != 0));then
        startup_error="Session startup failed (status $startup_rc). Check startup modules: ${SAM_HOOKS[session_start]:-none}"
        sam_preparation_error "$startup_error"
        sam_exit_reported=1
        printf 'SAM ERROR: %s\n' "$startup_error" >&2
        return 1
    fi
    sam_emit display_startup
    corelisttmp=("${corelist[@]}")
    local c have_catalog=0 last_prepare=-1
    if [[ "${sam_core_registry_active:-0}" == 1 ]]; then
        sam_bootstrap=0
        [[ "${SAM_MODE:-ALL}" == SINGLE ]] || sam_bootstrap=1
    else
        for c in "${corelist[@]}"; do [[ ! -s "$gamelistpath/${c}_gamelist.txt" ]] || have_catalog=1; done
        sam_bootstrap=$((1-have_catalog))
    fi
    printf '\n' > "$sam_game_log"
    while :; do
        sam_config_game_boundary || return 1
        if ((SECONDS != last_prepare)); then
            sam_schedule_preparation
            last_prepare=$SECONDS
        fi
        sam_replaying=0
        if [[ "$SAM_ACTION" == previous && -f "$sam_session/previous" ]]; then
            cp "$sam_session/previous" "$sam_session/ready/00000000.record"
        fi
        SAM_ACTION=
        sam_publish_phase preparing || return 1
        local take_rc=0
        sam_take_prepared || take_rc=$?
        if (( take_rc != 0 )); then
            if ((take_rc == 3)); then sam_preparation_error 'Prepared cover is unavailable'; fi
            if ((take_rc > 1)) && [[ ! -f "$sam_session/error" ]]; then sam_preparation_error "Selection validation failed (status $take_rc)"; fi
            if [[ -f "$sam_session/error" ]]; then
                local error; IFS= read -r error < "$sam_session/error"
                sam_exit_reported=1
                printf '\nSAM ERROR: %s. Current game retained; restart SAM to retry.\n' "$error" >&2
                sam_record_empty_autostart || true
                return 1
            fi
            local key
            read -r -s -t 0.1 -n 1 key || { [[ $? != 1 ]] || sleep 0.1; }
            case "$key" in
                n|N) SAM_ACTION=next ;;
                p|P) SAM_ACTION=previous ;;
                m|M) toggle_mute ;;
                '') ;;
                *) sam_service mode_key "$key" || true ;;
            esac
            continue
        fi
        sam_bootstrap=0
        sam_generation=$((sam_generation+1))
        sam_emit controls_ready 0
        SAM_ACTION=
        if load_core "$nextcore" "$rompath" "${romname%.*}"; then
            if [[ "${sam_selected_record##*/}" != 00000000.record ]]; then
                local commit_rc=0
                sam_service commit "$nextcore" "$rompath" "$sam_record_reset" "$sam_record_policy" || commit_rc=$?
                if ((commit_rc != 0)); then
                    sam_exit_reported=1
                    sam_exit_reason="Launch commit failed (status $commit_rc)"
                    printf '\nSAM ERROR: launch commit failed (status %s).\n' "$commit_rc" >&2
                    return 1
                fi
            fi
            # Keep compatibility replay data, but never source a runtime record.
            [[ ! -f "$sam_session/current" ]] || cp "$sam_session/current" "$sam_session/previous"
            cp "$sam_selected_record" "$sam_session/current"
            rm -f "$sam_selected_record"
            sam_loading_keys
            if [[ "$SAM_ACTION" == next ]]; then SAM_ACTION=; continue; fi
            if [[ "$SAM_ACTION" == previous ]]; then continue; fi
            SAM_ACTION=
            sam_schedule_preparation
            run_countdown_timer || return $?
        else
            local launch_rc=$?
            rm -f "$sam_selected_record"
            if (( launch_rc > 1 )); then
                sam_preparation_error "${sam_core_reason:-Launch infrastructure failed (status $launch_rc)}"
                sam_exit_reported=1
                printf '\nSAM ERROR: launch rejected (status %s): %s\n' "$launch_rc" "${sam_core_reason:-validation failed}" >&2
                return 1
            fi
        fi
    done
}

loop_core() {
    sam_core_session_begin "${1:-}" || { printf 'SAM: %s\n' "$sam_core_reason" >&2; return 1; }
    sam_service session_loop
}
sam_bind session_loop sam_normal_loop
