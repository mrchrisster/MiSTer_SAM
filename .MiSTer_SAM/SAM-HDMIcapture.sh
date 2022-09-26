#!/bin/bash

# ======== INI VARIABLES ========
# Change these in the INI file
function init_vars() {
	# ======== GLOBAL VARIABLES =========
	declare -g mrsampath="/media/fat/Scripts/.MiSTer_SAM"
	declare -g misterpath="/media/fat"
	# Save our PID and process
	declare -g sampid="${$}"
	declare -g samprocess="$(basename -- ${0})"
	declare -gi inmenu=0
	declare -gi speedtest=0

	# ======== DEBUG VARIABLES ========
	declare -gl samquiet="Yes"
	declare -gl samdebug="No"
	declare -gl samtrace="No"

	# ======== LOCAL VARIABLES ========
	declare -gi coreretries=3
	declare -gi romloadfails=0
	declare -g gamelistpath="${mrsampath}/SAM_Gamelists"
	declare -g gamelistpathtmp="/tmp/.SAM_List/"
	declare -g excludepath="${mrsampath}"
	declare -g mralist_old="${mrsampath}/SAM_Gamelists/arcade_romlist"
	declare -g mralist="${mrsampath}/SAM_Gamelists/arcade_hdmi.txt"
	declare -g mralist_tmp_old="/tmp/.SAM_List/arcade_romlist"
	declare -g mralist_tmp="/tmp/.SAM_List/arcade_hdmi.txt"
	declare -g tmpfile="/tmp/.SAM_List/tmpfile"
	declare -g tmpfile2="/tmp/.SAM_List/tmpfile2"
	declare -g corelisttmpfile="/tmp/.SAM_List/corelist.tmp"													 
	declare -gi gametimer=110
	declare -gl corelist="arcade,atari2600,atari5200,atari7800,atarilynx,amiga,c64,fds,gb,gbc,gba,genesis,gg,megacd,neogeo,nes,s32x,sms,snes,tgfx16,tgfx16cd,psx"
	# Make all cores available for menu
	declare -gl corelistall="${corelist}"
	declare -gl create_all_gamelists="No"
	declare -gl skipmessage="Yes"
	declare -gl usezip="Yes"
	declare -gl norepeat="Yes"
	declare -gl disablebootrom="Yes"
	declare -gl mute="Yes"
	declare -gl playcurrentgame="No"
	declare -gl listenmouse="Yes"
	declare -gl listenkeyboard="Yes"
	declare -gl listenjoy="Yes"
	declare -g repository_url="https://github.com/mrchrisster/MiSTer_SAM"
	declare -g branch="main"
	declare -gi counter=0
	declare -g userstartup="/media/fat/linux/user-startup.sh"
	declare -g userstartuptpl="/media/fat/linux/_user-startup.sh"
	declare -gl usedefaultpaths="No"
	declare -gl neogeoregion="English"
	declare -gl useneogeotitles="Yes"
	declare -gl rebuild_freq="Week"
	declare -gi regen_duration=4
	declare -gi rebuild_freq_int="604800"
	declare -gl rebuild_freq_arcade="Week"
	declare -gi regen_duration_arcade=1
	declare -gi rebuild_freq_arcade_int="604800"
	declare -gi bootsleep="60"
	declare -gi countdown="nocountdown"								
	# ======== BGM =======
	declare -gl bgm="No"
	# ======== TTY2OLED =======
	declare -gl ttyenable="No"
	declare -g ttydevice="/dev/ttyUSB0"
	declare -g ttysystemini="/media/fat/tty2oled/tty2oled-system.ini"
	declare -g ttyuserini="/media/fat/tty2oled/tty2oled-user.ini"
	declare -gl ttyuseack="No"

	# ======== CORE PATHS ========
	declare -g amigapath="/media/fat/Games/Amiga"	
	declare -g arcadepath="/media/fat/_Arcade"
	declare -g atari2600path="/media/fat/Games/Atari7800"
	declare -g atari5200path="/media/fat/Games/Atari5200"
	declare -g atari7800path="/media/fat/Games/Atari7800"
	declare -g atarilynxpath="/media/fat/Games/AtariLynx"
	declare -g c64path="/media/fat/Games/C64"
	declare -g fdspath="/media/fat/Games/NES"
	declare -g gbpath="/media/fat/Games/Gameboy"
	declare -g gbcpath="/media/fat/Games/Gameboy"
	declare -g gbapath="/media/fat/Games/GBA"
	declare -g genesispath="/media/fat/Games/Genesis"
	declare -g ggpath="/media/fat/Games/SMS"
	declare -g megacdpath="/media/fat/Games/MegaCD"
	declare -g neogeopath="/media/fat/Games/NeoGeo"
	declare -g nespath="/media/fat/Games/NES"
	declare -g s32xpath="/media/fat/Games/S32X"
	declare -g smspath="/media/fat/Games/SMS"
	declare -g snespath="/media/fat/Games/SNES"
	declare -g tgfx16path="/media/fat/Games/TGFX16"
	declare -g tgfx16cdpath="/media/fat/Games/TGFX16-CD"
	declare -g psxpath="/media/fat/Games/PSX"

	# ======== CORE PATHS EXTRA ========
	declare -g amigapathextra=""
	declare -g arcadepathextra=""
	declare -g atari2600pathextra=""
	declare -g atari5200pathextra=""
	declare -g atari7800pathextra=""
	declare -g atarilynxpathextra=""
	declare -g c64pathextra=""
	declare -g fdspathextra=""
	declare -g gbpathextra=""
	declare -g gbcpathextra=""
	declare -g gbapathextra=""
	declare -g genesispathextra=""
	declare -g ggpathextra=""
	declare -g megacdpathextra=""
	declare -g neogeopathextra=""
	declare -g nespathextra=""
	declare -g s32xpathextra=""
	declare -g smspathextra=""
	declare -g snespathextra=""
	declare -g tgfx16pathextra=""
	declare -g tgfx16cdpathextra=""
	declare -g psxpathextra=""

	# ======== CORE PATHS RBF ========
	declare -g amigapathrbf="_Computer"
	declare -g arcadepathrbf="_Arcade"
	declare -g atari2600pathrbf="_Console"
	declare -g atari5200pathrbf="_Console"
	declare -g atari7800pathrbf="_Console"
	declare -g atarilynxpathrbf="_Console"
	declare -g c64pathrbf="_Computer"
	declare -g fdspathrbf="_Console"
	declare -g gbpathrbf="_Console"
	declare -g gbcpathrbf="_Console"
	declare -g gbapathrbf="_Console"
	declare -g genesispathrbf="_Console"
	declare -g ggpathrbf="_Console"
	declare -g megacdpathrbf="_Console"
	declare -g neogeopathrbf="_Console"
	declare -g nespathrbf="_Console"
	declare -g s32xpathrbf="_Console"
	declare -g smspathrbf="_Console"
	declare -g snespathrbf="_Console"
	declare -g tgfx16pathrbf="_Console"
	declare -g tgfx16cdpathrbf="_Console"
	declare -g psxpathrbf="_Console"


}



