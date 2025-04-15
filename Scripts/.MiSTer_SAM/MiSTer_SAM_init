#!/bin/bash
#trap "" HUP
#trap "" TERM

#======== INI VARIABLES ========
# Change these in the INI file
#set -x
#======== GLOBAL VARIABLES =========
declare -g mrsampath="/media/fat/Scripts/.MiSTer_SAM"
declare -g misterpath="/media/fat"
declare -g gamelistpath="${mrsampath}/SAM_Gamelists"
declare -g gamelistpathtmp="/tmp/.SAM_List"
declare -g tmpfilefilter="/tmp/.SAM_List/tmpfilefilter"
declare -g tmpfile="/tmp/.SAM_List/tmpfile"
declare -g tmpfile2="/tmp/.SAM_List/tmpfile2"
declare -g saminit_log="/tmp/saminit.log"
declare -gl kids_safe
declare -gl unmute_on_boot

#========= PARSE INI =========
# Read INI, Check for mount point presence
while ! test -d /media/fat/
do
    sleep 1
    count=$(expr $count + 1)
    if test $count -eq 30; then
        echo " Mount timed out!"
        exit 1
    fi
done

if [ -f "${misterpath}/Scripts/MiSTer_SAM.ini" ]; then
	source "${misterpath}/Scripts/MiSTer_SAM.ini"
	IFS=',' read -ra corelist <<< "${corelist}"
	IFS=',' read -ra corelistall <<< "${corelistall}"
	grep "^[^#;]" < "${misterpath}/Scripts/MiSTer_SAM.ini" | grep "pathfilter=" | cut -f1 -d"=" | while IFS= read -r var; do
		declare -g "${var}"="${!var%/}"
	done
fi

#======== DEBUG VARIABLES ========
samquiet="Yes"

# Kill running process
pids=$(pidof -o $$ $(basename -- "${0}"))
if [ -n "$pids" ]; then
    echo -n " Removing other instances of $(basename -- "${0}")..."
    kill -9 ${pids} &>/dev/null
    wait ${pids} &>/dev/null
    echo " Done!"
fi

# Kill old activity processes
echo -n " Stopping activity monitoring..."
killall -q -9 MiSTer_SAM_joy.py 2>/dev/null
killall -q -9 MiSTer_SAM_mouse.py 2>/dev/null
killall -q -9 MiSTer_SAM_keyboard.py 2>/dev/null
kill -9 $(ps -o pid,args | grep "inotifywait" | grep "SAM_Joy_Change" | { read -r PID COMMAND; echo "$PID"; }) 2>/dev/null
echo " Done!"

#========= PREP =========
mkdir -p "${gamelistpathtmp}"
#Unmute MiSTer
if [ "${unmute_on_boot}" == "yes" ]; then
	echo "volume unmute" > /dev/MiSTer_cmd
fi

#======== Local Functions Unique to the Init Script ========
function start() {
    #======== Start ========
    echo -n " Starting SAM..."
    ${misterpath}/Scripts/MiSTer_SAM_on.sh bootstart
}

function stop() {
    echo -n " Stopping SAM MCP..."
    pids=$(pidof MiSTer_SAM_MCP)
    if [ -n "${pids}" ]; then
        kill -9 ${pids} &>/dev/null
        wait ${pids} &>/dev/null
    fi
    echo " Done!"

    echo -n " Stopping SAM..."
    pids=$(pidof MiSTer_SAM_on.sh)
    if [ -n "${pids}" ]; then
        kill -9 ${pids} &>/dev/null
        wait ${pids} &>/dev/null
    fi
    echo " Done!"
}

#======== DEBUG OUTPUT =========
if [ "${samquiet,,}" == "no" ]; then
    echo "********************************************************************************"
    echo " mrsampath: ${mrsampath}"
    echo " misterpath: ${misterpath}"
    echo " samtimeout: ${samtimeout}"
    echo " menuonly: ${menuonly}"
    echo "********************************************************************************"
fi

# Start Gamelist filter (run in background)


# Parse command line arguments for init actions
case "${1,,}" in
    start)
        start
        ;;
    quickstart)
        quickstart
        ;;      
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    *)
        echo " Usage: /media/fat/Scripts/.MiSTer_SAM/MiSTer_SAM_init {start|stop|restart}"
        exit 1
        ;;
esac
exit 0
