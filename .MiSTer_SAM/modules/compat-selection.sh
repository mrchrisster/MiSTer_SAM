# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function corelist_update() {
    local incoming=() rc=0
    if [[ -f "${corelistfile}.single" ]]; then
        mapfile -t incoming < "${corelistfile}.single"
        sam_normalize_cores incoming incoming || return 2
        if (( ${#incoming[@]} != 1 )); then
            sam_core_reason='Single-core request must contain exactly one supported core'; return 2
        fi
        SAM_MODE=SINGLE; SAM_TARGET_CORE=${incoming[0]}
        sam_requested_cores=("$SAM_TARGET_CORE")
        sam_core_policy_ready=1
        rm -f "${corelistfile}.single" "$corelistfile"
    elif [[ -f "$corelistfile" ]]; then
        mapfile -t incoming < "$corelistfile"
        sam_normalize_cores incoming sam_requested_cores || return 2
        sam_emit core_requested sam_requested_cores || return 2
        if [[ "$SAM_MODE" == SINGLE ]]; then sam_requested_cores=("$SAM_TARGET_CORE"); fi
        sam_core_policy_ready=1
        rm -f "$corelistfile"
    fi
    sam_core_policy_refresh || return $?
    if [[ "$disablecoredel" == 0 ]]; then delete_from_corelist "${nextcore:-}" tmp; fi
    (( ${#corelisttmp[@]} )) || corelisttmp=("${sam_allowed_cores[@]}")
}

function pick_core() {
    nextcore=
    sam_core_policy_refresh || return $?
    if [[ "$SAM_MODE" == SINGLE ]]; then
        sam_core_require "$SAM_TARGET_CORE" || return $?
        nextcore=$SAM_TARGET_CORE
    elif [[ "$coreweight" == yes ]]; then
        pick_core_weighted || return $?
    elif [[ "$samvideo" == yes && -n "${1:-}" ]]; then
        pick_core_samvideo "$1" || return $?
    else
        pick_core_standard || return $?
    fi
    sam_core_require "$nextcore"
}

function pick_core_standard() {
    sam_normal_choose_core
}

function init_core_weighted() {
    sam_core_policy_refresh || return $?
    local c f stamp files=()
    for c in "${sam_allowed_cores[@]}"; do
        files+=("$gamelistpathtmp/${c}_gamelist.txt" "$gamelistpath/${c}_gamelist.txt")
    done
    stamp="${sam_allowed_cores[*]}:$(stat -c '%n:%s:%y' "${files[@]}" 2>/dev/null || true)"
    [[ "${COREWEIGHT_STAMP:-}" != "$stamp" ]] || return 0
    COREWC=(); COREP=(); TOTAL_GAME_COUNT=0
    # Use existing counts only. Do not advance ordered mode lists or scan all
    # ROM collections merely to assign weights. Empty counts use equal weights.
    for c in "${sam_allowed_cores[@]}"; do
        f="$gamelistpathtmp/${c}_gamelist.txt"
        [[ -f "$f" ]] || f="$gamelistpath/${c}_gamelist.txt"
        COREWC[$c]=0
        [[ ! -f "$f" ]] || COREWC[$c]=$(wc -l < "$f")
        COREP[$c]=${COREWC[$c]}
        TOTAL_GAME_COUNT=$((TOTAL_GAME_COUNT + COREWC[$c]))
    done
    COREWEIGHT_STAMP=$stamp; COREWEIGHT_INITIALIZED=1
}

function pick_core_weighted() {
    init_core_weighted || return $?
    local c total=0
    local -A current_weights=()
    for c in "${corelisttmp[@]}"; do
        current_weights[$c]=${COREP[$c]:-0}
        total=$((total + current_weights[$c]))
    done
    if (( total == 0 )); then
        for c in "${corelisttmp[@]}"; do current_weights[$c]=1; done
        total=${#corelisttmp[@]}
    fi
    nextcore=$(pick_weighted_random current_weights "$total") || return $?
    sam_core_require "$nextcore"
}

function pick_weighted_random() {
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && "$1" != __sam_* ]] || return 2
    local -n __sam_weights="$1"
    local __sam_total="$2" __sam_pick __sam_key __sam_weight
    [[ "$__sam_total" =~ ^[0-9]+$ ]] || return 2
    (( __sam_total > 0 )) || return 1
    sam_random_below "$__sam_total" || return $?
    __sam_pick=$sam_random
    for __sam_key in "${!__sam_weights[@]}"; do
        __sam_weight=${__sam_weights[$__sam_key]}
        [[ "$__sam_weight" =~ ^[0-9]+$ ]] || return 2
        __sam_weight=$((10#$__sam_weight))
        if (( __sam_pick < __sam_weight )); then printf '%s\n' "$__sam_key"; return 0; fi
        __sam_pick=$((__sam_pick-__sam_weight))
    done
    return 2
}

function pick_rom() {
    sam_core_require "$nextcore" || return $?
    sam_emit candidate_filter "$nextcore" || return $?
    # 1. Handle special, non-random cases first.
    if [[ "$m82" == "yes" ]]; then
        # M82 mode is deterministic; it always takes the first line of the session list.
        rompath="$(head -n 1 "${gamelistpathtmp}/nes_gamelist.txt")"
        # Write current phase so MCP can apply correct button rules.
        if [[ "$rompath" == "$m82_bios_path" ]]; then
            echo "bios" > "${m82_phase_file}"
            samdebug "M82 phase: bios"
        else
            echo "game" > "${m82_phase_file}"
            samdebug "M82 phase: game ($rompath)"
        fi
        return
    fi

	if [[ "$samvideo" == "yes" ]] && [[ "$samvideo_tvc" == "yes" ]] && [[ -f /tmp/.SAM_tmp/sv_gamename ]]; then
        local sv_gamelist # Declare variable
        local filtered_list="${gamelistpathtmp}/${nextcore}_gamelist.txt"
        local master_list="${gamelistpath}/${nextcore}_gamelist.txt"
        [[ "${Artwork_only,,}" == "yes" ]] && master_list="$sam_artwork_root/eligible/${nextcore}_gamelist.txt"

		if [ ! -f "${filtered_list}" ]; then
            samdebug "Filtered list not found for samvideo, generating..."
			filter_list "${nextcore}"
			# The filter didn't produce results
			if [ $? -ne 0 ]; then
				samdebug "filter_list failed. Falling back to master list for samvideo."
				sv_gamelist="${master_list}"
            else
                samdebug "filter_list succeeded."
                sv_gamelist="${filtered_list}"
			fi
		else
            samdebug "Filtered list already exists."
			sv_gamelist="${filtered_list}"
		fi

		# samvideo mode tries to find a specific game matching a commercial.
        local specific_game
        local search_term=$(cat /tmp/.SAM_tmp/sv_gamename)
        samdebug "Searching for game matching string: $search_term"
        specific_game="$(grep -if /tmp/.SAM_tmp/sv_gamename "$sv_gamelist" | grep -iv "VGM\|MSU\|Disc 2\|Sega CD 32X" | shuf -n 1)"

        if [[ -z "${specific_game}" ]]; then
            samdebug "Match not found in session list. Checking master list..."
            specific_game="$(grep -if /tmp/.SAM_tmp/sv_gamename "$master_list" | grep -iv "VGM\|MSU\|Disc 2\|Sega CD 32X" | shuf -n 1)"
        fi

        if [[ -n "${specific_game}" ]]; then
            rompath="${specific_game}"
		    samdebug "Match found: $specific_game"
            return # Exit successfully if we found the specific game.
        fi
        echo "Could not find matching game for commercial. Picking a random game instead."
    fi

    # 2. Default Action: If no special game modes applied, use the random picker.
    rompath=$(pick_random_game "${nextcore}") || true

    # 3. Final validation.
    if [[ -z "$rompath" ]]; then
        echo "Could not pick a game for ${nextcore}. Check for empty gamelists or overly restrictive filters."
    fi
}

function pick_random_game() {
    local core_type=${1}
    local master_list="${gamelistpath}/${core_type}_gamelist.txt"
    local session_list="${gamelistpathtmp}/${core_type}_gamelist.txt"

    # 3. Apply filter
    if [ ! -s "${session_list}" ]; then
        cp -f "${master_list}" "${session_list}"

        filter_list "${core_type}"
        # Remove any blank or whitespace-only lines
        sed -i '/^[[:space:]]*$/d' "${session_list}"

        # If filtering resulted in an empty list, we must exit.
        if [ ! -s "${session_list}" ]; then
            samdebug "Warning: Filters for '${core_type}' produced an empty list. No games to play." >&2
            return 1
        fi
    fi

    # Recheck standard exclusions even when a cached list was refilled.
    sam_apply_exclusions "$core_type" "$session_list" || return 1

    # 4. Extra validation before selection
    if ! grep -q '[^[:space:]]' "${session_list}"; then
        samdebug "Session list for '${core_type}' contains no valid entries."
        return 1
    fi

    # 5. Pick a random line from the now-filtered session list
    local chosen_path
    chosen_path="$(shuf --random-source=/dev/urandom --head-count=1 "${session_list}")"

    # Sanitize the path to remove any control characters
    : # Preserve literal paths; newline lists cannot encode embedded newlines.

    # 6. Final check: the chosen path must be a real file (unless it's Amiga)
	if [[ "${core_type}" == "arcade" || "${core_type}" == "stv" ]]; then
		if [ ! -f "${chosen_path}" ]; then
			samdebug "ERROR: MRA file not found after pick and sanitize: '${chosen_path}'"
            samdebug "The gamelist for '${core_type}' appears out of date. Triggering rebuild."

            # Delete the stale lists
            rm -f "${master_list}" "${session_list}"

            # Rebuild the master list immediately so we can try again on the next pass
            ensure_list "${core_type}" "${gamelistpath}"

            # The outer selection loop owns bounded retries; do not recurse
            # indefinitely if rebuilding still yields unavailable MRA paths.
            return 1
		fi
	fi

    # 7. If 'norepeat' is enabled, remove the chosen game from the session list
    if [[ "${norepeat}" == "yes" && "${sam_preparing:-0}" != 1 ]]; then
        samdebug "(${core_type}) Removing from list for norepeat: ${chosen_path}"
        awk -vLine="$chosen_path" '!index($0,Line)' "${session_list}" > "${tmpfile}" && mv -f "${tmpfile}" "${session_list}"
    fi

    # Output the chosen path so the caller can capture it
    echo "${chosen_path}"
}
