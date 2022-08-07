#!/bin/bash

# https://github.com/mrchrisster/MiSTer_SAM/
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
# mbc by pocomane
# partun by woelper
# samindex by wizzo
# tty2oled by venice
#
# Thanks for the contributions and support:
# kaloun34, redsteakraw, RetroDriven, LamerDeluxe, InquisitiveCoder, Sigismond

trap 'rc=$?;[ ${rc} = 0 ] && exit;SAM_cleanup' EXIT TERM

# ======== GLOBAL VARIABLES =========
declare -g misterpath="/media/fat"
declare -g misterscripts="${misterpath}/Scripts"
declare -g mrsampath="${misterscripts}/.SuperAttract"
source ${mrsampath}/SuperAttractSystem.ini

# ======== REDEFINE SOME FUNCTIONS =========
function init_default_paths() {
	[[ -s ${mrsamtmp}/default_paths ]] && source ${mrsamtmp}/default_paths
}

function init_amigashared_path() {
	[[ -s ${mrsamtmp}/amigashared_path ]] && source ${mrsamtmp}/amigashared_path
	samquiet " Amigashared directory is ${amigashared} "
}

function init_vars() {
	# ======== LOCAL VARIABLES ========
	declare -gi inmenu=0
	declare -gi coreretries=3
	declare -gi romloadfails=0
	declare -g corelist_allowtmp=""
	declare -gi gametimer=120
	declare -gl skipmessage="Yes"
	declare -gl usezip="Yes"
	declare -gl norepeat="Yes"
	declare -gl playcurrentgame="No"
	declare -gi counter=0
	declare -gi countdown="nocountdown"
	declare -g file_to_load=""
}

function sam_prep() {
	[[ -d "${mrsamtmp}/SAM_config" ]] && [[ $(mount | grep -ic "${misterpath}/config") == "0" ]] && cp -pr --force "${misterpath}/config" ${mrsamtmp}/SAM_config && mount --bind "${mrsamtmp}/SAM_config/config" "${misterpath}/config"
	# [[ ! -d "${mrsamtmp}/Amiga_shared" ]] && mkdir -p "${mrsamtmp}/Amiga_shared"
	# [[ -d "${mrsamtmp}/Amiga_shared" ]] && [[ $(mount | grep -ic "${amigashared}") == "0" ]] && cp -pr --force ${amigashared}/Disk.info ${mrsamtmp}/Amiga_shared &>/dev/null && cp -pr --force ${amigashared}//minimig_vadjust.dat ${mrsamtmp}/Amiga_shared &>/dev/null && mount --bind "${mrsamtmp}/Amiga_shared" "${amigashared}"
	# Disable Bootrom - Make Bootrom folder inaccessible until restart
	if [ "${disablebootrom}" == "yes" ]; then
		[[ -d "${misterpath}/Bootrom" ]] && [[ $(mount | grep -ic 'bootrom') == "0" ]] && mount --bind /mnt "${misterpath}/Bootrom"
		# Disable Nes bootroms except for FDS Bios (boot0.rom)
		[[ -f "${CORE_PATH_FINAL[NES]}/boot1.rom" ]] && [[ $(mount | grep -ic 'nes/boot1.rom') == "0" ]] && touch ${mrsamtmp}/brfake && mount --bind ${mrsamtmp}/brfake "${CORE_PATH_FINAL[NES]}/boot1.rom"
		[[ -f "${CORE_PATH_FINAL[NES]}/boot2.rom" ]] && [[ $(mount | grep -ic 'nes/boot2.rom') == "0" ]] && touch ${mrsamtmp}/brfake && mount --bind ${mrsamtmp}/brfake "${CORE_PATH_FINAL[NES]}/boot2.rom"
		[[ -f "${CORE_PATH_FINAL[NES]}/boot3.rom" ]] && [[ $(mount | grep -ic 'nes/boot3.rom') == "0" ]] && touch ${mrsamtmp}/brfake && mount --bind ${mrsamtmp}/brfake "${CORE_PATH_FINAL[NES]}/boot3.rom"
	fi
}

function SAM_cleanup() {
	# Clean up by umounting any mount binds
	[[ $(mount | grep -ic "${misterpath}/config") -eq 1 ]] && umount "${misterpath}/config"
	# [[ $(mount | grep -ic ${amigashared}) != "0" ]] && umount "${amigashared}"
	[[ -d "${misterpath}/Bootrom" ]] && [[ $(mount | grep -ic 'bootrom') != "0" ]] && umount "${misterpath}/Bootrom"
	[[ -f "${CORE_PATH_FINAL[NES]}/boot1.rom" ]] && [[ $(mount | grep -ic 'nes/boot1.rom') != "0" ]] && umount "${CORE_PATH_FINAL[NES]}/boot1.rom"
	[[ -f "${CORE_PATH_FINAL[NES]}/boot2.rom" ]] && [[ $(mount | grep -ic 'nes/boot2.rom') != "0" ]] && umount "${CORE_PATH_FINAL[NES]}/boot2.rom"
	[[ -f "${CORE_PATH_FINAL[NES]}/boot3.rom" ]] && [[ $(mount | grep -ic 'nes/boot3.rom') != "0" ]] && umount "${CORE_PATH_FINAL[NES]}/boot3.rom"
	[[ -p ${SAM_Activity_pipe} ]] && rm -f ${SAM_Activity_pipe}
	[[ -e ${SAM_Activity_pipe} ]] && rm -f ${SAM_Activity_pipe}
	[[ -p ${SAM_cmd_pipe} ]] && rm -f ${SAM_cmd_pipe}
	[[ -e ${SAM_cmd_pipe} ]] && rm -f ${SAM_cmd_pipe}
	samquiet " Cleaned up mounts."
}

# ======== CORE CONFIG ========
function init_data() {
	# Core to long name mappings
	declare -gA CORE_PRETTY=(
		["amiga"]="Commodore Amiga"
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
		["snes"]="Super NES"
		["tgfx16"]="NEC TurboGrafx-16 "
		["tgfx16cd"]="NEC TurboGrafx-16 CD"
		["psx"]="Sony Playstation"
	)

	# Core to file extension mappings
	declare -glA CORE_EXT=(
		["amiga"]="hdf" #This is just a placeholder
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

	# Core to path mappings
	declare -gA CORE_PATH_FINAL=(
		["amiga"]="${amigapath}${amigapathextra}"
		["arcade"]="${arcadepath}${arcadepathextra}"
		["atari2600"]="${atari2600path}${atari2600pathextra}"
		["atari5200"]="${atari5200path}${atari5200pathextra}"
		["atari7800"]="${atari7800path}${atari7800pathextra}"
		["atarilynx"]="${atarilynxpath}${atarilynxpathextra}"
		["c64"]="${c64path}${c64pathextra}"
		["fds"]="${fdspath}${fdspathextra}"
		["gb"]="${gbpath}${gbpathextra}"
		["gbc"]="${gbcpath}${gbcpathextra}"
		["gba"]="${gbapath}${gbapathextra}"
		["genesis"]="${genesispath}${genesispathextra}"
		["gg"]="${ggpath}${ggpathextra}"
		["megacd"]="${megacdpath}${megacdpathextra}"
		["neogeo"]="${neogeopath}${neogeopathextra}"
		["nes"]="${nespath}${nespathextra}"
		["s32x"]="${s32xpath}${s32xpathextra}"
		["sms"]="${smspath}${smspathextra}"
		["snes"]="${snespath}${snespathextra}"
		["tgfx16"]="${tgfx16path}${tgfx16pathextra}"
		["tgfx16cd"]="${tgfx16cdpath}${tgfx16cdpathextra}"
		["psx"]="${psxpath}${psxpathextra}"
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
		["amiga"]="Yes"
		["arcade"]="No"
		["atari2600"]="No"
		["atari5200"]="Yes"
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

	declare -gA ATARI5200_GAME_SKIP=(
		["A.E."]=L
		["Activision Decathlon"]=L
		["Astro Chase"]=R
		["Atari PAM Diagnostics"]=R
		["Battlezone"]=R
		["Beamrider"]=L
		["BerZerk"]=L
		["Blaster"]=L
		["Blue Print"]=L
		["Bounty Bob Strikes Back"]=R
		["Buck Rogers - Planet of Zoom"]=R
		["Centipede"]=R
		["Choplifter!"]=L
		["Congo Bongo"]=R
		["Countermeasure"]=R
		["Defender"]=R
		["Dig Dug"]=R
		["Final Legacy"]=L
		["Frisky Tom"]=R
		["Frogger II"]=R
		["Gyruss"]=R
		["H.E.R.O."]=L
		["James Bond"]=R
		["Joust"]=R
		["Jr Pac-Man"]=R
		["Jungle Hunt"]=R
		["Kangaroo"]=R
		["Last Star Fighter"]=L
		["Last StarFighter"]=L
		["Looney Tunes Hotel"]=R
		["Meteorites"]=L
		["Microgammon SB"]=R
		["Millipede"]=L
		["Miner 2049er"]=L
		["Miniature Golf"]=R
		["Montezuma's Revenge"]=R
		["Moon Patrol"]=L
		["Ms. Pac-Man"]=R
		["Pac-Man"]=R
		["Pitfall II"]=L
		["Pole Position"]=R
		["Popeye"]=R
		["Qix"]=R
		["Quest for Quintana Roo"]=L
		["Realsports Basketball"]=R
		["Realsports Football"]=R
		["Realsports Soccer"]=R
		["Realsports Tennis"]=R
		["Road Runner"]=R
		["Robotron"]=L
		["Space Dungeon"]=R
		["Space Shuttle"]=L
		["Sport Goofy"]=R
		["Sports Goofy"]=R
		["Star Raiders"]=R
		["Star Trek SOS"]=R
		["Star Trek - Strategic Operations Simulator"]=R
		["Star Wars The Arcade Game"]=R
		["Star Wars - The Arcade Game"]=R
		["Stargate"]=R
		["Super Pac-Man"]=L
		["Tempest"]=L
		["Track & Field"]=L
		["Track and Field"]=L
		["Wizard of Wor"]=L
		["Xari Arena"]=R
		["Zone Ranger"]=L
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

	# TTY2OLED Core Pic mappings
	declare -gA TTY2OLED_PIC_NAME=(
		["amiga"]="Minimig"
		["arcade"]="Arcade"
		["atari2600"]="ATARI2600"
		["atari5200"]="ATARI5200"
		["atari7800"]="ATARI7800"
		["atarilynx"]="AtariLynx"
		["c64"]="C64"
		["fds"]="fds"
		["gb"]="GAMEBOY"
		["gbc"]="GAMEBOY"
		["gba"]="GBA"
		["genesis"]="Genesis"
		["gg"]="gamegear"
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

function start_pipe_readers() {
	[[ -p ${SAM_Activity_pipe} ]] && rm -f ${SAM_Activity_pipe}
	[[ -e ${SAM_Activity_pipe} ]] && rm -f ${SAM_Activity_pipe}
	[[ -p ${SAM_cmd_pipe} ]] && rm -f ${SAM_cmd_pipe}
	[[ -e ${SAM_cmd_pipe} ]] && rm -f ${SAM_cmd_pipe}

	if [[ ! -p ${SAM_Activity_pipe} ]]; then
		mkfifo ${SAM_Activity_pipe}
	fi

	if [[ ! -p ${SAM_cmd_pipe} ]]; then
		mkfifo ${SAM_cmd_pipe}
	fi

	while true; do
		if [[ -p ${SAM_cmd_pipe} ]]; then
			if read line <${SAM_cmd_pipe}; then
				set -- junk ${line}
				shift
				case "${1}" in
				exit)
					if [ ! -z "${2}" ]; then
						sam_exit ${2}
					else
						sam_exit 0
					fi
					break
					;;
				skip | next)
					tmux send-keys -t SAM C-c ENTER
					;;
				ban | exclude)
					exclude_game
					;;
				fakegameslog)
					fakegameslog
					;;
				samdebug | debug)
					shift
					samdebug_toggle "${1-}"
					;;
				samquiet | quiet)
					shift
					samquiet_toggle "${1-}"
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
		if read line <${SAM_Activity_pipe}; then
			samquiet " Activity detected! (${line})"
			samdebug " $(date '+%m-%d-%Y_%H:%M:%S')"
			play_or_exit
		fi
		sleep 0.5
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
	echo " corelist: ${corelist_allow}"
	echo " usezip: ${usezip}"

	echo " listenmouse: ${listenmouse}"
	echo " listenkeyboard: ${listenkeyboard}"
	echo " listenjoy: ${listenjoy}"
	echo ""
	echo " arcadepath: ${CORE_PATH_FINAL[arcade]}"
	echo " gbapath: ${CORE_PATH_FINAL[gba]}"
	echo " genesispath: ${CORE_PATH_FINAL[genesis]}"
	echo " megacdpath: ${CORE_PATH_FINAL[megacd]}"
	echo " neogeopath: ${CORE_PATH_FINAL[neogeo]}"
	echo " nespath: ${CORE_PATH_FINAL[nes]}"
	echo " snespath: ${CORE_PATH_FINAL[snes]}"
	echo " tgfx16path: ${CORE_PATH_FINAL[tgfx16]}"
	echo " tgfx16cdpath: ${CORE_PATH_FINAL[tgfx16cd]}"
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

