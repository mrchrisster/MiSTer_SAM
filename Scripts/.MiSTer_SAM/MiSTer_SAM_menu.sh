#!/usr/bin/env bash
# MiSTer_SAM_menu.sh — Dialog-based menu layout for Super Attract Mode (SAM)
# Source this on demand from MiSTer_SAM_on.sh to expose only UI functions.

# Guard against double-sourcing
[[ -n "${SAM_MENU_LOADED:-}" ]] && return
SAM_MENU_LOADED=1

# Temporary file for dialog output
sam_menu_file="/tmp/.sam_menu_choice"

# All cores
# source /tmp/.SAM_tmp/sam_core_pretty

#-------------------------------------------------------------------------------
# PRESETS MENU
#-------------------------------------------------------------------------------
function menu_presets() {
  inmenu=1
  while true; do
    dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Exit" \
           --backtitle "Super Attract Mode" --title "[ Game Modes ]" \
           --menu "Use the arrow keys or d-pad+A to navigate" 0 0 0 \
             menu_preset_standard      "Default Setting - Play all cores muted" \
             menu_preset_svc           "Play TV commercials and then show the advertised game." \
             menu_preset_goat_mode     "Play the Greatest of All Time Attract modes." \
             menu_preset_80s           "Play 80s Music, no Handhelds and only Horiz. games." \
             menu_preset_maturetgfx    "Play Games rated mature for TurboGrafx-CD." \
             menu_preset_kids          "All-Ages ESRB games only (Kids Safe)" \
             menu_preset_m82_mode      "Turn your MiSTer into a NES M82 unit." \
             menu_preset_roulette      "Game Roulette (timed random games)" \
      2> "${sam_menu_file}"

    local rc=$? choice=$(<"${sam_menu_file}")
    clear
    (( rc != 0 )) && return    # Back/Exit

    # If the function exists, just call it:
    if declare -F "$choice" >/dev/null; then
      "$choice"
      return
    else
      dialog --msgbox "Unknown selection: $choice" 0 0
    fi
  done
}


function menu_preset_standard() {
  # Reset everything to defaults for this preset
  reset_ini

  # Finally, start SAM
  exec "$0" start 
}

function menu_preset_svc() {
  # 1) Reset to a clean INI
  reset_ini

  # 2) Inform the user what this mode does
  dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ SAMVIDEO MODE ]" \
         --msgbox "This mode will download commercials from archive.org, play them on your MiSTer,\nand then attempt to launch the advertised game.\n\nExperimental: results may vary!" \
         0 0

  # 3) Choose video output
  exec 3>&1
  selection=$(dialog --clear --ascii-lines --no-cancel --backtitle "Super Attract Mode" \
            --title "[ Video Output ]" \
            --menu "Select your display device:" 0 0 0 \
              1 "HDMI" \
              2 "CRT" \
            2>&1 1>&3)
  exec 3>&-
  (( $? != 0 )) && return  # cancelled

  if [[ "$selection" == "1" ]]; then
    samini_mod samvideo_output HDMI
  else
    samini_mod samvideo_output CRT
  fi

  # 4) Ask about keeping local copies
  exec 3>&1
  keep=$(dialog --clear --ascii-lines --no-cancel --backtitle "Super Attract Mode" \
           --title "[ Local Copies ]" \
           --menu "Keep local copies of commercials? (~4GB req’d)" 0 0 0 \
             1 "Yes" \
             2 "No" \
           2>&1 1>&3)
  exec 3>&-
  (( $? != 0 )) && return

  if [[ "$keep" == "1" ]]; then
    samini_mod keep_local_copy Yes
  else
    samini_mod keep_local_copy No
  fi

  # 5) Core & BGM config for video mode
  samini_mod corelist "arcade,atarilynx,gb,gbc,genesis,gg,megacd,n64,nes,psx,saturn,s32x,sgb,sms,snes,tgfx16,tgfx16cd"
  samini_mod samvideo Yes
  samini_mod samvideo_source Archive
  samini_mod samvideo_tvc Yes

  # 6) Ensure the NES TV commercial list is present
  if [[ ! -f "${gamelistpath}/nes_tvc.txt" ]]; then
    get_samvideo
  fi

  # 7) Final confirmation
  dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ All Set ]" \
         --msgbox "Configuration saved. Press OK to start SAMVIDEO mode.\n\nIf commercials are slow to appear, give it a moment to download first." \
         0 0

  # 8) Launch it
  exec "$0" start 
}

# Function to process the GOAT list and create game list files
function menu_preset_goat_mode() {
  reset_ini
  # 1) Show info
  dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ GOAT MODE ]" \
         --msgbox "GOAT Attract Mode will only play games deemed to have the Greatest of All Time Attract Modes.\n\nPress OK to prepare the lists and return to the menu." \
         0 0
		
  samini_mod sam_goat_list yes

  # 4) Back to main menu
  tmp_reset
  exec "$0" start 
}

