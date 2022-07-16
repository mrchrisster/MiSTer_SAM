#!/bin/bash

# https://github.com/mrchrisster/SuperAttract/
# Copyright (c) 2021 by mrchrisster and Mellified

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# Description
# This cycles through arcade and console cores periodically
# Games are randomly pulled from their respective folders

# ======== Credits ========
# Original concept and implementation: mrchrisster
# Additional development and script layout: Mellified and Paradox
#
# Thanks for the contributions and support:
# pocomane, kaloun34, redsteakraw, RetroDriven, woelper, LamerDeluxe, InquisitiveCoder, Sigismond, venice, Paradox

trap 'rc=$?;[ $rc = 0 ] && exit;SAM_cleanup' EXIT

# ======== GLOBAL VARIABLES =========
declare -g mrsampath="/media/fat/Scripts/.SuperAttract"
declare -g misterpath="/media/fat"
declare -g repository_url="https://github.com/mrchrisster/MiSTer_SAM"
declare -g branch="main"
declare -g userstartup="/media/fat/linux/user-startup.sh"
declare -g userstartuptpl="/media/fat/linux/_user-startup.sh"
# Save our PID and process
declare -g sampid="${$}"
declare -g samprocess="$(basename -- ${0})"

# Named Pipes
declare -g SAM_cmd_pipe="/tmp/.SAM_tmp/SAM_cmd_pipe"
declare -g MCP_cmd_pipe="/tmp/.SAM_tmp/MCP_cmd_pipe"
declare -g activity_pipe2="/tmp/.SAM_tmp/SAM_Activity2"
declare -g TTY_cmd_pipe="/tmp/.SAM_tmp/TTY_cmd_pipe"

