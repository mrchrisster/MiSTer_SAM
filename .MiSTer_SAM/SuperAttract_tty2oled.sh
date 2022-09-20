#!/bin/bash

# https://github.com/mrchrisster/MiSTer_SAM/
# Copyright (c) 2021 by mrchrisster and Mellified

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

# Description
# This cycles through arcade and console cores periodically
# Games are randomly pulled from their respective folders

# ======== Credits ========
# Original concept and implementation: mrchrisster
# Additional development and script layout: Mellified and Paradox
#
# mbc by pocomane
# partun by woelper
# samindex by wizzo
# tty2oled by venice
#
# Thanks for the contributions and support:
# kaloun34, redsteakraw, RetroDriven, LamerDeluxe, InquisitiveCoder, Sigismond

# ======== GLOBAL VARIABLES =========
# Save our PID and process
declare -g sampid="${$}"
declare -g samprocess=$(basename -- ${0})
declare -g misterpath="/media/fat"
declare -g misterscripts="${misterpath}/Scripts"
declare -g mrsampath="${misterscripts}/.MiSTer_SAM"
declare -g mrsamtmp="/tmp/.SAM_tmp"
declare -g TTY_cmd_pipe="${mrsamtmp}/TTY_cmd_pipe"
compgen -v | sed s/=.\*// >/tmp/${samprocess}.tmp

#trap 'rc=$?;[ ${rc} = 0 ] && exit;tty_exit' EXIT TERM INT

#startup_tasks

	declare -g TTY_cmd_pipe="${mrsamtmp}/TTY_cmd_pipe"
	declare -gl ttyenable="Yes"
	declare -gi ttyupdate_pause=10
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
	declare -gi ttyscroll_speed=1
	declare -gi ttyscroll_speed_int=$((${ttyscroll_speed} - 1))



# ======== FUNCTIONS ========
samquiet=no

