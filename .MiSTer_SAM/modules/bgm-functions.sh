# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function bgm_start() {

	if [ "${bgm}" == "yes" ]; then
		if [ ! "$(ps -o pid,args | grep '[b]gm' | head -1)" ]; then
			/media/fat/Scripts/bgm.sh &>/dev/null &
			sleep 2
		else
			echo "BGM already running."
		fi
		echo -n "set playincore yes" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
		sleep 1
		echo -n "set playback random" | socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
		sleep 1
		echo -n "play" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null

	else
		# In case BGM is running, let's stop it
		if [ "$(ps -o pid,args | grep '[b]gm' | head -1)" ]; then
			bgm_stop force
		fi
	fi


}

function bgm_stop() {

	if [ "${bgm}" == "yes" ] || [ "$1" == "force" ]; then
		echo -n "Stopping Background Music Player... "
		echo -n "set playincore no" | timeout 1s socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
		echo -n "stop" | timeout 1s socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
		sleep 0.2
		if [ "${bgmstop}" == "yes" ]; then
			echo -n "stop" | timeout 1s socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
			sleep 0.2
			echo -n "set playback disabled" | timeout 1s socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
			kill -9 "$(ps -o pid,args | grep '[b]gm.sh' | awk '{print $1}' | head -1)" 2>/dev/null
			kill -9 "$(ps -o pid,args | grep 'mpg123' | awk '{print $1}' | head -1)" 2>/dev/null
			rm /tmp/bgm.sock 2>/dev/null
			if [ "${gvoladjust}" -ne 0 ]; then
				#local oldvol=$((7 - $currentvol + $gvoladjust))
				#samdebug "Changing global volume back to $oldvol"
				#echo "volume ${oldvol}" > /dev/MiSTer_cmd &
				echo -e "\00$currentvol\c" >"${configpath}/Volume.dat"
			fi
		fi
		echo "Done."
	fi

}
