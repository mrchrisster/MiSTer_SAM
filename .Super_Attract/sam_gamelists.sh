#!/bin/bash

# This library contains all functions for building and managing gamelists.

# --- High-Level Dispatcher ---
# This is the main entry point for creating any gamelist. It determines which
# specific builder function to use based on the core's configuration.
function ensure_list() {
    local core_type="$1"
    local dest_dir="${2:-$gamelistpath}"
    local list_file="${dest_dir}/${core_type}_gamelist.txt"
    
    if [ -s "${list_file}" ]; then return 0; fi
    samdebug "Gamelist for '${core_type}' not found in '${dest_dir}'. Building..."

    local core_config_name=${CORES[$core_type]}
    declare -n core_config=$core_config_name
    local builder_func=${core_config[builder]:-"build_gamelist_standard"}

    if type -t "$builder_func" > /dev/null; then
        "$builder_func" "$core_type" "$dest_dir"
    else
        samdebug "ERROR: Builder function '$builder_func' not found for '${core_type}'."
        return 1
    fi
    
    if [ ! -s "${list_file}" ]; then
        samdebug "ERROR: Failed to create or find games for '${core_type}' in '${dest_dir}'." >&2
        return 1
    fi
    return 0
}

# --- Worker Functions (Builders) ---

# Builds lists for standard cores using the samindex tool.
function build_gamelist_standard() {
    local core="$1"
    local outdir="${2:-$gamelistpath}"
    local file="${outdir}/${core}_gamelist.txt"
    local rc

    if ps -ef | grep -i '[s]amindex' &>/dev/null; then
        samdebug "JIT build for '${core}' taking priority. Stopping background samindex."
        ps -ef | grep -i '[s]amindex' | xargs --no-run-if-empty kill &>/dev/null
        sleep 0.5
    fi

    samdebug "Building gamelist for ${core} in ${outdir}"
    mkdir -p "$outdir"
    sync "$outdir"
    sleep 1

    "${mrsampath}/tools/samindex" -q -s "$core" -o "$outdir"
    rc=$?

	# Check if the build process failed during the initial run.
    if [[ "$outdir" == "$gamelistpath" ]] && (( rc > 1 )); then
        # On initial build, an exit code > 1 means "no games found".
        delete_from_corelist "$core"
                
        local core_config_name=${CORES[$core]}       
        local pretty_name_ref="${core_config_name}[pretty_name]"
        echo "Can't find games for ${!pretty_name_ref}"
                
        samdebug "build_gamelist_standard returned code $rc for $core"
        return 1 # Return an error
    fi

    if [[ -f "$file" ]]; then
        sort -u "$file" -o "$file"
    fi
    return 0
}

# Builds lists for MRA-based cores (Arcade, ST-V) using the find command.
function build_mra_list() {
    local core_type="$1"
    local dest_dir="${2:-$gamelistpath}"
    local output_file="${dest_dir}/${core_type}_gamelist.txt"
    local mra_path

    case "${core_type}" in
        "stv") mra_path="/media/fat/_Arcade/_ST-V" ;;
        "arcade") mra_path="/media/fat/_Arcade" ;;
        *) samdebug "ERROR: build_mra_list called with unsupported core '${core_type}'"; return 1 ;;
    esac

    if [ ! -d "${mra_path}" ]; then
        echo "The path ${mra_path} does not exist!"
        : > "${output_file}"
        return 0
    fi

    if ! find "${mra_path}" -type f -iname "*.mra" -print -quit | grep -q .; then
        echo "The path ${mra_path} contains no MRA files!"
        : > "${output_file}"
        return 0
    fi

    find "${mra_path}" -not -path '*/.*' -type f -iname "*.mra" > "${output_file}"
    samdebug "Created ${core_type} MRA gamelist in '${dest_dir}'."
    sync "${output_file}"
}

