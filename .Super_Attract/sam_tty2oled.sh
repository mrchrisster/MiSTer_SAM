#!/bin/bash

# https://github.com/Paradox
# TTY2OLED module created for SAM by paradox

# ======== GLOBAL VARIABLES =========
# Save our PID and process
declare -g sampid="${$}"
declare -g samprocess=$(basename -- ${0})
declare -g misterpath="/media/fat"
declare -g misterscripts="${misterpath}/Scripts"
declare -g mrsampath="${misterscripts}/.Super_Attract"
declare -g mrsamtmp="/tmp/.SAM_tmp"

declare -gl ttyenable="Yes"
declare -gi gametimer=120
declare -g TTY_cmd_pipe="${mrsamtmp}/TTY_cmd_pipe"
compgen -v | sed s/=.\*// >/tmp/${samprocess}.tmp
declare -gi ttyupdate_pause=1
declare -g tty_currentinfo_file=${mrsamtmp}/tty_currentinfo
declare -g tty_sleepfile="/tmp/tty2oled_sleep"
declare -gA tty_currentinfo=(
	[core_pretty]=
	[name]=
	[core]=
	[date]=0
	[counter]=0
	[name_scroll]=
	[name_scroll_position]=0
	[name_scroll_direction]=1
	[update_pause]=${ttyupdate_pause}
)

declare -g ttydevice="/dev/ttyUSB0"
declare -g ttysystemini="/media/fat/tty2oled/tty2oled-system.ini"
declare -g ttyuserini="/media/fat/tty2oled/tty2oled-user.ini"
declare -g ttypicture="/media/fat/tty2oled/pics"
declare -g ttypicture_pri="/media/fat/tty2oled/pics_pri"
declare -g prev_name_scroll=""
declare -g prev_counter=""
samquiet=no
samdebug=yes
samtrace=yes
splash=0

trap 'rc=$?;[ ${rc} = 0 ] && exit;tty_exit' EXIT TERM INT


# ======== Source ini files ========
source "${misterpath}/Scripts/Super_Attract_Mode.ini"
#Roulette Mode
if [ -f /tmp/.SAM_tmp/gameroulette.ini ]; then
	source /tmp/.SAM_tmp/gameroulette.ini
fi
source ${ttysystemini}
source ${ttyuserini}
ttydevice=${TTYDEV}

gametimer=$((gametimer + 3))

if [ "${ttyscroll_speed}" == "faster" ]; then
	ttyscroll_speed_int=0.5
elif [ "${ttyscroll_speed}" == "slower" ]; then
	ttyscroll_speed_int=1.5
else
	ttyscroll_speed_int=1
fi


# ======== tty2oled FUNCTIONS ========

function tty_init() { # tty_init
	# tty2oled initialization
	declare -gi START=$(date +%s)
	samquiet " Init tty2oled, loading variables... "
	ttypicture=${picturefolder}
	ttypicture_pri=${picturefolder_pri}
	set_scroll_speed

	### Wait for USB module and start tty2oled daemon
	WAITEND=$((SECONDS+10))
	while !  [ -c ${ttydevice} ] && [ ${SECONDS} -lt ${WAITEND} ]; do
		sleep 0.1
	done
	if ! [ -c ${ttydevice} ]; then
		echo "Could not find the needed USB module ${TTYDEV}. Exiting."
		exit 1
	fi

	# Clear Serial input buffer first
	samquiet "-n" " Clear tty2oled Serial Input Buffer..."
	while read -t 0 sdummy <${ttydevice}; do continue; done
	samquiet " Done!"

	# Stopping ScreenSaver
	samquiet "-n" " Stopping tty2oled ScreenSaver..."
	echo "CMDSWSAVER,0" >${ttydevice}
	tty_waitfor
	#sleep 2
	samquiet " Done!"

}

function tty_exit() {
	#Enable screensaver
	[[ -c ${ttydevice} ]] && echo "CMDSWSAVER,1" >${ttydevice}
	# Clear Display	with Random effect
	[[ -c ${ttydevice} ]] && echo "CMDCLST,-1,0" >${ttydevice}
	tty_waitfor
}
 
function tty_waitfor() {
	[[ -c ${ttydevice} ]] && read -t 10 -d ";" ttyresponse <${ttydevice} # Read now with Timeout and without "loop"
	ttyresponse=""
}

