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
# Original concept and implementation: mrchrisster
# Additional development and script layout: Mellified
#
# Thanks for the contributions and support:
# pocomane, kaloun34, redsteakraw, RetroDriven, woelper, LamerDeluxe, InquisitiveCoder, Sigismond, venice


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
mralist="/tmp/.SAMlist/arcade_romlist"
gametimer=120
corelist="arcade,fds,gba,genesis,gg,megacd,neogeo,nes,sms,snes,tgfx16,tgfx16cd,psx"
skipmessage="Yes"
usezip="Yes"
norepeat="Yes"
disablebootrom="Yes"
mute="Yes"					
listenmouse="Yes"
listenkeyboard="Yes"
listenjoy="Yes"
repository_url="https://github.com/mrchrisster/MiSTer_SAM"
branch="main"
counter=0
userstartup="/media/fat/linux/user-startup.sh"
userstartuptpl="/media/fat/linux/_user-startup.sh"


# ======== TTY2OLED =======
ttyenable="No"
ttydevice="/dev/ttyUSB0"
ttypicture="/media/fat/tty2oled/pics"
ttypicture_pri="/media/fat/tty2oled/pics_pri"

#======== CORE PATHS ========
arcadepath="/media/fat/_arcade"
fdspath="/media/fat/games/NES"
gbapath="/media/fat/games/GBA"
genesispath="/media/fat/games/Genesis"
ggpath="/media/fat/Games/SMS"
megacdpath="/media/fat/games/MegaCD"
neogeopath="/media/fat/games/NeoGeo"
nespath="/media/fat/games/NES"
smspath="/media/fat/Games/SMS"
snespath="/media/fat/games/SNES"
tgfx16path="/media/fat/games/TGFX16"
tgfx16cdpath="/media/fat/games/TGFX16-CD"
psxpath="/media/fat/games/PSX"

# ======== CONSOLE WHITELISTS ========
fdswhitelist="/media/fat/Scripts/SAM_whitelist_fds.txt"
gbawhitelist="/media/fat/Scripts/SAM_whitelist_gba.txt"
genesiswhitelist="/media/fat/Scripts/SAM_whitelist_genesis.txt"
ggwhitelist="/media/fat/Scripts/SAM_whitelist_gg.txt"
megacdwhitelist="/media/fat/Scripts/SAM_whitelist_megacd.txt"
neogeowhitelist="/media/fat/Scripts/SAM_whitelist_neogeo.txt"
neswhitelist="/media/fat/Scripts/SAM_whitelist_nes.txt"
smswhitelist="/media/fat/Scripts/SAM_whitelist_sms.txt"
sneswhitelist="/media/fat/Scripts/SAM_whitelist_snes.txt"
tgfx16whitelist="/media/fat/Scripts/SAM_whitelist_tgfx16.txt"
tgfx16cdwhitelist="/media/fat/Scripts/SAM_whitelist_tgfx16cd.txt"
psxwhitelist="/media/fat/Scripts/SAM_whitelist_psx.txt"

#======== EXCLUDE LISTS ========
arcadeexclude="First Bad Game.mra
Second Bad Game.mra
Third Bad Game.mra"

fdsexclude="First Bad Game.gba
Second Bad Game.gba
Third Bad Game.gba"

gbaexclude="First Bad Game.gba
Second Bad Game.gba
Third Bad Game.gba"

genesisexclude="First Bad Game.md
Second Bad Game.md
Third Bad Game.md"

ggexclude="First Bad Game.gg
Second Bad Game.gg
Third Bad Game.gg"

megacdexclude="First Bad Game.chd
Second Bad Game.chd
Third Bad Game.chd"

neogeoexclude="First Bad Game.neo
Second Bad Game.neo
Third Bad Game.neo"

nesexclude="First Bad Game.nes
Second Bad Game.nes
Third Bad Game.nes"

smsexclude="First Bad Game.sms
Second Bad Game.sms
Third Bad Game.sms"

snesexclude="First Bad Game.sfc
Second Bad Game.sfc
Third Bad Game.sfc"

tgfx16exclude="First Bad Game.pce
Second Bad Game.pce
Third Bad Game.pce"

tgfx16cdexclude="First Bad Game.chd
Second Bad Game.chd
Third Bad Game.chd"

psxexclude="First Bad Game.chd
Second Bad Game.chd
Third Bad Game.chd"

