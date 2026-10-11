#!/usr/bin/env bash
# MiSTer_SAM_menu.sh — Dialog-based menu layout for Super Attract Mode (SAM)
# Source this on demand from MiSTer_SAM_on.sh to expose only UI functions.

# Guard against double-sourcing
[[ -n "${SAM_MENU_LOADED:-}" ]] && return
SAM_MENU_LOADED=1

# Temporary file for sam_dialog output
sam_menu_file="/tmp/.sam_menu_choice.${BASHPID:-$$}"

# All cores
# source /tmp/.SAM_tmp/sam_core_pretty

#-------------------------------------------------------------------------------
# PRESETS MENU
#-------------------------------------------------------------------------------
sam_preset_start() {
  # MCP applies literal settings live; retain input monitoring if Start fails.
  if declare -F sam_menu_release_for_exec >/dev/null; then sam_menu_release_for_exec; fi
  exec "${SAM_ENTRY:-$0}" start
}

function menu_presets() {
  inmenu=1
  while true; do
    sam_dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Exit" \
           --backtitle "Super Attract Mode" --title "[ Game Modes ]" \
           --menu "Use the arrow keys or d-pad+A to navigate" 0 0 0 \
             menu_preset_standard      "Default Setting - Play all cores muted" \
             menu_smart_presets        "Smart category presets (permanent or until reboot)" \
             menu_preset_svc           "Play TV commercials and then show the advertised game." \
             menu_preset_goat_mode     "Play the Greatest of All Time Attract modes." \
             menu_preset_80s           "Play 80s Music, no Handhelds and only Horiz. games." \
             menu_preset_maturetgfx    "Play Games rated mature for TurboGrafx-CD." \
             menu_preset_kids          "Kids: community game whitelist" \
             menu_preset_m82_mode      "Turn your MiSTer into a NES M82 unit." \
             menu_preset_roulette_mode "Game Roulette (timed random games)" \
      2> "${sam_menu_file}"

    local rc=$? choice=$(<"${sam_menu_file}")
    clear
    (( rc != 0 )) && return    # Back/Exit

    # If the function exists, just call it:
    if declare -F "$choice" >/dev/null; then
      "$choice"
      return
    else
      sam_dialog --msgbox "Unknown selection: $choice" 0 0
    fi
  done
}


function menu_preset_standard() {
  # Reset everything to defaults for this preset
  reset_ini

  # Finally, start SAM
  sam_preset_start
}

function menu_preset_svc() {
  local rc selection keep

  # 2) Inform the user what this mode does
  sam_dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ SAMVIDEO MODE ]" \
         --msgbox "This mode will download commercials from archive.org, play them on your MiSTer,\nand then attempt to launch the advertised game.\n\nExperimental: results may vary!" \
         0 0

  # 3) Choose CD-i or mplayer
  exec 3>&1
  selection=$(sam_dialog --clear --ascii-lines --no-cancel --backtitle "Super Attract Mode" \
            --title "[ Video Mode ]" \
            --menu "Select how we want to play videos" 0 0 0 \
              1 "CD-i (best compatibility)" \
              2 "mPlayer" \
            2>&1 1>&3)
  rc=$?
  exec 3>&-
  (( rc != 0 )) && return 0  # cancelled

  # 4) Ask about keeping local copies
  exec 3>&1
  keep=$(sam_dialog --clear --ascii-lines --no-cancel --backtitle "Super Attract Mode" \
           --title "[ Local Copies ]" \
           --menu "Keep local copies of commercials? (~4GB req’d)" 0 0 0 \
             1 "Yes" \
             2 "No" \
           2>&1 1>&3)
  rc=$?
  exec 3>&-
  (( rc != 0 )) && return 0
  [[ "$selection" == 1 || "$selection" == 2 ]] || return 1
  [[ "$keep" == 1 || "$keep" == 2 ]] || return 1

  # Commercial mappings are JSON assets; a nonexistent legacy .txt filename
  # must not trigger a player update on every visit to this preset.
  local tvc_suffix=_tvc.json
  [[ "$selection" != 1 ]] || tvc_suffix=_tvc_vcd.json
  if [[ ! -s "$mrsampath/tvc/nes$tvc_suffix" ]]; then
    source "$mrsampath/lib/downloads.sh" || return 1
    get_tvc_files || return 1
    [[ -s "$mrsampath/tvc/nes$tvc_suffix" ]] || return 1
  fi

  reset_ini
  if [[ "$selection" == "1" ]]; then
    samini_mod samvideo_tvc_cdi Yes
  else
    samini_mod samvideo_tvc_cdi No
  fi

  if [[ "$keep" == "1" ]]; then
    samini_mod keep_local_copy Yes
  else
    samini_mod keep_local_copy No
  fi

  # 5) Core & BGM config for video mode
  samini_mod corelist "arcade,atarilynx,gb,gbc,genesis,gg,megacd,n64,nes,psx,saturn,s32x,sgb,sms,snes,tgfx16,tgfx16cd"
  samini_mod samvideo Yes
  samini_mod Artwork_only No
  samini_mod samvideo_source Archive
  samini_mod samvideo_tvc Yes

  # 7) Final confirmation
  sam_dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ All Set ]" \
         --msgbox "Configuration saved. Press OK to start SAMVIDEO mode.\n\nIf commercials are slow to appear, give it a moment to download first." \
         0 0

  # 8) Launch it
  sam_preset_start
}

# Function to process the GOAT list and create game list files
function menu_preset_goat_mode() {
  reset_ini
  # 1) Show info
  sam_dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ GOAT MODE ]" \
         --msgbox "GOAT Attract Mode will only play games deemed to have the Greatest of All Time Attract Modes.\n\nPress OK to prepare the lists and return to the menu." \
         0 0

  samini_mod sam_goat_list yes

  # 4) Back to main menu
  # The next session has private lists; its policy stamp includes this preset.
  # Never wipe shared runtime ownership/state while an old session is running.
  sam_preset_start
}

function menu_preset_80s() {
	reset_ini
	samini_mod corelist "amiga,arcade,fds,genesis,megacd,n64,neogeo,nes,saturn,s32x,sms,snes,tgfx16,tgfx16cd,psx"
	samini_mod arcadeorient horizontal
	enablebgm || return $?
	sam_preset_start
}

