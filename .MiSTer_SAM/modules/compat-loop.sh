# SPDX-License-Identifier: GPL-3.0-or-later
# Preserved special-mode transition implementation.
function loop_core() {
    # args: [target_core]
    sam_core_session_begin "${1:-}" || { printf 'SAM: %s\n' "$sam_core_reason" >&2; return 1; }
    trap sam_session_cleanup EXIT
    trap 'exit 0' TERM
    sam_pid_start "$$"; sam_owner="$$:$sam_proc_start"; sam_publish_phase preparing
    sam_emit display_start

    # Global trap to detach monitor on Ctrl+C instead of killing SAM
    trap 'tmux detach-client' INT

    # --- 1. Heavy Initialization (Runs once in background) ---
    echo "SAM Session: Initializing..."
    # Module settings are a session snapshot; do not reread the INI after loading.

    # This is the heavy step (downloads/mounts) that was freezing Python
    sam_prep || return 1

    disable_bootrom
    sam_emit session_start
    sam_emit display_startup

    # --- 2. Main Loop ---
    echo "SAM Session: Setup complete. Entering main loop."
    echo -e "Starting Super Attract Mode...\nLet Mortal Kombat begin!\n"

    # Reset game log for this session
    echo "" >"$sam_game_log"
    samdebug "Initial corelist: ${corelist[*]}"

    # The infinite loop
    while :; do
        sam_publish_phase preparing
        if [ "$SAM_ACTION" == "previous" ]; then
             if sam_record_read "$mrsamtmp/prev_game_info"; then
                 core=$sam_record_core rompath=$sam_record_path gamename=$sam_record_name
                 local replay_rc=0
                 sam_core_require "$core" || replay_rc=$?
                 if (( replay_rc > 1 )); then printf 'SAM: %s\n' "$sam_core_reason" >&2; return 1; fi
                 if (( replay_rc == 1 )); then SAM_ACTION=; continue; fi
                 if sam_is_excluded "$core" "$rompath"; then SAM_ACTION=; continue; fi
                 if [ "$core" == "cdi" ] && [ "${samvideo_tvc_cdi}" == "yes" ]; then
                     samdebug "Replaying previous CDI video: $gamename"
                     # Force the selection of the same video
                     sv_selected="$gamename"
                     sv_ar_cdi_mode
                 elif [ -f /tmp/SAM_game.previous.mgl ]; then
                     samdebug "Replaying previous game"
                     load_core "mgls" "/tmp/SAM_game.previous.mgl" "$gamename" "$core" "$rompath"
                 else
                     samdebug "Previous MGL not found."
                 fi
                 SAM_ACTION=""
                 run_countdown_timer
                 continue
             else
                 samdebug "No previous game info."
                 SAM_ACTION=""
             fi
        fi

        if next_core "${1-}"; then
            # Cache previous game details for replay
            sam_record_write "$mrsamtmp/prev_game_info" "$nextcore" "$rompath" "${gamename:-${romname%.*}}" '' "$sam_revision"


            run_countdown_timer
        else
            local next_rc=$?
            if (( next_rc > 1 )); then printf 'SAM: %s\n' "${sam_core_reason:-Selection failed (status $next_rc)}" >&2; return 1; fi
            samdebug "next_core failed. Looping to pick another core."
            continue
        fi
    done
}

function next_core() { # next_core (core)

    corelist_update || { printf 'SAM: %s\n' "$sam_core_reason" >&2; return 2; }
    if [[ -n "${1:-}" ]]; then
        sam_core_require "$1" || { printf 'SAM: %s\n' "$sam_core_reason" >&2; return 2; }
    fi

	if [[ -n "$cfgcore_configpath" ]]; then
		configpath="$cfgcore_configpath"
	else
		configpath="/media/fat/config/"
	fi

	if [ "${samvideo}" == "yes" ]; then
		load_samvideo
		if [ $? -ne 0 ]; then sv_nextcore="samvideo" && return; fi
	fi

	# Pick a core if no corename was supplied as argument (eg "MiSTer_SAM_on.sh psx")
	if [ -z "${1}" ]; then
		#samdebug "corelist: ${corelist[@]}"

		if [ "$samvideo" == "yes" ] && [ "$samvideo_tvc" == "yes" ]; then
			nextcore=$(cat /tmp/.SAM_tmp/sv_core)
		else
			pick_core || { printf 'SAM: %s\n' "${sam_core_reason:-No selectable cores}" >&2; return 2; }
		fi
	else
		# Single Mode: Use the provided argument
		nextcore="${1}"
	fi

    sam_core_require "$nextcore" || { printf 'SAM: %s\n' "$sam_core_reason" >&2; return 2; }

	check_list "${nextcore}"
	if [ $? -ne 0 ]; then
		samdebug "check_list function returned an error."
        delete_from_corelist "$nextcore" || { printf 'SAM: %s\n' "$sam_core_reason" >&2; return 2; }
		return 1
	fi

    # Check if new roms got added
    if [[ "$check_for_new_games" == "Yes" ]]; then
            check_list_update ${nextcore}
    fi

	pick_rom || {
        local pick_rc=$?
        (( pick_rc < 2 )) || return "$pick_rc"
        delete_from_corelist "$nextcore" || return 2
        return 1
    }

    declare -g romloadfails=0
    local rom_is_valid=false

    while [ ${romloadfails} -lt ${coreretries} ]; do
        # Call check_rom. It returns 0 on success.
        if check_rom "${nextcore}"; then
            # The ROM is valid! Mark as successful and break out of the loop.
            rom_is_valid=true
            break
        fi

        # If we are here, the ROM was invalid. Increment the failure counter.
        romloadfails=$((romloadfails + 1))

        # If we still have retries left, pick a new ROM to test on the next loop iteration.
        # The check_rom function may have rebuilt the list, so we need to pick again.
        if [ ${romloadfails} -lt ${coreretries} ]; then
            samdebug "ROM check failed. Picking a new ROM to try again (${romloadfails}/${coreretries})..."
            pick_rom
        fi
    done

    # After the loop, check if we ever found a valid ROM.
    if [ "$rom_is_valid" = "false" ]; then
        # All retries have been exhausted. No valid ROM was found.
        printf 'SAM: skipping %s after %s invalid ROM selections\n' "$nextcore" "$coreretries" >&2
        delete_from_corelist "$nextcore" || return 2
        return 1
    fi

	load_core "${nextcore}" "${rompath}" "${romname%.*}"


	# Capture the exit code from load_core and return it.
	# This passes the success/failure signal up to the main loop.
	return $?
}

