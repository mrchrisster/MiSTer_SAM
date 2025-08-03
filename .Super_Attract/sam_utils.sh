#!/bin/bash

# This library contains miscellaneous helper, utility, and operational functions.

# --- Initialization and Setup ---

# Sets all default global variables for the script.
function init_vars() {
	declare -g mrsampath="/media/fat/Scripts/.Super_Attract"
	declare -g misterpath="/media/fat"
	declare -g mrsamtmp="/tmp/.sam_tmp"
	# Save our PID and process
	declare -g sampid="${$}"
	declare -g samprocess
	samprocess="$(basename -- "${0}")"
	declare -g menuonly="Yes"
	declare -g key_activity_file="/tmp/.sam_tmp/SAM_Keyboard_Activity"
	declare -g joy_activity_file="/tmp/.sam_tmp/SAM_Joy_Activity"
	declare -g mouse_activity_file="/tmp/.sam_tmp/SAM_Mouse_Activity"
	declare -g sam_menu_file="/tmp/.sammenu"
	declare -g brfake="/tmp/.sam_tmp/brfake"
	declare -g samini_file="/media/fat/Scripts/Super_Attract_Mode.ini"
	declare -g samini_update_file="${mrsampath}/Super_Attract_Mode.default.ini"
	declare -gi inmenu=0
	declare -gi MENU_LOADED=0
	declare -gi sam_bgmmenu=0					  
	declare -gi shown=0
	declare -gi coreretries=3
	declare -gi romloadfails=0
	declare -g gamelistpath="${mrsampath}/lists/games"
	declare -g gamelistpathtmp="/tmp/.sam_list"
	declare -g tmpfile="/tmp/.sam_list/tmpfile"
	declare -g tmpfile2="/tmp/.sam_list/tmpfile2"
	declare -g tmpfilefilter="/tmp/.sam_list/tmpfilefilter"
	declare -g corelistfile="/tmp/.sam_list/corelist"
	declare -g core_count_file="/tmp/.sam_tmp/sv_corecount"	
	declare -gi disablecoredel="0"	
	declare -gi gametimer=120
	declare -gl corelist="amiga,amigacd32,ao486,arcade,atari2600,atari5200,atari7800,atarilynx,c64,cdi,coco2,fds,gb,gbc,gba,genesis,gg,jaguar,megacd,n64,neogeo,neogeocd,nes,s32x,saturn,sgb,sms,snes,stv,tgfx16,tgfx16cd,psx,x68k"
	declare -gl corelistall="${corelist}"
	declare -gl skipmessage="Yes"
	declare -gl disablebootrom="no"
	declare -gl skiptime="10"
	declare -gl norepeat="Yes"
	declare -gl disable_blacklist="No"
	declare -gl disablebootrom="Yes"
	declare -gl amigaselect="All"
	declare -gl m82="no"
	declare -gl sam_goat_list="no"
	declare -gl mute="No"
	declare -gi update_done=0
	declare -gl ignore_when_skip="no"
	declare -gl coreweight="No"
	declare -gi gamelists_created=0
	declare -gl playcurrentgame="No"
	declare -gl kids_safe="No"
	declare -gl rating="No"
	declare -gl dupe_mode="normal"
	declare -gl listenmouse="Yes"
	declare -gl listenkeyboard="Yes"
	declare -gl listenjoy="Yes"
	declare -g repository_url="https://github.com/mrchrisster/Super_Attract_Mode"
	declare -g branch="main"
	declare -g raw_base="https://raw.githubusercontent.com/mrchrisster/Super_Attract_Mode/${branch}"
	declare -gi counter=0
	declare -gA corewc
	declare -gA corep
	declare -g userstartup="/media/fat/linux/user-startup.sh"
	declare -g userstartuptpl="/media/fat/linux/_user-startup.sh"
	declare -gl useneogeotitles="Yes"
	declare -gl arcadeorient
	declare -gl checkzipsondisk="Yes"
	declare -gi bootsleep="60"
	declare -gi totalgamecount		
	# ======== DEBUG VARIABLES ========
	declare -gl samdebug="No"
	declare -gl samdebuglog="No"						
	# ======== BGM =======
	declare -gl bgm="No"
	declare -gl bgmplay="Yes"
	declare -gl bgmstop="Yes"
	declare -gi gvoladjust="0"
	
	# ======== TTY2OLED =======
	declare -g TTY_cmd_pipe="${mrsamtmp}/TTY_cmd_pipe"
	declare -gl ttyenable="No"
	declare -gi ttyupdate_pause=10
	declare -g tty_currentinfo_file=${mrsamtmp}/tty_currentinfo
	declare -g tty_sleepfile="/tmp/tty2oled_sleep"
	declare -gl ttyname_cleanup="no"
	declare -gA tty_currentinfo=(
		[core_pretty]=""
		[name]=""
		[core]=""
		[date]=0
		[counter]=0
		[name_scroll]=""
		[name_scroll_position]=0
		[name_scroll_direction]=1
		[update_pause]=${ttyupdate_pause}
	)
	
	# ======== SAMVIDEO =======
	declare -gA SV_TVC_CL
	declare -gl samvideo
	declare -gl samvideo_freq
	declare -gl samvideo_output="hdmi"
	declare -gl samvideo_source
	declare -gl samvideo_tvc
	declare -gl download_manager="yes"
	declare -gl sv_aspectfix_vmode
	declare -gl sv_inimod="yes"
	declare -gl sv_inibackup="yes" 
	declare -g sv_inibackup_file="/media/fat/MiSTer.ini.sam_backup"
	declare -g samvideo_crtmode="video_mode=640,16,64,80,240,1,3,14,12380"
	declare -g samvideo_displaywait="2"
	declare -g tmpvideo="/tmp/SAMvideo.mp4"
	declare -g ini_file="/media/fat/MiSTer.ini"
	declare -g ini_contents=$(cat "$ini_file")
	declare -g sv_core="/tmp/.sam_tmp/sv_core"
	declare -g sv_gametimer_file="/tmp/.sam_tmp/sv_gametimer"
	declare -g sv_loadcounter=0
	declare -g samvideo_path="/media/fat/video"
	declare -g sv_archive_hdmilist="https://archive.org/download/640x480_videogame_commercials/640x480_videogame_commercials_files.xml"
	declare -g sv_archive_crtlist="https://archive.org/download/640x240_videogame_commercials/640x240_videogame_commercials_files.xml"
	declare -g sv_youtube_hdmilist="${mrsampath}/sv_yt360_list.txt"
	declare -g sv_youtube_crtlist="${mrsampath}/sv_yt240_list.txt"
	
	
	# SPECIAL CORES
	if [[ "${corelist[@]}" == *"amiga"* ]] || [[ "${corelist[@]}" == *"amigacd32"* ]] || [[ "${corelist[@]}" == *"ao486"* ]] && [ -f "${mrsampath}"/samindex ]; then
		declare -g amigapath="$("${mrsampath}"/samindex -q -s amiga -d |awk -F':' '{print $2}')"
		declare -g amigacore="$(find /media/fat/_Computer/ -iname "*minimig*")"
		declare -g amigacd32path="$("${mrsampath}"/samindex -q -s amigacd32 -d |awk -F':' '{print $2}')"
		declare -g ao486path="$("${mrsampath}"/samindex -q -s ao486 -d |awk -F':' '{print $2}')"
	fi
	
	
	special_cores=(amiga ao486 x68k) #amigacd32 uses normal gamelists since it's chd files
	
	# ======= MiSTer.ini AITORGOMEZ FORK =======  
	declare -g cfgcore_configpath=$(
		awk -F '=' '
			BEGIN { found = 0 }
			/^cfgcore_subfolder[[:space:]]*=/ {
				if (!found) {
					print "/media/fat/config/" $2;
					found = 1
				}
			}
			END {
				if (!found) print ""
			}
		' "$ini_file" | tr -d '"' | sed -e 's|//|/|g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
	)
	declare -g cfgarcade_configpath=$(
		awk -F '=' '
			BEGIN { found = 0 }
			/^cfgarcade_subfolder[[:space:]]*=/ {
				if (!found) {
					print "/media/fat/config/" $2;
					found = 1
				}
			}
			END {
				if (!found) print ""
			}
		' "$ini_file" | tr -d '"' | sed -e 's|//|/|g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
	)

	if [[ -n "$cfgcore_configpath" ]]; then
		declare -g configpath="$cfgcore_configpath"
	else
		declare -g configpath="/media/fat/config/"
	fi

}