function menu_preset_maturetgfx() {
  # 1) Reset INI to defaults
  reset_ini

  # 2) Inform the user about this preset
  sam_dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ Mature TGFX Mode ]" \
         --msgbox "Mature TGFX Mode will only show mature-rated TurboGrafx-CD titles.\n\nEnjoy the edgier side of the library!" \
         0 0

  # 3) Disable any blacklist, set rating filter, and restrict to TGFX-CD core
  samini_mod disable_blacklist Yes
  samini_mod rating mature
  samini_mod corelist tgfx16cd

  # 4) Launch SAM
  sam_preset_start
}


menu_preset_kids() {
	reset_ini
	sam_dialog --clear --no-cancel --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ ALL-AGES GAMES ]" \
		--msgbox "SAM restricts games to the community whitelists under /media/fat/SAM/Rated.\n\nThese lists may contain rating errors. Review them for your household before relying on this mode." 0 0
	samini_mod rating kids
    local file corelist_value= core
    for file in "$ratedpath/"*_rated.txt; do
        [[ -s "$file" ]] || continue
        core=${file##*/}; core=${core%_rated.txt}
        [[ "$core" =~ ^[a-z0-9]+$ ]] || continue
        corelist_value+="${corelist_value:+,}$core"
    done
    [[ -n "$corelist_value" ]] || { sam_dialog --msgbox "No Kids whitelists are installed." 0 0; return 1; }
    samini_mod corelist "$corelist_value" || return 1
	sam_preset_start
}


# M82 mode
menu_preset_m82_mode() {
	reset_ini
	sam_dialog --clear --no-cancel --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ M82 MODE ]" \
		--msgbox "SAM will act as an M82 unit for NES. To disable this, go to MiSTer_SAM.ini and find m82 option or change to another preset.\n\nPlease define your controller in MiSTer's main menu\n\nGame Timer is set to ${m82_game_timer}s per Game - Change m82_game_timer in SAM's ini\n\nMiSter will restart now. " 0 0
		samini_mod m82 Yes
        samini_mod Artwork_only No
		sam_preset_start


}

function menu_preset_roulette_mode() {
  # Explain the mode
  sam_dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ GAME ROULETTE ]" \
         --msgbox "Game Roulette mode picks a random title for you to play for a set time, then moves on to the next random title.\n\nEnjoy the surprise!" \
         0 0

  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ GAME ROULETTE ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Choose a time per game:" 0 0 0 \
             Roulette2       "2 minutes" \
             Roulette5       "5 minutes" \
             Roulette10      "10 minutes" \
             Roulette15      "15 minutes" \
             Roulette20      "20 minutes" \
             Roulette25      "25 minutes" \
             Roulette30      "30 minutes" \
             Roulettetimer   "Custom (${roulettetimer}s from INI)" \
      2> "${sam_menu_file}"

    local rc=$? choice=$(<"${sam_menu_file}")
    clear

    # Back → return to Game Modes menu
    (( rc != 0 )) && return

    local timer
    case "$choice" in
      Roulettetimer)
        timer=$roulettetimer
        ;;
      Roulette2|Roulette5|Roulette10|Roulette15|Roulette20|Roulette25|Roulette30)
        timer=$(( ${choice#Roulette} * 60 ))
        ;;
      *)
        sam_dialog --msgbox "Unknown selection: $choice" 0 0
        continue
        ;;
    esac
    [[ "$timer" =~ ^[1-9][0-9]*$ ]] || {
      sam_dialog --msgbox "Roulette needs a positive time in seconds." 0 0
      return 1
    }

    # Commit only after selection. Back must preserve the existing mode.
    reset_ini
    mkdir -p "$mrsamtmp" || return 1
    local staged="$mrsamtmp/gameroulette.ini.tmp.$BASHPID"
    echo "gametimer=$timer" > "$staged" || return 1

    # Always disable core listening during roulette
    {
      echo "mute=no"
      echo "listenmouse=No"
      echo "listenkeyboard=No"
      echo "listenjoy=No"
    } >> "$staged" && mv -f -- "$staged" "$mrsamtmp/gameroulette.ini" || return 1

    # Launch SAM with the roulette INI
    sam_preset_start
    return
  done
}




#-------------------------------------------------------------------------------
# CORE LIST CONFIGURATOR
#-------------------------------------------------------------------------------
function menu_coreconfig() {
  # Show intro only once
  if [[ -z $shown_coreconfig ]]; then
    sam_dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ CORE CONFIG ]" \
           --msgbox "Current corelist:\n\n${corelist[*]}" 0 0
    shown_coreconfig=1
  fi

  local opts=(
    menu_corelist_preset   "Presets for Core List"
    menu_choose_cores      "Enable/Disable cores (keyboard only)"
    menu_singlecore        "Only play games from one core (until reboot)"
  )

  while sam_dialog --clear --ascii-lines --no-tags \
               --backtitle "Super Attract Mode" --title "[ CORE CONFIG ]" \
               --ok-label "Select" --cancel-label "Back" \
               --menu "Select an option:" 0 0 0 \
               "${opts[@]}" 2>"${sam_menu_file}"; do

    clear
    choice=$(<"${sam_menu_file}")

    if declare -F "$choice" >/dev/null; then
      "$choice"      # call menu_corelist_preset, menu_choose_cores, etc.
    else
      sam_dialog --msgbox "Unknown selection: $choice" 0 0
    fi
  done
}