# ======== CORE CONFIG ========
function init_data() {
	# Core to long name mappings
	declare -gA CORE_PRETTY=( \
		["arcade"]="MiSTer Arcade" \
		["fds"]="Nintendo Disk System" \
		["gba"]="Nintendo Game Boy Advance" \
		["genesis"]="Sega Genesis / Megadrive" \
		["gg"]="Sega Game Gear" \
		["megacd"]="Sega CD / Mega CD" \
		["neogeo"]="SNK NeoGeo" \
		["nes"]="Nintendo Entertainment System" \
		["sms"]="Sega Master System" \
		["snes"]="Super Nintendo Entertainment System" \
		["tgfx16"]="NEC TurboGrafx-16 / PC Engine" \
		["tgfx16cd"]="NEC TurboGrafx-16 CD / PC Engine CD" \
		["psx"]="Sony Playstation" \
		)
	
	# Core to file extension mappings
	declare -gA CORE_EXT=( \
		["arcade"]="mra" \
		["fds"]="fds" \
		["gba"]="gba" \
		["genesis"]="md" \
		["gg"]="gg" \
		["megacd"]="chd" \
		["neogeo"]="neo" \
		["nes"]="nes" \
		["sms"]="sms" \
		["snes"]="sfc" \
		["tgfx16"]="pce" \
		["tgfx16cd"]="chd" \
		["psx"]="chd" \
		)
	
	# Core to path mappings
	declare -gA CORE_PATH=( \
		["arcade"]="${arcadepath}" \
		["fds"]="${fdspath}" \
		["gba"]="${gbapath}" \
		["genesis"]="${genesispath}" \
		["gg"]="${ggpath}" \
		["megacd"]="${megacdpath}" \
		["neogeo"]="${neogeopath}" \
		["nes"]="${nespath}" \
		["sms"]="${smspath}" \
		["snes"]="${snespath}" \
		["tgfx16"]="${tgfx16path}" \
		["tgfx16cd"]="${tgfx16cdpath}" \
		["psx"]="${psxpath}" \
		)
	
	# Can this core use ZIPped ROMs
	declare -gA CORE_ZIPPED=( \
		["arcade"]="No" \
		["fds"]="Yes" \
		["gba"]="Yes" \
		["genesis"]="Yes" \
		["gg"]="Yes" \
		["megacd"]="No" \
		["neogeo"]="Yes" \
		["nes"]="Yes" \
		["sms"]="Yes" \
		["snes"]="Yes" \
		["tgfx16"]="Yes" \
		["tgfx16cd"]="No" \
		["psx"]="No" \
		)
		
	# Can this core skip Bios/Safety warning messages
	declare -gA CORE_SKIP=( \
		["arcade"]="No" \
		["fds"]="Yes" \
		["gba"]="No" \
		["genesis"]="No" \
		["gg"]="No" \
		["megacd"]="Yes" \
		["neogeo"]="No" \
		["nes"]="No" \
		["sms"]="No" \
		["snes"]="No" \
		["tgfx16"]="No" \
		["tgfx16cd"]="Yes" \
		["psx"]="No" \
		)

	# Core to folder mapping
	declare -gA CORE_LAUNCH=( \
		["arcade"]="arcade" \
		["fds"]="nes" \
		["gba"]="gba" \
		["genesis"]="genesis" \
		["gg"]="sms" \
		["megacd"]="megacd" \
		["neogeo"]="neogeo" \
		["nes"]="nes" \
		["sms"]="sms" \
		["snes"]="snes" \
		["tgfx16"]="tgfx16" \
		["tgfx16cd"]="tgfx16" \
		["psx"]="psx" \
		)
		
	# MGL core name settings
	declare -gA MGL_CORE=( \
		["arcade"]="arcade" \
		["fds"]="nes" \
		["gba"]="gba" \
		["genesis"]="genesis" \
		["gg"]="gg" \
		["megacd"]="megacd" \
		["neogeo"]="neogeo" \
		["nes"]="nes" \
		["sms"]="sms" \
		["snes"]="snes" \
		["tgfx16"]="turbografx16" \
		["tgfx16cd"]="turbografx16" \
		["psx"]="psx" \
		)	
	
	# MGL delay settings
	declare -gA MGL_DELAY=( \
		["arcade"]="2" \
		["fds"]="2" \
		["gba"]="2" \
		["genesis"]="1" \
		["gg"]="1" \
		["megacd"]="1" \
		["neogeo"]="1" \
		["nes"]="2" \
		["sms"]="1" \
		["snes"]="2" \
		["tgfx16"]="1" \
		["tgfx16cd"]="1" \
		["psx"]="1" \
		)	
		
	# MGL index settings
	declare -gA MGL_INDEX=( \
		["arcade"]="0" \
		["fds"]="0" \
		["gba"]="0" \
		["genesis"]="0" \
		["gg"]="2" \
		["megacd"]="0" \
		["neogeo"]="1" \
		["nes"]="0" \
		["sms"]="1" \
		["snes"]="0" \
		["tgfx16"]="0" \
		["tgfx16cd"]="0" \
		["psx"]="1" \
		)	
		
	# MGL type settings
	declare -gA MGL_TYPE=( \
		["arcade"]="f" \
		["fds"]="f" \
		["gba"]="f" \
		["genesis"]="f" \
		["gg"]="f" \
		["megacd"]="s" \
		["neogeo"]="f" \
		["nes"]="f" \
		["sms"]="f" \
		["snes"]="f" \
		["tgfx16"]="f" \
		["tgfx16cd"]="s" \
		["psx"]="s" \
		)	
		
}

#========= PARSE INI =========
# Read INI
if [ -f "${misterpath}/Scripts/MiSTer_SAM.ini" ]; then
	source "${misterpath}/Scripts/MiSTer_SAM.ini"
	# Remove trailing slash from paths
	for var in $(grep "^[^#;]" "${misterpath}/Scripts/MiSTer_SAM.ini" | grep "path=" | cut -f1 -d"="); do
		declare -g ${var}="${!var%/}"
	done
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
# Create folder exclude list for zips
fldrexzip=$(printf "%s," "${folderexclude[@]}" && echo "")
	



