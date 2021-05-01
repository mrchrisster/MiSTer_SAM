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

#======== LOCAL VARIABLES ========
declare -i coreretries=3
declare -i romloadfails=0
mralist="/tmp/.SAMmras"
gametimer=120
corelist="arcade,gba,genesis,megacd,neogeo,nes,snes,tgfx16,tgfx16cd"
usezip="Yes"
disablebootrom="Yes"
orientation=All
listenmouse="Yes"
listenkeyboard="Yes"
listenjoy="Yes"
mbcpath="/media/fat/Scripts/.MiSTer_SAM/mbc"
partunpath="/media/fat/Scripts/.MiSTer_SAM/partun"
mrapathvert="/media/fat/_Arcade/_Organized/_6 Rotation/_Vertical CW 90 Deg" 
mrapathhoriz="/media/fat/_Arcade/_Organized/_6 Rotation/_Horizontal"
branch="main"
mbcurl="blob/master/mbc_v02"
sindurl="blob/master/sind.sh"
doreboot="Yes"
normalreboot="Yes"

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
arcadeexclude="
First Bad Game.mra
Second Bad Game.mra
Third Bad Game.mra
"
gbaexclude="
First Bad Game.gba
Second Bad Game.gba
Third Bad Game.gba
"
genesisexclude="
First Bad Game.gen
Second Bad Game.gen
Third Bad Game.gen
"
megacdexclude="
First Bad Game.chd
Second Bad Game.chd
Third Bad Game.chd
"
neogeoexclude="
First Bad Game.neo
Second Bad Game.neo
Third Bad Game.neo
"
nesexclude="
First Bad Game.nes
Second Bad Game.nes
Third Bad Game.nes
"
snesexclude="
First Bad Game.sfc
Second Bad Game.sfc
Third Bad Game.sfc
"
tgfx16exclude="
First Bad Game.pce
Second Bad Game.pce
Third Bad Game.pce
"
tgfx16cdexclude="
First Bad Game.chd
Second Bad Game.chd
Third Bad Game.chd
"

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

# Set arcadepath based on orientation
if [ "${orientation,,}" == "vertical" ]; then
	arcadepath="${mrapathvert}"
elif [ "${orientation,,}" == "horizontal" ]; then
	arcadepath="${mrapathhoriz}"
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

# Remove trailing slash from paths
for var in mrsampath misterpath mrapathvert mrapathhoriz arcadepath gbapath genesispath megacdpath neogeopath nespath snespath tgfx16path tgfx16cdpath; do
	declare -g ${var}="${!var%/}"
done

# Warn if using non-default branch for updates
if [ ! "${branch}" == "main" ]; then
	echo ""
	echo " ***********************************************"
	echo " !! DOWNLOADING UPDATES FROM ${branch} BRANCH !!"
	echo " ***********************************************"
	echo ""
fi


#======== SAM MENU ========
function sam_menu() {
	for core in ${corelist}; do
		menulist+=( " ${core^^} " )
	done
	clear
	echo " +-------------------------------------------------+"
	echo " | Welcome to MiSTer FPGA Super Attract Mode (SAM) |"
	echo " +-------------------------------------------------+"
	echo ""
	echo " Your options are:"
	echo " -----------------"
	echo " Start				Start Super Attract Mode now - does not enable screensaver"
	echo " Next				Move to the next random game - does not reset the timer"
	echo " Stop				Stop Super Attract Mode now - does not disable screensaver"
	echo " Cancel				Do nothing and exit"
	echo ""
	for item in ${menulist[@]}; do
		echo " ${item^^}			Start SAM with only games from the ${CORE_PRETTY[${item,,}]}"
	done
	echo ""
	echo " Update				Updates Super Attract Mode and reboots"
	echo " Enable				Enables the Super Attract Mode screen saver"
	echo " Disable			Disables the Super Attract Mode screen saver"
	echo " Monitor			Monitors output from Super Attract Mode in this terminal - use via ssh"
	echo ""
	echo -n " "
	menuresponse=$(/media/fat/Scripts/.MiSTer_SAM/sind --line --options " Start " " Next " " Cancel " ${menulist[@]} " Update " " Enable " " Disable " " Monitor ")
	if [ "${samquiet,,}" == "no" ]; then echo "menuresponse: ${menuresponse,,}"; fi
	parse_cmd ${menuresponse,,}
}

