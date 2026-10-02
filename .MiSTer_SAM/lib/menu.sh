# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

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

    # default action to Start
    premenu="Start"

    for i in {10..1}; do
        echo -ne " Starting SAM in ${i} secs...\033[0K\r"
        read -r -s -N 1 -t 1 key
        case "$key" in
            A)  # UP arrow
                premenu="Menu"
                break
                ;;
            B)  # DOWN arrow
                premenu="Start"
                break
                ;;
            C)  # RIGHT arrow (or Ctrl‑something)
                premenu="Default"
                break
                ;;
        esac
    done
    echo # clear the countdown line
    parse_cmd "${premenu}"
}

function sam_menu() {
  # --- Ensure the menu system is available before showing the menu ---
  load_menu_if_needed

  # If you were exporting CORE_PRETTY for the menu script, that logic can stay
  # in your new load_menu_if_needed() function or here. Let's assume
  # it's not needed for this example to keep it simple.

  # --- Then show the main menu dialog ---
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

    # First, handle UI-only elements like separators.
    # If the user selected the separator, just restart the loop.
    if [[ "${choice,,}" == "separator" ]]; then
        continue
    fi

    # Everything dispatches cleanly through parse_cmd
    parse_cmd "${choice,,}"

    # If it was a "playback" command, exit the menu loop
    case "${choice,,}" in
      start|startmonitor|stop|kill|skip|next|update|ignore) break ;;
    esac
  done
}

function load_menu_if_needed() {
  # If already loaded, do nothing.
  if (( MENU_LOADED == 1 )); then
    return 0
  fi

  local menu_script="${mrsampath}/MiSTer_SAM_menu.sh"

  # Check if the menu script actually exists before trying to source it
  if [[ ! -f "$menu_script" ]]; then
    echo "Error: SAM is not fully installed."
    echo "Menu script not found at: $menu_script" >&2
    # Optionally, exit or show a dialog error
    env_check
    return 1
  fi

  # Add a debug message to confirm the source is being attempted
  # echo "Sourcing menu script..." >&2

  # Source the script and set the flag
  source "$menu_script"
  MENU_LOADED=1
}

function deletegl() {
	# In case of issues, reset game lists

	there_can_be_only_one
	if [ -d "${gamelistpath}" ]; then
		echo "Deleting MiSTer_SAM Gamelist folder"
		rm  "${gamelistpath}"/*_gamelist.txt
	fi

	if [ -d /tmp/.SAM_List ]; then
		rm -rf /tmp/.SAM_List
	fi

	if [ "${inmenu}" -eq 1 ]; then
		sleep 1
		sam_menu
	else
		echo -e "\nGamelist reset successful. Please start SAM now.\n"
		sleep 1
		parse_cmd stop
	fi
}

function creategl() {
	create_all_gamelists
	echo -e "\nGamelist creation successful. Please start SAM now.\n"
	sleep 1
	parse_cmd stop
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