function menu_corelist_preset() {
  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ CORELIST PRESET ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Select a preset" 0 0 0 \
             2 "Only Arcade & Console Cores" \
             1 "Only Arcade and NeoGeo games" \
             6 "1990s Arcade games + Neo Geo" \
             3 "Only Handheld Cores" \
             4 "Only Computer Cores" \
             5 "Only Cores from the 1990s (no handheld)" \
             7 "mrchrisster's favorite cores" \
      2> "${sam_menu_file}"

    local rc=$? choice=$(<"${sam_menu_file}")
    clear
    # Back → return to Core Config menu
    (( rc != 0 )) && return

    case "$choice" in
      1) samini_mod corelist "arcade,neogeo" ;;
      2) samini_mod corelist "arcade,atari2600,atari5200,atari7800,fds,genesis,megacd,neogeo,nes,saturn,s32x,sms,snes,stv,tgfx16,tgfx16cd,psx" ;;
      3) samini_mod corelist "gb,gbc,gba,gg,atarilynx" ;;
      4) samini_mod corelist "amiga,c64,coco2" ;;
      5|6)
         # Shared “1990s” confirmation
         sam_dialog --clear --ascii-lines --no-cancel \
                --backtitle "Super Attract Mode" --title "[ CORELIST PRESET ]" \
                --yesno "This will set Arcade Path Filter to 1990's.\nRemove later via Filters menu?" \
                0 0
         if (( $? == 0 )); then
           samini_mod arcadepathfilter "_The 1990s"
         else
           samini_mod arcadepathfilter ""
         fi
         if [[ "$choice" == "5" ]]; then
           samini_mod corelist "arcade,genesis,megacd,neogeo,saturn,s32x,snes,tgfx16,tgfx16cd,psx"
         else
           samini_mod corelist "arcade,neogeo"
         fi
         ;;
      7) samini_mod corelist "amiga,amigacd32,ao486,arcade,fds,genesis,megacd,neogeo,neogeocd,n64,nes,saturn,s32x,sms,snes,tgfx16,tgfx16cd,psx" ;;
      *)
        sam_dialog --msgbox "Unknown selection: $choice" 0 0
        continue
        ;;
    esac

    # Confirm & loop
    sam_dialog --clear --ascii-lines --no-cancel \
           --backtitle "Super Attract Mode" --title "[ CORELIST PRESET ]" \
           --msgbox "Changes saved!" 0 0
  done
}

function menu_choose_cores() {
    # Show warning only once
    if [[ -z $shown_choose_cores ]]; then
        sam_dialog --clear --no-cancel --ascii-lines \
            --backtitle "Super Attract Mode" --title "[ CORE CONFIGURATION ]" \
            --msgbox "Joystick isn’t supported for core toggling—use a keyboard (space to toggle).\n\nHit Back if you’re on a joystick." \
            0 0
        shown_choose_cores=1
    fi

    # Loop until the user hits “Back” (or cancels)
    while true; do
        # --- FIX: Rebuild the options array on EVERY loop iteration ---
        # This ensures the ON/OFF state is always current.
        local opts=()
        for core in "${corelistall[@]}"; do
            local state=OFF
            # Check if the core exists in our current corelist array
            [[ " ${corelist[*]} " == *" $core "* ]] && state=ON
            opts+=( "$core" "Show ${CORE_PRETTY[$core]} games" "$state" )
        done

        # Show the dialog. If the user hits "Back" (Cancel), break the loop.
        if ! sam_dialog --clear --ascii-lines --no-tags \
            --backtitle "Super Attract Mode" --title "[ CORE CONFIGURATION ]" \
            --ok-label "Save" --cancel-label "Back" \
            --separate-output --checklist "Toggle cores on/off:" 0 0 0 \
            "${opts[@]}" 2>"${sam_menu_file}"; then
            break # Exit the while loop
        fi

        # --- Process the saved changes ---
        # Read the user's choices into a new array
        local choices
        mapfile -t choices < "${sam_menu_file}"

        # If nothing was selected, we don't need to save or show a message.
        # The loop will simply redraw the menu.
        (( ${#choices[@]} == 0 )) && continue

        # Apply the new corelist to the INI file
        local corelistmod
        corelistmod=$(IFS=,; echo "${choices[*]}")
        samini_mod corelist "$corelistmod"

        # --- FIX: Update the in-memory corelist array ---
        # This is crucial so the *next* loop iteration builds the menu correctly.
        corelist=( "${choices[@]}" )

        sam_dialog --clear --ascii-lines --no-cancel \
            --backtitle "Super Attract Mode" --title "[ CORE CONFIGURATION ]" \
            --msgbox "Changes saved! Your new list has ${#corelist[@]} cores." \
            0 0
    done
}

function menu_singlecore() {
  while true; do
    # Build the menu entries dynamically
    local menulist=()
    for core in "${corelistall[@]}"; do
      menulist+=( "${core^^}" "${CORE_PRETTY[$core]} games only" )
    done

    # Show the single‐system menu
    sam_dialog --clear --ascii-lines --no-tags \
           --ok-label "Select" --cancel-label "Back" \
           --backtitle "Super Attract Mode" --title "[ Single System Select ]" \
           --menu "Choose a system to play only its games:" 0 0 0 \
           "${menulist[@]}" \
      2> "${sam_menu_file}"

    local rc=$? choice=$(<"${sam_menu_file}")
    clear

    # Back → return to Core Config (or previous) menu
    (( rc != 0 )) && return

    # Launch just that core
    if declare -F sam_menu_release_for_exec >/dev/null; then sam_menu_release_for_exec; fi
    exec "${SAM_ENTRY:-$0}" "${choice,,}"
    return
  done
}

#-------------------------------------------------------------------------------
# SAM EXIT BEHAVIOR
#-------------------------------------------------------------------------------

function menu_exitbehavior() {
  # Show the current state once
  if [[ -z $shown_exitbehavior ]]; then
    if [[ "${playcurrentgame,,}" == "yes" ]]; then
      msg="Currently, exiting will *play* the current game when you push a button."
    else
      msg="Currently, exiting will *return to the MiSTer menu* when you push a button.\n\nIf you configured your controller, only START (or NEXT) will play the game."
    fi
    sam_dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ Exit Behavior ]" \
           --msgbox "$msg" 0 0
    shown_exitbehavior=1
  fi

  # Loop until the user hits “Back”
  while sam_dialog --clear --ascii-lines --no-tags \
                --backtitle "Super Attract Mode" --title "[ Exit Behavior ]" \
                --ok-label "Select" --cancel-label "Back" \
                --menu "Choose what happens when you exit SAM:" 0 0 0 \
                  enableplaycurrent   "On Exit → Play Current Game" \
                  disableplaycurrent  "On Exit → Return to MiSTer Menu" \
    2> "${sam_menu_file}"; do

    clear
    choice=$(<"${sam_menu_file}")

    case "${choice,,}" in
      enableplaycurrent)
        samini_mod playcurrentgame Yes
        ;;
      disableplaycurrent)
        samini_mod playcurrentgame No
        ;;
      *)
        sam_dialog --msgbox "Unknown selection: $choice" 0 0
        continue
        ;;
    esac

    sam_dialog --clear --ascii-lines --no-cancel \
           --backtitle "Super Attract Mode" --title "[ Exit Behavior ]" \
           --msgbox "Changes saved!" 0 0
  done
}

