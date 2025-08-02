#!/bin/bash

# This library contains miscellaneous helper, utility, and operational functions.

# --- Initialization and Setup ---

# Sets all default global variables for the script.
function init_vars() {
	declare -g mrsampath="/media/fat/Scripts/.MiSTer_SAM"
	declare -g misterpath="/media/fat"
	declare -g mrsamtmp="/tmp/.SAM_tmp"
	# Save our PID and process
	declare -g sampid="${$}"
	declare -g samprocess
	samprocess="$(basename -- "${0}")"
	declare -g menuonly="Yes"
	declare -g key_activity_file="/tmp/.SAM_tmp/SAM_Keyboard_Activity"
	declare -g joy_activity_file="/tmp/.SAM_tmp/SAM_Joy_Activity"
	declare -g mouse_activity_file="/tmp/.SAM_tmp/SAM_Mouse_Activity"
	declare -g sam_menu_file="/tmp/.SAMmenu"
	declare -g brfake="/tmp/.SAM_tmp/brfake"
	declare -g samini_file="/media/fat/Scripts/MiSTer_SAM.ini"
	declare -g samini_update_file="${mrsampath}/MiSTer_SAM.default.ini"
	declare -gi inmenu=0
	declare -gi MENU_LOADED=0
	declare -gi sam_bgmmenu=0					  
	declare -gi shown=0
	declare -gi coreretries=3
	declare -gi romloadfails=0
	declare -g gamelistpath="${mrsampath}/SAM_Gamelists"
	declare -g gamelistpathtmp="/tmp/.SAM_List"
	declare -g gamelistpathtmp="/tmp/.SAM_List"
	declare -g tmpfile="/tmp/.SAM_List/tmpfile"
	declare -g tmpfile2="/tmp/.SAM_List/tmpfile2"
	declare -g tmpfilefilter="/tmp/.SAM_List/tmpfilefilter"
	declare -g corelistfile="/tmp/.SAM_List/corelist"
	declare -g core_count_file="/tmp/.SAM_tmp/sv_corecount"	
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
	declare -g repository_url="https://github.com/mrchrisster/MiSTer_SAM"
	declare -g branch="main"
	declare -g raw_base="https://raw.githubusercontent.com/mrchrisster/MiSTer_SAM/${branch}"
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
	declare -g sv_core="/tmp/.SAM_tmp/sv_core"
	declare -g sv_gametimer_file="/tmp/.SAM_tmp/sv_gametimer"
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
		echo "Error: MiSTer_SAM.ini not found."
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
	mkdir -p "${mrsampath}/SAM_Gamelists"
	mkdir -p /tmp/.SAM_List
	mkdir -p /tmp/.SAM_tmp
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
	ps -ef | grep -i '[M]iSTer_SAM_on.sh' | xargs --no-run-if-empty kill &>/dev/null
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
                 menu_inieditor     "MiSTer_SAM.ini Editor" \
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
	alias_m='alias m="/media/fat/Scripts/MiSTer_SAM_on.sh"'
	alias_ms='alias ms="source /media/fat/Scripts/MiSTer_SAM_on.sh --source-only"'
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
        echo "Alias added to $bash_profile. Please relaunch terminal. Type 'm' to start MiSTer_SAM_on.sh"
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
		 "${misterpath}/Scripts/MiSTer_SAM_on.sh" loop_core "$core"
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
	if [ ! -f "${mrsampath}/samindex" ] || [ ! -f "${mrsampath}/MiSTer_SAM_MCP" ]; then
		echo " SAM required files not found. Installing now."
		sam_update autoconfig
		echo " Setup complete."
	fi
}

