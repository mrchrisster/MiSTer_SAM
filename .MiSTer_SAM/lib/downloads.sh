# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function curl_download() { # curl_download ${filepath} ${URL}

	curl \
		--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
		--insecure \
		--fail \
		--location \
		-o "${1}" \
		"${2}"
}

function check_and_update() {
    local url="$1"
    local tmp_file="$2"
    local local_file="$3"
    local description="$4"

    # Fetch the remote file size (follow redirects)
    remote_size=$(curl -sI --location --insecure "$url" | awk '/^Content-Length:/ {size=$2} END {print size}' | tr -d '\r')
    if [ -z "$remote_size" ]; then
        echo "Error: Unable to determine the size of $description at $url" >&2
        return 1
    fi

    # Get the local file size, if it exists
    if [ -f "$local_file" ]; then
        local_size=$(stat --format="%s" "$local_file")
    else
        local_size=0
    fi

    # Debugging output
    samdebug "Remote size: $remote_size"
    samdebug "Local size: $local_size"

    # Compare sizes and update if needed
    if [ "$remote_size" -eq "$local_size" ]; then
        echo "$description is up-to-date. No update required."
        return 0  # File is up-to-date
    else
        echo "Updating $description..."
        curl_download "$tmp_file" "$url" || return 1  # Download failed
        mv "$tmp_file" "$local_file" || { echo "Error: Unable to move $tmp_file to $local_file" >&2; return 1; }
        [[ ! -x "$local_file" ]] || chmod +x "$local_file"
        echo "$description updated successfully."
        return 2  # File was updated
    fi
}

function get_samstuff() { #get_samstuff file (path)

	if [ -z "${1}" ]; then
		return 1
	fi

	filepath="${2}"
	if [ -z "${filepath}" ]; then
		filepath="${mrsampath}"
	fi

	echo -n " Downloading from ${raw_base}/${1} to ${filepath}/..."
	curl_download "/tmp/${1##*/}" "${raw_base}/${1}"


	if [ ! "${filepath}" == "/tmp" ]; then
		mv --force "/tmp/${1##*/}" "${filepath}/${1##*/}"
	fi

	if [ "${1##*.}" == "sh" ]; then
		chmod +x "${filepath}/${1##*/}"
	fi

	echo " Done."
}

function get_samindex() {
    echo "Downloading samindex - needed for creating gamelists..."
    echo "Created for MiSTer by wizzo"
    echo "https://github.com/wizzomafizzo/mrext"

    # Define URLs and file paths
    latest_url="${raw_base}/.MiSTer_SAM/samindex"
    tmp_file="/tmp/samindex"
    local_file="${mrsampath}/samindex"

    # Check and update samindex
    check_and_update "$latest_url" "$tmp_file" "$local_file" "samindex"

}

function get_mbc() {
    echo "Downloading mbc - Control MiSTer from cmd..."
    echo "Created for MiSTer by pocomane"
    remote_url="${raw_base}/.MiSTer_SAM/mbc"
    tmp_file="/tmp/mbc"
    local_file="${mrsampath}/mbc"

    check_and_update "$remote_url" "$tmp_file" "$local_file" "mbc"

}

function get_inputmap() {
    echo "Downloading input maps - needed to skip past BIOS for some systems..."
    [ ! -d "${configpath}/inputs" ] && mkdir -p "${configpath}/inputs"

    for input_file in \
        "GBA_input_1234_5678_v3.map" \
        "MegaCD_input_1234_5678_v3.map" \
        "NES_input_1234_5678_v3.map" \
        "TGFX16_input_1234_5678_v3.map" \
	"NEOGEO_input_1234_5678_v3.map" \
        "SATURN_input_1234_5678_v3.map"; do
        remote_url="${raw_base}/.MiSTer_SAM/inputs/$input_file"
        tmp_file="/tmp/$input_file"
        local_file="${configpath}/inputs/$input_file"

        check_and_update "$remote_url" "$tmp_file" "$local_file" "$input_file"
    done
    echo "Input maps updated."
}

