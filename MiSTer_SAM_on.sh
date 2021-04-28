#!/bin/bash

# https://github.com/mrchrisster/MiSTer_SAM/
# Copyright (c) 2021 by mrchrisster and Mellified

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

## Description
# This cycles through arcade and console cores periodically
# Games are randomly pulled from their respective folders

# ======== Credits ========
# Original concept and implementation by: mrchrisster
# Additional development by: Mellified
#
# Thanks for the contributions and support:
# pocomane, kaloun34, RetroDriven, woelper, LamerDeluxe


#======== INI VARIABLES ========
# Change these in the INI file

#======== GLOBAL VARIABLES =========
declare -g mrsampath="/media/fat/Scripts/.MiSTer_SAM"
declare -g misterpath="/media/fat"

#======== DEBUG VARIABLES ========
samquiet="Yes"

#======== LOCAL VARIABLES ========
branch="main"
mbcurl="blob/master/mbc_v02"
doreboot="Yes"
normalreboot="Yes"

#========= PARSE INI =========
# Read INI
if [ -f "${misterpath}/Scripts/MiSTer_SAM.ini" ]; then
	source "${misterpath}/Scripts/MiSTer_SAM.ini"
fi

# Remove trailing slash from paths
for var in mrsampath misterpath mrapathvert mrapathhoriz arcadepath gbapath genesispath megacdpath neogeopath nespath snespath tgfx16path tgfx16cdpath; do
	declare -g ${var}="${!var%/}"
done


# Warn if using non-default branch
if [ ! "${branch}" == "main" ]; then
	echo ""
	echo "***********************************************"
	echo "!! DOWNLOADING UPDATES FROM ${branch} BRANCH !!"
	echo "***********************************************"
	echo ""
fi


#======== BASIC FUNCTIONS ========
there_can_be_only_one() # there_can_be_only_one PID Process
{
	# If another attract process is running kill it
	# This can happen if the script is started multiple times
	if [ ! -z "$(pidof -o ${1} $(basename -- ${2}))" ]; then
		echo ""
		echo "Removing other running instances of $(basename -- ${2})..."
		kill -9 $(pidof -o ${1} $(basename -- ${2})) &>/dev/null
	fi
}


#======== DOWNLOAD FUNCTIONS ========
curl_check()
{
	ALLOW_INSECURE_SSL="true"
	SSL_SECURITY_OPTION=""
	curl --connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 \
	 --silent --show-error "https://github.com" > /dev/null 2>&1
	case $? in
		0)
			;;
		60)
			if [[ "${ALLOW_INSECURE_SSL}" == "true" ]]
			then
				declare -g SSL_SECURITY_OPTION="--insecure"
			else
				echo "CA certificates need"
				echo "to be fixed for"
				echo "using SSL certificate"
				echo "verification."
				echo "Please fix them i.e."
				echo "using security_fixes.sh"
				exit 2
			fi
			;;
		*)
			echo "No Internet connection"
			exit 1
			;;
	esac
	set -e
}

curl_download() # curl_download ${filepath} ${URL}
{
		curl \
			--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
			${SSL_SECURITY_OPTION} \
			--fail \
			--location \
			-o "${1}" \
			"${2}"
}


#======== UPDATER FUNCTIONS ========
get_samstuff() #get_samstuff file (path)
{
	if [ -z "${1}" ]; then
		return 1
	fi
	
	filepath="${2}"
	if [ -z "${filepath}" ]; then
		filepath="${mrsampath}"
	fi

	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
	
	echo -n "Downloading from ${REPOSITORY_URL}/blob/${branch}/${1} to ${filepath}/... "
	curl_download "/tmp/${1##*/}" "${REPOSITORY_URL}/blob/${branch}/${1}?raw=true"

	if [ ! "${filepath}" == "/tmp" ]; then
		mv --force "/tmp/${1##*/}" "${filepath}/${1##*/}"
	fi

	if [ "${1##*.}" == "sh" ]; then
		chmod +x "${filepath}/${1##*/}"
	fi
	echo "Done!"
}

get_mbc()
{
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_Batch_Control"
	echo "Downloading mbc - a tool needed for launching roms..."
	echo "Created for MiSTer by pocomane"
	echo "${REPOSITORY_URL}"
	echo ""
	curl_download "/tmp/mbc" "${REPOSITORY_URL}/${mbcurl}?raw=true"
	mv --force "/tmp/mbc" "${mrsampath}/mbc"
}

