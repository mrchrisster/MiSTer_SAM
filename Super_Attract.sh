#!/bin/bash

# Copyright (c) 2023 by mrchrisster and Mellified
# Refactored into a modular layout.

# --- Global Setup ---
# The trap is set here to be inherited by all sourced scripts.
trap '' SIGHUP

# Define base paths used by the libraries
declare -g mrsampath="/media/fat/Scripts/.MiSTer_SAM"
declare -g misterpath="/media/fat"
declare -g gamelistpath="${mrsampath}/SAM_Gamelists"
declare -g gamelistpathtmp="/tmp/.SAM_List"
declare -g mrsamtmp="/tmp/.SAM_tmp"

# --- Library Loader ---
# Source all the component parts of the script.
source "${mrsampath}/lib/utils.sh"
source "${mrsampath}/lib/config.sh"
source "${mrsampath}/lib/gamelists.sh"
source "${mrsampath}/lib/launchers.sh"

# --- Main Application Loop ---
function loop_core() { # loop_core (optional_core_name)
	echo -e "Starting Super Attract Mode...\nLet Mortal Kombat begin!\n"
	echo "" >/tmp/SAM_Games.log # Reset game log for this session
	samdebug "Initial corelist: ${corelist[*]}"

	while :; do
		# Attempt to launch a game.
		next_core "${1-}"

		if [ $? -eq 0 ]; then
			# SUCCESS: A game was launched.
			# If this was the first launch, start the background builder.
			if (( ! first_core_launched )); then
				samdebug "First core launched. Starting delayed background builder..."
				create_all_gamelists # This function backgrounds itself.
				first_core_launched=1
			fi
			run_countdown_timer
		else
			# FAILURE: Blacklist the core and retry immediately.
			echo "Core launch failed."
			echo "ERROR: Failed ${romloadfails} times. No valid game found for core: ${nextcore}"
			echo "ERROR: Core ${nextcore} is blacklisted!"
			delete_from_corelist "${nextcore}"
			echo "List of cores is now: ${corelist[*]}"
			echo "Trying the next available core..."
			continue
		fi
	done
}

# --- Command Parser and Entry Point ---
function main() {
    init_vars     # Initialize all default variables
    read_samini   # Read and apply settings from the INI file
    init_paths    # Create required temporary directories
    
    # If the script is run without arguments, it will dispatch based on the command.
    # The --source-only flag allows other scripts to source this file without executing it.
    if [ "${1,,}" != "--source-only" ]; then
        parse_cmd "${@}"
    fi
}

# Execute the main function with all passed arguments.
main "$@"
