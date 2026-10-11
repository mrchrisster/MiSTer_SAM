# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

# One interactive SAM UI at a time. Keep the lock outside session scratch:
# Reset and owner cleanup must not replace the inode while a menu holds it.
sam_menu_release_for_exec() {
    [[ "${sam_ui_menu_depth:-0}" == 1 && "${sam_ui_released:-0}" == 0 ]] || return 0
    sam_ui_released=1
    local rc=0
    if [[ -n "${sam_ui_resume_token:-}" ]]; then
        python3 "$mrsampath/sam/menu_session.py" release "$sam_ui_resume_token" || rc=$?
    fi
    rm -f -- "${sam_menu_file:-}" "${sam_dialog_error:-}" "${sam_dialog_error:-}.failed"
    # Explicit unlock also releases any short-lived inherited descriptions.
    if [[ "${sam_ui_unlocked:-0}" != 1 ]]; then
        flock -u "$sam_menu_lock_fd" || rc=$?
        exec {sam_menu_lock_fd}>&-
    fi
    return "$rc"
}

sam_menu_detach_for_action() {
    [[ "${sam_ui_menu_depth:-0}" == 1 && "${sam_ui_unlocked:-0}" != 1 ]] || return 0
    # Next/Stop/Play should receive a still-paused game. Cleanup resumes it only
    # if the command failed and the exact original selection remains current.
    flock -u "$sam_menu_lock_fd" || return 1
    exec {sam_menu_lock_fd}>&-
    sam_ui_unlocked=1
}

sam_menu_run() {
    if [[ "${sam_ui_menu_depth:-0}" == 1 ]]; then "$@"; return $?; fi
    (
        load_menu_if_needed || exit 1
        local sam_ui_root=${SAM_MENU_TMP_ROOT:-/tmp/.SAM_menu}
        local sam_menu_lock_fd sam_ui_menu_depth=1 sam_ui_released=0 sam_ui_resume_token= sam_ui_unlocked=0
        local sam_menu_file sam_dialog_error admission_fd rc=0
        mkdir -p "$sam_ui_root" || exit 1
        exec {sam_menu_lock_fd}> "$sam_ui_root/menu.lock" || exit 1
        if ! flock -x -n "$sam_menu_lock_fd"; then
            exec {sam_menu_lock_fd}>&-
            printf 'SAM menu is already open. Close the existing menu first.\n' >&2
            exit 2
        fi
        sam_menu_file=$(mktemp "$sam_ui_root/choice.XXXXXX") || exit 1
        sam_dialog_error=$(mktemp "$sam_ui_root/error.XXXXXX") || { rm -f "$sam_menu_file"; exit 1; }
        trap 'sam_menu_release_for_exec' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        trap 'exit 129' HUP
        # An already admitted launch finishes publishing its owner first. New
        # starts see the UI lock and refuse before changing any running core.
        mkdir -p "$mrsamtmp" || exit 1
        exec {admission_fd}> "$mrsamtmp/session-start.lock" || exit 1
        if ! flock -x -w 5 "$admission_fd"; then
            exec {admission_fd}>&-
            printf 'SAM is starting. Retry the menu when the game is ready.\n' >&2
            exit 1
        fi
        sam_ui_resume_token=$(python3 "$mrsampath/sam/menu_session.py" hold) || rc=$?
        flock -u "$admission_fd"
        exec {admission_fd}>&-
        ((rc == 0)) || exit "$rc"
        "$@" || rc=$?
        if [[ -e "$sam_dialog_error.failed" ]]; then
            printf 'SAM dialog failed:\n' >&2
            cat "$sam_dialog_error" >&2
            rc=2
        fi
        sam_menu_release_for_exec || rc=$?
        exit "$rc"
    )
}

sam_dialog() {
    # Result tags use a dedicated descriptor; curses/option errors must never
    # masquerade as a selected menu action. Assign internal errors a separate
    # status from Esc, which normally shares 255. Warnings are not failures.
    local diagnostics=${sam_dialog_error:-} scratch rc
    if [[ -z "$diagnostics" ]]; then
        scratch=$(mktemp /tmp/sam-dialog-error.XXXXXX) || return 2
        diagnostics=$scratch
    fi
    DIALOG_OK=0 DIALOG_CANCEL=1 DIALOG_ESC=255 DIALOG_ERROR=254 \
        dialog --output-fd 3 "$@" 3>&2 2>> "$diagnostics"
    rc=$?
    case "$rc" in
        0|1|2|3|4|5|255) ;;
        *) : > "$diagnostics.failed" ;;
    esac
    if [[ -n "${scratch:-}" ]]; then
        [[ ! -s "$scratch" ]] || cat "$scratch" >&2
        rm -f "$scratch" "$scratch.failed"
    fi
    return "$rc"
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
    [[ "${premenu,,}" == menu ]] || sam_menu_release_for_exec || return
    parse_cmd "${premenu}"
}

function sam_menu() {
  sam_menu_run sam_menu_body
}

function sam_menu_body() {
  # --- Ensure the menu system is available before showing the menu ---
  load_menu_if_needed || return 1

  # --- Then show the main menu dialog ---
  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --ok-label "Select" --cancel-label "Exit" \
           --backtitle "Super Attract Mode" --title "[ Main Menu ]" \
           --menu "Use arrow keys or d-pad to navigate" 0 0 0 \
              start "Start SAM now" \
              stop "Stop and return to MiSTer menu" \
              next "Next game" \
              play "Keep playing current game" \
              ignore "Exclude current game" \
              menu_presets "Game modes and presets" \
              menu_games "Games, filters and controller" \
              menu_settings "Settings: timing, sound and artwork" \
              2> "${sam_menu_file}"

    local rc=$? choice=$(<"${sam_menu_file}")
    clear
    (( rc != 0 )) && break

    case "$choice" in
      start|stop|next|play|ignore|menu_presets|menu_games|menu_settings) ;;
      *) continue ;;
    esac
    case "$choice" in
      start|stop|next|play|ignore) sam_menu_detach_for_action || return ;;
    esac
    parse_cmd "$choice"

    # If it was a "playback" command, exit the menu loop
    case "${choice,,}" in
      start|startmonitor|stop|kill|skip|next|play|update|ignore) break ;;
    esac
  done
  return 0
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
