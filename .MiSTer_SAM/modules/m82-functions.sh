# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function build_m82_list() {
	mkdir -p "$gamelistpathtmp" "$mrsamtmp"

	if [ ! -s "${gamelistpath}"/nes_gamelist.txt ]; then
		samdebug "Creating NES gamelist"
		local index_rc=0
        sam_m82_index_stage=$(mktemp -d "$mrsamtmp/m82-index.XXXXXX") || return 1
		sam_run_owned_command "$mrsampath/samindex" -q -s nes -o "$sam_m82_index_stage" || index_rc=$?
		if (( index_rc > 1 )) || [[ ! -s "$sam_m82_index_stage/nes_gamelist.txt" ]]; then
			echo "Error: NES gamelist missing. Make sure you have NES games."
            sam_m82_cleanup_index
            return 1
		fi
        cp "$sam_m82_index_stage/nes_gamelist.txt" "$gamelistpath/nes.tmp.$BASHPID" &&
            mv -f "$gamelistpath/nes.tmp.$BASHPID" "$gamelistpath/nes_gamelist.txt" || { sam_m82_cleanup_index; return 1; }
        sam_m82_cleanup_index
	fi
	if [ -f "${gamelistpathtmp}"/nes_gamelist.txt ]; then
		rm "${gamelistpathtmp}"/nes_gamelist.txt
	fi
	local m82_list_path="${gamelistpath}"/m82_list.txt
	# Check if the M82 list file exists
	if [ ! -f "$m82_list_path" ]; then
		echo "Error: The M82 list file ($m82_list_path) does not exist. Updating SAM now. Please try again."
		repository_url="https://github.com/mrchrisster/MiSTer_SAM"
		echo "Install $m82_list_path before enabling M82." >&2; return 1
	fi

	if [[ "$m82_muted" == "yes" ]]; then
		mute="global"
	else
		mute="no"
		only_unmute_if_needed
	fi
	gametimer="21"
}

sam_m82_cleanup_index() {
    if [[ -n "${sam_m82_index_stage:-}" && "$sam_m82_index_stage" == "$mrsamtmp/m82-index."* ]]; then
        rm -rf -- "$sam_m82_index_stage"
    fi
    sam_m82_index_stage=
}