function parse_cmd() {
	for arg in "${@}"; do
		case ${arg,,} in
			start) # Start SAM immediately
				gonext="sam_start"
				;;
			next) # Load next core - doesn't interrupt loop if running
				gonext="next_core"
				;;
			stop) # Stop SAM immediately
				there_can_be_only_one
				echo " Thanks for playing!"
				exit 0
				;;
			update) # Update SAM
				gonext="sam_update"
				;;
			enable) # Enable SAM screensaver mode
				gonext="sam_enable"
				;;
			disable) # Disable SAM screensaver
				gonext="sam_disable"
				;;
			monitor) # Attach output to terminal
				gonext="sam_monitor"
				;;
			arcade)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="Arcade"
				gonext="sam_start"
				;;
			gba)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="GBA"
				gonext="sam_start"
				;;
			genesis)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="Genesis"
				gonext="sam_start"
				;;
			megacd)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="MegaCD"
				gonext="sam_start"
				;;
			neogeo)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="NeoGeo"
				gonext="sam_start"
				;;
			nes)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="NES"
				gonext="sam_start"
				;;
			snes)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="SNES"
				gonext="sam_start"
				;;
			tgfx16cd)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="TGFX16CD"
				gonext="sam_start"
				;;
			tgfx16)
				echo " ${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="TGFX16"
				gonext="sam_start"
				;;
			cancel) # Exit
				exit 0
				;;
			*)
				gonext="sam_menu"
				;;
		esac
	done

	# If we need to go somewhere special - do it here
	if [ ! -z "${gonext}" ]; then
		${gonext}
		exit 0
	fi
}


#======== SAM COMMANDS ========
function sam_start() { #Start SAM
	there_can_be_only_one # Terminate any other running SAM processes
	
	# If the MCP isn't running we need to start it in monitoring only mode
	if [ -z "$(pidof MiSTer_SAM_MCP.sh)" ]; then
		${mrsampath}/MiSTer_SAM_MCP.sh monitoronly
	fi
	
	loop_core
}
	
function sam_update() {
	# Ensure the MiSTer SAM data directory exists
	mkdir --parents "${mrsampath}" &>/dev/null
	
	# Prep curl
	curl_check
	
	if [ ! "$(dirname -- ${0})" == "/tmp" ]; then
		# Initial run - need to get updated MiSTer_SAM.sh
		echo " Stopping MiSTer SAM processes..."
	
		# Clean out existing processes to ensure we can update
		there_can_be_only_one
		/etc/init.d/S93mistersam stop
	
		# Download the newest MiSTer_SAM.sh to /tmp
		get_samstuff MiSTer_SAM.sh /tmp
		if [ -f /tmp/MiSTer_SAM.sh ]; then
			/tmp/MiSTer_SAM.sh update
			exit 0
		else
			# /tmp/MiSTer_SAM.sh isn't there!
	  	echo " MiSTer SAM update FAILED - no Internet?"
		fi
	else # We're running from /tmp - download dependencies and proceed
		cp --force "/tmp/MiSTer_SAM.sh" "/media/fat/Scripts/MiSTer_SAM.sh"
		get_mbc
		get_partun
		get_sind
		get_samstuff MiSTer_SAM/MiSTer_SAM_init
		get_samstuff MiSTer_SAM/MiSTer_SAM_MCP.sh
		get_samstuff MiSTer_SAM/MiSTer_SAM_joy.sh
		get_samstuff MiSTer_SAM/MiSTer_SAM_joy.py
		get_samstuff MiSTer_SAM/MiSTer_SAM_keyboard.sh
		get_samstuff MiSTer_SAM/MiSTer_SAM_mouse.sh
		
		if [ -f /media/fat/Scripts/MiSTer_SAM.ini ]; then
			echo " MiSTer SAM INI already exists... SKIPPED!"
		else
			get_samstuff MiSTer_SAM.ini /media/fat/Scripts
		fi
	fi
	
	sam_reboot
}

