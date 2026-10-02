# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function sam_start() {
    local core="${1:-}" command
    [[ -z "$core" || -n "${CORE_PRETTY[$core]-}" ]] || { echo 'Unsupported core.' >&2; return 1; }
    env_check || return 1
    there_can_be_only_one || return 1
    mcp_start
    printf -v command '%q loop_core %q' "${SAM_ENTRY:-$misterpath/Scripts/MiSTer_SAM_on.sh}" "$core"
    tmux new-session -d -x 180 -y 40 -n 'SAM: next / previous / mute' -s SAM "$command"
}


function boot_sleep() { #Wait for rtc sync
	unset end
	end=$((SECONDS+60))
	while [ $SECONDS -lt $end ]; do
		if [[ "$(date +%Y)" -gt "2020" ]]; then
			break
		else
			sleep 1
		fi
	done
}

function there_can_be_only_one() {
    local line old_pid= old_start= expected_pid="${1:-}" expected_start="${2:-}"
    if [[ -r "$mrsamtmp/session-owner" ]]; then
        while IFS= read -r line; do
            case "$line" in pid=*) old_pid="${line#*=}" ;; start=*) old_start="${line#*=}" ;; esac
        done < "$mrsamtmp/session-owner"
        if [[ -n "$expected_pid" && ( "$old_pid" != "$expected_pid" || "$old_start" != "$expected_start" ) ]]; then
            return 1
        fi
        if [[ -n "$expected_pid" ]]; then
            sam_pid_start "$old_pid" && [[ "$sam_proc_start" == "$old_start" ]] || return 1
        fi
        if sam_pid_start "$old_pid" && [[ "$sam_proc_start" == "$old_start" && "$old_pid" != "$$" ]]; then
            kill -TERM "$old_pid"
            local deadline=$((SECONDS+5))
            while sam_pid_start "$old_pid" && [[ "$sam_proc_start" == "$old_start" ]] && ((SECONDS<deadline)); do sleep 0.1; done
            if sam_pid_start "$old_pid" && [[ "$sam_proc_start" == "$old_start" ]]; then
                echo 'Previous SAM session has not exited; start refused.' >&2; return 1
            fi
        fi
    fi
    if [[ -n "$expected_pid" && -z "$old_pid" ]]; then return 1; fi
    # A replacement started during cleanup must not lose its pane.
    if [[ -n "$expected_pid" ]] && [[ -r "$mrsamtmp/session-owner" ]]; then
        local current_pid= current_start=
        while IFS= read -r line; do
            case "$line" in pid=*) current_pid="${line#*=}" ;; start=*) current_start="${line#*=}" ;; esac
        done < "$mrsamtmp/session-owner"
        [[ "$current_pid" == "$expected_pid" && "$current_start" == "$expected_start" ]] || return 1
    fi
    tmux kill-session -t SAM 2>/dev/null || true
}


function kill_all_sams() {
    there_can_be_only_one
}


function exit_sam() { # exit_sam [menu|game]
    local exit_mode=${1:-menu} # Default to menu if no argument
    sam_emit display_off "$exit_mode"

    if [[ "$exit_mode" == "menu" ]]; then
        sam_cleanup
        sam_emit audio_stop
        sam_emit display_shutdown
        echo "SAM stopped. Returning to menu..."
        timeout 1s sh -c "echo 'load_core /media/fat/menu.rbf' > /dev/MiSTer_cmd"
    elif [[ "$exit_mode" == "game" ]] && [[ "${mute}" == "core" ]]; then
        # BGM mode: _volume.cfg was bind-mounted to mute the core. MiSTer only
        # reads it on core load, so we must unmount it before reloading.
        # Unmount is fast; everything else is backgrounded so load_core fires immediately.
        local reload_path=""
        if [ -s /tmp/SAM_Game.mgl ]; then
            reload_path="/tmp/SAM_Game.mgl"
        elif [[ -f "${sam_session:-}/current" ]] && sam_record_read "$sam_session/current"; then
            reload_path="$sam_record_path"
        fi
        if [ -n "$reload_path" ]; then
            # Unmount _volume.cfg bind mounts synchronously — MiSTer needs the
            # real file visible before load_core fires.
            readarray -t volmount <<< "$(mount | grep -i _volume.cfg | awk '{print $3}')"
            [ "${#volmount[@]}" -gt 0 ] && umount -l "${volmount[@]}" >/dev/null 2>&1
            echo "SAM stopped. Reloading game with restored volume..."
            timeout 1s bash -c 'printf "load_core %s\n" "$1" > /dev/MiSTer_cmd' _ "$reload_path"
            # Background the slow cleanup so it doesn't delay the reload.
            { sam_emit audio_stop; sam_emit display_shutdown; } &
        fi
    else
        # Normal exit-to-game (no BGM mute): just clean up and leave the game running.
        sam_cleanup
        sam_emit display_shutdown
    fi
}

