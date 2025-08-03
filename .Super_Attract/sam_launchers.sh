#!/bin/bash

# This library contains all functions for picking games and launching cores.

# --- High-Level Controller ---

# Orchestrates the entire process of selecting and launching a game for a given core.
function next_core() { # next_core (optional_core)
    local core_to_launch="$1"

    if [[ -n "$cfgcore_configpath" ]]; then
        configpath="$cfgcore_configpath"
    else
        configpath="/media/fat/config/"
    fi

    if [[ ! ${corelist[*]} ]]; then
        echo "ERROR: FATAL - List of cores is empty. Using default."
        corelist=("${corelistall[@]}")
    fi

    # If a core was passed as an argument, use it. Otherwise, pick one.
    if [[ -n "$core_to_launch" ]]; then
        nextcore="$core_to_launch"
    else
        corelist_update
        pick_core
    fi

    # Prepare the gamelists for the chosen core.
    check_list "${nextcore}"
    if [ $? -ne 0 ]; then
        samdebug "check_list function returned an error."
        return 1
    fi
    check_list_update "${nextcore}" &

    # Select a specific game.
    pick_rom

    # Validate the selected game, with retries on failure.
    declare -g romloadfails=0
    local rom_is_valid=false
    while [ ${romloadfails} -lt ${coreretries} ]; do
        if [[ "${nextcore}" == "amiga" ]] || check_rom "${nextcore}"; then
            rom_is_valid=true
            break
        fi
        romloadfails=$((romloadfails + 1))
        if [ ${romloadfails} -lt ${coreretries} ]; then
            samdebug "ROM check failed. Picking a new ROM to try again (${romloadfails}/${coreretries})..."
            pick_rom
        fi
    done

    if [ "$rom_is_valid" = "false" ]; then
        return 1 # All retries failed.
    fi

    delete_played_game
    load_core "${nextcore}" "${rompath}" "${romname%.*}"

    return $? # Pass the exit code from load_core up to the main loop.
}

# --- Game Pickers ---

# Main dispatcher for picking a core based on the configured mode.
function pick_core() {
    local gamelist_count
    gamelist_count=$(find "$gamelistpath" -maxdepth 1 -type f -name '*_gamelist.txt' 2>/dev/null | wc -l)

    if [ "$gamelist_count" -eq 0 ]; then
        samdebug "First run detected. Prioritizing Arcade core."
        if [[ " ${corelistall[*]} " =~ " arcade " ]]; then
            nextcore="arcade"
            return
        fi
    fi

    if [[ "$coreweight" == "yes" ]]; then
        pick_core_weighted
    elif [[ "$samvideo" == "yes" ]]; then
        pick_core_samvideo
    else
        pick_core_standard
    fi

    # Fallback in case a selection function failed.
    if [[ -z "$nextcore" ]]; then
        samdebug "nextcore empty. Using arcade core as fallback."
        nextcore="arcade"
    fi
}

# Worker for standard (uniform random) core selection.
function pick_core_standard() {
    nextcore=$(printf "%s\n" "${corelisttmp[@]}" | shuf --random-source=/dev/urandom -n1)
    samdebug "Picked core (standard): $nextcore"
}


declare -A SAMVC        # tvc counts per core
SAMVTOTAL=0             # sum of all counts
SAMVIDEO_INIT_SENTINEL="/tmp/.sam_tmp/samvideo_init"