get_partun()
{
    REPOSITORY_URL="https://github.com/woelper/partun"
    echo "Downloading partun - needed for unzipping roms from big archives..."
    echo "Created for MiSTer by woelper - who is allegedly not a spider"
    echo "${REPOSITORY_URL}"
    echo ""
    latest=$(curl -s -L --insecure https://api.github.com/repos/woelper/partun/releases/latest | jq -r ".assets[] | select(.name | contains(\"armv7\")) | .browser_download_url")
    curl_download "/tmp/partun" "${latest}"
   	mv --force "/tmp/partun" "${mrsampath}/partun"
}


#======== CONFIGURATION ========
config_init()
{
	echo -n "Turning MiSTer SAM on..."
	# Remount root as read-write if read-only so we can add our daemon
	mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
	[ "$RO_ROOT" == "true" ] && mount / -o remount,rw

	# Awaken daemon
	mv -f "${mrsampath}/MiSTer_SAM_init" /etc/init.d/S93mistersam &>/dev/null
	chmod +x /etc/init.d/S93mistersam

	# Remove read-write if we were read-only
	sync
	[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	sync
	echo "Done!"
}


#======== MAIN ========
# Ensure the MiSTer SAM data directory exists
mkdir --parents "${mrsampath}" &>/dev/null

# Prep curl
curl_check

#======== DEBUG OUTPUT =========
if [ "${samquiet,,}" == "no" ]; then
	echo "********************************************************************************"
	#======== GLOBAL VARIABLES =========
	echo "mrsampath: ${mrsampath}"
	echo "misterpath: ${misterpath}"
	#======== LOCAL VARIABLES ========
	echo "branch: ${branch}"
	echo "mbcurl: ${mbcurl}"
	echo "********************************************************************************"
fi	


if [ ! "$(dirname -- ${0})" == "/tmp" ]; then
	# Initial run - need to get updated MiSTer_SAM_on.sh
	echo "Stopping MiSTer SAM processes..."

	# Clean out existing processes to ensure we can update
	there_can_be_only_one "$$" "${0}"
	there_can_be_only_one "0" "S93mistersam"
	there_can_be_only_one "0" "MiSTer_SAM.sh"

	# Download the newest MiSTer_SAM_on.sh to /tmp
	get_samstuff MiSTer_SAM_on.sh /tmp
	if [ -f /tmp/MiSTer_SAM_on.sh ]; then
		/tmp/MiSTer_SAM_on.sh
		exit 0
	else
		# /tmp/MiSTer_SAM_on.sh isn't there!
  	echo "MiSTer SAM update FAILED - no Internet?"
		config_init
	fi
else # We're running from /tmp - download dependencies and proceed
	cp --force "/tmp/MiSTer_SAM_on.sh" "/media/fat/Scripts/MiSTer_SAM_on.sh"
	get_mbc
	get_partun
	get_samstuff MiSTer_SAM/MiSTer_SAM.sh
	get_samstuff MiSTer_SAM/MiSTer_SAM_init
	get_samstuff MiSTer_SAM/MiSTer_SAM_MCP.sh
	get_samstuff MiSTer_SAM/MiSTer_SAM_joy.sh
	get_samstuff MiSTer_SAM/MiSTer_SAM_joy.py
	get_samstuff MiSTer_SAM/MiSTer_SAM_joy_change.sh
	get_samstuff MiSTer_SAM/MiSTer_SAM_keyboard.sh
	get_samstuff MiSTer_SAM/MiSTer_SAM_mouse.sh
	get_samstuff MiSTer_SAM/MiSTer_SAM_now.sh /media/fat/Scripts
	get_samstuff MiSTer_SAM/MiSTer_SAM_off.sh /media/fat/Scripts
	
	if [ -f /media/fat/Scripts/MiSTer_SAM.ini ]; then
		echo "MiSTer SAM INI already exists... SKIPPED!"
	else
		get_samstuff MiSTer_SAM.ini /media/fat/Scripts
	fi

	config_init
fi


if [ "${doreboot,,}" == "yes" ]; then
	if [ "${normalreboot,,}" == "yes" ]; then
		echo "Rebooting..."
		reboot
	else
		echo "Forcing reboot..."
		reboot -f
	fi
else
	echo -n "MiSTer SAM daemon launching... "
	/etc/init.d/S93mistersam start &
	echo "Done!"
fi

exit 0
