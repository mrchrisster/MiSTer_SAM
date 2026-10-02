function check_list() {
    local core_type="$1"
    local mode="$2"
    local session_list="${gamelistpathtmp}/${core_type}_gamelist.txt"
    : # Optional candidate filtering is owned by registered modules.

    # 1. Ensure we have Master game list if it doesn't exist. Exit if it fails.
    ensure_list "${core_type}" "${gamelistpath}" || return 1

    # 2. Create "comparison" game lists to /tmp to check if we have new games
    if [[ "${mode}" == "comp" ]]; then
        local comp_dir="${gamelistpath}/comp"
        mkdir -p "${comp_dir}" # Ensure the 'comp' subdirectory exists
        ensure_list "${core_type}" "${comp_dir}"
    fi

    # 3. Handle special session lists (GOAT, M82, etc.)
    if [ "${sam_goat_list}" == "yes" ] && [ ! -s "${gamelistpathtmp}/${1}_gamelist.txt" ]; then
        cp "$gamelistpath/${core_type}_gamelist.txt" "$session_list" || return 1
        filter_list "$core_type" || return 1
        sam_curated_filter "$core_type"
        return
    fi

    # m82 populate lists
    if [ "${m82}" == "yes" ]; then
        # --- Find M82 BIOS (once per session) ---
        if [[ -z "$m82_bios_path" ]]; then
            echo -n "M82 mode active. Finding M82 bios..."
            # Search the master NES list for the BIOS file and store its path globally
            declare -g m82_bios_path
            m82_bios_path="$(fgrep -i "m82 game" "$gamelistpath/nes_gamelist.txt" | head -n 1)"
            echo "Success."
            samdebug "m82 bios found at: $m82_bios_path"
        fi

        # --- Validate BIOS was found ---
        if [[ -z "$m82_bios_path" ]]; then
            echo "Error: No suitable M82 BIOS found in your nes folder. The file should be named 'M82 Game[...].nes'"
            exit 1
        fi

        # --- Advance the list (runs when a game has just been played) ---
        # The session list is trimmed here, at the start of the NEXT cycle, so
        # pick_rom (head -1) always reads the entry that was already played and
        # we move past it before the new pick happens.
        if [ -s "${session_list}" ]; then
            sed -i '1d' "${session_list}"
        fi

        # --- Create the special M82 session list if it doesn't exist ---
        if [ ! -s "${session_list}" ]; then
            samdebug "Creating M82 game list from m82_list.txt"
            # Each game is preceded by a BIOS entry: BIOS, game1, BIOS, game2, ...
            while IFS= read -r line; do
                echo "$m82_bios_path"
                fgrep "$line" "${gamelistpath}/nes_gamelist.txt" | head -n 1
            done < "${gamelistpath}/m82_list.txt" > "${session_list}"

            samdebug "Found the following games: \n$(cat "${session_list}" | grep -iv m82)"
            samdebug "Found $(cat "${session_list}" | grep -iv m82 | wc -l) games"
        fi

        # --- "Next" button skip: user pressed next, so skip any BIOS at the top ---
        # On timer expiry the cycle is: game → BIOS → next_game (correct).
        # When "next" is pressed we go directly game → next_game (no BIOS interlude).
        # This also handles the wrap: last_game → [rebuild] → BIOS1 → skip → game1.
        if [[ "$SAM_ACTION" == "next" ]] && [ -s "${session_list}" ]; then
            local _next_entry
            _next_entry="$(head -n 1 "${session_list}")"
            if [[ "$_next_entry" == "$m82_bios_path" ]]; then
                samdebug "M82: 'next' pressed — skipping BIOS entry, jumping to game"
                sed -i '1d' "${session_list}"
                # If skipping BIOS emptied the list, rebuild and skip the first BIOS again
                if [ ! -s "${session_list}" ]; then
                    samdebug "M82: list empty after BIOS skip — rebuilding and skipping first BIOS"
                    while IFS= read -r line; do
                        echo "$m82_bios_path"
                        fgrep "$line" "${gamelistpath}/nes_gamelist.txt" | head -n 1
                    done < "${gamelistpath}/m82_list.txt" > "${session_list}"
                    sed -i '1d' "${session_list}"  # skip the leading BIOS of the new cycle
                fi
            fi
        fi
        SAM_ACTION=""  # consumed; clear so it doesn't bleed into the next cycle

		sync

        # --- Finalize M82 state for this cycle ---
        gametimer="21"
        return
    fi

    # 4. Default action: Copy the master list to the temp session directory if no
    #    special session list (like M82) was created.
    if [ ! -s "${session_list}" ]; then
        cp "${gamelistpath}/${core_type}_gamelist.txt" "${session_list}" 2>/dev/null
    fi

	filter_list "${core_type}"
	if [ $? -ne 0 ]; then
		samdebug "filter_list encountered an error"
	fi

    return 0
}

