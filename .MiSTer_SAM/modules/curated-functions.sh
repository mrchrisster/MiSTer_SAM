# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function build_goat_lists() {
	local goat_flag="/tmp/.SAM_tmp/goatmode.ready"
	local goat_custom_path="${gamelistpath}/sam_goat_list_custom.txt"
	local goat_list_path="${gamelistpath}/sam_goat_list.txt"

	# Already built this session?
	[[ -f "$goat_flag" ]] && return

	echo "SAM GOAT Mode active"

	# Ensure working dir
	rm -rf "${gamelistpathtmp}"/*
	mkdir -p "${gamelistpathtmp}" /tmp/.SAM_tmp

	# Use custom list if present, otherwise fall back to default
	if [[ -f "$goat_custom_path" ]]; then
		echo "Using custom GOAT list: ${goat_custom_path}"
		goat_list_path="$goat_custom_path"
	else
		# Download default list if missing
		if [[ ! -f "$goat_list_path" ]]; then
			samdebug "Downloading GOAT master list..."
			get_samstuff SAM/Gamelists/sam_goat_list.txt "$gamelistpath"
		fi
	fi

	# Parse master list into per-core tmp files
	local current_core=""
	while IFS= read -r line; do
	if [[ "$line" =~ ^\[(.+)\]$ ]]; then
	  current_core="${BASH_REMATCH[1],,}"
	  if [[ ! -f "${gamelistpath}/${current_core}_gamelist.txt" ]]; then
	    build_gamelist "$current_core"
	    rm -f "${gamelistpathtmp}/${current_core}_gamelist.txt"
	  fi
	elif [[ -n "$current_core" ]]; then
	  local all_matches
	  all_matches=$(fgrep -i "$line" "${gamelistpath}/${current_core}_gamelist.txt")
	  if [[ -n "$all_matches" ]]; then
	    local picked=""
	    # For arcade: prefer the canonical non-alternatives path first
	    if [[ "$current_core" == "arcade" ]]; then
	      picked=$(echo "$all_matches" | grep -v -i "_alternatives" | head -1)
	    fi
	    # Then try region preference: USA > Japan > World
	    if [[ -z "$picked" ]]; then
	      for region in "USA" "Japan" "World"; do
	        picked=$(echo "$all_matches" | grep -i "(${region}" | head -1)
	        [[ -n "$picked" ]] && break
	      done
	    fi
	    # Fall back to first match
	    [[ -z "$picked" ]] && picked=$(echo "$all_matches" | head -1)
	    echo "$picked" >> "${gamelistpathtmp}/${current_core}_gamelist.txt"
	  fi
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