function update_tasks() {
	[ -s "${mralist_old}" ] && { mv "${mralist_old}" "${mralist}"; }
	[ -s "${mralist_tmp_old}" ] && { mv "${mralist_tmp_old}" "${mralist_tmp}"; }
}									 

function init_paths() {
	# Default rom path search directories
	declare -ga GAMESDIR_FOLDERS=(
		/media/usb0/games
		/media/usb1/games
		/media/usb2/games
		/media/usb3/games
		/media/usb4/games
		/media/usb5/games
		/media/fat/cifs/games
		/media/fat/games
		/media/usb0
		/media/usb1
		/media/usb2
		/media/usb3
		/media/usb4
		/media/usb5
		/media/fat/cifs
		/media/fat
	)

	declare -g GET_SYSTEM_FOLDER_GAMESDIR=""
	declare -g GET_SYSTEM_FOLDER_RESULT=""
	# Create folders if they don't exist
	mkdir -p "${mrsampath}/SAM_Gamelists"
	mkdir -p /tmp/.SAM_List
	[ -e "${tmpfile}" ] && { rm "${tmpfile}"; }
	[ -e "${tmpfile2}" ] && { rm "${tmpfile2}"; }
	[ -e "${corelisttmpfile}" ] && { rm "${corelisttmpfile}"; }
	if [ ${usedefaultpaths} == "yes" ]; then
		for core in ${corelistall}; do
			defaultpath "${core}"
		done
	fi
}