function exit_sam_fast() {
    sam_emit display_off
    # Critical path only: unmount Volume.dat so audio is restored immediately.
    # BGM stop and tty cleanup are backgrounded so the menu loads without delay.
    only_unmute_if_needed
    { sam_emit audio_stop; sam_emit display_shutdown; sam_cleanup; } &
}

function mcp_start() {
	# MCP monitors when SAM should be launched.
	# "menuonly" and "samtimeout" determine when MCP launches SAM

	if tmux has-session -t MCP 2>/dev/null; then
		return
	fi

	if [ -z "$(pidof MiSTer_SAM_MCP)" ]; then
		tmux new-session -s MCP -d "${mrsampath}/MiSTer_SAM_MCP.py"
	fi
}

function mcp_monitor() {
	# Starts the MCP in an attached tmux session for monitoring/debugging.
	echo "Starting MCP in a visible tmux session for monitoring."
	echo "Detach with: Ctrl-b, then d"
	sleep 2
	# Kill any existing MCP session first
	tmux attach-session -t MCP
}

function sam_monitor() {

    exec tmux attach-session -t SAM
}

function sam_prep() {
    mkdir -p "$mrsamtmp/SAM_config" "$misterpath/video"
    [[ "$kids_safe" != yes ]] || rating=kids
    [[ "$mute" == no ]] || only_mute_if_needed
    sam_emit session_setup
}


function sam_cleanup() {
    [[ "${sam_cleanup_done:-0}" != 1 ]] || return 0
    sam_cleanup_done=1
	# Clean up by umounting any mount binds
	#[ -f "${configpath}/Volume.dat" ] && [ ${mute} == "yes" ] && rm "${configpath}/Volume.dat"
	[ "${mute}" != "no" ] && only_unmute_if_needed
    local mount_index
    for ((mount_index=${#SAM_OWNED_MOUNTS[@]}-1;mount_index>=0;mount_index--)); do
        timeout 3s umount -l "${SAM_OWNED_MOUNTS[mount_index]}" || true
    done
    SAM_OWNED_MOUNTS=()

	if [ "${mute}" != "no" ]; then
		readarray -t volmount <<< "$(mount | grep -i _volume.cfg | awk '{print $3}')"
		if [ "${#volmount[@]}" -gt 0 ]; then
			umount -l "${volmount[@]}" >/dev/null 2>&1
		fi
	fi
	sam_emit session_stop
	samdebug "Cleanup done."
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
	if [ ! -e "${userstartup}" ] && [ -e /etc/init.d/S99user ]; then
		if [ -e "${userstartuptpl}" ]; then
			echo "Copying ${userstartuptpl} to ${userstartup}"
			cp "${userstartuptpl}" "${userstartup}"
			sleep 1
		else
			echo "Building ${userstartup}"
		fi
	fi
	if [ "$(grep -ic "mister_sam" ${userstartup})" = "0" ]; then
		echo -e "Adding SAM to ${userstartup}\n"
		echo -e "\n# Startup MiSTer_SAM - Super Attract Mode" >>${userstartup}
		echo -e "[[ -e ${mrsampath}/MiSTer_SAM_init ]] && ${mrsampath}/MiSTer_SAM_init \$1 &" >>"${userstartup}"
	fi
	echo "SAM install complete."
	echo -e "\n\n\n"
	source "${samini_file}"
	echo -ne "\e[1m" SAM will start ${samtimeout} sec. after boot"\e[0m"
	if [ "${menuonly,,}" == "yes" ]; then
		echo -ne "\e[1m" in the main menu"\e[0m"
	else
		echo -ne "\e[1m" whenever controller is not in use"\e[0m"
	fi
	echo -e "\e[1m" and show each game for ${gametimer} sec."\e[0m"
	echo -ne "\e[1m" First run will take some time to compile game list... please wait."\e[0m"
	echo -e "\n\n\n"
	sleep 5

	"${misterpath}/Scripts/MiSTer_SAM_on.sh" start

	exit
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
	echo " Done."
}

function env_check() {
	# Check if we've been installed
	if [ ! -f "${mrsampath}/samindex" ]; then
		echo " SAM required files not found."
		echo " Installing now."
		sam_update_assets autoconfig
		echo " Setup complete."
	fi
	#Probably offline or update_all install
	if [ ! -f "${configpath}/inputs/GBA_input_1234_5678_v3.map" ]; then
		if [ -f "${mrsampath}/inputs/GBA_input_1234_5678_v3.map" ]; then
			cp "${mrsampath}/inputs/GBA_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/NES_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/TGFX16_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/SATURN_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/MegaCD_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
			cp "${mrsampath}/inputs/NEOGEO_input_1234_5678_v3.map" "${configpath}/inputs" >/dev/null
		else
			get_inputmap
		fi
	fi
}