#-------------------------------------------------------------------------------
# CONTROLLER CONFIGURATOR
#-------------------------------------------------------------------------------
function menu_controller() {
    sam_dialog --clear --ascii-lines --backtitle "Super Attract Mode" \
        --title "[ Controller buttons ]" --msgbox \
        "Define your controller once in MiSTer's main menu: Define joystick buttons.\n\nSAM reads supported saved global maps, then the controller database. Start keeps playing; Select advances to the next game; ordinary activity returns to Menu.\n\nFor troubleshooting, use the standalone sam_input_debug.py diagnostic from the SAM repository's tools-extras folder. Run with --duration 60 during gameplay; it does not change mappings or launch cores." 0 0
}

#-------------------------------------------------------------------------------
# FILTERS
#-------------------------------------------------------------------------------


function menu_filters() {
  local rc choice
  while true; do
    sam_dialog --clear --ascii-lines --no-tags --backtitle "Super Attract Mode" \
      --title "[ Filters ]" --ok-label "Select" --cancel-label "Back" \
      --menu "Filters refine your existing core, Kids, Ignore and artwork choices." 0 0 0 \
      menu_smart_presets "Smart category presets (permanent or until reboot)" \
      menu_cat_exclude "Exclude regions and release categories" \
      2> "$sam_menu_file"
    rc=$? choice=$(<"$sam_menu_file")
    ((rc == 0)) || return 0
    case "$choice" in
      menu_smart_presets|menu_cat_include) menu_smart_presets ;;
      menu_cat_exclude) menu_cat_exclude ;;
      # Retain the old explicit reset command for existing scripted menus.
      arcadedisable) samini_mod arcadepathfilter ""; samini_mod arcadeorient ""; menu_changes_saved ;;
    esac
  done
}

sam_category_menu_ready() {
  declare -F sam_category_read_scope >/dev/null || sam_load_module category || return 1
  sam_category_read_scope
}

sam_category_menu_scope() { # selected preset, literal exclusion tags
  local rc scope
  sam_dialog --clear --ascii-lines --no-tags --backtitle "Super Attract Mode" \
    --title "[ Save filter ]" --ok-label "Save" --cancel-label "Back" \
    --menu "Keep this choice after reboot? Running SAM applies it at the next game." 0 0 0 \
    permanent "Save permanently" reboot "Until reboot" 2> "$sam_menu_file"
  rc=$? scope=$(<"$sam_menu_file")
  ((rc == 0)) || return 0
  case "$scope" in permanent|reboot) ;; *) return 1;; esac
  sam_category_store "$1" "$2" "$scope" || {
    sam_dialog --msgbox "The filter could not be fully saved. Check the selected settings before starting SAM." 0 0
    return 1
  }
  local note="Saved. Active SAM applies this at the next game. Start SAM from the main menu if it is idle."
  [[ "$1" != pinball ]] || note+="\n\nPinball allows static-screen titles; Kids, Ignore, exclusions and artwork still apply."
  [[ "$scope" != reboot ]] || note+="\n\nAfter reboot your saved filters return."
  if compgen -G "$blacklistpath/*_gamelist_exclude.txt" >/dev/null; then
    note+="\n\nExisting legacy exclusion lists in Blacklists still apply. Clear them separately if needed; this menu does not delete user lists."
  fi
  sam_dialog --msgbox "$note" 0 0
}

function menu_smart_presets() {
  sam_category_menu_ready || return 1
  local rc preset current=${sam_category_preset//_/ } scope=saved
  [[ "$sam_category_preset" != off ]] || current='all categories'
  [[ "${sam_category_scope:-permanent}" != reboot ]] || scope='until reboot'
  sam_dialog --clear --ascii-lines --no-tags --backtitle "Super Attract Mode" \
    --title "[ Smart category presets ]" --ok-label "Select" --cancel-label "Back" \
    --default-item "$sam_category_preset" \
    --menu "Current: $current ($scope)\n\nChoose what SAM plays. Your other filters still apply." 0 0 0 \
    off "All categories (keep other filters)" \
    pinball "Pinball only (allow static-screen tables)" \
    arcade_horizontal "Arcade: horizontal only" \
    arcade_vertical "Arcade: vertical only" \
    shmups "Shoot 'em ups" fighting "Fighting games" puzzle "Puzzle games" racing "Racing games" \
    2> "$sam_menu_file"
  rc=$? preset=$(<"$sam_menu_file")
  ((rc == 0)) || return 0
  sam_category_valid "$preset" || return 1
  sam_category_menu_scope "$preset" "$sam_category_exclusions"
}

function menu_cat_include() { menu_smart_presets; }

function menu_cat_exclude() {
  sam_category_menu_ready || return 1
  local rc selected tag status
  local -a items=()
  for tag in Beta Hack Homebrew Prototype Unlicensed Translations USA Japan Europe; do
    status=off
    [[ ",${sam_category_exclusions,,}," != *",${tag,,},"* ]] || status=on
    items+=("$tag" "$tag" "$status")
  done
  sam_dialog --clear --ascii-lines --separate-output --backtitle "Super Attract Mode" \
    --title "[ Category exclusions ]" --ok-label "Select" --cancel-label "Back" \
    --checklist "Exclude exact folder or release metadata. Clear every checkbox to remove these tag rules. Existing legacy/user exclusion lists remain active." 0 0 0 \
    "${items[@]}" 2> "$sam_menu_file"
  rc=$? selected=$(<"$sam_menu_file")
  ((rc == 0)) || return 0
  selected=${selected//$'\n'/,}
  selected=${selected//\"/}
  sam_category_tags_valid "$selected" || return 1
  sam_category_menu_scope "$sam_category_preset" "$selected"
}


#-------------------------------------------------------------------------------
# ADD-ONS
#-------------------------------------------------------------------------------
# $mrsampath/MiSTer_SAM_menu.sh

function menu_addons() {
  local rc choice

  # Show intro only once (no change here)
  if [[ -z $shown_bgmmenu ]]; then
    sam_dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ SAMVIDEO, BGM & TTY2OLED ]" \
           --msgbox $'SAMVIDEO\n----------------\nVideo playback on MiSTer (toggles per core).\n\nBGM\n----------------\nPlay background music while SAM shuffles games.\n\nTTY2OLED\n----------------\nHardware display support (only if you have TTY2OLED).' 0 0
    shown_bgmmenu=1
  fi

  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ SAMVIDEO, BGM & TTY2OLED ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Pick an option:" 0 0 0 \
             sv_header   "--- SAMVIDEO Settings ---" \
             enablesv    "  Enable Video Playback" \
             disablesv   "  Disable Video Playback" \
             enablecrt   "  Force CRT Output" \
             enablehdmi  "  Force HDMI Output" \
             enableyt    "  Enable YouTube Playback" \
             enablear    "  Enable Archive.org Playback" \
             bgm_header  "--- BGM Settings ---" \
             enablebgm   "  Enable BGM" \
             disablebgm  "  Disable BGM" \
             tty_header  "--- TTY2OLED Settings ---" \
             enabletty   "  Enable TTY2OLED" \
             disabletty  "  Disable TTY2OLED" \
      2> "${sam_menu_file}"

    rc=$? choice=$(<"${sam_menu_file}")
    clear
    (( rc != 0 )) && return

    case "${choice,,}" in
      # Add this to ignore header selections
      sv_header|bgm_header|tty_header) continue ;;

      enablesv)   samini_mod samvideo Yes         ;;
      disablesv)  samini_mod samvideo No          ;;
      enablecrt)  samini_mod samvideo_output CRT   ;;
      enablehdmi) samini_mod samvideo_output HDMI  ;;
      enableyt)   samini_mod samvideo_source Youtube ;;
      enablear)   samini_mod samvideo_source Archive ;;
      enablebgm)  enablebgm ;;
      disablebgm)
        bgm_stop force
        samini_mod bgm No
        ;;
      enabletty)  samini_mod ttyenable Yes        ;;
      disabletty) samini_mod ttyenable No         ;;
      *)
        sam_dialog --msgbox "Unknown selection: $choice" 0 0
        continue
        ;;
    esac

    sam_dialog --clear --ascii-lines --no-cancel \
           --backtitle "Super Attract Mode" --title "[ SAMVIDEO, BGM & TTY2OLED ]" \
           --msgbox "Changes saved!" 0 0
  done
}