# Reads the user's INI file and applies the settings.
function read_samini() {
	if [ ! -f "${samini_file}" ]; then
		echo "Error: Super_Attract_Mode.ini not found."
		return 1
	fi
	source "${samini_file}"
	
	# Convert comma-separated corelist string to an array
	IFS=',' read -ra corelist <<< "${corelist}"
	IFS=',' read -ra corelistall <<< "${corelistall}"

	# Special mode overrides
	if [ "${bgm}" == "yes" ]; then
		local new_corelist=()
		for core in "${corelist[@]}"; do
			if [[ "$core" != "n64" && "$core" != "psx" ]]; then
				new_corelist+=("$core")
			fi
		done
		corelist=("${new_corelist[@]}")
		mute="core"
	fi
}

# Creates all necessary temporary directories.
function init_paths() {
	mkdir -p "${mrsampath}/lists/games"
	mkdir -p /tmp/.sam_list
	mkdir -p /tmp/.sam_tmp
	touch "${tmpfile}"
}

# --- Main Operational Functions ---

# The interactive countdown timer that runs between games.
function run_countdown_timer() {
    local counter=${gametimer}
    local prepared_next=0 # Flag to ensure we only prepare once
    local prepare_at_time=$((gametimer - 5)) # Trigger prep 5s after start

    trap 'echo; return' INT

    while [ ${counter} -gt 0 ]; do
        # When the counter reaches our designated time, start the background prep.
        if (( ! prepared_next && counter <= prepare_at_time )); then
            prepared_next=1
            samdebug "Countdown reached ${counter}s. Starting background prep..."
            pick_core
            (
                samdebug "Preparing gamelist for upcoming core '${nextcore}'..."
                check_list "${nextcore}"
                filter_list "${nextcore}"
            ) &
        fi

        echo -ne " Next game in ${counter}...\033[0K\r"
        sleep 1
        ((counter--))
        
        # Check for user activity (mouse, keyboard, joystick)
        if [ -s "$mouse_activity_file" ] && [ "${listenmouse}" == "yes" ]; then
            echo "Mouse activity detected!"; truncate -s 0 "$mouse_activity_file"; play_or_exit & return
        fi
        if [ -s "$key_activity_file" ] && [ "${listenkeyboard}" == "yes" ]; then
            echo "Keyboard activity detected!"; truncate -s 0 "$key_activity_file"; play_or_exit & return
        fi
        if [ -s "$joy_activity_file" ] && [ "${listenjoy}" == "yes" ]; then
            handle_joy_activity
            if [ $? -eq 1 ]; then return; fi
        fi
    done

    trap - INT
}