function update_name_scroll() {
	if [ ${#tty_currentinfo[name]} -gt 21 ]; then
		length=$((${#tty_currentinfo[name]} + 5))
		tty_currentinfo[name_scroll]="${tty_currentinfo[name]}      ${tty_currentinfo[name]}"
		if [[ "${tty_currentinfo[name_scroll_position]}" -lt "$length" ]]; then
			((tty_currentinfo[name_scroll_position]++))
		else
			tty_currentinfo[name_scroll_position]=0
			
		fi					
		tty_currentinfo[name_scroll]="${tty_currentinfo[name_scroll]:${tty_currentinfo[name_scroll_position]}:25}"
		[[ -c ${ttydevice} ]] && [[ "${ttybig,,}" == "no" ]] && echo "CMDTXT,103,0,0,0,20,${prev_name_scroll}" >${ttydevice}
		[[ -c ${ttydevice} ]] && [[ "${ttybig,,}" == "no" ]] && echo "CMDTXT,103,15,0,0,20,${tty_currentinfo[name_scroll]}" >${ttydevice}
		[[ -c ${ttydevice} ]] && [[ "${ttybig,,}" == "yes" ]] && echo "CMDTXT,105,0,0,0,30,${prev_name_scroll}" >${ttydevice}
		[[ -c ${ttydevice} ]] && [[ "${ttybig,,}" == "yes" ]] && echo "CMDTXT,105,15,0,0,30,${tty_currentinfo[name_scroll]}" >${ttydevice}
		prev_name_scroll="${tty_currentinfo[name_scroll]}"
	fi
}



# Update bottom row - Display Next game in XXX
function update_counter() {
	if [ ${tty_currentinfo[update_pause]} -gt 0 ]; then
		((tty_currentinfo[update_pause]--))
	else
		update_name_scroll
	fi
	local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
	tty_currentinfo[counter]=$((gametimer - elapsed))
	if [ ${tty_currentinfo[counter]} -lt 1 ]; then
		tty_currentinfo[counter]=0
	fi
	[[ -c ${ttydevice} ]] && echo "CMDTXT,102,0,0,0,60,Next game in ${prev_counter}" >${ttydevice}
	[[ -c ${ttydevice} ]] && echo "CMDTXT,102,15,0,0,60,Next game in ${tty_currentinfo[counter]}" >${ttydevice}
	prev_counter="${tty_currentinfo[counter]}"
	[[ -c ${ttydevice} ]] && echo "CMDDUPD" >${ttydevice}
	tty_waitfor
	if [ ${samtrace} == "yes" ]; then
		declare -p tty_currentinfo | sed 's/declare -A tty_currentinfo=//g'
	fi
}

function tty_display() { # tty_update core game
	if [ -s ${tty_currentinfo_file} ]; then
		if [ "${splash}" == "0" ]; then
			#Show Splash
			echo "CMDAPD,SAM_splash" >${ttydevice}
			tail -n +4 "/media/fat/tty2oled/pics/GSC/SAM_splash.gsc" | xxd -r -p >${ttydevice}
			tty_waitfor
			echo "CMDSPIC,-1" >${ttydevice}
			tty_waitfor
			sleep 5
			splash=1
		fi
		source "${tty_currentinfo_file}"
		gametimer="${tty_currentinfo[counter]}"
		sleepfile_expiration=$((tty_currentinfo[date] + (tty_currentinfo[counter] + 10)))
		echo "${sleepfile_expiration}" >${tty_sleepfile}
		# Wait for tty2oled daemon to show the core logo
		tty_senddata "${tty_currentinfo[core]}"
		# Wait for tty2oled to show the core logo
		samdebug "-------------------------------------------"
		samdebug " tty_update got Corename: ${tty_currentinfo[core]} "
		samdebug "-------------------------------------------"
		samdebug " tty_update counter: ${tty_currentinfo[counter]} "
		sleep "${ttycoresleep}"
		# Clear Display	with Random effect
		echo "CMDCLST,-1,0" >"${ttydevice}"
		tty_waitfor
		local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
		tty_currentinfo[counter]=$((gametimer - elapsed))
		[[ -c ${ttydevice} ]] && [[ "${ttybig,,}" == "yes" ]] && echo "CMDTXT,105,15,0,0,30,${tty_currentinfo[name_scroll]}" >${ttydevice}
		[[ -c ${ttydevice} ]] && [[ "${ttybig,,}" == "no" ]] && echo "CMDTXT,103,15,0,0,20,${tty_currentinfo[name_scroll]}" >${ttydevice}
		[[ -c ${ttydevice} ]] && [[ "${ttybig,,}" == "no" ]] && echo "CMDTXT,102,5,0,0,40,${tty_currentinfo[core_pretty]}" >${ttydevice}
		[[ -c ${ttydevice} ]] && echo "CMDTXT,102,15,0,0,60,Next game in ${tty_currentinfo[counter]}" >${ttydevice}
		prev_name_scroll="${tty_currentinfo[name_scroll]}"
		prev_counter="${tty_currentinfo[counter]}"
	fi
}

# USB Send-Picture-Data function
function tty_senddata() {
	local newcore="${1}"
	unset picfnam
	if [ -e "${ttypicture_pri}/${newcore}.gsc" ]; then # Check for _pri pictures
		picfnam="${ttypicture_pri}/${newcore}.gsc"
	elif [ -e "${ttypicture_pri}/${newcore}.xbm" ]; then
		picfnam="${ttypicture_pri}/${newcore}.xbm"
	else
		picfolders="gsc_us xbm_us gsc xbm xbm_text" # If no _pri picture found, try all the others
		[ "${USE_US_PICTURE}" = "no" ] && picfolders="${picfolders//gsc_us xbm_us/}"
		[ "${USE_GSC_PICTURE}" = "no" ] && picfolders="${picfolders//gsc_us/}" && picfolders="${picfolders//gsc/}"
		[ "${USE_TEXT_PICTURE}" = "no" ] && picfolders="${picfolders//xbm_text/}"
		for picfolder in ${picfolders}; do
			for ((c = "${#newcore}"; c >= 1; c--)); do                                 # Manipulate string...
				picfnam="${ttypicture}/${picfolder^^}/${newcore:0:${c}}.${picfolder:0:3}" # ...until it matches something
				[ -e "${picfnam}" ] && break
			done
			[ -e "${picfnam}" ] && break
		done
	fi
	if [ -e "${picfnam}" ]; then # Exist?
		# For testing...
		samdebug "-------------------------------------------"
		samdebug " tty2oled sending Corename: ${1} "
		samdebug " tty2oled found/send Picture : ${picfnam} "
		samdebug "-------------------------------------------"

		[[ -c ${ttydevice} ]] && echo "CMDCOR,${1}" >${ttydevice}                # Send CORECHANGE" Command and Corename
		[[ -c ${ttydevice} ]] && tail -n +4 "${picfnam}" | xxd -r -p >${ttydevice} # The Magic, send the Picture-Data up from Line 4 and proces
		tty_waitfor                                       # sleep needed here ?!
	else                                               # No Picture available!
		[[ -c ${ttydevice} ]] && echo "${1}" >${ttydevice}                       # Send just the CORENAME
		tty_waitfor                                       # sleep needed here ?!
	fi                                                 # End if Picture check
}

function samquiet() {
	if [ "${samquiet}" == "no" ]; then
		if [ "${1}" == "-n" ]; then
			echo -en "\e[1m\e[32m${2-}\e[0m"
		else
			echo -e "\e[1m\e[32m${1-}\e[0m"
		fi
	fi
}

function samdebug() {
	if [ "${samdebug}" == "yes" ]; then
		if [ "${1}" == "-n" ]; then
			echo -en "\e[1m\e[31m${2-}\e[0m"
		else
			echo -e "\e[1m\e[31m${1-}\e[0m"
		fi
	fi
}


function write_to_TTY_cmd_pipe() {
	[[ -p ${TTY_cmd_pipe} ]] && echo "${@}" >${TTY_cmd_pipe}
}


function update_loop() {
	while [[ -p ${TTY_cmd_pipe} ]]; do
		sleep ${ttyscroll_speed_int}
		write_to_TTY_cmd_pipe "update_counter" &
	done
}

function start_pipe_reader() {
	samquiet " Init tty2oled, starting pipe reader... "
	[ -p ${TTY_cmd_pipe} ] && rm -f ${TTY_cmd_pipe}
	[ -e ${TTY_cmd_pipe} ] && rm -f ${TTY_cmd_pipe}
	if [[ ! -p ${TTY_cmd_pipe} ]]; then
		mkfifo ${TTY_cmd_pipe}
	fi

	while true; do
		local line
		if [[ -p ${TTY_cmd_pipe} ]]; then
			if read line <${TTY_cmd_pipe}; then
				set -- junk ${line}
				shift
				case "${1}" in
				stop | quit | exit)
					tty_exit
					break
					;;
				display_info)
					shift
					if [ -c ${ttydevice} ]; then
						tty_display "${@}"
					fi
					;;
				update_counter)
					update_counter
					;;
				*)
					echo " ERROR! ${line} is unknown."
					echo " Try $(basename -- ${0}) help"
					echo " Or check the Github readme."
					echo " Named Pipe"
					;;
				esac
			fi
		fi
	done &
}


# ========= MAIN =========
function main() {
	start_pipe_reader
	tty_init
	update_loop
}

if [ "${ttyenable}" == "yes" ]; then
	main ${@}
fi
trap - INT
