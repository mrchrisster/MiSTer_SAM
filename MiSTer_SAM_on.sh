#!/bin/bash

declare -g misterpath="/media/fat"
declare -g misterscripts="${misterpath}/Scripts"
declare -g mrsampath="${misterscripts}/.SuperAttract"
declare -g gamelistpath="${mrsampath}/SAM_Gamelists"
declare -g repository_url="https://github.com/mrchrisster/MiSTer_SAM"
declare -g userstartup="/media/fat/linux/user-startup.sh"
declare -g userstartuptpl="/media/fat/linux/_user-startup.sh"
declare -g branch="named-pipes"


if [ -f "/media/fat/Scripts/Super_Attract_Mode.ini" ]; then
	source "/media/fat/Scripts/Super_Attract_Mode.ini"
elif [ -f "/media/fat/Scripts/MiSTer_SAM.ini" ]; then
	source "/media/fat/Scripts/MiSTer_SAM.ini"
fi

function sam_update() { # sam_update (next command)
	# End script through button push

	echo "Button push." >/tmp/.SAM_Joy_Activity
	# Ensure the MiSTer SAM data directory exists
	mkdir --parents "${mrsampath}" &>/dev/null
	mkdir --parents "${gamelistpath}" &>/dev/null

	if [ ! "$(dirname -- ${0})" == "/tmp" ]; then
		# Warn if using non-default branch for updates
		if [ ! "${branch}" == "main" ]; then
			echo ""
			echo "*******************************"
			echo " Updating from ${branch}"
			echo "*******************************"
			echo ""
		fi

		# Download the newest MiSTer_SAM_on.sh to /tmp
		get_samstuff MiSTer_SAM_on.sh /tmp
		if [ -f /tmp/MiSTer_SAM_on.sh ]; then
			if [ ${1} ]; then
				echo " Continuing setup with latest MiSTer_SAM_on.sh..."
				/tmp/MiSTer_SAM_on.sh ${1}
				exit 0
			else
				echo " Launching latest"
				echo " MiSTer_SAM_on.sh..."
				/tmp/MiSTer_SAM_on.sh update
				exit 0
			fi
		else
			# /tmp/MiSTer_SAM_on.sh isn't there!
			echo " SAM update FAILED"
			echo " No Internet?"
			exit 1
		fi
	else # We're running from /tmp - download dependencies and proceed
		if [ -f ${misterscripts}/MiSTer_SAM_on.sh ]; then
			echo ""
			echo ""
			echo " !!! PLEASE NOTE !!!"
			echo " MiSTer_SAM_on.sh has been renamed to Super_Attract_Mode.sh"
			echo ""
			for i in {5..1}; do
				echo -en " Migrating to new file naming convention in ${i}...\r"
				sleep 1
			done
			echo ""
		fi

		get_partun
		get_mbc
		get_samindex
		get_inputmap
		get_samstuff Super_Attract_Mode.sh ${misterscripts}
		get_samstuff .SuperAttract/SuperAttract_init
		get_samstuff .SuperAttract/SuperAttract_MCP
		get_samstuff .SuperAttract/SuperAttract_joy.py
		get_samstuff .SuperAttract/SuperAttract_keyboard.py
		get_samstuff .SuperAttract/SuperAttract_mouse.py
		get_samstuff .SuperAttract/SuperAttract_tty2oled
		get_samstuff .SuperAttract/SuperAttractSystem

		# blacklist files
		get_samstuff .SuperAttract/SAM_Excludelists/arcade_blacklist.txt ${excludepath}
		get_samstuff .SuperAttract/SAM_Excludelists/fds_blacklist.txt ${excludepath}
		get_samstuff .SuperAttract/SAM_Excludelists/megacd_blacklist.txt ${excludepath}
		get_samstuff .SuperAttract/SAM_Excludelists/tgfx16cd_blacklist.txt ${excludepath}

		if [ -f /media/fat/Scripts/MiSTer_SAM.ini ]; then
			cp /media/fat/Scripts/MiSTer_SAM.ini /media/fat/Scripts/Super_Attract_Mode.ini
		fi

		if [ -f "${misterscripts}/Super_Attract_Mode.ini" ]; then
			echo " SAM INI already exists... Merging with new ini."
			get_samstuff "Super_Attract_Mode.ini" /tmp
			echo " Backing up Super_Attract_Mode.ini to Super_Attract_Mode.ini.bak"
			cp ${misterscripts}/"Super_Attract_Mode.ini" ${misterscripts}/"Super_Attract_Mode.ini.bak" &>/dev/null
			echo -n " Merging ini values.."
			# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
			sed -i 's/==/--/g' ${misterscripts}/"Super_Attract_Mode.ini"
			sed -i 's/-=/--/g' ${misterscripts}/"Super_Attract_Mode.ini"
			sed -i 's/^corelist_allow=/corelist=/g' ${misterscripts}/"Super_Attract_Mode.ini"
			sed -i 's/^\^corelist_allow=/corelist=/g' ${misterscripts}/"Super_Attract_Mode.ini"
			awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' ${misterscripts}/Super_Attract_Mode.ini /tmp/"Super_Attract_Mode.ini" >/tmp/SuperAttract.tmp && mv --force /tmp/SuperAttract.tmp ${misterscripts}/"Super_Attract_Mode.ini"
			echo "Done."

		else
			get_samstuff Super_Attract_Mode.ini ${misterscripts}
		fi

	fi

    sam_bootmigrate

	[[ -f "/tmp/MiSTer_SAM_on.sh" ]] && rm -f "/tmp/MiSTer_SAM_on.sh"
	[[ -f "/tmp/Super_Attract_Mode.sh" ]] && rm -f "/tmp/Super_Attract_Mode.sh"
	[[ -f "/tmp/Super_Attract_Mode.ini" ]] && rm -f "/tmp/Super_Attract_Mode.ini"
	[[ -f "/tmp/SuperAttractSystem" ]] && rm -f "/tmp/SuperAttractSystem"
	[[ -f "/tmp/samindex.zip" ]] && rm -f "/tmp/samindex.zip"

	echo " Update complete!"
	echo " Please reboot your Mister. (Cold Reboot) or start SAM from the menu"

	sam_exit 0 "stop"
}

