# SPDX-License-Identifier: GPL-3.0-or-later
# One foreground owner. At most one owned background preparation job.
sam_worker_pid= sam_worker_start= sam_job_serial=0 sam_generation=0 sam_revision=1
SAM_ACTION=

sam_request_next() {
    SAM_ACTION=next
    sam_emit controls_ready 0
    sam_emit display_publish
}

sam_cancel_preparation() {
    [[ -n "$sam_worker_pid" ]] || return 0
    if sam_pid_start "$sam_worker_pid" && [[ "$sam_proc_start" == "$sam_worker_start" ]]; then
        sam_kill_tree "$sam_worker_pid" "$sam_worker_start"
    fi
    wait "$sam_worker_pid" 2>/dev/null || true
    sam_worker_pid= sam_worker_start=
}

sam_session_cleanup() {
    [[ -z "${sam_session:-}" ]] || rm -f "$sam_session/alive"
    sam_publish_phase stopping
    sam_cancel_preparation
    sam_cancel_launch_job
    [[ "${sam_session_cleaned:-0}" != 1 ]] || return 0
    sam_session_cleaned=1
    sam_cleanup
    sam_emit audio_stop
    sam_emit display_shutdown
    sam_emit display_exit
    if [[ -n "${sam_session:-}" && "$sam_session" == "$mrsamtmp/session-$sam_owner" ]]; then
        if [[ -f "$sam_session/error" ]]; then
            { cat "$sam_session/error"; cat "$sam_session/preparation.log"; } > "$mrsamtmp/last-error.log"
        fi
        rm -rf -- "$sam_session"
    fi
}

sam_queue_files() {
    sam_queue=("$sam_session/ready/"*.record)
    [[ -f "${sam_queue[0]}" ]] || sam_queue=()
}

sam_preparation_error() {
    printf '%s\n' "$1" > "$sam_session/error.tmp.$BASHPID"
    mv -f "$sam_session/error.tmp.$BASHPID" "$sam_session/error"
}