function enablebgm() {
    local staged script=${SAM_BGM_SCRIPT:-/media/fat/Scripts/bgm.sh}
    local music=${SAM_BGM_MUSIC_DIR:-/media/fat/music}
    if [[ ! -r "$script" ]]; then
        staged=$(mktemp /tmp/sam-bgm-install.XXXXXX.sh) || return 1
        if ! curl_download "$staged" "https://raw.githubusercontent.com/wizzomafizzo/MiSTer_BGM/main/bgm.sh" ||
           [[ ! -s "$staged" ]] || ! python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$staged"; then
            rm -f "$staged"
            sam_dialog --msgbox "BGM download failed. Existing settings were preserved." 0 0
            return 1
        fi
        chmod +x "$staged" && mv "$staged" "$script" || {
            rm -f "$staged"; return 1;
        }
    fi
    # A healthy installation is reused. Updating SAM must not kill unrelated
    # music processes or redownload BGM each time this option is selected.
    mkdir -p "$music" || return 1
    if [[ ! -r "$music/80s.pls" ]]; then
        get_samstuff Media/80s.pls "$music" || return 1
    fi
    # Publish configuration only after every installation prerequisite succeeds.
    samini_mod mute No
    samini_mod bgm Yes
    sam_preset_start
}



#-------------------------------------------------------------------------------
# INI Editor
#-------------------------------------------------------------------------------

function menu_inieditor() {
  local rc tmpfile

  # Intro message
  sam_dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ INI Settings ]" \
         --msgbox "Edit MiSTer_SAM.ini directly.\n\nUse TAB to switch between file, OK and Cancel." 0 0

  # Loop: allow multiple edits until user cancels
  while true; do
    sam_dialog --clear --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ INI Settings ]" \
           --ok-label "Save" --cancel-label "Back" \
           --editbox "${samini_file}" 0 0 2> "${sam_menu_file}"

    rc=$?
    tmpfile="${sam_menu_file}"
    clear

    # Back/Cancel → exit without further action
    (( rc != 0 )) && return

    # Only copy back if file is non-empty and differs
    if [[ -s "$tmpfile" ]] && ! cmp -s "$tmpfile" "${samini_file}" >/dev/null; then
      cp -f "$tmpfile" "${samini_file}"
      sam_dialog --clear --ascii-lines --no-cancel \
             --backtitle "Super Attract Mode" --title "[ INI Settings ]" \
             --msgbox "Changes saved!" 0 0
    else
      # No changes → just continue or break
      sam_dialog --clear --ascii-lines --no-cancel \
             --backtitle "Super Attract Mode" --title "[ INI Settings ]" \
             --msgbox "No changes made." 0 0
    fi

    # After saving (or no-op), return to main menu
    return
  done
}


