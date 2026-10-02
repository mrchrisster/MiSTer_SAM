# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function build_m82_list() {
	[ ! -d "/tmp/.SAM_List" ] && mkdir /tmp/.SAM_List/
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
		echo "Install $m82_list_path before enabling M82." >&2; return 1
	fi

	printf "%s\n" nes > "${corelistfile}"
	if [[ "$m82_muted" == "yes" ]]; then
		mute="global"
	else
		mute="no"
		only_unmute_if_needed
	fi
	gametimer="21"
}