# ======== SAM MENU ========
function sam_premenu() {
	echo "+---------------------------+"
	echo "| MiSTer Super Attract Mode |"
	echo "+---------------------------+"
	echo " SAM Configuration:"
	if [[ $(grep -ic "attract" ${userstartup}) != "0" ]]; then
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
	[[ -f "/tmp/Super_Attract_Mode.sh" ]] && rm -f "/tmp/Super_Attract_Mode.sh"
	[[ -f "/tmp/Super_Attract_Mode.ini" ]] && rm -f "/tmp/Super_Attract_Mode.ini"
	[[ -f "/tmp/samindex.zip" ]] && rm -f "/tmp/samindex.zip"
	
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
	main ${premenu}
}

function sam_menu() {
	inmenu=1
	dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Exit" \
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
		BGM "Background Music Player" \
		Config "Configure INI Settings" \
		Favorite "Copy current game to _Favorites folder" \
		Gamelists "Game Lists - Create or Delete" \
		Reset "Reset or uninstall SAM" \
		Autoplay "Autoplay Configuration" 2>"/tmp/.SAMmenu"

	opt=$?
	menuresponse=$(<"/tmp/.SAMmenu")
	clear

	if [ "${opt}" != "0" ]; then
		exit
	else
		main ${menuresponse}
	fi

}

function sam_singlemenu() {
	declare -a menulist=()
	for core in ${corelistall}; do
		menulist+=("${core^^}")
		menulist+=("${CORE_PRETTY[${core}]} games only")
	done

	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ Single System Select ]" \
		--menu "Which system?" 0 0 0 \
		"${menulist[@]}" 2>"/tmp/.SAMmenu"
	opt=$?
	menuresponse=$(<"/tmp/.SAMmenu")
	clear

	if [ "${opt}" != "0" ]; then
		sam_menu
	else
		main ${menuresponse}
	fi

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

	samquiet " menuresponse: ${menuresponse}"
	main ${menuresponse}
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

	samquiet " menuresponse: ${menuresponse}"
	main ${menuresponse}
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
	samquiet " menuresponse: ${menuresponse}"
	main ${menuresponse}
}

function sam_configmenu() {
	dialog --clear --ascii-lines --no-cancel \
		--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
		--msgbox "Here you can configure the INI settings for SAM.\n\nUse TAB to switch between editing, the OK and Cancel buttons." 0 0

	dialog --clear --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
		--editbox "${misterscripts}/Super_Attract_Mode.ini" 0 0 2>"/tmp/.SAMmenu"

	if [ -s "/tmp/.SAMmenu" ] && [ $(diff -wq "/tmp/.SAMmenu" "${misterscripts}/Super_Attract_Mode.ini") ]; then
		cp -f "/tmp/.SAMmenu" "${misterscripts}/Super_Attract_Mode.ini"
		dialog --clear --ascii-lines --no-cancel \
			--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
			--msgbox "Changes saved!" 0 0
	fi

	main menu
}