function init_core_samvideo() {
    local arr_name=$1
    local core cnt tvc
    local -n arr_ref=$arr_name

    # always (re)load counts into SAMVC & SAMVTOTAL
    SAMVTOTAL=0
    if [[ -f "$core_count_file" ]]; then
        while IFS="=" read -r core cnt; do
            if [[ "$core" == total_count ]]; then
                SAMVTOTAL=$cnt
            else
                SAMVC["$core"]=$cnt
            fi
        done < "$core_count_file"
    else
        for core in "${arr_ref[@]}"; do
            tvc="${gamelistpath}/${core}_tvc.txt"
            cnt=0
            [[ -f "$tvc" ]] && cnt=$(jq -r 'keys|length' "$tvc" 2>/dev/null || echo 0)
            SAMVC["$core"]=$cnt
            (( SAMVTOTAL += cnt ))
        done

        mkdir -p "$(dirname "$core_count_file")"
        : > "$core_count_file"
        for core in "${!SAMVC[@]}"; do
            echo "$core=${SAMVC[$core]}" >> "$core_count_file"
        done
        echo "total_count=$SAMVTOTAL" >> "$core_count_file"
    fi

    # print table only once, guarded by sentinel
    if [[ ! -f "$SAMVIDEO_INIT_SENTINEL" ]]; then
        echo -e "\nCore      TVC-Entries   Percent"
        printf '%.0s─' {1..34}; echo
        for core in "${!SAMVC[@]}"; do
            cnt=${SAMVC[$core]}
            if (( SAMVTOTAL > 0 )); then
                pct=$(awk "BEGIN{printf \"%.2f\", ($cnt*100)/$SAMVTOTAL}")
            else
                pct="0.00"
            fi
            printf "%-8s %10d   %6s%%\n" "$core" "$cnt" "$pct"
        done | sort -k2 -nr
        echo "─────────────────────────────────────────────────────────────────────────────"

        # ensure sentinel directory exists and create sentinel
        mkdir -p "$(dirname "$SAMVIDEO_INIT_SENTINEL")"
        touch "$SAMVIDEO_INIT_SENTINEL"
    fi
}


function pick_core_samvideo() {
    local arr_name=$1
    local -n array=$arr_name

	init_core_samvideo "$arr_name" 

    # now do the weighted pick
    nextcore=$(pick_weighted_random SAMVC "$SAMVTOTAL")
    [[ -z "$nextcore" ]] && nextcore="${array[0]}"

    # debug likelihood
    local w=${SAMVC[$nextcore]:-0}
    local likelihood
    likelihood=$(awk "BEGIN{printf \"%.2f\", ($w*100)/$SAMVTOTAL}")
    samdebug "Picked core (samvideo): $nextcore (likelihood: ${likelihood}%)"
}

# 3) Core-weight mode (weighted by games per core)

declare -A COREWC    # raw game counts per core
declare -A COREP     # mirror of COREWC for pick_weighted_random
TOTAL_GAME_COUNT=0
COREWEIGHT_INITIALIZED=0


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

    # d) mirror COREWC → COREP for picking
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


# ──────────────────────────────────────────────────────────────────────────────
# Game Picker and Checker
# ──────────────────────────────────────────────────────────────────────────────


# Main dispatcher for picking a specific game from a list.
function pick_rom() {
    # Handle special, non-random cases first.
    if [[ "$m82" == "yes" ]]; then
        rompath="$(head -n 1 "${gamelistpathtmp}/nes_gamelist.txt")"
        return
    fi
    if [[ "$samvideo" == "yes" ]] && [[ "$samvideo_tvc" == "yes" ]] && [[ -f /tmp/.sam_tmp/sv_gamename ]]; then
        local specific_game
        specific_game="$(grep -if /tmp/.sam_tmp/sv_gamename "${gamelistpath}/${nextcore}_gamelist.txt" | grep -iv "VGM\|MSU\|Disc 2\|Sega CD 32X" | shuf -n 1)"
        if [[ -n "${specific_game}" ]]; then
            rompath="${specific_game}"
            return
        fi
        samdebug "Could not find matching game for commercial. Picking random."
    fi

    # Default Action: Use the robust random picker.
    rompath=$(pick_random_game "${nextcore}") || true
    
    if [[ -z "$rompath" ]]; then
        echo "Could not pick a game for ${nextcore}." >&2
    fi
}

# Worker for picking a random game from a prepared session list.
function pick_random_game() {
    local core_type=$1
    local session_list="${gamelistpathtmp}/${core_type}_gamelist.txt"

    if [ ! -s "${session_list}" ]; then
        samdebug "Warning: Session list for '${core_type}' is empty." >&2
        return 1
    fi

    local chosen_path
    chosen_path="$(shuf --random-source=/dev/urandom --head-count=1 "${session_list}")"
    chosen_path=$(echo "$chosen_path" | tr -d '[:cntrl:]')

    if [[ "${norepeat}" == "yes" ]]; then
        samdebug "(${core_type}) Removing from list for norepeat: ${chosen_path}"
        awk -vLine="$chosen_path" '!index($0,Line)' "${session_list}" > "${tmpfile}" && mv -f "${tmpfile}" "${session_list}"
    fi

    echo "${chosen_path}"
}