# ======== CORE CONFIG ========
function init_data() {
	# Core to long name mappings
	declare -gA CORE_PRETTY=(
		["arcade"]="MiSTer Arcade"
		["atari2600"]="Atari 2600"
		["atari5200"]="Atari 5200"
		["atari7800"]="Atari 7800"
		["atarilynx"]="Atari Lynx"
		["amiga"]="Commodore Amiga"
		["c64"]="Commodore 64"
		["fds"]="Nintendo Disk System"
		["gb"]="Nintendo Game Boy"
		["gbc"]="Nintendo Game Boy Color"
		["gba"]="Nintendo Game Boy Advance"
		["genesis"]="Sega Genesis / Megadrive"
		["gg"]="Sega Game Gear"
		["megacd"]="Sega CD / Mega CD"
		["neogeo"]="SNK NeoGeo"
		["nes"]="Nintendo Entertainment System"
		["s32x"]="Sega 32x"
		["sms"]="Sega Master System"
		["snes"]="Super Nintendo Entertainment System"
		["tgfx16"]="NEC PC Engine / TurboGrafx-16 "
		["tgfx16cd"]="NEC PC Engine CD / TurboGrafx-16 CD"
		["psx"]="Sony Playstation"
	)

	# Core to file extension mappings
	declare -glA CORE_EXT=(
		["amiga"]="hdf" 		#This is just a placeholder
		["arcade"]="mra"
		["atari2600"]="a26"     
		["atari5200"]="a52,car" 
		["atari7800"]="a78"     
		["atarilynx"]="lnx"		 
		["c64"]="crt,prg" 			# need to be tested "reu,tap,flt,rom,c1581"
		["fds"]="fds"
		["gb"]="gb"			 		
		["gbc"]="gbc"		 		
		["gba"]="gba"
		["genesis"]="md,gen" 		
		["gg"]="gg"
		["megacd"]="chd,cue"
		["neogeo"]="neo"
		["nes"]="nes"
		["s32x"]="32x"
		["sms"]="sms,sg"
		["snes"]="sfc,smc" 	 		# Should we include? "bin,bs"
		["tgfx16"]="pce,sgx"		
		["tgfx16cd"]="chd,cue"
		["psx"]="chd,cue,exe"
	)

	# Core to path mappings
	declare -gA CORE_PATH=(
		["amiga"]="${amigapath}"
		["arcade"]="${arcadepath}"
		["atari2600"]="${atari2600path}"
		["atari5200"]="${atari5200path}"
		["atari7800"]="${atari7800path}"
		["atarilynx"]="${atarilynxpath}"				  
		["c64"]="${c64path}"
		["fds"]="${fdspath}"
		["gb"]="${gbpath}"
		["gbc"]="${gbcpath}"
		["gba"]="${gbapath}"
		["genesis"]="${genesispath}"
		["gg"]="${ggpath}"
		["megacd"]="${megacdpath}"
		["neogeo"]="${neogeopath}"
		["nes"]="${nespath}"
		["s32x"]="${s32xpath}"
		["sms"]="${smspath}"
		["snes"]="${snespath}"
		["tgfx16"]="${tgfx16path}"
		["tgfx16cd"]="${tgfx16cdpath}"
		["psx"]="${psxpath}"
	)

	# Core to extra path mappings
	declare -gA CORE_PATH_EXTRA=(
		["amiga"]="${amigapathextra}"
		["arcade"]="${arcadepathextra}"
		["atari2600"]="${atari2600pathextra}"
		["atari5200"]="${atari5200pathextra}"
		["atari7800"]="${atari7800pathextra}"
		["atarilynx"]="${atarilynxpathextra}"					   
		["c64"]="${c64pathextra}"
		["fds"]="${fdspathextra}"
		["gb"]="${gbpathextra}"
		["gbc"]="${gbcpathextra}"
		["gba"]="${gbapathextra}"
		["genesis"]="${genesispathextra}"
		["gg"]="${ggpathextra}"
		["megacd"]="${megacdpathextra}"
		["neogeo"]="${neogeopathextra}"
		["nes"]="${nespathextra}"
		["s32x"]="${s32xpathextra}"
		["sms"]="${smspathextra}"
		["snes"]="${snespathextra}"
		["tgfx16"]="${tgfx16pathextra}"
		["tgfx16cd"]="${tgfx16cdpathextra}"
		["psx"]="${psxpathextra}"
	)

	# Core to path mappings for rbf files
	declare -gA CORE_PATH_RBF=(
		["amiga"]="${amigapathrbf}"
		["arcade"]="${arcadepathrbf}"
		["atari2600"]="${atari2600pathrbf}"
		["atari5200"]="${atari5200pathrbf}"
		["atari7800"]="${atari7800pathrbf}"
		["atarilynx"]="${atarilynxpathrbf}"					 
		["c64"]="${c64pathrbf}"
		["fds"]="${fdspathrbf}"
		["gb"]="${gbpathrbf}"
		["gbc"]="${gbcpathrbf}"
		["gba"]="${gbapathrbf}"
		["genesis"]="${genesispathrbf}"
		["gg"]="${ggpathrbf}"
		["megacd"]="${megacdpathrbf}"
		["neogeo"]="${neogeopathrbf}"
		["nes"]="${nespathrbf}"
		["s32x"]="${s32xpathrbf}"
		["sms"]="${smspathrbf}"
		["snes"]="${snespathrbf}"
		["tgfx16"]="${tgfx16pathrbf}"
		["tgfx16cd"]="${tgfx16cdpathrbf}"
		["psx"]="${psxpathrbf}"
	)

	# Can this core use ZIPped ROMs
	declare -glA CORE_ZIPPED=(
		["amiga"]="No"
		["arcade"]="No"
		["atari2600"]="Yes"
		["atari5200"]="Yes"
		["atari7800"]="Yes"
		["atarilynx"]="Yes"			 
		["c64"]="Yes"
		["fds"]="Yes"
		["gb"]="Yes"
		["gbc"]="Yes"
		["gba"]="Yes"
		["genesis"]="Yes"
		["gg"]="Yes"
		["megacd"]="No"
		["neogeo"]="Yes"
		["nes"]="Yes"
		["s32x"]="Yes"
		["sms"]="Yes"
		["snes"]="Yes"
		["tgfx16"]="Yes"
		["tgfx16cd"]="No"
		["psx"]="No"
	)

	# Can this core skip Bios/Safety warning messages
	declare -glA CORE_SKIP=(
		["amiga"]="No"
		["arcade"]="No"
		["atari2600"]="No"
		["atari5200"]="No"
		["atari7800"]="No"
		["atarilynx"]="No"		
		["c64"]="No"
		["fds"]="Yes"
		["gb"]="No"
		["gbc"]="No"
		["gba"]="No"
		["genesis"]="No"
		["gg"]="No"
		["megacd"]="Yes"
		["neogeo"]="No"
		["nes"]="No"
		["s32x"]="No"
		["sms"]="No"
		["snes"]="No"
		["tgfx16"]="No"
		["tgfx16cd"]="No"
		["psx"]="No"
	)

	# Core to input maps mapping
	declare -gA CORE_LAUNCH=(
		["amiga"]="Minimig"
		["arcade"]="Arcade"
		["atari2600"]="ATARI7800"
		["atari5200"]="ATARI5200"
		["atari7800"]="ATARI7800"
		["atarilynx"]="AtariLynx"
		["c64"]="C64"
		["fds"]="NES"
		["gb"]="GAMEBOY"
		["gbc"]="GAMEBOY"
		["gba"]="GBA"
		["genesis"]="Genesis"
		["gg"]="SMS"
		["megacd"]="MegaCD"
		["neogeo"]="NEOGEO"
		["nes"]="NES"
		["s32x"]="S32X"
		["sms"]="SMS"
		["snes"]="SNES"
		["tgfx16"]="TGFX16"
		["tgfx16cd"]="TGFX16"
		["psx"]="PSX"
	)

	# MGL core name settings
	declare -gA MGL_CORE=(
		["amiga"]="minimig"
		["arcade"]="Arcade"
		["atari2600"]="ATARI7800"
		["atari5200"]="ATARI5200"
		["atari7800"]="ATARI7800"
		["atarilynx"]="AtariLynx"		   
		["c64"]="C64"
		["fds"]="NES"
		["gb"]="GAMEBOY"
		["gbc"]="GAMEBOY"
		["gba"]="GBA"
		["genesis"]="Genesis"
		["gg"]="SMS"
		["megacd"]="MegaCD"
		["neogeo"]="NEOGEO"
		["nes"]="NES"
		["s32x"]="S32X"
		["sms"]="SMS"
		["snes"]="SNES"
		["tgfx16"]="TurboGrafx16"
		["tgfx16cd"]="TurboGrafx16"
		["psx"]="PSX"
	)

	# MGL delay settings
	declare -giA MGL_DELAY=(
		["amiga"]="1"
		["arcade"]="2"
		["atari2600"]="1"
		["atari5200"]="1"
		["atari7800"]="1"
		["atarilynx"]="1"
		["c64"]="1"
		["fds"]="2"
		["gb"]="2"
		["gbc"]="2"
		["gba"]="2"
		["genesis"]="1"
		["gg"]="1"
		["megacd"]="1"
		["neogeo"]="1"
		["nes"]="2"
		["s32x"]="1"
		["sms"]="1"
		["snes"]="2"
		["tgfx16"]="1"
		["tgfx16cd"]="1"
		["psx"]="1"
	)

	# MGL index settings
	declare -giA MGL_INDEX=(
		["amiga"]="0"
		["arcade"]="0"
		["atari2600"]="0"
		["atari5200"]="1"
		["atari7800"]="1"
		["atarilynx"]="1"   
		["c64"]="1"
		["fds"]="0"
		["gb"]="0"
		["gbc"]="0"
		["gba"]="0"
		["genesis"]="0"
		["gg"]="2"
		["megacd"]="0"
		["neogeo"]="1"
		["nes"]="0"
		["s32x"]="0"
		["sms"]="1"
		["snes"]="0"
		["tgfx16"]="0"
		["tgfx16cd"]="0"
		["psx"]="1"
	)

	# MGL type settings
	declare -glA MGL_TYPE=(
		["amiga"]="f"
		["arcade"]="f"
		["atari2600"]="f"
		["atari5200"]="f"
		["atari7800"]="f"
		["atarilynx"]="f"
		["c64"]="f"
		["fds"]="f"
		["gb"]="f"
		["gbc"]="f"
		["gba"]="f"
		["genesis"]="f"
		["gg"]="f"
		["megacd"]="s"
		["neogeo"]="f"
		["nes"]="f"
		["s32x"]="f"
		["sms"]="f"
		["snes"]="f"
		["tgfx16"]="f"
		["tgfx16cd"]="s"
		["psx"]="s"
	)
}