function sam_gamemodemenu() {
	dialog --clear --no-cancel --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ GAME ROULETTE ]" \
		--msgbox "In Game Roulette mode SAM selects games for you. \n\nYou have a pre-defined amount of time to play this game, then SAM will move on to play the next game. \n\nPlease do a cold reboot when done playing." 0 0
	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ GAME ROULETTE ]" \
		--menu "Select an option" 0 0 0 \
		Roulette2 "Play a random game for 2 minutes. " \
		Roulette5 "Play a random game for 5 minutes. " \
		Roulette10 "Play a random game for 10 minutes. " \
		Roulette15 "Play a random game for 15 minutes. " \
		Roulette20 "Play a random game for 20 minutes. " \
		Roulette25 "Play a random game for 25 minutes. " \
		Roulette30 "Play a random game for 30 minutes. " \
		Roulettetimer "Play a random game for ${roulettetimer} secs (roulettetimer in Super_Attract_Mode.ini). " 2>"/tmp/.SAMmenu"

	opt=$?
	menuresponse=$(<"/tmp/.SAMmenu")

	if [ "${opt}" != "0" ]; then
		sam_menu
	elif [ "${menuresponse}" == "Roulettetimer" ]; then
		gametimer=${roulettetimer}
		only_survivor
		SAM_cleanup
		tty_init
		checkgl
		mute=no
		listenmouse="No"
		listenkeyboard="No"
		listenjoy="No"
		loop_core
	else
		timemin=${menuresponse//Roulette/}
		gametimer=$((timemin * 60))
		only_survivor
		SAM_cleanup
		tty_init
		checkgl
		mute=no
		listenmouse="No"
		listenkeyboard="No"
		listenjoy="No"
		loop_core
	fi
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

	if [ "${opt}" != "0" ]; then
		sam_menu
	else
		echo "Please wait... getting things ready."
		declare -a corelist_allow=()
		declare -a gamelists=()
		categ="${menuresponse}"
		# echo "${menuresponse}"
		# Delete all temporary Game lists
		if compgen -G "${gamelistpathtmp}/*_gamelist.txt" &>/dev/null; then
			rm ${gamelistpathtmp}/*_gamelist.txt
		fi
		gamelists=($(find "${gamelistpath}" -name "*_gamelist.txt"))

		# echo ${gamelists[@]}
		for list in ${gamelists[@]}; do
			listfile=$(basename "${list}")
			# awk -v category="${categ}" 'tolower($0) ~ category' "${list}" > "${gamelistpathtmp}/${listfile}"
			grep -i "${categ}" "${list}" >"${tmpfile}"
			awk -F'/' '!seen[$NF]++' "${tmpfile}" >"${gamelistpathtmp}/${listfile}"
			[[ -s "${gamelistpathtmp}/${listfile}" ]] || rm "${gamelistpathtmp}/${listfile}"
		done

		corelist_allow=$(find "${gamelistpathtmp}" -name "*_gamelist.txt" -exec basename \{} \; | cut -d '_' -f 1)

		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super_Attract_Mode" --title "[ CATEGORY SELECTION ]" \
			--msgbox "SAM will start now and only play games from the '${categ^^}' category.\n\nOn cold reboot, SAM will get reset automatically to play all games again. " 0 0
		only_survivor
		sam_prep
		tty_init
		checkgl
		loop_core
	fi

}

function samedit_excltags() {
	excludetags="${gamelistpath}/.excludetags"

	function process_tag() {
		for core in ${corelist_allow}; do
			[[ -f "${gamelistpathtmp}/${core}_gamelist.txt" ]] && rm "${gamelistpathtmp}/${core}_gamelist.txt"
			if [ -s "${gamelistpath}/${core}_gamelist.txt" ]; then
				grep -i "${categ}" "${gamelistpath}/${core}_gamelist.txt" >>"${gamelistpath}/${core}_gamelist_exclude.txt"
			else
				grep -i "${categ}" "${gamelistpath}/${core}_gamelist.txt" >"${gamelistpath}/${core}_gamelist_exclude.txt"
			fi
		done
	}

	if [ -f "${excludetags}" ]; then
		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super Attract Mode" --title "[ EXCLUDE CATEGORY SELECTION ]" \
			--msgbox "Currently excluded tags: \n\n$(cat "${excludetags}")" 0 0
	else
		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super Attract Mode" --title "[ EXCLUDE CATEGORY SELECTION ]" \
			--msgbox "Exclude hacks, prototypes, homebrew or other game categories you don't want SAM to show.\n\n" 0 0
	fi

	dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Done" \
		--backtitle "Super Attract Mode" --title "[ EXCLUDE CATEGORY SELECTION ]" \
		--menu "Which tags do you want to exclude?" 0 0 0 \
		Beta "Beta Games" \
		Hack "Hacks" \
		Homebrew "Homebrew" \
		Prototype "Prototypes" \
		Unlicensed "Unlicensed Games" \
		Translations "Translated Games" \
		USA "USA" \
		Japan "Japan" \
		Europe "Europe" \
		'' "Reset Exclusion Lists" 2>"/tmp/.SAMmenu"

	opt=$?
	menuresponse=$(<"/tmp/.SAMmenu")

	categ="${menuresponse}"

	if [ "${opt}" != "0" ]; then
		sam_menu
	else
		echo " Please wait... creating exclusion lists."
		if [ -z ${categ} ]; then
			if [ ! -s "${excludetags}" ]; then
				echo "${categ} " >"${excludetags}"
				process_tag
			else
				# Check if tag is already excluded
				if [ $(grep -i "${categ}" "${excludetags}") -gt 0 ]; then
					dialog --clear --no-cancel --ascii-lines \
						--backtitle "Super Attract Mode" --title "[ EXCLUDE CATEGORY SELECTION ]" \
						--msgbox "${categ} has already been excluded. \n\n" 0 0
				else
					echo "${categ} " >>"${excludetags}"
					# TO DO: What if we don't have gamelists
					process_tag
				fi
			fi
		else
			for core in ${corelist_allow}; do
				rm "${gamelistpath}/${core}_gamelist_exclude.txt" 2>/dev/null
				rm "${excludetags}" 2>/dev/null
			done
			dialog --clear --no-cancel --ascii-lines \
				--backtitle "Super Attract Mode" --title "[ EXCLUDE CATEGORY SELECTION ]" \
				--msgbox "All exclusion filters have been removed. \n\n" 0 0
			sam_menu
		fi
		find "${gamelistpath}" -name "*_gamelist_exclude.txt" -size 0 -print0 | xargs -0 rm
		samedit_excltags
	fi

}

function sam_bgmmenu() {
	dialog --clear --no-cancel --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ BACKGROUND MUSIC ENABLER ]" \
		--msgbox "While SAM is shuffling games, play some music.\n\nThis installs wizzomafizzo's BGM script to play Background music in SAM.\n\nWe'll drop one playlist in the music folder (80s.pls) as a default playlist. You can customize this later or to your liking by dropping mp3's or pls files in ${misterpath}/music folder." 0 0
	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ BACKGROUND MUSIC ENABLER ]" \
		--menu "Select from the following options?" 0 0 0 \
		Enablebgm "Enable BGM for SAM" \
		Disablebgm "Disable BGM for SAM" 2>"/tmp/.SAMmenu"

	opt=$?
	menuresponse=$(<"/tmp/.SAMmenu")

	if [ "${opt}" != "0" ]; then
		sam_menu
	else
		if [[ "${menuresponse,,}" == "enablebgm" ]]; then
			if [ ! -f "${misterscripts}/bgm.sh" ]; then
				echo " Installing BGM to Scripts folder"
				repository_url="https://github.com/wizzomafizzo/MiSTer_BGM"
				branch="main"
				get_samstuff bgm.sh /tmp
				mv --force /tmp/bgm.sh ${misterscripts}/
			else
				echo " BGM script is installed already. Updating just in case..."
				${misterscripts}/bgm.sh stop &>/dev/null
				repository_url="https://github.com/wizzomafizzo/MiSTer_BGM"
				branch="main"
				get_samstuff bgm.sh /tmp
				mv --force /tmp/bgm.sh ${misterscripts}/
				echo " Resetting BGM now."
			fi
			echo " Updating Super_Attract_Mode.ini to use Mute=Core"
			sed -i '/mute=/c\mute=Core' ${misterscripts}/Super_Attract_Mode.ini
			${misterscripts}/bgm.sh
			sync
			repository_url="https://github.com/mrchrisster/MiSTer_SAM"
			branch="main"
			get_samstuff Media/80s.pls ${misterpath}/music
			[[ ! $(grep -i "bgm" ${misterscripts}/Super_Attract_Mode.ini) ]] && echo "bgm=Yes" >>${misterscripts}/Super_Attract_Mode.ini
			sed -i '/bgm=/c\bgm=Yes' ${misterscripts}/Super_Attract_Mode.ini
			echo " All Done. Starting SAM now."
			${misterscripts}/"Super_Attract_Mode.sh" start

		elif [[ "${menuresponse,,}" == "disablebgm" ]]; then
			echo " Uninstalling BGM, please wait..."
			[[ -e ${misterscripts}/bgm.sh ]] && ${misterscripts}/bgm.sh stop
			[[ -e ${misterscripts}/bgm.sh ]] && rm ${misterscripts}/bgm.sh
			[[ -e ${misterpath}/music/bgm.ini ]] && rm ${misterpath}/music/bgm.ini
			sed -i '/bgm.sh/d' ${userstartup}
			sed -i '/Startup BGM/d' ${userstartup}
			sed -i '/bgm=/c\bgm=No' ${misterscripts}/Super_Attract_Mode.ini
			echo " Done."
		fi
	fi
}

# ======== SAM COMMANDS ========
function sam_update() { # sam_update (next command)
	[[ -s ${misterscripts}/Super_Attract_Mode.ini ]] && read_samini
	if [ $(dirname -- ${0}) != "/tmp" ]; then
		# Warn if using non-default branch for updates
		if [ "${branch}" != "main" ]; then
			echo ""
			echo "*******************************"
			echo " Updating from ${branch}"
			echo "*******************************"
			echo ""
		fi

		# Download the newest Super_Attract_Mode.sh to /tmp
		[[ -f /tmp/Super_Attract_Mode.sh ]] && rm /tmp/Super_Attract_Mode.sh
		get_samstuff Super_Attract_Mode.sh /tmp
		if [ -f /tmp/Super_Attract_Mode.sh ]; then
			if [ ! -z ${1} ]; then
				echo " Continuing setup with latest Super_Attract_Mode.sh..."
				/tmp/Super_Attract_Mode.sh ${1}
				return 0
			else
				echo " Launching latest"
				echo " Super_Attract_Mode.sh..."
				/tmp/Super_Attract_Mode.sh update
				return 0
			fi
		else
			# /tmp/Super_Attract_Mode.sh isn't there!
			echo " SAM update FAILED"
			echo " No Internet?"
			return 1
		fi
	else # We're running from /tmp - download dependencies and proceed
		cp --force "/tmp/Super_Attract_Mode.sh" "${misterscripts}/Super_Attract_Mode.sh" &>/dev/null

		get_partun
		get_mbc
		get_samindex
		get_inputmap
		get_samstuff .SuperAttract/SuperAttract_init
		get_samstuff .SuperAttract/SuperAttract_MCP
		get_samstuff .SuperAttract/SuperAttract_joy.py
		get_samstuff .SuperAttract/SuperAttract_keyboard.py
		get_samstuff .SuperAttract/SuperAttract_mouse.py
		get_samstuff .SuperAttract/SuperAttract_tty2oled
		get_samstuff .SuperAttract/SAM_splash.gsc
		get_samstuff .SuperAttract/SuperAttractSystem.ini

		#blacklist files
		get_samstuff .SuperAttract/SAM_Excludelists/arcade_blacklist.txt ${excludepath}
		get_samstuff .SuperAttract/SAM_Excludelists/fds_blacklist.txt ${excludepath}
		get_samstuff .SuperAttract/SAM_Excludelists/megacd_blacklist.txt ${excludepath}
		get_samstuff .SuperAttract/SAM_Excludelists/tgfx16cd_blacklist.txt ${excludepath}

		if [ -f "${misterscripts}/Super_Attract_Mode.ini" ]; then
			echo " SAM INI already exists... Merging with new ini."
			get_samstuff "Super_Attract_Mode.ini" /tmp
			echo " Backing up Super_Attract_Mode.ini to Super_Attract_Mode.ini.bak"
			cp ${misterscripts}/"Super_Attract_Mode.ini" ${misterscripts}/"Super_Attract_Mode.ini.bak" &>/dev/null
			echo -n " Merging ini values.."
			# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
			sed -i 's/==/--/g' ${misterscripts}/"Super_Attract_Mode.ini"
			sed -i 's/-=/--/g' ${misterscripts}/"Super_Attract_Mode.ini"
			sed -i 's/^corelist_allow=/corelist=/g' ${misterscripts}/"Super_Attract_Mode.ini"
			sed -i 's/^\^corelist_allow=/corelist=/g' ${misterscripts}/"Super_Attract_Mode.ini"
			awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' ${misterscripts}/Super_Attract_Mode.ini /tmp/"Super_Attract_Mode.ini" >/tmp/SuperAttract.tmp && mv --force /tmp/SuperAttract.tmp ${misterscripts}/"Super_Attract_Mode.ini"
			echo "Done."

		else
			get_samstuff "Super_Attract_Mode.ini" ${misterscripts}
		fi

	fi
	[[ -f "/tmp/Super_Attract_Mode.sh" ]] && rm -f "/tmp/Super_Attract_Mode.sh"
	[[ -f "/tmp/Super_Attract_Mode.ini" ]] && rm -f "/tmp/Super_Attract_Mode.ini"
	[[ -f "/tmp/samindex.zip" ]] && rm -f "/tmp/samindex.zip"

	echo " Update complete!"
	echo " Please reboot your Mister. (Cold Reboot) or start SAM from the menu"

	sam_exit 0 "stop"
}

function sam_install() { # Install SAM to startup
	echo -n " Installing Super Attract Mode..."

	# Awaken daemon
	# Check for and delete old fashioned scripts to prefer ${misterpath}/linux/user-startup.sh
	# (https://misterfpga.org/viewtopic.php?p=32159#p32159)

	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "${RO_ROOT}" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "${RO_ROOT}" == "true" ] && mount / -o remount,ro
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
	if [[ $(grep -ic "mister_sam" ${userstartup}) != "0" ]]; then
		sed -i '/[mM]i[sS][tT]er_[sS][aA][mM]/d' ${userstartup}
	fi
	
	if [[ $(grep -ic "attract" ${userstartup}) == "0" ]]; then
		echo -e "Adding SAM to ${userstartup}\n"
		echo -e "\n# Startup Super Attract Mode" >>${userstartup}
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
	echo " Please reboot your Mister. (Cold Reboot) or start SAM from the menu"

	sam_exit 0 "stop"
}

function sam_uninstall() { # Uninstall SAM from startup

	echo -n " Uninstallling SAM..."
	# Clean out existing processes to ensure we can update

	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "${RO_ROOT}" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "${RO_ROOT}" == "true" ] && mount / -o remount,ro
	fi

	there_can_be_only_one
	sed -i '/MiSTer_SAM/d' ${userstartup}
	sed -i '/Attract/d' ${userstartup}
	sync
	sam_exit 0 "stop"
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
}

# ======== UTILITY FUNCTIONS ========
function there_can_be_only_one() { # there_can_be_only_one
	# If another attract process is running kill it
	# This can happen if the script is started multiple times
	echo -n " Stopping other running instances of ${samprocess}..."

	kill_1=$(ps -o pid,args | grep '[S]uper_Attract_init start' | awk '{print $1}' | head -1)
	kill_2=$(ps -o pid,args | grep '[S]uper_Attract_Mode.sh start_real' | awk '{print $1}')
	kill_3=$(ps -o pid,args | grep '[S]uper_Attract_Mode.sh bootstart' | awk '{print $1}' | head -1)

	[[ ${kill_1} ]] && kill -9 ${kill_1} >/dev/null
	for kill in ${kill_2}; do
		[[ ${kill_2} ]] && kill -9 ${kill} >/dev/null
	done
	[[ ${kill_3} ]] && kill -9 ${kill_3} >/dev/null

	sleep 1

	echo " Done!"
}

function only_survivor() {
	# Kill all SAM processes except for currently running
	ps -ef | grep -i '[s]tart_real' | awk -v me=${sampid} '$1 != me {print $1}' | xargs kill &>/dev/null
	# kill_4=$(ps -ef | grep -i '[S]uper_Attract_Mode' | awk -v me=${sampid} '$1 != me {print $1}')
	# for kill in ${kill_4}; do
	# 	[[ ! -z ${kill_4} ]] && kill -9 ${kill} &>/dev/null
	# done
}

function sam_stop() {
	corename_name=$(printf '%s\n' $(</tmp/CORENAME))
	SAM_cleanup

	tries=5
	pids=$(pidof SuperAttract_MCP)
	if [ ! -z "${pids}" ]; then
		samquiet "-n" " Stopping MCP..."
		samquiet "-n" " ${pids} "
		# kill -9 ${pids} &>/dev/null
		while [ $(kill -15 ${pids} 2>/dev/null)] && [ ${tries} -gt 0 ]; do
			((tries--))
			sleep 1
		done
		pids=$(pidof SuperAttract_MCP)
		samquiet " Failed, forcing!"
		samquiet "-n" " Stopping MCP..."
		samquiet "-n" "${pids} "
		kill -9 ${pids} &>/dev/null
		samquiet " Done!"
	fi
	sleep 2
	pids=""
	pids=$(pidof SuperAttract_tty2oled)
	if [ ! -z "${pids}" ]; then
		samquiet "-n" " Stopping TTY..."
		samquiet "-n" " | ${pids} "
		# kill -9 ${pids} &>/dev/null
		while $(kill -15 ${pids} 2>/dev/null); do
			sleep 1
		done
		samquiet " Done!"
	fi
	sleep 2
	pids=""
	pids=$(pidof Super_Attract_Mode.sh)
	if [ ! -z "${pids}" ]; then
		samquiet "-n" " Stopping SAM..."
		samquiet "-n" " | ${pids} "
		# kill -9 ${pids} &>/dev/null
		while $(kill -15 ${pids} 2>/dev/null); do
			sleep 1
		done
		if [ ${corename_name} != "MENU" ]; then
			samquiet "-n" " Returning to MiSTer Menu..."
			echo "load_core ${misterpath}/menu.rbf" >/dev/MiSTer_cmd
			samquiet " Done!"
		fi
		samquiet " Done!"
	fi
	pids=""
	sleep 2
}

function sam_exit() { # args = ${1}(exit_code required) ${2} optional error message or stop
	[[ $(mount | grep -ic "${misterpath}/config") != "0" ]] && umount "${misterpath}/config"
	while [[ $(mount | grep -ic "${misterpath}/config") != "0" ]]; do
		sleep 1
	done
	# [[ $(mount | grep -ic ${amigashared}) != "0" ]] && umount "${amigashared}"
	# while [[ $(mount | grep -ic ${amigashared}) != "0" ]]; do
	# 	sleep 1
	# done
	bgm_stop
	write_to_TTY_cmd_pipe "exit" &
	corename_name=$(printf '%s\n' $(</tmp/CORENAME))
	if [ ! -z "${2}" ] && [ "${2}" == "stop" ]; then
		sam_stop
	elif [ "${1}" -eq 0 ]; then # just exit
		if [ ${corename_name,,} != "menu" ]; then
			echo "load_core ${misterpath}/menu.rbf" >/dev/MiSTer_cmd
		fi
		sleep 1
		echo " Done!"
		echo " Thanks for playing!"
	elif [ "${1}" -eq 1 ]; then # Error
		if [ ${corename_name,,} != "menu" ]; then
			echo "load_core ${misterpath}/menu.rbf" >/dev/MiSTer_cmd
		fi
		sleep 1
		echo " Done!"
		echo " There was an error ${2}" # Pass error messages in ${2}
	elif [ "${1}" -eq 2 ]; then      # Play Current Game
		if [ ${mute} != "no" ]; then
			sleep 0.5
			# if [ ${corename_name,,} == "minimig" ]; then
			# 	[[ -s ${mrsamtmp}/Amiga_shared/ags_boot ]] && mv -- ${mrsamtmp}/Amiga_shared/ags_boot ${amigashared}/ags_boot
			# 	[[ -s ${mrsamtmp}/Amiga_shared/ags_current ]] && mv -- ${mrsamtmp}/Amiga_shared/ags_current ${amigashared}/ags_boot
			# 	sleep 1
			# fi
			local xnextcore=$(tail -n1 '/tmp/SAM_Games.log' | grep -E -o '\- (\w*) \-' | sed 's/\s[\-]//' | sed 's/[\-]\s//')
			local xromname=$(tail -n1 '/tmp/SAM_Games.log' | grep -E -o "\- ${xnextcore} \- (.*)$" | sed "s/\- ${xnextcore} \- //")
			echo "load_core ${file_to_load}" >/dev/MiSTer_cmd
			if [ "${skipmessage}" == "yes" ] && [ "${CORE_SKIP[${xnextcore}]}" == "yes" ]; then
				skipmessage "${xnextcore}" "${xromname}"
			fi
			sleep 5
		fi
	fi
	SAM_cleanup
	tmux kill-session -t SAM
	exit $1
}

function deleteall() {
	# In case of issues, reset SAM

	# there_can_be_only_one
	if [ -d "${mrsampath}" ]; then
		echo "Deleting SuperAttract folder"
		rm -rf "${mrsampath}"
	fi
	if [ -f "${misterscripts}/Super_Attract_Mode.ini" ]; then
		echo "Deleting Super_Attract_Mode.ini"
		cp ${misterscripts}/"Super_Attract_Mode.ini" ${misterscripts}/"Super_Attract_Mode.ini.bak" &>/dev/null
		rm ${misterscripts}/"Super_Attract_Mode.ini"
	fi

	if [ -d "${gamelistpath}" ]; then
		echo "Deleting Gamelist folder"
		rm -rf "${gamelistpath}"
	fi

	if ls "${misterpath}/config/inputs/*_input_1234_5678_v3.map" 1>/dev/null 2>&1; then
		echo "Deleting Keyboard mapping files"
		rm "${misterpath}/config/inputs/*_input_1234_5678_v3.map"
	fi
	# Remount root as read-write if read-only so we can remove daemon
	mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
	[ "${RO_ROOT}" == "true" ] && mount / -o remount,rw

	# Delete daemon
	echo "Deleting Auto boot Daemon..."
	if [ -f /etc/init.d/S93mistersam ] || [ -f /etc/init.d/_S93mistersam ]; then
		mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="true"
		[ "${RO_ROOT}" == "true" ] && mount / -o remount,rw
		sync
		rm /etc/init.d/S93mistersam &>/dev/null
		rm /etc/init.d/_S93mistersam &>/dev/null
		sync
		[ "${RO_ROOT}" == "true" ] && mount / -o remount,ro
	fi
	echo "Done."

	sed -i '/Attract/d' ${userstartup}
	sed -i '/Super Attract/d' ${userstartup}

	printf "\nAll files deleted except for Super_Attract_Mode.sh\n"
	if [ ${inmenu} -eq 1 ]; then
		sleep 1
		sam_resetmenu
	else
		printf "\nGamelist reset successful. Please start SAM now.\n"
		sleep 1
		main stop
	fi
}

function deletegl() {
	# In case of issues, reset game lists

	there_can_be_only_one
	if [ -d "${gamelistpath}" ]; then
		echo "Deleting Super Attract Mode Gamelist folder"
		rm -rf "${gamelistpath}"
	fi

	if [ -d "${mrsampath}/SAM_Count" ]; then
		rm -rf "${mrsampath}/SAM_Count"
	fi
	if [ -d "${gamelistpathtmp}" ]; then
		rm -rf "${gamelistpathtmp}"
	fi

	if [ ${inmenu} -eq 1 ]; then
		sleep 1
		sam_menu
	else
		echo -e "\nGamelist reset successful. Please start SAM now.\n"
		sleep 1
		sam_exit 0 "stop"
	fi
}

function creategl() {
	mkdir -p "${gamelistpath}"
	mkdir -p "${gamelistpathtmp}"
	create_all_gamelists_old="${create_all_gamelists}"
	rebuild_freq_amiga_old="${rebuild_freq_amiga}"
	rebuild_freq_arcade_old="${rebuild_freq_arcade}"
	rebuild_freq_old="${rebuild_freq}"
	create_all_gamelists="Yes"
	rebuild_freq_amiga="Always"
	rebuild_freq_arcade="Always"
	rebuild_freq="Always"
	create_game_lists
	create_all_gamelists="${create_all_gamelists_old}"
	rebuild_freq_amiga="${rebuild_freq_amiga_old}"
	rebuild_freq_arcade="${rebuild_freq_arcade_old}"
	rebuild_freq="${rebuild_freq_old}"
	if [ ${inmenu} -eq 1 ]; then
		sleep 1
		sam_menu
	else
		echo -e "\nGamelist creation successful. Please start SAM now.\n"
		sleep 1
		sam_exit 0 "stop"
	fi
}

function skipmessage() {
	local core="${1,,}"
	local game="${2,,}"
	samdebug " core: ${core}"
	samdebug " game: ${game}"
	# Skip past bios/safety warnings
	if [ "${core}" == "amiga" ]; then
		if [ ! -s "${CORE_PATH_FINAL[${core}]}/listings/games.txt" ]; then
			sleep 15
			samquiet " Skipping BIOS/Safety Warnings!"
			# This is for MegaAGS version June 2022 or older
			"${mrsampath}/bin/mbc" raw_seq {6c
			"${mrsampath}/bin/mbc" raw_seq O
			"${mrsampath}/bin/mbc" raw_seq }
		fi
	elif [ "${core}" == "atari5200" ]; then
		shopt -s nullglob
		sleep 15
		for key in "${!ATARI5200_GAME_SKIP[@]}"; do
			if [[ "${game}" == *"${key,,}"* ]]; then
				samquiet " Skipping BIOS/Safety Warnings!"
				samdebug " Match!"
				"${mrsampath}/bin/mbc" raw_seq "${ATARI5200_GAME_SKIP[$key]}"
			fi
		done
		shopt -u nullglob
	else
		sleep 15
		samquiet " Skipping BIOS/Safety Warnings!"
		"${mrsampath}/bin/mbc" raw_seq :31
	fi
}

function mglfavorite() {
	# Add current game to _Favorites folder

	[[ ! -d "${misterpath}/_Favorites" ]] && mkdir -p "${misterpath}/_Favorites"
	cp /tmp/SAM_game.mgl "${misterpath}/_Favorites/$(cat /tmp/SAM_Game.txt).mgl" &>/dev/null
}

function exclude_game() {
	# Add current game to Exclude list
	local xnextcore=$(tail -n1 '/tmp/SAM_Games.log' | grep -E -o '\- (\w*) \-' | sed 's/\s[\-]//' | sed 's/[\-]\s//')
	if [ "${xnextcore}" == "neogeo" ]; then
		local xromname=$(tail -n1 '/tmp/SAM_Games.log' | grep -E -o "\- ${xnextcore} \- (.*)$" | sed "s/\- ${xnextcore} \- //" | sed "s/ \(.*\)//")
	else
		local xromname=$(tail -n1 '/tmp/SAM_Games.log' | grep -E -o "\- ${xnextcore} \- (.*)$" | sed "s/\- ${xnextcore} \- //")
	fi
	local xrompath=$(cat "${gamelistpath}/${xnextcore}_gamelist.txt" | grep "${xromname}")
	samquiet " xnextcore: ${xnextcore}"
	samquiet " xromname: ${xromname}"
	samquiet " xrompath: ${xrompath}"
	if [ -f "${excludepath}/${xnextcore}_excludelist.txt" ] && [ ! -z "${xromname}" ]; then
		echo "${xromname}" >>"${excludepath}/${xnextcore}_excludelist.txt"
	elif [ ! -z "${xromname}" ]; then
		echo "${xromname}" >"${excludepath}/${xnextcore}_excludelist.txt"
	fi
	next_core "${xnextcore}"
	return
}

function fakegameslog() {
	echo "" | >"/tmp/SAM_Games(fake).log"
	for fcore in ${corelistall}; do
		frompath=$(cat ${gamelistpath}/${fcore}_gamelist.txt | shuf --head-count=1)
		fromname=$(basename "${frompath}")
		fGAMENAME=""
		if [ ${fcore} == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then
			if [ ${neogeoregion} == "english" ]; then
				fGAMENAME="${NEOGEO_PRETTY_ENGLISH[${fromname}]}"
			elif [ ${neogeoregion} == "japanese" ]; then
				fGAMENAME="${NEOGEO_PRETTY_JAPANESE[${fromname}]}"
				[[ -z "${fGAMENAME}" ]] && fGAMENAME="${NEOGEO_PRETTY_ENGLISH[${fromname}]}"
			fi
		fi
		if [ -z "${fGAMENAME}" ]; then
			fGAMENAME="${fromname}"
		fi
		local date=$(date '+%H:%M:%S')
		if [ "${core}" == "neogeo" ] && [ "${useneogeotitles}" == "yes" ]; then
			echo "${date} - ${core} - ${romname} (${GAMENAME})" >>"/tmp/SAM_Games(fake).log"
		else
			echo "${date} - ${core} - ${romname}" >>"/tmp/SAM_Games(fake).log"
		fi
	done
}

function bgm_start() {
	if [ "${bgm}" == "yes" ] && [ "${mute}" == "core" ]; then
		echo -n "set playincore yes" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
		echo -n "play" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
	fi
}

function bgm_stop() {
	if [ "${bgm}" == "yes" ]; then
		echo -n "set playincore no" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
		echo -n "stop" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
	fi
}

function mute() {
	if [ "${mute}" == "yes" ]; then
		# Mute Global Volume
		echo -e "\0020\c" >"${misterpath}/config/Volume.dat"
	elif [ "${mute}" == "core" ]; then
		# UnMute Global Volume
		echo -e "\0000\c" >"${misterpath}/config/Volume.dat"
		# Mute Core Volumes
		echo -e "\0006\c" >"${misterpath}/config/${1}_volume.cfg"
	elif [ "${mute}" == "no" ]; then
		# UnMute Global Volume
		echo -e "\0000\c" >"${misterpath}/config/Volume.dat"
		# UnMute Core Volumes
		echo -e "\0000\c" >"${misterpath}/config/${1}_volume.cfg"
	fi
}

function core_error() { # core_error core /path/to/ROM
	local core=${1}
	local rompath=${2}
	if [ ${romloadfails} -lt ${coreretries} ]; then
		((romloadfails++))
		echo " ERROR: Failed ${romloadfails} times. No valid game found for core: ${core} rom: ${rompath}"
		echo " Trying to find another rom..."
		next_core "${core}"
		return
	else
		echo " ERROR: Failed ${romloadfails} times. No valid game found for core: ${core} rom: ${rompath}"
		echo " ERROR: Core ${core} is blacklisted!"
		corelist_allow=$(echo "${corelist_allow}"  | sed "s/\b${core}\b//" | tr -d '[:cntrl:]' | awk '{$2=$2};1')
		echo " List of cores is now: ${corelist_allow}"
		romloadfails=0
		next_core "${core}"
		return
	fi
}

function play_or_exit() {
	if [ "${playcurrentgame}" == "yes" ]; then
		write_to_SAM_cmd_pipe "exit 2"
	else
		write_to_SAM_cmd_pipe "exit 0"
	fi
}

# ======== UPDATER FUNCTIONS ========
function curl_download() { # curl_download ${filepath} ${URL}

	curl \
		--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
		--insecure \
		--fail \
		--location \
		-o "${1}" \
		"${2-}"
}

function get_samstuff() { #get_samstuff file (path)
	if [ -z "${1}" ]; then
		return 1
	fi

	filepath="${2:-${mrsampath}}"

	echo -n " Downloading from ${repository_url}/blob/${branch}/${1} to ${filepath}/..."
	curl_download "/tmp/${1##*/}" "${repository_url}/blob/${branch}/${1}?raw=true"

	if [ "${filepath}" != "/tmp" ]; then
		mv --force "/tmp/${1##*/}" "${filepath}/${1##*/}"
	fi

	if [ "${1##*.}" == "sh" ]; then
		chmod +x "${filepath}/${1##*/}"
	fi

	echo " Done!"
}

