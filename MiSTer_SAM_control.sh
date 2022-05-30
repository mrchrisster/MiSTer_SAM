#!/bin/bash

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/media/fat/linux:/media/fat/Scripts:/media/fat/Scripts/.MiSTer_SAM:.

# ======== GLOBAL VARIABLES =========
declare cmd_pipe="/tmp/SAM_cmd_pipe"

function write_to_pipe() {
	if [[ ! -p ${cmd_pipe} ]]; then
		echo "SAM not running"
		exit 1
	fi
	echo "${1}" >${cmd_pipe}
}
# we can actually combine commands together that are exact copies, like below, and, probably simplify this down to just
# write_to_pipe ${1} for everything coming in (need to add code, of course, to reject bad input, but, this is just for testing)
case "${1,,}" in
--stop | --quit)
    write_to_pipe ${1}
    ;;
--skip | --next)
	echo " Skipping to next game..."
    write_to_pipe ${1}
    ;;
*)
    echo " ERROR! ${1} is unknown."
    echo " Try $(basename -- ${0}) help"
    echo " Or check the Github readme."
    ;;
esac