# Builds lists for MGL-based computer cores (ao486, x68k).
function build_mgl_list() {
    local core_type="$1"
    local dest_dir="${2:-$gamelistpath}"
    local output_file="${dest_dir}/${core_type}_gamelist.txt"
    local search_paths=()
    local existing_paths=()

    case "${core_type}" in
        "ao486") search_paths=("/media/fat/_DOS Games" "/media/fat/_Computer/_DOS Games") ;;
        "x68k") search_paths=("/media/fat/_X68000 Games" "/media/fat/_Computer/_X68000 Games") ;;
        *) samdebug "No MGL search path defined for ${core_type}."; return 1 ;;
    esac

    for path in "${search_paths[@]}"; do
        [ -d "$path" ] && existing_paths+=("$path")
    done

    if [ ${#existing_paths[@]} -eq 0 ]; then
        samdebug "No valid MGL search directories found for ${core_type}."
        : > "${output_file}"
        return 0
    fi

    find "${existing_paths[@]}" -type f -iname '*.mgl' 2>/dev/null > "${output_file}"

    if [ ! -s "${output_file}" ]; then
        samdebug "No .mgl files found for ${core_type}—disabling core."
        delete_from_corelist "${core_type}"
        return 1
    fi
    samdebug "Created ${core_type} gamelist in '${dest_dir}' with $(wc -l < ${output_file}) entries."
}

# Builds the unique title-based list for the Amiga core.
function build_amiga_list() {
    local core_type="$1"
    local dest_dir="${2:-$gamelistpath}"
    local output_file="${dest_dir}/${core_type}_gamelist.txt"
    local demos_file="${amigapath}/listings/demos.txt"
    local games_file="${amigapath}/listings/games.txt"

    if [ ! -f "${games_file}" ]; then
        echo "ERROR: Can't find Amiga games.txt file at '${games_file}'"
        : > "${output_file}"
        return 1
    fi

    > "${output_file}"

    if [[ "${amigaselect}" == "demos" ]] || [[ "${amigaselect}" == "all" ]]; then
        if [ -f "${demos_file}" ]; then
            sed 's/^/Demo: /' "${demos_file}" >> "${output_file}"
        fi
    fi

    if [[ "${amigaselect}" == "games" ]] || [[ "${amigaselect}" == "all" ]]; then
        cat "${games_file}" >> "${output_file}"
    fi

    if [ ! -s "${output_file}" ]; then
        samdebug "No Amiga games or demos matched current selection (${amigaselect})."
        return 1
    fi
    samdebug "$(wc -l < ${output_file}) Amiga Games/Demos found for list in '${dest_dir}'."
    sync "${output_file}"
}

# --- Management and Filtering ---

# Prepares the master and session lists for a given core just-in-time.
function check_list() {
    local core_type="$1"
    local session_list="${gamelistpathtmp}/${core_type}_gamelist.txt"

    # 1. Ensure the master gamelist exists. Exit if it fails.
    ensure_list "${core_type}" "${gamelistpath}" || return 1

    # 2. Handle special session list modes (GOAT, M82).
    if [ "${sam_goat_list}" == "yes" ] && [ ! -s "${session_list}" ]; then
        build_goat_lists; return 0
    fi
    if [ "${m82}" == "yes" ]; then
        build_m82_list; return 0
    fi

    # 3. Default action: Copy master to session list if it doesn't exist yet.
    if [ ! -s "${session_list}" ]; then
        cp "${gamelistpath}/${core_type}_gamelist.txt" "${session_list}" 2>/dev/null
    fi
    
    # 4. Apply filters to the session list.
    filter_list "${core_type}"
    if [ $? -ne 0 ]; then
        samdebug "filter_list encountered an error"
    fi
    
    return 0
}

# Kicks off a background process to build all missing standard gamelists.
function create_all_gamelists() {
    if (( gamelists_created )); then return 0; fi
    gamelists_created=1

    (
        sleep 15 # Wait for the first core to launch before starting.
        samdebug "Starting background build of standard gamelists..."
        for c in "${corelist[@]}"; do
            if [[ ! " ${special_cores[*]} " =~ " ${c} " ]]; then
                ensure_list "${c}" "${gamelistpath}"
            fi
        done
        samdebug "Background build process complete."
    ) &
}

# Checks for differences between the master list and a fresh scan.
function check_list_update() {
    local core="$1"
    local flag_dir="${gamelistpathtmp}/.checked"
    mkdir -p "$flag_dir"
    local flag_file="$flag_dir/$core"
    if [ -e "$flag_file" ]; then return; fi
    touch "$flag_file"
    
    if [[ "$m82" == "yes" ]]; then return 0; fi

    (
        local orig="${gamelistpath}/${core}_gamelist.txt"
        local compdir="${gamelistpathtmp}/comp"
        local comp="${compdir}/${core}_gamelist.txt"
        mkdir -p "$compdir"
        
        sleep 10 # Delay before running the comparison build.
        ensure_list "$core" "$compdir"
        
        if ! diff -q <(sort "$orig") <(sort "$comp") &>/dev/null; then
            samdebug "[${core}] Gamelist has changed, updating master list…"
            sort "$comp" -o "$orig"
            samdebug "[${core}] Gamelist updated."
        else
            samdebug "[${core}] No changes detected in ${core} gamelist."
        fi
    ) &
}

# Applies all user-configured filters to the session gamelist.
function filter_list() {
    local core=$1
    local session_list="${gamelistpathtmp}/${core}_gamelist.txt"
    local flag_dir="${gamelistpathtmp}/.checked"
    mkdir -p "$flag_dir"
    local flag_file="$flag_dir/$core.filtered"
    
    if [ -e "$flag_file" ]; then
        samdebug "Filters for '${core}' already applied this session. Skipping."
        return 0
    fi

    cp -f "${session_list}" "${tmpfile}"
    
    if [ -n "${PATHFILTER[${core}]}" ]; then
        grep -F "${PATHFILTER[${core}]}" "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    fi

    if [ "$dupe_mode" = "strict" ]; then
        awk -F'/' '{full=$0; lowpath=tolower(full); if (lowpath ~ /\/[^\/]*(hack|beta|proto)[^\/]*\//) next; fname=$NF; if (tolower(fname) ~ /\([^)]*(hack|beta|proto)[^)]*\)/) next; name=fname; sub(/\.[^.]+$/, "", name); sub(/\s*\(.*/, "", name); sub(/^([0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?|[0-9]+)[^[:alnum:]]*/, "", name); key=tolower(name); gsub(/^[ \t]+|[ \t]+$/, "", key); if (!seen[key]++) print full}' "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    else
        awk -F'/' '!seen[$NF]++' "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    fi

    if [ -s "${gamelistpath}/${core}_gamelist_exclude.txt" ]; then
		awk 'FNR==NR{a[$0];next} !($0 in a)' "${gamelistpath}/${core}_gamelist_exclude.txt" "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
	fi

    if [ -f "${gamelistpath}/${core}_excludelist.txt" ]; then
        awk -v EXCL="${gamelistpath}/${core}_excludelist.txt" 'BEGIN{while(getline line<EXCL){raw[line]=1;name=line;sub(/\.[^.]*$/,"",name);sub(/^.*\//,"",name);names[name]=1}close(EXCL)}{file=$0;base=file;sub(/\.[^.]*$/,"",base);sub(/^.*\//,"",base);if(file in raw||base in names)next;print}' "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    fi

    if [ "${rating}" != "no" ]; then
        apply_ratings_filter "${core}" "${tmpfile}"
    fi

    if [ "${disable_blacklist}" == "no" ] && [ -f "${gamelistpath}/${core}_blacklist.txt" ]; then
        awk "BEGIN{while(getline<\"${gamelistpath}/${core}_blacklist.txt\"){a[\$0]=1}} {gamelistfile=\$0;sub(/\\.[^.]*\$/,\"\",gamelistfile);sub(/^.*\\//,\"\",gamelistfile);if(!(gamelistfile in a))print}" "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    fi

    cp -f "${tmpfile}" "${session_list}"
    echo "$(wc -l <"${session_list}") games are now in the active shuffle list." >&2

    if [ ! -s "${session_list}" ]; then
        echo "Error: All filters combined produced an empty list for '${core}'." >&2
        delete_from_corelist "${core}"
        return 1
    fi
    touch "$flag_file"
    return 0
}

# Helper function for the ratings filter.
function apply_ratings_filter() {
    local core=${1}
    local target_file=${2} # Pass the file to modify ($tmpfile)
		echo "Ratings Mode ${rating} active - Filtering Roms..."	
		if [ "${rating}" == "kids" ]; then
				if [ ${1} == amiga ]; then
					fgrep -f "${mrsampath}/SAM_Rated/amiga_rated.txt" <(fgrep -v "Demo:" "${gamelistpath}/amiga_gamelist.txt") | awk -F'(' '!seen[$1]++ {print $0}' > "${tmpfilefilter}"
				else
					fgrep -f "${mrsampath}/SAM_Rated/${1}_rated.txt" "${gamelistpathtmp}/${1}_gamelist.txt" | awk -F "/" '{split($NF,a," \\("); if (!seen[a[1]]++) print $0}' > "${tmpfilefilter}"
				fi
				if [ -s "${tmpfilefilter}" ]; then 
					samdebug "$(wc -l <"${tmpfilefilter}") games after kids safe filter applied."
					cp -f "${tmpfilefilter}" "${gamelistpathtmp}/${1}_gamelist.txt"
				else
					delete_from_corelist "${1}"
					delete_from_corelist "${1}" tmp
					echo "${1} kids safe filter produced no results and will be disabled."
					echo "List of cores is now: ${corelist[*]}"
					return 1
				fi
		else
			# $1 is the core name
			rated_file="${mrsampath}/SAM_Rated/${1}_mature.txt"
			if [[ ! -f "$rated_file" ]]; then
			  samdebug "No ${1}_mature.txt found—skipping mature filter."
			else
			  # load your mature names
			  mapfile -t rated_list <"$rated_file"

			  # prepare output file
			  : >"$tmpfilefilter"

			  # choose which gamelist to read (and strip Demos for amiga)
			  if [[ "$1" == "amiga" ]]; then
				gamelist_src="${gamelistpath}/amiga_gamelist.txt"
				readarray -t games < <(grep -v '^Demo:' "$gamelist_src")
			  else
				gamelist_src="${gamelistpathtmp}/${1}_gamelist.txt"
				readarray -t games < <(cat "$gamelist_src")
			  fi

			  declare -A seen
			  for line in "${games[@]}"; do
				# strip dir + extension
				name="${line##*/}"
				name="${name%.*}"
				name_lc="${name,,}"

				# loose substring match
				for entry in "${rated_list[@]}"; do
				  entry_lc="${entry,,}"
				  if [[ "$name_lc" == *"$entry_lc"* ]]; then
					if [[ -z "${seen[$name_lc]}" ]]; then
					  seen[$name_lc]=1
					  printf '%s\n' "$line" >>"$tmpfilefilter"
					fi
					break
				  fi
				done
			  done

			  if [[ -s "$tmpfilefilter" ]]; then
				samdebug "$(wc -l <"$tmpfilefilter") games after mature filter applied."
				cp -f "$tmpfilefilter" "${gamelistpathtmp}/${1}_gamelist.txt"
			  else
				delete_from_corelist "$1"
				delete_from_corelist "$1" tmp
				echo "${1} mature filter produced no results and will be disabled."
				echo "List of cores is now: ${corelist[*]}"
				return 1
			  fi
			fi

		fi
}


# --- Special Mode Builders ---
function build_goat_lists() {
	local goat_flag="/tmp/.SAM_tmp/goatmode.ready"
	local goat_list_path="${gamelistpath}/sam_goat_list.txt"
	
	echo "SAM GOAT Mode active"
	
	# Already built this session?
	[[ -f "$goat_flag" ]] && return
	
	# Ensure working dir
	mkdir -p "${gamelistpathtmp}" /tmp/.SAM_tmp
	
	# Download master list if missing
	if [[ ! -f "$goat_list_path" ]]; then
	samdebug "Downloading GOAT master list..."
	get_samstuff .Super_Attract/lists/filter_special_modes/sam_goat_list.txt "$gamelistpath"
	fi
	
	# Parse master list into per-core tmp files
	local current_core=""
	while IFS= read -r line; do
	if [[ "$line" =~ ^\[(.+)\]$ ]]; then
	  current_core="${BASH_REMATCH[1],,}"
	  [[ ! -f "${gamelistpath}/${current_core}_gamelist.txt" ]] && build_gamelist "$current_core"
	elif [[ -n "$current_core" ]]; then
	  fgrep -i -m1 "$line" "${gamelistpath}/${current_core}_gamelist.txt" \
		>> "${gamelistpathtmp}/${current_core}_gamelist.txt"
	fi
	done < "$goat_list_path"
	
	# Gather cores with entries
	readarray -t corelist < <(
	find "${gamelistpathtmp}" -name "*_gamelist.txt" \
	  -exec basename {} \; | cut -d '_' -f1
	)
	printf "%s\n" "${corelist[@]}" > "${corelistfile}"
	
	# Update INI corelist if changed
	local newvalue; newvalue="$(IFS=,; echo "${corelist[*]}")"
	if ! grep -q "^corelist=\"$newvalue\"" "$samini_file"; then
		samini_mod corelist "$newvalue"
	fi
	
	# Enable GOAT flag
	if ! grep -q '^sam_goat_list="yes"' "$samini_file"; then
		samini_mod sam_goat_list yes
	fi
	
	# Mark as built
	touch "$goat_flag"
}

function build_m82_list() {
	[ ! -d "/tmp/.sam_list" ] && mkdir /tmp/.sam_list/ 
	[ ! -d "/tmp/.SAM_tmp" ] && mkdir /tmp/.SAM_tmp/

	if [ ! -f "${gamelistpath}"/nes_gamelist.txt ]; then
		samdebug "Creating NES gamelist"
		${mrsampath}/samindex -q -s "nes" -o "${gamelistpath}" 
		if [ $? -gt 1 ]; then
			echo "Error: NES gamelist missing. Make sure you have NES games." 
		fi
	fi
	if [ -f "${gamelistpathtmp}"/nes_gamelist.txt ]; then
		rm "${gamelistpathtmp}"/nes_gamelist.txt
	fi
	local m82_list_path="${gamelistpath}"/m82_list.txt
	# Check if the M82 list file exists
	if [ ! -f "$m82_list_path" ]; then
		echo "Error: The M82 list file ($m82_list_path) does not exist. Updating SAM now. Please try again."
		repository_url="https://github.com/mrchrisster/MiSTer_SAM"
		get_samstuff .Super_Attract/lists/filter_special_modes/m82_list.txt "${gamelistpath}"
	fi

	printf "%s\n" nes > "${corelistfile}"
	if [[ "$m82_muted" == "yes" ]]; then
		mute="global"
	else
		mute="no"
		only_unmute_if_needed
	fi
	gametimer="21"
	listenjoy=no
}