# Handles specific joystick button presses during the countdown.
function handle_joy_activity() {
    local joy_action
    joy_action=$(cat "$joy_activity_file")
    truncate -s 0 "$joy_activity_file"

    case "${joy_action}" in
        "Start" | "zaparoo")
            samdebug "'${joy_action}' button pushed. Exiting SAM."
            [[ "$joy_action" == "zaparoo" ]] && mute="yes"
            playcurrentgame="yes"
            play_or_exit &
            return 1 # Signal to exit countdown
            ;;
        "Next")
            if [[ "$m82" == "yes" ]]; then
                local romname_lower="${romname,,}"
                if [[ "$romname_lower" != *"m82"* ]]; then
                    sed -i '1d' "${gamelistpathtmp}/nes_gamelist.txt"
                fi
                update_done=1
            else
                echo "Starting next Game"
                if [[ "$ignore_when_skip" == "yes" ]]; then ignoregame; fi
            fi
            return 1 # In both modes, "Next" breaks the countdown
            ;;
        *) # Default case for any other joystick activity
            if [[ "$m82" == "yes" ]]; then
                local romname_lower="${romname,,}"
                if [[ "$romname_lower" != *"m82"* ]] && (( ! update_done )); then
                    if [[ "$m82_muted" == "yes" ]]; then unmute; fi
                    counter=$m82_game_timer
                    update_done=1
                fi
                return 0 # In M82 mode, other presses CONTINUE the countdown
            else
                play_or_exit &
                return 1 # In standard mode, other presses start the game
            fi
            ;;
    esac
}

# Handles the final exit from the script.
function play_or_exit() {
	sam_cleanup
	if [[ "${playcurrentgame}" == "yes" ]]; then
        # Reloads the last played game for the user.
        if [ "${nextcore}" == "arcade" ]; then
            echo "load_core ${rompath}" >/dev/MiSTer_cmd
        elif [ "${nextcore}" == "amiga" ]; then
            echo "${rompath}" > "${amigapath}/shared/ags_boot"
            echo "load_core ${amigacore}" >/dev/MiSTer_cmd
        else
            echo "load_core /tmp/SAM_Game.mgl" >/dev/MiSTer_cmd
        fi
	else
		# Returns to the MiSTer menu.
		echo "load_core /media/fat/menu.rbf" >/dev/MiSTer_cmd
		echo "Thanks for playing!"
	fi
	bgm_stop
	tty_exit
	# Kills all SAM-related processes.
	ps -ef | grep -i '[S]upser_Attract_Mode.sh' | xargs --no-run-if-empty kill &>/dev/null
}

# --- Command Parsing and Menus ---

# The main command-line argument parser.
function parse_cmd() {
    (( $# == 0 )) && { sam_premenu; return; }
    local first="${1,,}"; shift
    if [[ -n ${CORE_PRETTY[$first]} ]]; then
        tmp_reset
        echo "$first" > "${gamelistpathtmp}/corelist.single"
        echo "${CORE_PRETTY[$first]} selected!"
        sam_start "$first"
        return
    fi
    case "$first" in
        start|restart)      sam_start "$@" ;;
        startmonitor|sm)    sam_start "$@"; sleep 1; sam_monitor ;;
        skip|next)          echo "Skipping…"; tmux send-keys -t SAM C-c ENTER ;;
        stop|kill)          tmp_reset; parse_cmd juststop ;;
        update)             sam_update ;;
        monitor)            sam_monitor ;;
        playcurrent)        playcurrentgame=yes; play_or_exit ;;
        juststop)           kill_all_sams; playcurrentgame=no; play_or_exit ;;
        enable)             env_check enable; sam_enable ;;
        disable)            sam_cleanup; sam_disable ;;
        ignore)             ignoregame ;;
        menu|back)          sam_menu ;;
        help)               sam_help ;;
        loop_core)          loop_core "$@" ;; # <-- FIX: Added internal command
        *)
            echo "Unknown command: $first" >&2
            sam_help
            return 1
            ;;
    esac
}

function sam_menu() {
    load_menu_if_needed
    while true; do
        dialog --clear --ascii-lines --no-tags \
               --ok-label "Select" --cancel-label "Exit" \
               --backtitle "Super Attract Mode" --title "[ Main Menu ]" \
               --menu "Use arrow keys or d-pad to navigate" 0 0 0 \
                 Start              "Start SAM" \
                 Startmonitor       "Start + Monitor (SSH)" \
                 Stop               "Stop SAM" \
                 Skip               "Skip Game" \
                 Update             "Update to latest" \
                 Ignore             "Ignore current game" \
                 separator          "-----------------------------" \
                 menu_presets       "Presets & Game Modes" \
                 menu_coreconfig    "Configure Core List" \
                 menu_exitbehavior  "Configure Exit Behavior" \
                 menu_controller    "Configure Gamepad" \
                 menu_filters       "Filters" \
                 menu_addons        "Add-ons" \
                 menu_inieditor     "Super_Attract_Mode.ini Editor" \
                 menu_settings      "Settings" \
                 menu_reset         "Reset or Uninstall SAM" \
                 2> "${sam_menu_file}"

        local rc=$? choice=$(<"${sam_menu_file}")
        clear
        (( rc != 0 )) && break
        
        if [[ "${choice,,}" == "separator" ]]; then
            continue
        fi
        
        parse_cmd "${choice,,}"

        case "${choice,,}" in
            start|startmonitor|stop|kill|skip|next|update|ignore) break ;;
        esac
    done
}

