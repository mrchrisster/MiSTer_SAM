# SPDX-License-Identifier: GPL-3.0-or-later
# Persistent platform adapter. stdin is a fixed protocol, FD 3 replies only.
sam_engine_parent_valid() {
    local line args=() fields=()
    [[ "${SAM_ENGINE_OWNER_PID:-}" =~ ^[1-9][0-9]*$ && "$SAM_ENGINE_OWNER_PID" == "$PPID" &&
       "${SAM_ENGINE_OWNER_START:-}" =~ ^[0-9]+$ ]] || return 1
    IFS= read -r line < "/proc/$PPID/stat" || return 1
    read -ra fields <<< "${line##*) }"
    [[ "${fields[19]:-}" == "$SAM_ENGINE_OWNER_START" && "${fields[0]}" != Z ]] || return 1
    mapfile -d '' -t args < "/proc/$PPID/cmdline" || return 1
    [[ "${args[0]##*/}" == python* ]] || return 1
    local arg found=0
    for arg in "${args[@]}"; do [[ "$arg" != "$sam_root/sam/session_engine.py" ]] || found=1; done
    ((found)) || return 1
    sam_engine_adapter_verified=1
}

sam_engine_reply() {
    local action=${SAM_ACTION:--} remaining=0 timer=${countdown:-${gametimer:-0}}
    [[ "$action" == next || "$action" == previous ]] || action=-
    if [[ "${sam_engine_timer_active:-0}" == 1 ]]; then
        remaining=$(( ${sam_paused:-0} ? ${sam_frozen:-0} : ${end_time:-$SECONDS}-SECONDS ))
        ((remaining >= 0)) || remaining=0
        [[ "${m82_is_infinite:-0}" != 1 ]] || { remaining=0; timer=0; }
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" \
        "${sam_mode:-normal}" "${sam_last_phase:-preparing}" "$timer" "${sam_paused:-0}" "$remaining" "$action" >&3
}

sam_engine_protocol_broken() {
    if [[ "${sam_engine_hosted:-0}" == 1 && "${sam_session_started:-0}" == 1 ]] &&
        sam_session_is_current && ! sam_engine_controller_alive; then
        sam_engine_stop_menu
    fi
    exit 1
}

sam_engine_stop_menu() {
    # Called through a verified parent's signal, even during a blocking launch.
    [[ "${sam_engine_menu_exit:-0}" != 1 ]] || return 0
    sam_engine_menu_exit=1 sam_exit_reason=menu_request
    sam_session_is_current || exit 1
    sam_menu_delivery_begin
    sam_exit_menu_context_owner=$sam_owner sam_exit_expected_owner=$sam_owner
    sam_exit_menu_initial_main=$sam_menu_initial_main
    sam_exit_menu_initial_fifo=$sam_menu_initial_fifo
    sam_exit_menu_initial_marker=$sam_menu_initial_marker
    printf '%s\n' "$sam_owner" > "$mrsamtmp/menu-audio-owner.tmp.$BASHPID" &&
        mv -f -- "$mrsamtmp/menu-audio-owner.tmp.$BASHPID" "$mrsamtmp/menu-audio-owner" || exit 1
    rm -f -- "$mrsamtmp/menu-audio-complete"
    local rc=0
    sam_session_cleanup || rc=$?
    if ((rc == 0)); then sam_exit_finalize menu 0 || rc=$?; fi
    exit "$rc"
}

sam_engine_error() {
    local error='No eligible games found for the enabled cores and filters'
    [[ ! -r "$sam_session/error" ]] || IFS= read -r error < "$sam_session/error"
    sam_exit_reported=1 sam_exit_reason=$error
    printf 'SAM ERROR: %s\n' "$error" >&2
    sam_record_empty_autostart || true
    return 2
}