function menu_preset_80s() {
	reset_ini
	samini_mod corelist "amiga,arcade,fds,genesis,megacd,n64,neogeo,nes,saturn,s32x,sms,snes,tgfx16,tgfx16cd,psx"
	samini_mod arcadeorient horizontal
	enablebgm
	exec "$0" start 
}

function menu_preset_maturetgfx() {
  # 1) Reset INI to defaults
  reset_ini

  # 2) Inform the user about this preset
  dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ Mature TGFX Mode ]" \
         --msgbox "Mature TGFX Mode will only show mature-rated TurboGrafx-CD titles.\n\nEnjoy the edgier side of the library!" \
         0 0

  # 3) Disable any blacklist, set rating filter, and restrict to TGFX-CD core
  samini_mod disable_blacklist Yes
  samini_mod rating mature
  samini_mod corelist tgfx16cd

  # 4) Launch SAM
  exec "$0" start 
}


menu_preset_kids() {
	reset_ini
	dialog --clear --no-cancel --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ MATURE TGFX ]" \
		--msgbox "SAM uses ESRB rated games to only show games suitable for all ages.\n\nPlease feel free to contribute by editing the lists under .MiSTER_SAM/SAM_Rated folder." 0 0
	samini_mod rating kids
	corelist_value=$(printf "%s\n" "${RATED_FILES[@]}" | sed -E 's/_.+\.txt$//' | sort -u | paste -sd, -)
	corelist_line="corelist=\"${corelist_value}\""
	sed -i '/^corelist=/c\'"$corelist_line" $samini_file
	exec "$0" start 
}


# M82 mode
menu_preset_m82_mode() {
	reset_ini
	dialog --clear --no-cancel --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ M82 MODE ]" \
		--msgbox "SAM will act as an M82 unit for NES. To disable this, go to MiSTer_SAM.ini and find m82 option or change to another preset.\n\nPlease make sure you configure Gamepad in SAM's menu\n\nGame Timer is set to ${m82_game_timer}s per Game - Change m82_game_timer in SAM's ini\n\nMiSter will restart now. " 0 0
		samini_mod m82 Yes
		exec "$0" start 
	

}

function menu_preset_roulette_mode() {
  # Reset to defaults for Roulette mode
  reset_ini

  # Explain the mode
  dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ GAME ROULETTE ]" \
         --msgbox "Game Roulette mode picks a random title for you to play for a set time, then moves on to the next random title.\n\nEnjoy the surprise!" \
         0 0

  while true; do
    dialog --clear --ascii-lines --no-tags \
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

    # Build a temporary INI for this roulette session
    mkdir -p /tmp/.SAM_tmp
    case "$choice" in
      Roulettetimer)
        echo "gametimer=${roulettetimer}" > /tmp/.SAM_tmp/gameroulette.ini
        ;;
      Roulette*)
        local mins=${choice//Roulette/}
        echo "gametimer=$((mins*60))" > /tmp/.SAM_tmp/gameroulette.ini
        ;;
      *)
        dialog --msgbox "Unknown selection: $choice" 0 0
        continue
        ;;
    esac

    # Always disable core listening during roulette
    {
      echo "mute=no"
      echo "listenmouse=No"
      echo "listenkeyboard=No"
      echo "listenjoy=No"
    } >> /tmp/.SAM_tmp/gameroulette.ini

    # Launch SAM with the roulette INI
    exec "$0" start 
    return
  done
}




#-------------------------------------------------------------------------------
# CORE LIST CONFIGURATOR
#-------------------------------------------------------------------------------
function menu_coreconfig() {
  # Show intro only once
  if [[ -z $shown_coreconfig ]]; then
    dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ CORE CONFIG ]" \
           --msgbox "Current corelist:\n\n${corelist[*]}" 0 0
    shown_coreconfig=1
  fi

  local opts=(
    menu_corelist_preset   "Presets for Core List"
    menu_choose_cores      "Enable/Disable cores (keyboard only)"
    menu_singlecore        "Only play games from one core (until reboot)"
  )

  while dialog --clear --ascii-lines --no-tags \
               --backtitle "Super Attract Mode" --title "[ CORE CONFIG ]" \
               --ok-label "Select" --cancel-label "Back" \
               --menu "Select an option:" 0 0 0 \
               "${opts[@]}" 2>"${sam_menu_file}"; do

    clear
    choice=$(<"${sam_menu_file}")

    if declare -F "$choice" >/dev/null; then
      "$choice"      # call menu_corelist_preset, menu_choose_cores, etc.
    else
      dialog --msgbox "Unknown selection: $choice" 0 0
    fi
  done
}