function there_can_be_only_one() {
    echo "Stopping other running instances of ${samprocess}…"
    tmux kill-session -t SAM 2>/dev/null || true
    local patterns=(
        "MiSTer_SAM_on.sh initial_start"
        "MiSTer_SAM_on.sh loop_core"
        "MiSTer_SAM_on.sh bootstart"
        "MiSTer_SAM_init start"
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
	if [[ "$(cat /media/fat/Scripts/.config/downloader/downloader.log | grep -c "MiSTer_SAM.default.ini")" != "0" ]] && [ "${samini_update_file}" -nt "${samini_file}" ]; then
		echo "New MiSTer_SAM.ini version downloaded. Merging with new ini."
		cp "${samini_file}" "${samini_file}".bak
		sed -i 's/==/--/g' "${samini_file}"
		sed -i 's/-=/--/g' "${samini_file}"
		awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' "${samini_file}" "${samini_update_file}" >/tmp/MiSTer_SAM.tmp && cp -f --force /tmp/MiSTer_SAM.tmp "${samini_file}"
		echo "Done."
	fi
}

function mcp_start() {
	if [ -z "$(pidof MiSTer_SAM_MCP)" ]; then
		tmux new-session -s MCP -d "${mrsampath}/MiSTer_SAM_MCP"
	fi
}

function sam_prep() {
	if [ "${rating}" == "yes" ]; then
		samvideo=no
	fi
	# ... (rest of sam_prep logic from original script) ...
}

function disable_bootrom() {
	if [ "${disablebootrom}" == "yes" ]; then
		mkdir -p /tmp/.SAM_List/Bootrom
		[ -d "${misterpath}/Bootrom" ] && [ "$(mount | grep -ic 'bootrom')" == "0" ] && mount --bind /tmp/.SAM_List/Bootrom "${misterpath}/Bootrom"
		# ... (rest of disable_bootrom logic from original script) ...
	fi
}

# --- System Interaction ---

function mute() {
	if [ "${mute}" == "core" ]; then
		samdebug "mute=core"
		only_unmute_if_needed
		
		local mute_target="$1"
		[ ! -f "${configpath}/${mute_target}_volume.cfg" ] && touch "${configpath}/${mute_target}_volume.cfg"
		[ ! -f "/tmp/.SAM_tmp/SAM_config/${mute_target}_volume.cfg" ] && touch "/tmp/.SAM_tmp/SAM_config/${mute_target}_volume.cfg"		
		
		mount --bind "/tmp/.SAM_tmp/SAM_config/${mute_target}_volume.cfg" "${configpath}/${mute_target}_volume.cfg"
		
		if [[ "$(mount | grep -ic "${mute_target}"_volume.cfg)" != "0" ]]; then
			echo -e "\0006\c" > "/tmp/.SAM_tmp/SAM_config/${mute_target}_volume.cfg"
		fi
	fi
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

function tty_start() {
    if [ "${ttyenable}" == "yes" ]; then
        touch "${mrsamtmp}/tty_sleep"
        echo -n "Starting tty2oled... "
        tmux new -s OLED -d "${mrsampath}/MiSTer_SAM_tty2oled" &>/dev/null
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

		# Download the newest MiSTer_SAM_on.sh to /tmp
		get_samstuff MiSTer_SAM_on.sh /tmp
		if [ -f /tmp/MiSTer_SAM_on.sh ]; then
			if [ "${1}" ]; then
				echo " Continuing setup with latest MiSTer_SAM_on.sh..."
				/tmp/MiSTer_SAM_on.sh "${1}"
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
		get_samindex
		get_mbc
		#get_samstuff .MiSTer_SAM/MiSTer_SAM.default.ini
		get_samstuff .MiSTer_SAM/MiSTer_SAM_init
		get_samstuff .MiSTer_SAM/MiSTer_SAM_MCP
		get_samstuff .MiSTer_SAM/MiSTer_SAM_menu.sh
		get_samstuff .MiSTer_SAM/MiSTer_SAM_tty2oled
		get_samstuff .MiSTer_SAM/MiSTer_SAM_joy.py
		if [ ! -f "${mrsampath}/sam_controllers.json" ]; then
			get_samstuff .MiSTer_SAM/sam_controllers.json
		fi
		if [ "${samvideo}" == "yes" ]; then
			get_samvideo
		fi
		get_samstuff .MiSTer_SAM/MiSTer_SAM_keyboard.py
		get_samstuff .MiSTer_SAM/MiSTer_SAM_mouse.py
		get_inputmap
		get_blacklist
		get_ratedlist
		get_samstuff MiSTer_SAM_off.sh /media/fat/Scripts
		

		if [ -f "${samini_file}" ]; then
			echo " MiSTer SAM INI already exists... Merging with new ini."
			get_samstuff MiSTer_SAM.ini /tmp
			echo " Backing up MiSTer_SAM.ini to MiSTer_SAM.ini.bak"
			cp "${samini_file}" "${samini_file}".bak
			echo -n " Merging ini values.."
			# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
			sed -i 's/==/--/g' "${samini_file}"
			sed -i 's/-=/--/g' "${samini_file}"
			awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' "${samini_file}" /tmp/MiSTer_SAM.ini >/tmp/MiSTer_SAM.tmp && cp -f --force /tmp/MiSTer_SAM.tmp "${samini_file}"
			echo "Done."

		else
			get_samstuff MiSTer_SAM.ini /media/fat/Scripts
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

function sam_cleanup() {
    only_unmute_if_needed
    # ... (and all other cleanup logic like umounting) ...
}

function activity_reset() {
    truncate -s 0 "$joy_activity_file"
    truncate -s 0 "$mouse_activity_file"
    truncate -s 0 "$key_activity_file"
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