#-------------------------------------------------------------------------------
# SETTINGS
#-------------------------------------------------------------------------------
# Menu tags are an explicit allowlist. Cancel and sam_dialog errors invoke nothing.
function sam_menu_group() {
  local title=$1 prompt=$2 rc choice tag matched
  shift 2
  local entries=( "$@" )
  while true; do
    sam_dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Back" \
      --backtitle "Super Attract Mode" --title "[ $title ]" \
      --menu "$prompt" 0 0 0 "${entries[@]}" 2> "$sam_menu_file"
    rc=$?
    choice=$(<"$sam_menu_file")
    clear
    (( rc == 0 )) || return 0
    matched=0
    for ((tag=0; tag<${#entries[@]}; tag+=2)); do
      [[ "$choice" == "${entries[tag]}" ]] && { matched=1; break; }
    done
    (( matched )) || continue
    parse_cmd "$choice"
  done
}

function menu_games() {
  sam_menu_group "Games" "Choose games and input behavior" \
    menu_coreconfig "Systems: cores or a single system" \
    menu_filters "Filters: genre and arcade orientation" \
    menu_exitbehavior "On input: return to menu or keep playing" \
    menu_controller "Controller: MiSTer mapping and diagnostics"
}

function menu_settings() {
  sam_menu_group "Settings" "Everyday screensaver settings" \
    menu_sam_timer "Timing: idle delay and time per game" \
    menu_autoplay "Autoplay: start SAM when idle" \
    menu_mute "Sound: mute games during SAM" \
    menu_artwork "Artwork: covers and installed packs" \
    menu_addons "Display, music and video add-ons" \
    menu_advanced "Advanced and maintenance"
}

function menu_advanced() {
  sam_menu_group "Advanced and maintenance" "Options for customized setups" \
    menu_advancedsettings "Startup, core weighting, input and debug" \
    menu_inieditor "Edit MiSTer_SAM.ini" \
    startmonitor "Start SAM with SSH Monitor" \
    menu_diagnostics "Diagnostics and logs" \
    update "Update SAM" \
    menu_reset "Rebuild lists, reset or uninstall"
}

function menu_diagnostics() {
  sam_menu_group "Diagnostics and logs" "History is kept in RAM until reboot. Upload sends a filtered log to public 0x0.st; anyone with its link can read it." \
    menu_diagnostics_recent "View recent decisions, exit and failure" \
    menu_diagnostics_verbose "View verbose SAM debug" \
    menu_diagnostics_preview "Preview the filtered upload log" \
    menu_diagnostics_upload "Upload log and get a shareable URL"
}

sam_diagnostics_view() {
  local file rc=0
  file=$(mktemp "${sam_ui_root:-/tmp}/sam-diagnostics.XXXXXX") || return 1
  python3 "$mrsampath/sam/diagnostics.py" --runtime "$mrsamtmp" "$@" > "$file" 2>&1 || rc=$?
  sam_dialog --title "[ Diagnostics and logs ]" --textbox "$file" 0 0 || true
  rm -f -- "$file"
  return "$rc"
}
menu_diagnostics_recent() { sam_diagnostics_view; }
menu_diagnostics_verbose() { sam_diagnostics_view --verbose; }
menu_diagnostics_preview() { sam_diagnostics_view --preview; }
menu_diagnostics_upload() { sam_diagnostics_view --upload; }


function menu_artwork() {
    # Load only the artwork setup helpers, even when artwork filtering is off.
    sam_artwork_root="$mrsampath/artwork"
    source "$sam_artwork_root/sam_artwork.sh" || return 1
    source "${mrsampath}/artwork/sam_artwork_menu.sh" || return 1
    sam_artwork_menu
}

function menu_sam_timer() {
  local rc choice timemin secs

  # Intro only once
  if [[ -z $shown_timer ]]; then
    sam_dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
           --msgbox $'Configure when SAM starts and for how long:\n\n• Delay = idle before showing games\n• Duration = how long to display games' 0 0
    shown_timer=1
  fi

  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Choose an option:" 0 0 0 \
             samtimeout1  "Wait 1 minute before showing games" \
             samtimeout2  "Wait 2 minutes before showing games" \
             samtimeout3  "Wait 3 minutes before showing games" \
             samtimeout5  "Wait 5 minutes before showing games" \
             gametimer1   "Show games for 1 minute" \
             gametimer2   "Show games for 2 minutes" \
             gametimer3   "Show games for 3 minutes" \
             gametimer5   "Show games for 5 minutes" \
             gametimer10  "Show games for 10 minutes" \
             gametimer15  "Show games for 15 minutes" \
      2> "${sam_menu_file}"

    rc=$? choice=$(<"${sam_menu_file}")
    clear
    # Back → return to Settings menu
    (( rc != 0 )) && return

    case "$choice" in
      samtimeout1|samtimeout2|samtimeout3|samtimeout5 )
        timemin=${choice#samtimeout}
        secs=$(( timemin * 60 ))
        samini_mod samtimeout "$secs"
        sam_dialog --clear --ascii-lines --no-cancel \
               --backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
               --msgbox "Delay set: $timemin minute(s) ($secs seconds)." 0 0
        ;;
      gametimer1|gametimer2|gametimer3|gametimer5|gametimer10|gametimer15 )
        timemin=${choice#gametimer}
        secs=$(( timemin * 60 ))
        samini_mod gametimer "$secs"
        sam_dialog --clear --ascii-lines --no-cancel \
               --backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
               --msgbox "Duration set: $timemin minute(s) ($secs seconds)." 0 0
        ;;
      * )
        sam_dialog --msgbox "Unknown selection: $choice" 0 0
        ;;
    esac
  done
}



function menu_mute() {
  local rc choice

  # Intro
  sam_dialog --clear --no-cancel --ascii-lines \
         --backtitle "Super Attract Mode" --title "[ MUTE INFO ]" \
         --msgbox $'SAM can mute the system volume globally while games are shown in Attract Mode.' \
         0 0

  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ MUTE OPTIONS ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Choose mute mode:" 0 0 0 \
             enablemute   "Enable global mute" \
             disablemute  "Disable global mute" \
      2> "${sam_menu_file}"

    rc=$? choice=$(<"${sam_menu_file}")
    clear
    # Back → return to Settings menu
    (( rc != 0 )) && return

    case "${choice,,}" in
      enablemute)
        samini_mod mute Yes
        sam_dialog --msgbox "Global mute enabled." 0 0
        ;;
      disablemute)
        samini_mod mute No
        sam_dialog --msgbox "Global mute disabled." 0 0
        ;;
      *)
        sam_dialog --msgbox "Unknown selection: $choice" 0 0
        ;;
    esac
  done
}


function menu_autoplay() {
  local rc choice

  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ Autoplay Configuration ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Enable or disable Autoplay:" 0 0 0 \
             enable    "Enable Autoplay" \
             disable   "Disable Autoplay" \
      2> "${sam_menu_file}"

    rc=$? choice=$(<"${sam_menu_file}")
    clear
    # Back → return to Settings menu
    (( rc != 0 )) && return

    case "${choice,,}" in
      enable)
        sam_enable
        sam_dialog --clear --ascii-lines --no-cancel \
               --backtitle "Super Attract Mode" --title "[ Autoplay Configuration ]" \
               --msgbox "Autoplay enabled." 0 0
        ;;
      disable)
        sam_disable
        sam_dialog --clear --ascii-lines --no-cancel \
               --backtitle "Super Attract Mode" --title "[ Autoplay Configuration ]" \
               --msgbox "Autoplay disabled." 0 0
        ;;
      *)
        sam_dialog --msgbox "Unknown selection: $choice" 0 0
        ;;
    esac
  done
}

