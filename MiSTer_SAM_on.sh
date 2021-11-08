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
# pocomane, kaloun34, redsteakraw, RetroDriven, woelper, LamerDeluxe


#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/media/fat/linux:/media/fat/Scripts:/media/fat/Scripts/.MiSTer_SAM:.

#======== INI VARIABLES ========
# Change these in the INI file

#======== GLOBAL VARIABLES =========
declare -g mrsampath="/media/fat/Scripts/.MiSTer_SAM"
declare -g misterpath="/media/fat"
# Save our PID and process
declare -g sampid="${$}"
declare -g samprocess="$(basename -- ${0})"

#======== DEBUG VARIABLES ========
samquiet="Yes"
samdebug="No"
samtrace="No"

#======== LOCAL VARIABLES ========
declare -i coreretries=3
declare -i romloadfails=0
mralist="/tmp/.SAMmras"
gametimer=120
corelist="arcade,gba,genesis,megacd,neogeo,nes,snes,tgfx16,tgfx16cd"
usezip="Yes"
disablebootrom="Yes"
listenmouse="Yes"
listenkeyboard="Yes"
listenjoy="Yes"
branch="main"
mbcurl="blob/master/mbc_v06"

# ======== TTY2OLED =======
ttyenable="No"
ttydevice="/dev/ttyUSB0"

#======== CORE PATHS ========
arcadepath="/media/fat/_arcade"
gbapath="/media/fat/games/GBA"
genesispath="/media/fat/games/Genesis"
megacdpath="/media/fat/games/MegaCD"
neogeopath="/media/fat/games/NeoGeo"
nespath="/media/fat/games/NES"
snespath="/media/fat/games/SNES"
tgfx16path="/media/fat/games/TGFX16"
tgfx16cdpath="/media/fat/games/TGFX16-CD"

#======== EXCLUDE LISTS ========
arcadeexclude="First Bad Game.mra
Second Bad Game.mra
Third Bad Game.mra"

gbaexclude="First Bad Game.gba
Second Bad Game.gba
Third Bad Game.gba"

genesisexclude="First Bad Game.gen
Second Bad Game.gen
Third Bad Game.gen"

megacdexclude="First Bad Game.chd
Second Bad Game.chd
Third Bad Game.chd"

neogeoexclude="First Bad Game.neo
Second Bad Game.neo
Third Bad Game.neo"

nesexclude="First Bad Game.nes
Second Bad Game.nes
Third Bad Game.nes"

snesexclude="First Bad Game.sfc
Second Bad Game.sfc
Third Bad Game.sfc"

tgfx16exclude="First Bad Game.pce
Second Bad Game.pce
Third Bad Game.pce"

tgfx16cdexclude="First Bad Game.chd
Second Bad Game.chd
Third Bad Game.chd"

# ======== CORE CONFIG ========
function init_data() {
	# Core to long name mappings
	declare -gA CORE_PRETTY=( \
		["arcade"]="MiSTer Arcade" \
		["gba"]="Nintendo Game Boy Advance" \
		["genesis"]="Sega Genesis / Megadrive" \
		["megacd"]="Sega CD / Mega CD" \
		["neogeo"]="SNK NeoGeo" \
		["nes"]="Nintendo Entertainment System" \
		["snes"]="Super Nintendo Entertainment System" \
		["tgfx16"]="NEC TurboGrafx-16 / PC Engine" \
		["tgfx16cd"]="NEC TurboGrafx-16 CD / PC Engine CD" \
		)
	
	# Core to file extension mappings
	declare -gA CORE_EXT=( \
		["arcade"]="mra" \
		["gba"]="gba" \
		["genesis"]="md" \
		["megacd"]="chd" \
		["neogeo"]="neo" \
		["nes"]="nes" \
		["snes"]="sfc" \
		["tgfx16"]="pce" \
		["tgfx16cd"]="chd" \
		)
	
	# Core to path mappings
	declare -gA CORE_PATH=( \
		["arcade"]="${arcadepath}" \
		["gba"]="${gbapath}" \
		["genesis"]="${genesispath}" \
		["megacd"]="${megacdpath}" \
		["neogeo"]="${neogeopath}" \
		["nes"]="${nespath}" \
		["snes"]="${snespath}" \
		["tgfx16"]="${tgfx16path}" \
		["tgfx16cd"]="${tgfx16cdpath}" \
		)
	
	# Can this core use ZIPped ROMs
	declare -gA CORE_ZIPPED=( \
		["arcade"]="No" \
		["gba"]="Yes" \
		["genesis"]="Yes" \
		["megacd"]="No" \
		["neogeo"]="Yes" \
		["nes"]="Yes" \
		["snes"]="Yes" \
		["tgfx16"]="Yes" \
		["tgfx16cd"]="No" \
		)
}

#========= PARSE INI =========
# Read INI
if [ -f "${misterpath}/Scripts/MiSTer_SAM.ini" ]; then
	source "${misterpath}/Scripts/MiSTer_SAM.ini"
fi

# Setup corelist
corelist="$(echo ${corelist} | tr ',' ' ')"

# Create array of coreexclude list names
declare -a coreexcludelist
for core in ${corelist}; do
	coreexcludelist+=( "${core}exclude" )
done

