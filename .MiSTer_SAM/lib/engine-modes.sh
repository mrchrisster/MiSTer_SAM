# SPDX-License-Identifier: GPL-3.0-or-later
# One-operation mode hooks for the resident session adapter. Timer state is
# deliberately global: fixed adapter commands all operate on the same clock.

sam_engine_program_take() { :; }
sam_engine_program_launch() { sam_engine_mode_step "${SAM_TARGET_CORE:-}"; }

sam_engine_mode_video_load() { # compatibility sentinel: 1 clip, 0 game, >1 fatal
    sv_loadcounter=$(( ${sv_loadcounter:-0}+1 ))
    local show_video=0
    case "${samvideo_freq:-}" in
        only) show_video=1 ;;
        core)
            (( ${#corelist[@]} > 0 )) || return 2
            if ((sv_loadcounter % ${#corelist[@]} == 0)); then
                show_video=1 sv_loadcounter=0
            fi ;;
        alternate) ((sv_loadcounter % 2 == 0)) || show_video=1 ;;
    esac
    sv_nextcore=
    ((show_video)) || return 0
    sam_publish_phase video || return 2
    # The adapter overrides load_samvideo with this fixed helper. Its existing
    # launch-job group owns downloads, late FIFO writers and the player together.
    sam_job_spawn sam_launch samvideo_play || return 2
    return 1
}

sam_engine_mode_step() { # target; 0 launched, 1 retry, >1 fatal
    local rc=0 replay=0
    case "${sam_mode:-normal}" in m82|samvideo) ;; *) return 2 ;; esac
    [[ "${sam_mode:-normal}" != m82 ]] || sam_engine_m82_phase=loading
    sam_cancel_launch_job || return 2
    if [[ "${sam_mode:-normal}" == samvideo && -n "${sv_gametimer_file:-}" ]]; then
        rm -f -- "$sv_gametimer_file" || return 2
    fi
    sam_publish_phase preparing || return 2
    sam_emit controls_ready 0 || return 2
    if [[ "${SAM_ACTION:-}" == previous ]]; then
        SAM_ACTION=
        if sam_record_read "$sam_session/mode-previous"; then
            core=$sam_record_core nextcore=$sam_record_core
            rompath=$sam_record_path gamename=$sam_record_name romname=${sam_record_path##*/}
            sam_core_require "$core" || rc=$?
            ((rc <= 1)) || return "$rc"
            if ((rc == 0)) && ! sam_is_excluded "$core" "$rompath"; then
                replay=1
                if [[ "$core" == cdi && "${samvideo_tvc_cdi:-no}" == yes ]]; then
                    sv_selected=$gamename sv_nextcore=samvideo
                    sv_ar_cdi_mode || rc=$?
                else
                    sv_nextcore=
                    load_core "$core" "$rompath" "$gamename" || rc=$?
                fi
            fi
        fi
    fi
    if ((replay == 0)); then
        # In M82, check_list consumes Next and skips the interstitial BIOS.
        # Do not clear this action before invoking the compatibility selector.
        rc=0
        next_core "${1:-}" || rc=$?
    fi
    SAM_ACTION=
    ((rc == 0)) || return "$rc"
    if [[ "${sv_nextcore:-}" != samvideo ]]; then
        # Keep the preceding game across commercial clips. Literal records
        # let replay launch the original ROM without depending on a global MGL.
        [[ ! -f "$sam_session/mode-current" ]] ||
            cp -- "$sam_session/mode-current" "$sam_session/mode-previous" || return 2
        sam_record_write "$sam_session/mode-current" "$nextcore" "$rompath" \
            "${gamename:-${romname%.*}}" '' "$sam_revision" || return 2
    fi
    return 0
}

sam_engine_mode_timer_finish() {
    sam_emit controls_ready 0 || return 2
    sam_emit display_publish || return 2
    return 1
}

sam_engine_mode_timer_begin() {
    countdown=${gametimer:-0}
    [[ "$countdown" =~ ^[0-9]{1,8}$ ]] || return 2
    countdown=$((10#$countdown))
    start_time=$SECONDS end_time=$((SECONDS+countdown))
    sam_paused=0 sam_frozen=0 m82_play_triggered=0 m82_is_infinite=0
    video_synced=yes sam_engine_timer_output= sam_engine_timer_schedule=-1
    if [[ "${sam_mode:-normal}" == samvideo && "${sv_nextcore:-}" == samvideo ]]; then
        sam_publish_phase video || return 2
        video_synced=no
        ((countdown >= 60)) || countdown=60
        end_time=$((SECONDS+countdown))
        sam_emit display_publish || return 2
    else
        sam_publish_phase playing || return 2
        sam_emit display_publish "$countdown" "$((EPOCHSECONDS+countdown))" || return 2
    fi
    if [[ "${sam_mode:-normal}" == m82 ]]; then
        if [[ "${rompath:-}" == "${m82_bios_path:-}" ]]; then
            sam_engine_m82_phase=bios
        else sam_engine_m82_phase=game; fi
        sam_m82_publish_phase "$sam_engine_m82_phase" || return 2
    fi
    case "${sam_mode:-normal}" in
        m82|samvideo)
            sam_control_generation=$(( ${sam_control_generation:-0}+1 ))
            sam_emit controls_ready 1 || return 2 ;;
        *)
            sam_emit countdown_start || return 2
            sam_service timer_begin || return 2 ;;
    esac
    return 0
}

sam_engine_mode_timer_tick() { # 0 alive, 1 boundary, >1 fatal
    local rc=0 video_time= current_rem
    if ((SECONDS != sam_engine_timer_schedule)); then
        sam_config_timer_update || return 2
    fi
    # The adapter suppresses the legacy command claim here; the Python owner
    # supplies acknowledged controls through its fixed control operation.
    sam_emit countdown_tick || rc=$?
    if ((rc == 0)); then sam_service timer_tick || rc=$?; fi
    if ((rc == 1)); then sam_engine_mode_timer_finish; return $?; fi
    ((rc == 0)) || return "$rc"
    if [[ "$video_synced" == no ]]; then
        ((end_time-SECONDS >= 5)) || end_time=$((SECONDS+10))
        if [[ -r "${sv_gametimer_file:-}" ]]; then
            IFS= read -r video_time < "$sv_gametimer_file" || true
            video_time=${video_time%$'\r'}
            if [[ "$video_time" =~ ^[0-9]{1,8}$ ]]; then
                countdown=$((10#$video_time))
                end_time=$((SECONDS+countdown)) video_synced=yes
                rm -f -- "$sv_gametimer_file" || return 2
                sam_session_ui_handoff_ready 1 || return 2
                sam_emit display_publish "$countdown" "$((EPOCHSECONDS+countdown))" || return 2
            fi
        fi
    fi
    if (( !sam_paused && !m82_is_infinite )) && [[ "$video_synced" == yes ]]; then
        # A synchronized zero-length clip advances; zero game time is indefinite.
        if [[ "${sv_nextcore:-}" == samvideo && "${sam_mode:-normal}" == samvideo ]] || ((gametimer != 0)); then
            if ((SECONDS >= end_time)); then sam_engine_mode_timer_finish; return $?; fi
        fi
    fi
    current_rem=$((end_time-SECONDS))
    if ((m82_is_infinite)) || { [[ "${sv_nextcore:-}" != samvideo ]] && ((gametimer == 0)); }; then current_rem=0; fi
    (( !sam_paused )) || current_rem=$sam_frozen
    ((current_rem >= 0)) || current_rem=0
    if [[ "$current_rem:$sam_paused:$video_synced:$m82_is_infinite" != "$sam_engine_timer_output" ]]; then
        if ((sam_paused)); then printf 'Paused: %s seconds remaining...\033[0K\r' "$current_rem"
        elif [[ "$video_synced" == no ]]; then printf 'Loading video...\033[0K\r'
        elif ((m82_is_infinite)); then printf 'Play Time: Infinite\033[0K\r'
        else printf 'Next in %s seconds...\033[0K\r' "$current_rem"; fi
        sam_engine_timer_output="$current_rem:$sam_paused:$video_synced:$m82_is_infinite"
    fi
    if ((SECONDS != sam_engine_timer_schedule)); then
        case "${sam_mode:-normal}" in
            m82|samvideo) ;;
            *) sam_schedule_preparation || return 2 ;;
        esac
        sam_engine_timer_schedule=$SECONDS
    fi
    return 0
}

sam_engine_mode_timer_key() { # key; 0 stay, 1 boundary, >1 fatal
    case "$1" in
        n|N) sam_request_next || return 2; return 1 ;;
        p|P) SAM_ACTION=previous; sam_engine_mode_timer_finish; return $? ;;
        m|M) toggle_mute || return 2 ;;
        y|Y)
            [[ "${sam_mode:-normal}" == m82 && "${sam_engine_m82_phase:-}" == game && "$m82_play_triggered" == 0 ]] || return 0
            if ! sam_m82_restore_audio; then
                printf 'M82: Could not restore SAM audio; play activation will retry.\n' >&2
                sam_diagnostic m82_play_failed audio_restore_failed "${sam_owner:-}" || true
                return 2
            fi
            local mg_timer=${m82_game_timer:-180}
            mg_timer=${mg_timer//$'\r'/}
            [[ "$mg_timer" =~ ^[0-9]{1,8}$ ]] || return 2
            mg_timer=$((10#$mg_timer))
            m82_is_infinite=$((mg_timer == 0))
            end_time=$((SECONDS+mg_timer)) sam_frozen=$mg_timer
            # Publish only after SAM-owned audio has been restored. Repeated
            # physical input then observes this launch's existing play ack.
            sam_m82_publish_phase play || return 2
            m82_play_triggered=1 sam_engine_m82_phase=play
            countdown=$mg_timer
            sam_emit display_publish "$mg_timer" "$((EPOCHSECONDS+mg_timer))" || return 2
            sam_diagnostic m82_play_started "timer=$mg_timer infinite=$m82_is_infinite" "${sam_owner:-}" || true
            ;;
        '') ;;
        *) sam_service mode_key "$1" || true ;;
    esac
    return 0
}