#======== SAM MENU ========
function sam_premenu() {
	echo "+---------------------------+"
	echo "| MiSTer Super Attract Mode |"
	echo "+---------------------------+"
	echo " SAM Configuration:"
	if [ $(grep -c "mistersam" ${userstartup}) = "0" ]; then
		echo " -SAM autoplay DISABLED"
	else
		echo " -SAM autoplay ENABLED"
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

	for i in {5..1}; do
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
	Skip "Skip game" \
	Stop "Stop SAM" \
	Single "Games from only one core" \
	Favorite "Favorite Game. Copy current game to _Favorites folder" \
	Utility "Update and Monitor" \
	Config "Configure INI Settings" \
	Reset "Reset or uninstall SAM" \
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

function sam_resetmenu() {
	dialog --clear --no-cancel --ascii-lines --no-tags \
	--backtitle "Super Attract Mode" --title "[ Reset ]" \
	--menu "Select an option" 0 0 0 \
	Deleteall "Reset/Delete all files" \
	Default "Reinstall SAM and enable Autostart" \
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
				arcade | fds | gba | genesis | gg | megacd | neogeo | nes | sms | snes | tgfx16 | tgfx16cd | psx)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				nextcore="${arg,,}"
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
					sam_update autoconfig
					break
					;;
				autoconfig)
					sam_update
					mcp_start
					sam_enable start
					break
					;;
				softstart) # Start as from init
					env_check ${1,,}
					mcp_start
					echo " Starting SAM in the background."
					tmux new-session -x 180 -y 40 -n "-= SAM Monitor -- Detach with ctrl-b d  =-" -s SAM -d ${misterpath}/Scripts/MiSTer_SAM_on.sh softstart_real
					break
					;;
				start) # Start as a detached tmux session for monitoring
					env_check ${1,,}
					# Terminate any other running SAM processes
					there_can_be_only_one
					mcp_start
					echo "Starting SAM in the background."
					tmux new-session -x 180 -y 40 -n "-= SAM Monitor -- Detach with ctrl-b d  =-" -s SAM -d  ${misterpath}/Scripts/MiSTer_SAM_on.sh start_real ${nextcore}
					break
					;;
				start_real) # Start SAM immediately
					env_check ${1,,}
					tty_init					
					loop_core ${nextcore}					
					break
					;;
				softstart_real) # Start SAM immediately
					env_check ${1,,}
					tty_init
					counter=${samtimeout}
					loop_core ${nextcore}
					break
					;;
				skip | next) # Load next game - stops monitor
					echo " Skipping to next game..."
					tmux send-keys -t SAM C-c ENTER
					#break
					;;
				stop) # Stop SAM immediately
					there_can_be_only_one
					tty_exit
					unmute
					echo " Thanks for playing!" 
					break
					;;
				update) # Update SAM
					sam_update
					break
					;;
				enable) # Enable SAM autoplay mode
					env_check ${1,,}
					sam_enable start
					break
					;;
				disable) # Disable SAM autoplay
					sam_disable
					break
					;;
				monitor) # Warn user of changes
					sam_monitor_new
					break
					;;
				arcade | fds | gba | genesis | gg | megacd | neogeo | nes | sms | snes | tgfx16 | tgfx16cd | psx)
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
				favorite)
					mglfavorite
					break
					;;
				reset)
					sam_resetmenu
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
				deleteall)
					deleteall
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
function mcp_start() {
	
	# If the MCP isn't running we need to start it in monitoring only mode
	if [ -z "$(pidof MiSTer_SAM_MCP)" ]; then
		#${mrsampath}/MiSTer_SAM_MCP monitoronly &
		${mrsampath}/MiSTer_SAM_MCP &
	fi
	
}
	
function sam_update() { # sam_update (next command)
	# Ensure the MiSTer SAM data directory exists
	mkdir --parents "${mrsampath}" &>/dev/null
	mkdir --parents "${mrsampath}"/vol &>/dev/null
	
			
		   
 
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
		cp --force "/tmp/MiSTer_SAM_on.sh" "/media/fat/Scripts/MiSTer_SAM_on.sh"
		 
		get_partun
		get_mbc
		get_inputmap
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
	
	# Awaken daemon
	# Check for and delete old fashioned scripts to prefer /media/fat/linux/user-startup.sh
	# (https://misterfpga.org/viewtopic.php?p=32159#p32159)
	
	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	fi

	
	# Add new startup way
	if [ ! -e ${userstartup} ] && [ -e /etc/init.d/S99user ]; then
	  if [ -e ${userstartuptpl} ]; then
		echo "Copying ${userstartuptpl} to ${userstartup}"
		cp ${userstartuptpl} ${userstartup}
	  else
		echo "Building ${userstartup}"
	  fi
	fi
	if [ $(grep -ic "mister_sam" ${userstartup}) = "0" ]; then
	  echo -e "Add mistersam to ${userstartup}\n"
	  echo -e "\n# Startup Super Attract Mode" >> ${userstartup}
	  echo -e "[[ -e ${mrsampath}/MiSTer_SAM_init ]] && ${mrsampath}/MiSTer_SAM_init \$1" >> ${userstartup}
	fi

	echo -n " SAM autoplay daemon starting..."

		${mrsampath}/MiSTer_SAM_init start &


	echo " Done!"
	return
}

function sam_disable() { # Disable autoplay

	echo -n " Disabling SAM autoplay..."
	# Clean out existing processes to ensure we can update
	
	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	fi

	there_can_be_only_one																											 
	sed -i '/MiSTer_SAM/d' ${userstartup}
	sync
	unmute
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

	# -- SAM's {soft,}start_real tmux instance
	kill -9 $(ps -o pid,args | grep '[M]iSTer_SAM_on.sh start_real' | awk '{print $1}') &> /dev/null
	kill -9 $(ps -o pid,args | grep '[M]iSTer_SAM_on.sh softstart_real' | awk '{print $1}') &> /dev/null
	#kill -9 $(ps -o pid,args | grep '[M]iSTer_SAM_on.sh' | awk '{print $1}') &> /dev/null
	# -- Everything executable in mrsampath
	kill -9 $(ps -o pid,args | grep ${mrsampath} | grep -v grep | awk '{print $1}') &> /dev/null
	# -- inotifywait but only if it involves SAM
	kill -9 $(ps -o pid,args | grep '[i]notifywait.*SAM' | awk '{print $1}') &> /dev/null
	# -- hexdump since that's launched, no better way to see which ones to kill
	killall -9 hexdump &> /dev/null

	#wait $(pidof -o ${sampid} ${samprocess}) &>/dev/null
	# -- can't wait PID-wise which is admittedly better, but we know the processes requested will close if running
	# -- instead we sleep one second which seems more than fair. Alternatives, while loop, grep against ps -o args for SAM?
	sleep 1

	echo " Done!"
}