function write_to_TTY_cmd_pipe() {
	[[ -p ${TTY_cmd_pipe} ]] && echo "${@}" >${TTY_cmd_pipe}
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

# ======== tty2oled FUNCTIONS ========

function tty_init() { # tty_init
	# tty2oled initialization
	declare -gi START=$(date +%s)
	samquiet " Init tty2oled, loading variables... "
	source ${ttysystemini}
	source ${ttyuserini}
	ttydevice=${TTYDEV}
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

	# Stopping tty2oled Daemon
	if [ -f ${tty_sleepfile} ]; then
		sleepfile_expiration=$(<${tty_sleepfile})
		samdebug "! Expires: ${sleepfile_expiration} ! Now: ${EPOCHSECONDS} !"
		if [ ${sleepfile_expiration} -gt ${EPOCHSECONDS} ] && [ -s ${tty_currentinfo_file} ]; then
			write_to_TTY_cmd_pipe "display_info" &
		else
			rm ${tty_sleepfile}
		fi
	fi
	if [ ! -f ${tty_sleepfile} ]; then
		samquiet "-n" " Stopping tty2oled Daemon..."
		sleepfile_expiration=$((EPOCHSECONDS + (gametimer + 10)))
		echo "${sleepfile_expiration}" >${tty_sleepfile}
		samquiet " Done!"

		# Clear Serial input buffer first
		samquiet "-n" " Clear tty2oled Serial Input Buffer..."
		while read -t 0 sdummy <${ttydevice}; do continue; done
		samquiet " Done!"

		# Stopping ScreenSaver
		samquiet "-n" " Stopping tty2oled ScreenSaver..."
		[[ -c ${ttydevice} ]] && echo "CMDSAVER,0,0,0" >${ttydevice}
		tty_waitfor
		samquiet " Done!"

		tty_senddata "SAM_splash"
		# Wait for tty2oled to show the core logo
		samdebug "-------------------------------------------"
		samdebug " tty_update got Corename: SAM_splash "
		# Show Core-Logo for 5 Secs
		sleep 5
		if [ -z ${tty_currentinfo} ] && [ -s ${tty_currentinfo_file} ]; then
			write_to_TTY_cmd_pipe "display_info" &
		fi
	fi
	if [ "${samdebug}" == "yes" ]; then
		vardebug_out
	fi
}

function tty_exit() {
	# Clear Display	with Random effect
	[[ -c ${ttydevice} ]] && echo "CMDCLST,-1,0" >${ttydevice}
	tty_waitfor
	[[ -c ${ttydevice} ]] && echo "CMDBYE" >${ttydevice}
	sleep 5
	tty_cleanup
}

function tty_waitfor() {
	[[ -c ${ttydevice} ]] && read -t 10 -d ";" ttyresponse <${ttydevice} # Read now with Timeout and without "loop"
	ttyresponse=""
}

function update_loop() {
	while [[ -p ${TTY_cmd_pipe} ]]; do
		sleep 1
		write_to_TTY_cmd_pipe "update_counter" &
	done
}

function set_scroll_speed() {
	ttyscroll_speed_int=$((${ttyscroll_speed} - 1))
}

function update_name_scroll() {
	if [ ${ttyscroll_speed} -gt 0 ]; then
		if [ ${#tty_currentinfo[name]} -gt 21 ]; then
			if [ ${ttyscroll_speed_int} -gt 0 ]; then
				((ttyscroll_speed_int--))
			else
				set_scroll_speed
				if [ ${tty_currentinfo[name_scroll_direction]} -eq 1 ]; then
					if [ ${tty_currentinfo[name_scroll_position]} -lt $((${#tty_currentinfo[name]} - 21)) ]; then
						((tty_currentinfo[name_scroll_position]++))
					else
						tty_currentinfo[name_scroll_direction]=0
					fi
				elif [ ${tty_currentinfo[name_scroll_direction]} -eq 0 ]; then
					if [ ${tty_currentinfo[name_scroll_position]} -gt 0 ]; then
						((tty_currentinfo[name_scroll_position]--))
					else
						tty_currentinfo[name_scroll_direction]=1
					fi
				fi
				tty_currentinfo[name_scroll]="${tty_currentinfo[name]:${tty_currentinfo[name_scroll_position]}:21}"
				[[ -c ${ttydevice} ]] && echo "CMDTXT,103,0,0,0,20,${prev_name_scroll}" >${ttydevice}
				[[ -c ${ttydevice} ]] && echo "CMDTXT,103,15,0,0,20,${tty_currentinfo[name_scroll]}" >${ttydevice}
				prev_name_scroll="${tty_currentinfo[name_scroll]}"
			fi
		fi
	fi
}

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
	#if [ ${samtrace} == "yes" ]; then
	#	declare -p tty_currentinfo | sed 's/declare -A tty_currentinfo=//g'
	#fi
}

function tty_display() { # tty_update core game
	if [ -s ${tty_currentinfo_file} ]; then
		source "${tty_currentinfo_file}"
		sleepfile_expiration=$((tty_currentinfo[date] + (tty_currentinfo[counter] + 10)))
		echo "${sleepfile_expiration}" >${tty_sleepfile}
		# Wait for tty2oled daemon to show the core logo
		tty_senddata "${tty_currentinfo[core]}"
		# Wait for tty2oled to show the core logo
		samdebug "-------------------------------------------"
		samdebug " tty_update got Corename: ${tty_currentinfo[core]} "
		# Show Core-Logo for 5 Secs
		sleep 5
		# Clear Display	with Random effect
		echo "CMDCLST,-1,0" >"${ttydevice}"
		tty_waitfor
		local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
		tty_currentinfo[counter]=$((gametimer - elapsed))
		[[ -c ${ttydevice} ]] && echo "CMDTXT,103,15,0,0,20,${tty_currentinfo[name_scroll]}" >${ttydevice}
		[[ -c ${ttydevice} ]] && echo "CMDTXT,102,5,0,0,40,${tty_currentinfo[core_pretty]}" >${ttydevice}
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

# ========= TTY MONITOR =========
function tty_monitor_new() {
	# We can omit -r here. Tradeoff;
	# window size size is correct, can disconnect with ctrl-C but ctrl-C kills MCP
	# tmux attach-session -t SAM
	# window size will be wrong/too small, but ctrl-c nonfunctional instead of killing/disconnecting
	tmux attach-session -t TTY
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