# --- Validator ---

# This function validates a given ROM file ('rompath') against the configuration for a specific core.
# It checks for file existence and ensures the file extension is one of the valid types for that core.
function check_rom() {
    local core="$1"

    if [ -z "${rompath}" ]; then
        echo "ERROR: rompath is empty for core '${core}'." >&2
        return 1
    fi

    local core_config_name=${CORES[$core]}
    declare -n core_config=${core_config_name}

    local extlist="${core_config[valid_exts]}"

    # If 'valid_exts' is empty, no extension check is needed.
    if [[ -z "$extlist" ]]; then
        romname=$(basename "${rompath}")
        return 0
    fi

    # Verify that the ROM file (or the .zip it's inside) actually exists.
    if [[ "${rompath,,}" != *.zip* ]]; then
        if [ ! -f "${rompath}" ]; then
            echo "ERROR: File not found - ${rompath}"
            rm -f "${gamelistpath}/${core}_gamelist.txt"; ensure_list "${core}" "${gamelistpath}"
            return 1
        fi
    else
        local zipfile
        zipfile="$(echo "$rompath" | awk -F".zip" '{print $1}').zip"
        if [ ! -f "${zipfile}" ]; then
            echo "ERROR: Zip file not found - ${zipfile}"
            rm -f "${gamelistpath}/${core}_gamelist.txt"; ensure_list "${core}" "${gamelistpath}"
            return 1
        fi
    fi
    
    romname=$(basename "${rompath}")
    
    # --- Start of Fix ---

    # 1. Extract the file extension and convert it to lowercase immediately.
    # This handles incoming extensions like 'PCE', 'pce', or 'Pce'.
    local extension="${romname##*.}"
    extension="${extension,,}"
    
    # 2. Convert the comma-separated list into a space-separated list for looping.
    local exts_to_loop
    exts_to_loop=$(echo "$extlist" | tr ',' ' ')

    # 3. Loop through each valid extension and perform a direct string comparison.
    local is_valid_ext=false
    for valid_ext in $exts_to_loop; do
        if [[ "$extension" == "$valid_ext" ]]; then
            is_valid_ext=true
            break # Found a match, no need to check further.
        fi
    done

    # 4. Check the result of the loop.
    if ! $is_valid_ext; then
        samdebug "Wrong extension found: '${extension^^}' for core: ${core} rom: ${rompath}"
        ensure_list "${core}" "${gamelistpath}" &
        return 1
    fi
    
    # --- End of Fix ---

    return 0
}
# --- Core Loaders ---