function create_all_gamelists() {
    # This function now only runs once per script invocation.
    if (( gamelists_created )); then
        return 0
    fi
    gamelists_created=1

    # Run the entire process in a subshell in the background (&)
    (
        # Wait a moment before starting the background build to keep resources free.
        sleep 15

        samdebug "Starting background build of standard gamelists..."

        for c in "${corelist[@]}"; do
            # Only process non-special cores
            if [[ ! " ${special_cores[*]} " =~ " ${c} " ]]; then
                # Use the dispatcher to handle the check and call the correct builder.
                # This is cleaner and respects your modular design.
                ensure_list "${c}" "${gamelistpath}"
            fi
        done

        samdebug "Background build process complete."
    ) &
}

function schedule_gamelist_updates() {
        local core
		[[ "$check_for_new_games" != "Yes" ]] && return
        for core in ${corelist//,/ }; do
                check_list_update "$core"
        done
}

function check_list_update() {
    [[ "$check_for_new_games" != "Yes" ]] && return
    local core="$1"
    local orig="${gamelistpath}/${core}_gamelist.txt"
    local compdir="${gamelistpathtmp}/comp"
    local comp="${compdir}/${core}_gamelist.txt"

	# ── only run this check once per core, per session ──
	local flag_dir="${gamelistpathtmp}/.checked"
	mkdir -p "$flag_dir"
	local flag_file="$flag_dir/$core"
	if [ -e "$flag_file" ]; then
	    return
	fi
	touch "$flag_file"

	# Skip for special modes like M82 that have their own list logic
	if [[ "$m82" == "yes" ]]; then
		return 0
	fi

    (
		mkdir -p "$compdir"

		#wait before building comparison lists
		sleep 10

		ensure_list "$core" "$compdir"

		# Now, compare the sorted original list with the new sorted comparison list
		if ! diff -q <(sort "$orig") <(sort "$comp") &>/dev/null; then
			samdebug "[${core}] Gamelist has changed, updating master list…"

			# Log up to 10 lines of differences for debugging
			samdebug "[${core}] DIFF:"
			comm -3 <(sort "$orig") <(sort "$comp") | head -n10 | \
				while read -r ln; do samdebug "    $ln"; done

			# Overwrite the original list with the sorted new one
			sort "$comp" -o "$orig"
			samdebug "[${core}] Gamelist updated."
		else
			samdebug "[${core}] No changes detected in ${core} gamelist."
		fi
    ) &
}

# Legacy modes retain their own ordered lists and do not use the normal queue.
sam_compat_ensure_list() {
    local core="$1" out="${2:-$gamelistpath}"
    [[ -s "$out/${core}_gamelist.txt" ]] && return 0
    mkdir -p "$out"
    case "$core" in
        arcade|stv) build_mra_list "$core" "$out" ;;
        ao486|x68k|mgls) build_mgl_list "$core" "$out" ;;
        amiga) sam_adapter_paths amiga && build_amiga_list "$core" "$out" ;;
        *) build_gamelist "$core" "$out" ;;
    esac
    [[ -s "$out/${core}_gamelist.txt" ]]
}
ensure_list() { sam_compat_ensure_list "$@"; }
declare -A COREWC=() COREP=()
TOTAL_GAME_COUNT=0 COREWEIGHT_INITIALIZED=0