# ======== INI VARIABLES ========
# Change these in the INI file
function init_vars() {
	# ======== DEBUG VARIABLES ========
	declare -gl samquiet="Yes"
	declare -gl samdebug="No"
	declare -gl samtrace="No"
	declare -gi speedtest=0

	# ======== LOCAL VARIABLES ========
	declare -gi inmenu=0
	declare -gi coreretries=3
	declare -gi romloadfails=0
	declare -g gamelistpath="${mrsampath}/SAM_Gamelists"
	declare -g gamelistpathtmp="/tmp/.SAM_List/"
	declare -g excludepath="${mrsampath}"
	declare -g mralist_old="${mrsampath}/SAM_Gamelists/arcade_romlist"
	declare -g mralist="${mrsampath}/SAM_Gamelists/arcade_gamelist.txt"
	declare -g mralist_tmp_old="/tmp/.SAM_List/arcade_romlist"
	declare -g mralist_tmp="/tmp/.SAM_List/arcade_gamelist.txt"
	declare -g tmpfile="/tmp/.SAM_List/tmpfile"
	declare -g tmpfile2="/tmp/.SAM_List/tmpfile2"
	declare -g corelisttmpfile="/tmp/.SAM_List/corelist.tmp"
	declare -gi gametimer=120
	declare -gl corelist="arcade,atari2600,atari5200,atari7800,atarilynx,c64,fds,gb,gbc,gba,genesis,gg,megacd,neogeo,nes,s32x,sms,snes,tgfx16,tgfx16cd,psx"
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
	declare -gi counter=0
	declare -gl usedefaultpaths="Yes"
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

	# ======== TTY2OLED =======
	declare -gl ttyenable="No"
	declare -gl ttyuseack="No"
	declare -gA tty_currentinfo=(
		["core_pretty"]=""
		["name"]=""
		["name_scroll"]=""
		["core"]=""
		["counter"]=${gametimer}
	)

	# ======== CORE PATHS ========
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

function config_bind() {
	[ ! -d "/tmp/.SAM_tmp/SAM_config" ] && mkdir -p "/tmp/.SAM_tmp/SAM_config"
	[ -d "/tmp/.SAM_tmp/SAM_config" ] && cp -pr --force /media/fat/config/* /tmp/.SAM_tmp/SAM_config &>/dev/null
	[ -d "/tmp/.SAM_tmp/SAM_config" ] && [ "$(mount | grep -ic '/media/fat/config')" == "0" ] && mount --bind "/tmp/.SAM_tmp/SAM_config" "/media/fat/config"
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
		["arcade"]="mra"
		["atari2600"]="a26"     # Should we include? "bin"
		["atari5200"]="a52,car" # Should we include? "bin,rom"
		["atari7800"]="a78"     # Should we include? "bin"
		["atarilynx"]="lnx"
		["c64"]="crt,prg" # need to be tested "reu,tap,flt,rom,c1581"
		["fds"]="fds"
		["gb"]="gb"   # Should we include? "bin"
		["gbc"]="gbc" # Should we include? "bin"
		["gba"]="gba"
		["genesis"]="md,gen" # Should we include? "bin"
		["gg"]="gg"
		["megacd"]="chd,cue"
		["neogeo"]="neo"
		["nes"]="nes"
		["s32x"]="32x"
		["sms"]="sms,sg"
		["snes"]="sfc,smc"   # Should we include? "bin,bs"
		["tgfx16"]="pce,sgx" # Should we include? "bin"
		["tgfx16cd"]="chd,cue"
		["psx"]="chd,cue,exe"
	)

	# Core to path mappings
	declare -gA CORE_PATH=(
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
		["tgfx16cd"]="Yes"
		["psx"]="No"
	)

	# Core to input maps mapping
	declare -gA CORE_LAUNCH=(
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

	# NEOGEO to long name mappings English
	declare -gA NEOGEO_PRETTY_ENGLISH=(
		["3countb"]="3 Count Bout"
		["2020bb"]="2020 Super Baseball"
		["2020bba"]="2020 Super Baseball (set 2)"
		["2020bbh"]="2020 Super Baseball (set 3)"
		["abyssal"]="Abyssal Infants"
		["alpham2"]="Alpha Mission II"
		["alpham2p"]="Alpha Mission II (prototype)"
		["androdun"]="Andro Dunos"
		["aodk"]="Aggressors of Dark Kombat"
		["aof"]="Art of Fighting"
		["aof2"]="Art of Fighting 2"
		["aof2a"]="Art of Fighting 2 (NGH-056)"
		["aof3"]="Art of Fighting 3: The Path of the Warrior"
		["aof3k"]="Art of Fighting 3: The Path of the Warrior (Korean release)"
		["b2b"]="Bang Bang Busters"
		["badapple"]="Bad Apple Demo"
		["bakatono"]="Bakatonosama Mahjong Manyuuki"
		["bangbead"]="Bang Bead"
		["bjourney"]="Blue's Journey"
		["blazstar"]="Blazing Star"
		["breakers"]="Breakers"
		["breakrev"]="Breakers Revenge"
		["brningfh"]="Burning Fight (NGH-018, US)"
		["brningfp"]="Burning Fight (prototype, older)"
		["brnngfpa"]="Burning Fight (prototype, near final, ver 23.3, 910326)"
		["bstars"]="Baseball Stars Professional"
		["bstars2"]="Baseball Stars 2"
		["bstarsh"]="Baseball Stars Professional (NGH-002)"
		["burningf"]="Burning Fight"
		["burningfh"]="Burning Fight (NGH-018, US)"
		["burningfp"]="Burning Fight (prototype, older)"
		["burningfpa"]="Burning Fight (prototype, near final, ver 23.3, 910326)"
		["cabalng"]="Cabal"
		["columnsn"]="Columns"
		["cphd"]="Crouching Pony Hidden Dragon Demo"
		["crswd2bl"]="Crossed Swords 2 (CD conversion)"
		["crsword"]="Crossed Swords"
		["ct2k3sa"]="Crouching Tiger Hidden Dragon 2003 Super Plus (The King of Fighters 2001 bootleg)"
		["ctomaday"]="Captain Tomaday"
		["cyberlip"]="Cyber-Lip"
		["diggerma"]="Digger Man"
		["doubledr"]="Double Dragon"
		["eightman"]="Eight Man"
		["fatfursp"]="Fatal Fury Special"
		["fatfurspa"]="Fatal Fury Special (NGM-058 ~ NGH-058, set 2)"
		["fatfury1"]="Fatal Fury: King of Fighters"
		["fatfury2"]="Fatal Fury 2"
		["fatfury3"]="Fatal Fury 3: Road to the Final Victory"
		["fbfrenzy"]="Football Frenzy"
		["fghtfeva"]="Fight Fever (set 2)"
		["fightfev"]="Fight Fever"
		["fightfeva"]="Fight Fever (set 2)"
		["flipshot"]="Battle Flip Shot"
		["frogfest"]="Frog Feast"
		["froman2b"]="Idol Mahjong Final Romance 2 (CD conversion)"
		["fswords"]="Fighters Swords (Korean release of Samurai Shodown III)"
		["ftfurspa"]="Fatal Fury Special (NGM-058 ~ NGH-058, set 2)"
		["galaxyfg"]="Galaxy Fight: Universal Warriors"
		["ganryu"]="Ganryu"
		["garou"]="Garou: Mark of the Wolves"
		["garoubl"]="Garou: Mark of the Wolves (bootleg)"
		["garouh"]="Garou: Mark of the Wolves (earlier release)"
		["garoup"]="Garou: Mark of the Wolves (prototype)"
		["ghostlop"]="Ghostlop"
		["goalx3"]="Goal! Goal! Goal!"
		["gowcaizr"]="Voltage Fighter Gowcaizer"
		["gpilots"]="Ghost Pilots"
		["gpilotsh"]="Ghost Pilots (NGH-020, US)"
		["gururin"]="Gururin"
		["hyprnoid"]="Hypernoid"
		["irnclado"]="Ironclad (prototype, bootleg)"
		["ironclad"]="Ironclad"
		["ironclado"]="Ironclad (prototype, bootleg)"
		["irrmaze"]="The Irritating Maze"
		["janshin"]="Janshin Densetsu: Quest of Jongmaster"
		["joyjoy"]="Puzzled"
		["kabukikl"]="Far East of Eden: Kabuki Klash"
		["karnovr"]="Karnov's Revenge"
		["kf2k2mp"]="The King of Fighters 2002 Magic Plus (bootleg)"
		["kf2k2mp2"]="The King of Fighters 2002 Magic Plus II (bootleg)"
		["kf2k2pla"]="The King of Fighters 2002 Plus (bootleg set 2)"
		["kf2k2pls"]="The King of Fighters 2002 Plus (bootleg)"
		["kf2k5uni"]="The King of Fighters 10th Anniversary 2005 Unique (The King of Fighters 2002 bootleg)"
		["kf10thep"]="The King of Fighters 10th Anniversary Extra Plus (The King of Fighters 2002 bootleg)"
		["kizuna"]="Kizuna Encounter: Super Tag Battle"
		["kof2k4se"]="The King of Fighters Special Edition 2004 (The King of Fighters 2002 bootleg)"
		["kof94"]="The King of Fighters '94"
		["kof95"]="The King of Fighters '95"
		["kof95a"]="The King of Fighters '95 (NGM-084, alt board)"
		["kof95h"]="The King of Fighters '95 (NGH-084)"
		["kof96"]="The King of Fighters '96"
		["kof96h"]="The King of Fighters '96 (NGH-214)"
		["kof97"]="The King of Fighters '97"
		["kof97h"]="The King of Fighters '97 (NGH-2320)"
		["kof97k"]="The King of Fighters '97 (Korean release)"
		["kof97oro"]="The King of Fighters '97 Chongchu Jianghu Plus 2003 (bootleg)"
		["kof97pls"]="The King of Fighters '97 Plus (bootleg)"
		["kof98"]="The King of Fighters '98: The Slugfest"
		["kof98a"]="The King of Fighters '98: The Slugfest (NGM-2420, alt board)"
		["kof98h"]="The King of Fighters '98: The Slugfest (NGH-2420)"
		["kof98k"]="The King of Fighters '98: The Slugfest (Korean release)"
		["kof98ka"]="The King of Fighters '98: The Slugfest (Korean release, set 2)"
		["kof99"]="The King of Fighters '99: Millennium Battle"
		["kof99e"]="The King of Fighters '99: Millennium Battle (earlier release)"
		["kof99h"]="The King of Fighters '99: Millennium Battle (NGH-2510)"
		["kof99k"]="The King of Fighters '99: Millennium Battle (Korean release)"
		["kof99p"]="The King of Fighters '99: Millennium Battle (prototype)"
		["kof2000"]="The King of Fighters 2000"
		["kof2000n"]="The King of Fighters 2000"
		["kof2001"]="The King of Fighters 2001"
		["kof2001h"]="The King of Fighters 2001 (NGH-2621)"
		["kof2002"]="The King of Fighters 2002"
		["kof2002b"]="The King of Fighters 2002 (bootleg)"
		["kof2003"]="The King of Fighters 2003"
		["kof2003h"]="The King of Fighters 2003 (NGH-2710)"
		["kof2003ps2"]="The King of Fighters 2003 (PS2)"
		["kog"]="King of Gladiators (The King of Fighters '97 bootleg)"
		["kotm"]="King of the Monsters"
		["kotm2"]="King of the Monsters 2: The Next Thing"
		["kotm2p"]="King of the Monsters 2: The Next Thing (prototype)"
		["kotmh"]="King of the Monsters (set 2)"
		["lans2004"]="Lansquenet"
		["lastblad"]="The Last Blade"
		["lastbladh"]="The Last Blade (NGH-2340)"
		["lastbld2"]="The Last Blade 2"
		["lasthope"]="Last Hope"
		["lastsold"]="The Last Soldier"
		["lbowling"]="League Bowling"
		["legendos"]="Legend of Success Joe"
		["lresort"]="Last Resort"
		["lresortp"]="Last Resort (prototype)"
		["lstbladh"]="Last Blade (NGH-2340)"
		["magdrop2"]="Magical Drop II"
		["magdrop3"]="Magical Drop III"
		["maglord"]="Magician Lord"
		["maglordh"]="Magician Lord (NGH-005)"
		["mahretsu"]="Mahjong Kyo Retsuden"
		["marukodq"]="Chibi Marukochan Deluxe Quiz"
		["matrim"]="Power Instinct Matrimelee"
		["miexchng"]="Money Puzzle Exchanger"
		["minasan"]="Minasan no Okagesamadesu! Dai Sugoroku Taikai"
		["montest"]="Monitor Test ROM"
		["moshougi"]="Shougi no Tatsujin: Master of Syougi"
		["ms4plus"]="Metal Slug 4 Plus (bootleg)"
		["mslug"]="Metal Slug: Super Vehicle-001"
		["mslug2"]="Metal Slug 2: Super Vehicle-001/II"
		["mslug2t"]="Metal Slug 2 Turbo (hack)"
		["mslug3"]="Metal Slug 3"
		["mslug3b6"]="Metal Slug 6 (Metal Slug 3 bootleg)"
		["mslug3h"]="Metal Slug 3 (NGH-2560)"
		["mslug4"]="Metal Slug 4"
		["mslug4h"]="Metal Slug 4 (NGH-2630)"
		["mslug5"]="Metal Slug 5"
		["mslug5h"]="Metal Slug 5 (NGH-2680)"
		["mslug6"]="Metal Slug 6 (Metal Slug 3 bootleg)"
		["mslugx"]="Metal Slug X: Super Vehicle-001"
		["mutnat"]="Mutation Nation"
		["nam1975"]="NAM-1975"
		["nblktigr"]="Neo Black Tiger"
		["ncombat"]="Ninja Combat"
		["ncombath"]="Ninja Combat (NGH-009)"
		["ncommand"]="Ninja Commando"
		["neobombe"]="Neo Bomberman"
		["neocup98"]="Neo-Geo Cup 98: The Road to the Victory"
		["neodrift"]="Neo Drift Out: New Technology"
		["neofight"]="Neo Fight"
		["neomrdo"]="Neo Mr. Do!"
		["neothund"]="Neo Thunder"
		["neotris"]="NeoTRIS (free beta version)"
		["ninjamas"]="Ninja Master's"
		["nitd"]="Nightmare in the Dark"
		["nitdbl"]="Nightmare in the Dark (bootleg)"
		["nsmb"]="New Super Mario Bros."
		["overtop"]="OverTop"
		["panicbom"]="Panic Bomber"
		["pbbblenb"]="Puzzle Bobble (bootleg)"
		["pbobbl2n"]="Puzzle Bobble 2"
		["pbobblen"]="Puzzle Bobble"
		["pbobblenb"]="Puzzle Bobble (bootleg)"
		["pgoal"]="Pleasure Goal"
		["pnyaa"]="Pochi and Nyaa"
		["popbounc"]="Pop 'n Bounce"
		["preisle2"]="Prehistoric Isle 2"
		["pspikes2"]="Power Spikes II"
		["pulstar"]="Pulstar"
		["puzzldpr"]="Puzzle De Pon! R!"
		["puzzledp"]="Puzzle De Pon!"
		["quizdai2"]="Quiz Meitantei Neo & Geo: Quiz Daisousa Sen part 2"
		["quizdais"]="Quiz Daisousa Sen: The Last Count Down"
		["quizdask"]="Quiz Salibtamjeong: The Last Count Down (Korean localized Quiz Daisousa Sen)"
		["quizkof"]="Quiz King of Fighters"
		["quizkofk"]="Quiz King of Fighters (Korean release)"
		["ragnagrd"]="Ragnagard"
		["rbff1"]="Real Bout Fatal Fury"
		["rbff1a"]="Real Bout Fatal Fury (bug fix revision)"
		["rbff2"]="Real Bout Fatal Fury 2: The Newcomers"
		["rbff2h"]="Real Bout Fatal Fury 2: The Newcomers (NGH-2400)"
		["rbff2k"]="Real Bout Fatal Fury 2: The Newcomers (Korean release)"
		["rbffspck"]="Real Bout Fatal Fury Special (Korean release)"
		["rbffspec"]="Real Bout Fatal Fury Special"
		["rbffspeck"]="Real Bout Fatal Fury Special (Korean release)"
		["ridhero"]="Riding Hero"
		["ridheroh"]="Riding Hero (set 2)"
		["roboarma"]="Robo Army (NGM-032 ~ NGH-032)"
		["roboarmy"]="Robo Army"
		["roboarmya"]="Robo Army (NGM-032 ~ NGH-032)"
		["rotd"]="Rage of the Dragons"
		["rotdh"]="Rage of the Dragons (NGH-2640?)"
		["s1945p"]="Strikers 1945 Plus"
		["samsh5fe"]="Samurai Shodown V Special Final Edition"
		["samsh5pf"]="Samurai Shodown V Perfect"
		["samsh5sp"]="Samurai Shodown V Special"
		["samsh5sph"]="Samurai Shodown V Special (2nd release, less censored)"
		["samsh5spho"]="Samurai Shodown V Special (1st release, censored)"
		["samsho"]="Samurai Shodown"
		["samsho2"]="Samurai Shodown II"
		["samsho2k"]="Saulabi Spirits (Korean release of Samurai Shodown II)"
		["samsho2ka"]="Saulabi Spirits (Korean release of Samurai Shodown II, set 2)"
		["samsho3"]="Samurai Shodown III"
		["samsho3h"]="Samurai Shodown III (NGH-087)"
		["samsho4"]="Samurai Shodown IV: Amakusa's Revenge"
		["samsho4k"]="Pae Wang Jeon Seol: Legend of a Warrior"
		["samsho5"]="Samurai Shodown V"
		["samsho5b"]="Samurai Shodown V (bootleg)"
		["samsho5h"]="Samurai Shodown V (NGH-2700)"
		["samsho5x"]="Samurai Shodown V (XBOX version hack)"
		["samshoh"]="Samurai Shodown (NGH-045)"
		["savagere"]="Savage Reign"
		["sbp"]="Super Bubble Pop"
		["scbrawlh"]="Soccer Brawl (NGH-031)"
		["sdodgeb"]="Super Dodge Ball"
		["sengoku"]="Sengoku"
		["sengoku2"]="Sengoku 2"
		["sengoku3"]="Sengoku 3"
		["sengokuh"]="Sengoku (NGH-017, US)"
		["shcktroa"]="Shock Troopers (set 2)"
		["shocktr2"]="Shock Troopers: 2nd Squad"
		["shocktro"]="Shock Troopers"
		["shocktroa"]="Shock Troopers (set 2)"
		["smbng"]="New Super Mario Bros. Demo"
		["smsh5sph"]="Samurai Shodown V Special (2nd release, less censored)"
		["smsh5spo"]="Samurai Shodown V Special (1st release, censored)"
		["smsho2k2"]="Saulabi Spirits (Korean release of Samurai Shodown II, set 2)"
		["socbrawl"]="Soccer Brawl"
		["socbrawlh"]="Soccer Brawl (NGH-031)"
		["sonicwi2"]="Aero Fighters 2"
		["sonicwi3"]="Aero Fighters 3"
		["spinmast"]="Spinmaster"
		["ssideki"]="Super Sidekicks"
		["ssideki2"]="Super Sidekicks 2: The World Championship"
		["ssideki3"]="Super Sidekicks 3: The Next Glory"
		["ssideki4"]="The Ultimate 11: The SNK Football Championship"
		["stakwin"]="Stakes Winner"
		["stakwin2"]="Stakes Winner 2"
		["strhoop"]="Street Hoop / Street Slam"
		["superspy"]="The Super Spy"
		["svc"]="SNK vs. Capcom: SVC Chaos"
		["svccpru"]="SNK vs. Capcom Remix Ultra"
		["svcplus"]="SNK vs. Capcom Plus (bootleg)"
		["svcsplus"]="SNK vs. Capcom Super Plus (bootleg)"
		["teot"]="The Eye of Typhoon: Tsunami Edition"
		["tetrismn"]="Tetris"
		["tophuntr"]="Top Hunter: Roddy & Cathy"
		["tophuntrh"]="Top Hunter: Roddy & Cathy (NGH-046)"
		["totc"]="Treasure of the Caribbean"
		["tpgolf"]="Top Player's Golf"
		["tphuntrh"]="Top Hunter: Roddy & Cathy (NGH-046)"
		["trally"]="Thrash Rally"
		["turfmast"]="Neo Turf Masters"
		["twinspri"]="Twinkle Star Sprites"
		["tws96"]="Tecmo World Soccer '96"
		["twsoc96"]="Tecmo World Soccer '96"
		["viewpoin"]="Viewpoint"
		["wakuwak7"]="Waku Waku 7"
		["wh1"]="World Heroes"
		["wh1h"]="World Heroes (ALH-005)"
		["wh1ha"]="World Heroes (set 3)"
		["wh2"]="World Heroes 2"
		["wh2j"]="World Heroes 2 Jet"
		["whp"]="World Heroes Perfect"
		["wjammers"]="Windjammers"
		["wjammss"]="Windjammers Supersonic"
		["xenocrisis"]="Xeno Crisis"
		["zedblade"]="Zed Blade"
		["zintrckb"]="ZinTricK"
		["zintrkcd"]="ZinTricK (CD conversion)"
		["zupapa"]="Zupapa!"
	)

	# NEOGEO to long name mappings Japanese
	declare -gA NEOGEO_PRETTY_JAPANESE=(
		["3countb"]="Fire Suplex"
		["2020bb"]=""
		["2020bba"]=""
		["2020bbh"]=""
		["abyssal"]=""
		["alpham2"]="ASO II: Last Guardian"
		["alpham2p"]="ASO II: Last Guardian (prototype)"
		["androdun"]=""
		["aodk"]="Tsuukai GANGAN Koushinkyoku"
		["aof"]="Ryuuko no Ken"
		["aof2"]="Ryuuko no Ken 2"
		["aof2a"]="Ryuuko no Ken 2 (NGH-056)"
		["aof3"]="Art of Fighting: Ryuuko no Ken Gaiden"
		["aof3k"]=""
		["b2b"]=""
		["badapple"]=""
		["bakatono"]=""
		["bangbead"]=""
		["bjourney"]="Raguy"
		["blazstar"]=""
		["breakers"]=""
		["breakrev"]=""
		["brningfh"]=""
		["brningfp"]=""
		["brnngfpa"]=""
		["bstars"]=""
		["bstars2"]=""
		["bstarsh"]=""
		["burningf"]=""
		["burningfh"]=""
		["burningfp"]=""
		["burningfpa"]=""
		["cabalng"]=""
		["columnsn"]=""
		["cphd"]=""
		["crswd2bl"]=""
		["crsword"]=""
		["ct2k3sa"]=""
		["ctomaday"]=""
		["cyberlip"]=""
		["diggerma"]=""
		["doubledr"]=""
		["eightman"]=""
		["fatfursp"]="Garou Densetsu Special"
		["fatfurspa"]="Garou Densetsu Special (NGM-058 ~ NGH-058, set 2)"
		["fatfury1"]="Garou Densetsu: Shukumei no Tatakai"
		["fatfury2"]="Garou Densetsu 2: Arata-naru Tatakai"
		["fatfury3"]="Garou Densetsu 3: Haruka-naru Tatakai"
		["fbfrenzy"]=""
		["fghtfeva"]="Wang Jung Wang (set 2)"
		["fightfev"]="Wang Jung Wang"
		["fightfeva"]="Wang Jung Wang (set 2)"
		["flipshot"]=""
		["frogfest"]=""
		["froman2b"]=""
		["fswords"]=""
		["ftfurspa"]="Garou Densetsu Special (NGM-058 ~ NGH-058, set 2)"
		["galaxyfg"]=""
		["ganryu"]="Musashi Ganryuki"
		["garou"]=""
		["garoubl"]=""
		["garouh"]=""
		["garoup"]=""
		["ghostlop"]=""
		["goalx3"]=""
		["gowcaizr"]="Choujin Gakuen Gowcaizer"
		["gpilots"]=""
		["gpilotsh"]=""
		["gururin"]=""
		["hyprnoid"]=""
		["irnclado"]="Choutetsu Brikin'ger (prototype, bootleg)"
		["ironclad"]="Choutetsu Brikin'ger"
		["ironclado"]="Choutetsu Brikin'ger (prototype, bootleg)"
		["irrmaze"]="Ultra Denryu Iraira Bou"
		["janshin"]=""
		["joyjoy"]="Joy Joy Kid"
		["kabukikl"]="Tengai Makyou: Shin Den"
		["karnovr"]="Fighter's History Dynamite"
		["kf2k2mp"]=""
		["kf2k2mp2"]=""
		["kf2k2pla"]=""
		["kf2k2pls"]=""
		["kf2k5uni"]=""
		["kf10thep"]=""
		["kizuna"]="Fu'un Super Tag Battle"
		["kof2k4se"]=""
		["kof94"]=""
		["kof95"]=""
		["kof95a"]=""
		["kof95h"]=""
		["kof96"]=""
		["kof96h"]=""
		["kof97"]=""
		["kof97h"]=""
		["kof97k"]=""
		["kof97oro"]=""
		["kof97pls"]=""
		["kof98"]="King of Fighters '98: Dream Match Never Ends"
		["kof98a"]="King of Fighters '98: Dream Match Never Ends (NGM-2420, alt board)"
		["kof98h"]="King of Fighters '98: Dream Match Never Ends (NGH-2420)"
		["kof98k"]=""
		["kof98ka"]=""
		["kof99"]=""
		["kof99e"]=""
		["kof99h"]=""
		["kof99k"]=""
		["kof99p"]=""
		["kof2000"]=""
		["kof2000n"]=""
		["kof2001"]=""
		["kof2001h"]=""
		["kof2002"]=""
		["kof2002b"]=""
		["kof2003"]=""
		["kof2003h"]=""
		["kof2003ps2"]=""
		["kog"]=""
		["kotm"]=""
		["kotm2"]=""
		["kotm2p"]=""
		["kotmh"]=""
		["lans2004"]=""
		["lastblad"]="Bakumatsu Roman: Gekka no Kenshi"
		["lastbladh"]="Bakumatsu Roman: Gekka no Kenshi (NGH-2340)"
		["lastbld2"]="Bakumatsu Roman: Dai Ni Maku Gekka no Kenshi"
		["lasthope"]=""
		["lastsold"]=""
		["lbowling"]=""
		["legendos"]="Ashita no Joe Densetsu"
		["lresort"]=""
		["lresortp"]=""
		["lstbladh"]="Bakumatsu Roman: Gekka no Kenshi (NGH-2340)"
		["magdrop2"]="Magical Drop 2"
		["magdrop3"]=""
		["maglord"]=""
		["maglordh"]=""
		["mahretsu"]=""
		["marukodq"]=""
		["matrim"]="Shin Goketsuji Ichizoku: Tokon Matrimelee"
		["miexchng"]="Money Idol Exchanger"
		["minasan"]=""
		["montest"]=""
		["moshougi"]=""
		["ms4plus"]=""
		["mslug"]=""
		["mslug2"]=""
		["mslug2t"]=""
		["mslug3"]=""
		["mslug3b6"]=""
		["mslug3h"]=""
		["mslug4"]=""
		["mslug4h"]=""
		["mslug5"]=""
		["mslug5h"]=""
		["mslug6"]=""
		["mslugx"]=""
		["mutnat"]=""
		["nam1975"]=""
		["nblktigr"]=""
		["ncombat"]=""
		["ncombath"]=""
		["ncommand"]=""
		["neobombe"]=""
		["neocup98"]=""
		["neodrift"]=""
		["neofight"]=""
		["neomrdo"]=""
		["neothund"]=""
		["neotris"]=""
		["ninjamas"]="Haoh-ninpo-cho"
		["nitd"]=""
		["nitdbl"]=""
		["nsmb"]=""
		["overtop"]=""
		["panicbom"]=""
		["pbbblenb"]="Bust-A-Move (bootleg)"
		["pbobbl2n"]="Bust-A-Move Again"
		["pbobblen"]="Bust-A-Move"
		["pbobblenb"]="Bust-A-Move (bootleg)"
		["pgoal"]=""
		["pnyaa"]="Pochi to Nyaa"
		["popbounc"]="Gapporin"
		["preisle2"]=""
		["pspikes2"]=""
		["pulstar"]=""
		["puzzldpr"]=""
		["puzzledp"]=""
		["quizdai2"]=""
		["quizdais"]=""
		["quizdask"]=""
		["quizkof"]=""
		["quizkofk"]=""
		["ragnagrd"]="Shin-Oh-Ken"
		["rbff1"]="Real Bout Garou Densetsu"
		["rbff1a"]="Real Bout Garou Densetsu (bug fix revision)"
		["rbff2"]="Real Bout Garou Densetsu 2: The Newcomers"
		["rbff2h"]="Real Bout Garou Densetsu 2: The Newcomers (NGH-2400)"
		["rbff2k"]=""
		["rbffspck"]=""
		["rbffspec"]="Real Bout Garou Densetsu Special"
		["rbffspeck"]=""
		["ridhero"]=""
		["ridheroh"]=""
		["roboarma"]=""
		["roboarmy"]=""
		["roboarmya"]=""
		["rotd"]=""
		["rotdh"]=""
		["s1945p"]=""
		["samsh5fe"]="Samurai Shodown Zero Special Final Edition"
		["samsh5pf"]="Samurai Spirits Zero Perfect"
		["samsh5sp"]="Samurai Spirits Zero Special"
		["samsh5sph"]="Samurai Spirits Zero Special (2nd release, less censored)"
		["samsh5spho"]="Samurai Spirits Zero Special (1st release, censored)"
		["samsho"]="Samurai Spirits"
		["samsho2"]="Shin Samurai Spirits: Haohmaru Jigokuhen"
		["samsho2k"]=""
		["samsho2ka"]=""
		["samsho3"]="Samurai Spirits: Zankurou Musouken"
		["samsho3h"]="Samurai Spirits: Zankurou Musouken (NGH-087)"
		["samsho4"]="Samurai Spirits: Amakusa Kourin"
		["samsho4k"]=""
		["samsho5"]="Samurai Spirits Zero"
		["samsho5b"]="Samurai Spirits Zero (bootleg)"
		["samsho5h"]="Samurai Spirits Zero (NGH-2700)"
		["samsho5x"]="Samurai Spirits Zero (XBOX version hack)"
		["samshoh"]="Samurai Spirits (NGH-045)"
		["savagere"]="Fu'un Mokushiroku: Kakutou Sousei"
		["sbp"]=""
		["scbrawlh"]=""
		["sdodgeb"]="Kunio no Nekketsu Toukyuu Densetsu"
		["sengoku"]="Sengoku Denshou"
		["sengoku2"]="Sengoku Denshou 2"
		["sengoku3"]="Sengoku Denshou 2001"
		["sengokuh"]="Sengoku Denshou (NGH-017, US)"
		["shcktroa"]=""
		["shocktr2"]=""
		["shocktro"]=""
		["shocktroa"]=""
		["smbng"]=""
		["smsh5sph"]="Samurai Spirits Zero Special (2nd release, less censored)"
		["smsh5spo"]="Samurai Spirits Zero Special (1st release, censored)"
		["smsho2k2"]=""
		["socbrawl"]=""
		["socbrawlh"]=""
		["sonicwi2"]="Sonic Wings 2"
		["sonicwi3"]="Sonic Wings 3"
		["spinmast"]="Miracle Adventure"
		["ssideki"]="Tokuten Ou"
		["ssideki2"]="Tokuten Ou 2: Real Fight Football"
		["ssideki3"]="Tokuten Ou 3: Eikou e no Chousen"
		["ssideki4"]="Tokuten Ou: Honoo no Libero"
		["stakwin"]="Stakes Winner: GI Kinzen Seiha e no Michi"
		["stakwin2"]=""
		["strhoop"]="Dunk Dream"
		["superspy"]=""
		["svc"]=""
		["svccpru"]=""
		["svcplus"]=""
		["svcsplus"]=""
		["teot"]=""
		["tetrismn"]=""
		["tophuntr"]=""
		["tophuntrh"]=""
		["totc"]=""
		["tpgolf"]=""
		["tphuntrh"]=""
		["trally"]=""
		["turfmast"]="Big Tournament Golf"
		["twinspri"]=""
		["tws96"]=""
		["twsoc96"]=""
		["viewpoin"]=""
		["wakuwak7"]=""
		["wh1"]=""
		["wh1h"]=""
		["wh1ha"]=""
		["wh2"]=""
		["wh2j"]=""
		["whp"]=""
		["wjammers"]="Flying Power Disc"
		["wjammss"]=""
		["xenocrisis"]=""
		["zedblade"]="Operation Ragnarok"
		["zintrckb"]="Oshidashi Zentrix"
		["zintrkcd"]="Oshidashi Zentrix (CD conversion)"
		["zupapa"]=""
	)
}

function startup_tasks() {
	init_vars
	read_samini
	init_paths
	init_data # Setup data arrays
	update_tasks
}

function start_pipe_readers() {
	if [[ ! -p ${SAM_cmd_pipe} ]]; then
		mkfifo ${SAM_cmd_pipe}
	fi

	while true; do
		if [[ -p ${SAM_cmd_pipe} ]]; then
			if read line <${SAM_cmd_pipe}; then
				set -- junk ${line}
				shift
				case "${1}" in
				stop | quit)
					sam_exit 0 "stop"
					break
					;;
				exit)
					sam_exit ${2}
					break
					;;
				skip | next)
					tmux send-keys -t SAM C-c ENTER
					;;
				*)
					echo " ERROR! ${line} is unknown."
					echo " Try $(basename -- ${0}) help"
					echo " Or check the Github readme."
					echo " Named Pipe"
					;;
				esac
			fi
		fi
		sleep 0.1
	done &

	while true; do
		if read line <${activity_pipe2}; then
			echo " Activity detected! (${line})"
			play_or_exit
		fi
		sleep 0.1
	done &
}

# ======== DEBUG OUTPUT =========
function debug_output() {
	echo " ********************************************************************************"
	# ======== GLOBAL VARIABLES =========
	echo " mrsampath: ${mrsampath}"
	echo " misterpath: ${misterpath}"
	echo " sampid: ${sampid}"
	echo " samprocess: ${samprocess}"
	echo ""
	# ======== LOCAL VARIABLES ========
	echo " commandline: ${@}"
	echo " repository_url: ${repository_url}"
	echo " branch: ${branch}"

	echo ""
	echo " gametimer: ${gametimer}"
	echo " corelist: ${corelist}"
	echo " usezip: ${usezip}"

	echo " mralist: ${mralist_tmp}"
	echo " listenmouse: ${listenmouse}"
	echo " listenkeyboard: ${listenkeyboard}"
	echo " listenjoy: ${listenjoy}"
	echo ""
	echo " arcadepath: ${arcadepath}"
	echo " gbapath: ${gbapath}"
	echo " genesispath: ${genesispath}"
	echo " megacdpath: ${megacdpath}"
	echo " neogeopath: ${neogeopath}"
	echo " nespath: ${nespath}"
	echo " snespath: ${snespath}"
	echo " tgfx16path: ${tgfx16path}"
	echo " tgfx16cdpath: ${tgfx16cdpath}"
	echo ""
	echo " gbalist: ${gbalist}"
	echo " genesislist: ${genesislist}"
	echo " megacdlist: ${megacdlist}"
	echo " neogeolist: ${neogeolist}"
	echo " neslist: ${neslist}"
	echo " sneslist: ${sneslist}"
	echo " tgfx16list: ${tgfx16list}"
	echo " tgfx16cdlist: ${tgfx16cdlist}"
	echo ""
	echo " arcadeexclude: ${arcadeexclude[@]}"
	echo " gbaexclude: ${gbaexclude[@]}"
	echo " genesisexclude: ${genesisexclude[@]}"
	echo " megacdexclude: ${megacdexclude[@]}"
	echo " neogeoexclude: ${neogeoexclude[@]}"
	echo " nesexclude: ${nesexclude[@]}"
	echo " snesexclude: ${snesexclude[@]}"
	echo " tgfx16exclude: ${tgfx16exclude[@]}"
	echo " tgfx16cdexclude: ${tgfx16cdexclude[@]}"
	echo " ********************************************************************************"
	read -p " Continuing in 5 seconds or press any key..." -n 1 -t 5 -r -s
}
# ========= PARSE INI =========

# Read INI
function read_samini() {
	if [ -f "${misterpath}/Scripts/Super Attract Mode.ini" ]; then
		source "${misterpath}/Scripts/Super Attract Mode.ini"
		# Remove trailing slash from paths
		for var in $(grep "^[^#;]" "${misterpath}/Scripts/Super Attract Mode.ini" | grep "path=" | cut -f1 -d"="); do
			declare -g ${var}="${!var%/}"
		done
		for var in $(grep "^[^#;]" "${misterpath}/Scripts/Super Attract Mode.ini" | grep "pathextra=" | cut -f1 -d"="); do
			declare -g ${var}="${!var%/}"
		done
		for var in $(grep "^[^#;]" "${misterpath}/Scripts/Super Attract Mode.ini" | grep "pathrbf=" | cut -f1 -d"="); do
			declare -g ${var}="${!var%/}"
		done
	fi

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

function GET_SYSTEM_FOLDER() {
	local SYSTEM="${1}"
	for folder in "${GAMESDIR_FOLDERS[@]}"; do
		local RESULT=$(find "${folder}" -maxdepth 1 -iname "${SYSTEM}" -printf "%P\n" -quit 2>/dev/null)
		if [[ "${RESULT}" != "" ]]; then
			GET_SYSTEM_FOLDER_GAMESDIR="${folder}"
			GET_SYSTEM_FOLDER_RESULT="${RESULT}"
			break
		fi
	done
}

function defaultpath() {
	local SYSTEM="${1}"
	local SYSTEM_ORG="${SYSTEM}"
	if [ ${SYSTEM} == "arcade" ]; then
		SYSTEM="_arcade"
	fi
	if [ ${SYSTEM} == "atari2600" ]; then
		SYSTEM="atari7800"
	fi
	if [ ${SYSTEM} == "fds" ]; then
		SYSTEM="nes"
	fi
	if [ ${SYSTEM} == "gb" ]; then
		SYSTEM="gameboy"
	fi
	if [ ${SYSTEM} == "gbc" ]; then
		SYSTEM="gameboy"
	fi
	if [ ${SYSTEM} == "gg" ]; then
		SYSTEM="sms"
	fi
	if [ ${SYSTEM} == "tgfx16cd" ]; then
		SYSTEM="tgfx16-cd"
	fi
	shift

	GET_SYSTEM_FOLDER "${SYSTEM}"
	local SYSTEM_FOLDER="${GET_SYSTEM_FOLDER_RESULT}"
	local GAMESDIR="${GET_SYSTEM_FOLDER_GAMESDIR}"

	if [[ "${SYSTEM_FOLDER}" != "" ]]; then
		eval ${SYSTEM_ORG}"path"="${GAMESDIR}/${GET_SYSTEM_FOLDER_RESULT}"
	fi
}

# ======== SAM MENU ========
function sam_premenu() {
	echo "+---------------------------+"
	echo "| MiSTer Super Attract Mode |"
	echo "+---------------------------+"
	echo " SAM Configuration:"
	if [ $(grep -ic "SuperAttract" "${userstartup}") != "0" ]; then
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
	echo " auto-configuration"
	echo ""

	for i in {5..1}; do
		echo -ne " Updating SAM in ${i}...\033[0K\r"
		premenu="Default"
		read -r -s -N 1 -t 1 key
		if [[ "${key}" == "A" ]]; then
			premenu="Menu"
			break
		elif [[ "${key}" == "B" ]]; then
			premenu="Start"
			break
		elif [[ "${key}" == "C" ]]; then
			premenu="Default"
			break
		fi
	done
	parse_cmd ${premenu}
}

function sam_menu() {
	inmenu=1
	dialog --clear --no-cancel --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ Main Menu ]" \
		--menu "Use the arrow keys and enter \nor the d-pad and A button" 0 0 0 \
		Start "Start SAM now" \
		Startmonitor "Start SAM now and monitor (ssh)" \
		Skip "Skip game" \
		Stop "Stop SAM" \
		Update "Update SAM to latest" \
		'' "" \
		Single "Single core selection" \
		Include "Single category selection" \
		Exclude "Exclude categories" \
		Gamemode "Game roulette" \
		Config "Configure INI Settings" \
		Favorite "Copy current game to _Favorites folder" \
		Gamelists "Game Lists - Create or Delete" \
		Reset "Reset or uninstall SAM" \
		Autoplay "Autoplay Configuration" \
		'' "" \
		Cancel "Exit now" 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	clear

	if [ "${samquiet}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function sam_singlemenu() {
	declare -a menulist=()
	for core in ${corelistall}; do
		menulist+=("${core^^}")
		menulist+=("${CORE_PRETTY[${core}]} games only")
	done

	dialog --clear --no-cancel --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ Single System Select ]" \
		--menu "Which system?" 0 0 0 \
		"${menulist[@]}" \
		Back 'Previous menu' 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	clear

	if [ "${samquiet}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function sam_resetmenu() {
	inmenu=1
	dialog --clear --no-cancel --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ Reset ]" \
		--menu "Select an option" 0 0 0 \
		Deleteall "Reset/Delete all files" \
		Default "Reinstall SAM and enable Autostart" \
		Back 'Previous menu' 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	clear

	if [ "${samquiet}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function sam_gamelistmenu() {
	inmenu=1
	dialog --clear --no-cancel --ascii-lines --colors \
		--backtitle "Super Attract Mode" --title "[ GAMELIST MENU ]" \
		--msgbox "Game Lists contain filenames that SAM can play for each core. \n\nThey get created automatically when SAM plays games. Here you can create or delete those lists." 0 0
	dialog --clear --no-cancel --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ GAMELIST MENU ]" \
		--menu "Select an option" 0 0 0 \
		CreateGL "Create all Game Lists" \
		DeleteGL "Delete all Game Lists" \
		Back 'Previous menu' 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	clear

	if [ "${samquiet}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function sam_autoplaymenu() {
	dialog --clear --no-cancel --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ Configure Autoplay ]" \
		--menu "Select an option" 0 0 0 \
		Enable "Enable Autoplay" \
		Disable "Disable Autoplay" \
		Back 'Previous menu' 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")

	clear
	if [ "${samquiet}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function sam_configmenu() {
	dialog --clear --ascii-lines --no-cancel \
		--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
		--msgbox "Here you can configure the INI settings for SAM.\n\nUse TAB to switch between editing, the OK and Cancel buttons." 0 0

	dialog --clear --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
		--editbox "${misterpath}/Scripts/Super Attract Mode.ini" 0 0 2>"/tmp/.SAMmenu"

	if [ -s "/tmp/.SAMmenu" ] && [ "$(diff -wq "/tmp/.SAMmenu" "${misterpath}/Scripts/Super Attract Mode.ini")" ]; then
		cp -f "/tmp/.SAMmenu" "${misterpath}/Scripts/Super Attract Mode.ini" &>/dev/null
		dialog --clear --ascii-lines --no-cancel \
			--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
			--msgbox "Changes saved!" 0 0
	fi

	parse_cmd menu
}

function sam_gamemodemenu() {
	dialog --clear --no-cancel --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ GAME ROULETTE ]" \
		--msgbox "In Game Roulette mode SAM selects games for you. \n\nYou have a pre-defined amount of time to play this game, then SAM will move on to play the next game. \n\nPlease do a cold reboot when done playing." 0 0
	dialog --clear --no-cancel --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ GAME ROULETTE ]" \
		--menu "Select an option" 0 0 0 \
		Roulette5 "Play a random game for 5 minutes. " \
		Roulette10 "Play a random game for 10 minutes. " \
		Roulette15 "Play a random game for 15 minutes. " \
		Roulette20 "Play a random game for 20 minutes. " \
		Roulette25 "Play a random game for 25 minutes. " \
		Roulette30 "Play a random game for 30 minutes. " \
		Roulettetimer "Play a random game for ${roulettetimer} secs (roulettetimer in Super Attract Mode.ini). " \
		Back 'Previous menu' 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	clear

	if [ "${samquiet}" == "no" ]; then echo " menuresponse: ${menuresponse}"; fi
	parse_cmd ${menuresponse}
}

function samedit_exclude() {
	declare -a menulist=()
	for core in ${corelist}; do
		menulist+=(ex_"${core}")
		menulist+=("Select ${CORE_PRETTY[${core,,}]} gamelist")
	done
	dialog --clear --no-cancel --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ EXCLUSION EDITOR ]" \
		--menu "Which system?" 0 0 0 \
		"${menulist[@]}" \
		Back 'Previous menu' 2>"/tmp/.SAMmenu"
	menuresponse=$(<"/tmp/.SAMmenu")
	clear
	parse_cmd ${menuresponse}

}

function samedit_include() {
	dialog --clear --no-cancel --ascii-lines --colors \
		--backtitle "Super Attract Mode" --title "[ CATEGORY SELECTION ]" \
		--msgbox "Play games from only one category.\n\n\Z1Please use Everdrive packs for this mode. \Zn \n\nSome categories (like country selection) will probably work with some other rompacks as well. \n\nMake sure you have game lists created for this mode." 0 0
	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ CATEGORY SELECTION ]" \
		--menu "Only play games from the following categories" 0 0 0 \
		''"("'usa'")"'' "Only USA Games" \
		''"("'japan'")"'' "Only Japanese Games" \
		''"("'europe'")"'' "Only Europe games" \
		'shoot '"'"'em' "Only Shoot 'Em Ups" \
		'beat '"'"'em' "Only Beat 'Em Ups" \
		'role playing' "Only Role Playing Games" \
		pinball "Only Pinball Games" \
		platformers "Only Platformers" \
		'genre/fight' "Only Fighting Games" \
		trivia "Only Trivia Games" \
		sports "Only Sport Games" \
		racing "Only Racing Games" \
		hacks "Only Hacks" \
		translations "Only Translated Games" \
		homebrew "Only Homebrew" 2>"/tmp/.SAMmenu"

	opt=$?
	menuresponse=$(<"/tmp/.SAMmenu")
	clear

	if [ "$opt" != "0" ]; then
		sam_menu
	else
		echo "Please wait... getting things ready."
		declare -a corelist=()
		declare -a gamelists=()
		categ="${menuresponse}"
		# echo "${menuresponse}"
		# Delete all temporary Game lists
		if compgen -G "${gamelistpathtmp}/*_gamelist.txt" >/dev/null; then
			rm ${gamelistpathtmp}/*_gamelist.txt
		fi
		gamelists=($(find "${gamelistpath}" -name "*_gamelist.txt"))

		# echo ${gamelists[@]}
		for list in ${gamelists[@]}; do
			listfile=$(basename ${list})
			# awk -v category="$categ" 'tolower($0) ~ category' "${list}" > "${gamelistpathtmp}/${listfile}"
			grep -i "${categ}" "${list}" >"${tmpfile}"
			awk -F'/' '!seen[$NF]++' "${tmpfile}" >"${gamelistpathtmp}/${listfile}"
			[[ -s "${gamelistpathtmp}/${listfile}" ]] || rm "${gamelistpathtmp}/${listfile}"
		done

		corelist=$(find "${gamelistpathtmp}" -name "*_gamelist.txt" -exec basename \{} \; | cut -d '_' -f 1)
		dialog --clear --no-cancel --ascii-lines --colors \
			--backtitle "Super Attract Mode" --title "[ CATEGORY SELECTION ]" \
			--msgbox "SAM will start now and only play games from the "${categ^^}" category.\n\nOn cold reboot, SAM will get reset automatically to play all games again. " 0 0
		loop_core
	fi

}

function samedit_excltags() {
	dialog --title "[ EXCLUDE CATEGORY SELECTION ]" --ascii-lines --checklist \
		"Which tags do you want to exclude?" 0 0 0 \
		"Beta" "" OFF \
		"Hack" "" OFF \
		"Homebrew" "" OFF \
		"Prototypes" "" OFF \
		"Unlicensed" "" OFF \
		"Translations" "" OFF \
		"USA" "" OFF \
		"Japan" "" OFF \
		"Europe" "" OFF \
		"Australia" "" OFF \
		"Brazil" "" OFF \
		"China" "" OFF \
		"France" "" OFF \
		"Germany" "" OFF "Italy" "" OFF \
		"Korea" "" OFF \
		"Spain" "" OFF \
		"Sweden" "" OFF 2>"/tmp/.SAMmenu"

	opt=$?
	menuresponse=$(<"/tmp/.SAMmenu")

	if [ "$opt" != "0" ]; then
		sam_menu
	else
		echo "Please wait... creating list."
		categ="$(echo ${menuresponse} | tr ' ' '|')"
		if [ ! -z ${categ} ]; then
			awk -v category="$categ" 'BEGIN {IGNORECASE = 1}  $0 ~ category' "${gamelistpath}/${nextcore}_gamelist.txt" >"${gamelistpath}/${nextcore}_gamelist_exclude.txt"
		else
			echo "" >"${gamelistpath}/${nextcore}_gamelist_exclude.txt"
		fi
		core=${nextcore}
		[[ -f "${gamelistpathtmp}/${nextcore}_gamelist.txt" ]] && rm "${gamelistpathtmp}/${nextcore}_gamelist.txt"
		samedit_taginfo
	fi

}

function samedit_taginfo() {
	dialog --clear --ascii-lines --no-cancel \
		--backtitle "Super Attract Mode" --title "[ TAG EXCLUSION SUMMARY ]" \
		--msgbox "Gamelist: ${CORE_PRETTY[${core,,}]} 
	\n\nExcluded tags:
	\n\n
	${menuresponse} 
	\n\n\n\n
	If you would like to return to the original list, just run \n
	'Exclude game categories' again without any tags selected." 0 0
	clear
	sam_menu
}

function write_to_SAM_cmd_pipe() {
	if [[ ! -p ${SAM_cmd_pipe} ]]; then
		echo "SAM not running"
		exit 1
	fi
	echo "${@}" >${SAM_cmd_pipe}
}

function write_to_TTY_cmd_pipe() {
	if [[ ! -p ${TTY_cmd_pipe} ]]; then
		echo "TTY2oled not running"
		exit 1
	fi
	echo "${@}" >${TTY_cmd_pipe}
}

function write_to_MCP_cmd_pipe() {
	if [[ ! -p ${MCP_cmd_pipe} ]]; then
		echo "MCP not running"
		exit 1
	fi
	echo "${@}" >${MCP_cmd_pipe}
}

function process_cmd() {
	case "${1,,}" in
	start | restart | bootstart) # Start as from init
		sam_start
		exit 0
		;;
	stop | quit)
		write_to_SAM_cmd_pipe ${1-}
		exit 0
		;;
	exit)
		write_to_SAM_cmd_pipe ${1-}
		exit 0
		;;
	skip | next)
		echo " Skipping to next game..."
		write_to_SAM_cmd_pipe ${1-}
		exit 0
		;;
	monitor)
		sam_monitor_new
		exit 0
		;;
	update) # Update SAM
		startup_tasks
		sam_update
		;;
	install) # Enable SAM autoplay mode
		startup_tasks
		sam_install
		;;
	uninstall) # Disable SAM autoplay
		startup_tasks
		sam_uninstall
		;;
	speedtest)
		startup_tasks
		speedtest
		;;
	create-gamelists)
		startup_tasks
		creategl
		;;
	delete-gamelists)
		startup_tasks
		deletegl
		;;
	help)
		sam_help
		;;
	*)
		return
		;;
	esac
}

function source-only() {
	startup_tasks
	return 0
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
			arcade | atari2600 | atari5200 | atari7800 | atarilynx | c64 | fds | gb | gbc | gba | genesis | gg | megacd | neogeo | nes | s32x | sms | snes | tgfx16 | tgfx16cd | psx)
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
			arcade | atari2600 | atari5200 | atari7800 | atarilynx | c64 | fds | gb | gbc | gba | genesis | gg | megacd | neogeo | nes | s32x | sms | snes | tgfx16 | tgfx16cd | psx)
				: # Placeholder since we parsed these above
				;;
			update) # Update SAM
				# echo "Use new commandline option --update"
				sam_update
				break
				;;
			favorite)
				mglfavorite
				break
				;;
			deleteall)
				deleteall
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
				# echo "Use new commandline option --help"
				break
				;;
			esac
			[ ! -z ${2} ] && shift
			config_bind
			disable_bootrom # Disable Bootrom until Reboot
			case "${1,,}" in
			start_real) # Start as a detached tmux session for monitoring
				sam_start_new
				break
				;;
			startmonitor)
				sam_start_new
				sam_monitor_new
				break
				;;
			autoconfig)
				tmux kill-session -t MCP &>/dev/null
				# there_can_be_only_one
				sam_update
				mcp_start
				sam_install
				break
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
			exclude)
				samedit_exclude
				break
				;;
			ex_atari2600 | ex_atari5200 | ex_atari7800 | ex_atarilynx | ex_c64 | ex_fds | ex_gb | ex_gbc | ex_gba | ex_genesis | ex_gg | ex_megacd | ex_neogeo | ex_nes | ex_s32x | ex_sms | ex_snes | ex_tgfx16 | ex_tgfx16cd | ex_psx)
				nextcore=${1:3}
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
			gamelists)
				sam_gamelistmenu
				break
				;;
			roulette5)
				only_survivor
				listenmouse="No"
				listenkeyboard="No"
				listenjoy="No"
				gametimer=300
				loop_core
				break
				;;
			roulette10)
				only_survivor
				listenmouse="No"
				listenkeyboard="No"
				listenjoy="No"
				gametimer=600
				loop_core
				break
				;;
			roulette15)
				only_survivor
				listenmouse="No"
				listenkeyboard="No"
				listenjoy="No"
				gametimer=900
				loop_core
				break
				;;
			roulette20)
				only_survivor
				listenmouse="No"
				listenkeyboard="No"
				listenjoy="No"
				gametimer=1200
				loop_core
				break
				;;
			roulette25)
				only_survivor
				listenmouse="No"
				listenkeyboard="No"
				listenjoy="No"
				gametimer=1500
				loop_core
				break
				;;
			roulette30)
				only_survivor
				listenmouse="No"
				listenkeyboard="No"
				listenjoy="No"
				gametimer=1800
				loop_core
				break
				;;
			roulettetimer)
				only_survivor
				listenmouse="No"
				listenkeyboard="No"
				listenjoy="No"
				gametimer=${roulettetimer}
				loop_core
				break
				;;
			*)
				echo " ERROR! ${1} is unknown."
				echo " Try $(basename -- ${0}) help"
				echo " Or check the Github readme."
				echo "parse_cmd"
				break
				;;
			esac
		done
	fi
}

# ======== SAM COMMANDS ========
function sam_update() { # sam_update (next command)
	# Ensure the MiSTer SAM data directory exists
	mkdir -p "${mrsampath}" &>/dev/null

	if [ ! "$(dirname -- ${0})" == "/tmp" ]; then
		# Warn if using non-default branch for updates
		if [ ! "${branch}" == "main" ]; then
			echo ""
			echo "*******************************"
			echo " Updating from ${branch}"
			echo "*******************************"
			echo ""
		fi

		# Download the newest SuperAttract_on.sh to /tmp
		get_samstuff SuperAttract_on.sh /tmp
		if [ -f /tmp/SuperAttract_on.sh ]; then
			if [ ${1} ]; then
				echo " Continuing setup with latest SuperAttract_on.sh..."
				/tmp/SuperAttract_on.sh ${1}
				return 0
			else
				echo " Launching latest"
				echo " SuperAttract_on.sh..."
				/tmp/SuperAttract_on.sh update
				return 0
			fi
		else
			# /tmp/SuperAttract_on.sh isn't there!
			echo " SAM update FAILED"
			echo " No Internet?"
			return 1
		fi
	else # We're running from /tmp - download dependencies and proceed
		cp --force "/tmp/SuperAttract_on.sh" "/media/fat/Scripts/SuperAttract_on.sh" &>/dev/null

		get_partun
		get_mbc
		get_inputmap
		get_samstuff .SuperAttract/SuperAttract_init
		get_samstuff .SuperAttract/SuperAttract_MCP
		get_samstuff .SuperAttract/SuperAttract_joy.py
		get_samstuff .SuperAttract/SuperAttract_keyboard.py
		get_samstuff .SuperAttract/SuperAttract_mouse.py
		get_samstuff .SuperAttract/SuperAttract_tty2oled
		get_samstuff .SuperAttract/SuperAttract_control.sh
		get_samstuff SuperAttract_off.sh /media/fat/Scripts


		if [ -f "/media/fat/Scripts/Super Attract Mode.ini" ]; then
			echo " MiSTer SAM INI already exists... Merging with new ini."
			get_samstuff "Super Attract Mode.ini" /tmp
			echo " Backing up Super Attract Mode.ini to Super Attract Mode.ini.bak"
			cp /media/fat/Scripts/"Super Attract Mode.ini" /media/fat/Scripts/"Super Attract Mode.ini.bak" &>/dev/null
			echo -n " Merging ini values.."
			# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
			sed -i 's/==/--/g' /media/fat/Scripts/"Super Attract Mode.ini"
			sed -i 's/-=/--/g' /media/fat/Scripts/"Super Attract Mode.ini"
			awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' /media/fat/Scripts/Super Attract Mode.ini /tmp/"Super Attract Mode.ini" >/tmp/SuperAttract.tmp && mv --force /tmp/SuperAttract.tmp /media/fat/Scripts/"Super Attract Mode.ini"
			echo "Done."

		else
			get_samstuff "Super Attract Mode.ini" /media/fat/Scripts
		fi

	fi

	echo " Update complete!"
	return

	if [ ${inmenu} -eq 1 ]; then
		sleep 1
		sam_menu
	fi

}

function sam_install() { # Install SAM to startup
	echo -n " Installing MiSTer SAM..."

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
			cp "${userstartuptpl}" "${userstartup}" &>/dev/null
		else
			echo "Building ${userstartup}"
		fi
	fi
	if [ $(grep -ic "SuperAttract" ${userstartup}) = "0" ]; then
		echo -e "Add MiSTer SAM to ${userstartup}\n"
		echo -e "\n# Startup SuperAttract - Super Attract Mode" >>${userstartup}
		echo -e "[[ -e "${mrsampath}/SuperAttract_init" ]] && "${mrsampath}/SuperAttract_init " \$1 &" >>"${userstartup}"
	fi
	echo "Done."
	echo " SAM install complete."
	echo -e "\n\n\n"
	boot_samtimeout=$((${samtimeout} + ${bootsleep}))
	echo -ne "\e[1m" SAM will start ${boot_samtimeout} sec. after boot"\e[0m"
	if [ "${menuonly}" == "yes" ]; then
		echo -ne "\e[1m" in the main menu"\e[0m"
	else
		echo -ne "\e[1m" whenever controller is not in use"\e[0m"
	fi
	echo -e "\e[1m" and show each game for ${gametimer} sec."\e[0m"
	echo -e "\n\n\n"
	sleep 5
	echo " Please restart your Mister. (Hard Reboot)"

	sam_exit 0
}

function sam_uninstall() { # Uninstall SAM from startup

	echo -n " Uninstallling SAM..."
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

	# there_can_be_only_one
	sed -i '/SuperAttract/d' ${userstartup}
	sync
	sam_exit 0
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
	echo " menu - load to menu"
	echo ""
	echo " arcade, genesis, gba..."
	echo " games from one system only"
	sam_exit 0
}

# ======== UTILITY FUNCTIONS ========
function there_can_be_only_one() { # there_can_be_only_one
	# If another attract process is running kill it
	# This can happen if the script is started multiple times
	echo -n " Stopping other running instances of ${samprocess}..."

	kill_1=$(ps -o pid,args | grep '[M]iSTer_SAM_init start' | awk '{print $1}' | head -1)
	kill_2=$(ps -o pid,args | grep '[M]iSTer_SAM_on.sh start_real' | awk '{print $1}')
	kill_3=$(ps -o pid,args | grep '[M]iSTer_SAM_on.sh bootstart_real' | awk '{print $1}' | head -1)

	[[ ! -z ${kill_1} ]] && kill -9 ${kill_1} >/dev/null
	for kill in ${kill_2}; do
		[[ ! -z ${kill_2} ]] && kill -9 ${kill} >/dev/null
	done
	[[ ! -z ${kill_3} ]] && kill -9 ${kill_3} >/dev/null

	sleep 1

	echo " Done!"
}

function only_survivor() {
	# Kill all SAM processes except for currently running
	ps -ef | grep -i '[s]tart_real' | awk -v me=${sampid} '$1 != me {print $1}' | xargs kill &>/dev/null
	# kill_4=$(ps -ef | grep -i '[M]iSTer_SAM' | awk -v me=${sampid} '$1 != me {print $1}')
	# for kill in ${kill_4}; do
	# 	[[ ! -z ${kill_4} ]] && kill -9 ${kill} &>/dev/null
	# done
}

function sam_stop() {
	# Stop all SAM processes and reboot to menu
	[ ! -z ${samprocess} ] && echo -n " Stopping other running instances of ${samprocess}..."

	kill_1=$(ps -o pid,args | grep '[M]CP' | awk '{print $1}' | head -1)
	kill_2=$(ps -o pid,args | grep '[S]AM' | awk '{print $1}' | head -1)
	kill_3=$(ps -o pid,args | grep '[i]notifywait.*SAM' | awk '{print $1}' | head -1)
	kill_4=$(ps -o pid,args | grep -i '[M]iSTer_SAM' | awk '{print $1}')

	[[ ! -z ${kill_1} ]] && tmux kill-session -t MCP &>/dev/null
	[[ ! -z ${kill_2} ]] && tmux kill-session -t SAM &>/dev/null
	[[ ! -z ${kill_3} ]] && kill -9 ${kill_4} &>/dev/null
	for kill in ${kill_4}; do
		[[ ! -z ${kill_4} ]] && kill -9 ${kill} &>/dev/null
	done
}
function SAM_cleanup() {
	# Clean up by umounting any mount binds
	write_to_TTY_cmd_pipe "exit" &
	[ "$(mount | grep -ic '/media/fat/config')" == "1" ] && umount "/media/fat/config"
	[ -d "${misterpath}/Bootrom" ] && [ "$(mount | grep -ic 'bootrom')" == "1" ] && umount "${misterpath}/Bootrom"
	[ -f "${misterpath}/Games/NES/boot1.rom" ] && [ "$(mount | grep -ic 'nes/boot1.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot1.rom"
	[ -f "${misterpath}/Games/NES/boot2.rom" ] && [ "$(mount | grep -ic 'nes/boot2.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot2.rom"
	[ -f "${misterpath}/Games/NES/boot3.rom" ] && [ "$(mount | grep -ic 'nes/boot3.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot3.rom"
	[ -p ${SAM_cmd_pipe} ] && rm -f ${SAM_cmd_pipe}
	[ -e ${SAM_cmd_pipe} ] && rm -f ${SAM_cmd_pipe}
	if [ "${samquiet}" == "no" ]; then printf '%s\n' "Cleaned up!"; fi
}

function sam_exit() { # args = ${1}(exit_code required) ${2} optional error message
	SAM_cleanup
	if [ ${1} -eq 0 ]; then # just exit
		echo "load_core /media/fat/menu.rbf" >/dev/MiSTer_cmd
		sleep 1
		echo " Done!"
		echo " Thanks for playing!"
	elif [ ${1} -eq 1 ]; then # Error
		echo "load_core /media/fat/menu.rbf" >/dev/MiSTer_cmd
		sleep 1
		echo " Done!"
		echo " There was an error ${2}" # Pass error messages in ${2}
	elif [ ${1} -eq 2 ]; then        # Play Current Game
		sleep 1
	elif [ ${1} -eq 3 ]; then # Play Current Game
		sleep 1
		echo "load_core /tmp/SAM_game.mgl" >/dev/MiSTer_cmd
	fi
	if [ ! -z ${2} ] && [ ${2} == "stop" ]; then
		sam_stop
	else
		ps -ef | grep -i '[M]iSTer_SAM_on.sh' | xargs kill &>/dev/null
	fi
}

function env_check() {
	# Check if we've been installed
	if [ ! -f "${mrsampath}/partun" ] || [ ! -f "${mrsampath}/SuperAttract_MCP" ]; then
		echo " SAM required files not found."
		echo " Surprised? Check your INI."
		sam_update ${1}
		echo " Setup complete."
	fi
}

function deleteall() {
	# In case of issues, reset SAM

	# there_can_be_only_one
	if [ -d "${mrsampath}" ]; then
		echo "Deleting SuperAttract folder"
		rm -rf "${mrsampath}"
	fi
	if [ -f "/media/fat/Scripts/Super Attract Mode.ini" ]; then
		echo "Deleting Super Attract Mode.ini"
		cp /media/fat/Scripts/"Super Attract Mode.ini" /media/fat/Scripts/"Super Attract Mode.ini.bak" &>/dev/null
		rm /media/fat/Scripts/"Super Attract Mode.ini"
	fi
	if [ -f "/media/fat/Scripts/SuperAttract_off.sh" ]; then
		echo "Deleting SuperAttract_off.sh"
		rm /media/fat/Scripts/SuperAttract_off.sh
	fi

	if [ -d "/media/fat/Scripts/SAM_Gamelists" ]; then
		echo "Deleting Gamelist folder"
		rm -rf "/media/fat/Scripts/SAM_Gamelists"
	fi

	if ls /media/fat/Config/inputs/*_input_1234_5678_v3.map 1>/dev/null 2>&1; then
		echo "Deleting Keyboard mapping files"
		rm /media/fat/Config/inputs/*_input_1234_5678_v3.map
	fi
	# Remount root as read-write if read-only so we can remove daemon
	mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
	[ "$RO_ROOT" == "true" ] && mount / -o remount,rw

	# Delete daemon
	echo "Deleting Auto boot Daemon..."
	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
	fi
	echo "Done."

	sed -i '/SuperAttract/d' ${userstartup}
	sed -i '/Super Attract/d' ${userstartup}

	printf "\nAll files deleted except for SuperAttract_on.sh\n"
	if [ ${inmenu} -eq 1 ]; then
		sleep 1
		sam_resetmenu
	else
		printf "\nGamelist reset successful. Please start SAM now.\n"
		sleep 1
		parse_cmd stop
	fi
}

function deletegl() {
	# In case of issues, reset game lists

	# there_can_be_only_one
	if [ -d "${mrsampath}/SAM_Gamelists" ]; then
		echo "Deleting SuperAttract Gamelist folder"
		rm -rf "${mrsampath}/SAM_Gamelists"
	fi

	if [ -d "${mrsampath}/SAM_Count" ]; then
		rm -rf "${mrsampath}/SAM_Count"
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
		sam_exit 0
	fi
}

function creategl() {
	mkdir -p "${mrsampath}/SAM_Gamelists"
	mkdir -p /tmp/.SAM_List
	create_all_gamelists_old="${create_all_gamelists}"
	rebuild_freq_arcade_old="${rebuild_freq_arcade}"
	rebuild_freq_old="${rebuild_freq}"
	create_all_gamelists="Yes"
	rebuild_freq_arcade="Always"
	rebuild_freq="Always"
	create_game_lists
	create_all_gamelists="${create_all_gamelists_old}"
	rebuild_freq_arcade="${rebuild_freq_arcade_old}"
	rebuild_freq="${rebuild_freq_old}"
	if [ ${inmenu} -eq 1 ]; then
		sleep 1
		sam_menu
	else
		echo -e "\nGamelist creation successful. Please start SAM now.\n"
		sleep 1
		sam_exit 0
	fi
}

function skipmessage() {
	# Skip past bios/safety warnings
	sleep 10
	if [ "${samquiet}" == "no" ]; then echo " Skipping BIOS/Safety Warnings!"; fi
	"${mrsampath}/mbc" raw_seq :31
}

function mglfavorite() {
	# Add current game to _Favorites folder

	if [ ! -d "${misterpath}/_Favorites" ]; then
		mkdir -p "${misterpath}/_Favorites"
	fi
	cp /tmp/SAM_game.mgl "${misterpath}/_Favorites/$(cat /tmp/SAM_Game.txt).mgl" &>/dev/null

}

# ======== DOWNLOAD FUNCTIONS ========
function curl_download() { # curl_download ${filepath} ${URL}

	curl \
		--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
		--insecure \
		--fail \
		--location \
		-o "${1}" \
		"${2}"
}

# ======== UPDATER FUNCTIONS ========
function get_samstuff() { #get_samstuff file (path)
	if [ -z "${1}" ]; then
		return 1
	fi

	filepath="${2}"
	if [ -z "${filepath}" ]; then
		filepath="${mrsampath}"
	fi

	echo -n " Downloading from ${repository_url}/blob/${branch}/${1} to ${filepath}/..."
	curl_download "/tmp/${1##*/}" "${repository_url}/blob/${branch}/${1}?raw=true"

	if [ ! "${filepath}" == "/tmp" ]; then
		mv --force "/tmp/${1##*/}" "${filepath}/${1##*/}"
	fi

	if [ "${1##*.}" == "sh" ]; then
		chmod +x "${filepath}/${1##*/}"
	fi

	echo " Done!"
}