sam_engine_normal_take() {
    if [[ "$SAM_ACTION" == previous && -f "$sam_session/previous" ]]; then
        cp -- "$sam_session/previous" "$sam_session/ready/00000000.record" || return 2
    fi
    local rc=0
    sam_take_prepared || rc=$?
    # Keep the current game playable during a ready handoff. Publish preparing
    # only when we actually need to wait for a successor from the worker.
    ((rc != 1)) || sam_publish_phase preparing || return 2
    if ((rc > 1)); then sam_preparation_error 'Prepared selection is unavailable'; fi
    [[ ! -r "$sam_session/error" ]] || { sam_engine_error; return $?; }
    return "$rc"
}

sam_engine_normal_launch() {
    sam_engine_timer_active=0
    sam_bootstrap=0 sam_generation=$((sam_generation+1))
    sam_emit controls_ready 0 || return 2
    SAM_ACTION=
    local rc=0
    load_core "$nextcore" "$rompath" "${romname%.*}" || rc=$?
    if ((rc != 0)); then rm -f -- "$sam_selected_record"; return "$rc"; fi
    if [[ "${sam_selected_record##*/}" != 00000000.record ]]; then
        sam_service commit "$nextcore" "$rompath" "$sam_record_reset" "$sam_record_policy" || return 2
    fi
    [[ ! -f "$sam_session/current" ]] || cp -- "$sam_session/current" "$sam_session/previous" || return 2
    cp -- "$sam_selected_record" "$sam_session/current" || return 2
    rm -f -- "$sam_selected_record"
}

sam_engine_control() {
    case "$1" in
        pause)
            [[ "${sam_mode:-normal}" != m82 && "${sam_mode:-normal}" != samvideo ]] || return 2
            if [[ "${sam_paused:-0}" == 0 ]]; then
                sam_frozen=$((end_time-SECONDS)); ((sam_frozen >= 0)) || sam_frozen=0
                sam_paused=1
            fi
            sam_control_publish 1 ;;
        resume)
            if [[ "${sam_paused:-0}" == 1 ]]; then
                end_time=$((SECONDS+sam_frozen)); sam_paused=0
                sam_emit display_publish "$sam_frozen" "$((EPOCHSECONDS+sam_frozen))"
            fi
            sam_control_publish 1 ;;
        next) sam_request_next; return 1 ;;
        ignore)
            sam_display_read
            ignoregame "$sam_display_core" "$sam_display_rom_path" >/dev/null || return 2
            sam_request_next; return 1 ;;
        play)
            sam_control_publish 0
            exit_sam game || return 2
            sam_engine_quit=1 ;;
        *) return 2 ;;
    esac
}