# Read INI
function read_samini() {

	samtimeout=60
	gametimer=2
	menuonly="Yes"
	corelist="arcade,amiga,atari2600,atari5200,atari7800,fds,genesis,megacd,neogeo,nes,s32x,sms,snes,tgfx16,tgfx16cd,psx"
	mute=no
	playcurrentgame="No" 
	roulettetimer="30"
	ttyenable="No"
	exclude=( readme )
	listenmouse="No"
	listenkeyboard="No"
	listenjoy="No"



	# The following option uses the default rom locations that MiSTer and all cores use by default
	# Setting this to "yes" is only recommended if you have trouble with the default method. 
	# It can cause significant delay on startup.
	usedefaultpaths="No"

	# -------- NeoGeo Full Titles -------
	# Options are English and JAPANESE
	# Not all games have an alternate Japanese Name, in that case, The English Title is used
	neogeoregion="English"
	useneogeotitles="No"

	# -------- TTY2OLED ADVCANCED SETTINGS -------
	# All needed values are read from the tty2oled INI files

	ttysystemini="/media/fat/tty2oled/tty2oled-system.ini"
	ttyuserini="/media/fat/tty2oled/tty2oled-user.ini"
	ttyuseack="Yes"

	# BGM settings
	# SAM support BGM ( https://github.com/wizzomafizzo/MiSTer_BGM ) but you have to set it up in the SAM menu first (Select "Background Music Player")
	bgm=No

	# SAM will play every game on your system once before starting from the beginning
	norepeat="Yes"

	# -------- DEBUG --------
	# These are intended for debugging SAM - use with care!

	# Can be used to find issues with rom detection in SAM. Set to No to ignore zip files in your directory
	usezip="Yes"

	# Show variables
	samtrace="No"

	# Should SAM be quiet - disable for extra logging - only useful via ssh
	samquiet="No"

	# GitHub branch to download updates from
	# Valid choices are: "main" or "test"
	branch="main"


	# Setup corelist
	corelist="$(echo ${corelist} | tr ',' ' ' | tr -s ' ')"
	corelistall="$(echo ${corelistall} | tr ',' ' ' | tr -s ' ')"

	# Create array of coreexclude list names
	declare -a coreexcludelist
	for core in ${corelistall}; do
		coreexcludelist+=("${core}exclude")
	done

	# Iterate through coreexclude lists and make list into array
	for excludelist in ${coreexcludelist[@]}; do
		readarray -t ${excludelist} <<<${!excludelist}
	done

	# Create folder and file exclusion list
	folderex=$(for f in "${exclude[@]}"; do echo "-o -iname *$f*"; done)
	fileex=$(for f in "${exclude[@]}"; do echo "-and -not -iname *$f*"; done)

	# Create file and folder exclusion list for zips. Always exclude BIOS files as a default
	zipex=$(printf "%s," "${exclude[@]}" && echo "bios")
}


function parse_cmd() {
	if [ ${#} -gt 2 ]; then # We don't accept more than 2 parameters
		sam_help
	elif [ ${#} -eq 0 ]; then # No options - show the pre-menu
		sam_premenu
	else
		# If we're given a core name then we need to set it first
		nextcore=""
		for arg in ${@,,}; do
			case ${arg} in
			arcade | atari2600 | atari5200 | atari7800 | atarilynx | amiga | c64 | fds | gb | gbc | gba | genesis | gg | megacd | neogeo | nes | s32x | sms | snes | tgfx16 | tgfx16cd | psx)
				echo " ${CORE_PRETTY[${arg}]} selected!"
				nextcore="${arg}"
				;;
			esac
		done

		# If the one command was a core then we need to call in again with "start" specified
		if [ ${nextcore} ] && [ ${#} -eq 1 ]; then
			# Move cursor up a line to avoid duplicate message
			echo -n -e "\033[A"
			# Re-enter this function with start added
			parse_cmd ${nextcore} start
			return
		fi

		while [ ${#} -gt 0 ]; do
			case "${1,,}" in
			default) # sam_update relaunches itself
				sam_update autoconfig
				break
				;;
			--speedtest | --sourceonly | --create-gamelists)
				break
				;;
			autoconfig | defaultb)
				tmux kill-session -t MCP &>/dev/null
				there_can_be_only_one
				sam_update
				mcp_start
				sam_enable
				break
				;;
			bootstart) # Start as from init
				env_check ${1}
				# Sleep before startup so clock of Mister can synchronize if connected to the internet.
				# We assume most people don't have RTC add-on so sleep is default.
				# Only start MCP on boot
				sleep ${bootsleep}
				mcp_start
				break
				;;
			start) # Start SAM immediately
				#env_check ${1}
				#tty_init
				#bgm_start
				loop_core ${nextcore}
				break
				;;
			skip | next) # Load next game - stops monitor
				echo " Skipping to next game..."
				tmux send-keys -t SAM C-c ENTER
				# break
				;;
			stop) # Stop SAM immediately
				sam_cleanup
				sam_stop
				exit
				break
				;;
			update) # Update SAM
				sam_cleanup
				sam_update
				break
				;;
			enable) # Enable SAM autoplay mode
				env_check ${1}
				sam_enable
				break
				;;
			disable) # Disable SAM autoplay
				sam_cleanup
				sam_disable
				break
				;;
			monitor) # Warn user of changes
				sam_monitor
				break
				;;
			startmonitor)
				sam_start
				sam_monitor
				break
				;;
			amiga | arcade | atari2600 | atari5200 | atari7800 | atarilynx | c64 | fds | gb | gbc | gba | genesis | gg | megacd | neogeo | nes | s32x | sms | snes | tgfx16 | tgfx16cd | psx)
				: # Placeholder since we parsed these above
				;;
			single)
				sam_singlemenu
				break
				;;
			utility)
				sam_utilitymenu
				break
				;;
			autoplay)
				sam_autoplaymenu
				break
				;;
			favorite)
				mglfavorite
				break
				;;
			reset)
				sam_resetmenu
				break
				;;
			config)
				sam_configmenu
				break
				;;
			back)
				sam_menu
				break
				;;
			menu)
				sam_menu
				break
				;;
			cancel) # Exit
				echo " It's pitch dark; You are likely to be eaten by a Grue."
				inmenu=0
				break
				;;
			deleteall)
				deleteall
				break
				;;
			exclude)
				samedit_excltags
				break
				;;
			include)
				samedit_include
				break
				;;
			gamemode)
				sam_gamemodemenu
				break
				;;
			bgm)
				sam_bgmmenu
				break
				;;
			gamelists)
				sam_gamelistmenu
				break
				;;
			creategl)
				creategl
				break
				;;
			deletegl)
				deletegl
				break
				;;
			help)
				sam_help
				break
				;;
			*)
				echo " ERROR! ${1} is unknown."
				echo " Try $(basename -- ${0}) help"
				echo " Or check the Github readme."
				break
				;;
			esac
			shift
		done
	fi
}

function skipmessage() {
	# Skip past bios/safety warnings

	"${mrsampath}/mbc" raw_seq :31
}