function get_partun() {
	REPOSITORY_URL="https://github.com/woelper/partun"
	echo " Downloading partun - needed for unzipping roms from big archives..."
	echo " Created for MiSTer by woelper - Talk to him at this year's PartunCon"
	echo " ${REPOSITORY_URL}"
	latest=$(curl -s -L --insecure https://api.github.com/repos/woelper/partun/releases/latest | jq -r ".assets[] | select(.name | contains(\"armv7\")) | .browser_download_url")
	curl_download "/tmp/partun" "${latest}"
	mv --force "/tmp/partun" "${mrsampath}/partun"
	echo " Done!"
}

function get_mbc() {
	echo " Downloading mbc - Control MiSTer from cmd..."
	echo " Created for MiSTer by pocomane"
	get_samstuff .SuperAttract/mbc
}

function get_inputmap() {
	# Ok, this is messy. Try to download every map file and just disable errors if they don't exist.
	echo -n " Downloading input maps - needed to skip past BIOS for some systems..."
	for i in "${CORE_LAUNCH[@]}"; do
		if [ ! -f /media/fat/Config/inputs/"${CORE_LAUNCH[$i]}"_input_1234_5678_v3.map ]; then
			curl_download "/tmp/${CORE_LAUNCH[$i]}_input_1234_5678_v3.map" "${repository_url}/blob/${branch}/.SuperAttract/inputs/${CORE_LAUNCH[$i]}_input_1234_5678_v3.map?raw=true" &>/dev/null
			mv --force "/tmp/${CORE_LAUNCH[$i]}_input_1234_5678_v3.map" "/media/fat/Config/inputs/${CORE_LAUNCH[$i]}_input_1234_5678_v3.map" &>/dev/null
		fi
	done
	echo " Done!"
}

# ========= SAM START =========
function sam_start_new() {
	env_check ${1}
	if [ ${create_all_gamelists} == "yes" ]; then
		create_game_lists
	fi
	loop_core ${nextcore}
}

function sam_start() {
	if [ -z "$(pidof SuperAttract_init)" ]; then
		"${mrsampath}/SuperAttract_init" "quickstart"
	fi
}

# ========= SAM MONITOR =========
function sam_monitor_new() {
	# We can omit -r here. Tradeoff;
	# window size size is correct, can disconnect with ctrl-C but ctrl-C kills MCP
	# tmux attach-session -t SAM
	# window size will be wrong/too small, but ctrl-c nonfunctional instead of killing/disconnecting
	tmux attach-session -t SAM
}

# ======== SAM OPERATIONAL FUNCTIONS ========
function loop_core() { # loop_core (core)
	echo -e " Starting Super Attract Mode...\n Let Mortal Kombat begin!\n"
	# Reset game log for this session
	echo "" | >/tmp/SAM_Games.log
	start_pipe_readers
	declare -i name_position=0
	declare -i scroll_direction=1
	while [[ -p ${SAM_cmd_pipe} ]]; do
		trap 'counter=0' INT #Break out of loop for skip & next command
		while [ ${counter} -gt 0 ]; do
			echo -ne " Next game in ${counter}...\033[0K\r"
			sleep 1
			((counter--))
			if [ "${ttyenable}" == "yes" ]; then
				if [ ${#tty_currentinfo[name]} -gt 21 ]; then
					if [ ${scroll_direction} -eq 1 ]; then
						if [ ${name_position} -lt ${#tty_currentinfo[name]} ]; then
							((name_position++))
						else
							scroll_direction=0
						fi
					elif [ ${scroll_direction} -eq 0 ]; then
						if [ ${name_position} -gt 0 ]; then
							((name_position--))
						else
							scroll_direction=1
						fi
					fi
				fi
				tty_currentinfo["name_scroll"]="${tty_currentinfo[name]:${name_position}:21}"
				tty_currentinfo["counter"]=$(printf "%03d" ${counter})
				write_to_TTY_cmd_pipe "update_info $(declare -p tty_currentinfo)" &
			fi
		done
		trap - INT
		sleep 1
		name_position=0
		scroll_direction=1
		counter=${gametimer}
		next_core ${nextcore}
	done
}

function reset_core_gl() { # args ${nextcore}
	echo " Deleting old game lists for ${1^^}..."
	rm "${gamelistpath}/${1}_gamelist.txt" &>/dev/null
	sync
}

function speedtest() {
	speedtest=1
	[ ! -d "/tmp/.SAM_tmp/gl" ] && { mkdir -p /tmp/.SAM_tmp/gl; }
	[ ! -d "/tmp/.SAM_tmp/glt" ] && { mkdir -p /tmp/.SAM_tmp/glt; }
	[ "$(mount | grep -ic '${gamelistpath}')" == "0" ] && mount --bind /tmp/.SAM_tmp/gl "${gamelistpath}"
	[ "$(mount | grep -ic '${gamelistpathtmp}')" == "0" ] && mount --bind /tmp/.SAM_tmp/glt "${gamelistpathtmp}"
	START="$(date +%s)"
	for core in ${corelistall}; do
		defaultpath "${core}"
	done
	DURATION_DP=$(($(date +%s) - ${START}))
	START="$(date +%s)"
	echo "" >"${gamelistpathtmp}/Durations.tmp"
	for core in ${corelistall}; do
		local DIR=$(echo $(realpath -s --canonicalize-missing "${CORE_PATH[${core}]}${CORE_PATH_EXTRA[${core}]}"))
		if [ ${core} = " " ] || [ ${core} = "" ] || [ -z ${core} ]; then
			continue
		elif [ ${core} != "arcade" ]; then
			START2="$(date +%s)"
			create_romlist ${core} "${DIR}"
			echo " in $(($(date +%s) - ${START2})) seconds" >>"${gamelistpathtmp}/Durations.tmp"
		elif [ ${core} == "arcade" ]; then
			START2="$(date +%s)"
			build_mralist "${DIR}"
			echo " in $(($(date +%s) - ${START2})) seconds" >>"${gamelistpathtmp}/Durations.tmp"
		fi
	done
	echo "Total: $(($(date +%s) - ${START})) seconds" >>"${gamelistpathtmp}/Durations.tmp"
	if [ -s "${gamelistpathtmp}/Durations.tmp" ]; then
		cat "${gamelistpathtmp}/Durations.tmp" | while IFS=$'\n' read line; do
			echo "${line}"
		done
	fi
	echo "Searching for Default Paths took ${DURATION_DP} seconds"
	[ "$(mount | grep -ic '${gamelistpath}')" == "1" ] && umount "${gamelistpath}"
	[ "$(mount | grep -ic '${gamelistpathtmp}')" == "1" ] && umount "${gamelistpathtmp}"
	speedtest=0
}

function create_game_lists() {
	case ${rebuild_freq} in
	hour)
		rebuild_freq_int=$((3600 * ${regen_duration}))
		;;
	day)
		rebuild_freq_int=$((86400 * ${regen_duration}))
		;;
	week)
		rebuild_freq_int=$((604800 * ${regen_duration}))
		;;
	always)
		rebuild_freq_int=0
		;;
	never)
		rebuild_freq_int=$((3155760000 * ${regen_duration}))
		;;
	*)
		echo "Incorrect regeneration value"
		;;
	esac

	case ${rebuild_freq_arcade} in
	hour)
		rebuild_freq_arcade_int=$((3600 * ${regen_duration_arcade}))
		;;
	day)
		rebuild_freq_arcade_int=$((86400 * ${regen_duration_arcade}))
		;;
	week)
		rebuild_freq_arcade_int=$((604800 * ${regen_duration_arcade}))
		;;
	always)
		rebuild_freq_arcade_int=0
		;;
	never)
		rebuild_freq_arcade_int=$((3155760000 * ${regen_duration_arcade}))
		;;
	*)
		echo "Incorrect regeneration value"
		;;
	esac
	# TODO integrate this later
	# if [ ! -f "${gamelistpath}/${1}_gamelist.txt" ]; then
	#	if [ "${samquiet}" == "no" ]; then echo " Creating game list at ${gamelistpath}/${1}_gamelist.txt"; fi
	# create_romlist ${1} "${2}"
	# fi

	# If folder changed, make new list
	# if [[ ! "$(cat ${gamelistpath}/${1}_gamelist.txt | grep "${2}" | head -1)" ]]; then
	#	if [ "${samquiet}" == "no" ]; then echo " Creating new game list because folder "${DIR}" changed in ini."; fi
	# create_romlist ${1} "${2}"
	# fi

	# Check if zip still exists
	# if [ "$(grep -c ".zip" ${gamelistpath}/${1}_gamelist.txt)" != "0" ]; then
	#	mapfile -t zipsinfile < <(grep ".zip" "${gamelistpath}/${1}_gamelist.txt" | awk -F".zip" '!seen[$1]++' | awk -F".zip" '{print $1}' | sed -e 's/$/.zip/')
	#	for zips in "${zipsinfile[@]}"; do
	#		if [ ! -f "${zips}" ]; then
	#			if [ "${samquiet}" == "no" ]; then echo " Creating new game list because zip file[s] seems to have changed."; fi
	# create_romlist ${1} "${2}"
	#		fi
	#	done
	# fi

	for core in ${corelistall}; do
		corelisttmp=${corelist}
		local DIR=$(echo $(realpath -s --canonicalize-missing "${CORE_PATH[${core}]}${CORE_PATH_EXTRA[${core}]}"))
		local date_file=""
		if [ ${core} != "arcade" ]; then
			if [ -f "${gamelistpath}/${core}_gamelist.txt" ]; then
				if [ -s "${gamelistpath}/${core}_gamelist.txt" ]; then
					date_file=$(stat -c '%Y' "${gamelistpath}/${core}_gamelist.txt")
					if [ $(($(date +%s) - ${date_file})) -gt ${rebuild_freq_int} ]; then
						create_romlist ${core} "${DIR}"
					fi
				else
					corelisttmp=$(echo "$corelist" | awk '{print $0" "}' | sed "s/${core} //" | tr -s ' ')
					rm "${gamelistpath}/${core}_gamelist.txt" &>/dev/null
				fi
				if [ ! -s "${gamelistpathtmp}/${core}_gamelist.txt" ]; then
					cp "${gamelistpath}/${core}_gamelist.txt" "${gamelistpathtmp}/${core}_gamelist.txt" &>/dev/null
				fi
			else
				create_romlist ${core} "${DIR}"
			fi
		elif [ ${core} == "arcade" ]; then
			if [ -f "${mralist}" ]; then
				if [ -s "${mralist}" ]; then
					date_file=$(stat -c '%Y' "${mralist}")
					if [ $(($(date +%s) - ${date_file})) -gt ${rebuild_freq_arcade_int} ]; then
						build_mralist "${DIR}"
					fi
				else
					corelisttmp=$(echo "$corelist" | awk '{print $0" "}' | sed "s/${core} //" | tr -s ' ')
					rm "${mralist}" &>/dev/null
				fi
				if [ ! -s "${mralist_tmp}" ]; then
					cp "${mralist}" "${mralist_tmp}" &>/dev/null
				fi
			else
				build_mralist "${DIR}"
			fi
		fi
		corelist=${corelisttmp}
	done
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

	cat "${tmpfile}" | sort >"${gamelistpath}/${1}_gamelist.txt.tmp"

	# Strip out all duplicate filenames with a fancy awk command
	awk -F'/' '!seen[$NF]++' "${gamelistpath}/${1}_gamelist.txt.tmp" >"${gamelistpath}/${1}_gamelist.txt"
	cp "${gamelistpath}/${1}_gamelist.txt" "${gamelistpathtmp}/${1}_gamelist.txt" &>/dev/null
	rm "${gamelistpath}/${1}_gamelist.txt.tmp" &>/dev/null
	rm "${tmpfile}" &>/dev/null
	rm "${tmpfile2}" &>/dev/null

	total_games=$(echo $(cat "${gamelistpath}/${1}_gamelist.txt" | sed '/^\s*$/d' | wc -l))
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
	if [ ! -f "${gamelistpath}/${1}_gamelist.txt" ]; then
		if [ "${samquiet}" == "no" ]; then echo " Creating game list at ${gamelistpath}/${1}_gamelist.txt"; fi
		create_romlist ${1} "${2}"
	fi

	# If folder changed, make new list
	if [[ ! "$(cat ${gamelistpath}/${1}_gamelist.txt | grep "${2}" | head -1)" ]]; then
		if [ "${samquiet}" == "no" ]; then echo " Creating new game list because folder "${DIR}" changed in ini."; fi
		create_romlist ${1} "${2}"
	fi

	# Check if zip still exists
	if [ "$(grep -c ".zip" ${gamelistpath}/${1}_gamelist.txt)" != "0" ]; then
		mapfile -t zipsinfile < <(grep ".zip" "${gamelistpath}/${1}_gamelist.txt" | awk -F".zip" '!seen[$1]++' | awk -F".zip" '{print $1}' | sed -e 's/$/.zip/')
		for zips in "${zipsinfile[@]}"; do
			if [ ! -f "${zips}" ]; then
				if [ "${samquiet}" == "no" ]; then echo " Creating new game list because zip file[s] seems to have changed."; fi
				create_romlist ${1} "${2}"
			fi
		done
	fi

	# If gamelist is not in /tmp dir, let's put it there
	if [ -s "${gamelistpathtmp}/${1}_gamelist.txt" ]; then

		# Pick the actual game
		rompath="$(cat ${gamelistpathtmp}/${1}_gamelist.txt | shuf --head-count=1)"
	else

		# Repopulate list
		if [ -f "${gamelistpath}/${1}_gamelist_exclude.txt" ]; then
			if [ "${samquiet}" == "no" ]; then echo -n " Exclusion list found. Excluding games now..."; fi
			comm -13 <(sort <"${gamelistpath}/${1}_gamelist_exclude.txt") <(sort <"${gamelistpath}/${1}_gamelist.txt") >${tmpfile}
			awk -F'/' '!seen[$NF]++' ${tmpfile} >"${gamelistpathtmp}/${1}_gamelist.txt"
			if [ "${samquiet}" == "no" ]; then echo "Done."; fi
			rompath="$(cat ${gamelistpathtmp}/${1}_gamelist.txt | shuf --head-count=1)"
		else
			awk -F'/' '!seen[$NF]++' "${gamelistpath}/${1}_gamelist.txt" >"${gamelistpathtmp}/${1}_gamelist.txt"
			# cp "${gamelistpath}/${1}_gamelist.txt" "${gamelistpathtmp}/${1}_gamelist.txt" &>/dev/null
			rompath="$(cat ${gamelistpathtmp}/${1}_gamelist.txt | shuf --head-count=1)"
		fi
	fi

	# Make sure file exists since we're reading from a static list
	if [[ ! "${rompath,,}" == *.zip* ]]; then
		if [ ! -f "${rompath}" ]; then
			if [ "${samquiet}" == "no" ]; then echo " Creating new game list because file not found."; fi
			create_romlist ${1} "${2}"
		fi
	fi

	# Delete played game from list
	if [ "${samquiet}" == "no" ]; then echo " Selected file: ${rompath}"; fi
	if [ "${norepeat}" == "yes" ]; then
		awk -vLine="$rompath" '!index($0,Line)' "${gamelistpathtmp}/${1}_gamelist.txt" >${tmpfile} && mv ${tmpfile} "${gamelistpathtmp}/${1}_gamelist.txt"
	fi
}

