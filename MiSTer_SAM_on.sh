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


#======== DEFAULT VARIABLES ========
mrsampath="/media/fat/Scripts/.MiSTer_SAM"

#======== BASIC FUNCTIONS ========
there_can_be_only_one() # there_can_be_only_one PID Process
{
	# If another attract process is running kill it
	# This can happen if the script is started multiple times
	if [ ! -z "$(pidof -o ${1} $(basename ${2}))" ]; then
		echo ""
		echo "Removing other running instances of $(basename ${2})..."
		kill -9 $(pidof -o ${1} $(basename ${2})) &>/dev/null
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
get_samon() #get_samon process_name
{
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
	if [ "$(dirname -- "${1}")" == "/tmp" ]; then
		echo "Updating MiSTer_SAM_on.sh"
		cp -f "/tmp/MiSTer_SAM_on.sh" "/media/fat/Scripts/MiSTer_SAM_on.sh"
	else
		echo "Downloading MiSTer SAM on"
		curl_download "/tmp/MiSTer_SAM_on.sh" "${REPOSITORY_URL}/blob/main/MiSTer_SAM_on.sh?raw=true"
		chmod +x "/tmp/MiSTer_SAM_on.sh"
	fi
}

get_mbc()
{
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_Batch_Control"
	echo "Downloading mbc - a tool needed for launching roms"
	echo "Created for MiSTer by pocomane"
	echo "${REPOSITORY_URL}"
	echo ""
	curl_download "/tmp/mbc" "${REPOSITORY_URL}/blob/master/mbc_v02?raw=true"
	mv -f "/tmp/mbc" "${mrsampath}/mbc"
}

get_partun()
{
	REPOSITORY_URL="https://github.com/woelper/partun"
	echo "Downloading partun - needed for unzipping roms from big archives."
	echo "Created for MiSTer by woelper - who is allegedly not a spider"
	echo "${REPOSITORY_URL}"
	echo ""
	curl_download "/tmp/partun" "${REPOSITORY_URL}/releases/download/0.1.5/partun_armv7"
	mv -f "/tmp/partun" "${mrsampath}/partun"
}

get_sam()
{
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
	echo "Updating MiSTer Super Attract Mode"
	curl_download "/tmp/MiSTer_SAM.sh" "${REPOSITORY_URL}/blob/main/MiSTer_SAM/MiSTer_SAM.sh?raw=true"
	mv -f "/tmp/MiSTer_SAM.sh" "${mrsampath}/MiSTer_SAM.sh"
}

get_samoff()
{
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
	echo "Updating MiSTer SAM off"
	curl_download "/tmp/MiSTer_SAM_off.sh" "${REPOSITORY_URL}/blob/main/MiSTer_SAM/MiSTer_SAM_off.sh?raw=true"
	mv -f "/tmp/MiSTer_SAM_off.sh" "/media/fat/Scripts/MiSTer_SAM_off.sh"
}

get_ini()
{
	if [ ! -f "/media/fat/Scripts/MiSTer_SAM.ini" ]; then
		REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
		echo "Downloading MiSTer SAM INI"
		curl_download "/media/fat/Scripts/MiSTer_SAM.ini" "${REPOSITORY_URL}/blob/main/MiSTer_SAM.ini?raw=true"
	else
		echo "SKIPPED MiSTer SAM INI - already exists!"
	fi
}

get_init()
{
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
	echo "Updating MiSTer SAM daemon"
	curl_download "/tmp/MiSTer_SAM_init" "${REPOSITORY_URL}/blob/main/MiSTer_SAM/MiSTer_SAM_init?raw=true"
	mv -f "/tmp/MiSTer_SAM_init" "${mrsampath}/MiSTer_SAM_init"
}

get_joy()
{
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
	echo "Updating MiSTer SAM controller helper"
	curl_download "/tmp/MiSTer_SAM_joy.sh" "${REPOSITORY_URL}/blob/main/MiSTer_SAM/MiSTer_SAM_joy.sh?raw=true"
	mv -f "/tmp/MiSTer_SAM_joy.sh" "${mrsampath}/MiSTer_SAM_joy.sh"
}

get_keyboard()
{
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
	echo "Updating MiSTer SAM keyboard helper"
	curl_download "/tmp/MiSTer_SAM_keyboard.sh" "${REPOSITORY_URL}/blob/main/MiSTer_SAM/MiSTer_SAM_keyboard.sh?raw=true"
	mv -f "/tmp/MiSTer_SAM_keyboard.sh" "${mrsampath}/MiSTer_SAM_keyboard.sh"
}

get_mouse()
{
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
	echo "Updating MiSTer SAM mouse helper"
	curl_download "/tmp/MiSTer_SAM_mouse.sh" "${REPOSITORY_URL}/blob/main/MiSTer_SAM/MiSTer_SAM_mouse.sh?raw=true"
	mv -f "/tmp/MiSTer_SAM_mouse.sh" "${mrsampath}/MiSTer_SAM_mouse.sh"
}


#======== CONFIGURATION ========
config_helpers()
{
	echo "Configuring helpers"
	chmod +x "${mrsampath}/MiSTer_SAM_joy.sh"
	chmod +x "${mrsampath}/MiSTer_SAM_keyboard.sh"
	chmod +x "${mrsampath}/MiSTer_SAM_mouse.sh"
}

config_init()
{
	# Remount root as read-write if read-only so we can add our daemon
	mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
	[ "$RO_ROOT" == "true" ] && mount / -o remount,rw

	# Awaken daemon
	echo "Adding launch daemon"
	mv -f "${mrsampath}/MiSTer_SAM_init" /etc/init.d/S93mistersam &>/dev/null
	chmod +x /etc/init.d/S93mistersam

	# Remove read-write if we were read-only
	sync
	[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	sync
}


#======== DEPENDENCIES ========
echo "Turning MiSTer SAM on"
# Read INI
basepath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if [ -f ${basepath}/MiSTer_SAM.ini ]; then
	. ${basepath}/MiSTer_SAM.ini
	IFS=$'\n'
fi

# Remove trailing slash from paths
for var in mrsampath; do
	declare -g ${var}="${!var%/}"
done

# Ensure the MiSTer SAM data directory exists
mkdir "${mrsampath}" &>/dev/null

there_can_be_only_one "$$" "${0}"
there_can_be_only_one "0" "S93mistersam"
there_can_be_only_one "0" "MiSTer_SAM.sh"

curl_check

get_samon "${0}"

# If we're running from /tmp update and proceed
if [ "$(dirname -- ${0})" == "/tmp" ]; then
	get_mbc
	get_partun
	get_sam
	get_samoff
	get_ini
	get_init
	get_joy
	get_keyboard
	get_mouse
	config_helpers
	config_init
elif [ -f /tmp/MiSTer_SAM_on.sh ]; then
	/tmp/MiSTer_SAM_on.sh
	exit 0
else
  echo "Unable to update - no Internet?"
	config_helpers
	config_init
fi

echo "MiSTer SAM daemon launch"
/etc/init.d/S93mistersam start &
exit 0