function get_blacklist() {
    echo "Downloading blacklist files - SAM can auto-detect games with static screens and filter them out..."

    for blacklist_file in "${BLACKLIST_FILES[@]}"; do
        remote_url="${raw_base}/SAM/Blacklists/$blacklist_file"
        tmp_file="/tmp/$blacklist_file"
        local_file="${blacklistpath}/$blacklist_file"
        check_and_update "$remote_url" "$tmp_file" "$local_file" "$blacklist_file"
    done
    echo "Blacklist files updated."
}

function get_ratedlist() {
	echo "Downloading lists with kids-friendly games..."

	for rated_file in "${RATED_FILES[@]}"; do
		remote_url="${raw_base}/SAM/Rated/$rated_file"
		tmp_file="/tmp/$rated_file"
		local_file="${ratedpath}/$rated_file"
		check_and_update "$remote_url" "$tmp_file" "$local_file" "$rated_file"
	done
	echo "Rated lists updated."
}

get_dlmanager() {

	if [ "$download_manager" = yes ]; then

		aria2_path="/media/fat/linux/aria2c"

		if [ ! -f "$aria2_path" ]; then

			aria2_urls=(
				"https://raw.githubusercontent.com/mrchrisster/0mhz-collection/main/aria2c/aria2c.zip.001"
				"https://raw.githubusercontent.com/mrchrisster/0mhz-collection/main/aria2c/aria2c.zip.002"
				"https://raw.githubusercontent.com/mrchrisster/0mhz-collection/main/aria2c/aria2c.zip.003"
				"https://raw.githubusercontent.com/mrchrisster/0mhz-collection/main/aria2c/aria2c.zip.004"

			)
			echo ""
			echo -n "Installing aria2c Download Manager... "
			for url in "${aria2_urls[@]}"; do
				file_name=$(basename "${url%%\?*}")
				curl -s --insecure -L $url -o /tmp/"$file_name"
				if [ $? -ne 0 ]; then
					echo "Failed to download $file_name"
					download_manager=no
				fi
			done

			# Check if the download was successful
			if [ $? -eq 0 ]; then
				echo "Done."
			else
				echo "Failed."
			fi

			cat /tmp/aria2c.zip.* > /tmp/aria2c_full.zip
			unzip -qq -o /tmp/aria2c_full.zip -d /media/fat/linux

		fi
	fi
}

function get_tvc_files() {
    local target_dir="${mrsampath}/tvc"
    local api_url="https://api.github.com/repos/mrchrisster/MiSTer_SAM/contents/.MiSTer_SAM/tvc?ref=${branch}"
    local tmp_json="/tmp/tvc_files.json"

    mkdir -p "$target_dir"
    samdebug "Checking for TVC VCD JSON updates..."

    if curl -s -L --insecure -H "User-Agent: MiSTer_SAM" "$api_url" > "$tmp_json"; then
        # Check if valid JSON array using jq
        if jq -e '. | type == "array"' "$tmp_json" >/dev/null 2>&1; then
             # Parse filename
             jq -r '.[] | .name' "$tmp_json" | while read -r name; do
                  if [ "$name" != "null" ]; then
                      samdebug "Updating $name..."
                      curl_download "${target_dir}/${name}" "${raw_base}/.MiSTer_SAM/tvc/${name}"
                  fi
             done
             samdebug "TVC VCD JSON update complete."
        else
             samdebug "Error: Failed to fetch TVC file list from GitHub (Invalid JSON)."
             local err_msg=$(jq -r '.message // empty' "$tmp_json" 2>/dev/null)
             if [ -n "$err_msg" ]; then
                samdebug "GitHub API Message: $err_msg"
             else
                samdebug "Response content: $(cat "$tmp_json")"
             fi
        fi
    else
        samdebug "Error: Could not connect to GitHub API for TVC updates."
    fi
    rm -f "$tmp_json"
}
