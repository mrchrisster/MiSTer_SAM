# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function build_mra_list() {
    # Accept core and destination directory arguments
    local core_type="$1"
    local dest_dir="${2:-$gamelistpath}"
    local output_file="${dest_dir}/${core_type}_gamelist.txt"
    local mra_path

    # 1. Determine the correct search path based on the core.
    case "${core_type}" in
        "stv")
            mra_path="$misterpath/_Arcade/_ST-V"
            ;;
        "arcade")
            mra_path="$misterpath/_Arcade"
            ;;
        *)
            samdebug "ERROR: build_mra_list called with unsupported core '${core_type}'"
            return 1
            ;;
    esac

    # 2. Check if the search directory exists.
    if [ ! -d "${mra_path}" ]; then
        echo "The path ${mra_path} does not exist!"
        : > "${output_file}" # Create empty list to prevent re-running
        return 0
    fi

    # Check if the directory contains any MRA files before running a full find.
    if ! find "${mra_path}" -type f -iname "*.mra" -print -quit | grep -q .; then
        echo "The path ${mra_path} contains no MRA files!"
        : > "${output_file}" # Create empty list
        return 0
    fi

    # 3. Build the list directly into the destination file using find.
    find "${mra_path}" -not -path '*/.*' -type f -iname "*.mra" > "${output_file}"

    samdebug "Created ${core_type} MRA gamelist in '${dest_dir}'."
    sync "${output_file}"
}

function build_mgl_list() {
    # Accept core and destination directory arguments
    local core_type="$1"
	local dest_dir="${2:-$gamelistpath}"

    # Define paths, making the output file dynamic
    local search_paths
    local output_file="${dest_dir}/${core_type}_gamelist.txt"
    local game_count
    local existing_paths=()

    # Determine which directories to search based on the core
    case "${core_type}" in
       "ao486")
           search_paths=(
               "/media/fat/_DOS Games"
               "/media/fat/_Computer/_DOS Games"
               "/media/fat/games/ao486/_DOS"
               "/media/usb0/games/ao486/_DOS"
           )
           ;;
       "x68k")
           search_paths=(
               "/media/fat/_X68000 Games"
               "/media/fat/_Computer/_X68000 Games"
           )
           ;;
       "mgls")
           IFS=',' read -ra search_paths <<< "${mgls_dirs}"
           ;;
       *)
           samdebug "No MGL search path defined for ${core_type}."
           return 1
           ;;
    esac

    # Collect only the search paths that actually exist
    for path in "${search_paths[@]}"; do
        [ -d "$path" ] && existing_paths+=("$path")
    done

    # If no valid search directories were found, create an empty list and exit
    if [ ${#existing_paths[@]} -eq 0 ]; then
        samdebug "No valid MGL search directories found for ${core_type}."
        : > "${output_file}" # Create empty list to prevent retry loops
        return 0
    fi

    # Run find on existing paths and write directly to the destination file
    find "${existing_paths[@]}" -type f -iname '*.mgl' 2>/dev/null > "${output_file}"

    # If the resulting list is empty, disable the core
    if [ ! -s "${output_file}" ]; then
        samdebug "No .mgl files found for ${core_type}-disabling core."
        delete_from_corelist "${core_type}"
        delete_from_corelist "${core_type}" tmp
        return 1
    fi

    game_count=$(wc -l < "${output_file}")
    samdebug "Created ${core_type} gamelist in '${dest_dir}' with ${game_count} entries."
}

function build_amiga_list() {
    # Accept core and destination directory arguments for consistency
	local dest_dir="${2:-$gamelistpath}"

    # Define paths; the output file is now dynamic based on dest_dir
    local demos_file="${amigapath}/listings/demos.txt"
    local games_file="${amigapath}/listings/games.txt"
    local output_file="${dest_dir}/amiga_gamelist.txt"

    # Check if the source 'games.txt' exists
    if [ ! -f "${games_file}" ]; then
        echo "ERROR: Can't find Amiga games.txt file at '${games_file}'"
        # Create an empty file at the destination to prevent rebuild attempts
        : > "${output_file}"
        return 1
    fi

    # Start with a fresh, empty list directly at the final destination
    > "${output_file}"

    # Append demos to the output file if selected
    if [[ "${amigaselect}" == "demos" ]] || [[ "${amigaselect}" == "all" ]]; then
        if [ -f "${demos_file}" ]; then
            sed 's/^/Demo: /' "${demos_file}" >> "${output_file}"
        else
            samdebug "Demos list not found at ${demos_file}"
        fi
    fi

    # Append games to the output file if selected
    if [[ "${amigaselect}" == "games" ]] || [[ "${amigaselect}" == "all" ]]; then
        cat "${games_file}" >> "${output_file}"
    fi

    # Verify that the final list is not empty
    if [ ! -s "${output_file}" ]; then
        samdebug "No Amiga games or demos matched current selection (${amigaselect})."
        return 1
    fi

    local total_entries
    total_entries="$(wc -l < "${output_file}")"
    samdebug "${total_entries} Amiga Games and/or Demos found for list in '${dest_dir}'."
}

function build_gamelist() {
    local core="$1"
	local outdir="${2:-$gamelistpath}"
    local file rc
    local is_initial_build=0

    # Determine if this is an "initial" build by checking the output path.
    # This makes the function's behavior dependent on its direct inputs.
    if [[ "$outdir" == "$gamelistpath" ]]; then
        is_initial_build=1
    fi

    samdebug "Building gamelist for ${core} in ${outdir}"

    # 2. SETUP: Ensure output directory exists and let the filesystem settle.
    mkdir -p "$outdir"
    sync "$outdir"
    sleep 1

    # 3. EXECUTION: Run the indexer to generate the list.
    # The tool is run twice to work around a potential issue where it misses files on the first pass.
    "${mrsampath}/samindex" -q -s "$core" -o "$outdir"
    "${mrsampath}/samindex" -q -s "$core" -o "$outdir"
    rc=$?

    # 4. POST-PROCESSING: Handle results and cleanup.
    file="${outdir}/${core}_gamelist.txt"

    # Only perform special error handling and seeding for initial builds.
    if (( is_initial_build )); then
        # On initial build, an exit code > 1 means "no games found".
        if (( rc > 1 )); then
            delete_from_corelist "$core"
            if [ -n "$core" ]; then
                echo "Can't find games for ${CORE_PRETTY[$core]}"
            else
                echo "Can't find games for (unknown core)"
            fi
            samdebug "build_gamelist returned code $rc for $core"
            return 1 # Return an error
        fi

        mkdir -p "${gamelistpathtmp}"
        cp "${file}" "${gamelistpathtmp}/${core}_gamelist.txt" 2>/dev/null
    fi

    # Always sort and de-duplicate the final output file, regardless of build type.
    if [[ -f "$file" ]]; then
        sort -u "$file" -o "$file"
    fi

    return 0
}

function ensure_list() {
    [[ -s "$gamelistpath/${1}_gamelist.txt" ]] || sam_build_catalog "$1" || return $?
    [[ -s "$gamelistpath/${1}_gamelist.txt" ]]
}