#-------------------------------------------------------------------------------
# ADVANCED SETTINGS
#-------------------------------------------------------------------------------

# Rename of your “miscellaneous” submenu, now fully self-contained
function menu_advancedsettings() {
  # Show the initial info box only once per session
  if [[ "${shown_menu_misc:-0}" == "0" ]]; then
    sam_dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ ALT CORE MODE ]" \
           --msgbox "Alternative Core Mode will prefer cores with larger libraries so you don't get many repeats.

Please configure your controller in the main menu instead of using Play Current Game if possible." \
           0 0
    shown_menu_misc=1
  fi

  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --ok-label "Select" --cancel-label "Back" \
           --backtitle "Super Attract Mode" --title "[ Miscellaneous Settings ]" \
           --menu "Select from the following options:" 0 0 0 \
             enablemenuonly    "Start SAM only in MiSTer Menu" \
             disablemenuonly   "Start SAM outside of MiSTer Menu" \
             -----             "-----------------------------" \
             enablealtcore     "Enable Alternative Core Selection Mode" \
             disablealtcore    "Disable Alternative Core Selection Mode" \
             -----             "-----------------------------" \
             enablelistenjoy   "Enable Joystick detection" \
             disablelistenjoy  "Disable Joystick detection" \
             enablelistenkey   "Enable Keyboard detection" \
             disablelistenkey  "Disable Keyboard detection" \
             enablelistenmouse "Enable Mouse detection" \
             disablelistenmouse "Disable Mouse detection" \
             -----             "-----------------------------" \
             enabledebug       "Enable Debug" \
             disabledebug      "Disable Debug" \
             enabledebuglog    "Enable Debug Log File" \
             disabledebuglog   "Disable Debug Log File" \
      2> "${sam_menu_file}"

    local rc=$? choice=$(<"${sam_menu_file}")
    clear

    # “Back” → return to Settings menu
    (( rc != 0 )) && return

    case "${choice,,}" in
      enablemenuonly)    samini_mod menuonly Yes                   ;;
      disablemenuonly)   samini_mod menuonly No                    ;;
      enablealtcore)     samini_mod coreweight Yes                 ;;
      disablealtcore)    samini_mod coreweight No                  ;;
      enablelistenjoy)   samini_mod listenjoy Yes                  ;;
      disablelistenjoy)  samini_mod listenjoy No                   ;;
      enablelistenkey)   samini_mod listenkeyboard Yes             ;;
      disablelistenkey)  samini_mod listenkeyboard No              ;;
      enablelistenmouse) samini_mod listenmouse Yes                ;;
      disablelistenmouse) samini_mod listenmouse No                ;;
      enabledebug)       samini_mod samdebug Yes                   ;;
      disabledebug)      samini_mod samdebug No                    ;;
      enabledebuglog)    samini_mod samdebuglog Yes                ;;
      disabledebuglog)   samini_mod samdebuglog No                 ;;
      -----)             ;;  # no action, just a divider
      *)
        sam_dialog --msgbox "Unknown selection: $choice" 0 0
        ;;
    esac

    # Confirm the change, then loop back
    menu_changes_saved
  done
}

#-------------------------------------------------------------------------------
# RESET SAM
#-------------------------------------------------------------------------------

# in MiSTer_SAM_menu.sh

function menu_reset() {
  local rc choice

  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ Reset / Uninstall ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Choose an action:" 0 0 0 \
             menu_reset_gamelists "Reset all Game Lists" \
             menu_resetini       "Reset MiSTer_SAM.ini to defaults" \
             menu_deleteall      "Completely uninstall SAM" \
             menu_reinstall      "Reinstall SAM from scratch" \
      2> "${sam_menu_file}"

    rc=$? choice=$(<"${sam_menu_file}")
    clear
    (( rc != 0 )) && return

    case "${choice,,}" in
      menu_reset_gamelists) menu_reset_gamelists  ;;  # or call sam_gamelistmenu if you prefer
      menu_resetini)       menu_resetini        ;;
      menu_deleteall)      menu_deleteall       ;;
      menu_reinstall)      menu_reinstall       ;;
      *)                   sam_dialog --msgbox "Unknown selection: $choice" 0 0; continue ;;
    esac

    # For those that don’t self-confirm, give a "Done" box
    case "${choice,,}" in
      menu_resetini|menu_reinstall)
        sam_dialog --msgbox "Done." 0 0
        ;;
    esac
  done
}


