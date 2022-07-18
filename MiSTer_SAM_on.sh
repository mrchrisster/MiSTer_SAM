#!/bin/bash

declare -g mrsampath="/media/fat/Scripts/.SuperAttract"
declare -g gamelistpath="${mrsampath}/SAM_Gamelists"
declare -g repository_url="https://github.com/mrchrisster/MiSTer_SAM"
declare -g userstartup="/media/fat/linux/user-startup.sh"
declare -g userstartuptpl="/media/fat/linux/_user-startup.sh"
declare -g branch="main"


if [ -f "/media/fat/Scripts/MiSTer_SAM.ini" ]; then
	source "/media/fat/Scripts/MiSTer_SAM.ini"
fi

function parse_cmd() {
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
		#cp --force "/tmp/MiSTer_SAM_on.sh" "/media/fat/Scripts/MiSTer_SAM_on.sh"

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

		get_partun
		get_mbc
		get_inputmap
        	get_samstuff Super_Attract_Mode.sh /media/fat/Scripts
		get_samstuff .SuperAttract/SuperAttract_init
		get_samstuff .SuperAttract/SuperAttract_MCP
		get_samstuff .SuperAttract/SuperAttract_joy.py
		get_samstuff .SuperAttract/SuperAttract_keyboard.py
		get_samstuff .SuperAttract/SuperAttract_mouse.py
		get_samstuff .SuperAttract/SuperAttract_tty2oled

		if [ -f /media/fat/Scripts/MiSTer_SAM.ini ]; then
			cp /media/fat/Scripts/MiSTer_SAM.ini /media/fat/Scripts/Super_Attract_Mode.ini
		fi
		
		if [ -f /media/fat/Scripts/Super_Attract_Mode.ini ]; then
			echo " MiSTer SAM INI already exists... Merging with new ini."
			get_samstuff Super_Attract_Mode.ini /tmp
			echo " Backing up Super_Attract_Mode.ini to Super_Attract_Mode.ini.bak"
			cp /media/fat/Scripts/Super_Attract_Mode.ini /media/fat/Scripts/Super_Attract_Mode.ini.bak
			echo -n " Merging ini values.."
			# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
			sed -i 's/==/--/g' /media/fat/Scripts/Super_Attract_Mode.ini
			sed -i 's/-=/--/g' /media/fat/Scripts/Super_Attract_Mode.ini
			awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' /media/fat/Scripts/Super_Attract_Mode.ini /tmp/Super_Attract_Mode.ini >/tmp/SuperAttract.tmp && mv --force /tmp/SuperAttract.tmp /media/fat/Scripts/Super_Attract_Mode.ini
			echo "Done."

		else
			get_samstuff Super_Attract_Mode.ini /media/fat/Scripts
		fi
		
		#blacklist files
		get_samstuff .SuperAttract/SAM_Gamelists/arcade_blacklist.txt /media/fat/Scripts/.SuperAttract/SAM_Gamelists

	fi

    sam_bootmigrate

	echo " Update complete!"


    return

}

# ======== UPDATER FUNCTIONS ========
function curl_download() { # curl_download ${filepath} ${URL}

	curl \
		--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
		--insecure \
		--fail \
		--location \
		-o "${1}" \
		"${2}"
}
function get_samstuff() { #get_samstuff file (path)
	if [ -z "${1}" ]; then
		return 1
	fi

	filepath="${2}"
	if [ -z "${filepath}" ]; then
		filepath="${mrsampath}"
	fi

	echo -n " Downloading from ${repository_url}/blob/${branch}/${1} to ${filepath}/..."
	curl_download "/tmp/${1##*/}" "${repository_url}/blob/${branch}/${1}?raw=true"

	if [ ! "${filepath}" == "/tmp" ]; then
		mv --force "/tmp/${1##*/}" "${filepath}/${1##*/}"
	fi

	if [ "${1##*.}" == "sh" ]; then
		chmod +x "${filepath}/${1##*/}"
	fi

	echo " Done!"
}

function get_partun() {
	REPOSITORY_URL="https://github.com/woelper/partun"
	echo " Downloading partun - needed for unzipping roms from big archives..."
	echo " Created for MiSTer by woelper - Talk to him at this year's PartunCon"
	echo " ${REPOSITORY_URL}"
	latest=$(curl -s -L --insecure https://api.github.com/repos/woelper/partun/releases/latest | jq -r ".assets[] | select(.name | contains(\"armv7\")) | .browser_download_url")
	curl_download "/tmp/partun" "${latest}"
	mv --force "/tmp/partun" "${mrsampath}/partun"
	echo " Done!"
}

function get_mbc() {
	echo " Downloading mbc - Control MiSTer from cmd..."
	echo " Created for MiSTer by pocomane"
	get_samstuff .SuperAttract/mbc
}

function get_inputmap() {
	echo -n " Downloading input maps - needed to skip past BIOS for some systems..."
	get_samstuff .SuperAttract/inputs/GBA_input_1234_5678_v3.map /media/fat/Config/inputs >/dev/null
	get_samstuff .SuperAttract/inputs/MegaCD_input_1234_5678_v3.map /media/fat/Config/inputs >/dev/null
	get_samstuff .SuperAttract/inputs/NES_input_1234_5678_v3.map /media/fat/Config/inputs >/dev/null
	get_samstuff .SuperAttract/inputs/TGFX16_input_1234_5678_v3.map /media/fat/Config/inputs >/dev/null
	echo " Done!"
}

function sam_cleanup() {
	# Clean up by umounting any mount binds
	tty_exit &
	bgm_stop
	[ "$(mount | grep -ic '/media/fat/config')" == "1" ] && umount "/media/fat/config"
	[ "$(mount | grep -ic ${amigapath}/shared)" == "1" ] && umount "${amigapath}/shared"
	[ -d "${misterpath}/Bootrom" ] && [ "$(mount | grep -ic 'bootrom')" == "1" ] && umount "${misterpath}/Bootrom"
	[ -f "${misterpath}/Games/NES/boot1.rom" ] && [ "$(mount | grep -ic 'nes/boot1.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot1.rom"
	[ -f "${misterpath}/Games/NES/boot2.rom" ] && [ "$(mount | grep -ic 'nes/boot2.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot2.rom"
	[ -f "${misterpath}/Games/NES/boot3.rom" ] && [ "$(mount | grep -ic 'nes/boot3.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot3.rom"
	if [ "${samquiet}" == "no" ]; then printf '%s\n' " Cleaned up mounts."; fi
}

function tty_exit() { # tty_exit
	if [ "${ttyenable}" == "yes" ]; then
		# Clear Display	with Random effect
		echo "CMDCLST,19,1" >${ttydevice}
		# echo "CMDCLS" >"${ttydevice}"
		tty_waitfor &
		# Starting tty2oled daemon only if needed
		if [ "${ttyuseack}" == "yes" ]; then
			if [[ ! $(ps -o pid,args | grep '[t]ty2oled.sh' | awk '{print $1}') ]]; then
				sleep 1
				tmux new -s TTY -d "/media/fat/tty2oled/tty2oled.sh"
			fi
		fi
	fi
}

function bgm_stop() {

	if [ "${bgm}" == "yes" ]; then
		echo -n "set playincore no" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
		echo -n "stop" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
	fi

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
		rsync -avx "/media/fat/Scripts/.MiSTer_SAM/SAM_Gamelists" "/media/fat/Scripts/.SuperAttract/SAM_Gamelists" >/dev/null
		echo " Done."
	fi
}

parse_cmd ${@}