function run_countdown_timer() {
    if [[ "${samvideo,,}" == yes && "${sv_nextcore:-}" == samvideo ]]; then
        sam_publish_phase video
    else sam_publish_phase playing; fi
    local countdown=${gametimer}
    local sam_paused=0 sam_frozen=0
    sam_control_generation=$(( ${sam_control_generation:-0} + 1 ))
    local start_time=$SECONDS
    local end_time=$((start_time + countdown))
    local m82_play_triggered=0
    local m82_is_infinite=0

    # Set a local trap to handle Ctrl+C.
    # Inherit global trap (detach)
    # trap 'echo; return' INT

    # This loop provides a visible, second-by-second countdown with input handling
    local video_synced="yes"
    if [ "${samvideo}" == "yes" ] && [ "$sv_nextcore" == "samvideo" ]; then
        video_synced="no"
        # Ensure we don't timeout while loading
        if (( countdown < 60 )); then countdown=60; fi
        end_time=$((start_time + countdown))
    fi
    if [[ "$video_synced" == yes ]]; then
        sam_emit display_publish "$countdown" "$((EPOCHSECONDS + end_time - SECONDS))"
    else
        sam_emit display_publish
    fi

    sam_emit controls_ready 1
    while (( sam_paused == 1 || SECONDS < end_time )); do
        sam_emit countdown_tick || return
        if [ "$video_synced" == "no" ]; then
            # extend timeout slightly to keep loop alive if loading is slow
            if (( end_time - SECONDS < 5 )); then
                end_time=$((SECONDS + 10))
            fi

            if [ -f "$sv_gametimer_file" ]; then
                local video_time=$(cat "$sv_gametimer_file")
                if [[ "$video_time" =~ ^[0-9]+$ ]]; then
                    countdown=$video_time
                    end_time=$((SECONDS + countdown))
                    rm "$sv_gametimer_file" 2>/dev/null
                    samdebug "Timer synced to video: $countdown seconds"
                    video_synced="yes"
                    sam_emit display_publish "$countdown" "$((EPOCHSECONDS + end_time - SECONDS))"
                fi
            fi
        fi

        local current_rem=$((end_time - SECONDS))
        [[ "$sam_paused" == 1 ]] && current_rem=$sam_frozen
        if (( current_rem < 0 )); then current_rem=0; fi

        if [[ "$sam_paused" == 1 ]]; then
             echo -ne "Paused: ${current_rem} seconds remaining...\033[0K\r"
        elif [ "$video_synced" == "no" ]; then
             echo -ne "Loading video...\033[0K\r"
        elif [[ "$m82_is_infinite" == "1" ]]; then
             echo -ne "Play Time: Infinite\033[0K\r"
        else
             echo -ne "Next in ${current_rem} seconds...\033[0K\r"
        fi

        read -s -t 1 -n 1 key
        if [[ $? -eq 0 ]]; then
            case "$key" in
                n|N)
                    echo
                    sam_request_next
                    return
                    ;;
                p|P)
                    echo
                    SAM_ACTION="previous"
                    sam_emit controls_ready 0
                    sam_emit display_publish
                    return
                    ;;
                m|M)
                    toggle_mute
                    ;;
                y|Y)
                    # M82 play mode: user pressed a button during a game.
                    # Extend the countdown to m82_game_timer and restore audio ONCE per game.
                    if [[ "$m82" == "yes" ]] || [[ "$m82" == *"yes"* ]]; then
                        if [[ "$m82_play_triggered" == "0" ]]; then
                            local mg_timer="${m82_game_timer:-180}"
                            mg_timer="${mg_timer//$'\r'/}"

                            if [[ "$mg_timer" == "0" ]]; then
                                mg_timer=86400
                                m82_is_infinite=1
                            fi

                            end_time=$((SECONDS + mg_timer))
                            m82_play_triggered=1
                            if [[ "$m82_is_infinite" == 1 ]]; then
                                sam_emit display_publish 0 "$EPOCHSECONDS"
                            else
                                sam_emit display_publish "$mg_timer" "$((EPOCHSECONDS + end_time - SECONDS))"
                            fi
                            samdebug "M82 play mode triggered. Extended timer by $mg_timer seconds."
                            only_unmute_if_needed
                        fi
                    fi
                    ;;
            esac
        fi
    done

    sam_emit controls_ready 0
    sam_emit display_publish
    # Reset the trap to its default behavior after the countdown finishes normally.
    # trap - INT
}