# Iterate through coreexclude lists and make list into array
for excludelist in ${coreexcludelist[@]}; do
	readarray -t ${excludelist} <<<${!excludelist}
done

# Create folder exclude list
fldrex=$(for f in "${folderexclude[@]}"; do echo "-o -iname *$f*" ; done)
	
# Remove trailing slash from paths
for var in mrsampath misterpath mrapathvert mrapathhoriz arcadepath gbapath genesispath megacdpath neogeopath nespath snespath tgfx16path tgfx16cdpath; do
	declare -g ${var}="${!var%/}"
done


#======== SAM MENU ========
function sam_premenu() {
	echo "+---------------------------+"
	echo "| MiSTer Super Attract Mode |"
	echo "+---------------------------+"
	echo " SAM Configuration:"
	if [ -f /etc/init.d/S93mistersam ]; then
		echo " -SAM autoplay ENABLED"
	else
		echo " -SAM autoplay DISABLED"
	fi
	echo " -Start after ${samtimeout} sec. idle"
	echo " -Start only on the menu: ${menuonly^}"
	echo " -Show each game for ${gametimer} sec."
	echo "" 
	echo " Press UP to open menu"
	echo " Press DOWN to start SAM"
	echo ""	
	echo " Or wait for"
	echo " auto-configuration"
	echo ""

	for i in {10..1}; do
		echo -ne " Updating SAM in ${i}...\033[0K\r"
		premenu="Default"
		read -r -s -N 1 -t 1 key
		if [[ "${key}" == "A" ]]; then
			premenu="Menu"
			break
		elif [[ "${key}" == "B" ]]; then
			premenu="Start"
			break
		elif [[ "${key}" == "C" ]]; then
			premenu="Default"
			break
		fi
	done
	parse_cmd ${premenu}
}

function sam_menu() {
	dialog --clear --no-cancel --ascii-lines --no-tags \
	--backtitle "Super Attract Mode" --title "[ Main Menu ]" \
	--menu "Use the arrow keys and enter \nor the d-pad and A button" 0 0 0 \
	Start "Start SAM now" \
	Skip "Skip game (ssh only)" \
	Stop "Stop SAM (ssh only)" \
	Single "Games from only one core" \
	Utility "Update and Monitor" \
	Config "Configure INI Settings" \
	Autoplay "Autoplay Configuration" \
	Cancel "Exit now" 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	clear
	
	if [ "${samquiet,,}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function sam_singlemenu() {
	declare -a menulist=()
	for core in ${corelist}; do
		menulist+=( "${core^^}" )
		menulist+=( "${CORE_PRETTY[${core,,}]} games only" )
	done

	dialog --clear --no-cancel --ascii-lines --no-tags \
	--backtitle "Super Attract Mode" --title "[ Single System Select ]" \
	--menu "Which system?" 0 0 0 \
	"${menulist[@]}" \
	Back 'Previous menu' 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	clear
	
	if [ "${samquiet,,}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function sam_utilitymenu() {
	dialog --clear --no-cancel --ascii-lines --no-tags \
	--backtitle "Super Attract Mode" --title "[ Utilities ]" \
	--menu "Select an option" 0 0 0 \
	Update "Update SAM to latest" \
	Monitor "Display messages (ssh only)" \
	Back 'Previous menu' 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	clear
	
	if [ "${samquiet,,}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function sam_autoplaymenu() {
	dialog --clear --no-cancel --ascii-lines --no-tags \
	--backtitle "Super Attract Mode" --title "[ Configure Autoplay ]" \
	--menu "Select an option" 0 0 0 \
	Enable "Enable Autoplay" \
	Disable "Disable Autoplay" \
	Back 'Previous menu' 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	
	clear
	if [ "${samquiet,,}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function sam_configmenu() {
	dialog --clear --ascii-lines --no-cancel \
	--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
	--msgbox "Here you can configure the INI settings for SAM.\n\nUse TAB to switch between editing, the OK and Cancel buttons." 0 0
	
	dialog --clear --ascii-lines \
	--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
	--editbox "${misterpath}/Scripts/MiSTer_SAM.ini" 0 0 2>"/tmp/.SAMmenu"
	
	if [ -s "/tmp/.SAMmenu" ] && [ "$(diff -wq "/tmp/.SAMmenu" "${misterpath}/Scripts/MiSTer_SAM.ini")" ]; then
		cp -f "/tmp/.SAMmenu" "${misterpath}/Scripts/MiSTer_SAM.ini"
		dialog --clear --ascii-lines --no-cancel \
		--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
		--msgbox "Changes saved!" 0 0
	fi
	
	parse_cmd menu
}

function parse_cmd() {
	if [ ${#} -gt 2 ]; then # We don't accept more than 2 parameters
		sam_help
	elif [ ${#} -eq 0 ]; then # No options - show the pre-menu
		sam_premenu
	else
		# If we're given a core name then we need to set it first
		nextcore=""
		for arg in ${@}; do
			case ${arg,,} in
				arcade | gba | genesis | megacd | neogeo | nes | snes | tgfx16 | tgfx16cd)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				nextcore="${arg}"
				;;
			esac
		done
		
		# If the one command was a core then we need to call in again with "start" specified
		if [ ${nextcore} ] && [ ${#} -eq 1 ]; then
			# Move cursor up a line to avoid duplicate message
			echo -n -e "\033[A"
			# Re-enter this function with start added
			parse_cmd ${nextcore} start
			return
		fi

		while [ ${#} -gt 0 ]; do
			case ${1,,} in
				default) # Default is split because sam_update relaunches itself
					sam_update defaultb
					break
					;;
				defaultb)
					sam_update
					sam_enable quickstart
					sam_start
					break
					;;
				start) # Start SAM immediately
					env_check ${1,,}
					tty_init
					sam_start ${nextcore}
					pre_exit
					break
					;;
				skip | next) # Load next game - doesn't interrupt loop if running
					echo " Skipping to next game..."
					env_check ${1,,}
					tty_init
					next_core ${nextcore}
					break
					;;
				stop) # Stop SAM immediately
					there_can_be_only_one
					echo " Thanks for playing!"
					pre_exit
					break
					;;
				update) # Update SAM
					sam_update
					break
					;;
				enable) # Enable SAM autoplay mode
					env_check ${1,,}
					sam_enable quickstart
					break
					;;
				disable) # Disable SAM autoplay
					sam_disable
					break
					;;
				monitor) # Attach output to terminal
					sam_monitor
					break
					;;
				arcade | gba | genesis | megacd | neogeo | nes | snes | tgfx16 | tgfx16cd)
					: # Placeholder since we parsed these above
					;;
				single)
					sam_singlemenu
					break
					;;
				utility)
					sam_utilitymenu
					break
					;;
				autoplay)
					sam_autoplaymenu
					break
					;;
				config)
					sam_configmenu
					break
					;;
				back)
					sam_menu
					break
					;;
				menu)
					sam_menu
					break
					;;
				cancel) # Exit
					echo " It's pitch dark; You are likely to be eaten by a Grue."
					break
					;;
				help)
					sam_help
					break
					;;
				*)
					echo " ERROR! ${1} is unknown."
					echo " Try $(basename -- ${0}) help"
					echo " Or check the Github readme."
					break
					;;
			esac
			shift
		done
	fi
}