function menu_corelist_preset() {
  while true; do
    dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ CORELIST PRESET ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Select a preset" 0 0 0 \
             2 "Only Arcade & Console Cores" \
             1 "Only Arcade and NeoGeo games" \
             6 "Only Arcade and NeoGeo games from the 1990s" \
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
         dialog --clear --ascii-lines --no-cancel \
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
        dialog --msgbox "Unknown selection: $choice" 0 0
        continue
        ;;
    esac

    # Confirm & loop
    dialog --clear --ascii-lines --no-cancel \
           --backtitle "Super Attract Mode" --title "[ CORELIST PRESET ]" \
           --msgbox "Changes saved!" 0 0
  done
}

function menu_choose_cores() {
  # Show warning only once
  if [[ -z $shown_choose_cores ]]; then
    dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ CORE CONFIGURATION ]" \
           --msgbox "Joystick isn’t supported for core toggling—use a keyboard (space to toggle).\n\nHit Back if you’re on a joystick." \
           0 0
    shown_choose_cores=1
  fi

  # Build the checklist entries once
  local opts=()
  for core in "${corelistall[@]}"; do
    local state=OFF
    [[ " ${corelist[*]} " == *" $core "* ]] && state=ON
    opts+=( "$core" "Show ${CORE_PRETTY[$core]} games" "$state" )
  done

  # Loop until the user hits “Back”
  while dialog --clear --ascii-lines --no-tags \
                --backtitle "Super Attract Mode" --title "[ CORE CONFIGURATION ]" \
                --ok-label "Save" --cancel-label "Back" \
                --separate-output --checklist "Toggle cores on/off:" 0 0 0 \
                "${opts[@]}" 2>"${sam_menu_file}"; do

    clear
    local choices=( $(<"${sam_menu_file}") )
    # If nothing selected, just loop again
    (( ${#choices[@]} == 0 )) && continue

    # Apply the new corelist
    local corelistmod
    corelistmod=$(IFS=,; echo "${choices[*]}")
    samini_mod corelist "$corelistmod"

    dialog --clear --ascii-lines --no-cancel \
           --backtitle "Super Attract Mode" --title "[ CORE CONFIGURATION ]" \
           --msgbox "Changes saved! Corelist is now: $corelistmod" \
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
    dialog --clear --ascii-lines --no-tags \
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
    exec "$0" "${choice,,}"
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
    dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ Exit Behavior ]" \
           --msgbox "$msg" 0 0
    shown_exitbehavior=1
  fi

  # Loop until the user hits “Back”
  while dialog --clear --ascii-lines --no-tags \
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
        dialog --msgbox "Unknown selection: $choice" 0 0
        continue
        ;;
    esac

    dialog --clear --ascii-lines --no-cancel \
           --backtitle "Super Attract Mode" --title "[ Exit Behavior ]" \
           --msgbox "Changes saved!" 0 0
  done
}

#-------------------------------------------------------------------------------
# CONTROLLER CONFIGURATOR
#-------------------------------------------------------------------------------
function menu_controller() {
    # 1) Gather all joystick devices
    mapfile -t devices < <(ls /dev/input/js* 2>/dev/null)
    total=${#devices[@]}

    # 2) Build a parallel array of friendly names
    names=()
    for dev in "${devices[@]}"; do
        js=$(basename "$dev")
        model=$(udevadm info --query=property --name="$dev" 2>/dev/null \
                | awk -F= '/^ID_MODEL=/{print $2}')
        if [[ -z "$model" ]]; then
            sysfs="/sys/class/input/$js/device/name"
            [[ -r "$sysfs" ]] && model=$(cat "$sysfs")
        fi
        names+=( "$model" )
    done

    # 3) No controllers?
    if (( total == 0 )); then
        dialog --backtitle "Super Attract Mode" --title "[ CONTROLLER SETUP ]" \
               --msgbox "No joysticks connected." 0 0
        sam_exittask
    fi

	# 4) If more than one, prompt to pick by friendly name
	if (( total > 1 )); then
		menu=()
		for i in "${!devices[@]}"; do
			tag=$((i+1))
			menu+=( "$tag" "${names[i]}" )
		done
	
		# --- START: MODIFIED BLOCK ---
	
		# Create a temporary file to store the choice from the menu
		CHOICE_TMP=$(mktemp)
	
		dialog --backtitle "Super Attract Mode" --title "[ CONTROLLER SETUP ]" \
			   --menu "Multiple controllers detected.\nSelect one to configure:" \
			   0 0 0 "${menu[@]}" 2> "$CHOICE_TMP"
	
		# Capture the dialog exit status
		exit_status=$?
	
		# Check the exit status
		if [[ $exit_status -ne 0 ]]; then
			# If status is not 0, the user pressed Cancel or ESC.
			rm -f "$CHOICE_TMP" # Clean up temp file
			sam_exittask         # Call the exit function
			return               # Exit the current function
		fi
	
		# If we are here, the user pressed OK. Proceed to get the choice.
		choice=$(< "$CHOICE_TMP")
		rm -f "$CHOICE_TMP" # Clean up temp file
	
		# --- END: MODIFIED BLOCK ---
	
		sel=$((choice-1))
		# Add a check to ensure the selection is valid
		if [[ -z "$choice" || $sel -lt 0 || $sel -ge ${#devices[@]} ]]; then
			dialog --msgbox "Invalid selection." 0 0
			sam_exittask
			return
		fi
		device="${devices[sel]}"
		name="${names[sel]}"
	else
		device="${devices[0]}"
		name="${names[0]}"
	fi
    # 5) Prompt & wait for START button
    dialog --backtitle "Super Attract Mode" --title "[ CONTROLLER SETUP ]" \
           --infobox "Using:\n  $name\n($device)\n\n⏳ Waiting for you to press the START button..." \
           8 50

    id="$(${mrsampath}/MiSTer_SAM_joy.py "$device" id)"
    startbtn="$(${mrsampath}/MiSTer_SAM_joy.py "$device" button)"

    dialog --clear
    dialog --backtitle "Super Attract Mode" --title "[ CONTROLLER SETUP ]" \
           --msgbox "Got it! START = button $startbtn" 6 50

    # 6) Prompt & wait for NEXT button
    dialog --backtitle "Super Attract Mode" --title "[ NEXT BUTTON SETUP ]" \
           --infobox "Press the button you want to use for NEXT GAME (eg SELECT Button)...\n\n⏳ Waiting for NEXT button press..." \
           6 50

    nextbtn="$(${mrsampath}/MiSTer_SAM_joy.py "$device" button)"

    dialog --clear
    dialog --backtitle "Super Attract Mode" --title "[ NEXT BUTTON SETUP ]" \
           --msgbox "Great! NEXT = button $nextbtn" 6 50

    # 7) Save into JSON
    c_json="${mrsampath}/sam_controllers.json"
    c_custom_json="${mrsampath}/sam_controllers.custom.json"

    if [[ "$startbtn" == *not\ exist* || "$nextbtn" == *not\ exist* ]]; then
        dialog --backtitle "Super Attract Mode" --title "[ CONTROLLER SETUP ]" \
               --msgbox "No joysticks connected." 0 0
        sam_exittask
    fi

    # ensure custom file exists
    if [[ ! -f "$c_custom_json" ]]; then
        cp "$c_json" "$c_custom_json"
    fi

    # merge safely into custom
    if jq --arg name  "$name" \
          --arg id    "$id" \
          --argjson start "$startbtn" \
          --argjson next  "$nextbtn" \
          '. + {($id): {"name": $name, "button": {"start": $start, "next": $next}, "axis": {}}}' \
          "$c_custom_json" > /tmp/temp.json
    then
        mv /tmp/temp.json "$c_custom_json"
    else
        dialog --backtitle "Super Attract Mode" --title "[ ERROR ]" \
               --msgbox "Failed to update controller JSON:\n$c_custom_json" 0 0
        return 1
    fi

	# only prompt if needed
	if ! grep -qEi '^[[:space:]]*playcurrentgame[[:space:]]*=[[:space:]]*"?[Nn][Oo]"?[[:space:]]*$' "$samini_file"; then
		dialog --backtitle "Super Attract Mode" --yesno \
		"Should we adjust settings so that only pushing START button will play the active game?\
		\n(While SAM is running, push any button to return to Menu unless START or NEXT button are pressed.)" 0 0
					…
	fi
	dialog --clear --ascii-lines --no-cancel \
	--backtitle "Super Attract Mode" --title "[ GAME CONTROLLER ]" \
	--msgbox "Changes saved./n/nIf it doesn't work right away, you might have to restart your MiSTer. " 0 0
	sam_menu
	tmp_reset
}

#-------------------------------------------------------------------------------
# FILTERS
#-------------------------------------------------------------------------------


function menu_filters() {
  local rc choice
  while true; do
    dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ Filters ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Select a filter option:" 0 0 0 \
             menu_cat_include   "Include single category/genre" \
             menu_cat_exclude   "Exclude categories/genres" \
             arcadehoriz    	"Horizontal arcade only" \
             arcadevert         "Vertical arcade only" \
             arcadedisable      "Show all arcade games" \
      2> "${sam_menu_file}"

    rc=$? choice=$(<"${sam_menu_file}")
    clear
    # Back → return to Main Menu
    (( rc != 0 )) && return

    case "${choice,,}" in
      menu_cat_include)
        menu_cat_include    
        ;;
      menu_cat_exclude)
        menu_cat_exclude   
        ;;
      arcadehoriz)
        samini_mod arcadepathfilter _Horizontal
        samini_mod arcadeorient horizontal
        menu_changes_saved
        ;;
      arcadevert)
        samini_mod arcadeorient vertical
        menu_changes_saved
        ;;
      arcadedisable)
        samini_mod arcadeorient
        menu_changes_saved
        ;;
      *)
        dialog --msgbox "Unknown selection: $choice" 0 0
        ;;
    esac
  done
}

