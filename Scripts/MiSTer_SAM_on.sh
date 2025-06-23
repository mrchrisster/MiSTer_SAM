function build_stvmralist() {

	# If no MRAs found - suicide!
	find /media/fat/_Arcade/_ST-V -type f \( -iname "*.mra" \) &>/dev/null
	if [ ! ${?} == 0 ]; then
		echo " The path _Arcade/_ST-V contains no MRA files!"
		loop_core
	fi	
	
	find "/media/fat/_Arcade/_ST-V" -not -path '*/.*' -type f \( -iname "*.mra" \) > "${gamelistpath}/stv_gamelist.txt"
	cp "${gamelistpath}/stv_gamelist.txt" "${gamelistpathtmp}/stv_gamelist.txt" 2>/dev/null

}

function load_core_stv() {

	# Check if the MRA list is empty or doesn't exist - if so, make a new list

	if [ ! -s "${gamelistpath}/stv_gamelist.txt" ]; then
		samdebug "Rebuilding mra list."
		build_stvmralist 
	fi
	
	#Check blacklist and copy gamelist to tmp
	if [ ! -s "${gamelistpathtmp}/stv_gamelist.txt" ]; then
		cp "${gamelistpath}/stv_gamelist.txt" "${gamelistpathtmp}/stv_gamelist.txt" 2>/dev/null
		
		filter_list stv
		
	fi
	
	sed -i '/^$/d' "${gamelistpathtmp}/stv_gamelist.txt"
	
	
	#samvideo mode
	if [ "$samvideo" == "yes" ] && [ "$samvideo_tvc" == "yes" ] && [ -f /tmp/.SAM_tmp/sv_gamename ]; then
		mra="$(cat ${gamelistpathtmp}/"stv"_gamelist.txt | grep -if /tmp/.SAM_tmp/sv_gamename | shuf -n 1)"
		if [ -z "${mra}" ]; then
			samdebug "Error with picking the corresponding game for the commercial. Playing random game now."
			mra="$(cat ${gamelistpathtmp}/"stv"_gamelist.txt | shuf --random-source=/dev/urandom --head-count=1)"
		fi
		sleep 5   #anything lower than 5 doesn't work
	else
		# Get a random game from the list
		mra="$(shuf --random-source=/dev/urandom --head-count=1 ${gamelistpathtmp}/stv_gamelist.txt)"
	fi
	
	# Check if Game exists
	if [ ! -f "${mra}" ]; then
		build_stvmralist 
		mra=$(shuf --random-source=/dev/urandom --head-count=1 ${gamelistpathtmp}/stv_gamelist.txt)
	fi
	
	
	#mraname="$(basename "${mra}" | sed -e 's/\.[^.]*$//')"	
	mraname="$(basename "${mra//.mra/}")"
	mrasetname=$(grep "<setname>" "${mra}" | sed -e 's/<setname>//' -e 's/<\/setname>//' | tr -cd '[:alnum:]')
	tty_corename="${mrasetname}"

	samdebug "Selected file: ${mra}"

	# Delete mra from list so it doesn't repeat
	if [ "${norepeat}" == "yes" ]; then
		awk -vLine="$mra" '!index($0,Line)' "${gamelistpathtmp}/stv_gamelist.txt" >${tmpfile} && cp -f ${tmpfile} "${gamelistpathtmp}/stv_gamelist.txt"
	fi
	
	mute "${mrasetname}"

	#BGM title
	if [ "${bgm}" == "yes" ]; then
		streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
	fi



	echo -n "Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[stv]}\e[0m: "
	echo -e "\e[1m${mraname}\e[0m"
	[[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"
	echo "$(date +%H:%M:%S) - Arcade - ${mraname}" >>/tmp/SAM_Games.log
	echo "${mraname} (stv)" >/tmp/SAM_Game.txt
	

	#TTY2OLED
	
	if [[ -n "$streamtitle" ]]; then
		gamename="${mraname} - BGM: ${streamtitle}"
	fi
	
	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			[core_pretty]="${CORE_PRETTY[stv]}"
			[name]="${mraname}"
			[core]=${tty_corename}
			[date]=$EPOCHSECONDS
			[counter]=${gametimer}
			[name_scroll]="${mraname:0:21}"
			[name_scroll_position]=0
			[name_scroll_direction]=1
			[update_pause]=${ttyupdate_pause}
		)
		declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
		write_to_TTY_cmd_pipe "display_info" &
		local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
		SECONDS=${elapsed}
	fi
	
	# Tell MiSTer to load the next MRA
	echo "load_core ${mra}" >/dev/MiSTer_cmd
	
	sleep 1
	activity_reset
	

}