function sam_premenu() {
    echo "+---------------------------+"
    echo "| MiSTer Super Attract Mode |"
    echo "+---------------------------+"
    echo " SAM Configuration:"
    if grep -iq "mister_sam" "${userstartup}"; then
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
    echo " auto-start"
    echo ""
    local premenu="Start"
    for i in {10..1}; do
        echo -ne " Starting SAM in ${i} secs...\033[0K\r"
        read -r -s -N 1 -t 1 key
        case "$key" in
            A) premenu="Menu"; break ;;
            B) premenu="Start"; break ;;
            C) premenu="Default"; break ;;
        esac
    done
    echo
    parse_cmd "${premenu}"
}

function sam_sshconfig() {
	# Alias to be added
	alias_m='alias m="/media/fat/Scripts/Super_Attract_Mode.sh"'
	alias_ms='alias ms="source /media/fat/Scripts/Super_Attract_Mode.sh --source-only"'
	alias_u='alias u="/media/fat/Scripts/update_all.sh"'

	# Path to the .bash_profile
	bash_profile="${HOME}/.bash_profile"
	# Check if .bash_profile exists
	if [ ! -f "$bash_profile" ]; then
		touch "$bash_profile"
	fi
	   # Check if the alias already exists in the file
    if grep -Fxq "$alias_m" "$bash_profile"; then
        echo "Alias already exists in $bash_profile"
    else
        # Add the alias to .bash_profile
        echo "$alias_m" >> "$bash_profile"
		echo "$alias_ms" >> "$bash_profile"
		echo "$alias_u" >> "$bash_profile"
        echo "Alias added to $bash_profile. Please relaunch terminal. Type 'm' to start Super_Attract_Mode.sh"
    fi
	source ~/.bash_profile
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
	echo " deletegl - delete all game lists"
	echo " creategl - create all game lists" 
	echo ""
	echo " menu - load to menu"
	echo ""
	echo " arcade, genesis, gba..."
	echo " games from one system only"
	exit 2
}

# --- Startup and Shutdown ---

function sam_start() {
	local core="$1"
	env_check
	there_can_be_only_one
	update_samini	
	read_samini
	mcp_start
	sam_prep
	disable_bootrom
	bgm_start
	tty_start
	echo "Starting SAM in the background."
	
	[[ "$samvideo" == "yes" ]] && echo "Samvideo mode. Please wait for video to load"
	
	if tmux has-session -t SAM 2>/dev/null; then
		samdebug "SAM session already exists—skipping."
		return
	fi
	
	(
	    tmux new-session -d \
		 -x 180 -y 40 \
		 -n "-= SAM Monitor -- Detach with ctrl-b, then push d =-" \
		 -s SAM \
		 "${misterpath}/Scripts/Super_Attract_Mode.sh" loop_core "$core"
	) &
}