# This function will pick a random rom from the game list.
function next_core() { # next_core (core)
	if [ -z "$(echo ${corelist} | sed 's/ //g')" ]; then
		if [ -s "${corelisttmpfile}" ]; then
			corelist="$(cat ${corelisttmpfile})"
		else
			echo " ERROR: FATAL - List of cores is empty. Nothing to do!"
			sam_exit 1 " ERROR: FATAL - List of cores is empty. Nothing to do!"
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
	if [ "${countdown}" != "countdown" ]; then
		# Set $nextcore from $corelist
		nextcore="$(echo ${corelist} | xargs shuf --head-count=1 --echo)"
		wc=$(echo "$corelisttmpfile" | awk '{print NF}')
		if [ $wc -gt 1 ] && [ "${1}" == "${nextcore}" ]; then
			next_core ${nextcore}
			return
		else
			corelist=$(echo ${corelist} | awk '{print $0" "}' | sed "s/${nextcore} //" | tr -s ' ')
		fi
	fi
	if [ "${samquiet}" == "no" ]; then echo -e " Selected core: \e[1m${nextcore^^}\e[0m"; fi
	if [ "${nextcore}" == "arcade" ]; then
		# If this is an arcade core we go to special code
		load_core_arcade
		return
	fi
	local DIR=$(echo $(realpath -s --canonicalize-missing "${CORE_PATH[${nextcore}]}${CORE_PATH_EXTRA[${nextcore}]}"))
	check_list ${nextcore} "${DIR}"
	romname=$(basename "${rompath}")

	# Sanity check that we have a valid rom in var
	extension="${rompath##*.}"
	extlist=$(echo "${CORE_EXT[${nextcore}]}" | sed -e "s/,/ /g")
	if [ ! $(echo "${extlist}" | grep -i -w -q "${extension}" | echo $?) ]; then
		if [ "${samquiet}" == "no" ]; then echo -e " Wrong Extension! \e[1m${extension^^}\e[0m"; fi
		next_core ${nextcore}
		return
	else
		if [ "${samquiet}" == "no" ]; then echo -e " Correct Extension! \e[1m${extension^^}\e[0m"; fi
	fi

	# If there is an exclude list check it
	declare -n excludelist="${nextcore}exclude"
	if [ ${#excludelist[@]} -gt 0 ]; then
		for excluded in "${excludelist[@]}"; do
			if [ "${romname}" == "${excluded}" ]; then
				echo " ${romname} is excluded - SKIPPED"
				awk -vLine="${romname}" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} && mv ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
				next_core ${nextcore}
				return
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
	echo "$(date +%H:%M:%S) - ${1} - ${3}" $(if [ ${1} == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then echo "(${GAMENAME})"; fi) >>/tmp/SAM_Games.log
	echo "${3} (${1}) "$(if [ ${1} == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then echo "(${GAMENAME})"; fi) >/tmp/SAM_Game.txt
	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			["core_pretty"]="${CORE_PRETTY[${1}]}"
			["name"]="${GAMENAME}"
			["name_scroll"]="${GAMENAME:0:21}"
			["core"]="${CORE_LAUNCH[${1}]}"
			["counter"]=${gametimer}
		)
		write_to_TTY_cmd_pipe "display_info $(declare -p tty_currentinfo)" &
	fi

	if [ "${4}" == "countdown" ]; then
		for i in {5..1}; do
			echo -ne " Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi

	# Create mgl file and launch game
	if [ -s /tmp/SAM_game.mgl ]; then
		mv /tmp/SAM_game.mgl /tmp/SAM_game.previous.mgl
	fi

	mute "${CORE_LAUNCH[${nextcore}]}"

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
		skipmessage &
	fi
}

function mute() {
	if [ "${mute}" == "yes" ]; then
		# Mute Global Volume
		echo -e "\0020\c" >/media/fat/config/Volume.dat
	elif [ "${mute}" == "core" ]; then
		# UnMute Global Volume
		echo -e "\0000\c" >/media/fat/config/Volume.dat
		# Mute Core Volumes
		echo -e "\0006\c" >"/media/fat/config/${1}_volume.cfg"
	elif [ "${mute}" == "no" ]; then
		# UnMute Global Volume
		echo -e "\0000\c" >/media/fat/config/Volume.dat
		# UnMute Core Volumes
		echo -e "\0000\c" >"/media/fat/config/${1}_volume.cfg"
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
		next_core ${1}
	fi
}

function disable_bootrom() {
	if [ "${disablebootrom}" == "Yes" ]; then
		# Make Bootrom folder inaccessible until restart
		[ -d "${misterpath}/Bootrom" ] && [ "$(mount | grep -ic 'bootrom')" == "0" ] && mount --bind /mnt "${misterpath}/Bootrom"
		# Disable Nes bootroms except for FDS Bios (boot0.rom)
		[ -f "${misterpath}/Games/NES/boot1.rom" ] && [ "$(mount | grep -ic 'nes/boot1.rom')" == "0" ] && touch /tmp/.SAM_tmp/brfake && mount --bind /tmp/.SAM_tmp/brfake "${misterpath}/Games/NES/boot1.rom"
		[ -f "${misterpath}/Games/NES/boot2.rom" ] && [ "$(mount | grep -ic 'nes/boot2.rom')" == "0" ] && touch /tmp/.SAM_tmp/brfake && mount --bind /tmp/.SAM_tmp/brfake "${misterpath}/Games/NES/boot2.rom"
		[ -f "${misterpath}/Games/NES/boot3.rom" ] && [ "$(mount | grep -ic 'nes/boot3.rom')" == "0" ] && touch /tmp/.SAM_tmp/brfake && mount --bind /tmp/.SAM_tmp/brfake "${misterpath}/Games/NES/boot3.rom"
	fi
}

function play_or_exit() {
	if [ "${playcurrentgame}" == "yes" ] && ([ ${mute} == "yes" ] || [ ${mute} == "core" ]); then
		write_to_SAM_cmd_pipe "exit 2"
	elif [ "${playcurrentgame}" == "yes" ] && [ ${mute} == "no" ]; then
		write_to_SAM_cmd_pipe "exit 3"
	else
		write_to_SAM_cmd_pipe "exit 0"
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
		build_mralist "${DIR}"
	fi

	if [ ! -s "${mralist_tmp}" ]; then
		cp "${mralist}" "${mralist_tmp}" &>/dev/null
	fi

	# Get a random game from the list
	mra="$(shuf --head-count=1 ${mralist_tmp})"
	MRAPATH="$(echo $(realpath -s --canonicalize-missing "${DIR}/${mra}"))"

	# If the mra variable is valid this is skipped, but if not we try 10 times
	# Partially protects against typos from manual editing and strange character parsing problems
	for i in {1..10}; do
		if [ ! -f "${MRAPATH}" ]; then
			mra=$(shuf --head-count=1 ${mralist_tmp})
			MRAPATH="$(echo $(realpath -s --canonicalize-missing "${DIR}/${mra}"))"
		fi
	done

	# If the MRA is still not valid something is wrong - suicide
	if [ ! -f "${MRAPATH}" ]; then
		echo " There is no valid file at ${MRAPATH}!"
		return
	fi

	if [ "${samquiet}" == "no" ]; then echo " Selected file: ${MRAPATH}"; fi

	# Delete mra from list so it doesn't repeat
	if [ "${norepeat}" == "yes" ]; then
		awk -vLine="$mra" '!index($0,Line)' "${mralist_tmp}" >${tmpfile} && mv ${tmpfile} "${mralist_tmp}"
	fi

	mraname=$(echo $(basename "${mra}") | sed -e 's/\.[^.]*$//')
	echo -n " Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore}]}\e[0m: "
	echo -e "\e[1m${mraname}\e[0m"
	echo "$(date +%H:%M:%S) - Arcade - ${mraname}" >>/tmp/SAM_Games.log
	echo "${mraname} (${nextcore})" >/tmp/SAM_Game.txt

	# Get Setname from MRA needed for tty2oled, thx to RealLarry
	mrasetname=$(grep "<setname>" "${MRAPATH}" | sed -e 's/<setname>//' -e 's/<\/setname>//' | tr -cd '[:alnum:]')
	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			["core_pretty"]="${CORE_PRETTY[${nextcore}]}"
			["name"]="${mraname}"
			["name_scroll"]="${mraname:0:21}"
			["core"]="${mrasetname}"
			["counter"]=${gametimer}
		)
		write_to_TTY_cmd_pipe "display_info $(declare -p tty_currentinfo)" &
	fi

	mute "${mrasetname}"

	if [ "${1}" == "countdown" ]; then
		for i in {5..1}; do
			echo " Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi

	# Tell MiSTer to load the next MRA
	echo "load_core ${MRAPATH}" >/dev/MiSTer_cmd
	sleep 1
}

# ========= MAIN =========
function main() {
	process_cmd ${@}
	startup_tasks
	if [ "${samtrace}" == "yes" ]; then
		debug_output
	fi
	parse_cmd ${@} # Parse command line parameters for input
}

if [ "${1,,}" == "--source-only" ]; then
	source-only
else
	main ${@}
fi