# ======== SAM OPERATIONAL FUNCTIONS ========
function loop_core() { # loop_core (core)
	echo -e " Starting Super Attract Mode...\n Let Mortal Kombat begin!\n"
	# Reset game log for this session
	echo "" | >/tmp/SAM_Games.log

	while :; do

		while [ ${counter} -gt 0 ]; do
			trap 'kill -9 $sampid' INT #Break out of loop for skip & next command
			echo -ne " Next game in ${counter}...\033[0K\r"
			sleep 1
			((counter--))

			if [ -s /tmp/.SAM_Mouse_Activity ]; then
				if [ "${listenmouse}" == "yes" ]; then
					echo " Mouse activity detected!"
					sam_cleanup
					play_or_exit
				else
					echo " Mouse activity ignored!"
					echo "" | >/tmp/.SAM_Mouse_Activity
				fi
			fi

			if [ -s /tmp/.SAM_Keyboard_Activity ]; then
				if [ "${listenkeyboard}" == "yes" ]; then
					echo " Keyboard activity detected!"
					sam_cleanup
					play_or_exit

				else
					echo " Keyboard activity ignored!"
					echo "" | >/tmp/.SAM_Keyboard_Activity
				fi
			fi

			if [ -s /tmp/.SAM_Joy_Activity ]; then
				if [ "${listenjoy}" == "yes" ]; then
					echo " Controller activity detected!"
					sam_cleanup
					play_or_exit
				else
					echo " Controller activity ignored!"
					echo "" | >/tmp/.SAM_Joy_Activity
				fi
			fi

		done

		counter=${gametimer}
		next_core ${1}

	done
	trap - INT
	sleep 1
}

function reset_core_gl() { # args ${nextcore}
	echo " Deleting old game lists for ${1^^}..."
	rm "${gamelistpath}/${1}_gamelist_hdmi.txt" &>/dev/null
	sync
}



# ======== ROMFINDER ========
function create_romlist() { # args ${nextcore} "${DIR}"
	if [ ${speedtest} -eq 1 ] || [ "${samquiet}" == "no" ]; then
		echo " Looking for games in  ${2}..."
	else
		echo -n " Looking for games in  ${2}..."
	fi
	# Find all files in core's folder with core's extension
	extlist=$(echo ${CORE_EXT[${1}]} | sed -e "s/,/ -o -iname *.$f/g")
	find -L "${2}" \( -type l -o -type d \) \( -iname *BIOS* ${folderex} \) -prune -false -o -not -path '*/.*' -type f \( -iname "*."${extlist} -not -iname *BIOS* ${fileex} \) -fprint >(cat >>"${tmpfile}")
	# Now find all zips in core's folder and process
	if [ "${CORE_ZIPPED[${1}]}" == "yes" ]; then
		find -L "${2}" \( -type l -o -type d \) \( -iname *BIOS* ${folderex} \) -prune -false -o -not -path '*/.*' -type f \( -iname "*.zip" -not -iname *BIOS* ${fileex} \) -fprint "${tmpfile2}"
		if [ -s "${tmpfile2}" ]; then
			cat "${tmpfile2}" | while read z; do
				if [ ${speedtest} -eq 1 ] || [ "${samquiet}" == "no" ]; then
					echo " Processing: ${z}"
				fi
				"${mrsampath}/partun" "${z}" -l -e ${zipex} --include-archive-name --ext "${CORE_EXT[${1}]}" >>"${tmpfile}"
			done
		fi
	fi

	cat "${tmpfile}" | sort >"${gamelistpath}/${1}_gamelist_hdmi.txt"

	# Strip out all duplicate filenames with a fancy awk command
	awk -F'/' '!seen[$NF]++' "${gamelistpath}/${1}_gamelist_hdmi.txt" > $tmpfile && mv -f $tmpfile "${gamelistpath}/${1}_gamelist_hdmi.txt"
	# cp "${gamelistpath}/${1}_gamelist_hdmi.txt" "${gamelistpathtmp}/${1}_gamelist_hdmi.txt"
	rm ${tmpfile} &>/dev/null
	rm ${tmpfile2} &>/dev/null

	total_games=$(echo $(cat "${gamelistpath}/${1}_gamelist_hdmi.txt" | sed '/^\s*$/d' | wc -l))
	if [ ${speedtest} -eq 1 ]; then
		echo -n "${1}: ${total_games} Games found" >>"${gamelistpathtmp}/Durations.tmp"
	fi
	if [ ${speedtest} -eq 1 ] || [ "${samquiet}" == "no" ]; then
		echo "${total_games} Games found."
	else
		echo " ${total_games} Games found."
	fi
}

function check_list() { # args ${nextcore}  "${DIR}"
	# If gamelist is not in /tmp dir, let's put it there
	if [ ! -f "${gamelistpath}/${1}_gamelist_hdmi.txt" ]; then
		if [ "${samquiet}" == "no" ]; then echo " Creating game list at ${gamelistpath}/${1}_gamelist_hdmi.txt"; fi
		create_romlist ${1} "${2}"
	fi

	# If folder changed, make new list
	if [[ ! "$(cat ${gamelistpath}/${1}_gamelist_hdmi.txt | grep "${2}" | head -1)" ]]; then
		if [ "${samquiet}" == "no" ]; then echo " Creating new game list because folder "${DIR}" changed in ini."; fi
		create_romlist ${1} "${2}"
	fi

	# Check if zip still exists
	if [ "$(grep -c ".zip" ${gamelistpath}/${1}_gamelist_hdmi.txt)" != "0" ]; then
		mapfile -t zipsinfile < <(grep ".zip" "${gamelistpath}/${1}_gamelist_hdmi.txt" | awk -F".zip" '!seen[$1]++' | awk -F".zip" '{print $1}' | sed -e 's/$/.zip/')
		for zips in "${zipsinfile[@]}"; do
			if [ ! -f "${zips}" ]; then
				if [ "${samquiet}" == "no" ]; then echo " Creating new game list because zip file[s] seems to have changed."; fi
				create_romlist ${1} "${2}"
			fi
		done
	fi

	# If gamelist is not in /tmp dir, let's put it there
	if [ -f "${gamelistpathtmp}/${1}_gamelist_hdmi.txt" ]; then

		# Pick the actual game
		rompath="$(cat ${gamelistpathtmp}/${1}_gamelist_hdmi.txt | head -n1)"
	else

		# Repopulate list
		if [ -f "${gamelistpath}/${1}_gamelist_exclude.txt" ]; then
			if [ "${samquiet}" == "no" ]; then echo -n " Exclusion list found. Excluding games now..."; fi
			comm -13 <(sort <"${gamelistpath}/${1}_gamelist_exclude.txt") <(sort <"${gamelistpath}/${1}_gamelist_hdmi.txt") >${tmpfile}
			awk -F'/' '!seen[$NF]++' ${tmpfile} >"${gamelistpathtmp}/${1}_gamelist_hdmi.txt"
			if [ "${samquiet}" == "no" ]; then echo "Done."; fi
			rompath="$(cat ${gamelistpathtmp}/${1}_gamelist_hdmi.txt | shuf --head-count=1)"
		else
			awk -F'/' '!seen[$NF]++' "${gamelistpath}/${1}_gamelist_hdmi.txt" >"${gamelistpathtmp}/${1}_gamelist_hdmi.txt"
			# cp "${gamelistpath}/${1}_gamelist_hdmi.txt" "${gamelistpathtmp}/${1}_gamelist_hdmi.txt" &>/dev/null
			rompath="$(cat ${gamelistpathtmp}/${1}_gamelist_hdmi.txt | shuf --head-count=1)"
		fi
	fi
	
	if [ ! -s "${gamelistpathtmp}/${1}_gamelist_hdmi.txt" ]; then
		kill -9 $sampid
	fi

	# Make sure file exists since we're reading from a static list
	if [[ ! "${rompath,,}" == *.zip* ]]; then
		if [ ! -f "${rompath}" ]; then
			if [ "${samquiet}" == "no" ]; then echo " Creating new game list because file not found."; fi
			create_romlist ${1} "${2}"
		fi
	fi

}