function menu_cat_include() {
  reset_ini
  local rc choice categ


  # 1) Intro
  dialog --clear --no-cancel --ascii-lines \
         --backtitle "Super Attract Mode" --title "[ CATEGORY SELECTION ]" \
         --msgbox $'Play games from only one category.\n\nUse Everdrive packs for this mode.\nMake sure you have built game lists first.' \
         0 0

  # 2) Pick a category
  while dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ CATEGORY SELECTION ]" \
		--ok-label "Select" --cancel-label "Back" \
		--menu "Only play games from the following categories:" 0 0 0 \
		 usa         "Only USA Games" \
		 japan       "Only Japanese Games" \
		 europe      "Only European Games" \
		 shoot-em    "Only Shoot ’Em Ups" \
		 beat-em     "Only Beat ’Em Ups" \
		 rpg         "Only Role-Playing Games" \
		 pinball     "Only Pinball Games" \
		 platformers "Only Platformers" \
		 fighting    "Only Fighting Games" \
		 trivia      "Only Trivia Games" \
		 sports      "Only Sports Games" \
		 racing      "Only Racing Games" \
		 hacks       "Only Hacks" \
		 kiosk       "Only Kiosk Mode Games" \
		 translations "Only Translations" \
		 homebrew    "Only Homebrew" \
    2> "${sam_menu_file}"; do

    rc=$? choice=$(<"${sam_menu_file}")
    clear
    (( rc != 0 )) && return

    categ="$choice"
    echo "Please wait… filtering lists for '$categ'"

    # clear out the temp folder
    rm -f "${gamelistpathtmp}"/*_gamelist.txt

    # for each existing gamelist, grep the category
    find "${gamelistpath}" -name "*_gamelist.txt" | while read -r list; do
      listfile=$(basename "$list")
      # directly grep+dedupe into the temp gamelist file
      grep -i -- "$categ" "$list" | awk -F'/' '!seen[$NF]++' \
        > "${gamelistpathtmp}/${listfile}"
      # if there were no matches, remove the empty file so later logic skips it
      [[ ! -s "${gamelistpathtmp}/${listfile}" ]] && rm -f "${gamelistpathtmp}/${listfile}"
    done

    # collect which cores survived
    readarray -t corelist <<< \
      "$(find "${gamelistpathtmp}" -name "*_gamelist.txt" \
             -exec basename {} \; | cut -d _ -f1)"
    corelistmod=$(IFS=,; echo "${corelist[*]}")

    # write out the corelist file for SAM
    printf "%s\n" "${corelist[@]}" > "${corelistfile}"

    dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ CATEGORY SELECTION ]" \
           --msgbox "Now playing *only* '${categ^^}' games.\nReboot will reset to all games." \
           0 0

    exec "$0" start
  done
}

function menu_cat_exclude() {
  local rc choice categ excludetags

  excludetags="${gamelistpath}/.excludetags"

  # show current exclusions (once)
  if [[ -f $excludetags ]]; then
    dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ EXCLUDE CATEGORIES ]" \
           --msgbox "Currently excluded tags:\n\n$(<"$excludetags")" \
           0 0
  else
    dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ EXCLUDE CATEGORIES ]" \
           --msgbox "Exclude certain categories (e.g. hacks, homebrew) so SAM never shows those games." \
           0 0
  fi

  while dialog --clear --ascii-lines --no-tags \
               --backtitle "Super Attract Mode" --title "[ EXCLUDE CATEGORIES ]" \
               --ok-label "Select" --cancel-label "Done" \
               --menu "Which tag would you like to toggle?" 0 0 0 \
                 Beta         "Beta Games" \
                 Hack         "Hacks" \
                 Homebrew     "Homebrew" \
                 Prototype    "Prototypes" \
                 Unlicensed   "Unlicensed Games" \
                 Translations "Translated Games" \
                 USA          "USA Games" \
                 Japan        "Japanese Games" \
                 Europe       "European Games" \
                 Reset        "Clear all exclusions" \
        2> "${sam_menu_file}"; do

    rc=$? choice=$(<"${sam_menu_file}")
    clear
    (( rc != 0 )) && return

    # Clear all
    if [[ "$choice" == Reset ]]; then
      rm -f "$excludetags" "${gamelistpath}"/*_gamelist_exclude.txt
      sync
      dialog --msgbox "All exclusion filters removed." 0 0
      continue
    fi

    # Toggle this tag in the excludetags file
    if grep -qi "^${choice}$" "$excludetags" 2>/dev/null; then
      # already excluded → remove it
      grep -v -i "^${choice}$" "$excludetags" >"${excludetags}.tmp"
      mv "${excludetags}.tmp" "$excludetags"
      sync "$excludetags"
      dialog --msgbox "'$choice' un‐excluded." 0 0
    else
      # add it
      echo "$choice" >> "$excludetags"
      sync "$excludetags"
      dialog --msgbox "'$choice' will now be excluded." 0 0
    fi

    # rebuild per-core exclusion lists
    while read -r core; do
      # remove any old tmp file
      rm -f "${gamelistpathtmp}/${core}_gamelist.txt"
      # filter out excluded tags
      grep -viv -f "$excludetags" "${gamelistpath}/${core}_gamelist.txt" \
        > "${gamelistpath}/${core}_gamelist_exclude.txt"
      sync "${gamelistpath}/${core}_gamelist_exclude.txt"
    done < <(printf "%s\n" "${corelist[@]}")

  done
}


#-------------------------------------------------------------------------------
# ADD-ONS
#-------------------------------------------------------------------------------
# $mrsampath/MiSTer_SAM_menu.sh

function menu_addons() {
  local rc choice

  # Show intro only once (no change here)
  if [[ -z $shown_bgmmenu ]]; then
    dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ SAMVIDEO, BGM & TTY2OLED ]" \
           --msgbox $'SAMVIDEO\n----------------\nVideo playback on MiSTer (toggles per core).\n\nBGM\n----------------\nPlay background music while SAM shuffles games.\n\nTTY2OLED\n----------------\nHardware display support (only if you have TTY2OLED).' 0 0
    shown_bgmmenu=1
  fi

  while true; do
    dialog --clear --ascii-lines --no-tags \
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
        bgm_stop
        rm -f /media/fat/Scripts/bgm.sh /media/fat/music/bgm.ini
        sed -i '/bgm.sh/d;/Startup BGM/d' "${userstartup}"
        samini_mod bgm No
        ;;
      enabletty)  samini_mod ttyenable Yes        ;;
      disabletty) samini_mod ttyenable No         ;;
      *)
        dialog --msgbox "Unknown selection: $choice" 0 0
        continue
        ;;
    esac

    dialog --clear --ascii-lines --no-cancel \
           --backtitle "Super Attract Mode" --title "[ SAMVIDEO, BGM & TTY2OLED ]" \
           --msgbox "Changes saved!" 0 0
  done
}

function enablebgm() {
	if [ ! -f "/media/fat/Scripts/bgm.sh" ]; then
		echo " Installing BGM to Scripts folder"
		repository_url="https://github.com/wizzomafizzo/MiSTer_BGM"
		curl_download "/tmp/bgm.sh" "https://raw.githubusercontent.com/wizzomafizzo/MiSTer_BGM/main/bgm.sh"
		mv --force /tmp/bgm.sh /media/fat/Scripts/
	else
		echo " BGM script is installed already. Updating just in case..."
		echo -n "stop" | socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
		kill -9 "$(ps -o pid,args | grep '[b]gm.sh' | awk '{print $1}' | head -1)" 2>/dev/null
		rm /tmp/bgm.sock 2>/dev/null
		curl_download "/tmp/bgm.sh" "https://raw.githubusercontent.com/wizzomafizzo/MiSTer_BGM/main/bgm.sh"
		mv --force /tmp/bgm.sh /media/fat/Scripts/
		echo " Resetting BGM now."
	fi
	#echo " Updating MiSTer_SAM.ini to use Mute=No"
	samini_mod mute No
	/media/fat/Scripts/bgm.sh &>/dev/null &
	sync
	get_samstuff Media/80s.pls /media/fat/music
	[[ ! $(grep -i "bgm" "${samini_file}") ]] && echo "bgm=Yes" >> "${samini_file}"
	samini_mod bgm Yes
	echo " Enabling BGM debug so SAM can see what's playing.."
	sleep 5
	if grep -q '^debug = no' /media/fat/music/bgm.ini; then
		sed -i 's/^debug = no/debug = yes/' /media/fat/music/bgm.ini
		sleep 1
	fi
	#echo " All Done. Starting SAM now."
	exec "$0" start
}


#-------------------------------------------------------------------------------
# INI Editor
#-------------------------------------------------------------------------------

function menu_inieditor() {
  local rc tmpfile

  # Intro message
  dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ INI Settings ]" \
         --msgbox "Edit MiSTer_SAM.ini directly.\n\nUse TAB to switch between file, OK and Cancel." 0 0

  # Loop: allow multiple edits until user cancels
  while true; do
    dialog --clear --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ INI Settings ]" \
           --ok-label "Save" --cancel-label "Back" \
           --editbox "${samini_file}" 0 0 2> "${sam_menu_file}"

    rc=$?
    tmpfile="${sam_menu_file}"
    clear

    # Back/Cancel → exit without further action
    (( rc != 0 )) && return

    # Only copy back if file is non-empty and differs
    if [[ -s "$tmpfile" ]] && ! diff -wq "$tmpfile" "${samini_file}" >/dev/null; then
      cp -f "$tmpfile" "${samini_file}"
      dialog --clear --ascii-lines --no-cancel \
             --backtitle "Super Attract Mode" --title "[ INI Settings ]" \
             --msgbox "Changes saved!" 0 0
    else
      # No changes → just continue or break
      dialog --clear --ascii-lines --no-cancel \
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
function menu_settings() {
  while true; do
    dialog --clear --ascii-lines --no-tags \
           --ok-label "Select" --cancel-label "Back" \
           --backtitle "Super Attract Mode" --title "[ Settings ]" \
           --menu "Configure SAM behavior" 0 0 0 \
             menu_sam_timer             "Select Timers: delay & duration" \
             menu_mute              	"Mute cores while SAM is on" \
             menu_autoplay              "Autoplay configuration" \
             menu_enablekidssafe        "Enable Kids Safe Filter" \
             menu_disablekidssafe       "Disable Kids Safe Filter" \
             menu_advancedsettings 		"Advanced Settings" \
      2> "${sam_menu_file}"

    local rc=$? choice=$(<"${sam_menu_file}")
    clear
    # “Back” selected → exit to Main Menu
    (( rc != 0 )) && break

    case "${choice,,}" in
      enablekidssafe)
        enable_kids_safe
        ;;
      disablekidssafe)
        disable_kids_safe
        ;;
      *)
        parse_cmd "${choice,,}"
        ;;
    esac
  done
}


function menu_sam_timer() {
  local rc choice timemin secs

  # Intro only once
  if [[ -z $shown_timer ]]; then
    dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
           --msgbox $'Configure when SAM starts and for how long:\n\n• Delay = idle before showing games\n• Duration = how long to display games' 0 0
    shown_timer=1
  fi

  while true; do
    dialog --clear --ascii-lines --no-tags \
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
      samtimeout* )
        timemin=${choice#samtimeout}
        secs=$(( timemin * 60 ))
        samini_mod samtimeout "$secs"
        dialog --clear --ascii-lines --no-cancel \
               --backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
               --msgbox "Delay set: $timemin minute(s) ($secs seconds)." 0 0
        ;;
      gametimer* )
        timemin=${choice#gametimer}
        secs=$(( timemin * 60 ))
        samini_mod gametimer "$secs"
        dialog --clear --ascii-lines --no-cancel \
               --backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
               --msgbox "Duration set: $timemin minute(s) ($secs seconds)." 0 0
        ;;
      * )
        dialog --msgbox "Unknown selection: $choice" 0 0
        ;;
    esac
  done
}



function menu_mute() {
  local rc choice

  # Intro
  dialog --clear --no-cancel --ascii-lines \
         --backtitle "Super Attract Mode" --title "[ MUTE INFO ]" \
         --msgbox $'SAM uses each core’s built-in mute (low volume alert still possible).\n\nGlobal mute works system-wide but is less tested.' \
         0 0

  while true; do
    dialog --clear --ascii-lines --no-tags \
           --backtitle "Super Attract Mode" --title "[ MUTE OPTIONS ]" \
           --ok-label "Select" --cancel-label "Back" \
           --menu "Choose mute mode:" 0 0 0 \
             globalmute   "Global volume mute" \
             disablemute  "Core-level unmute" \
      2> "${sam_menu_file}"

    rc=$? choice=$(<"${sam_menu_file}")
    clear
    # Back → return to Settings menu
    (( rc != 0 )) && return

    case "${choice,,}" in
      globalmute)
        samini_mod mute Yes
        dialog --msgbox "Global mute enabled." 0 0
        ;;
      disablemute)
        samini_mod mute No
        dialog --msgbox "Core mute disabled." 0 0
        ;;
      *)
        dialog --msgbox "Unknown selection: $choice" 0 0
        ;;
    esac
  done
}


function menu_autoplay() {
  local rc choice

  while true; do
    dialog --clear --ascii-lines --no-tags \
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
        samini_mod autoplay Yes
        dialog --clear --ascii-lines --no-cancel \
               --backtitle "Super Attract Mode" --title "[ Autoplay Configuration ]" \
               --msgbox "Autoplay enabled." 0 0
        ;;
      disable)
        samini_mod autoplay No
        dialog --clear --ascii-lines --no-cancel \
               --backtitle "Super Attract Mode" --title "[ Autoplay Configuration ]" \
               --msgbox "Autoplay disabled." 0 0
        ;;
      *)
        dialog --msgbox "Unknown selection: $choice" 0 0
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
    dialog --clear --no-cancel --ascii-lines \
           --backtitle "Super Attract Mode" --title "[ ALT CORE MODE ]" \
           --msgbox "Alternative Core Mode will prefer cores with larger libraries so you don't get many repeats.

Please configure your controller in the main menu instead of using Play Current Game if possible." \
           0 0
    shown_menu_misc=1
  fi

  while true; do
    dialog --clear --ascii-lines --no-tags \
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
        dialog --msgbox "Unknown selection: $choice" 0 0
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
    dialog --clear --ascii-lines --no-tags \
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
      *)                   dialog --msgbox "Unknown selection: $choice" 0 0; continue ;;
    esac

    # For those that don’t self-confirm, give a "Done" box
    case "${choice,,}" in
      menu_resetini|menu_reinstall)
        dialog --msgbox "Done." 0 0
        ;;
    esac
  done
}


function menu_reset_gamelists() {
  # Intro
  dialog --clear --ascii-lines --colors \
         --backtitle "Super Attract Mode" --title "[ GAMELIST MENU ]" \
         --msgbox $'Game lists contain filenames SAM uses per core.\n\nThey\'re built automatically when SAM plays games, but you can recreate or remove them here.' \
         0 0

  while true; do
    dialog --clear --ascii-lines --no-tags \
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
        dialog --infobox "Creating all game lists..." 5 40
		${mrsampath}/samindex -o "${gamelistpath}"
		
		if [ ${inmenu} -eq 1 ]; then
			sleep 1
			sam_menu
		else
			echo -e "\nGamelist creation successful. Please start SAM now.\n"
			sleep 1
			parse_cmd stop
		fi
        dialog --msgbox "All game lists created." 0 0
        return   
        ;;
      menu_deletegl)
        dialog --yesno "Really delete all game lists?" 7 50
        if (( $? == 0 )); then
          dialog --infobox "Deleting all game lists..." 5 40
          	# In case of issues, reset game lists

			there_can_be_only_one
			if [ -d "${mrsampath}/SAM_Gamelists" ]; then
				echo "Deleting MiSTer_SAM Gamelist folder"
				rm  "${mrsampath}"/SAM_Gamelists/*_gamelist.txt
			fi
		
			if [ -d /tmp/.SAM_List ]; then
				rm -rf /tmp/.SAM_List
			fi
		
			if [ ${inmenu} -eq 1 ]; then
				sleep 1
				sam_menu
			else
				echo -e "\nGamelist reset successful. Please start SAM now.\n"
				sleep 1
				parse_cmd stop
			fi
          dialog --msgbox "All game lists deleted." 0 0
        fi
        return  
        ;;
      *)
        dialog --msgbox "Unknown selection: $choice" 0 0
        ;;
    esac
  done
}


function menu_resetini() {
  # 1) Clean up any running SAM state
  rm -rf "/tmp/.SAM_List" "/tmp/.SAM_tmp"
  sam_cleanup

  # 2) No args → full INI reset
  if (( $# == 0 )); then
    if [[ -f "${mrsampath}/MiSTer_SAM.default.ini" ]]; then
      cp "${mrsampath}/MiSTer_SAM.default.ini" "${samini_file}"
    else
      get_samstuff MiSTer_SAM.ini /tmp
      cp /tmp/MiSTer_SAM.ini "${samini_file}"
    fi
    return
  fi

  # 3) Partial resets
  for key in "$@"; do
    case "$key" in
      bgm)
        bgm_stop force
        samini_mod bgm No
        ;;
      samvideo)
        samini_mod samvideo No
        samini_mod samvideo_source ""   # clear any selected source
        ;;
      m82)
        samini_mod m82 No
        ;;
      *)
        echo "Warning: unknown reset target '$key'" >&2
        ;;
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
  find "${mrsampath}/SAM_Gamelists" -name "*_excludelist.txt" -exec cp --parents '{}' "${backup_dir}" \; 2>/dev/null
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
  dialog --clear --ascii-lines --no-cancel \
         --backtitle "Super Attract Mode" --title "[ Settings ]" \
         --msgbox "Changes saved!" 0 0
}

function reset_ini() { # args ${nextcore}
	# Build a comma-separated list of every core
	corelistall=$(printf "%s\n" "${!CORE_PRETTY[@]}" | sort | paste -sd "," -)
	
	#Reset gamelists
	[[ -d /tmp/.SAM_List ]] && rm -rf /tmp/.SAM_List
	mkdir -p "${gamelistpathtmp}"
	mkdir -p /tmp/.SAM_tmp
	
	# Mute cores, use every core, horizontal arcade by default
	samini_mod mute Yes
	samini_mod corelist "$corelistall"
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