# ======== UPDATER FUNCTIONS ========
function curl_download() { # curl_download ${filepath} ${URL}

	curl \
		--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
		--insecure \
		--fail \
		--location \
		-o "${1}" \
		"${2-}"
}

function get_samstuff() { #get_samstuff file (path)
	if [ -z "${1}" ]; then
		return 1
	fi

	local filepath="${2:-${mrsampath}}"

	echo -n " Downloading from ${repository_url}/blob/${branch}/${1} to ${filepath}/..."
	curl_download "/tmp/${1##*/}" "${repository_url}/blob/${branch}/${1}?raw=true"

	if [ "${filepath}" != "/tmp" ]; then
		mv --force "/tmp/${1##*/}" "${filepath}/${1##*/}"
	fi

	if [ "${1##*.}" == "sh" ]; then
		chmod +x "${filepath}/${1##*/}"
	fi

	echo " Done!"
}

function get_partun() {
	local REPO_URL="https://github.com/woelper/partun"
	echo " Downloading partun - needed for unzipping roms from big archives..."
	echo " Created for MiSTer by woelper - Talk to him at this year's PartunCon"
	echo " ${REPO_URL}"
	local latest=$(curl -s -L --insecure https://api.github.com/repos/woelper/partun/releases/latest | jq -r ".assets[] | select(.name | contains(\"armv7\")) | .browser_download_url")
	curl_download "/tmp/partun" "${latest}"
	[[ ! -d "${mrsampath}/bin" ]] && mkdir -p "${mrsampath}/bin"
	mv --force "/tmp/partun" "${mrsampath}/bin/partun"
	[[ -f "${mrsampath}/partun" ]] && rm -f "${mrsampath}/partun"
	echo " Done!"
}

function get_samindex() {
	local REPO_URL="${repository_url}/blob/${branch}/.SuperAttract/bin/samindex.zip?raw=true"
	echo " Downloading samindex - needed for creating gamelists..."
	echo " Created for MiSTer by wizzo"
	echo " ${REPO_URL}"
	local latest="${repository_url}/blob/${branch}/.SuperAttract/bin/samindex.zip?raw=true"
	curl_download "/tmp/samindex.zip" "${latest}"
	[[ ! -d "${mrsampath}/bin" ]] && mkdir -p "${mrsampath}/bin"
	unzip -ojq /tmp/samindex.zip -d "${mrsampath}/bin" # &>/dev/null
	# mv --force "/tmp/samindex" "${mrsampath}/bin/samindex"
	[[ -f "${mrsampath}/samindex" ]] && rm -f "${mrsampath}/samindex"
	echo " Done!"
}

function get_mbc() {
	local REPO_URL="${repository_url}/blob/${branch}/.SuperAttract/bin/mbc?raw=true"
	echo " Downloading mbc - Control MiSTer from cmd..."
	echo " Created for MiSTer by pocomane"
	echo " ${REPO_URL}"
	local latest="${repository_url}/blob/${branch}/.SuperAttract/bin/mbc?raw=true"
	curl_download "/tmp/mbc" "${latest}"
	[[ ! -d "${mrsampath}/bin" ]] && mkdir -p "${mrsampath}/bin"
	mv --force "/tmp/mbc" "${mrsampath}/bin/mbc"
	[[ -f "${mrsampath}/mbc" ]] && rm -f "${mrsampath}/mbc"
	echo " Done!"
}

function get_inputmap() {
	echo -n " Downloading input maps - needed to skip past BIOS for some systems..."
	get_samstuff .SuperAttract/inputs/GBA_input_1234_5678_v3.map ${misterpath}/config/inputs >/dev/null
	get_samstuff .SuperAttract/inputs/MegaCD_input_1234_5678_v3.map ${misterpath}/config/inputs >/dev/null
	get_samstuff .SuperAttract/inputs/NES_input_1234_5678_v3.map ${misterpath}/config/inputs >/dev/null
	get_samstuff .SuperAttract/inputs/TGFX16_input_1234_5678_v3.map ${misterpath}/config/inputs >/dev/null
	echo " Done!"
}

function sam_cleanup() {
	# Clean up by umounting any mount binds
	[[ $(mount | grep -ic "${misterpath}/config") -eq 1 ]] && umount "${misterpath}/config"
	# [[ $(mount | grep -ic ${amigashared}) != "0" ]] && umount "${amigashared}"
	[[ -d "${misterpath}/bootrom" ]] && [[ $(mount | grep -ic 'bootrom') != "0" ]] && umount "${misterpath}/bootrom"
	[[ -f "${CORE_PATH_FINAL[NES]}/boot1.rom" ]] && [[ $(mount | grep -ic 'nes/boot1.rom') != "0" ]] && umount "${CORE_PATH_FINAL[NES]}/boot1.rom"
	[[ -f "${CORE_PATH_FINAL[NES]}/boot2.rom" ]] && [[ $(mount | grep -ic 'nes/boot2.rom') != "0" ]] && umount "${CORE_PATH_FINAL[NES]}/boot2.rom"
	[[ -f "${CORE_PATH_FINAL[NES]}/boot3.rom" ]] && [[ $(mount | grep -ic 'nes/boot3.rom') != "0" ]] && umount "${CORE_PATH_FINAL[NES]}/boot3.rom"
	[[ -p ${SAM_Activity_pipe} ]] && rm -f ${SAM_Activity_pipe}
	[[ -e ${SAM_Activity_pipe} ]] && rm -f ${SAM_Activity_pipe}
	[[ -p ${SAM_cmd_pipe} ]] && rm -f ${SAM_cmd_pipe}
	[[ -e ${SAM_cmd_pipe} ]] && rm -f ${SAM_cmd_pipe}
}

function sam_bootmigrate() {
    echo " Deleting old startup files..."
	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	fi
	sed -i '/MiSTer_SAM/d' ${userstartup}
	sed -i '/Attract/d' ${userstartup}

    echo " Done."

    # Add new startup way

    if [ ! -e "${userstartup}" ] && [ -e /etc/init.d/S99user ]; then
		if [ -e "${userstartuptpl}" ]; then
			echo "Copying ${userstartuptpl} to ${userstartup}"
			cp "${userstartuptpl}" "${userstartup}"
		else
			echo "Building ${userstartup}"
		fi
	fi
	if [ $(grep -ic "mister_sam" ${userstartup}) = "0" ] || [ $(grep -ic "attract" ${userstartup}) = "0" ]; then
		echo -e " Add Super Attract Mode to ${userstartup}\n"
		echo -e "\n# Startup Super Attract Mode" >>${userstartup}
		echo -e "[[ -e ${mrsampath}/SuperAttract_init ]] && ${mrsampath}/SuperAttract_init \$1 &" >>"${userstartup}"
	fi

	if [ -d /media/fat/Scripts/.MiSTer_SAM/SAM_Gamelists ]; then
		echo -e " Migrating Gamelists..."
		rsync -avx "/media/fat/Scripts/.MiSTer_SAM/SAM_Gamelists/" "/media/fat/Scripts/.SuperAttract/SAM_Gamelists/" >/dev/null
		echo " Done."
	fi
}

function main() {
	while [ ${#} -gt 0 ]; do
        case "${1,,}" in
			default) # sam_update relaunches itself
				sam_update autoconfig
				break
				;;
			autoconfig | defaultb | update) # Update SAM
				sam_cleanup
				sam_update
				break
				;;
			*)
				echo " ERROR! ${1} is unknown."
				echo " Try $(basename -- ${0}) help"
				echo " Or check the Github readme."
				break
				;;
		esac
	done
}

main ${@}