function get_partun() {
	local REPO_URL="https://github.com/woelper/partun"
	echo " Downloading partun - needed for unzipping roms from big archives..."
	echo " Created for MiSTer by woelper - Talk to him at this year's PartunCon"
	echo " ${REPO_URL}"
	latest=$(curl -s -L --insecure https://api.github.com/repos/woelper/partun/releases/latest | jq -r ".assets[] | select(.name | contains(\"armv7\")) | .browser_download_url")
	curl_download "/tmp/partun" "${latest}"
	[[ ! -d "${mrsampath}/bin" ]] && mkdir -p "${mrsampath}/bin"
	mv --force "/tmp/partun" "${mrsampath}/bin/partun"
	[[ -f "${mrsampath}/partun" ]] && rm -f "${mrsampath}/partun"
	echo " Done!"
}

function get_samindex() {
	local REPO_URL="${repository_url}/blob/${branch}/.SuperAttract/bin/samindex.zip?raw=true"
	echo " Downloading samindex - needed for creating gamelists..."
	echo " Created for MiSTer by wizzo"
	echo " ${REPO_URL}"
	latest="${repository_url}/blob/${branch}/.SuperAttract/bin/samindex.zip?raw=true"
	curl_download "/tmp/samindex.zip" "${latest}"
	[[ ! -d "${mrsampath}/bin" ]] && mkdir -p "${mrsampath}/bin"
	unzip -ojq /tmp/samindex.zip -d "${mrsampath}/bin" # &>/dev/null
	# mv --force "/tmp/samindex" "${mrsampath}/bin/samindex"
	[[ -f "${mrsampath}/samindex" ]] && rm -f "${mrsampath}/samindex"
	echo " Done!"
}

function get_mbc() {
	local REPO_URL="${repository_url}/blob/${branch}/.SuperAttract/bin/mbc?raw=true"
	echo " Downloading mbc - Control MiSTer from cmd..."
	echo " Created for MiSTer by pocomane"
	echo " ${REPO_URL}"
	latest="${repository_url}/blob/${branch}/.SuperAttract/bin/mbc?raw=true"
	curl_download "/tmp/mbc" "${latest}"
	[[ ! -d "${mrsampath}/bin" ]] && mkdir -p "${mrsampath}/bin"
	mv --force "/tmp/mbc" "${mrsampath}/bin/mbc"
	[[ -f "${mrsampath}/mbc" ]] && rm -f "${mrsampath}/mbc"
	echo " Done!"
}

function get_inputmap() {
	echo -n " Downloading input maps - needed to skip past BIOS for some systems..."
	get_samstuff .SuperAttract/inputs/GBA_input_1234_5678_v3.map ${misterpath}/config/inputs >/dev/null
	get_samstuff .SuperAttract/inputs/MegaCD_input_1234_5678_v3.map ${misterpath}/config/inputs >/dev/null
	get_samstuff .SuperAttract/inputs/NES_input_1234_5678_v3.map ${misterpath}/config/inputs >/dev/null
	get_samstuff .SuperAttract/inputs/TGFX16_input_1234_5678_v3.map ${misterpath}/config/inputs >/dev/null
	echo " Done!"
}

# ========= SAM START =========
function sam_start_new() {
	loop_core "${nextcore}"
}

function sam_start() {
	env_check
	# If MCP isn't running we need to start it in monitoring only mode
	if [ -z "$(pidof SuperAttract_MCP)" ]; then
		echo " Starting MCP.."
		tmux new-session -s MCP -d "${mrsampath}/SuperAttract_MCP" &
	fi
	# If TTY2oled isn't running we need to start it in monitoring only mode
	if [ -z "$(pidof SuperAttract_tty2oled)" ]; then
		echo " Starting TTY.."
		tmux new-session -s TTY -d "${mrsampath}/SuperAttract_tty2oled" &
	fi
	# If SAM isn't running we need to start it in monitoring only mode
	if [ -z "$(pidof Super_Attract_Mode.sh)" ]; then
		echo " Starting SAM.."
		if [ -z "${1}" ]; then
			tmux new-session -x 180 -y 40 -n "-= SAM Monitor -- Detach with ctrl-b d  =-" -s SAM -d "${misterscripts}/Super_Attract_Mode.sh" start_real &
		else
			tmux new-session -x 180 -y 40 -n "-= SAM Monitor -- Detach with ctrl-b d  =-" -s SAM -d "${misterscripts}/Super_Attract_Mode.sh" "${1}" start_real &
		fi
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

function get_nextcore() {
	printf '%s' ${nextcore}
}

# ======== SAM OPERATIONAL FUNCTIONS ========
function loop_core() { # loop_core (core)
	echo -e " Starting Super_Attract_Mode...\n Let Mortal Kombat begin!\n"
	# Reset game log for this session
	echo "" | >"/tmp/SAM_Games.log"
	start_pipe_readers
	while true; do
		trap 'counter=0' INT #Break out of loop for skip & next command
		while [ ${counter} -gt 0 ]; do
			if [[ $(mount | grep -ic "${misterpath}/config") != "0" ]]; then
				echo -ne " Next game in ${counter}...\033[0K\r"
				sleep 1
				((counter--))
				if [ "${ttyenable}" == "yes" ]; then
					tty_currentinfo[counter]=$(printf "%03d" ${counter})
					write_to_TTY_cmd_pipe "update_counter ${tty_currentinfo[counter]}" &
				fi
			else
				break
			fi
		done
		trap - INT
		sleep 1
		if [[ $(mount | grep -ic "${misterpath}/config") -eq 1 ]]; then
			counter=${gametimer}
			core=$(get_nextcore)
			next_core "${core}"
		fi
	done
}

function reset_core_gl() { # args ${nextcore}
	echo " Deleting old game lists for ${1^^}..."
	rm "${gamelistpath}/${1}_gamelist.txt" &>/dev/null
	sync
}

function speedtest() {
	speedtest=1
	[[ ! -d "${mrsamtmp}/gl" ]] && { mkdir -p ${mrsamtmp}/gl; }
	[[ ! -d "${mrsamtmp}/glt" ]] && { mkdir -p ${mrsamtmp}/glt; }
	[[ $(mount | grep -ic "${gamelistpath}") == "0" ]] && mount --bind ${mrsamtmp}/gl "${gamelistpath}"
	[[ $(mount | grep -ic "${gamelistpathtmp}") == "0" ]] && mount --bind ${mrsamtmp}/glt "${gamelistpathtmp}"
	START=$(date +%s)
	for core in ${corelistall}; do
		defaultpath "${core}"
	done
	DURATION_DP=$(($(date +%s) - ${START}))
	START=$(date +%s)
	echo "" | >"${gamelistpathtmp}/Durations.tmp"
	for core in ${corelistall}; do
		local DIR=$(echo $(realpath -s --canonicalize-missing "${CORE_PATH_FINAL[${core}]}"))
		if [ ${core} = " " ] || [ ${core} = "" ] || [ -z ${core} ]; then
			continue
		else
			START2=$(date +%s)
			create_romlist ${core} "${DIR}"
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
	[ $(mount | grep -ic "${gamelistpath}") != "0" ] && umount "${gamelistpath}"
	[ $(mount | grep -ic "${gamelistpathtmp}") != "0" ] && umount "${gamelistpathtmp}"
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

	case ${rebuild_freq_amiga} in
	hour)
		rebuild_freq_amiga_int=$((3600 * ${regen_duration_amiga}))
		;;
	day)
		rebuild_freq_amiga_int=$((86400 * ${regen_duration_amiga}))
		;;
	week)
		rebuild_freq_amiga_int=$((604800 * ${regen_duration_amiga}))
		;;
	always)
		rebuild_freq_amiga_int=0
		;;
	never)
		rebuild_freq_amiga_int=$((3155760000 * ${regen_duration_amiga}))
		;;
	*)
		echo "Incorrect regeneration value"
		;;
	esac

	for core in ${corelistall}; do
		corelist_allowtmp="${corelist_allow}"
		local DIR=$(echo $(realpath -s --canonicalize-missing "${CORE_PATH_FINAL[${core}]}"))
		local date_file=""

		if [ ${core} == "arcade" ]; then
			rebuild_freq_int=${rebuild_freq_arcade_int}
		elif [ ${core} == "amiga" ]; then
			rebuild_freq_int=${rebuild_freq_amiga_int}
		fi

		if [ -f "${gamelistpath}/${core}_gamelist.txt" ]; then
			if [ -s "${gamelistpath}/${core}_gamelist.txt" ]; then
				date_file=$(stat -c '%Y' "${gamelistpath}/${core}_gamelist.txt")
				if [ $(($(date +%s) - ${date_file})) -gt ${rebuild_freq_int} ]; then
					create_romlist ${core} "${DIR}"
				fi
			else
				corelist_allowtmp=$(echo "${corelist_allow}"  | sed "s/\b${core}\b//" | awk '{$2=$2};1')
				rm "${gamelistpath}/${core}_gamelist.txt" &>/dev/null
			fi
		else
			create_romlist ${core} "${DIR}"
		fi
		corelist_allow=${corelist_allowtmp}
	done
}