function env_check() {
	# Check if we've been installed
	if [ ! -f "${mrsampath}/partun" ] || [ ! -f "${mrsampath}/MiSTer_SAM_MCP" ]; then
		echo " SAM required files not found."
		echo " Surprised? Check your INI."
		sam_update ${1}
		echo " Setup complete."
	fi
}

function deleteall() {
	# In case of issues, reset SAM
	if [ -d "${mrsampath}" ]; then
		echo "Deleting MiSTer_SAM folder"
		rm -rf "${mrsampath}"
	fi
	if [ -f "/media/fat/Scripts/MiSTer_SAM.ini" ]; then
		echo "Deleting MiSTer_SAM.ini"
		cp /media/fat/Scripts/MiSTer_SAM.ini /media/fat/Scripts/MiSTer_SAM.ini.bak
		rm /media/fat/Scripts/MiSTer_SAM.ini
	fi
	if [ -f "/media/fat/Scripts/MiSTer_SAM_off.sh" ]; then
		echo "Deleting MiSTer_SAM_off.sh"
		rm /media/fat/Scripts/MiSTer_SAM_off.sh
	fi
	if ls /media/fat/Config/inputs/*_input_1234_5678_v3.map 1> /dev/null 2>&1; then
		echo "Deleting Keyboard mapping files"
		rm /media/fat/Config/inputs/*_input_1234_5678_v3.map
	fi
	# Remount root as read-write if read-only so we can remove daemon
	mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
	[ "$RO_ROOT" == "true" ] && mount / -o remount,rw

	# Delete daemon
	echo "Deleting Auto boot Daemon..."
	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	fi
	echo "Done."
	
	sed -i '/MiSTer_SAM/d' ${userstartup}
	sed -i '/Super Attract/d' ${userstartup}
	
	printf "\n\n\n\n\n\nAll files deleted except for MiSTer_SAM_on.sh\n\n\n\n\n\n"
	for i in {5..1}; do
		echo -ne "Returning to menu in ${i}...\033[0K\r"
		sleep 1
	done
	sam_resetmenu
}

function skipmessage() {
	#Skip past bios/safety warnings

			sleep 3 && "${mrsampath}"/mbc raw_seq :31
}	
			
function mglfavorite() {
	#Add current game to _Favorites folder
	
	if [ ! -d "${misterpath}"/_Favorites ]; then
		mkdir "${misterpath}"/_Favorites
	fi
	cp /tmp/SAM_game.mgl "${misterpath}"/_Favorites/"$(cat /tmp/SAM_Game.txt)".mgl
	
}

function tty_waitforack() {
  #echo -n "Waiting for tty2oled Acknowledge... "
  read -d ";" ttyresponse < ${ttydevice}                # The "read" command at this position simulates an "do..while" loop
  while [ "${ttyresponse}" != "ttyack" ]; do
    read -d ";" ttyresponse < ${ttydevice}              # Read Serial Line until delimiter ";"
  done
  #echo -e "${fgreen}${ttyresponse}${freset}"
  ttyresponse=""
}

# USB Send-Picture-Data function
function tty_senddata() {
  newcore="${1}"
  unset picfnam
  if [ -e "${ttypicture_pri}/${newcore}.gsc" ]; then			# Check for _pri pictures
	picfnam="${ttypicture_pri}/${newcore}.gsc"
  elif [ -e "${ttypicture_pri}/${newcore}.xbm" ]; then
    picfnam="${ttypicture_pri}/${newcore}.xbm"
  else
    picfolders="gsc_us xbm_us gsc xbm xbm_text"				# If no _pri picture found, try all the others
    [ "${USE_US_PICTURE}" = "no" ] && picfolders="${picfolders//gsc_us xbm_us/}"
    [ "${USE_GSC_PICTURE}" = "no" ] && picfolders="${picfolders//gsc_us/}" && picfolders="${picfolders//gsc/}"
    [ "${USE_TEXT_PICTURE}" = "no" ] && picfolders="${picfolders//xbm_text/}"
    for picfolder in ${picfolders}; do
      for (( c="${#newcore}"; c>=1; c-- )); do					# Manipulate string...
        picfnam="${ttypicture}/${picfolder^^}/${newcore:0:$c}.${picfolder:0:3}"	# ...until it matches something
	    [ -e "${picfnam}" ] && break
      done
	  [ -e "${picfnam}" ] && break
    done
  fi
  if [ -e "${picfnam}" ]; then							# Exist?
	# For testing...
	if [ "${samdebug,,}" == "yes" ]; then
		echo "-------------------------------------------"
		echo " tty2oled sending Corename: ${1} "
		echo " tty2oled found/send Picture : ${picfnam} "
		echo "-------------------------------------------"
	fi
    echo "CMDCOR,${1}" > ${ttydevice}					# Send CORECHANGE" Command and Corename
    sleep 0.02											# sleep needed here ?!
    tail -n +4 "${picfnam}" | xxd -r -p > ${ttydevice}	# The Magic, send the Picture-Data up from Line 4 and proces
  else													# No Picture available!
    echo "${1}" > ${ttydevice}							# Send just the CORENAME
  fi													# End if Picture check
}

function tty_exit() { # tty_exit
	if [ "${ttyenable,,}" == "yes" ]; then
		# Clear Display	with Random effect
		echo "CMDCLST,-1,0" > "${ttydevice}"
		tty_waitforack
		sleep 1 
		# Show GAME OVER! for 3 secs
		echo "CMDTXT,5,15,0,15,45,GAME OVER!" > "${ttydevice}"
		tty_waitforack
		sleep 3 
		# Set CORENAME for tty2oled Daemon start
		echo "MENU" > /tmp/CORENAME
		# Starting tty2oled daemon
		echo " Starting tty2oled daemon..."
		/media/fat/tty2oled/S60tty2oled start
		echo " Done!"
		#sleep 2
	fi
}

function tty_init() { # tty_init
	# tty2oled initialization
	if [ "${ttyenable,,}" == "yes" ]; then

		if [ "${samquiet,,}" == "no" ]; then echo " Init tty2oled, loading variables... "; fi
		source ${ttysystemini}
		source ${ttyuserini}
		ttydevice=${TTYDEV}
		ttypicture=${picturefolder}
		ttypicture_pri=${picturefolder_pri}
		
		
		# Clear Serial input buffer first
		if [ "${samquiet,,}" == "no" ]; then echo " Clear tty2oled Serial Input Buffer "; fi
		while read -t 0 sdummy < ${ttydevice}; do continue; done
		if [ "${samquiet,,}" == "no" ]; then echo " Done!"; fi
		#sleep 2

		# Stopping ScreenSaver
		if [ "${samquiet,,}" == "no" ]; then echo " Stopping tty2oled ScreenSaver..."; fi
		echo "CMDSAVER,0,0,0" > "${ttydevice}"
		tty_waitforack
		if [ "${samquiet,,}" == "no" ]; then echo " Done!"; fi
		#sleep 2

		# Stopping tty2oled Daemon
		if [ "${samquiet,,}" == "no" ]; then echo " Stopping tty2oled Daemon..."; fi
		/media/fat/tty2oled/S60tty2oled stop
		if [ "${samquiet,,}" == "no" ]; then echo " Done!"; fi
		#sleep 2
		
		# Small loop for Welcome...
		for l in {1..4}; do
			echo "CMDCLS" > "${ttydevice}"
			tty_waitforack
			sleep 0.2
			echo "CMDTXT,1,15,0,0,9, Welcome to..." > "${ttydevice}"
			tty_waitforack
			sleep 0.2
		done
		sleep 2
		echo "CMDTXT,3,15,0,47,27, Super" > "${ttydevice}"
		tty_waitforack
		sleep 0.8
		echo "CMDTXT,3,15,0,97,45, Attract" > "${ttydevice}"
		tty_waitforack
		sleep 0.8
		echo "CMDTXT,3,15,0,153,63, Mode!" > "${ttydevice}"
		tty_waitforack
		sleep 1
	fi
}

function tty_update() { # tty_update core game
	if [ "${ttyenable,,}" == "yes" ]; then
	
		# Wait for tty2oled daemon to show the core logo
		#inotifywait -e modify /tmp/CORENAME
		
		# Wait for tty2oled to show the core logo
		if [ "${samdebug,,}" == "yes" ]; then
			echo "-------------------------------------------"
			echo " tty_update got Corename: ${3} "
		fi
		tty_senddata "${3}"
		tty_waitforack
		# Show Core-Logo for 7 Secs
		sleep 7
		# Clear Display	with Random effect
		echo "CMDCLST,-1,0" > "${ttydevice}"
		tty_waitforack
		#sleep 0.5
		
		# Split long lines - length is approximate since fonts are variable width!

		if [ ${#2} -gt 23 ]; then
			for l in {1..15}; do
				echo "CMDTXT,103,${l},0,0,20,${2:0:20}..." > "${ttydevice}"
				tty_waitforack
				echo "CMDTXT,103,${l},0,0,40, ${2:20}" > "${ttydevice}"
				tty_waitforack																											
				echo "CMDTXT,2,$(( ${l}/3 )),0,0,60,${1}" > "${ttydevice}"
				tty_waitforack
				sleep 0.1
			done
		else
			for l in {1..15}; do
				echo "CMDTXT,103,${l},0,0,20,${2}" > "${ttydevice}"
				tty_waitforack
				echo "CMDTXT,2,$(( ${l}/3 )),0,0,60,${1}" > "${ttydevice}"
				tty_waitforack
				sleep 0.1
			done
													
												 
		fi
	fi
}



#======== DOWNLOAD FUNCTIONS ========
function curl_download() { # curl_download ${filepath} ${URL}

		curl \
			--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
			--insecure \
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
  get_samstuff .MiSTer_SAM/mbc
} 

function get_inputmap() {
	#Ok, this is messy. Try to download every map file and just disable errors if they don't exist.
	echo -n " Downloading input maps - needed to skip past BIOS for some systems..."
	for i in "${CORE_LAUNCH[@]}"; do 
		if [ ! -f /media/fat/Config/inputs/"${CORE_LAUNCH[$i]}"_input_1234_5678_v3.map ]; then  
			curl_download "/tmp/${CORE_LAUNCH[$i]^^}_input_1234_5678_v3.map" "${repository_url}/blob/${branch}/.MiSTer_SAM/inputs/${CORE_LAUNCH[$i]^^}_input_1234_5678_v3.map?raw=true" &>/dev/null
			mv --force "/tmp/${CORE_LAUNCH[$i]^^}_input_1234_5678_v3.map" "/media/fat/Config/inputs/${CORE_LAUNCH[$i]^^}_input_1234_5678_v3.map" &>/dev/null	
		fi
	done
	echo " Done!"
}


#========= SAM MONITOR =========
function sam_monitor_new() {
	# We can omit -r here. Tradeoff; 
	# window size size is correct, can disconnect with ctrl-C but ctrl-C kills MCP
	#tmux attach-session -t SAM															
	# window size will be wrong/too small, but ctrl-c nonfunctional instead of killing/disconnecting
	tmux attach-session -r -t SAM												  
   
}


# ======== SAM OPERATIONAL FUNCTIONS ========
function loop_core() { # loop_core (core)
	echo -e " Starting Super Attract Mode...\n Let Mortal Kombat begin!\n"
	# Reset game log for this session
	echo "" |> /tmp/SAM_Games.log
	
	while :; do					  
	
		while [ ${counter} -gt 0 ]; do
			trap 'counter=0' INT #Break out of loop for skip & next command
			echo -ne " Next game in ${counter}...\033[0K\r"
			sleep 1
			((counter--))
			
			if [ -s /tmp/.SAM_Mouse_Activity ]; then
				if [ "${listenmouse,,}" == "yes" ]; then
					echo " Mouse activity detected!"
					unmute
					exit

				else
					echo " Mouse activity ignored!"
					echo "" |>/tmp/.SAM_Mouse_Activity
				fi
			fi
			
			if [ -s /tmp/.SAM_Keyboard_Activity ]; then
				if [ "${listenkeyboard,,}" == "yes" ]; then
					echo " Keyboard activity detected!"
					unmute					
					exit

				else
					echo " Keyboard activity ignored!"
					echo "" |>/tmp/.SAM_Keyboard_Activity
				fi
			fi
			
			if [ -s /tmp/.SAM_Joy_Activity ]; then
				if [ "${listenjoy,,}" == "yes" ]; then
					echo " Controller activity detected!"
					unmute
					exit
				else
					echo " Controller activity ignored!"
					echo "" |>/tmp/.SAM_Joy_Activity
				fi
			fi
			
		done
		counter=${gametimer}
		next_core ${1}

	done
	trap - INT
	sleep 1
}


function next_core() { # next_core (core)

	if [ -z "${corelist[@]//[[:blank:]]/}" ]; then
		echo " ERROR: FATAL - List of cores is empty. Nothing to do!"
		exit 1
	fi

	if [ -z "${1}" ]; then
		# Don't repeat same core twice
		if [ ! -z ${nextcore} ]; then
			corelisttmp=$(echo $corelist | sed "s/${nextcore} //")
			nextcore="$(echo ${corelisttmp}| xargs shuf --head-count=1 --random-source=/dev/urandom --echo)"
		else		
		nextcore="$(echo ${corelist}| xargs shuf --head-count=1 --random-source=/dev/urandom --echo)"
		fi
		
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

# Mister SAM tries to determine how the user has set up their rom collection. There are 4 possible cases:
# 1. Roms are all unzipped
# 2. Roms are in one big zip archive - like Everdrive
# 3. Roms are zipped individually
# 4. There are some zipped roms and some unzipped roms in the same dir 
							
	#Setting up file lists
	mkdir -p /tmp/.SAMcount
	mkdir -p /tmp/.SAMlist
	mkdir -p "${misterpath}"/Scripts/SAM_GameLists
	romlist=""${misterpath}"/Scripts/SAM_GameLists/${nextcore,,}_romlist"
	romlisttmp="/tmp/.SAMlist/${nextcore,,}_romlist"


	# Simple case: We have unzipped roms. Pretty straight forward.
	function use_roms() {
		
		# Find Roms
		function find_roms() {
			find "${CORE_PATH[${nextcore,,}]}" -type d \( -iname *BIOS* ${fldrex} \) -not -path '*/.*' -prune -false -o -type f -iname "*.${CORE_EXT[${nextcore,,}]}" > ${romlist}
			cp "${romlist}" "${romlisttmp}" &>/dev/null
		}
		
		#Create list
		if [ ! -f "${romlist}" ]; then
			find_roms
		fi
		
		#If dir changed
		if [ "${CORE_PATH[${nextcore,,}]}" != "$(cat ${romlist} |  head -1 | sed 's:^\(.*\)/.*$:\1:')" ]; then
			find_roms
		fi
		
		#Delete played game from list	
		if [ -s "${romlisttmp}" ]; then
			
			#Pick the actual game
			rompath="$(cat ${romlisttmp} | shuf --head-count=1 --random-source=/dev/urandom)"
			
			#Make sure file exists since we're reading from a static list
			if [ ! -f "${rompath}" ]; then
				find_roms
			fi
			
			if [ "${norepeat,,}" == "yes" ]; then
				awk -vLine="$rompath" '!index($0,Line)' "${romlisttmp}"  > /tmp/.SAMlist/tmpfile && mv /tmp/.SAMlist/tmpfile "${romlisttmp}"
			fi
		else
			#Repopulate list
			cp "${romlist}" "${romlisttmp}" &>/dev/null
		fi
			
		romname=$(basename "${rompath}")
	}				  
	
	# Some cores don't use zips, they might use chds for example - get on with it					
	if [ "${CORE_ZIPPED[${nextcore,,}],,}" == "no" ]; then
		if [ "${samquiet,,}" == "no" ]; then echo " ${nextcore^^} does not use ZIPs."; fi
		use_roms
	
	# We might be using ZIPs
	else
		########## Check how many ZIP and ROM files in core path	(Case 4)
	
		if [ ! -f /tmp/.SAMcount/${nextcore}_zipcount ]; then
			zipcount=$(find "${CORE_PATH[${nextcore,,}]}" -type f -iname "*.zip" -print | wc -l)
			echo ${zipcount} > /tmp/.SAMcount/${nextcore}_zipcount
		else
			zipcount=$(cat /tmp/.SAMcount/${nextcore}_zipcount)
		fi
		
		if [ ! -f /tmp/.SAMcount/${nextcore}_romcount ]; then
			romcount=$(find "${CORE_PATH[${nextcore,,}]}" -type d \( -iname *BIOS* ${fldrex} \) -prune -false -o -type f -iname "*.${CORE_EXT[${nextcore,,}]}" -print | wc -l)
			echo ${romcount} > /tmp/.SAMcount/${nextcore}_romcount
		else
			romcount=$(cat /tmp/.SAMcount/${nextcore}_romcount)
		fi

		#How many roms and zips did we find
		if [ "${samquiet,,}" == "no" ]; then echo " Found ${zipcount} zip files in ${CORE_PATH[${nextcore,,}]}."; fi
		if [ "${samquiet,,}" == "no" ]; then echo " Found ${romcount} ${CORE_EXT[${nextcore,,}]} files in ${CORE_PATH[${nextcore,,}]}."; fi		

		#Compare roms vs zips
		if [ "${zipcount}" -gt 0 ] && [ "${romcount}" -gt 0 ] && [ "${usezip,,}" == "yes" ]; then
		
		############ Zip to Rom Compare completed #############
								
		#We've found ZIPs AND ROMs AND we're using zips
		if [ "${samquiet,,}" == "no" ]; then echo " Both ROMs and ZIPs found!"; fi

			#We found at least one large ZIP file - use it (Case 2)
			if [ $(find "${CORE_PATH[${nextcore,,}]}" -maxdepth 1 -xdev -type f -size +300M \( -iname "*.zip" \) -print | wc -l) -gt 0 ]; then
				if [ "${samquiet,,}" == "no" ]; then echo " Using largest zip in folder ( < 300MB+ )"; fi				
				
				function findzip_roms() {
					#find biggest zip file over 300MB
					romfind=$(find "${CORE_PATH[${nextcore,,}]}" -maxdepth 1 -xdev -size +300M -type f -iname "*.zip" -printf '%s %p\n' | sort -n | tail -1 | cut -d ' ' -f 2- )
					"${mrsampath}/partun" "${romfind}" -l -e ${fldrexzip::-1} -f .${CORE_EXT[${nextcore,,}]} > ${romlist}
					cp "${romlist}" "${romlisttmp}" &>/dev/null
				}			
				
				#Create a list of all valid roms in zip
				if [ ! -f ${romlist} ]; then
					findzip_roms
				fi		
					
				#If dir changed
				if [ "${CORE_PATH[${nextcore,,}]}" != "$(cat ${romlist} |  head -1 | sed 's:^\(.*\)/.*$:\1:')" ]; then
					findzip_roms
				fi
				
				if [ -s ${romlisttmp} ]; then
				
					#Pick the actual game
					romselect="$(cat ${romlisttmp} | shuf --head-count=1 --random-source=/dev/urandom)"		
							
					#Check if zip file is still there
					if [ ! -f "$(head -1 ${romlist} | awk -F '.zip' '{print $1".zip"}')" ]; then
						findzip_roms
					fi
					
					rompath="${romfind}/${romselect}"
					
					#Delete rom from list so we don't have repeats
					if [ "${norepeat,,}" == "yes" ]; then
						awk -vLine="$romselect" '!index($0,Line)' "${romlisttmp}"  > /tmp/.SAMlist/tmpfile && mv /tmp/.SAMlist/tmpfile "${romlisttmp}"
					fi
				else
					#Repopulate list
					cp "${romlist}" "${romlisttmp}" &>/dev/null
				fi
								
				romname=$(basename "${rompath}")
				
			# We see more zip files than ROMs, we're probably dealing with individually zipped roms (Case 3)
			elif [ ${zipcount} -gt ${romcount} ]; then
				if [ "${samquiet,,}" == "no" ]; then echo " Fewer ROMs - using ZIPs."; fi
				romfind=$(find "${CORE_PATH[${nextcore,,}]}" -type f -iname "*.zip" | shuf --head-count=1 --random-source=/dev/urandom)
				rompath="${romfind}/$("${mrsampath}/partun" "${romfind}" -l -r -e ${fldrexzip::-1} -f ${CORE_EXT[${nextcore,,}]})"
				romname=$(basename "${rompath}")
					

				
			# I guess we use the ROMs! (Case 1)
			else
				if [ "${samquiet,,}" == "no" ]; then echo " Using ROMs."; fi
				use_roms
			fi

		# Found no ZIPs or we're ignoring them
		
		elif [ $zipcount = 0 ] || [ "${usezip,,}" == "no" ]; then
			if [ "${samquiet,,}" == "no" ]; then echo " Found no zips or ignoring them."; fi
			use_roms

		# Use the ZIP Luke!
		else
			if [ "${samquiet,,}" == "no" ]; then echo " Using zip"; fi
			romfind=$(find "${CORE_PATH[${nextcore,,}]}" -xdev -type f -iname "*.zip" | shuf --head-count=1 --random-source=/dev/urandom)
			rompath="${romfind}/$("${mrsampath}/partun" "${romfind}" -l -r -e ${fldrexzip::-1} -f ${CORE_EXT[${nextcore,,}]})"
			romname=$(basename "${rompath}")
		fi
		

	fi
	
	
	# Sanity check that we have a valid rom in var
	if [[ ${rompath} != *"${CORE_EXT[${nextcore,,}]}"* ]]; then
		next_core 
		return
	fi

	# If there is a whitelist check it
	declare -n whitelist="${nextcore,,}list"
	# Possible exit statuses:
	# 0: found
	# 1: not found
	# 2: error (e.g. file not found)
	if [ $(grep -Fqsx "${romname}" "${whitelist}"; echo "$?") -eq 1 ]; then
		echo " ${romname} is not in ${whitelist} - SKIPPED"
		next_core
		return
	fi

	# If there is an exclude list check it
	declare -n excludelist="${nextcore,,}exclude"
	if [ ${#excludelist[@]} -gt 0 ]; then
		for excluded in "${excludelist[@]}"; do
			if [ "${romname}" == "${excluded}" ]; then
				echo " ${romname} is excluded - SKIPPED"
				awk -vLine="${romname}" '!index($0,Line)' "${romlisttmp}"  > /tmp/.SAMlist/tmpfile && mv /tmp/.SAMlist/tmpfile "${romlisttmp}"
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
	tty_update "${CORE_PRETTY[${1,,}]}" "${3}" "${CORE_LAUNCH[${1,,}]}" &  # Non blocking Version
	#tty_update "${CORE_PRETTY[${1,,}]}" "${3}" "${CORE_LAUNCH[${1,,}]}"    # Blocking Version
	


	if [ "${4}" == "countdown" ]; then
		for i in {5..1}; do
			echo -ne " Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi
	


	#Create mgl file and launch game
	
	
	echo "<mistergamedescription>" > /tmp/SAM_game.mgl
	echo "<rbf>_console/${MGL_CORE[${nextcore}]}</rbf>" >> /tmp/SAM_game.mgl	
	echo "<file delay="${MGL_DELAY[${nextcore}]}" type="${MGL_TYPE[${nextcore}]}" index="${MGL_INDEX[${nextcore}]}" path="\"../../../..${rompath}\""/>" >> /tmp/SAM_game.mgl		
	echo "</mistergamedescription>" >> /tmp/SAM_game.mgl
	
	
	echo "load_core /tmp/SAM_game.mgl" > /dev/MiSTer_cmd	

	sleep 1
	echo "" |>/tmp/.SAM_Joy_Activity
	echo "" |>/tmp/.SAM_Mouse_Activity
	echo "" |>/tmp/.SAM_Keyboard_Activity
	
	if [ "${skipmessage,,}" == "yes" ] && [ "${CORE_SKIP[${nextcore,,}],,}" == "yes" ]; then	
		skipmessage	
	fi
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
	#Make Bootrom folder inaccessible until restart
		if [ -d "${misterpath}/Bootrom" ]; then
			mount --bind /mnt "${misterpath}/Bootrom"
		fi
		#Disable Nes bootroms except for FDS Bios (boot0.rom)
		if [ -f "${misterpath}/Games/NES/boot1.rom" ]; then
			touch /tmp/brfake
			mount --bind /tmp/brfake ${misterpath}/Games/NES/boot1.rom
		fi
		if [ -f "${misterpath}/Games/NES/boot2.rom" ]; then
			touch /tmp/brfake
			mount --bind /tmp/brfake ${misterpath}/Games/NES/boot2.rom
		fi
		if [ -f "${misterpath}/Games/NES/boot3.rom" ]; then
			touch /tmp/brfake
			mount --bind /tmp/brfake ${misterpath}/Games/NES/boot3.rom
		fi
	fi
}

function mute() {
	if [ "${mute,,}" == "yes" ]; then
			#Mute Global Volume
			echo -e "\0020\c" > /media/fat/config/Volume.dat
	fi
}

function unmute() {
	if [ "${mute,,}" == "yes" ]; then
			#Unmute and reload core
			echo -e "\0000\c" > /media/fat/config/Volume.dat
			echo "load_core /tmp/SAM_game.mgl" > /dev/MiSTer_cmd	
	fi
}
		

# ======== ARCADE MODE ========
function build_mralist() {
	# If no MRAs found - suicide!
	find "${arcadepath}" -type f \( -iname "*.mra" \) &>/dev/null
	if [ ! ${?} == 0 ]; then
		echo " The path ${arcadepath} contains no MRA files!"
		loop_core
	fi

	mkdir -p /tmp/.SAMlist

	# This prints the list of MRA files in a path,
	# Cuts the string to just the file name,
	# Then saves it to the mralist file.
	
	# If there is an empty exclude list ignore it
	# Otherwise use it to filter the list
	if [ ${#arcadeexclude[@]} -eq 0 ]; then
		find "${arcadepath}" -not -path '*/.*' -type f \( -iname "*.mra" \)  | cut -c $(( $(echo ${#arcadepath}) + 2 ))- >"${mralist}"
	else
		find "${arcadepath}" -not -path '*/.*' -type f \( -iname "*.mra" \)  | cut -c $(( $(echo ${#arcadepath}) + 2 ))- | grep -vFf <(printf '%s\n' ${arcadeexclude[@]})>"${mralist}"
	fi
}

function load_core_arcade() {

	# Check if the MRA list is empty or doesn't exist - if so, make a new list
	
	if [ ! -s ${mralist} ]; then
		build_mralist	
	fi
	
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
	
	#Delete mra from list so it doesn't repeat
	if [ "${norepeat,,}" == "yes" ]; then
		awk -vLine="$mra" '!index($0,Line)' "${mralist}"  > /tmp/.SAMlist/tmpfile && mv /tmp/.SAMlist/tmpfile "${mralist}"

	fi

	mraname="$(echo "$(basename "${mra}")" | sed -e 's/\.[^.]*$//')"
	echo -n " Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore,,}]}\e[0m: "
	echo -e "\e[1m${mraname}\e[0m"
	echo "$(date +%H:%M:%S) - Arcade - ${mraname}" >> /tmp/SAM_Games.log
	echo "${mraname} (${nextcore})" > /tmp/SAM_Game.txt
	
	# Get Setname from MRA needed for tty2oled, thx to RealLarry
	mrasetname=$(grep "<setname>" "${arcadepath}/${mra}" | sed -e 's/<setname>//' -e 's/<\/setname>//' | tr -cd '[:alnum:]')
	#tty_update "${CORE_PRETTY[${nextcore,,}]}" "${mraname}" "${mrasetname}" &  # Non-Blocking
	tty_update "${CORE_PRETTY[${nextcore,,}]}" "${mraname}" "${mrasetname}"    # Blocking

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
	echo " repository_url: ${repository_url}"
	echo " branch: ${branch}"
						  
	echo ""
	echo " gametimer: ${gametimer}"
	echo " corelist: ${corelist}"
	echo " usezip: ${usezip}"
										  
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
	echo " gbalist: ${gbalist}"
	echo " genesislist: ${genesislist}"
	echo " megacdlist: ${megacdlist}"
	echo " neogeolist: ${neogeolist}"
	echo " neslist: ${neslist}"
	echo " sneslist: ${sneslist}"
	echo " tgfx16list: ${tgfx16list}"
	echo " tgfx16cdlist: ${tgfx16cdlist}"
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
mute									   
init_data		# Setup data arrays
parse_cmd ${@}	# Parse command line parameters for input


#exit