function corelist_update() {
	if [ -s "${gamelistpathtmp}/corelist.single" ]; then
		unset corelist
		mapfile -t corelist < "${gamelistpathtmp}/corelist.single"
		rm "${gamelistpathtmp}/corelist.single" "${gamelistpathtmp}/corelist}" > /dev/null 2>&1
		
	elif [ -s "${gamelistpathtmp}/corelist" ]; then
		unset corelist
		mapfile -t corelist < "${gamelistpathtmp}/corelist"
		rm "${gamelistpathtmp}/corelist"
	fi
		
	if [[ "${disablecoredel}" == "0" ]]; then
		delete_from_corelist "$nextcore" tmp
	fi
	
	if [ ${#corelisttmp[@]} -eq 0 ]; then
		declare -ga corelisttmp=("${corelist[@]}")
	fi

	if [[ ! "${corelisttmp[*]}" ]]; then
		corelisttmp=("${corelist[@]}")
	fi
}

function sam_monitor() {
    tmux attach-session -t SAM
}

function env_check() {
	if [ ! -f "${mrsampath}/tools/samindex" ] || [ ! -f "${mrsampath}/input/sam_mcp.sh" ]; then
		echo " SAM required files not found. Installing now."
		sam_update autoconfig
		echo " Setup complete."
	fi
}

function there_can_be_only_one() {
    echo "Stopping other running instances of ${samprocess}…"
    tmux kill-session -t SAM 2>/dev/null || true
    local patterns=(
        "Super_Attract_Mode.sh initial_start"
        "Super_Attract_Mode.sh loop_core"
        "Super_Attract_Mode.sh bootstart"
        "sam_init start"
    )
    local pat pid
    for pat in "${patterns[@]}"; do
        ps -o pid,args | grep "$pat" | grep -v grep | awk '{print $1}' | while read -r pid; do
            [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
        done
    done
    sleep 1
}

function update_samini() {
	[ ! -f /media/fat/Scripts/.config/downloader/downloader.log ] && return
	[ ! -f ${samini_file} ] && return
	if [[ "$(cat /media/fat/Scripts/.config/downloader/downloader.log | grep -c "Super_Attract_Mode.default.ini")" != "0" ]] && [ "${samini_update_file}" -nt "${samini_file}" ]; then
		echo "New Super_Attract_Mode.ini version downloaded. Merging with new ini."
		cp "${samini_file}" "${samini_file}".bak
		sed -i 's/==/--/g' "${samini_file}"
		sed -i 's/-=/--/g' "${samini_file}"
		awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' "${samini_file}" "${samini_update_file}" >/tmp/Super_Attract_Mode.tmp && cp -f --force /tmp/Super_Attract_Mode.tmp "${samini_file}"
		echo "Done."
	fi
}

function mcp_start() {
	if [ -z "$(pidof sam_mcp.sh)" ]; then
		tmux new-session -s MCP -d "${mrsampath}/input/sam_mcp.sh"
	fi
}

function sam_prep() {
	
	# samvideo and ratings filter can't both be set
	if [ "${rating}" == "yes" ]; then
		samvideo=no
	fi
	[ ! -d "/tmp/.sam_tmp/SAM_config" ] && mkdir -p "/tmp/.sam_tmp/SAM_config"
	[ ! -d "${misterpath}/video" ] && mkdir -p "${misterpath}/video"
	[[ -f /tmp/SAM_game.previous.mgl ]] && rm /tmp/SAM_game.previous.mgl
	[[ ! -d "${mrsampath}" ]] && mkdir -p "${mrsampath}"
	[[ ! -d "${mrsamtmp}" ]] && mkdir -p "${mrsamtmp}"
	mkdir -p /media/fat/Games/SAM &>/dev/null
	[ ! -d "/tmp/.sam_tmp/Amiga_shared" ] && mkdir -p "/tmp/.sam_tmp/Amiga_shared"
	if [ -d "${amigapath}/shared" ] && [ "$(mount | grep -ic "${amigapath}"/shared)" == "0" ]; then
		if [ "$(du -m "${amigapath}/shared" | cut -f1)" -lt 30 ]; then
			cp -r --force "${amigapath}"/shared/* /tmp/.sam_tmp/Amiga_shared &>/dev/null
			mount --bind "/tmp/.sam_tmp/Amiga_shared" "${amigapath}/shared"
		else
			echo "WARNING: ${amigapath}/shared folder is bigger than 30 MB. Items in shared folder won't be accessible while SAM is running."
			mount --bind "/tmp/.sam_tmp/Amiga_shared" "${amigapath}/shared"
		fi
	fi
	
	#Downloads rating lists and sets the corelist to match only cores with rated lists
	if [ "${kids_safe}" == "yes" ]; then
		rating="kids"
	fi

	if [ "${rating}" != "no" ]; then	
	    local missing=()

		# make sure the target dir exists
		mkdir -p "${mrsampath}/SAM_Rated"
		# check each expected file
		for f in "${RATED_FILES[@]}"; do
			if [[ ! -f "${mrsampath}/SAM_Rated/$f" ]]; then
				missing+=( "$f" )
			fi
		done
		if (( ${#missing[@]} )); then
			echo "Missing rating lists: ${missing[*]}"
			echo "Downloading..."
			if ! get_ratedlist; then
				echo "Ratings Filter failed downloading."
				return 1
			fi
		else
			echo "All rating lists present."
		fi

		#Set corelist to only include cores with rated lists
		# build glr from the files on disk
		if [ "${rating}" == "kids" ]; then
			readarray -t glr < <(
			  find "${mrsampath}/SAM_Rated" -name "*_rated.txt" \
				| awk -F'/' '{print $NF}' \
				| awk -F'_'  '{print $1}'
			)
		else
			readarray -t glr < <(
			  find "${mrsampath}/SAM_Rated" -name "*_mature.txt" \
				| awk -F'/' '{print $NF}' \
				| awk -F'_'  '{print $1}'
			)
		fi

		# intersect glr with corelist
		clr=()
		for g in "${glr[@]}"; do
		  for c in "${corelist[@]}"; do
			[[ "$c" == "$g" ]] && clr+=("$c")
		  done
		done

		# if no overlap, warn & use the full rated list
		if (( ${#clr[@]} == 0 )); then
		  echo "Warning: none of your enabled cores match the '${rating}' list."
		  echo "→ Falling back to ALL rated cores."
		  clr=( "${glr[@]}" )
		else
		  # otherwise show which cores have no rating file
		  readarray -t nclr < <(
			printf '%s\n' "${clr[@]}" "${corelist[@]}" \
			  | sort \
			  | uniq -iu
		  )
		  #echo "Rating lists missing for cores: ${nclr[*]}"
		fi

		# finally, write out the new corelist
		printf "%s\n" "${clr[@]}" > "${corelistfile}"

	fi
	
	[ "${coreweight}" == "yes" ] && echo "Weighted core mode active."
	[ "${samdebuglog}" == "yes" ] && rm /tmp/samdebug.log 2>/dev/null
	if [ "${samvideo}" == "yes" ]; then
		# Hide login prompt
		echo -e '\033[2J' > /dev/tty1
		# Hide blinking cursor
		echo 0 > /sys/class/graphics/fbcon/cursor_blink
		echo -e '\033[?17;0;0c' > /dev/tty1 
		
		misterini_mod
		get_dlmanager
		if [ ! -f "${mrsampath}"/mplayer ] || [ ! -f "${mrsampath}"/ytdl ]; then
			if [ -f "${mrsampath}"/mplayer.zip ]; then
				unzip -ojq "${mrsampath}"/mplayer.zip -d "${mrsampath}"
				curl_download "${mrsampath}"/ytdl "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_armv7l"
			else
				get_samvideo
			fi
		fi

		if { [ "$samvideo_source" == "local" ] || [ "$samvideo_source" == "youtube" ]; } && [ "$samvideo_tvc" == "yes" ]; then
			samini_mod samvideo_tvc no
		fi
	fi
	# Mute Global Volume
	# if Volume.dat exists, try to mute only if needed
	if [ "${mute}" != "no" ]; then
		if [ -f "${configpath}/Volume.dat" ]; then
		  only_mute_if_needed
	
		# if Volume.dat doesn’t exist yet, create it *and* mute
		else
		  # create a “level=0 + mute” byte = 0x10
		  write_byte "${configpath}/Volume.dat" "10"
		  echo "volume mute" > /dev/MiSTer_cmd
		  samdebug "Volume.dat created (0x10) and muted."
		fi
	fi
}

function sam_cleanup() {
	# Clean up by umounting any mount binds
	#[ -f "${configpath}/Volume.dat" ] && [ ${mute} == "yes" ] && rm "${configpath}/Volume.dat"
	only_unmute_if_needed
	[ "$(mount | grep -ic "${amigapath}"/shared)" == "1" ] && umount -l "${amigapath}/shared"
	[ -d "${misterpath}/Bootrom" ] && [ "$(mount | grep -ic 'bootrom')" == "1" ] && umount "${misterpath}/Bootrom"
	[ -f "${misterpath}/Games/NES/boot1.rom" ] && [ "$(mount | grep -ic 'nes/boot1.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot1.rom"
	[ -f "${misterpath}/Games/NES/boot2.rom" ] && [ "$(mount | grep -ic 'nes/boot2.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot2.rom"
	[ -f "${misterpath}/Games/NES/boot3.rom" ] && [ "$(mount | grep -ic 'nes/boot3.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot3.rom"
	if [ "${mute}" != "no" ]; then
		readarray -t volmount <<< "$(mount | grep -i _volume.cfg | awk '{print $3}')"
		if [ "${#volmount[@]}" -gt 0 ]; then
			umount -l "${volmount[@]}" >/dev/null 2>&1
		fi
	fi
	if [ "${samvideo}" == "yes" ]; then
		echo 1 > /sys/class/graphics/fbcon/cursor_blink
		echo 'Super Attract Mode Video was used.' > /dev/tty1 
		echo 'Please reboot for proper MiSTer Terminal' > /dev/tty1 
		echo '' > /dev/tty1 
		echo 'Login:' > /dev/tty1 
		[ -f /tmp/.sam_tmp/sv_corecount ] && rm /tmp/.sam_tmp/sv_corecount
		misterini_restore
	fi
	samdebug "Cleanup done."
}


function disable_bootrom() {
	if [ "${disablebootrom}" == "yes" ]; then
		# Make Bootrom folder inaccessible until restart
		mkdir -p /tmp/.sam_list/Bootrom
		[ -d "${misterpath}/Bootrom" ] && [ "$(mount | grep -ic 'bootrom')" == "0" ] && mount --bind /tmp/.sam_list/Bootrom "${misterpath}/Bootrom"
		# Disable Nes bootroms except for FDS Bios (boot0.rom)
		[ -f "${misterpath}/Games/NES/boot1.rom" ] && [ "$(mount | grep -ic 'nes/boot1.rom')" == "0" ] && touch "$brfake" && mount --bind "$brfake" "${misterpath}/Games/NES/boot1.rom"
		[ -f "${misterpath}/Games/NES/boot2.rom" ] && [ "$(mount | grep -ic 'nes/boot2.rom')" == "0" ] && touch "$brfake" && mount --bind "$brfake" "${misterpath}/Games/NES/boot2.rom"
		[ -f "${misterpath}/Games/NES/boot3.rom" ] && [ "$(mount | grep -ic 'nes/boot3.rom')" == "0" ] && touch "$brfake" && mount --bind "$brfake" "${misterpath}/Games/NES/boot3.rom"
	fi
}

# --- System Interaction ---

function mute() {
	if [ "${mute}" == "core" ]; then
		samdebug "mute=core"
		only_unmute_if_needed
		
		local mute_target="$1"
		[ ! -f "${configpath}/${mute_target}_volume.cfg" ] && touch "${configpath}/${mute_target}_volume.cfg"
		[ ! -f "/tmp/.sam_tmp/SAM_config/${mute_target}_volume.cfg" ] && touch "/tmp/.sam_tmp/SAM_config/${mute_target}_volume.cfg"		
		
		mount --bind "/tmp/.sam_tmp/SAM_config/${mute_target}_volume.cfg" "${configpath}/${mute_target}_volume.cfg"
		
		if [[ "$(mount | grep -ic "${mute_target}"_volume.cfg)" != "0" ]]; then
			echo -e "\0006\c" > "/tmp/.sam_tmp/SAM_config/${mute_target}_volume.cfg"
		fi
	fi
}

function write_byte() {
  local f="$1"; local hex="$2"
  printf '%b' "\\x$hex" > "$f" && sync
}

function global_mute() {
    local f="${configpath}/Volume.dat"
    local cur m hex
    cur=$(xxd -p -c1 "$f")
    m=$(( 0x$cur | 0x10 ))
    hex=$(printf '%02x' "$m")
    printf '%b' "\\x$hex" > "$f" && sync
    echo "volume mute" > /dev/MiSTer_cmd
    samdebug "WRITE TO SD: Global mute → Volume.dat"
}

function global_unmute() {
	local f="${configpath}/Volume.dat"
	local cur hex u
	cur=$(xxd -p -c1 "$f")
	u=$((0x$cur & 0x0F))
	hex=$(printf '%02x' "$u")
	write_byte "$f" "$hex"
	# sent unmute for interactive unmute
	echo "volume unmute" > /dev/MiSTer_cmd
	samdebug "WRITE TO SD: Restored Volume.dat"
}



function only_mute_if_needed() {
  local f="${configpath}/Volume.dat"
  local cur

  # 1) read the single byte as two hex digits, e.g. "05" or "15"
  cur=$(xxd -p -c1 "$f")

  # 2) test bit 4 (0x10).  If (cur & 0x10) == 0 then we’re not muted yet.
  if (( (0x$cur & 0x10) == 0 )); then
    samdebug "Volume not yet muted (Volume.dat=0x$cur) → muting now"
    global_mute
  else
    samdebug "Already muted (Volume.dat=0x$cur) → skipping write"
  fi
}


function only_unmute_if_needed() {
  local f="${configpath}/Volume.dat"
  local cur

  # 1) Read the single-byte value, e.g. "15" if muted at level5, or "05" if unmuted
  cur=$(xxd -p -c1 "$f")

  # 2) If bit4 (0x10) *is* set, we’re currently muted → clear it
  if (( (0x$cur & 0x10) != 0 )); then
    samdebug "Volume is muted (Volume.dat=0x$cur) → unmuting now"
    global_unmute
    return 0    # indicate we did an unmute
  else
    samdebug "Volume already unmuted (Volume.dat=0x$cur) → skipping write"
    return 1    # indicate no action taken
  fi
}



function tty_start() {
    if [ "${ttyenable}" == "yes" ]; then
        touch "${mrsamtmp}/tty_sleep"
        echo -n "Starting tty2oled... "
        tmux new -s OLED -d "${mrsampath}/sam_tty2oled" &>/dev/null
        echo "Done."
    fi
}

function tty_exit() {
	if [ "${ttyenable}" == "yes" ]; then
		echo -n "Stopping tty2oled... "
		[[ -p ${TTY_cmd_pipe} ]] && echo "stop" >${TTY_cmd_pipe} &
		tmux kill-session -t OLED &>/dev/null
		rm "${tty_sleepfile}" &>/dev/null
		#/media/fat/tty2oled/S60tty2oled restart 
		#sleep 5

		echo "Done."
	fi
}

function bgm_start() {
    if [ "${bgm}" == "yes" ]; then
        if [ ! "$(ps -o pid,args | grep '[b]gm' | head -1)" ]; then
            /media/fat/Scripts/bgm.sh &>/dev/null &
            sleep 2
        fi
        echo -n "set playincore yes" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
        sleep 1
        echo -n "play" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
    fi
}

function bgm_stop() {

	if [ "${bgm}" == "yes" ] || [ "$1" == "force" ]; then
		echo -n "Stopping Background Music Player... "
		echo -n "set playincore no" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
		echo -n "stop" | socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
		sleep 0.2
		if [ "${bgmstop}" == "yes" ]; then
			echo -n "stop" | socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
			sleep 0.2
			echo -n "set playback disabled" | socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
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


# --- Updating ---

function sam_update() { # sam_update (next command)

	if ping -4 -q -w 1 -c 1 github.com > /dev/null; then 
		echo " Connection established"
	else
		echo "No connection to Github. Please use offline install."
		sleep 5
		#exit 1
	fi
	
	# Ensure the MiSTer SAM data directory exists
	mkdir --parents "${mrsampath}" &>/dev/null
	mkdir --parents "${mrsampath}/SAM_Rated" &>/dev/null
	mkdir --parents "${gamelistpath}" &>/dev/null

	if [ ! "$(dirname -- "${0}")" == "/tmp" ]; then
		# Warn if using non-default branch for updates
		if [ ! "${branch}" == "main" ]; then
			echo ""
			echo "*******************************"
			echo " Updating from ${branch}"
			echo "*******************************"
			echo ""
		fi

		# Download the newest Super_Attract_Mode.sh to /tmp
		get_samstuff Super_Attract_Mode.sh /tmp
		if [ -f /tmp/Super_Attract_Mode.sh ]; then
			if [ "${1}" ]; then
				echo " Continuing setup with latest Super_Attract_Mode.sh..."
				/tmp/Super_Attract_Mode.sh "${1}"
				exit 0
			else
				echo " Launching latest"
				echo " Super_Attract_Mode.sh..."
				/tmp/Super_Attract_Mode.sh update
				exit 0
			fi
		else
			# /tmp/Super_Attract_Mode.sh isn't there!
			echo " SAM update FAILED"
			echo " No Internet?"
			exit 1
		fi
	else # We're running from /tmp - download dependencies and proceed
		cp --force "/tmp/Super_Attract_Mode.sh" "/media/fat/Scripts/Super_Attract_Mode.sh"

		get_partun
		get_samindex
		get_mbc
		#get_samstuff .Super_Attract_Mode/Super_Attract_Mode.default.ini
		get_samstuff .Super_Attract_Mode/Super_Attract_Mode_init
		get_samstuff .Super_Attract_Mode/Super_Attract_Mode_MCP
		get_samstuff .Super_Attract_Mode/Super_Attract_Mode_menu.sh
		get_samstuff .Super_Attract_Mode/Super_Attract_Mode_tty2oled
		get_samstuff .Super_Attract_Mode/Super_Attract_Mode_joy.py
		if [ ! -f "${mrsampath}/sam_controllers.json" ]; then
			get_samstuff .Super_Attract_Mode/sam_controllers.json
		fi
		if [ "${samvideo}" == "yes" ]; then
			get_samvideo
		fi
		get_samstuff .Super_Attract_Mode/Super_Attract_Mode_keyboard.py
		get_samstuff .Super_Attract_Mode/Super_Attract_Mode_mouse.py
		get_inputmap
		get_blacklist
		get_ratedlist
		get_samstuff Super_Attract_Mode_off.sh /media/fat/Scripts
		

		if [ -f "${samini_file}" ]; then
			echo " MiSTer SAM INI already exists... Merging with new ini."
			get_samstuff Super_Attract_Mode.ini /tmp
			echo " Backing up Super_Attract_Mode.ini to Super_Attract_Mode.ini.bak"
			cp "${samini_file}" "${samini_file}".bak
			echo -n " Merging ini values.."
			# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
			sed -i 's/==/--/g' "${samini_file}"
			sed -i 's/-=/--/g' "${samini_file}"
			awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' "${samini_file}" /tmp/Super_Attract_Mode.ini >/tmp/Super_Attract_Mode.tmp && cp -f --force /tmp/Super_Attract_Mode.tmp "${samini_file}"
			echo "Done."

		else
			get_samstuff Super_Attract_Mode.ini /media/fat/Scripts
		fi
		
	fi

	echo " Update complete!"
	return
	
	mcp_start

	if [ ${inmenu} -eq 1 ]; then
		sleep 1
		sam_menu
	fi

}


function get_samstuff() {
	local file="$1"
	local filepath="${2:-$mrsampath}"
	echo -n " Downloading from ${raw_base}/${file} to ${filepath}/..."
	curl --connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
		--insecure --fail -L -o "/tmp/${file##*/}" "${raw_base}/${file}"
	
	if [ $? -eq 0 ]; then
		mv --force "/tmp/${file##*/}" "${filepath}/${file##*/}"
		if [ "${file##*.}" == "sh" ]; then
			chmod +x "${filepath}/${file##*/}"
		fi
		echo " Done."
	else
		echo " FAILED."
		return 1
	fi
}

# ... (and all other get_* functions: get_samindex, get_samvideo, etc.) ...

# --- Miscellaneous Helpers ---

function samdebug() {
    local ts msg
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    msg="$*"
    if [[ "${samdebug}" == "yes" ]]; then
        echo -e "\e[1m\e[31m[${ts}] ${msg}\e[0m" >&2
    fi
    if [[ "${samdebuglog}" == "yes" ]]; then
        echo "[${ts}] ${msg}" >> /tmp/samdebug.log
    fi
}

function delete_from_corelist() {
    local core_to_delete="$1"
    local list_to_modify="$2"
    
    if [ -z "$list_to_modify" ]; then
        local new_corelist=()
        for core in "${corelist[@]}"; do
            if [[ "$core" != "$core_to_delete" ]]; then
                new_corelist+=("$core")
            fi
        done
        corelist=("${new_corelist[@]}")
        samdebug "Deleted $core_to_delete from corelist"
    else
        local new_corelist_tmp=()
        for core in "${corelisttmp[@]}"; do
            if [[ "$core" != "$core_to_delete" ]]; then
                new_corelist_tmp+=("$core")
            fi
        done
        corelisttmp=("${new_corelist_tmp[@]}")
    fi
}

function skipmessage() {
    local core=${1}
    if [ -z "${core}" ]; then return; fi
    
    local core_config_name=${CORES[$core]}
    declare -n core_config=$core_config_name
    
    if [ "${skipmessage}" == "yes" ] && [ "${core_config[can_skip_bios]}" == "yes" ]; then
        (
            sleep "$skiptime"
            samdebug "Button push sent for '${core}' to skip BIOS"
            "${mrsampath}/mbc" raw_seq :31
            sleep 1
            "${mrsampath}/mbc" raw_seq :31
        ) &
    fi
}

function kill_all_sams() {
	# Kill all SAM processes except for currently running
	ps -ef | grep -i '[M]iSTer_SAM' | awk -v me=${sampid} '$1 != me {print $1}' | xargs kill &>/dev/null
}


function activity_reset() {
    truncate -s 0 "$joy_activity_file"
    truncate -s 0 "$mouse_activity_file"
    truncate -s 0 "$key_activity_file"
}

function tmp_reset() {
	[[ -d /tmp/.sam_list ]] && rm -rf /tmp/.sam* /tmp/sam* 
	mkdir -p /tmp/.sam_list  /tmp/.sam_tmp 
}

function samini_mod() {
    local key="$1"
    local value="$2"
    local file="${3:-$samini_file}"
    local formatted="${key}=\"${value}\""
    if grep -q "^${key}=" "$file"; then
        sed -i "/^${key}=/c\\${formatted}" "$file"
    else
        echo "$formatted" >> "$file"
    fi
}