#======== SAM COMMANDS ========
function sam_start() { # sam_start (core)
	# Terminate any other running SAM processes
	there_can_be_only_one
	
	# If the MCP isn't running we need to start it in monitoring only mode
	if [ -z "$(pidof MiSTer_SAM_MCP)" ]; then
		${mrsampath}/MiSTer_SAM_MCP monitoronly &
	fi
	
	# Start SAM looping through cores and games
	loop_core ${1}
}
	
function sam_update() { # sam_update (next command)
	# Ensure the MiSTer SAM data directory exists
	mkdir --parents "${mrsampath}" &>/dev/null
	
	# Prep curl
	curl_check
	
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
				echo " Continuing setup with latest"
				echo " MiSTer_SAM_on.sh..."
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
		cp --force "/tmp/MiSTer_SAM_on.sh" "/media/fat/Scripts/MiSTer_SAM_on.sh"
		get_mbc
		get_partun
		get_samstuff .MiSTer_SAM/MiSTer_SAM_init
		get_samstuff .MiSTer_SAM/MiSTer_SAM_MCP
		get_samstuff .MiSTer_SAM/MiSTer_SAM_joy.py
		get_samstuff .MiSTer_SAM/MiSTer_SAM_keyboard.sh
		get_samstuff .MiSTer_SAM/MiSTer_SAM_mouse.sh
		get_samstuff MiSTer_SAM_off.sh /media/fat/Scripts
		
		if [ -f /media/fat/Scripts/MiSTer_SAM.ini ]; then
			echo " MiSTer SAM INI already exists... SKIPPED!"
		else
			get_samstuff MiSTer_SAM.ini /media/fat/Scripts
		fi
	fi	
	echo " Update complete!"
	return
}