sam_engine_adapter_main() {
    source "$sam_root/lib/engine-hosted.sh" || return 1
    if [[ "${sam_engine_hosted:-0}" == 1 ]]; then trap sam_engine_protocol_broken PIPE; fi
    # The engine claims Monitor requests in-process; other countdown hooks stay.
    sam_control_tick() { :; }
    source "$sam_root/lib/engine-modes.sh" || return 1
    # Also support trusted source-only integrations which loaded the registry
    # before adapter verification. Never overwrite a provider registered by a module.
    [[ -n "${SAM_SERVICES[engine_take]-}" ]] || sam_bind engine_take sam_engine_normal_take || return 1
    [[ -n "${SAM_SERVICES[engine_launch]-}" ]] || sam_bind engine_launch sam_engine_normal_launch || return 1
    [[ -n "${SAM_SERVICES[engine_timer_begin]-}" ]] || sam_bind engine_timer_begin sam_engine_mode_timer_begin || return 1
    [[ -n "${SAM_SERVICES[engine_timer_tick]-}" ]] || sam_bind engine_timer_tick sam_engine_mode_timer_tick || return 1
    [[ -n "${SAM_SERVICES[engine_key]-}" ]] || sam_bind engine_key sam_engine_mode_timer_key || return 1
    if [[ "${sam_mode:-normal}" == samvideo ]]; then
        load_samvideo() { sam_engine_mode_video_load; }
    fi
    sam_core_session_begin "${1:-}" || { printf 'SAM ERROR: %s\n' "$sam_core_reason" >&2; return 1; }
    if [[ "${sam_engine_hosted:-0}" == 1 ]]; then
        # This first reply authorizes no hardware or replacement. EOF and every
        # token except the single fixed activation token exit before ownership.
        sam_engine_reply validated 0 || return 1
        local activation
        IFS= read -r activation || return 0
        [[ "$activation" == activate ]] || return 64
        sam_engine_controller_alive || return 1
        init_paths || return 1
    fi
    sam_exit_trace core_policy_ready
    sam_session_begin || return 1
    trap sam_engine_stop_menu USR1
    [[ "${sam_engine_stop_pending:-0}" != 1 ]] || sam_engine_stop_menu
    trap ':' INT
    if [[ "${sam_engine_hosted:-0}" == 1 ]]; then
        sam_engine_guardian_begin || return 1
    fi
    sam_emit display_start || return 1
    echo 'SAM Session: Initializing the session adapter...'
    sam_exit_trace session_setup_begin
    sam_prep || return 1
    sam_exit_trace session_setup_end
    disable_bootrom
    sam_emit session_start || { sam_preparation_error 'Session startup module failed'; sam_engine_error; return 1; }
    sam_emit display_startup || return 1
    sam_exit_trace display_startup_ready
    corelisttmp=("${corelist[@]}")
    # First automatic game gets an arcade seed even when other lists exist.
    # Explicit core and program modes retain their own selectors.
    sam_bootstrap=0
    if [[ "$SAM_MODE" != SINGLE && "${sam_core_registry_active:-0}" == 1 ]]; then sam_bootstrap=1; fi
    printf '\n' > "$sam_game_log"
    sam_engine_reply ready 0
    local id action argument extra rc last_preparation=-1
    # Keep ordinary IFS at this blocking read: signal cleanup uses /proc's
    # space-separated fields and must not inherit a temporary tab-only IFS.
    while read -r id action argument extra; do
        [[ "$id" =~ ^[0-9]{1,12}$ && ${#id} -le 12 && -z "$extra" && ${#argument} -le 32 ]] || return 64
        sam_session_is_current || return 1
        rc=0
        case "$action" in boundary|prepare|take|launch|timer_begin|key|control) sam_exit_trace "operation_begin:$action" ;; esac
        case "$action" in
            boundary)
                sam_engine_timer_active=0
                sam_config_game_boundary || rc=2
                if ((rc == 0)); then
                    sam_queue_files
                    case "${sam_mode:-normal}" in
                        normal|roulette)
                            if ((${#sam_queue[@]} == 0)); then sam_publish_phase preparing || rc=2; fi ;;
                        *) sam_publish_phase preparing || rc=2 ;;
                    esac
                fi ;;
            prepare)
                if [[ "${sam_mode:-normal}" != m82 && "${sam_mode:-normal}" != samvideo && "$SECONDS" != "$last_preparation" ]]; then
                    sam_schedule_preparation || rc=2
                    last_preparation=$SECONDS
                fi ;;
            take) sam_service engine_take || rc=$? ;;
            launch) sam_service engine_launch || rc=$? ;;
            timer_begin) sam_service engine_timer_begin || rc=$?; sam_engine_timer_active=1 ;;
            timer_tick) sam_service engine_timer_tick || rc=$? ;;
            key)
                [[ "$argument" == [nNpPmMyY] ]] || return 64
                sam_service engine_key "$argument" || rc=$? ;;
            control) sam_engine_control "$argument" || rc=$? ;;
            cleanup) sam_session_cleanup || rc=$?; sam_engine_quit=1 ;;
            *) return 64 ;;
        esac
        case "$action" in boundary|prepare|take|launch|timer_begin|key|control) sam_exit_trace "operation_end:$action:$rc" ;; esac
        sam_engine_reply "$id" "$rc" || return 1
        [[ "${sam_engine_quit:-0}" != 1 ]] || return "$rc"
    done
    if [[ "${sam_engine_hosted:-0}" == 1 ]] && ! sam_engine_controller_alive && sam_session_is_current; then
        sam_engine_stop_menu
    fi
}