function compare_mp4-gl() {
	nextcore=${1}
	ssh chelm@192.168.1.64 'dir /b "c:\SAM\'${nextcore}'\*.mp4"' /s | rev | cut -c6- | rev | awk -F'\\' '{print $NF}' |sort > "${gamelistpathtmp}/${nextcore}_gamelist_mp4.txt"
	fgrep -vf "${gamelistpathtmp}/${nextcore}_gamelist_mp4.txt" "${gamelistpath}/${nextcore}_gamelist_hdmi.txt" > "${gamelistpathtmp}/${nextcore}_gamelist_hdmi.txt"
	if [ "$(cat "${gamelistpathtmp}/${nextcore}_gamelist_hdmi.txt" |wc -l)" == "0" ]; then
		echo " No new games found"
		exit
	else
		echo " $(cat "${gamelistpathtmp}/${nextcore}_gamelist_hdmi.txt" |wc -l) Games left to capture"
	fi
}
	

function next_core() { # next_core (core)
	if [ -z "$(echo ${corelist} | sed 's/ //g')" ]; then
		if [ -s "${corelisttmpfile}" ]; then
			corelist="$(cat ${corelisttmpfile})"
		else
			echo " ERROR: FATAL - List of cores is empty. Nothing to do!"
			exit 1
		fi
	elif [ ! -s "${corelisttmpfile}" ]; then
		echo "${corelist}" >"${corelisttmpfile}"
	fi
	if [ "${1,,}" == "countdown" ] && [ "$2" ]; then
		countdown="countdown"
		nextcore="${2}"
	elif [ "${2,,}" == "countdown" ]; then
		nextcore="${1}"
		countdown="countdown"
	fi
	# If nextcore is passed as an argument e.g "MiSTer_SAM_on.sh snes", don't select core from corelist
	if [ -z "${1}" ]; then
		if [ "${countdown}" != "countdown" ]; then
			# Set $nextcore from $corelist
			nextcore="$(echo ${corelist} | xargs shuf --head-count=1 --echo)"
			if [ "${1}" == "${nextcore}" ]; then
				next_core ${nextcore}
				return
			else
				# Limit corelist to only show games from one core
				corelist=$(echo ${corelist} | awk '{print $0" "}' | sed "s/${nextcore} //" | tr -s ' ')
			fi
		fi
	fi
	if [ "${samquiet}" == "no" ]; then echo -e " Selected core: \e[1m${nextcore^^}\e[0m"; fi
	if [ "${nextcore}" == "arcade" ]; then
		# If this is an arcade core we go to special code
		load_core_arcade
		return
	fi
	if [ "${nextcore}" == "amiga" ]; then
		# If this is Amiga core we go to special code
		if [ -f "${amigapath}/MegaAGS.hdf" ]; then
			load_core_amiga
		else
			echo " ERROR - MegaAGS Pack not found in Amiga folder. Skipping to next core..."
			declare -g corelist=("${corelist[@]/${1}/}")
			next_core
		fi
		return
	fi

	local DIR=$(echo $(realpath -s --canonicalize-missing "${CORE_PATH[${nextcore}]}${CORE_PATH_EXTRA[${nextcore}]}"))
		
	rompath="$(cat ${gamelistpathtmp}/${1}_gamelist_hdmi.txt | head -n1)"
	romname=$(basename "${rompath}")

	# Sanity check that we have a valid rom in var
	extension="${rompath##*.}"
	extlist=$(echo "${CORE_EXT[${nextcore}]}" | sed -e "s/,/ /g")
				
	if [[ ! "$(echo "${extlist}" | grep -i "${extension}")" ]]; then
		if [ "${samquiet}" == "no" ]; then echo -e " Wrong extension found: \e[1m${extension^^}\e[0m"; fi
		if [ "${samquiet}" == "no" ]; then echo -e " Regenerating Game List"; fi

		create_romlist ${nextcore} "${DIR}"
		next_core ${nextcore}
		return
	fi
	
	if [[ "$(cat "${gamelistpathtmp}/${nextcore}_gamelist_hdmi.txt" |wc -l)" == "0" ]]; then
		if [[ "$yesno" == y ]]; then
			ssh chelm@192.168.1.64 'wsl sh -c "/mnt/c/SAM/blacklist_maker.sh '${nextcore}'"'
		fi
		exit
	fi
	

	# If there is an exclude list check it
	declare -n excludelist="${nextcore}exclude"
	if [ ${#excludelist[@]} -gt 0 ]; then
		for excluded in "${excludelist[@]}"; do
			if [ "${romname}" == "${excluded}" ]; then
				echo " {romname} empty."
				exit
			fi
		done
	fi

	if [ -f "${excludepath}/${nextcore}_excludelist.txt" ]; then
		cat "${excludepath}/${nextcore}_excludelist.txt" | while IFS=$'\n' read line; do
			echo " Found exclusion list for core $nextcore"
			awk -vLine="$line" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} && mv ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
		done
	fi

	if [ -z "${rompath}" ]; then
		core_error "${nextcore}" "${rompath}"
	else
		if [ -f "${rompath}.sam" ]; then
			source "${rompath}.sam"
		fi

		declare -g romloadfails=0
		load_core "${nextcore}" "${rompath}" "${romname%.*}" "${countdown}"
	fi
}

function load_core() { # load_core core /path/to/rom name_of_rom (countdown)

	GAMENAME=""
	if [ ${1} == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then
		if [ ${neogeoregion} == "english" ]; then
			GAMENAME="${NEOGEO_PRETTY_ENGLISH[${3}]}"
		elif [ ${neogeoregion} == "japanese" ]; then
			GAMENAME="${NEOGEO_PRETTY_JAPANESE[${3}]}"
			[[ ! "${GAMENAME}" ]] && GAMENAME="${NEOGEO_PRETTY_ENGLISH[${3}]}"
		fi
	fi
	if [ ! "${GAMENAME}" ]; then
		GAMENAME="${3}"
	fi

	echo -n " Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${1}]}\e[0m: "
	echo -e "\e[1m${GAMENAME}\e[0m"
	#echo "$(date +%H:%M:%S) - ${1} - ${3}" $(if [ ${1} == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then echo "(${GAMENAME})"; fi) >>/tmp/SAM_Games.log
	#echo "${3} (${1}) "$(if [ ${1} == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then echo "(${GAMENAME})"; fi) >/tmp/SAM_Game.txt

	if [ "${4}" == "countdown" ]; then
		for i in {5..1}; do
			echo -ne " Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi

	# Create mgl file and launch game
	#if [ -s /tmp/SAM_game.mgl ]; then
	#	mv /tmp/SAM_game.mgl /tmp/SAM_game.previous.mgl
	#fi

	#mute "${CORE_LAUNCH[${nextcore}]}"

	echo "<mistergamedescription>" >/tmp/SAM_game.mgl
	echo "<rbf>${CORE_PATH_RBF[${nextcore}]}/${MGL_CORE[${nextcore}]}</rbf>" >>/tmp/SAM_game.mgl

	if [ ${usedefaultpaths} == "yes" ]; then
		corepath="${CORE_PATH[${nextcore}]}/"
		rompath="${rompath#${corepath}}"
		echo "<file delay="${MGL_DELAY[${nextcore}]}" type="${MGL_TYPE[${nextcore}]}" index="${MGL_INDEX[${nextcore}]}" path="\"${rompath}\""/>" >>/tmp/SAM_game.mgl
	else
		echo "<file delay="${MGL_DELAY[${nextcore}]}" type="${MGL_TYPE[${nextcore}]}" index="${MGL_INDEX[${nextcore}]}" path="\"../../../..${rompath}\""/>" >>/tmp/SAM_game.mgl
	fi

	echo "</mistergamedescription>" >>/tmp/SAM_game.mgl

	echo "load_core /tmp/SAM_game.mgl" >/dev/MiSTer_cmd
	if [ "${skipmessage}" == "yes" ] && [ "${CORE_SKIP[${nextcore}]}" == "yes" ]; then
		sleep 5
		skipmessage
	fi
	sleep 30
	
	ssh chelm@192.168.1.64 'mkdir "c:\SAM\'${nextcore}'"'
	ssh chelm@192.168.1.64 'c:\code\ffmpeg\ffmpeg -r 5 -t 90 -f dshow -rtbufsize 100M -video_size 640x480 -framerate 5 -i video="USB Video" -vcodec libx265 -crf 28 -y -fps_mode auto "c:\SAM\'${nextcore}'\'${GAMENAME}'".mp4'

	echo "" | >/tmp/.SAM_Joy_Activity
	echo "" | >/tmp/.SAM_Mouse_Activity
	echo "" | >/tmp/.SAM_Keyboard_Activity
	
	# Delete played game from list
	if [ "${samquiet}" == "no" ]; then echo " Selected file: ${rompath}"; fi
	if [ "${norepeat}" == "yes" ]; then
		awk -vLine="$rompath" '!index($0,Line)' "${gamelistpathtmp}/${1}_gamelist_hdmi.txt" >${tmpfile} && mv ${tmpfile} "${gamelistpathtmp}/${1}_gamelist_hdmi.txt"
	fi



}

function core_error() { # core_error core /path/to/ROM
	if [ ${romloadfails} -lt ${coreretries} ]; then
		declare -g romloadfails=$((romloadfails + 1))
		echo " ERROR: Failed ${romloadfails} times. No valid game found for core: ${1} rom: ${2}"
		echo " Trying to find another rom..."
		next_core ${1}
	else
		echo " ERROR: Failed ${romloadfails} times. No valid game found for core: ${1} rom: ${2}"
		echo " ERROR: Core ${1} is blacklisted!"
		declare -g corelist=("${corelist[@]/${1}/}")
		echo " List of cores is now: ${corelist[@]}"
		declare -g romloadfails=0
		# Load a different core
		next_core
	fi
}



# ======== ARCADE MODE ========
function build_mralist() {
	if [ ${speedtest} -eq 1 ] || [ "${samquiet}" == "no" ]; then
		echo " Looking for games in  ${1}..."
	else
		echo -n " Looking for games in  ${1}..."
	fi
	# If no MRAs found - suicide!
	find "${1}" -type f \( -iname "*.mra" \) &>/dev/null
	if [ ! ${?} == 0 ]; then
		echo " The path '${1}' contains no MRA files!"
		loop_core
	fi

	# This prints the list of MRA files in a path,
	# Cuts the string to just the file name,
	# Then saves it to the mralist file.

	# If there is an empty exclude list ignore it
	# Otherwise use it to filter the list
	if [ ${#arcadeexclude[@]} -eq 0 ]; then
		find "${1}" -not -path '*/.*' -type f \( -iname "*.mra" \) | cut -c $(($(echo ${#1}) + 2))- >"${mralist}"
	else
		find "${1}" -not -path '*/.*' -type f \( -iname "*.mra" \) | cut -c $(($(echo ${#1}) + 2))- | grep -vFf <(printf '%s\n' ${arcadeexclude[@]}) >"${mralist}"
	fi
	if [ ! -s "${mralist_tmp}" ]; then
		cp "${mralist}" "${mralist_tmp}" &>/dev/null
	fi
	total_games=$(cat "${mralist}" | sed '/^\s*$/d' | wc -l)
	if [ ${speedtest} -eq 1 ]; then
		echo -n "Arcade: ${total_games} Games found" >>"${gamelistpathtmp}/Durations.tmp"
	fi
	if [ ${speedtest} -eq 1 ] || [ "${samquiet}" == "no" ]; then
		echo "${total_games} Games found."
	else
		echo " ${total_games} Games found."
	fi
}

function load_core_arcade() {

	DIR=$(echo $(realpath -s --canonicalize-missing "${CORE_PATH[${nextcore}]}${CORE_PATH_EXTRA[${nextcore}]}"))
	
	# Check if the MRA list is empty or doesn't exist - if so, make a new list

	if [ ! -s "${mralist}" ]; then
		build_mralist "${arcadepath}"
		[ -f "${mralist_tmp}" ] && rm "${mralist_tmp}"
	fi

	if [ ! -f "${mralist_tmp}" ]; then
		cp "${mralist}" "${mralist_tmp}" &>/dev/null
	fi
	
	if [ ! -s "${mralist_tmp}" ]; then
		kill -9 $sampid
	fi
	

	# Get a random game from the list
	mra="$(head -n1 ${mralist_tmp})"
	MRAPATH="$(echo $(realpath -s --canonicalize-missing "${DIR}/${mra}"))"
	

	if [ "${samquiet}" == "no" ]; then echo " Selected file: ${MRAPATH}"; fi

	# Delete mra from list so it doesn't repeat
	if [ "${norepeat}" == "yes" ]; then
		awk -vLine="$mra" '!index($0,Line)' "${mralist_tmp}" >${tmpfile} && mv ${tmpfile} "${mralist_tmp}"

	fi

	mraname=$(echo $(basename "${mra}") | sed -e 's/\.[^.]*$//')
	echo -n " Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore}]}\e[0m: "
	echo -e "\e[1m${mraname}\e[0m"

	if [ "${1}" == "countdown" ]; then
		for i in {5..1}; do
			echo " Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi
	if [[ "$(cat "${gamelistpathtmp}/${nextcore}_gamelist.txt" |wc -l)" == "0" ]]; then
			if [[ "$yesno" == y ]]; then
				ssh chelm@192.168.1.64 'wsl sh -c "/mnt/c/SAM/blacklist_maker.sh '${nextcore}'"'
			fi
	fi

	# Tell MiSTer to load the next MRA
	echo "load_core ${MRAPATH}" >/dev/MiSTer_cmd
	sleep 10
	ssh chelm@192.168.1.64 'c:\code\ffmpeg\ffmpeg -r 5 -t 90 -f dshow -rtbufsize 100M -video_size 640x480 -framerate 5 -i video="USB Video" -vcodec libx265 -crf 28 -y -fps_mode auto "c:\SAM\arcade\'${mraname}'".mp4'
	echo "" | >/tmp/.SAM_Joy_Activity
	echo "" | >/tmp/.SAM_Mouse_Activity
	echo "" | >/tmp/.SAM_Keyboard_Activity
}

function create_amigalist () {

	if [ -f "${amigapath}/listings/games.txt" ]; then
		[ -f "${amigapath}/listings/games.txt" ] && cat "${amigapath}/listings/demos.txt" > ${gamelistpath}/${nextcore}_gamelist.txt
		sed -i -e 's/^/Demo: /' ${gamelistpath}/${nextcore}_gamelist.txt
		[ -f "${amigapath}/listings/demos.txt" ] && cat "${amigapath}/listings/games.txt" >> ${gamelistpath}/${nextcore}_gamelist.txt
		
		total_games=$(echo $(cat "${gamelistpath}/${nextcore}_gamelist.txt" | sed '/^\s*$/d' | wc -l))

		if [ ${speedtest} -eq 1 ] || [ "${samquiet}" == "no" ]; then
			echo "${total_games} Games and Demos found."
		else
			echo " ${total_games} Games and Demos found."
		fi
	fi

}


function load_core_amiga() {

	amigacore="$(find /media/fat/_Computer/ -iname "*minimig*")"
	
	mute "${CORE_LAUNCH[${nextcore}]}"

	if [ ! -f "${amigapath}/listings/games.txt" ]; then
		# This is for MegaAGS version June 2022 or older
		echo -n " Starting now on the "
		echo -ne "\e[4m${CORE_PRETTY[${nextcore}]}\e[0m: "
		echo -e "\e[1mMegaAGS Amiga Game\e[0m"


		#tty_update "${CORE_PRETTY[${nextcore}]}" & # Non-Blocking

		if [ "${nextcore}" == "countdown" ]; then
			for i in {5..1}; do
				echo " Loading game in ${i}...\033[0K\r"
				sleep 1
			done
		fi

		# Tell MiSTer to load the next MRA

		echo "load_core ${amigacore}" >/dev/MiSTer_cmd
		sleep 13
		"${mrsampath}/mbc" raw_seq {6c
		"${mrsampath}/mbc" raw_seq O
		echo "" | >/tmp/.SAM_Joy_Activity
		echo "" | >/tmp/.SAM_Mouse_Activity
		echo "" | >/tmp/.SAM_Keyboard_Activity
	else
		# This is for MegaAGS version July 2022 or newer
		[ ! -f ${gamelistpath}/${nextcore}_gamelist.txt ] && create_amigalist
		
		if [ ! -s "${gamelistpathtmp}/${nextcore}_gamelist.txt" ]; then
			cp ${gamelistpath}/${nextcore}_gamelist.txt "${gamelistpathtmp}/${nextcore}_gamelist.txt" &>/dev/null
		fi

		rompath="$(shuf --head-count=1 ${gamelistpathtmp}/${nextcore}_gamelist.txt)"
		agpretty="$(echo "${rompath}" | tr '_' ' ')"
		
		# Special case for demo
		if [[ "${rompath}" == *"Demo:"* ]]; then
			rompath=${rompath//Demo: /}
		fi

		# Delete played game from list
		if [ "${samquiet}" == "no" ]; then echo " Selected file: ${rompath}"; fi
		if [ "${norepeat}" == "yes" ]; then
			awk -vLine="$rompath" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} && mv ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
		fi
		
		if [[ "$(cat "${gamelistpathtmp}/${nextcore}_gamelist.txt" |wc -l)" == "0" ]]; then
			echo "Create blacklist? y/n"
			read yesno
			if [[ "$yesno" == y ]]; then
				ssh chelm@192.168.1.64 'wsl sh -c "/mnt/c/SAM/blacklist_maker.sh '${nextcore}'"'
			fi
		fi


		echo "${rompath}" > "${amigapath}"/shared/ags_boot

		echo -n " Starting now on the "
		echo -ne "\e[4m${CORE_PRETTY[${nextcore}]}\e[0m: "
		echo -e "\e[1m${agpretty}\e[0m"
		echo "$(date +%H:%M:%S) - ${nextcore} - ${rompath}" >>/tmp/SAM_Games.log
		echo "${rompath} (${nextcore})" >/tmp/SAM_Game.txt
		tty_update "${CORE_PRETTY[${nextcore}]}" "${agpretty}" "${CORE_LAUNCH[${nextcore}]}" & # Non blocking Version

		echo "load_core ${amigacore}" >/dev/MiSTer_cmd

	fi
}



# ========= MAIN =========
function main() {

	init_vars

	read_samini

	init_paths

	init_data # Setup data arrays
	
	echo "Create new romlist? y/n"
	read answer
	echo "Update existing list? y/n"
	read answer
	echo "Create blacklist? y/n"
	read yesno

	if [[ "$answer" == y ]]; then
		create_romlist ${1} ${CORE_PATH[${1}]}
	fi
	

	if [[ "$answer" == y ]]; then
		compare_mp4-gl ${1}
	fi
	
	parse_cmd ${@} # Parse command line parameters for input

}

if [ "${1,,}" != "--source-only" ]; then
	main ${@}
fi

