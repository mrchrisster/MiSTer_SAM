# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function load_samvideo() {
	sv_loadcounter=$((sv_loadcounter + 1))
	#Load the actual rom (or play a video)

	if [ "${samvideo_freq}" == "only" ]; then
		sam_publish_phase video
		samvideo_play &
		return 1
	elif [ "${samvideo_freq}" == "core" ]; then
		samdebug "samvideo load core counter is now $sv_loadcounter"
		if ((sv_loadcounter % ${#corelist[@]} == 0)); then
			sam_publish_phase video
		samvideo_play &
			sv_loadcounter=0
			return 1
		fi
		sv_nextcore=""
		return 0

	elif [ "${samvideo_freq}" == "alternate" ]; then
		if ((sv_loadcounter % 2 == 1)); then
			sam_publish_phase video
		samvideo_play &
			return 1
		else
			sv_nextcore=""
			return 0
		fi
	fi


}

function init_core_samvideo() {
    local arr_name=$1 c cnt stamp cached_stamp= files=()
    local -a video_cores=()
    local -A video_cached_counts=()
    sam_core_policy_refresh || return $?
    sam_filter_cores "$arr_name" video_cores || return 2
    (( ${#video_cores[@]} )) || return 1
    local suffix=_tvc.json
    [[ "$samvideo_tvc_cdi" != yes ]] || suffix=_tvc_vcd.json
    for c in "${video_cores[@]}"; do
        sam_core_require "$c" || return $?
        files+=("$mrsampath/tvc/${c}${suffix}")
    done
    stamp="${video_cores[*]}:$(stat -c '%n:%s:%y' "${files[@]}" 2>/dev/null || true)"
    [[ ! -f "$core_count_file.stamp" ]] || cached_stamp=$(<"$core_count_file.stamp")
    if [[ "$cached_stamp" == "$stamp" && -f "$core_count_file" ]]; then
        while IFS='=' read -r c cnt; do
            [[ "$c" =~ ^[a-z0-9_]+$ && "$cnt" =~ ^[0-9]+$ ]] || continue
            video_cached_counts[$c]=$cnt
        done < "$core_count_file"
    fi
    SAMVC=(); SAMVTOTAL=0
    for c in "${video_cores[@]}"; do
        if [[ -n "${video_cached_counts[$c]-}" ]]; then cnt=${video_cached_counts[$c]}
        else cnt=$(jq -r 'keys|length' "$mrsampath/tvc/${c}${suffix}" 2>/dev/null) || cnt=0; fi
        [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
        cnt=$((10#$cnt)); SAMVC[$c]=$cnt; SAMVTOTAL=$((SAMVTOTAL+cnt))
    done
    mkdir -p "${core_count_file%/*}"
    : > "$core_count_file"
    for c in "${video_cores[@]}"; do printf '%s=%s\n' "$c" "${SAMVC[$c]}" >> "$core_count_file"; done
    printf 'total_count=%s\n' "$SAMVTOTAL" >> "$core_count_file"
    printf '%s' "$stamp" > "$core_count_file.stamp"
    return 0
}

function pick_core_samvideo() {
    init_core_samvideo "$1" || return $?
    local c total=0
    local -A video_weights=()
    for c in "${!SAMVC[@]}"; do video_weights[$c]=${SAMVC[$c]}; total=$((total+SAMVC[$c])); done
    if (( total == 0 )); then
        for c in "${!SAMVC[@]}"; do video_weights[$c]=1; done
        total=${#SAMVC[@]}
    fi
    nextcore=$(pick_weighted_random video_weights "$total") || return $?
    sam_core_require "$nextcore"
}

function misterini_apply_temp() {
    # Check if sv_inimod is set to "no"
    if [ "$sv_inimod" == "no" ]; then
        echo "sv_inimod is set to 'no'. Skipping MiSTer.ini modification."
        return 0
    fi

    # Exit if MiSTer.ini doesn't exist
    if [ ! -f "$ini_file" ]; then
        echo "Error: $ini_file not found."
        return 1
    fi

    # Check if it's *already* mounted by us
    if mountpoint -q "$ini_file"; then
        echo "MiSTer.ini is already temporarily mounted. Skipping."
        return 0
    fi

    echo "Checking and applying temporary settings to $ini_file."

    # --- Desired settings logic (Copied from your function) ---
    local fb_terminal="1"
    local vga_scaler="1"
    local video_mode

    if [ "$samvideo_output" == "hdmi" ]; then
        if [ "${sv_aspectfix_vmode}" == "yes" ]; then
            video_mode="6"
        else
            video_mode="8"
        fi
    elif [ "$samvideo_output" == "crt" ]; then
        if [ "$samvideo_source" == "youtube" ]; then
            samvideo_crtmode="${samvideo_crtmode320}"
        elif [ "$samvideo_source" == "archive" ]; then
            samvideo_crtmode="${samvideo_crtmode640}"
        fi
        video_mode="$(echo "$samvideo_crtmode" | awk -F'=' '{print $2}')"
    else
        echo "Unknown video output mode: $samvideo_output"
        return 1
    fi

    # --- INI Modification Logic ---
    # We now write to our *temporary file*, not the original.

    # Use awk to read the *original* file and write to the *temp* file.
    awk '
    BEGIN { inside_menu = 0 }
    /^\[[Mm][Ee][Nn][Uu]\]/ { inside_menu = 1; next }
    /\[.*\]/ && !/^\[[Mm][Ee][Nn][Uu]\]/ { inside_menu = 0 }
    !inside_menu { print }
    ' "$ini_file" > "$sv_ini_temp_file"

    # Append the new [Menu] section to the temp file
    {
        echo ""
        echo "[Menu]"
        echo "; Settings temporarily overridden by SAM Video via bind mount."
        echo "video_mode=$video_mode"
        echo "vga_scaler=$vga_scaler"
        echo "fb_terminal=$fb_terminal"
    } >> "$sv_ini_temp_file"

    # --- Bind Mount Logic ---
    # This is the new part. It requires sudo.
    echo "Applying temporary settings via bind mount..."
    if ! sudo mount --bind "$sv_ini_temp_file" "$ini_file"; then
        echo "Error: SAM failed to bind mount."
        rm -f "$sv_ini_temp_file" # Clean up
        return 1
    fi

    echo "MiSTer.ini is now temporarily modified."
    return 0
}

function misterini_restore() {
    # If we never planned to modify, there's nothing to restore.
    if [ "$sv_inimod" == "no" ]; then
        return 0
    fi

    echo "Restoring original MiSTer.ini..."

    # Check if our file is currently a mount point
    if mountpoint -q "$ini_file"; then
        echo "Unmounting temporary MiSTer.ini..."
        if ! sudo umount "$ini_file"; then
            echo "Error: Failed to unmount $ini_file."
            echo "You may need to unmount it manually: sudo umount $ini_fsile"
            return 1
        fi
        echo "Original MiSTer.ini restored."
    else
        echo "MiSTer.ini was not mounted. No restore needed."
    fi

    # Clean up our temporary file
    rm -f "$sv_ini_temp_file"

    return 0
}

function sv_ar_cdi_mode() {

    # 1. Setup Variables
    samvideo_list="/tmp/.SAM_List/sv_archive_list.txt"
    tmpvideo="/tmp/SAMvideo.chd"
    local http_archive="${sv_archive_cdi//https/http}"

    # Check for CDi core availability
    local cdi_check_path="/media/fat/_Console"
    local cdi_core_file=""

    # Find existing CDi core (case-insensitive)
    if [ -d "$cdi_check_path" ]; then
        cdi_core_file=$(find "$cdi_check_path" -maxdepth 1 -iname "cdi*.rbf" -print -quit)
    fi

    if [ -z "$cdi_core_file" ]; then
        echo "CDi core not found. Attempting to retrieve..."
        mkdir -p "$cdi_check_path"

        # Retrieve URL from JSON
        local cdi_url=$(curl -k -s "https://raw.githubusercontent.com/MiSTer-unstable-nightlies/Unstable_Folder_MiSTer/main/db_unstable_nightlies_folder.json" | \
            jq -r '.files | to_entries[] | select(.key | contains("_Unstable/CDi")) | .value.url' | head -n 1)

        if [ -n "$cdi_url" ]; then
             echo "Downloading CDi core from: $cdi_url"
             curl -k -L -o "${cdi_check_path}/CDi_unstable.rbf" "$cdi_url"
             if [ $? -eq 0 ]; then
                 echo "CDi core downloaded successfully."
                 cdi_core_file="${cdi_check_path}/CDi_unstable.rbf"
             else
                 echo "Error downloading CDi core."
             fi
        else
             echo "Failed to fetch CDi core URL."
        fi
    fi

    # 2. Populate the samvideo_list if it's empty (only needed for non-TVC mode)
    if [ ! -s "${samvideo_list}" ]; then
        curl_download /tmp/SAMvideos.xml "${http_archive}"
        grep -o '<file name="[^"]\+\.chd"' /tmp/SAMvideos.xml \
            | sed 's/<file name="//;s/"$//' \
            | sed 's/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/\</g; s/&gt;/\>/g; s/&quot;/\"/g; s/#&#39;/\'"'"'/g; s/&ldquo;/\"/g; s/&rdquo;/\"/g;' \
            > "${samvideo_list}"
    fi

    # 3. Select a video and check availability
    while true; do
        if [ -n "$sv_selected" ]; then
             samdebug "Video pre-selected: $sv_selected"
        elif [ "$samvideo_tvc" == "yes" ]; then
            samvideo_tvc || { printf '1\n' > "$sv_gametimer_file"; return 1; }
            # Check if selection was made
            if [ -n "$sv_selected" ]; then
                samdebug "Video selected via TVC: $sv_selected"
            else
                samdebug "TVC selection failed, falling back."
                sv_selected="$(shuf -n1 "${samvideo_list}")"
            fi
        else
            sv_selected="$(shuf -n1 "${samvideo_list}")"
        fi

        # Safety check: if list is empty or shuf failed
        if [ -z "$sv_selected" ]; then
             samdebug "Error: No video selected."
             return
        fi

        sv_selected_url="${http_archive%/*}/${sv_selected}"

        # 4. Check Local Availability First
		local local_svfile="${samvideo_path}/$(echo "$sv_selected" | sed "s/[\":?]//g")"
		samdebug "Checking if file is available locally...$local_svfile"
		if [ -f "$local_svfile" ]; then
			if [[ "$new_only_chd" == "yes" || "$do_fast_chd_fill" == "yes" ]] && [ "$keep_local_copy" == "yes" ]; then
				samdebug "Exists=>SKIP"
				awk -v Line="$sv_selected" '!index($0, Line)' "${samvideo_list}" >"${tmpfile}" && cp -f "${tmpfile}" "${samvideo_list}"
		        unset sv_selected
				continue
			else
				samdebug "Local file exists so using: $local_svfile"
				break
			fi
		fi

        # Check if the URL is available using wget
        samdebug "Checking availability of ${sv_selected_url}..."
        if wget --spider --quiet --timeout=10 --tries=1 "${sv_selected_url}"; then
            samdebug "URL is available: ${sv_selected_url}"

			if [ "$do_fast_chd_fill" == "yes" ] && [ "$keep_local_copy" == "yes" ]; then
				samdebug "Preloading ${sv_selected} from archive.org for smooth playback"
				dl_video "${sv_selected_url}"

				# Check if download succeeded AND file has size > 0
				if [ -s "$tmpvideo" ]; then
					samdebug "Download succeeded."
				else
					samdebug "Error: Download failed or file is empty. Moving to next video."
					awk -v Line="$sv_selected" '!index($0, Line)' "${samvideo_list}" >"${tmpfile}" && cp -f "${tmpfile}" "${samvideo_list}"
			        unset sv_selected
					continue
				fi

				# 5. Cache the file locally ONLY if it was a fresh download
				cp "$tmpvideo" "$local_svfile"
				samdebug "Saved local copy of video: $local_svfile"
				samdebug "${sv_selected} preloaded successfully. Removing from list and selecting another."
				awk -v Line="$sv_selected" '!index($0, Line)' "${samvideo_list}" >"${tmpfile}" && cp -f "${tmpfile}" "${samvideo_list}"
		        unset sv_selected
				continue
			fi

            break
        else
            samdebug "URL is not available: ${sv_selected_url}. Removing from list and selecting another."
            awk -v Line="$sv_selected" '!index($0, Line)' "${samvideo_list}" >"${tmpfile}" && cp -f "${tmpfile}" "${samvideo_list}"
            unset sv_selected
        fi
    done

    # 5. Download / Cache Logic
    # Flag to track if we just downloaded a new file
    local fresh_download="no"

    if [ -f "$local_svfile" ]; then
        echo "Local file exists: $local_svfile"
        cp "$local_svfile" "$tmpvideo"
    else
        echo "Preloading ${sv_selected} from archive.org for smooth playback"
        dl_video "${sv_selected_url}"

        # Check if download succeeded AND file has size > 0
        if [ -s "$tmpvideo" ]; then
            fresh_download="yes"
        else
            echo "Error: Download failed or file is empty."
            echo "1" > "$sv_gametimer_file"
            return
        fi
    fi

    # 5. Cache the file locally ONLY if it was a fresh download
    if [ "$fresh_download" == "yes" ] && [ "$keep_local_copy" == "yes" ]; then
        cp "$tmpvideo" "$local_svfile"
        samdebug "Saved local copy of video: $local_svfile"
    fi

    # 6. Update samvideo_list to remove the processed file
    if [ "$samvideo_tvc" == "no" ]; then
        awk -vLine="$sv_selected" '!index($0,Line)' "${samvideo_list}" >${tmpfile} && cp -f ${tmpfile} "${samvideo_list}"
    fi



    # 8. Calculate Game Timer
    # BACKUP FALLBACK - Using awk to estimate duration based on file size if JSON duration missing.
    local timer_delay=6
    sv_gametimer=$(du -m "$tmpvideo" | awk -v delay="$timer_delay" '{print int($1 * 7.5) + delay}')

    sv_title="${sv_selected%.*}"
	sv_title="${sv_title#*-}"
    sv_title="${sv_title//_/ }"

    # Check for TVC VCD JSON and override duration/title if available
    if [ -f "/tmp/.SAM_tmp/sv_core" ]; then
        local current_core=$(cat "/tmp/.SAM_tmp/sv_core")
        local vcd_json="${mrsampath}/tvc/${current_core}_tvc_vcd.json"

        if [ -f "$vcd_json" ]; then
             samdebug "Found VCD JSON: $vcd_json"

             local json_duration=$(jq -r --arg f "$sv_selected" '.[$f].duration // empty' "$vcd_json")
             local json_title=$(jq -r --arg f "$sv_selected" '.[$f].title // empty' "$vcd_json")


             if [[ -n "$json_duration" ]] && [[ "$json_duration" != "null" ]]; then
                 sv_gametimer=$((json_duration + timer_delay))
                 samdebug "Duration set to $sv_gametimer (from JSON: $json_duration)"
             fi


        fi
    fi

    # 9. Show tty2oled splash


	if [ "${ttyenable}" == "yes" ]; then
        local tty_gamename="${sv_title}"

        tty_currentinfo=(
            [core_pretty]="${nextcore^} Commercial" [name]="${tty_gamename}" [core]=SAM_splash
            [date]=$EPOCHSECONDS [counter]=${sv_gametimer} [name_scroll]="${tty_gamename:0:21}"
            [name_scroll_position]=0 [name_scroll_direction]=1 [update_pause]=${ttyupdate_pause}
        )
        declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
        write_to_TTY_cmd_pipe "display_info" &
        SECONDS=$((EPOCHSECONDS - tty_currentinfo[date]))
    fi


    # 10. Play file
    sam_core_rule_check cdi auxiliary || { printf "SAM: %s\n" "$sam_core_reason" >&2; return 2; }
    local core_prefix="${sv_selected%%-*}"
    core_prefix="${core_prefix//_/ }"
    echo -e "Now playing: \e[1m${core_prefix} Commercial - ${sv_title}\e[0m"
    if [ -s /tmp/SAM_Game.mgl ]; then mv /tmp/SAM_Game.mgl /tmp/SAM_game.previous.mgl; fi
    {
        # Prepare RBF path for MGL
        local mgl_rbf="_Console/CDi"
        if [ -n "$cdi_core_file" ]; then
             # Extract filename without path and extension
             local cdi_basename=$(basename "$cdi_core_file" .rbf)
             mgl_rbf="_Console/${cdi_basename}"
        fi

        echo "<mistergamedescription>"
        echo "<rbf>${mgl_rbf}</rbf>"
        echo "<setname same_dir=\"1\">cdi_sam</setname>"
        echo "<file delay=\"1\" type=\"s\" index=\"1\" path=\"../../../../..${tmpvideo}\"/>"
    } >/tmp/SAM_Game.mgl

    echo "load_core /tmp/SAM_Game.mgl" > /dev/MiSTer_cmd
    timeout 1s sh -c "echo 'load_core /tmp/SAM_Game.mgl' > /dev/MiSTer_cmd"
    sam_emit display_launch "$sv_title" "$tmpvideo" cdi "" samvideo 0

    # Wait for CD-i core to load before starting timer
    for i in {1..20}; do
        if grep -iqE "cd.?i" /tmp/CORENAME 2>/dev/null; then
			samdebug "CD-i core is loaded"
            break
        fi
        sleep 1

	done
    echo "$sv_gametimer" > "$sv_gametimer_file"
    unset sv_selected
}

function dl_video() {
    rm -f "$tmpvideo"

    if [ "$download_manager" = "yes" ]; then
        get_dlmanager
        # aria2c logic
        /media/fat/linux/aria2c \
            --dir="$(dirname "$tmpvideo")" \
            --file-allocation=none \
            -o "$(basename "$tmpvideo")" \
            -s 4 -x 4 -k 1M \
            --summary-interval=0 \
            --console-log-level=warn \
            --download-result=hide \
            --quiet=false \
            --allow-overwrite=true \
            --ca-certificate=/etc/ssl/certs/cacert.pem \
            "${1}"
    else
        # wget logic
        wget -q --show-progress -O "$tmpvideo" "${1}"
    fi
}

function sv_ar_download() {
    local resolution="$1"   # Resolution, 480 or 240
    local list_file="$2"    # Associated list file, sv_archive_hdmilist or sv_archive_crtlist

    samvideo_list="/tmp/.SAM_List/sv_archive_list.txt"
    local http_archive="${list_file//https/http}"

    # Populate the samvideo_list if it's empty
    if [ ! -s "${samvideo_list}" ]; then
        curl_download /tmp/SAMvideos.xml "${http_archive}"
        grep -o '<file name="[^"]\+\.avi"' /tmp/SAMvideos.xml \
            | sed 's/<file name="//;s/"$//' \
            | sed 's/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/\</g; s/&gt;/\>/g; s/&quot;/\"/g; s/#&#39;/\'"'"'/g; s/&ldquo;/\"/g; s/&rdquo;/\"/g;' \
            > "${samvideo_list}"
    fi

    # Select a video and check availability
    while true; do
        if [ "$samvideo_tvc" == "yes" ]; then
            samvideo_tvc || { printf '1\n' > "$sv_gametimer_file"; return 1; }
        else
            sv_selected="$(shuf -n1 "${samvideo_list}")"
        fi

        # Safety check
        if [ -z "$sv_selected" ]; then
             samdebug "Error: No video selected."
             return
        fi

        sv_selected_url="${http_archive%/*}/${sv_selected}"

        # Check Local Availability First
        local local_svfile="${samvideo_path}/$(echo "$sv_selected" | sed "s/[\":?]//g")"
        if [ -f "$local_svfile" ]; then
            samdebug "Local file found: $local_svfile. Skipping remote check."
            break
        fi

        # Check if the URL is available using wget
        samdebug "Checking availability of ${sv_selected_url}..."
        if wget --spider --quiet --timeout=10 --tries=1 "${sv_selected_url}"; then
            samdebug "URL is available: ${sv_selected_url}"
            break
        else
            samdebug "URL is not available: ${sv_selected_url}. Removing from list and selecting another."
            awk -v Line="$sv_selected" '!index($0, Line)' "${samvideo_list}" >"${tmpfile}" && cp -f "${tmpfile}" "${samvideo_list}"
        fi
    done

    tmpvideo="/tmp/SAMvideo.avi"
	samdebug "Checking if file is available locally...$local_svfile"


    if [ -f "$local_svfile" ]; then
        echo "Local file exists: $local_svfile"
        cp "$local_svfile" "$tmpvideo"
    else
        echo "Preloading ${sv_selected} from archive.org for smooth playback"
        dl_video "${sv_selected_url}"
    fi

    # Update samvideo_list to remove the processed file
	if [ "$samvideo_tvc" == "no" ]; then
		awk -vLine="$sv_selected" '!index($0,Line)' "${samvideo_list}" >${tmpfile} && cp -f ${tmpfile} "${samvideo_list}"
	fi

    # Set resolution-specific variables
    if [ "$resolution" -eq 480 ]; then
        res_space="640 480"
    else
        res_space="640 240"
    fi
}

function sv_local() {
	samvideo_list="/tmp/.SAM_List/sv_local_list.txt"
	if [ ! -s ${samvideo_list} ]; then
		find "$samvideo_path" -type f > ${samvideo_list}
	fi
	tmpvideo=$(cat ${samvideo_list} | shuf -n1)
	awk -vLine="$tmpvideo" '!index($0,Line)' ${samvideo_list} >${tmpfile} && cp -f ${tmpfile} ${samvideo_list}
	res="$(LD_LIBRARY_PATH=${mrsampath} ${mrsampath}/mplayer -vo null -ao null -identify -frames 0 "$tmpvideo" 2>/dev/null | grep "VIDEO:" | awk '{print $3}')"
	res_space=$(echo "$res" | tr 'x' ' ')
	sv_selected="$(basename "${tmpvideo}")"

}

function samvideo_tvc() {
    local tvc_suffix="_tvc.json"
    if [ "${samvideo_tvc_cdi}" == "yes" ]; then
        tvc_suffix="_tvc_vcd.json"
    fi

    if [ ! -f "${mrsampath}/tvc/nes${tvc_suffix}" ]; then
        get_tvc_files
    fi

    # Setting corelist to available commercials
    unset TVC_LIST
    unset SV_TVC_CL
    for g in "${!SV_TVC[@]}"; do
        for c in "${corelist[@]}"; do
            if [[ "$c" == "$g" ]]; then
                SV_TVC_CL+=("$c")
            fi
        done
    done
    samdebug "samvideo corelist: ${SV_TVC_CL[@]}"

    # NEW: Respect Single Core Mode
    if [ "$SAM_MODE" == "SINGLE" ] && [ -n "$SAM_TARGET_CORE" ]; then
         sam_core_require "$SAM_TARGET_CORE" || return $?
         nextcore="$SAM_TARGET_CORE"
         samdebug "Single mode active. Forcing samvideo target: $nextcore"
    else
         pick_core SV_TVC_CL || return $?
    fi
    samdebug "nextcore = $nextcore"

    # Initialize variables
    count=0
    sv_selected= tvc_selected=
    local gamelist_tmp="${gamelistpathtmp}/${nextcore}${tvc_suffix}"
    local gamelist_original="${mrsampath}/tvc/${nextcore}${tvc_suffix}"

    # Prepare only this core, using its normal session filters. Do not play an
    # advertisement for a named game that cannot be selected afterward.
    check_list "$nextcore" || return 1
    [[ -s "$gamelistpathtmp/${nextcore}_gamelist.txt" ]] || return 1
    sam_emit candidate_filter "$nextcore" || return $?

    # Ensure a local temporary copy exists or reset it if empty
	if [ ! -f "$gamelist_tmp" ] || [ ! -s "$gamelist_tmp" ] || [ "$(cat "$gamelist_tmp")" = "{}" ]; then
        samdebug "Copying original gamelist to temporary file: $gamelist_tmp"
        cp "$gamelist_original" "$gamelist_tmp"
    fi

    while [ $count -lt 15 ]; do
        if [ -f "$gamelist_tmp" ]; then
            samdebug "$gamelist_tmp found."

            # Select a random game and its corresponding entry
            sv_selected=$(jq -r 'keys[]' "$gamelist_tmp" | shuf -n 1)
            [[ -n "$sv_selected" ]] || break
            tvc_selected=$(jq -r --arg key "$sv_selected" '.[$key]' "$gamelist_tmp")

            # Remove the selected entry from the temporary file
            samdebug "Removing $sv_selected from $gamelist_tmp"
            jq --arg key "$sv_selected" 'del(.[$key])' "$gamelist_tmp" > "${gamelist_tmp}.tmp" && mv "${gamelist_tmp}.tmp" "$gamelist_tmp"
            # Save the selected game information
            if [ "${samvideo_tvc_cdi}" == "yes" ]; then
                 echo "${tvc_selected}" | jq -r '.title' > /tmp/.SAM_tmp/sv_gamename
            else
                 echo "${tvc_selected}" > /tmp/.SAM_tmp/sv_gamename
            fi
            local match_rc=0
            python3 "$mrsampath/modules/commercial_picker.py" --core "$nextcore" \
                --list "$gamelistpathtmp/${nextcore}_gamelist.txt" \
                --query-file /tmp/.SAM_tmp/sv_gamename \
                --cache "$gamelistpathtmp/.commercial-${nextcore}.json" >/dev/null || match_rc=$?
            if ((match_rc == 0)); then break; fi
            ((match_rc == 1)) || return "$match_rc"
            printf 'SAM commercial: skipping %s; no matching game remains in the filtered list.\n' "$sv_selected" >&2
            sv_selected= tvc_selected=
            count=$((count+1))
            continue
        else
            # If the file is not found, select a new core randomly
            pick_core SV_TVC_CL || return $?
            samdebug "${nextcore}${tvc_suffix} not found, selecting new core."
        fi

        ((count++))
    done

    if [[ -z "$sv_selected" ]]; then
        rm -f /tmp/.SAM_tmp/sv_gamename
        echo 'SAM commercial: no playable advertisement found in this batch.' >&2
        return 1
    fi
    echo $nextcore > /tmp/.SAM_tmp/sv_core
    samdebug "Searching for ${SV_TVC[$nextcore]}"
    if [ -z "${tvc_selected}" ]; then
        echo "Couldn't find TVC list. Selecting random game from system"
        sv_selected="$(cat ${samvideo_list} | grep -i "${SV_TVC[$nextcore]}" | shuf --random-source=/dev/urandom | head -1)"
    fi
    samdebug "Picked $sv_selected"
}

function samvideo_play() {

	if [ "${samvideo_tvc_cdi}" == "yes" ]; then
		sv_ar_cdi_mode
		return
	fi

	if [ "${samvideo_source}" == "archive" ] && [ "$samvideo_output" == "hdmi" ]; then
		sv_ar_download 480 "${sv_archive_hdmilist}"
	elif [ "${samvideo_source}" == "archive" ] && [ "$samvideo_output" == "crt" ]; then
		sv_ar_download 240 "${sv_archive_crtlist}"
	elif [ "${samvideo_source}" == "local" ]; then
		sv_local
	fi



	if [ -z "${sv_selected}" ]; then
		echo "Error while downloading"
		echo "1" > "$sv_gametimer_file"
		return
	fi

	sv_gametimer="$(LD_LIBRARY_PATH=${mrsampath} ${mrsampath}/mplayer -vo null -ao null -identify -frames 0 "$tmpvideo" 2>/dev/null | grep "ID_LENGTH" | sed 's/[^0-9.]//g' | awk -F '.' '{print $1}')"
	sv_title="${sv_selected%.*}"

	#Show tty2oled splash
	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			[core_pretty]="SAM Video Player"
			[name]="${sv_title}"
			[core]=SAM_splash
			[date]=$EPOCHSECONDS
			[counter]=${sv_gametimer}
			[name_scroll]="${sv_title:0:21}"
			[name_scroll_position]=0
			[name_scroll_direction]=1
			[update_pause]=${ttyupdate_pause}
		)

		declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
		tty_displayswitch=$(($gametimer / $ttycoresleep - 1))
		write_to_TTY_cmd_pipe "display_info" &
		local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
		SECONDS=${elapsed}
	fi


	if [ "$mute" != "no" ] || [ "$bgm" == "yes" ]; then
		options="-nosound"
	fi


	if [ -s "$tmpvideo" ]; then
		timeout 1s sh -c "echo 'load_core /media/fat/menu.rbf' > /dev/MiSTer_cmd"
		sleep "${samvideo_displaywait}"
		# TODO delete blinking cursor
		#echo "\033[?25l" > /dev/tty1
		#setterm -cursor off
		echo $(("$sv_gametimer" + 2)) > "$sv_gametimer_file"
		${mrsampath}/mbc raw_seq :43
		vmode -r ${res_space} rgb32
		echo -e "\nPlaying video now.\n"
		echo -e "Title: ${sv_selected%.*}"
		echo -e "Resolution: ${res_space}"
		echo -e "Length: ${sv_gametimer} seconds\n"
		sam_emit display_launch "$sv_title" "$tmpvideo" samvideo "" samvideo "$((sv_gametimer + 2))"

		nice -n -20 env LD_LIBRARY_PATH=${mrsampath} ${mrsampath}/mplayer -msglevel all=0:statusline=5 "${options}" "$tmpvideo" 2>/dev/null
		rm "$sv_gametimer_file" 2>/dev/null
	else
		echo "No video was downloaded. Skipping video playback.."
		echo "1" > "$sv_gametimer_file"
		return
	fi
	#echo load_core /media/fat/menu.rbf > /dev/MiSTer_cmd
	#next_core
}

function get_samvideo() {
    echo "Checking and updating components for SAM video playback..."
    echo "Created for MiSTer by wizzo"
    echo "https://github.com/wizzomafizzo/mrext"

    # Define URLs and file paths
    latest_mplayer="${raw_base}/.MiSTer_SAM/mplayer.zip"
    tmp_mplayer="/tmp/mplayer.zip"
    local_mplayer="${mrsampath}/mplayer.zip"

    # Check and update mplayer
    check_and_update "$latest_mplayer" "$tmp_mplayer" "$local_mplayer" "mplayer"
	result=$?
	if [ "$result" -eq 2 ] || [ ! -f "${mrsampath}/mplayer" ]; then
        echo "Extracting mplayer..."
        unzip -ojq "$local_mplayer" -d "${mrsampath}" || {
            echo "Error: Failed to extract mplayer.zip" >&2
        }
        echo "mplayer updated and extracted successfully."
    fi

}