function menu_reset_gamelists() {
  # Intro
  sam_dialog --clear --ascii-lines --colors \
         --backtitle "Super Attract Mode" --title "[ GAMELIST MENU ]" \
         --msgbox $'Game lists contain filenames SAM uses per core.\n\nThey\'re built automatically when SAM plays games, but you can recreate or remove them here.' \
         0 0

  while true; do
    sam_dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ GAMELIST MENU ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Choose an action:" 0 0 0 \
             menu_creategl   "Create all Game Lists" \
             menu_deletegl   "Delete all Game Lists" \
      2> "${sam_menu_file}"

    local rc=$? choice=$(<"${sam_menu_file}")
    clear
    # Back → return to Reset menu
    (( rc != 0 )) && return

    case "${choice,,}" in
      menu_creategl)
        sam_dialog --infobox "Creating all game lists..." 5 40
        if ! sam_rebuild_all_lists; then
            sam_dialog --msgbox "Gamelist rebuild failed. Check the storage and SAM output. Previous lists were preserved for scans that failed." 0 0
            return 1
        fi

		if [ ${inmenu} -eq 1 ]; then
			sleep 1
			: # Return through the existing menu stack.
		else
			echo -e "\nGamelist creation successful. Please start SAM now.\n"
			sleep 1
			parse_cmd stop
		fi
        sam_dialog --msgbox "All game lists created." 0 0
        return
        ;;
      menu_deletegl)
        sam_dialog --yesno "Really delete all game lists?" 7 50
        if (( $? == 0 )); then
          sam_dialog --infobox "Deleting all game lists..." 5 40
	# In case of issues, reset game lists

			there_can_be_only_one
			if [ -d "${gamelistpath}" ]; then
				echo "Deleting MiSTer_SAM Gamelist folder"
				rm -f "${gamelistpath}"/*_gamelist.txt
			fi

			if [ -d /tmp/.SAM_List ]; then
				rm -rf /tmp/.SAM_List
			fi

			if [ ${inmenu} -eq 1 ]; then
                : # Return through the existing sam_dialog stack.
			else
				echo -e "\nGamelist reset successful. Please start SAM now.\n"
				sleep 1
				parse_cmd stop
			fi
          sam_dialog --msgbox "All game lists deleted." 0 0
        fi
        return
        ;;
      *)
        sam_dialog --msgbox "Unknown selection: $choice" 0 0
        ;;
    esac
  done
}


function menu_resetini() {
  if declare -F sam_caller_require_runtime >/dev/null; then
    sam_caller_require_runtime || return 1
  fi
  local mcp_was_running=0 result=0
  if tmux has-session -t MCP 2>/dev/null ||
     python3 "$mrsampath/sam_mcp_process.py" --running "$mrsampath/MiSTer_SAM_MCP.py"; then
    mcp_was_running=1
  fi
  # Quiesce autostart before stopping the exact session. Restore monitoring on
  # every ordinary error path, including failed stop, download and INI writes.
  if mcp_stop; then
    sam_menu_resetini_apply "$@" || result=$?
  else
    result=$?
  fi
  if ((mcp_was_running)); then
    local restart_result=0
    mcp_start || restart_result=$?
    ((result != 0 || restart_result == 0)) || result=$restart_result
  fi
  return "$result"
}

sam_menu_resetini_apply() {
  local staged source_file key
  python3 "$mrsampath/samctl.py" stop || return 1
  # Preserve the runtime root: it contains ownership locks and the UI lease.
  # Only stopped-session lists and temporary mode/filter choices need clearing.
  rm -rf -- "$gamelistpathtmp" || return 1
  rm -f -- "$mrsamtmp/category-preset" "$mrsamtmp/gameroulette.ini" || return 1
  if (( $# == 0 )); then
    source_file="$mrsampath/MiSTer_SAM.default.ini"
    if [[ ! -f "$source_file" ]]; then
      get_samstuff MiSTer_SAM.ini /tmp || return 1
      source_file=/tmp/MiSTer_SAM.ini
    fi
    staged=$(mktemp "${samini_file}.reset.XXXXXX") || return 1
    if ! cp "$source_file" "$staged" || ! mv -f "$staged" "$samini_file"; then
      rm -f "$staged"
      return 1
    fi
    return 0
  fi
  for key in "$@"; do
    case "$key" in
      bgm) bgm_stop force; samini_mod bgm No || return 1 ;;
      samvideo)
        samini_mod samvideo No || return 1
        samini_mod samvideo_source "" || return 1 ;;
      m82) samini_mod m82 No || return 1 ;;
      *) printf "Unknown reset target '%s'\n" "$key" >&2; return 1 ;;
    esac
  done
}

function menu_deleteall() {
  local timestamp=$(date +%Y%m%d-%H%M%S)
  local backup_dir="/media/fat/Scripts/.SAM_Backup/${timestamp}"

  echo "→ Stopping any running SAM instances…"
  there_can_be_only_one

  echo "→ Creating backup at ${backup_dir}"
  mkdir -p "${backup_dir}"
  find "${ignorepath}" -name "*_excludelist.txt" -exec cp --parents '{}' "${backup_dir}" \; 2>/dev/null
  cp --parents "${samini_file}" "${backup_dir}/" 2>/dev/null

  # A helper to remount /
  local ro_root=false
  function with_rw_root() {
    mount | grep -qE 'on / .*[(,]ro[,$]' && { mount / -o remount,rw; ro_root=true; }
    "$@"
    $ro_root && mount / -o remount,ro
  }

  echo "→ Deleting MiSTer_SAM directory…"
  [[ -d "${mrsampath}" ]] && rm -rf "${mrsampath}"

  echo "→ Removing INI file…"
  [[ -f "${samini_file}" ]] && { cp "${samini_file}" "${samini_file}".bak; rm "${samini_file}"; }

  echo "→ Removing MiSTer_SAM_off.sh…"
  [[ -f "/media/fat/Scripts/MiSTer_SAM_off.sh" ]] && rm /media/fat/Scripts/MiSTer_SAM_off.sh

  echo "→ Cleaning up temporary lists…"
  rm -rf "/tmp/.SAM_List" "/tmp/.SAM_tmp"

  echo "→ Removing keyboard mapping files…"
  ls "${configpath}/inputs"*"_input_1234_5678_v3.map" &>/dev/null && rm "${configpath}/inputs"*"_input_1234_5678_v3.map"

  echo "→ Deleting auto‐boot daemon…"
  with_rw_root rm -f /etc/init.d/S93mistersam /etc/init.d/_S93mistersam

  echo "→ Cleaning up startup entries…"
  sed -i '/MiSTer_SAM/d;/Super Attract/d' "${userstartup}"

  echo
  echo "All SAM files removed. Backups are in ${backup_dir}."

  if (( inmenu == 1 )); then
    sleep 1
    sam_resetmenu
  else
    sleep 1
    parse_cmd stop
  fi
}


#-------------------------------------------------------------------------------
# MISC FUNCTIONS
#-------------------------------------------------------------------------------


# Display a simple “saved” confirmation
function menu_changes_saved() {
  sam_dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ Settings ]" \
         --msgbox "Changes saved!" 0 0
}

function reset_ini() { # args ${nextcore}
	# Build a comma-separated list of every core
	local allcores
	allcores=$(printf "%s\n" "${!CORE_PRETTY[@]}" | sort | paste -sd "," -)

	# A roulette marker is an enable switch, not a cache. Other presets must
	# clear it or they retain roulette's timer and disabled input listeners.
	rm -f -- "${mrsamtmp:-/tmp/.SAM_tmp}/gameroulette.ini"
    rm -f -- "${mrsamtmp:-/tmp/.SAM_tmp}/category-preset"
    samini_mod category_preset off

	# Mute cores, use every core, horizontal arcade by default
	samini_mod mute Yes
	samini_mod corelist "$allcores"
	samini_mod arcadeorient horizontal
	samini_mod bgm No
	samini_mod samvideo No
	samini_mod samvideo_tvc No
	samini_mod rating No
	samini_mod coreweight no
	samini_mod m82 no
	samini_mod sam_goat_list No
	samini_mod disable_blacklist No
	samini_mod dupe_mode normal

}