# Main dispatcher that calls the correct loader function based on the core's config.
function load_core() {
    local core="$1"
    local rompath_arg="$2"
    local romname_arg="$3"
    
    local core_config_name=${CORES[$core]}
    if [[ -z "$core_config_name" ]]; then
        echo "ERROR: No configuration found for core '${core}'." >&2
        return 1
    fi
    declare -n core_config=${core_config_name}
    local loader_func=${core_config[loader]:-"loader_standard"}

    # These variables will be set by the loader function.
    local gamename tty_corename launch_cmd mute_target rompath romname post_launch_hook
    
    "$loader_func" "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then return $exit_code; fi

    # --- Common Execution Block (mute, log, TTY display, etc.) ---
    mute "${mute_target}"
    local streamtitle
    if [ "${bgm}" == "yes" ]; then
        streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
    fi

	echo -n "Starting now on the "; echo -ne "\e[4m${core_config[pretty_name]}\e[0m: "; echo -e "\e[1m${gamename}\e[0m"
    [[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"

    echo "$(date +%H:%M:%S) - ${core} - ${rompath:-$gamename}" >>/tmp/SAM_Games.log
    echo "${gamename} (${core})" >/tmp/SAM_Game.txt

    if [ "${ttyenable}" == "yes" ]; then
        local tty_gamename="${gamename}"
        if [[ "${ttyname_cleanup}" == "yes" ]]; then tty_gamename="$(echo "${tty_gamename}" | sed 's/ *([^)]*) *$//')"; fi
        if [[ -n "$streamtitle" ]]; then tty_gamename="${tty_gamename} - BGM: ${streamtitle}"; fi
        
        tty_currentinfo=(
			[core_pretty]="${core_config[pretty_name]}" [name]="${tty_gamename}" [core]="${tty_corename}"
            [date]=$EPOCHSECONDS [counter]=${gametimer} [name_scroll]="${tty_gamename:0:21}"
            [name_scroll_position]=0 [name_scroll_direction]=1 [update_pause]=${ttyupdate_pause}
        )
        declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
        write_to_TTY_cmd_pipe "display_info" &
        SECONDS=$((EPOCHSECONDS - tty_currentinfo[date]))
    fi

    echo "${launch_cmd}" >/dev/MiSTer_cmd
    if [ -n "${post_launch_hook}" ]; then
        eval "${post_launch_hook}"
    fi

    sleep 1
    activity_reset
    return 0
}

# Worker for launching all standard cores by creating a temporary MGL file.
function loader_standard() {
    local core="$1"
    local rompath_arg="$2"
    local romname_arg="$3"
	declare -n core_config=${CORES[$core]}

    rompath="$rompath_arg"
    romname="$romname_arg"
    gamename="$romname_arg"

    if [ "${core}" == "neogeo" ] && [ "${useneogeotitles}" == "yes" ]; then
        for e in "${!NEOGEO_PRETTY_ENGLISH[@]}"; do
            if [[ "$rompath" == *"$e"* ]]; then gamename="${NEOGEO_PRETTY_ENGLISH[$e]}"; break; fi
        done
    fi
    
    tty_corename="${core_config[tty_icon]}"
    mute_target="${core_config[launch_name]}"

    {
        echo "<mistergamedescription>"
        echo "<rbf>${core_config[rbf_path]}/${core_config[mgl_rbf]}</rbf>"
        echo "<file delay=\"${core_config[mgl_delay]}\" type=\"${core_config[mgl_type]}\" index=\"${core_config[mgl_index]}\" path=\"../../../../..${rompath}\"/>"
        [ -n "${core_config[mgl_setname]}" ] && echo "<setname>${core_config[mgl_setname]}</setname>"
    } >/tmp/SAM_Game.mgl
    
    launch_cmd="load_core /tmp/SAM_Game.mgl"
    
    if [[ "${core_config[can_skip_bios]}" == "yes" ]]; then
        skipmessage "${core}" &
    fi
    return 0
}

# Worker for launching MRA-based cores (Arcade, ST-V).
function loader_arcade() {
    local core="$1"
    rompath=$(pick_random_game "${core}")
    rompath=$(echo "$rompath" | tr -d '[:cntrl:]')
    
    if [ ! -f "${rompath}" ]; then return 1; fi

    gamename="$(basename "${rompath//.mra/}")"
    tty_corename=$(grep "<setname>" "${rompath}" | sed -e 's/<setname>//' -e 's/<\/setname>//' | tr -cd '[:alnum:]')
    mute_target="${tty_corename:-$gamename}"
    launch_cmd="load_core ${rompath}"
    return 0
}

# Worker for launching the Amiga core.
function loader_amiga() {
    local core="$1"
	declare -n core_config=${CORES[$core]}

    if ! [ -f "${core_config[prereq_file]}" ]; then
        echo "ERROR - MegaAGS/AmigaVision pack not found." >&2; delete_from_corelist amiga; return 1
    fi

    local amiga_title_raw=$(pick_random_game "amiga")
    if [ -z "${amiga_title_raw}" ]; then return 1; fi

    gamename="$(echo "${amiga_title_raw}" | sed 's/Demo: //' | tr '_' ' ')"
    echo "${amiga_title_raw//Demo: /}" > "${amigapath}/shared/ags_boot"
    rompath="${gamename}"

    tty_corename="${core_config[tty_icon]}"
    mute_target="${core_config[launch_name]}"
    launch_cmd="load_core ${amigacore}"
    return 0
}

# --- Helpers ---
function delete_played_game() {
	if [ "${norepeat}" == "yes" ]; then
		awk 'BEGIN{v=1} $0==line && v{v=0; next} 1' line="$rompath" "${gamelistpathtmp}/${nextcore}_gamelist.txt" > "${tmpfile}" && mv "${tmpfile}" "${gamelistpathtmp}/${nextcore}_gamelist.txt"
	fi
}