function sam_enable() { # Enable autoplay
	echo -n " Enabling MiSTer SAM Autoplay..."
	# Remount root as read-write if read-only so we can add our daemon
	mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
	[ "$RO_ROOT" == "true" ] && mount / -o remount,rw

	# Awaken daemon
	cp -f "${mrsampath}/MiSTer_SAM_init" /etc/init.d/_S93mistersam &>/dev/null
	mv -f /etc/init.d/_S93mistersam /etc/init.d/S93mistersam &>/dev/null
	chmod +x /etc/init.d/S93mistersam

	# Remove read-write if we were read-only
	sync
	[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	sync
	echo " Done!"

	echo -n " SAM autoplay daemon starting..."

	if [ "${1,,}" == "quickstart" ]; then
		/etc/init.d/S93mistersam quickstart &
	else
		/etc/init.d/S93mistersam start &
	fi

	echo " Done!"
	return
}

function sam_disable() { # Disable autoplay
	echo -n " Disabling SAM autoplay..."
	# Clean out existing processes to ensure we can update
	there_can_be_only_one
	killall -q -9 S93mistersam
	killall -q -9 MiSTer_SAM_MCP
	killall -q -9 MiSTer_SAM_mouse.sh
	killall -q -9 MiSTer_SAM_keyboard.sh
	killall -q -9 xxd
	kill -9 $(ps | grep "inotifywait" | grep "SAM_Joy_Change" | cut --fields=2 --only-delimited --delimiter=' ')

	mount | grep -q "on / .*[(,]ro[,$]" && RO_ROOT="true"
	[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
	rm -f /etc/init.d/S93mistersam > /dev/null 2>&1
	sync
	[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	sync
	echo " Done!"
}

function sam_help() { # sam_help
	echo " start - start immediately"
	echo " skip - skip to the next game"
	echo " stop - stop immediately"
	echo ""
	echo " update - self-update"
	echo " monitor - monitor SAM output"
	echo ""
	echo " enable - enable autoplay"
	echo " disable - disable autoplay"
	echo ""
	echo " menu - load to menu"
	echo ""
	echo " arcade, genesis, gba..."
	echo " games from one system only"
	exit 2
}

#======== UTILITY FUNCTIONS ========
function there_can_be_only_one() { # there_can_be_only_one
	# If another attract process is running kill it
	# This can happen if the script is started multiple times
	echo -n " Stopping other running instances of ${samprocess}..."
	kill -9 $(pidof -o ${sampid} ${samprocess}) &>/dev/null
	wait $(pidof -o ${sampid} ${samprocess}) &>/dev/null
	echo " Done!"
}

function env_check() {
	# Check if we've been installed
	if [ ! -f "${mrsampath}/mbc" ] || [ ! -f "${mrsampath}/partun" ] || [ ! -f "${mrsampath}/MiSTer_SAM_MCP" ]; then
		echo " SAM required files not found."
		echo " Surprised? Check your INI."
		sam_update ${1}
		echo " Setup complete."
	fi
}

function tty_init() { # tty_init
	# tty2oled initialization
	if [ "${ttyenable,,}" == "yes" ]; then
		#echo " Stopping tty2oled daemon..."
		#/etc/init.d/S60tty2oled stop
		#echo " Done!"
		
		echo "CMDCLS" > "${ttydevice}"
		echo "CMDTXT,0,1,0,9, Welcome to..." > "${ttydevice}"
		sleep 0.2
		echo "CMDCLS" > "${ttydevice}"
		echo "CMDTXT,0,1,0,9, Welcome to..." > "${ttydevice}"
		sleep 0.2
		echo "CMDCLS" > "${ttydevice}"
		echo "CMDTXT,0,1,0,9, Welcome to..." > "${ttydevice}"
		sleep 0.2
		echo "CMDTXT,2,1,47,27,  Super" > "${ttydevice}"
		sleep 0.2
		echo "CMDTXT,2,1,47,45,      Attract" > "${ttydevice}"
		sleep 0.2
		echo "CMDTXT,2,1,47,61,          Mode!" > "${ttydevice}"
	fi
}

function tty_update() { # tty_update core game
	if [ "${ttyenable,,}" == "yes" ]; then
		# Wait for tty2oled daemon to show the core logo
		inotifywait -e modify /tmp/CORENAME
		sleep 10
		
		# Transition effect
		echo "CMDGEO,8,1,126,30,31,15,0" > "${ttydevice}"
		sleep 0.2                                        
		echo "CMDGEO,8,1,126,30,63,31,0" > "${ttydevice}"
		sleep 0.2                                        
		echo "CMDGEO,8,1,126,30,127,63,0" > "${ttydevice}"
		sleep 0.2                                        
		echo "CMDGEO,8,1,126,30,255,127,0" > "${ttydevice}"
		sleep 0.2
		echo "CMDGEO,8,0,126,30,31,15,0" > "${ttydevice}"
		sleep 0.2                                        
		echo "CMDGEO,8,0,126,30,63,31,0" > "${ttydevice}"
		sleep 0.2                                        
		echo "CMDGEO,8,0,126,30,127,63,0" > "${ttydevice}"
		sleep 0.2                                        
		echo "CMDGEO,8,0,126,30,255,127,0" > "${ttydevice}"
		sleep 0.2                                        
		
		# Split long lines - length is approximate since fonts are variable width!
		if [ ${#2} -gt 23 ]; then
			echo "CMDTXT,2,1,0,20,${2:0:20}..." > "${ttydevice}"
			echo "CMDTXT,2,1,0,40, ${2:20}" > "${ttydevice}"
		else
			echo "CMDTXT,2,1,0,20,${2}" > "${ttydevice}"
		fi
		echo "CMDTXT,1,1,0,60,on ${1}" > "${ttydevice}"
	fi
}

function pre_exit() { # pre_exit
	#if [ "${usetty,,}" == "yes" ]; then /etc/init.d/S60tty2oled start; fi
	echo
}
	

#======== DOWNLOAD FUNCTIONS ========
function curl_check() {
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

function curl_download() { # curl_download ${filepath} ${URL}
		curl \
			--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
			${SSL_SECURITY_OPTION} \
			--fail \
			--location \
			-o "${1}" \
			"${2}"
}


#======== UPDATER FUNCTIONS ========
function get_samstuff() { #get_samstuff file (path)
	if [ -z "${1}" ]; then
		return 1
	fi
	
	filepath="${2}"
	if [ -z "${filepath}" ]; then
		filepath="${mrsampath}"
	fi

	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_SAM"
		echo -n " Downloading from ${REPOSITORY_URL}/blob/${branch}/${1} to ${filepath}/..."
	curl_download "/tmp/${1##*/}" "${REPOSITORY_URL}/blob/${branch}/${1}?raw=true"

	if [ ! "${filepath}" == "/tmp" ]; then
		mv --force "/tmp/${1##*/}" "${filepath}/${1##*/}"
	fi

	if [ "${1##*.}" == "sh" ]; then
		chmod +x "${filepath}/${1##*/}"
	fi
	
	echo " Done!"
}

function get_mbc() {
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_Batch_Control"
	echo " Downloading mbc - a tool needed for launching roms..."
	echo " Created for MiSTer by pocomane"
	echo " ${REPOSITORY_URL}"
	curl_download "/tmp/mbc" "${REPOSITORY_URL}/${mbcurl}?raw=true"
	mv --force "/tmp/mbc" "${mrsampath}/mbc"
	echo " Done!"
}

function get_partun() {
  REPOSITORY_URL="https://github.com/woelper/partun"
  echo " Downloading partun - needed for unzipping roms from big archives..."
  echo " Created for MiSTer by woelper - who is allegedly not a spider"
  echo " ${REPOSITORY_URL}"
  latest=$(curl -s -L --insecure https://api.github.com/repos/woelper/partun/releases/latest | jq -r ".assets[] | select(.name | contains(\"armv7\")) | .browser_download_url")
  curl_download "/tmp/partun" "${latest}"
 	mv --force "/tmp/partun" "${mrsampath}/partun"
	echo " Done!"
}


#========= SAM MONITOR =========
function sam_monitor() {
	
	PID=$(ps aux |grep MiSTer_SAM_on.sh |grep -v grep |awk '{print $1}' | head -n 1)

	if [ $PID ]; then
		echo -n " Attaching MiSTer SAM to current shell..."
		THIS=$0
		ARGS=$@
		name=$(basename $THIS)
		quiet="no"
		nopt=""
		shift $((OPTIND-1))
		fds=""
		
		if [ -n "$nopt" ]; then
			for n_f in $nopt; do
			n=${n_f%%:*}
			f=${n_f##*:}
			if [ -n "${n//[0-9]/}" ] || [ -z "$f" ]; then 
				warn "Error parsing descriptor (-n $n_f)"
				exit 1
			fi

			if ! 2>/dev/null : >> $f; then
				warn "Cannot write to (-n $n_f) $f"
				exit 1
			fi
			fds="$fds $n"
			fns[$n]=$f
			done
		fi
		
		if [ -z "$stdout" ] && [ -z "$stderr" ] && [ -z "$stdin" ] && [ -z "$nopt" ]; then
			#second invocation form: dup to my own in/err/out
			[ -e /proc/$$/fd/0 ] &&  stdin=$(readlink /proc/$$/fd/0)
			[ -e /proc/$$/fd/1 ] && stdout=$(readlink /proc/$$/fd/1)
			[ -e /proc/$$/fd/2 ] && stderr=$(readlink /proc/$$/fd/2)
			if [ -z "$stdout" ] && [ -z "$stderr" ] && [ -z "$stdin" ]; then
			warn "Could not determine current standard in/out/err"
			exit 1
			fi
		fi
		
	
		gdb_cmds() {
			local _name=$1
			local _mode=$2
			local _desc=$3
			local _msgs=$4
			local _len
	
			[ -w "/proc/$PID/fd/$_desc" ] || _msgs=""
			if [ -d "/proc/$PID/fd" ] && ! [ -e "/proc/$PID/fd/$_desc" ]; then
			warn "Attempting to remap non-existent fd $n of PID ($PID)"
			fi
	
			[ -z "$_name" ] && return
	
			echo "set \$fd=open(\"$_name\", $_mode)"
			echo "set \$xd=dup($_desc)"
			echo "call dup2(\$fd, $_desc)"
			echo "call close(\$fd)"

			if  [ $((_mode & 3)) ] && [ -n "$_msgs" ]; then
				_len=$(echo -en "$_msgs" | wc -c)
				echo "call write(\$xd, \"$_msgs\", $_len)"
			fi

			echo "call close(\$xd)"
		}
	
		trap '/bin/rm -f $GDBCMD' EXIT
		GDBCMD=$(mktemp /tmp/gdbcmd.XXXX)
		{
			#Linux file flags (from /usr/include/bits/fcntl.sh)
			O_RDONLY=00
			O_WRONLY=01
			O_RDWR=02 
			O_CREAT=0100
			O_APPEND=02000
			echo "#gdb script generated by running '$0 $ARGS'"
			echo "attach $PID"
			gdb_cmds "$stdin"  $((O_RDONLY)) 0 "$msg_stdin"
			gdb_cmds "$stdout" $((O_WRONLY|O_CREAT|O_APPEND)) 1 "$msg_stdout"
			gdb_cmds "$stderr" $((O_WRONLY|O_CREAT|O_APPEND)) 2 "$msg_stderr"

			for n in $fds; do
				msg="Descriptor $n of $PID is remapped to ${fns[$n]}\n"
				gdb_cmds ${fns[$n]} $((O_RDWR|O_CREAT|O_APPEND)) $n "$msg"
			done
			#echo "quit"
		} > $GDBCMD
	
		if gdb -batch -n -x $GDBCMD >/dev/null </dev/null; then
			[ "$quiet" != "yes" ] && echo " Done!" >&2
		else
			warn " Failed!"
		fi
		
		#cp $GDBCMD /tmp/gdbcmd
		rm -f $GDBCMD
	else
		echo " Couldn't detect MiSTer_SAM_on.sh running"
	fi
}


# ======== SAM OPERATIONAL FUNCTIONS ========
function loop_core() { # loop_core (core)
	echo " Let Mortal Kombat begin!"
	# Reset game log for this session
	echo "" |> /tmp/SAM_Games.log
	
	while :; do
		counter=${gametimer}

		next_core ${1}
		while [ ${counter} -gt 0 ]; do
			echo -ne " Next game in ${counter}...\033[0K\r"
			sleep 1
			((counter--))
			
			if [ -s /tmp/.SAM_Mouse_Activity ]; then
				if [ "${listenmouse,,}" == "yes" ]; then
					echo " Mouse activity detected!"
					exit
				else
					echo " Mouse activity ignored!"
					echo "" |>/tmp/.SAM_Mouse_Activity
				fi
			fi
			
			if [ -s /tmp/.SAM_Keyboard_Activity ]; then
				if [ "${listenkeyboard,,}" == "yes" ]; then
					echo " Keyboard activity detected!"
					exit
				else
					echo " Keyboard activity ignored!"
					echo "" |>/tmp/.SAM_Keyboard_Activity
				fi
			fi
			
			if [ -s /tmp/.SAM_Joy_Activity ]; then
				if [ "${listenjoy,,}" == "yes" ]; then
					echo " Controller activity detected!"
					exit
				else
					echo " Controller activity ignored!"
					echo "" |>/tmp/.SAM_Joy_Activity
				fi
			fi
		done
	done
}

function next_core() { # next_core (core)
	if [ -z "${corelist[@]//[[:blank:]]/}" ]; then
		echo " ERROR: FATAL - List of cores is empty. Nothing to do!"
		exit 1
	fi

	if [ -z "${1}" ]; then
		nextcore="$(echo ${corelist}| xargs shuf --head-count=1 --random-source=/dev/urandom --echo)"
	elif [ "${1,,}" == "countdown" ] && [ "$2" ]; then
		countdown="countdown"
		nextcore="${2}"
	elif [ "${2,,}" == "countdown" ]; then
		nextcore="${1}"
		countdown="countdown"
	fi

	if [ "${nextcore,,}" == "arcade" ]; then
		# If this is an arcade core we go to special code
		load_core_arcade
		return
	fi

	# Core doesn't use zips - get on with it
	if [ "${CORE_ZIPPED[${nextcore,,}],,}" == "no" ]; then
		if [ "${samquiet,,}" == "no" ]; then echo " ${nextcore,,} does not use ZIPs."; fi
		rompath="$(find ${CORE_PATH[${nextcore,,}]} -type d \( -iname *BIOS* ${fldrex} \) -prune -false -o -type f -iname "*.${CORE_EXT[${nextcore,,}]}" | shuf --head-count=1 --random-source=/dev/urandom)"
		romname=$(basename "${rompath}")
	
	# We might be using ZIPs
	else
		# Check how many ZIP and ROM files in core path	
		zipcount=$(find ${CORE_PATH[${nextcore,,}]} -maxdepth 1 -type f -iname "*.zip" -print | wc -l)
		if [ "${samquiet,,}" == "no" ]; then echo " Found ${zipcount} zip files in ${CORE_PATH[${nextcore,,}]}."; fi
		romcount=$(find ${CORE_PATH[${nextcore,,}]} -type d \( -iname *BIOS* ${fldrex} \) -prune -false -o -type f -iname "*.${CORE_EXT[${nextcore,,}]}" -print | wc -l)
		if [ "${samquiet,,}" == "no" ]; then echo " Found ${romcount} ${CORE_EXT[${nextcore,,}]} files in ${CORE_PATH[${nextcore,,}]}."; fi

		if [ ${zipcount} -gt 0 ] && [ ${romcount} -gt 0 ] && [ "${usezip,,}" == "yes" ]; then
			# We've found ZIPs AND ROMs AND we're using zips
			if [ "${samquiet,,}" == "no" ]; then echo " Both ROMs and ZIPs found!"; fi

			# We found at least one large ZIP file - use it
			if [ $(find ${CORE_PATH[${nextcore,,}]} -maxdepth 1 -xdev -type f -size +500M \( -iname "*.zip" \) -print | wc -l) -gt 0 ]; then
				if [ "${samquiet,,}" == "no" ]; then echo " Using 500MB+ ZIP(s)."; fi
				romname=$("${mrsampath}/partun" "$(find ${CORE_PATH[${nextcore,,}]} -xdev -maxdepth 1 -size +500M -type f -iname "*.zip" | shuf --head-count=1 --random-source=/dev/urandom)" -i -r -f ${CORE_EXT[${nextcore,,}]} --rename /tmp/Extracted.${CORE_EXT[${nextcore,,}]})
				# Partun returns the actual rom name to us so we need a special case here
				romname=$(basename "${romname}")
				rompath="/tmp/Extracted.${CORE_EXT[${nextcore,,}]}"

			# We see more zip files than ROMs - individually zipped roms?
			elif [ ${zipcount} -gt ${romcount} ]; then
				if [ "${samquiet,,}" == "no" ]; then echo " Fewer ROMs - using ZIPs."; fi
				romname=$("${mrsampath}/partun" "$(find ${CORE_PATH[${nextcore,,}]} -maxdepth 1 -type f -iname "*.zip" | shuf --head-count=1 --random-source=/dev/urandom)" -i -r -f ${CORE_EXT[${nextcore,,}]} --rename /tmp/Extracted.${CORE_EXT[${nextcore,,}]})
				# Partun returns the actual rom name to us so we need a special case here
				romname=$(basename "${romname}")
				rompath="/tmp/Extracted.${CORE_EXT[${nextcore,,}]}"
				
			# I guess we use the ROMs!
			else
				if [ "${samquiet,,}" == "no" ]; then echo " Using ROMs."; fi
				rompath="$(find ${CORE_PATH[${nextcore,,}]} -type d \( -iname *BIOS* ${fldrex} \) -prune -false -o -iname "*.${CORE_EXT[${nextcore,,}]}" | shuf --head-count=1 --random-source=/dev/urandom)"
				romname=$(basename "${rompath}")
			fi

		# Found no ZIPs or we're ignoring them
		elif [ -z "$(find ${CORE_PATH[${nextcore,,}]} -maxdepth 1 -type f \( -iname "*.zip" \))" ] || [ "${usezip,,}" == "no" ]; then
			rompath="$(find ${CORE_PATH[${nextcore,,}]} -type d \( -iname *BIOS* ${fldrex} \) -prune -false -o -iname "*.${CORE_EXT[${nextcore,,}]}" | shuf --head-count=1 --random-source=/dev/urandom)"
			romname=$(basename "${rompath}")

		# Use the ZIP Luke!
		else
			romname=$("${mrsampath}/partun" "$(find ${CORE_PATH[${nextcore,,}]} -maxdepth 1 -type f -iname "*.zip" | shuf --head-count=1 --random-source=/dev/urandom)" -i -r -f ${CORE_EXT[${nextcore,,}]} --rename /tmp/Extracted.${CORE_EXT[${nextcore,,}]})
			# Partun returns the actual rom name to us so we need a special case here
			romname=$(basename "${romname}")
			rompath="/tmp/Extracted.${CORE_EXT[${nextcore,,}]}"
		fi
	fi

	# If there is an exclude list check it
	declare -n excludelist="${nextcore,,}exclude"
	if [ ${#excludelist[@]} -gt 0 ]; then
		for excluded in "${excludelist[@]}"; do
			if [ "${romname}" == "${excluded}" ]; then
				echo " ${romname} is excluded - SKIPPED"
				next_core
				return
			fi
		done
	fi

	if [ -z "${rompath}" ]; then
		core_error "${nextcore}" "${rompath}"
	else
		if [ -f "${rompath}.sam" ]; then
			source "${rompath}.sam"
		fi
		
		declare -g romloadfails=0
		load_core "${nextcore}" "${rompath}" "${romname%.*}" "${countdown}"
	fi
}

function load_core() { # load_core core /path/to/rom name_of_rom (countdown)
	echo -n " Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${1,,}]}\e[0m: "
	echo -e "\e[1m${3}\e[0m"
	echo "$(date +%H:%M:%S) - ${1} - ${3}" >> /tmp/SAM_Games.log
	echo "${3} (${1})" > /tmp/SAM_Game.txt
	tty_update "${CORE_PRETTY[${1,,}]}" "${3}" &

	if [ "${4}" == "countdown" ]; then
		for i in {5..1}; do
			echo -ne " Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi

	"${mrsampath}/mbc" load_rom ${1^^} "${2}" > /dev/null 2>&1
	sleep 1
	echo "" |>/tmp/.SAM_Joy_Activity
	echo "" |>/tmp/.SAM_Mouse_Activity
	echo "" |>/tmp/.SAM_Keyboard_Activity
}

function core_error() { # core_error core /path/to/ROM
	if [ ${romloadfails} -lt ${coreretries} ]; then
		declare -g romloadfails=$((romloadfails+1))
		echo " ERROR: Failed ${romloadfails} times. No valid game found for core: ${1} rom: ${2}"
		echo " Trying to find another rom..."
		next_core ${1}
	else
		echo " ERROR: Failed ${romloadfails} times. No valid game found for core: ${1} rom: ${2}"
		echo " ERROR: Core ${1} is blacklisted!"
		declare -g corelist=("${corelist[@]/${1}}")
		echo " List of cores is now: ${corelist[@]}"
		declare -g romloadfails=0
		next_core
	fi	
}

function disable_bootrom() {
	if [ "${disablebootrom}" == "Yes" ]; then
		if [ -d "${misterpath}/Bootrom" ]; then
			mount --bind /mnt "${misterpath}/Bootrom"
		fi
		if [ -f "${misterpath}/Games/NES/boot0.rom" ]; then
			touch /tmp/brfake
			mount --bind /tmp/brfake ${misterpath}/Games/NES/boot0.rom
		fi
		if [ -f "${misterpath}/Games/NES/boot1.rom" ]; then
			touch /tmp/brfake
			mount --bind /tmp/brfake ${misterpath}/Games/NES/boot1.rom
		fi
	fi
}


# ======== ARCADE MODE ========
function build_mralist() {
	# If no MRAs found - suicide!
	find "${arcadepath}" -maxdepth 1 -type f \( -iname "*.mra" \) &>/dev/null
	if [ ! ${?} == 0 ]; then
		echo " The path ${arcadepath} contains no MRA files!"
		loop_core
	fi

	# Check if the MRA list already exists - if so, leave it alone
	if [ -f ${mralist} ]; then
		return
	fi
	
	# This prints the list of MRA files in a path,
	# Cuts the string to just the file name,
	# Then saves it to the mralist file.
	
	# If there is an empty exclude list ignore it
	# Otherwise use it to filter the list
	if [ ${#arcadeexclude[@]} -eq 0 ]; then
		find "${arcadepath}" -maxdepth 1 -type f \( -iname "*.mra" \) | cut -c $(( $(echo ${#arcadepath}) + 2 ))- >"${mralist}"
	else
		find "${arcadepath}" -maxdepth 1 -type f \( -iname "*.mra" \) | cut -c $(( $(echo ${#arcadepath}) + 2 ))- | grep -vFf <(printf '%s\n' ${arcadeexclude[@]})>"${mralist}"
	fi
}

function load_core_arcade() {
	# Get a random game from the list
	mra="$(shuf --head-count=1 --random-source=/dev/urandom ${mralist})"

	# If the mra variable is valid this is skipped, but if not we try 10 times
	# Partially protects against typos from manual editing and strange character parsing problems
	for i in {1..10}; do
		if [ ! -f "${arcadepath}/${mra}" ]; then
			mra=$(shuf --head-count=1 --random-source=/dev/urandom ${mralist})
		fi
	done

	# If the MRA is still not valid something is wrong - suicide
	if [ ! -f "${arcadepath}/${mra}" ]; then
		echo " There is no valid file at ${arcadepath}/${mra}!"
		return
	fi

	mraname="$(echo "$(basename "${mra}")" | sed -e 's/\.[^.]*$//')"
	echo -n " Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore,,}]}\e[0m: "
	echo -e "\e[1m${mraname}\e[0m"
	echo "$(date +%H:%M:%S) - Arcade - ${mraname}" >> /tmp/SAM_Games.log
	echo "${mraname} (${nextcore})" > /tmp/SAM_Game.txt
	tty_update "${CORE_PRETTY[${nextcore,,}]}" "${mraname}"

	if [ "${1}" == "countdown" ]; then
		for i in {5..1}; do
			echo " Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi

  # Tell MiSTer to load the next MRA
  echo "load_core ${arcadepath}/${mra}" > /dev/MiSTer_cmd
 	sleep 1
	echo "" |>/tmp/.SAM_Joy_Activity
	echo "" |>/tmp/.SAM_Mouse_Activity
	echo "" |>/tmp/.SAM_Keyboard_Activity
}


#========= MAIN =========
#======== DEBUG OUTPUT =========
if [ "${samtrace,,}" == "yes" ]; then
	echo " ********************************************************************************"
	#======== GLOBAL VARIABLES =========
	echo " mrsampath: ${mrsampath}"
	echo " misterpath: ${misterpath}"
	echo " sampid: ${sampid}"
	echo " samprocess: ${samprocess}"
	echo ""
	#======== LOCAL VARIABLES ========
	echo " commandline: ${@}"
	echo " branch: ${branch}"
	echo " mbcurl: ${mbcurl}"
	echo ""
	echo " gametimer: ${gametimer}"
	echo " corelist: ${corelist}"
	echo " usezip: ${usezip}"
	echo " disablebootrom: ${disablebootrom}"
	echo " mralist: ${mralist}"
	echo " listenmouse: ${listenmouse}"
	echo " listenkeyboard: ${listenkeyboard}"
	echo " listenjoy: ${listenjoy}"
	echo ""
	echo " arcadepath: ${arcadepath}"
	echo " gbapath: ${gbapath}"
	echo " genesispath: ${genesispath}"
	echo " megacdpath: ${megacdpath}"
	echo " neogeopath: ${neogeopath}"
	echo " nespath: ${nespath}"
	echo " snespath: ${snespath}"
	echo " tgfx16path: ${tgfx16path}"
	echo " tgfx16cdpath: ${tgfx16cdpath}"
  echo ""
	echo " arcadeexclude: ${arcadeexclude[@]}"
	echo " gbaexclude: ${gbaexclude[@]}"
	echo " genesisexclude: ${genesisexclude[@]}"
	echo " megacdexclude: ${megacdexclude[@]}"
	echo " neogeoexclude: ${neogeoexclude[@]}"
	echo " nesexclude: ${nesexclude[@]}"
	echo " snesexclude: ${snesexclude[@]}"
	echo " tgfx16exclude: ${tgfx16exclude[@]}"
	echo " tgfx16cdexclude: ${tgfx16cdexclude[@]}"
	echo " ********************************************************************************"
	read -p " Continuing in 5 seconds or press any key..." -n 1 -t 5 -r -s
fi	

disable_bootrom	# Disable Bootrom until Reboot 
build_mralist		# Generate list of MRAs
init_data				# Setup data arrays
parse_cmd ${@}	# Parse command line parameters for input
pre_exit				# Shutdown routine	
exit
