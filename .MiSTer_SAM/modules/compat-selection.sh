# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function corelist_update() {

	#Single Core Mode
	if [ -s "${corelistfile}.single" ]; then
		unset corelist
		mapfile -t corelist < "${corelistfile}.single"
		rm "${corelistfile}.single" "${corelistfile}" > /dev/null 2>&1

	elif [ -s "${corelistfile}" ]; then
		unset corelist
		mapfile -t corelist < "${corelistfile}"
		rm "${corelistfile}"
	fi

	# BGM mode: n64, saturn and psx are incompatible with BGM (no per-core volume control).
	# Filter them out here so the rule is enforced regardless of how corelist was set.
	if [[ "${bgm}" == "yes" ]]; then
		local bgm_filtered=()
		for core in "${corelist[@]}"; do
			[[ "$core" != "n64" && "$core" != "psx" && "$core" != "saturn" ]] && bgm_filtered+=("$core")
		done
		corelist=("${bgm_filtered[@]}")
	fi

	# Resynchronize corelisttmp with the potentially updated corelist
	declare -A valid_cores_map
	for core in "${corelist[@]}"; do
		valid_cores_map["$core"]=1
	done

	local updated_corelisttmp=()
	for tmp_core in "${corelisttmp[@]}"; do
		if [[ -n "${valid_cores_map["$tmp_core"]}" ]]; then
			updated_corelisttmp+=("$tmp_core")
		fi
	done
	corelisttmp=("${updated_corelisttmp[@]}")


	if [[ "${disablecoredel}" == "0" ]]; then
		delete_from_corelist "$nextcore" tmp
	fi


	if [ ${#corelisttmp[@]} -eq 0 ]; then
		declare -ga corelisttmp=("${corelist[@]}")
	fi

	if [[ ! "${corelisttmp[*]}" ]]; then
		corelisttmp=("${corelist[@]}")
	fi
}

function pick_core() {
    # SAFETY: If in SINGLE mode, Force Target Core
    if [ "$SAM_MODE" == "SINGLE" ] && [ -n "$SAM_TARGET_CORE" ]; then
        nextcore="$SAM_TARGET_CORE"
        samdebug "pick_core: Single mode active. Forcing core: $nextcore"
        return
    fi

    # If it's not a first run, proceed with the standard mode selection.
    if [[ "$coreweight" == "yes" ]]; then
        pick_core_weighted
    elif [[ "$samvideo" == "yes" ]]; then
        pick_core_samvideo "$1"
    else
        pick_core_standard
    fi

    # Fallback in case a selection function failed
    if [[ -z "$nextcore" ]]; then
        samdebug "nextcore empty. Using arcade core as fallback."
        nextcore="arcade"
    fi
}

function pick_core_standard() {
    nextcore=$(printf "%s\n" "${corelisttmp[@]}" \
               | shuf --random-source=/dev/urandom -n1)
    samdebug "Picked core (standard): $nextcore"
}

function init_core_weighted() {
    # only run once
    (( COREWEIGHT_INITIALIZED )) && return
    COREWEIGHT_INITIALIZED=1

    echo -n "Please wait while calculating core weights..."

    # a) ensure every core has a gamelist
    for c in "${corelist[@]}"; do
        f="${gamelistpathtmp}/${c}_gamelist.txt"
        [[ -f "$f" ]] || check_list "$c" >/dev/null
    done

    # b) build raw counts & total
    TOTAL_GAME_COUNT=0
    for c in "${corelist[@]}"; do
        f="${gamelistpathtmp}/${c}_gamelist.txt"
        if [[ -f "$f" ]]; then
            COREWC["$c"]=$(wc -l < "$f")
            (( TOTAL_GAME_COUNT += COREWC["$c"] ))
        fi
    done

    # c) fallback to equal if truly empty
    if (( TOTAL_GAME_COUNT == 0 )); then
        for c in "${corelist[@]}"; do
            COREWC["$c"]=1
        done
        TOTAL_GAME_COUNT=${#corelist[@]}
    fi

    # d) mirror COREWC -> COREP for picking
    for c in "${!COREWC[@]}"; do
        COREP["$c"]=${COREWC["$c"]}
    done

    # e) print table of counts & percentages
    echo -e "\nCore      Games   Percent"
    printf '%.0s─' {1..28}; echo
    for core in "${!COREWC[@]}"; do
        cnt=${COREWC[$core]}
        pct=$(awk "BEGIN{printf \"%.2f\", ($cnt*100)/${TOTAL_GAME_COUNT}}")
        printf "%-8s %6d   %6s%%\n" "$core" "$cnt" "$pct"
    done | sort -k2 -nr

    echo " Done."
}

function pick_core_weighted() {
    init_core_weighted

    # fast pick from prebuilt COREP/TOTAL_GAME_COUNT
    nextcore=$(pick_weighted_random COREP "$TOTAL_GAME_COUNT")
    [[ -z "$nextcore" ]] && nextcore="${corelist[0]}"

    # debug likelihood
    local w=${COREP[$nextcore]}
    local likelihood=$(awk "BEGIN{printf \"%.2f\", ($w*100)/$TOTAL_GAME_COUNT}")
    samdebug "Picked core (coreweight): $nextcore (likelihood: ${likelihood}%)"
}

function pick_weighted_random() {
    local -n weights=$1
    local total=$2
    (( total<=0 )) && echo "" && return

    local pick sum=0
    pick=$(shuf --random-source=/dev/urandom -i 1-"$total" -n1)
    for key in "${!weights[@]}"; do
        (( sum += weights[$key] ))
        if (( pick <= sum )); then
            echo "$key"
            return
        fi
    done
    echo ""
}

function pick_rom() {
    sam_emit candidate_filter "$nextcore" || return 1
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

            # RECURSIVE CALL: Try to pick again immediately from the fresh list
            pick_random_game "${core_type}"
			return $?
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