function sam_enable() { # Enable screensaver
	echo -n "Enabling MiSTer SAM Screensaver... "
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

	echo -n "MiSTer SAM starting... "
	/etc/init.d/S93mistersam start &
	echo "Done!"
}

function sam_disable() { # Disable screensaver
	/etc/init.d/S93mistersam stop
	
	mount | grep -q "on / .*[(,]ro[,$]" && RO_ROOT="true"
	[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
	rm -f /etc/init.d/S93mistersam > /dev/null 2>&1
	sync
	[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	sync
	
	echo " MiSTer Super Attract Mode is off and inactive at startup."
}


#======== UTILITY FUNCTIONS ========
function there_can_be_only_one() { # there_can_be_only_one (pid) (process)
	# If another attract process is running kill it
	# This can happen if the script is started multiple times
	echo " Stopping other running instances of ${samprocess}..."
	kill -9 $(pidof -o ${sampid} ${samprocess}) &>/dev/null
	wait $(pidof -o ${sampid} ${samprocess}) &>/dev/null
	echo " Done!"
}

function env_check() {
	# Check if we've been installed
	if [ ! -f "${mbcpath}" ] || [ ! -f "${partunpath}" ] || [ ! -f "${mrsampath}/sind" ] || [ ! -f "${mrsampath}/MiSTer_SAM_MCP.sh" ]; then
		echo " MiSTer Super Attract Mode support files not found."
		echo " If this is unexpected check your INI settings."
		for i in {5..1}; do
			echo -ne " Starting installation and reboot in ${i}...\033[0K\r"
			sleep 1
		done
		echo ""
		sam_update
	fi
}

function sam_reboot() {
	# Reboot
	if [ "${doreboot,,}" == "yes" ]; then
		if [ "${normalreboot,,}" == "yes" ]; then
			echo " Rebooting..."
			reboot
		else
			echo " Forcing reboot..."
			reboot -f
		fi
	fi
}

function sam_jsmonitor() {
	# Monitor joystick devices for changes
	inotifywait --quiet --monitor --event create --event moved_to --event close_write /dev/input/ | while read path action file; do
		echo "Device change" >> /tmp/.SAM_Joy_Change
	done
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
		echo -n " Downloading from ${REPOSITORY_URL}/blob/${branch}/${1} to ${filepath}/... "
	curl_download "/tmp/${1##*/}" "${REPOSITORY_URL}/blob/${branch}/${1}?raw=true"

	if [ ! "${filepath}" == "/tmp" ]; then
		mv --force "/tmp/${1##*/}" "${filepath}/${1##*/}"
	fi

	if [ "${1##*.}" == "sh" ]; then
		chmod +x "${filepath}/${1##*/}"
	fi
	
	echo "Done!"
}

function get_mbc() {
	REPOSITORY_URL="https://github.com/mrchrisster/MiSTer_Batch_Control"
	echo " Downloading mbc - a tool needed for launching roms..."
	echo " Created for MiSTer by pocomane"
	echo " ${REPOSITORY_URL}"
	echo " Done!"
	curl_download "/tmp/mbc" "${REPOSITORY_URL}/${mbcurl}?raw=true"
	mv --force "/tmp/mbc" "${mrsampath}/mbc"
}

function get_partun() {
  REPOSITORY_URL="https://github.com/woelper/partun"
  echo " Downloading partun - needed for unzipping roms from big archives..."
  echo " Created for MiSTer by woelper - who is allegedly not a spider"
  echo " ${REPOSITORY_URL}"
	echo " Done!"
  latest=$(curl -s -L --insecure https://api.github.com/repos/woelper/partun/releases/latest | jq -r ".assets[] | select(.name | contains(\"armv7\")) | .browser_download_url")
  curl_download "/tmp/partun" "${latest}"
 	mv --force "/tmp/partun" "${mrsampath}/partun"
}

function get_sind() {
	REPOSITORY_URL="https://github.com/l3laze/sind"
	echo " Downloading sind - bash menu to the stars..."
	echo " Public domain - maintained by l3laze"
	echo " ${REPOSITORY_URL}"
	curl_download "/tmp/sind" "${REPOSITORY_URL}/${sindurl}?raw=true"
	mv --force "/tmp/sind" "${mrsampath}/sind"
	echo " Done!"
}


#========= SAM MONITOR =========
function sam_monitor() {
	
	PID=$(pidof -s -o ${sampid} ${samprocess})

	if [ $PID ]; then
		echo " Attaching MiSTer SAM to current shell"
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
	
		PID=$(pidof -s -o ${sampid} ${samprocess})
	
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
			[ "$quiet" != "yes" ] && echo "Success" >&2
		else
			warn "Remapping failed"
		fi
		
		#cp $GDBCMD /tmp/gdbcmd
		rm -f $GDBCMD
	else
		echo " Couldn't detect MiSTer_SAM.sh running"
	fi
}


# ======== SAM OPERATIONAL FUNCTIONS ========
function loop_core() {
	echo " Let Mortal Kombat begin!"
	# Reset game log for this session
	echo "" |> /tmp/SAM_Games.log
	
	sam_jsmonitor &

	while :; do
		counter=${gametimer}

		next_core
		while [ ${counter} -gt 0 ]; do
			echo -ne "Next game in ${counter}...\033[0K\r"
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

function next_core() { # next_core (nextcore)
	if [ -z "${corelist[@]//[[:blank:]]/}" ]; then
		echo " ERROR: FATAL - List of cores is empty. Nothing to do!"
		exit 1
	fi

	if [ -z "${1}" ]; then
		nextcore="$(echo ${corelist}| xargs shuf -n1 -e)"
	else
		nextcore="${1}"
	fi

	if [ "${nextcore,,}" == "arcade" ]; then
		load_core_arcade
		return
	elif [ "${CORE_ZIPPED[${nextcore,,}],,}" == "yes" ]; then
		# If not ZIP in game directory OR if ignoring ZIP
		if [ -z "$(find ${CORE_PATH[${nextcore,,}]} -maxdepth 1 -type f \( -iname "*.zip" \))" ] || [ "${usezip,,}" == "no" ]; then
			rompath="$(find ${CORE_PATH[${nextcore,,}]} -type d \( -name *BIOS* -o -name *Eu* -o -name *Other* -o -name *VGM* -o -name *NES2PCE* -o -name *FDS* -o -name *SPC* -o -name Unsupported \) -prune -false -o -name *.${CORE_EXT[${nextcore,,}]} | shuf -n 1)"
			romname=$(basename "${rompath}")
		else # Use ZIP
			romname=$("${partunpath}" "$(find ${CORE_PATH[${nextcore,,}]} -maxdepth 1 -type f \( -iname "*.zip" \) | shuf -n 1)" -i -r -f ${CORE_EXT[${nextcore,,}]} --rename /tmp/Extracted.${CORE_EXT[${nextcore,,}]})
			# Partun returns the actual rom name to us so we need a special case here
			romname=$(basename "${romname}")
			rompath="/tmp/Extracted.${CORE_EXT[${nextcore,,}]}"
		fi
	else
		rompath="$(find ${CORE_PATH[${nextcore,,}]} -type f \( -iname *.${CORE_EXT[${nextcore,,}]} \) | shuf -n 1)"
		romname=$(basename "${rompath}")
	fi

	# If there is an exclude list check it
	declare -n excludelist="${nextcore,,}exclude"
	if [ ${#excludelist[@]} -gt 0 ]; then
		for excluded in "${excludelist[@]}"; do
			if [ "${romname}" == "${excluded}" ]; then
				echo " The game \"${romname}\" is on the exclusion list - SKIPPED"
				next_core
				return
			fi
		done
	fi

	if [ -z "${rompath}" ]; then
		core_error "${nextcore}" "${rompath}"
	else
		load_core "${nextcore}" "${rompath}" "${romname%.*}" "${1}"
	fi
}

function load_core() { # load_core core /path/to/rom name_of_rom (countdown)
	echo -n "Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${1,,}]}\e[0m: "
	echo -e "\e[1m${3}\e[0m"
	echo "$(date +%H:%M:%S) - ${1} - ${3}" >> /tmp/SAM_Games.log
	echo "${3} (${1})" > /tmp/SAM_Game.txt

	if [ "${4}" == "countdown" ]; then
		for i in {5..1}; do
			echo -ne "Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi

	"${mbcpath}" load_rom ${1^^} "${2}" > /dev/null 2>&1
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
	mra="$(shuf -n 1 ${mralist})"

	# If the mra variable is valid this is skipped, but if not we try 10 times
	# Partially protects against typos from manual editing and strange character parsing problems
	for i in {1..10}; do
		if [ ! -f "${arcadepath}/${mra}" ]; then
			mra=$(shuf -n 1 ${mralist})
		fi
	done

	# If the MRA is still not valid something is wrong - suicide
	if [ ! -f "${arcadepath}/${mra}" ]; then
		echo " There is no valid file at ${arcadepath}/${mra}!"
		return
	fi

	echo -n "Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore,,}]}\e[0m: "
	echo -e "\e[1m$(echo $(basename "${mra}") | sed -e 's/\.[^.]*$//')\e[0m"
	echo "$(echo $(basename "${mra}") | sed -e 's/\.[^.]*$//') (${nextcore})" > /tmp/SAM_Game.txt
	echo "$(date +%H:%M:%S) - Arcade - $(echo $(basename "${mra}"))" >> /tmp/SAM_Games.log

	if [ "${1}" == "countdown" ]; then
		for i in {5..1}; do
			echo " Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi

  # Tell MiSTer to load the next MRA
  echo "load_core ${arcadepath}/${mra}" > /dev/MiSTer_cmd
}


#========= MAIN =========
#======== DEBUG OUTPUT =========
if [ "${samquiet,,}" == "no" ]; then
	echo " ********************************************************************************"
	#======== GLOBAL VARIABLES =========
	echo " mrsampath: ${mrsampath}"
	echo " misterpath: ${misterpath}"
	echo " sampid: ${sampid}"
	echo " samprocess: ${samprocess}"
	echo ""
	#======== LOCAL VARIABLES ========
	echo " branch: ${branch}"
	echo " mbcurl: ${mbcurl}"
	echo ""
	echo " gametimer: ${gametimer}"
	echo " corelist: ${corelist}"
	echo " usezip: ${usezip}"
	echo " disablebootrom: ${disablebootrom}"
	echo " orientation: ${orientation}"
	echo " mralist: ${mralist}"
	echo " listenmouse: ${listenmouse}"
	echo " listenkeyboard: ${listenkeyboard}"
	echo " listenjoy: ${listenjoy}"
	echo " mbcpath: ${mbcpath}"
	echo " partunpath: ${partunpath}"
	echo " mrapathvert: ${mrapathvert}"
	echo " mrapathhoriz: ${mrapathhoriz}"
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

disable_bootrom							# Disable Bootrom until Reboot 
build_mralist								# Generate list of MRAs
init_data										# Setup data arrays
env_check										# Check that we've been installed
parse_cmd ${@}							# Parse command line parameters for input
sam_menu										# What are we doing today?
exit
