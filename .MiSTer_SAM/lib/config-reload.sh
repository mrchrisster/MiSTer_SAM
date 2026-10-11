# SPDX-License-Identifier: GPL-3.0-or-later
# Reload requests are literal owner-bound RAM data, never sourced/evaluated.
sam_config_read_update() {
    local line key value pid= ticks= revision= structural= selection= timer= mg_timer=180 debug=no debuglog=no count=0
    declare -gA sam_reload_settings=()
    declare -ga sam_reload_exclude=()
    [[ -r "$sam_session/config-update" ]] || return 1
    while IFS= read -r line; do
        count=$((count+1)); ((count <= 512 && ${#line} <= 8192)) || return 1
        key=${line%%=*} value=${line#*=}
        case "$key" in
            pid) pid=$value ;; start) ticks=$value ;; revision) revision=$value ;;
            structural) structural=$value ;; selection) selection=$value ;; gametimer) timer=$value ;;
            m82timer) mg_timer=$value ;; debug) debug=$value ;; debuglog) debuglog=$value ;;
            setting_corelist|setting_corelistall|setting_rating|setting_kids_safe|setting_dupe_mode|setting_arcadeorient|setting_norepeat|setting_disable_blacklist|setting_coreweight|setting_amigaselect|setting_skiptime|setting_skipmessage|setting_disablebootrom|setting_category_preset)
                sam_reload_settings[${key#setting_}]=$value ;;
            setting_*pathfilter)
                local filtercore=${key#setting_}; filtercore=${filtercore%pathfilter}
                [[ -n "${PATHFILTER[$filtercore]+x}" ]] || continue
                sam_reload_settings[${key#setting_}]=$value ;;
            exclude_*) [[ "${key#exclude_}" =~ ^[0-9]+$ ]] && sam_reload_exclude+=("$value") ;;
        esac
    done < "$sam_session/config-update"
    [[ "$pid:$ticks" == "$sam_owner" && "$revision" =~ ^[a-f0-9]{64}$ &&
       "$structural:$selection" =~ ^[01]:[01]$ && "$timer" =~ ^[0-9]{1,8}$ && "$mg_timer" =~ ^[0-9]{1,8}$ ]] || return 1
    sam_reload_revision=$revision sam_reload_structural=$structural sam_reload_selection=$selection
    sam_reload_timer=$((10#$timer))
    sam_reload_m82timer=$((10#$mg_timer)) sam_reload_debug=$debug sam_reload_debuglog=$debuglog
}

sam_config_timer_update() { # uses the countdown's dynamically scoped locals
    sam_config_read_update || return 0
    samdebug=$sam_reload_debug samdebuglog=$sam_reload_debuglog
    if [[ "${sam_mode:-normal}" == m82 ]]; then
        if ((m82_game_timer != sam_reload_m82timer)); then
            if [[ "${m82_play_triggered:-0}" == 1 ]]; then
                if ((sam_reload_m82timer == 0)); then
                    end_time=$((SECONDS+86400)); sam_frozen=86400; m82_is_infinite=1
                    sam_emit display_publish 0 "$EPOCHSECONDS"
                else
                    if [[ "${m82_is_infinite:-0}" == 1 ]]; then
                        end_time=$((SECONDS+sam_reload_m82timer)); sam_frozen=$sam_reload_m82timer; m82_is_infinite=0
                    else
                        local m82_delta=$((sam_reload_m82timer-m82_game_timer))
                        end_time=$((end_time+m82_delta)); sam_frozen=$((sam_frozen+m82_delta))
                    fi
                    ((sam_frozen >= 0)) || sam_frozen=0
                    local m82_remaining=$((sam_paused ? sam_frozen : end_time-SECONDS))
                    ((m82_remaining >= 0)) || m82_remaining=0
                    sam_emit display_publish "$m82_remaining" "$((EPOCHSECONDS+m82_remaining))"
                fi
            fi
            m82_game_timer=$sam_reload_m82timer
        fi
        return 0
    fi
    [[ "${sam_mode:-normal}" == normal ]] || return 0
    ((gametimer != sam_reload_timer)) || return 0
    local delta=$((sam_reload_timer-gametimer))
    if ((sam_reload_timer == 0)); then end_time=$SECONDS; sam_frozen=0
    elif ((gametimer == 0)); then end_time=$((SECONDS+sam_reload_timer)); sam_frozen=$sam_reload_timer
    else end_time=$((end_time+delta)); sam_frozen=$((sam_frozen+delta)); fi
    ((sam_frozen >= 0)) || sam_frozen=0
    gametimer=$sam_reload_timer
    local remaining=$((sam_paused ? sam_frozen : end_time-SECONDS))
    ((remaining >= 0)) || remaining=0
    sam_emit display_publish "$remaining" "$((EPOCHSECONDS+remaining))"
}

sam_config_game_boundary() {
    sam_config_read_update || return 0
    [[ "$sam_reload_revision" != "${sam_reload_applied_revision:-}" ]] || return 0
    # Commercial clips own their current deadline. Update the generic game
    # interval only here, before selecting the next commercial/game.
    [[ "${sam_mode:-normal}" != samvideo ]] || gametimer=$sam_reload_timer
    if [[ "$sam_reload_structural" == 1 ]]; then
        local boundary_revision=$sam_reload_revision
        sam_emit controls_ready 0
        # A game remains onscreen while this handoff waits. Retain playing/video
        # so an arriving Start/Play can still choose the ordinary keep-game exit.
        sam_session_is_current || return 1
        printf 'pid=%s\nstart=%s\nrevision=%s\ntarget=%s\n' "${sam_owner%%:*}" "${sam_owner#*:}" "$sam_reload_revision" "${SAM_TARGET_CORE:-}" > "$sam_session/config-boundary.tmp.$BASHPID" &&
            mv -f "$sam_session/config-boundary.tmp.$BASHPID" "$sam_session/config-boundary" || return 1
        # Leave terminal bytes queued for the coordinator/new owner. A human
        # Stop still cancels this verified owner through the ordinary gateway.
        while sam_session_is_current; do
            sam_config_read_update || { sleep .1; continue; }
            [[ "$sam_reload_structural" == 1 ]] || { rm -f "$sam_session/config-boundary"; break; }
            if [[ "$boundary_revision" != "$sam_reload_revision" ]]; then
                boundary_revision=$sam_reload_revision
                printf 'pid=%s\nstart=%s\nrevision=%s\ntarget=%s\n' "${sam_owner%%:*}" "${sam_owner#*:}" "$sam_reload_revision" "${SAM_TARGET_CORE:-}" > "$sam_session/config-boundary.tmp.$BASHPID" &&
                    mv -f "$sam_session/config-boundary.tmp.$BASHPID" "$sam_session/config-boundary" || return 1
            fi
            sleep .1
        done
        sam_session_is_current || return 1
    fi
    if [[ "$sam_reload_selection" == 1 ]]; then
        sam_cancel_preparation || return 1
        sam_session_is_current || return 1
        rm -f -- "$sam_session/ready/"*.record "$sam_session/error" "$sam_session/outcome"
        local name value
        for name in "${!sam_reload_settings[@]}"; do
            value=${sam_reload_settings[$name]}
            case "$name" in corelist|corelistall) IFS=',' read -ra "$name" <<< "$value" ;;
                *) printf -v "$name" '%s' "$value" ;;
            esac
            if [[ "$name" == *pathfilter ]]; then PATHFILTER[${name%pathfilter}]=$value; fi
        done
        exclude=("${sam_reload_exclude[@]}")
        sam_revision=$((sam_revision+1))
        sam_emit config_refresh || return 1
        sam_core_session_begin "${SAM_TARGET_CORE:-}" || return 1
        corelisttmp=("${sam_allowed_cores[@]}")
    fi
    local suffix destination
    for suffix in ini category roulette tags; do
        destination=config-$suffix
        [[ "$suffix" != ini ]] || destination=config.ini
        [[ ! -f "$sam_session/config-$sam_reload_revision.$suffix" ]] ||
            mv -f -- "$sam_session/config-$sam_reload_revision.$suffix" "$sam_session/$destination" || return 1
    done
    sam_reload_applied_revision=$sam_reload_revision
}