# ======== ROMFINDER ========
function create_romlist() { # args ${core} "${DIR}"
	local core=${1}
	local DIR="${2}"
	local total_games=0
	if [ ${speedtest} -eq 1 ] || [ "${samquiet}" == "no" ]; then
		echo " Looking for games in  ${DIR}..."
	else
		echo -n " Looking for games in  ${DIR}..."
	fi
	rm "${gamelistpathtmp}/${core}_gamelist.txt" &>/dev/null
	[[ -f "${tmpfile}" ]] && rm "${tmpfile}" &>/dev/null
	[[ -f "${tmpfile2}" ]] && rm "${tmpfile2}" &>/dev/null

	if [ ${core} == "amiga" ]; then
		# Check for existing files that define the "ROMs"
		if [ -f "${CORE_PATH_FINAL[${core}]}/listings/games.txt" ]; then
			[ -s "${CORE_PATH_FINAL[${core}]}/listings/games.txt" ] && cat "${CORE_PATH_FINAL[${core}]}/listings/demos.txt" >"${tmpfile}"
			sed -i -e 's/^/Demo: /' "${tmpfile}"
			[ -f "${CORE_PATH_FINAL[${core}]}/listings/demos.txt" ] && cat "${CORE_PATH_FINAL[${core}]}/listings/games.txt" >>"${tmpfile}"
		fi
	elif [ ${core} == "arcade" ]; then
		# This prints the list of MRA files in a path,
		# Cuts the string to just the file name,
		# Then saves it to the games list file.
		# If there is an empty exclude list ignore it
		# Otherwise use it to filter the list
		if echo "${DIR}" | grep -q "_Organized"; then
			samdebug "_Organized detected!"
			if [ ${#arcadeexclude[@]} -eq 0 ]; then
				find -L "${DIR}" \( -xtype l -o -xtype d \) \( -path '*/.*' \) -prune -o \( -xtype l -o -xtype f \) \( -iname "*.mra" \) -fprint >(cat >>"${tmpfile}")
			else
				find -L "${DIR}" \( -xtype l -o -xtype d \) \( -path '*/.*' \) -prune -o \( -xtype l -o -xtype f \) \( -iname "*.mra" \) -fprint >(cat >>"${tmpfile}") | grep -vFf <(printf '%s\n' ${arcadeexclude[@]}) >"${tmpfile}"
			fi
		else
			samdebug "_Organized not detected!"
			if [ ${#arcadeexclude[@]} -eq 0 ]; then
				find -L "${DIR}" \( -xtype l -o -xtype d \) \( -path '*/.*' -o -path '*_Organized*' \) -prune -o \( -xtype l -o -xtype f \) \( -iname "*.mra" \) -fprint >(cat >>"${tmpfile}")
			else
				find -L "${DIR}" \( -xtype l -o -xtype d \) \( -path '*/.*' -o -path '*_Organized*' \) -prune -o \( -xtype l -o -xtype f \) \( -iname "*.mra" \) -fprint >(cat >>"${tmpfile}") | grep -vFf <(printf '%s\n' ${arcadeexclude[@]}) >"${tmpfile}"
			fi
		fi
	else
		# Find all files in core's folder with core's extension
		if [ "${samindex}" == "yes" ] && [ -s "${mrsampath}/bin/samindex" ]; then
			mkdir -p "${gamelistpathtmp}/samindex"
			if [ "${samquiet}" == "no" ]; then
				${mrsampath}/bin/samindex -s ${core} -o "${gamelistpathtmp}/samindex"
			else
				${mrsampath}/bin/samindex -q -s ${core} -o "${gamelistpathtmp}/samindex"
			fi
			[[ ! -f "${gamelistpathtmp}/samindex/${core}_gamelist.txt" ]] && echo "" | >"${tmpfile}" &>/dev/null
			[[ -f "${gamelistpathtmp}/samindex/${core}_gamelist.txt" ]] && cp "${gamelistpathtmp}/samindex/${core}_gamelist.txt" "${tmpfile}" &>/dev/null
		else
			extlist=$(echo ${CORE_EXT[${core}]} | sed -e "s/,/ -o -iname *.${f}/g")
			find -L "${DIR}" \( -xtype l -o -xtype d \) \( -iname *BIOS* ${folderex} \) -prune -false -o -not -path '*/.*' \( -xtype l -o -xtype f \) \( -iname "*."${extlist} -not -iname *BIOS* ${fileex} \) -fprint >(cat >>"${tmpfile}")
			# Now find all zips in core's folder and process
			if [ "${CORE_ZIPPED[${core}]}" == "yes" ]; then
				find -L "${DIR}" \( -xtype l -o -xtype d \) \( -iname *BIOS* ${folderex} \) -prune -false -o -not -path '*/.*' \( -xtype l -o -xtype f \) \( -iname "*.zip" -not -iname *BIOS* ${fileex} \) -fprint >(cat >>"${tmpfile2}")
				if [ -f "${tmpfile2}" ]; then
					cat "${tmpfile2}" | while read z; do
						if [ ${speedtest} -eq 1 ] || [ "${samquiet}" == "no" ]; then
							echo " Processing: ${z}"
						fi
						"${mrsampath}/bin/partun" "${z}" -l -e ${zipex} --include-archive-name --ext "${CORE_EXT[${core}]}" >>"${tmpfile}"
					done
				fi
			fi
		fi
	fi
	# Strip out all duplicate filenames with a fancy awk command
	if [ -f "${tmpfile}" ]; then
		echo "" | >"${tmpfile2}" &>/dev/null
		cat "${tmpfile}" | while read z; do
			echo "${z}" >>"${tmpfile2}"
		done
	fi
	[ -f "${tmpfile2}" ] && awk -F'/' '!seen[$NF]++' "${tmpfile2}" | sort >"${gamelistpathtmp}/${core}_gamelist.txt"
	[[ -f "${gamelistpathtmp}/${core}_gamelist.txt" ]] && cp "${gamelistpathtmp}/${core}_gamelist.txt" "${gamelistpath}/${core}_gamelist.txt" &>/dev/null
	[[ -f "${tmpfile}" ]] && rm "${tmpfile}" &>/dev/null
	[[ -f "${tmpfile2}" ]] && rm "${tmpfile2}" &>/dev/null
	total_games=$(echo $(cat "${gamelistpath}/${core}_gamelist.txt" | sed '/^\s*$/d' | wc -l))
	if [ ${speedtest} -eq 1 ]; then
		echo -n "${core}: ${total_games} Games found" >>"${gamelistpathtmp}/Durations.tmp"
	fi
	if [ ${speedtest} -eq 1 ] || [ "${samquiet}" == "no" ]; then
		echo "${total_games} Games found."
	else
		echo " ${total_games} Games found."
	fi
}

function check_romlist() { # args ${core}  "${DIR}"
	local core=${1}
	local DIR="${2}"
	# If gamelist is not in gameslist dir, let's put it there
	if [ ! -s "${gamelistpath}/${core}_gamelist.txt" ]; then
		samquiet " Creating game list at ${gamelistpath}/${core}_gamelist.txt"
		create_romlist ${core} "${DIR}"
	fi

	# If gamelist is not in /tmp dir, let's put it there
	if [ ! -s "${gamelistpathtmp}/${core}_gamelist.txt" ]; then
		samquiet " Creating game list at ${gamelistpathtmp}/${core}_gamelist.txt"
		cp "${gamelistpath}/${core}_gamelist.txt" "${gamelistpathtmp}/${core}_gamelist.txt"
	fi

	# If folder changed, make new list
	if [ ${core} != "amiga" ] && [[ ! $(cat ${gamelistpath}/${core}_gamelist.txt | grep -i "${DIR}" | head -1) ]]; then
		samquiet " Creating new game list because folder "${DIR}" changed in ini."
		create_romlist ${core} "${DIR}"
	fi

	# Check if zip still exists
	if [ "${CORE_ZIPPED[${core}]}" == "yes" ]; then
		if [ $(grep -c ".zip" ${gamelistpath}/${core}_gamelist.txt) -gt 0 ]; then
			mapfile -t zipsinfile < <(grep ".zip" "${gamelistpath}/${core}_gamelist.txt" | awk -F".zip" '!seen[$1]++' | awk -F".zip" '{print $1}' | sed -e 's/$/.zip/')
			for zips in "${zipsinfile[@]}"; do
				if [ ! -f "${zips}" ]; then
					samquiet " Creating new game list because zip file[s] seems to have changed."
					create_romlist ${core} "${DIR}"
				fi
			done
		fi
	fi

	# Pick the actual game
	if [ -s "${gamelistpathtmp}/${core}_gamelist.txt" ]; then
		rompath=$(cat ${gamelistpathtmp}/${core}_gamelist.txt | shuf --head-count=1)
	else
		# Repopulate list
		if [ -s "${gamelistpath}/${core}_gamelist_exclude.txt" ]; then
			samquiet "-n" " Exclusion list found. Excluding games now..."
			comm -13 <(sort <"${gamelistpath}/${core}_gamelist_exclude.txt") <(sort <"${gamelistpath}/${core}_gamelist.txt") >${tmpfile}
			awk -F'/' '!seen[$NF]++' ${tmpfile} >"${gamelistpathtmp}/${core}_gamelist.txt"
			samquiet "Done."
			rompath=$(cat ${gamelistpathtmp}/${core}_gamelist.txt | shuf --head-count=1)
		else
			awk -F'/' '!seen[$NF]++' "${gamelistpath}/${core}_gamelist.txt" >"${gamelistpathtmp}/${core}_gamelist.txt"
			# cp "${gamelistpath}/${core}_gamelist.txt" "${gamelistpathtmp}/${core}_gamelist.txt" &>/dev/null
			rompath=$(cat ${gamelistpathtmp}/${core}_gamelist.txt | shuf --head-count=1)
		fi
	fi

	# Make sure file exists since we're reading from a static list
	if [[ "${rompath,,}" != *.zip* ]] && [ ${core} != "amiga" ]; then
		if [ ! -s "${rompath}" ]; then
			samquiet " Creating new game list because file not found."
			create_romlist ${core} "${DIR}"
		fi
	fi

	# Delete played game from list
	samquiet " Selected file: ${rompath}"
	if [ "${norepeat}" == "yes" ]; then
		awk -vLine="${rompath}" '!index($0,Line)' "${gamelistpathtmp}/${core}_gamelist.txt" >${tmpfile} && mv --force ${tmpfile} "${gamelistpathtmp}/${core}_gamelist.txt"
	fi
	[ -f "${tmpfile}" ] && rm "${tmpfile}" &>/dev/null
}

# This function will pick a random rom from the game list.
function next_core() { # next_core (core)
	if [ "${1,,}" == "countdown" ] && [ ! -z "$2" ]; then
		countdown="countdown"
		nextcore="${2}"
	elif [ "${2,,}" == "countdown" ]; then
		nextcore="${1}"
		countdown="countdown"
	fi
	if [ "${countdown}" != "countdown" ]; then
		core="${1}"
		corelist_count=$(echo $(wc -w <<<"${corelist_allow}"))
		corelist_allowtmp_count=$(echo $(wc -w <<<"${corelist_allowtmp}"))
		samdebug " corelist count is ${corelist_count} at start of next_core()"
		if [ "${corelist_count}" -gt 0 ]; then
			if [ "${corelist_allowtmp_count}" -eq 0 ]; then
				printf -v corelist_allowtmp '%s ' "${corelist_allow}"
				corelist_allowtmp=$(echo "${corelist_allowtmp}"  | awk '{$2=$2};1')
				corelist_allowtmp_count=$(echo $(wc -w <<<"${corelist_allowtmp}"))
			fi
		else
			if [ "${corelist_count}" -eq 0 ]; then
				printf -v corelist_allow '%s ' "${corelist_allowtmp}"
				corelist_allow=$(echo "${corelist_allow}"  | awk '{$2=$2};1')
				corelist_count=$(echo $(wc -w <<<"${corelist_allow}"))
			fi
		fi
		if [ "${corelist_count}" -eq 0 ]; then
			corelist_allow="arcade"
			corelist_allowtmp=${corelist_allow}
			corelist_count=$(echo $(wc -w <<<"${corelist_allow}"))
			corelist_allowtmp_count=$(echo $(wc -w <<<"${corelist_allowtmp}"))
		fi
		# Set ${nextcore} from ${corelist_allow}
		if [ ${corelist_allowtmp_count} -gt 1 ]; then
			if [ ! -z "${2}" ] && [ "${2}" == "repeat" ]; then
				nextcore=${core}
			else
				nextcore=$(echo ${corelist_allow} | xargs shuf --head-count=1 --echo)
				corelist_allow=$(echo "${corelist_allow}"  | sed "s/\b${nextcore}\b//" | tr -d '[:cntrl:]' | awk '{$2=$2};1')
				corelist_count=$(echo $(wc -w <<<"${corelist_allow}"))
			fi
		else
			nextcore=${core}
		fi
	fi

	samquiet " Selected core: \e[1m${nextcore^^}\e[0m"

	local DIR=$(echo $(realpath -s --canonicalize-missing "${CORE_PATH_FINAL[${nextcore}]}"))
	check_romlist ${nextcore} "${DIR}"

	if [ -z "${rompath}" ]; then
		core_error "${nextcore}" "${rompath}"
		return
	else
		if [ -f "${rompath}.sam" ]; then
			source "${rompath}.sam"
		fi
	fi

	romname=$(basename "${rompath}")

	# Sanity check that we have a valid rom in var
	extension="${romname##*.}"
	extlist=$(echo "${CORE_EXT[${nextcore}]}" | sed -e "s/,/ /g")
	if [ ! $(echo "${extlist}" | grep -i -w -q "${extension}" | echo $?) ]; then
		samquiet " Wrong Extension! \e[1m${extension^^}\e[0m"
		next_core "${nextcore}" "repeat"
		return
	fi

	# If there is an exclude list check it
	declare -n excludelist="${nextcore}exclude"
	if [ ${#excludelist[@]} -gt 0 ]; then
		for excluded in "${excludelist[@]}"; do
			if [ "${excluded}" == "${rompath}" ]; then
				samquiet " Excluded: ${rompath}, trying a different game.."
				awk -vLine="${rompath}" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} &&  mv --force ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
				next_core "${nextcore}" "repeat"
				return
			fi
		done
	fi

	if [ -f "${excludepath}/${nextcore}_excludelist.txt" ]; then
		samdebug " Found exclusion list for core ${nextcore}"
		cat "${excludepath}/${nextcore}_excludelist.txt" | while IFS=$'\n' read line; do
			if [ "${line}" != "\n" ]; then
				if [ "${line}" == "${rompath}" ]; then
					samquiet " Excluded by user: ${rompath}, trying a different game.."
					awk -vLine="${rompath}" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} &&  mv --force ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
					return 1
				fi
			fi
		done
		[ $? -eq 1 ] && next_core "${nextcore}" "repeat" && return
	fi

	#Check blacklist
	if [ -f "${excludepath}/${nextcore}_blacklist.txt" ]; then
		samdebug " Found exclusion list for core ${nextcore}"
		cat "${excludepath}/${nextcore}_blacklist.txt" | while IFS=$'\n' read line; do
			if [ "${line}" != "\n" ]; then
				if [[ "${rompath}" == *"${line}"* ]]; then
					samquiet " Blacklisted because duplicate or boring: ${rompath}, trying a different game.."
					awk -vLine="${rompath}" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} &&  mv --force ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
					return 1
				fi
			fi
		done
		[ $? -eq 1 ] && next_core "${nextcore}" "repeat" && return
	fi

	corelist_count=$(echo $(wc -w <<<"${corelist_allow}"))
	samdebug " corelist:    ${corelist_allow}!"
	samdebug " corelisttmp: ${corelist_allowtmp}!"
	samdebug " corelist count is ${corelist_count} at end of next_core()"

	load_core "${nextcore}" "${rompath}" "${romname%.*}" "${countdown}"
}

function load_core() { # load_core core /path/to/rom name_of_rom (countdown)
	local core=${1}
	local rompath=${2}
	local romname=${3}
	local countdown=${4}
	GAMENAME=""
	if [ "${core}" == "neogeo" ] && [ "${useneogeotitles}" == "yes" ]; then
		if [ ${neogeoregion} == "english" ]; then
			GAMENAME="${NEOGEO_PRETTY_ENGLISH[${romname}]}"
		elif [ ${neogeoregion} == "japanese" ]; then
			GAMENAME="${NEOGEO_PRETTY_JAPANESE[${romname}]}"
			[[ -z "${GAMENAME}" ]] && GAMENAME="${NEOGEO_PRETTY_ENGLISH[${romname}]}"
		fi
	fi
	if [ -z "${GAMENAME}" ]; then
		GAMENAME="${romname}"
	fi

	if [ ${core} == "arcade" ]; then
		tty_corename=$(grep "<setname>" "${rompath}" | sed -e 's/<setname>//' -e 's/<\/setname>//' | tr -cd '[:alnum:]')
	else
		tty_corename="${TTY2OLED_PIC_NAME[${core}]}"
	fi

	if [ ${core} == "amiga" ]; then
		GAMENAME=$(echo "${GAMENAME}" | tr '_' ' ')
	fi

	echo -n " Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${core}]}\e[0m: "
	echo -e "\e[1m${GAMENAME}\e[0m"
	local date=$(date '+%H:%M:%S')
	if [ "${core}" == "neogeo" ] && [ "${useneogeotitles}" == "yes" ]; then
		echo "${date} - ${core} - ${romname} (${GAMENAME})" >>"/tmp/SAM_Games.log"
	else
		echo "${date} - ${core} - ${romname}" >>"/tmp/SAM_Games.log"
	fi
	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			[core_pretty]="${CORE_PRETTY[${core}]}"
			[name]="${GAMENAME}"
			[core]=${tty_corename}
			[counter]=${gametimer}
			[name_scroll]="${GAMENAME:0:21}"
			[name_scroll_position]=0
			[name_scroll_direction]=1
			[update_pause]=${ttyupdate_pause}
		)
		write_to_TTY_cmd_pipe "display_info $(declare -p tty_currentinfo)" &
	fi

	if [ ${core} != "arcade" ]; then
		mute "${CORE_LAUNCH[${core}]}"
	else
		mute "${tty_corename}"
	fi

	if [ "${countdown}" == "countdown" ]; then
		for i in {5..1}; do
			echo -ne " Loading game in ${i}...\033[0K\r"
			sleep 1
		done
	fi

	if [ ${core} == "arcade" ]; then
		file_to_load="${rompath}"
		# Tell MiSTer to load the next MRA
	else
		if [ ${core} == "amiga" ]; then
			if [ ! -f "${CORE_PATH_FINAL[${core}]}/MegaAGS.hdf" ]; then
				echo " ERROR - MegaAGS Pack not found in Amiga folder."
				next_core "${core}"
				return
			fi
			if [ -s "${CORE_PATH_FINAL[${core}]}/listings/games.txt" ]; then
				# This is for MegaAGS version July 2022 or newer
				# Special case for demo
				if [[ "${rompath}" == *"Demo:"* ]]; then
					rompath=${rompath//Demo: /}
				fi
				# [[ $(mount | grep -ic ${amigashared}) != "0" ]] &&
				echo "${rompath}" >${amigashared}/ags_boot
				echo "${rompath}" >${CORE_PATH_FINAL[${core}]}/shared/ags_boot
			fi
		fi
		file_to_load="/tmp/SAM_game.mgl"
		# Create mgl file and launch game

		echo "<mistergamedescription>" >${file_to_load}
		echo "<rbf>${CORE_PATH_RBF[${core}]}/${MGL_CORE[${core}]}</rbf>" >>${file_to_load}

		if [ ${usedefaultpaths} == "yes" ] || [ ${core} == "amiga" ]; then
			corepath="${CORE_PATH[${core}]}/"
			rompath="${rompath#${corepath}}"
			echo "<file delay="${MGL_DELAY[${core}]}" type="${MGL_TYPE[${core}]}" index="${MGL_INDEX[${core}]}" path="\"${rompath}\""/>" >>${file_to_load}
		else
			echo "<file delay="${MGL_DELAY[${core}]}" type="${MGL_TYPE[${core}]}" index="${MGL_INDEX[${core}]}" path="\"../../../..${rompath}\""/>" >>${file_to_load}
		fi

		echo "</mistergamedescription>" >>${file_to_load}
	fi

	# check for case of config files
	if [ "${core}" == "arcade" ]; then
		name=${tty_corename}
	else
		name=${CORE_LAUNCH[${core}]}
	fi
	shopt -s nullglob
	if [ "${name}" != ${name,,} ]; then
		for f in ${mrsamtmp}/SAM_config/${name,,}*; do
			 mv --force "${f}" "${f//${name,,}/${name}}"
		done
	fi
	shopt -u nullglob

	echo "load_core ${file_to_load}" >/dev/MiSTer_cmd
	if [ "${skipmessage}" == "yes" ] && [ "${CORE_SKIP[${core}]}" == "yes" ]; then
		skipmessage "${core}" "${rompath}" &
	fi
}

# ========= MAIN =========
function main() {
	if [ ${#} -eq 0 ]; then # No options - show the pre-menu
		startup_tasks
		init_data # Setup data arrays
		sam_premenu
	elif [ ${#} -gt 2 ]; then # We don't accept more than 2 parameters
		sam_help
	else
		while [ ${#} -gt 0 ]; do
			case "${1,,}" in
			stop | quit | exit)
				write_to_SAM_cmd_pipe ${1-}
				break
				;;
			skip | next)
				echo " Skipping to next game..."
				write_to_SAM_cmd_pipe ${1-}
				break
				;;
			ban | exclude)
				echo " Excluding the current game and Skipping to next game..."
				write_to_SAM_cmd_pipe ${1-}
				break
				;;
			fakegameslog)
				echo " Creating Fake SAM_Games.log..."
				write_to_SAM_cmd_pipe ${1-}
				break
				;;
			samdebug | debug)
				if [ ! -z "${2}" ] && ([ "${2,,}" == "yes" ] || [ "${2,,}" == "no" ]); then
					echo " Toggling ${1,,} to ${2,,}..."
					write_to_SAM_cmd_pipe ${1-,,}
				else
					echo " Toggling ${1,,} ..."
					write_to_SAM_cmd_pipe "${1,,}" "toggle"
				fi
				break
				;;
			samquiet | quiet)
				if [ ! -z "${2}" ] && ([ "${2,,}" == "no" ] || [ "${2,,}" == "yes" ]); then
					echo " Toggling ${1,,} to ${2,,}..."
					write_to_SAM_cmd_pipe ${1-,,}
				else
					echo " Toggling ${1,,} ..."
					write_to_SAM_cmd_pipe "${1,,}" "toggle"
				fi
				break
				;;
			monitor)
				sam_monitor_new
				break
				;;
			install) # Enable SAM autoplay mode
				startup_tasks
				sam_install
				break
				;;
			uninstall) # Disable SAM autoplay
				startup_tasks
				sam_uninstall
				break
				;;
			speedtest)
				startup_tasks
				init_data # Setup data arrays
				speedtest
				break
				;;
			create-gamelists)
				startup_tasks
				init_data # Setup data arrays
				creategl
				break
				;;
			delete-gamelists)
				startup_tasks
				init_data # Setup data arrays
				deletegl
				break
				;;
			default) # sam_update relaunches itself
				startup_tasks
				sam_update autoconfig
				break
				;;
			update) # Update SAM
				startup_tasks
				sam_update
				break
				;;
			autoconfig)
				tmux kill-session -t MCP &>/dev/null
				there_can_be_only_one
				startup_tasks
				sam_update
				sam_install
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
				break
				;;
			esac

			startup_tasks
			init_data # Setup data arrays
			sam_prep

			bgm_start
			if [ ${create_all_gamelists} == "yes" ]; then
				echo " Checking Gamelists"
				create_game_lists
			fi

			if [ "${samtrace}" == "yes" ]; then
				debug_output
			fi

			case "${1,,}" in
			amiga | arcade | atari2600 | atari5200 | atari7800 | atarilynx | c64 | fds | gb | gbc | gba | genesis | gg | megacd | neogeo | nes | s32x | sms | snes | tgfx16 | tgfx16cd | psx)
				# If we're given a core name then we need to set it first
				if [ ! -z "${2}" ] && [ "${2,,}" == "start_real" ]; then
					declare -gl corelist_allow=${1}
					declare -gl nextcore=${1}
					sam_start_new
				else
					declare -gl corelist_allow=${1}
					declare -gl nextcore=${1}
					sam_start ${nextcore}
				fi
				break
				;;
			stop | quit)
				${mrsampath}/SuperAttract_init "stop" &
				jobs -l
				disown -a
				break
				;;
			start) # quickstart
				env_check
				${mrsampath}/SuperAttract_init "quickstart" &
				jobs -l
				disown -a
				break
				;;
			restart) # stop everything and restart
				env_check
				${mrsampath}/SuperAttract_init "restart" &
				jobs -l
				disown -a
				break
				;;
			start_real) # Start looping
				declare -gl corelist_allow=$(echo "${corelist}"  | tr ',' ' ' | tr -d '[:cntrl:]' | awk '{$2=$2};1')
				sam_start_new
				break
				;;
			startmonitor)
				declare -gl corelist_allow=$(echo "${corelist}"  | tr ',' ' ' | tr -d '[:cntrl:]' | awk '{$2=$2};1')
				sam_start_new
				sam_monitor_new
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
			bgm)
				sam_bgmmenu
				break
				;;
			*)
				echo " ERROR! ${1} is unknown."
				echo " Try $(basename -- ${0}) help"
				echo " Or check the Github readme."
				echo "main"
				break
				;;
			esac
		done
	fi
}

if [ "${1,,}" == "--source-only" ]; then
	startup_tasks
	init_data # Setup data arrays
else
	main ${@}
fi