sam_prepare_worker() {
    trap - EXIT INT
    trap 'exit 0' TERM
    sam_preparing=1
    sam_job="$sam_session/jobs/$sam_job_serial"
    mkdir -p "$sam_job/lists" "$sam_job/lists/.checked"
    trap 'printf done > "$sam_job/done"' EXIT
    sam_core_policy_refresh || { sam_preparation_error "$sam_core_reason"; return 0; }
    renice 10 -p "$BASHPID" >/dev/null 2>&1 || true
    ionice -c 3 -p "$BASHPID" >/dev/null 2>&1 || true
    gamelistpathtmp="$sam_job/lists"
    tmpfile="$sam_job/filter" tmpfilefilter="$sam_job/rating"
    corelistfile="$sam_job/corelist"
    # Candidate records use policy revision; control generation advances only
    # on a real launch and must not invalidate an already prepared successor.
    sam_generation=$sam_revision
    local c record path i attempts rc existing reset number
    local enabled_count=${#corelist[@]} prepared=0 bootstrap_core=
    local bootstrap_active=${sam_bootstrap:-0}
    sam_queue_files
    existing=${#sam_queue[@]}
    for record in "${sam_queue[@]}"; do
        sam_record_read "$record" || continue
        printf '%s\n' "$sam_record_path" >> "$sam_job/reserved-$sam_record_core"
        delete_from_corelist "$sam_record_core" tmp
    done
    (( ${#corelisttmp[@]} )) || corelisttmp=("${sam_allowed_cores[@]}")
    for ((i=existing; i<2; i++)); do
        attempts=0
        while (( attempts < enabled_count + 3 )); do
            [[ -e "$sam_session/alive" ]] || return 0
            if [[ "$bootstrap_active" == 1 && -n "$bootstrap_core" ]]; then nextcore=$bootstrap_core
            else
                rc=0; sam_service choose_core || rc=$?
                if (( rc > 1 )); then sam_preparation_error "${sam_core_reason:-Core selection failed (status $rc)}"; return 0; fi
                (( rc == 0 )) || break
            fi
            c=$nextcore
            rc=0; sam_core_require "$c" || rc=$?
            if (( rc > 1 )); then sam_preparation_error "$sam_core_reason"; return 0; fi
            if (( rc == 1 )); then
                sam_preparation_error "Selector proposed a rejected core: $sam_core_reason"; return 0
            fi
            : >> "$sam_session/consumed/$c"
            : >> "$sam_job/reserved-$c"
            sam_candidate_cover= sam_candidate_reset=no sam_candidate_policy=
            rc=0
            if sam_service pick_candidate "$c"; then
                if check_rom "$c" && sam_emit candidate_prepare "$c" "$rompath"; then
                    number=$((sam_job_serial * 10 + i))
                    printf -v record '%s/ready/%08d.record' "$sam_session" "$number"
                    [[ -e "$sam_session/alive" ]] || return 0
                    [[ "$bootstrap_active" != 1 ]] || bootstrap_core=$c
                    prepared=$((prepared+1))
                    sam_record_write "$record" "$c" "$rompath" "${rompath##*/}" "" "$sam_revision" || return 1
                    printf '%s\n' "$rompath" >> "$sam_job/reserved-$c"
                    delete_from_corelist "$c" tmp
                    (( ${#corelisttmp[@]} )) || corelisttmp=("${sam_allowed_cores[@]}")
                    break
                else
                    rc=$?
                    if (( rc == 3 )); then
                        printf 'Cover download or validation failed for %s\n' "$c" > "$sam_session/error.tmp.$BASHPID"
                        mv "$sam_session/error.tmp.$BASHPID" "$sam_session/error"
                        return 0
                    fi
                fi
            else rc=$?; fi
            if ((rc == 3)); then
                printf 'Artwork catalog or cover download failed for %s\n' "$c" > "$sam_session/error"
                return 0
            elif ((rc > 1)); then
                sam_preparation_error "Candidate preparation failed for $c (status $rc)"; return 0
            fi
            attempts=$((attempts+1))
            delete_from_corelist "$c" tmp
            (( ${#corelisttmp[@]} )) || corelisttmp=("${sam_allowed_cores[@]}")
        done
    done
    # Extend discovery only after filling the small ready queue. This job exits
    # after one catalog; the next event schedules more work, never another daemon.
    sam_catalog_background_step
    sam_queue_files
    if (( prepared == 0 && existing == 0 && ${#sam_queue[@]} == 0 )) && ! sam_catalog_pending; then
        printf 'No eligible games found for the enabled cores and filters\n' > "$sam_session/error"
    fi
}

sam_schedule_preparation() {
    if [[ -n "$sam_worker_pid" ]]; then
        if [[ ! -f "$sam_session/jobs/$sam_job_serial/done" ]]; then
            if sam_pid_start "$sam_worker_pid" && [[ "$sam_proc_start" == "$sam_worker_start" ]]; then return 0; fi
            printf 'Preparation worker exited unexpectedly\n' > "$sam_session/error"
        fi
        wait "$sam_worker_pid" 2>/dev/null || true
        sam_worker_pid= sam_worker_start=
        rm -rf -- "$sam_session/jobs/$sam_job_serial"
    fi
    [[ ! -f "$sam_session/error" ]] || return 0
    sam_queue_files
    # Once all lists are built and the queue is full, no preparation process is
    # needed. The foreground countdown only performs built-in existence checks.
    if (( ${#sam_queue[@]} >= 2 )); then
        sam_catalog_pending || return 0
    fi
    sam_job_serial=$((sam_job_serial+1))
    (sam_prepare_worker) > "$sam_session/preparation.log" 2>&1 &
    sam_worker_pid=$!
    if sam_pid_start "$sam_worker_pid"; then sam_worker_start=$sam_proc_start; fi
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
        sam_emit launch_validate "$c" "$sam_record_path" || return $?
        sam_selected_record=$record
        nextcore=$c rompath=$sam_record_path romname=$sam_record_name gamename="${sam_record_name%.*}" core=$c
        [[ -z "$sam_record_amigapath" ]] || amigapath=$sam_record_amigapath
        [[ -z "$sam_record_amigacore" ]] || amigacore=$sam_record_amigacore
        return 0
    done
    return 1
}

sam_loading_keys() { # coalesce all queued Next presses into one pending action
    local key
    # A 1 ms timeout can expire under CPU load despite queued input, leaving
    # part of a burst for the next game. Allow a short bounded quiet interval.
    while read -r -s -t 0.05 -n 1 key; do
        case "$key" in n|N) SAM_ACTION=next ;; esac
    done
}

run_countdown_timer() {
    sam_publish_phase playing
    local countdown=$gametimer sam_paused=0 sam_frozen=0
    local start_time=$SECONDS end_time=$((SECONDS + gametimer)) current_rem key last_output=-1 last_schedule=-1
    sam_emit display_publish "$countdown" "$((EPOCHSECONDS + countdown))"
    sam_emit countdown_start
    sam_service timer_begin
    while (( sam_paused || gametimer == 0 || SECONDS < end_time )); do
        sam_emit countdown_tick || return 0
        sam_service timer_tick || return 0
        current_rem=$((end_time - SECONDS))
        (( !sam_paused )) || current_rem=$sam_frozen
        (( current_rem >= 0 )) || current_rem=0
        if (( current_rem != last_output )); then
            if (( sam_paused )); then printf 'Paused: %s seconds remaining...\033[0K\r' "$current_rem"
            else printf 'Next in %s seconds...\033[0K\r' "$current_rem"; fi
            last_output=$current_rem
        fi
        if (( SECONDS != last_schedule )); then sam_schedule_preparation; last_schedule=$SECONDS; fi
        # A builtin timed read handles keyboard immediately and bounds file
        # command latency. No sleep/date/stat/Python on an idle timer tick.
        if read -r -s -t 0.1 -n 1 key; then
            case "$key" in
                n|N) sam_request_next; return 0 ;;
                p|P) SAM_ACTION=previous; sam_emit controls_ready 0; return 0 ;;
                m|M) toggle_mute ;;
                *) sam_service mode_key "$key" || true ;;
            esac
        else
            # Timeout is >128; EOF is 1. Headless callers must not spin.
            [[ $? != 1 ]] || sleep 0.1
        fi
    done
    sam_emit controls_ready 0
    sam_emit display_publish
}

sam_normal_loop() {
    sam_pid_start "$$" || return 1
    sam_owner="$$:$sam_proc_start"
    sam_session="$mrsamtmp/session-$sam_owner"
    sam_catalog_cache="$mrsamtmp/catalog-cache"
    mkdir -p "$sam_session/ready" "$sam_session/jobs" "$sam_session/consumed" "$sam_catalog_cache"
    : > "$sam_session/alive"
    sam_publish_phase preparing
    trap sam_session_cleanup EXIT
    trap 'exit 0' TERM
    trap 'tmux detach-client' INT
    sam_emit display_start
    sam_prep || return 1
    disable_bootrom
    sam_emit session_start
    sam_emit display_startup
    corelisttmp=("${corelist[@]}")
    local c have_catalog=0
    for c in "${corelist[@]}"; do [[ ! -s "$gamelistpath/${c}_gamelist.txt" ]] || have_catalog=1; done
    sam_bootstrap=$((1-have_catalog))
    printf '\n' > "$sam_game_log"
    while :; do
        sam_schedule_preparation
        sam_replaying=0
        if [[ "$SAM_ACTION" == previous && -f "$sam_session/previous" ]]; then
            cp "$sam_session/previous" "$sam_session/ready/00000000.record"
        fi
        SAM_ACTION=
        sam_publish_phase preparing
        local take_rc=0
        sam_take_prepared || take_rc=$?
        if (( take_rc != 0 )); then
            if ((take_rc == 3)); then printf 'Prepared cover is unavailable\n' > "$sam_session/error"; fi
            if ((take_rc > 1)) && [[ ! -f "$sam_session/error" ]]; then sam_preparation_error "Selection validation failed (status $take_rc)"; fi
            if [[ -f "$sam_session/error" ]]; then
                local error; IFS= read -r error < "$sam_session/error"
                printf '\nSAM ERROR: %s. Current game retained; restart SAM to retry.\n' "$error" >&2
                return 1
            fi
            local key
            read -r -s -t 0.1 -n 1 key || { [[ $? != 1 ]] || sleep 0.1; }
            case "$key" in n|N) SAM_ACTION=next ;; esac
            continue
        fi
        sam_bootstrap=0
        sam_generation=$((sam_generation+1))
        sam_emit controls_ready 0
        SAM_ACTION=
        if load_core "$nextcore" "$rompath" "${romname%.*}"; then
            [[ "${sam_selected_record##*/}" == 00000000.record ]] || sam_service commit "$nextcore" "$rompath" "$sam_record_reset" "$sam_record_policy"
            # Keep compatibility replay data, but never source a runtime record.
            [[ ! -f "$sam_session/current" ]] || cp "$sam_session/current" "$sam_session/previous"
            cp "$sam_selected_record" "$sam_session/current"
            rm -f "$sam_selected_record"
            sam_loading_keys
            if [[ "$SAM_ACTION" == next ]]; then SAM_ACTION=; continue; fi
            SAM_ACTION=
            sam_schedule_preparation
            run_countdown_timer
        else
            local launch_rc=$?
            rm -f "$sam_selected_record"
            if (( launch_rc > 1 )); then
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
