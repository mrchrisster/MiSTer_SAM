#!/bin/bash

# https://github.com/mrchrisster/MiSTer_SAM/
# Copyright (c) 2023 by mrchrisster and Mellified

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
# Script layout & watchdog functionality: Mellified 
# tty2oled submodule: Paradox
# Indexing tool: wizzomafizzo
#
# Thanks for the contributions and support:
# pocomane, kaloun34, redsteakraw, RetroDriven, woelper, LamerDeluxe, InquisitiveCoder, Sigismond, theypsilon
# tty2oled improvements by venice

# TODO implement playcurrentgame for amiga
# SAM is immune to the signal sent when detaching from tmux
trap '' SIGHUP

# ======== INI VARIABLES ========
# Change these in the INI file
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


	# ======== CORE PATHS RBF ========
	declare -g amigapathrbf="_Computer"
	declare -g amigacd32pathrbf="_Computer"
	declare -g arcadepathrbf="_Arcade"
	declare -g ao486pathrbf="_Computer"
	declare -g atari2600pathrbf="_Console"
	declare -g atari5200pathrbf="_Console"
	declare -g atari7800pathrbf="_Console"
	declare -g atarilynxpathrbf="_Console"
	declare -g c64pathrbf="_Computer"
	declare -g cdipathrbf="_Console"	
	declare -g coco2pathrbf="_Computer"
	declare -g fdspathrbf="_Console"
	declare -g gbpathrbf="_Console"
	declare -g gbcpathrbf="_Console"
	declare -g gbapathrbf="_Console"
	declare -g genesispathrbf="_Console"
	declare -g ggpathrbf="_Console"
	declare -g jaguarpathrbf="_Console"
	declare -g megacdpathrbf="_Console"
	declare -g n64pathrbf="_Console"
	declare -g neogeopathrbf="_Console"
	declare -g neogeocdpathrbf="_Console"
	declare -g nespathrbf="_Console"
	declare -g s32xpathrbf="_Console"
	declare -g saturnpathrbf="_Console"
	declare -g sgbpathrbf="_Console"
	declare -g smspathrbf="_Console"
	declare -g snespathrbf="_Console"
	declare -g stvpathrbf="_Arcade"
	declare -g tgfx16pathrbf="_Console"
	declare -g tgfx16cdpathrbf="_Console"
	declare -g psxpathrbf="_Console"
	declare -g x68kpathrbf="_Computer"
	
	
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

# ======== CORE CONFIG ========
function init_data() {
	# Core to long name mappings
	declare -gA CORE_PRETTY=(
		["amiga"]="Commodore Amiga"
		["arcade"]="MiSTer Arcade"
		["amigacd32"]="Commodore Amiga CD32"
		["ao486"]="PC 486 DX-100"
		["atari2600"]="Atari 2600"
		["atari5200"]="Atari 5200"
		["atari7800"]="Atari 7800"
		["atarilynx"]="Atari Lynx"
		["c64"]="Commodore 64"
		["cdi"]="Philips CD-i"
		["coco2"]="TRS-80 Color Computer 2"
		["fds"]="Nintendo Disk System"
		["gb"]="Nintendo Game Boy"
		["gbc"]="Nintendo Game Boy Color"
		["gba"]="Nintendo Game Boy Advance"
		["genesis"]="Sega Genesis / Megadrive"
		["gg"]="Sega Game Gear"
		["jaguar"]="Atari Jaguar"
		["megacd"]="Sega CD / Mega CD"
		["n64"]="Nintendo N64"
		["neogeo"]="SNK NeoGeo"
		["neogeocd"]="SNK NeoGeo CD"
		["nes"]="Nintendo Entertainment System"
		["s32x"]="Sega 32x"
		["saturn"]="Sega Saturn"
		["sgb"]="Super Gameboy"		
		["sms"]="Sega Master System"
		["snes"]="Super Nintendo"
		["stv"]="Sega Titan Video"
		["tgfx16"]="NEC TurboGrafx-16 "
		["tgfx16cd"]="NEC TurboGrafx-16 CD"
		["psx"]="Sony Playstation"
		["x68k"]="Sharp X68000"
	)

	# Core to file extension mappings
	declare -glA CORE_EXT=(
		["amiga"]="hdf" 			#This is just a placeholder
		["amigacd32"]="chd,cue" 
		["ao486"]="vhd"		#This is just a placeholder
		["arcade"]="mra"
		["atari2600"]="a26"     
		["atari5200"]="a52,car" 
		["atari7800"]="a78"     
		["atarilynx"]="lnx"		 
		["c64"]="crt,prg" 		# need to be tested "reu,tap,flt,rom,c1581"
		["cdi"]="chd,cue"	
		["coco2"]="ccc"
		["fds"]="fds"
		["gb"]="gb"			 		
		["gbc"]="gbc"		 		
		["gba"]="gba"
		["genesis"]="md,gen" 		
		["gg"]="gg"
		["jaguar"]="j64,rom,bin,jag"
		["megacd"]="chd,cue"
		["n64"]="n64,z64"
		["neogeo"]="neo"
		["neogeocd"]="cue,chd"
		["nes"]="nes"
		["s32x"]="32x"
		["saturn"]="cue,chd"
		["sgb"]="gb,gbc" 
		["sms"]="sms,sg"
		["snes"]="sfc,smc" 	 	# Should we include? "bin,bs"
		["tgfx16"]="pce,sgx"		
		["tgfx16cd"]="chd,cue"
		["psx"]="chd,cue,exe"
		["x68k"]="vhd"		#This is just a placeholder
	)
	
	# Core to path mappings
	declare -gA PATHFILTER=(
		["amiga"]="${amigapathfilter}"
		["amigacd32"]="${amigacd32pathfilter}"
		["ao486"]="${ao486pathfilter}"
		["arcade"]="${arcadepathfilter}"
		["atari2600"]="${atari2600pathfilter}"
		["atari5200"]="${atari5200pathfilter}"
		["atari7800"]="${atari7800pathfilter}"
		["atarilynx"]="${atarilynxpathfilter}"				  
		["c64"]="${c64pathfilter}"
		["cdi"]="${cdipathfilter}"
		["coco2"]="${coco2pathfilter}"
		["fds"]="${fdspathfilter}"
		["gb"]="${gbpathfilter}"
		["gbc"]="${gbcpathfilter}"
		["gba"]="${gbapathfilter}"
		["genesis"]="${genesispathfilter}"
		["gg"]="${ggpathfilter}"
		["jaguar"]="${jaguarpathfilter}"
		["megacd"]="${megacdpathfilter}"
		["n64"]="${n64pathfilter}"
		["neogeo"]="${neogeopathfilter}"
		["neogeocd"]="${neogeocdpathfilter}"
		["nes"]="${nespathfilter}"
		["s32x"]="${s32xpathfilter}"
		["saturn"]="${saturnpathfilter}"
		["sgb"]="${sgbpathfilter}"
		["sms"]="${smspathfilter}"
		["snes"]="${snespathfilter}"
		["stv"]="${stvpathfilter}"
		["tgfx16"]="${tgfx16pathfilter}"
		["tgfx16cd"]="${tgfx16cdpathfilter}"
		["psx"]="${psxpathfilter}"
		["x68k"]="${x68kpathfilter}"
	)


	# Core to path mappings for rbf files
	declare -gA CORE_PATH_RBF=(
		["amiga"]="${amigapathrbf}"
		["amigacd32"]="${amigacd32pathrbf}"
		["ao486"]="${ao486pathrbf}"
		["arcade"]="${arcadepathrbf}"
		["atari2600"]="${atari2600pathrbf}"
		["atari5200"]="${atari5200pathrbf}"
		["atari7800"]="${atari7800pathrbf}"
		["atarilynx"]="${atarilynxpathrbf}"					 
		["c64"]="${c64pathrbf}"
		["cdi"]="${cdipathrbf}"
		["coco2"]="${coco2pathrbf}"
		["fds"]="${fdspathrbf}"
		["gb"]="${gbpathrbf}"
		["gbc"]="${gbcpathrbf}"
		["gba"]="${gbapathrbf}"
		["genesis"]="${genesispathrbf}"
		["gg"]="${ggpathrbf}"
		["jaguar"]="${jaguarpathrbf}"
		["megacd"]="${megacdpathrbf}"
		["n64"]="${n64pathrbf}"
		["neogeo"]="${neogeopathrbf}"
		["neogeocd"]="${neogeocdpathrbf}"
		["nes"]="${nespathrbf}"
		["s32x"]="${s32xpathrbf}"
		["saturn"]="${saturnpathrbf}"
		["sgb"]="${sgbpathrbf}"
		["sms"]="${smspathrbf}"
		["snes"]="${snespathrbf}"
		["stv"]="${stvpathrbf}"
		["tgfx16"]="${tgfx16pathrbf}"
		["tgfx16cd"]="${tgfx16cdpathrbf}"
		["psx"]="${psxpathrbf}"
		["x68k"]="${x68kpathrbf}"
	)

	# Can this core skip Bios/Safety warning messages
	declare -glA CORE_SKIP=(
		["amiga"]="No"
		["amigacd32"]="Yes"
		["ao486"]="No"
		["arcade"]="No"
		["atari2600"]="No"
		["atari5200"]="No"
		["atari7800"]="No"
		["atarilynx"]="No"		
		["c64"]="No"
		["cdi"]="No"
		["coco2"]="No"
		["fds"]="Yes"
		["gb"]="No"
		["gbc"]="No"
		["gba"]="No"
		["genesis"]="No"
		["gg"]="No"
		["jaguar"]="No"
		["megacd"]="Yes"
		["n64"]="No"
		["neogeo"]="No"
		["neogeocd"]="Yes"
		["nes"]="No"
		["s32x"]="No"
		["saturn"]="Yes"
		["sgb"]="No"
		["sms"]="No"
		["snes"]="No"
		["stv"]="No"
		["tgfx16"]="No"
		["tgfx16cd"]="Yes"
		["psx"]="No"
		["x68k"]="No"
	)
	

	# Core to input maps mapping
	declare -gA CORE_LAUNCH=(
		["amiga"]="Minimig"
		["amigacd32"]="Minimig"
		["ao486"]="ao486"
		["arcade"]="Arcade"
		["atari2600"]="ATARI7800"
		["atari5200"]="ATARI5200"
		["atari7800"]="ATARI7800"
		["atarilynx"]="AtariLynx"
		["c64"]="C64"
		["cdi"]="CDi"
		["coco2"]="CoCo2"
		["fds"]="NES"
		["gb"]="GAMEBOY"
		["gbc"]="GAMEBOY"
		["gba"]="GBA"
		["genesis"]="MEGADRIVE"
		["gg"]="SMS"
		["jaguar"]="Jaguar"
		["megacd"]="MegaCD"
		["n64"]="N64"
		["neogeo"]="NEOGEO"
		["neogeocd"]="NEOGEO"
		["nes"]="NES"
		["s32x"]="S32X"
		["saturn"]="SATURN"
		["sgb"]="SGB"
		["sms"]="SMS"
		["snes"]="SNES"
		["stv"]="S-TV"
		["tgfx16"]="TGFX16"
		["tgfx16cd"]="TGFX16"
		["psx"]="PSX"
		["x68k"]="X68000"
	)
	
	# TTY2OLED Core Pic mappings
	declare -gA TTY2OLED_PIC_NAME=(
		["amiga"]="Minimig"
		["amigacd32"]="Minimig"
		["ao486"]="ao486"
		["arcade"]="Arcade"
		["atari2600"]="ATARI2600"
		["atari5200"]="ATARI5200"
		["atari7800"]="ATARI7800"
		["atarilynx"]="AtariLynx"
		["c64"]="C64"
		["cdi"]="CD-i"
		["coco2"]="CoCo2"
		["fds"]="fds"
		["gb"]="GAMEBOY"
		["gbc"]="GAMEBOY"
		["gba"]="GBA"
		["genesis"]="Genesis"
		["gg"]="gamegear"
		["jaguar"]="Jaguar"
		["megacd"]="MegaCD"
		["n64"]="N64"
		["neogeo"]="NEOGEO"
		["neogeocd"]="NEOGEO"
		["nes"]="NES"
		["s32x"]="S32X"
		["saturn"]="SATURN"
		["sgb"]="SGB"
		["sms"]="SMS"
		["snes"]="SNES"
		["stv"]="S-TV"
		["tgfx16"]="TGFX16"
		["tgfx16cd"]="TGFX16"
		["psx"]="PSX"
		["x68k"]="X68000"
	)

	# MGL core name settings
	declare -gA MGL_CORE=(
		["amiga"]="Minimig"
		["amigacd32"]="Minimig"
		["ao486"]="ao486"
		["arcade"]="Arcade"
		["atari2600"]="ATARI7800"
		["atari5200"]="ATARI5200"
		["atari7800"]="ATARI7800"
		["atarilynx"]="AtariLynx"		   
		["c64"]="C64"
		["cdi"]="CDi"
		["coco2"]="CoCo2"
		["fds"]="NES"
		["gb"]="GAMEBOY"
		["gbc"]="GAMEBOY"
		["gba"]="GBA"
		["genesis"]="MegaDrive"
		["gg"]="SMS"
		["jaguar"]="Jaguar"
		["megacd"]="MegaCD"
		["n64"]="N64"
		["neogeo"]="NEOGEO"
		["neogeocd"]="NEOGEO"
		["nes"]="NES"
		["s32x"]="S32X"
		["saturn"]="SATURN"
		["sgb"]="SGB"
		["sms"]="SMS"
		["snes"]="SNES"
		["stv"]="S-TV"
		["tgfx16"]="TurboGrafx16"
		["tgfx16cd"]="TurboGrafx16"
		["psx"]="PSX"
		["x68k"]="X68000"
	)

	# MGL setname settings
	declare -gA MGL_SETNAME=(
		["amigacd32"]="AmigaCD32"
		["gbc"]="GBC"
		["gg"]="GameGear"
	)

	# MGL delay settings
	declare -giA MGL_DELAY=(
		["amiga"]="1"
		["amigacd32"]="1"
		["ao486"]="0"
		["arcade"]="2"
		["atari2600"]="1"
		["atari5200"]="1"
		["atari7800"]="1"
		["atarilynx"]="1"
		["c64"]="1"
		["cdi"]="1"
		["coco2"]="1"
		["fds"]="2"
		["gb"]="2"
		["gbc"]="2"
		["gba"]="2"
		["genesis"]="1"
		["gg"]="1"
		["jaguar"]="1"
		["megacd"]="1"
		["n64"]="1"
		["neogeo"]="1"
		["neogeocd"]="1"
		["nes"]="2"
		["s32x"]="1"
		["saturn"]="1"
		["sgb"]="1"
		["sms"]="1"
		["snes"]="2"
		["stv"]="2"
		["tgfx16"]="1"
		["tgfx16cd"]="1"
		["psx"]="1"
		["x68k"]="1"

	)

	# MGL index settings
	declare -giA MGL_INDEX=(
		["amiga"]="0"
		["amigacd32"]="0"
		["ao486"]="2"
		["arcade"]="0"
		["atari2600"]="0"
		["atari5200"]="1"
		["atari7800"]="1"
		["atarilynx"]="1"   
		["c64"]="1"
		["cdi"]="1"
		["coco2"]="1"
		["fds"]="0"
		["gb"]="0"
		["gbc"]="0"
		["gba"]="0"
		["genesis"]="0"
		["gg"]="2"
		["jaguar"]="1"
		["megacd"]="0"
		["n64"]="1"
		["neogeo"]="1"
		["neogeocd"]="1"
		["nes"]="0"
		["s32x"]="0"
		["saturn"]="1"
		["sgb"]="1"
		["sms"]="1"
		["snes"]="0"
		["stv"]="0"
		["tgfx16"]="1"
		["tgfx16cd"]="0"
		["psx"]="1"
		["x68k"]="2"
	)

	# MGL type settings
	declare -glA MGL_TYPE=(
		["amiga"]="f"
		["amigacd32"]="f"
		["ao486"]="s"
		["arcade"]="f"
		["atari2600"]="f"
		["atari5200"]="f"
		["atari7800"]="f"
		["atarilynx"]="f"
		["c64"]="f"
		["cdi"]="s"
		["coco2"]="f"
		["fds"]="f"
		["gb"]="f"
		["gbc"]="f"
		["gba"]="f"
		["genesis"]="f"
		["gg"]="f"
		["jaguar"]="f"
		["megacd"]="s"
		["n64"]="f"
		["neogeo"]="f"
		["neogeocd"]="s"
		["nes"]="f"
		["s32x"]="f"
		["saturn"]="s"
		["sgb"]="f"
		["sms"]="f"
		["snes"]="f"
		["stv"]="f"
		["tgfx16"]="f"
		["tgfx16cd"]="s"
		["psx"]="s"
		["x68k"]="s"
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
	
	declare -glA SV_TVC=(
		["gb"]="gb\|game boy"
		["gbc"]="gb\|game boy"
		["genesis"]="genesis"
		["megacd"]="megacd"
		["nes"]="^nes-\| nes"
		["snes"]="snes"
		["n64"]="n64-\|n64"
		["atari2600"]="atari vcs"
		["atari5200"]="atari 5200"
		["atari7800"]="atari 7800"
		["atarilynx"]="atari lynx"
		["saturn"]="sega saturn"
		["s32x"]="sega 32x"
		["sgb"]="super game boy\|gb-super game boy\|snes-super game boy"
		["tgfx16cd"]="turboduo"
		["tgfx16"]="turboduo\|turbografx-16"
		["gg"]="sega game"
		["sms"]="sega master"
		["psx"]="psx\|playstation"
		["arcade"]="arcade"
	)

	RATED_FILES=(
	  n64_mature.txt
	  saturn_mature.txt
	  tgfx16cd_mature.txt
	  arcade_rated.txt
	  amiga_rated.txt
	  ao486_rated.txt
	  fds_rated.txt
	  gb_rated.txt
	  gbc_rated.txt
	  gba_rated.txt
	  gg_rated.txt
	  genesis_rated.txt
	  megacd_rated.txt
	  n64_rated.txt
	  nes_rated.txt
	  neogeo_rated.txt
	  psx_rated.txt
	  sms_rated.txt
	  snes_rated.txt
	  tgfx16_rated.txt
	  tgfx16cd_rated.txt
	)

	# All blacklist files
	BLACKLIST_FILES=(
	  amiga_blacklist.txt
	  arcade_blacklist.txt
	  fds_blacklist.txt
	  gba_blacklist.txt
	  genesis_blacklist.txt
	  megacd_blacklist.txt
	  n64_blacklist.txt
	  nes_blacklist.txt
	  neogeo_blacklist.txt
	  psx_blacklist.txt
	  s32x_blacklist.txt
	  sms_blacklist.txt
	  snes_blacklist.txt
	  tgfx16_blacklist.txt
	  tgfx16cd_blacklist.txt
	)

}



# ========= SOUCRCE INI & UPDATE =========

# Read INI
function read_samini() {
	if [ ! -f "${samini_file}" ]; then
		echo "Error: MiSTer_SAM.ini not found. Attempting to update now..."
		get_samstuff MiSTer_SAM.ini /media/fat/Scripts
		if [ $? -ne 0 ]; then 
			echo "Error: Please try again or update MiSTer_SAM.ini manually."
			exit 1
		fi
	fi
	source "${samini_file}"
	
	# Remove trailing slash from paths
	grep "^[^#;]" < "${samini_file}" | grep "pathfilter=" | cut -f1 -d"=" | while IFS= read -r var; do
		declare -g "${var}"="${!var%/}"
	done
	
	#corelist=("$(echo "${corelist[@]}" | tr ',' ' ' | tr -s ' ')")
	IFS=',' read -ra corelist <<< "${corelist}"
	IFS=',' read -ra corelistall <<< "${corelistall}"
	
	#BGM mode
	if [ "${bgm}" == "yes" ]; then
		# delete n64 and psx
		# echo "Deleting N64 and PSX from corelist"
		new_corelist=()
		for core in "${corelist[@]}"; do
			if [[ "$core" != "n64" && "$core" != "psx" ]]; then
				new_corelist+=("$core")
			fi
		done

		corelist=("${new_corelist[@]}")
		mute="core"
	fi
	
	#Roulette Mode
	if [ -f /tmp/.SAM_tmp/gameroulette.ini ]; then
		source /tmp/.SAM_tmp/gameroulette.ini
	fi
	
	#GOAT Mode
	if [ "$sam_goat_list" == "yes" ]; then
		build_goat_lists
	fi

	#NES M82 Mode
	if [ "$m82" == "yes" ]; then	
		build_m82_list
	fi
	
}


function update_samini() {
	[ ! -f /media/fat/Scripts/.config/downloader/downloader.log ] && return
	[ ! -f ${samini_file} ] && return
	if [[ "$(cat /media/fat/Scripts/.config/downloader/downloader.log | grep -c "MiSTer_SAM.default.ini")" != "0" ]] && [ "${samini_update_file}" -nt "${samini_file}" ]; then
		echo "New MiSTer_SAM.ini version downloaded from update_all. Merging with new ini."
		echo "Backing up MiSTer_SAM.ini to MiSTer_SAM.ini.bak"
		cp "${samini_file}" "${samini_file}".bak
		echo -n "Merging ini values.."
		# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
		sed -i 's/==/--/g' "${samini_file}"
		sed -i 's/-=/--/g' "${samini_file}"
		awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' "${samini_file}" "${samini_update_file}" >/tmp/MiSTer_SAM.tmp && cp -f --force /tmp/MiSTer_SAM.tmp "${samini_file}"
		echo "Done."
	fi

}

# ============== PARSE COMMANDS ===============


function parse_cmd() {
  # 1) No args ⇒ show the pre-menu
  (( $# == 0 )) && { sam_premenu; return; }

  # 2) Normalize
  local first="${1,,}"
  shift

  # 3) Single core shorthand
  if [[ -n ${CORE_PRETTY[$first]} ]]; then
    tmp_reset
    echo $first > "${corelistfile}.single"
    echo "${CORE_PRETTY[$first]} selected!"
    sam_start "$first"
    return
  fi

  # 4) Built-in commands (now with explicit menu handling)
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
    
    default)            sam_update autoconfig ;;
    autoconfig|defaultb)
                        tmux kill-session -t MCP &>/dev/null
                        there_can_be_only_one
                        sam_update; mcp_start; sam_enable
                        ;;
    bootstart)          env_check bootstart; boot_sleep; mcp_start ;;
    loop_core)          loop_core ;;
    
    menu|back)          sam_menu ;;
    help)               sam_help ;;
    sshconfig)          sam_sshconfig ;;
    
    menu_*)
		# Check if the function is actually defined before trying to run it
		if declare -F "$first" > /dev/null; then
		"$first" "$@"
		else
		echo "Error: Unknown menu function '$first'" >&2
		sam_help
		return 1
		fi
		;;   
    *)
		# Otherwise unknown (the old catch-all is now just for errors)
		echo "Unknown command: $first" >&2
		sam_help
		return 1
		;;
  esac
}




# ======== SAM MENU ========
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

    # If it was a “playback” command, exit the menu loop
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



# ======== SAM OPERATIONAL FUNCTIONS ========


function loop_core() { # loop_core (optional_core_name)
	echo -e "Starting Super Attract Mode...\nLet Mortal Kombat begin!\n"
	# Reset game log for this session
	echo "" >/tmp/SAM_Games.log
	samdebug "Initial corelist: ${corelist[*]}"

	# This is the main script loop that runs forever.
	while :; do
		# ----------------------------------------------------
		# Call next_core to attempt a game launch.
		# We pass along any argument that might have been given to loop_core.
		next_core "${1-}" 
		
		# Check the exit code of the next_core function.
		if [ $? -eq 0 ]; then
			# SUCCESS (Exit code 0): A game was launched successfully.
			# Now, we start the countdown timer before the next game.
			run_countdown_timer
		else
			# We immediately loop again to try the next core without waiting.
			echo "Core launch failed."
			# Blacklist the core and bail out of this launch attempt.
			echo "ERROR: Failed ${romloadfails} times. No valid game found for core: ${nextcore}"
			echo "ERROR: Core ${nextcore} is blacklisted!"
			delete_from_corelist "${nextcore}"
			echo "List of cores is now: ${corelist[*]}"
			echo "Trying the next available core..."
			continue
		fi
		# ----------------------------------------------------
	done
}

function run_countdown_timer() {
    local counter=${gametimer}
    
    # Set a local trap to handle Ctrl+C during the countdown, allowing a graceful skip.
    trap 'echo; return' INT

    while [ ${counter} -gt 0 ]; do
        # Only show game counter when samvideo is not active
        if [ "${samvideo}" == "yes" ] && [ "$sv_nextcore" == "samvideo" ]; then
            if [ -f "$sv_gametimer_file" ]; then
                counter=$(cat "$sv_gametimer_file")	
                rm "$sv_gametimer_file" 2>/dev/null
            fi
        else
            echo -ne " Next game in ${counter}...\033[0K\r"
        fi

        sleep 1
        ((counter--))
        
        # --- Activity Checks ---
        # NOTE: This section could also be refactored into a helper function
        # to make the countdown loop even cleaner.
        if [ -s "$mouse_activity_file" ] && [ "${listenmouse}" == "yes" ]; then
            echo "Mouse activity detected!"
            truncate -s 0 "$mouse_activity_file"
            play_or_exit &
            return # Exit the countdown
        fi

        if [ -s "$key_activity_file" ] && [ "${listenkeyboard}" == "yes" ]; then
            echo "Keyboard activity detected!"
            truncate -s 0 "$key_activity_file"
            play_or_exit &
            return # Exit the countdown
        fi

        if [ -s "$joy_activity_file" ] && [ "${listenjoy}" == "yes" ]; then
            handle_joy_activity # Call a new helper for joystick logic
            if [ $? -eq 1 ]; then # Check if handle_joy_activity wants to break the loop
                return
            fi
        fi
    done

    # Restore the default INT trap once the countdown is over.
    trap - INT
}

# This new helper function cleans up the joystick logic.
function handle_joy_activity() {
    local joy_action
    joy_action=$(cat "$joy_activity_file")
    truncate -s 0 "$joy_activity_file"

    case "${joy_action}" in
        "Start")
            samdebug "Start button pushed. Exiting SAM."
            playcurrentgame="yes"
            play_or_exit &
            return 1 # Signal to exit countdown
            ;;
        "Next")
            echo "Starting next Game"
            if [[ "$ignore_when_skip" == "yes" ]]; then
                ignoregame
            fi
            # Returning 1 will break the countdown loop and let the main loop call next_core
            return 1
            ;;
        "zaparoo")
            echo "Zaparoo starting. SAM exiting"
            mute="yes"
            playcurrentgame="yes"
            play_or_exit &
            return 1 # Signal to exit countdown
            ;;
        *)
            # Default case for other joy activity
            play_or_exit &
            return 1 # Signal to exit countdown
            ;;
    esac
    return 0
}

# Pick a random core
function next_core() { # next_core (core)
	
	if [[ -n "$cfgcore_configpath" ]]; then
		configpath="$cfgcore_configpath"
	else
		configpath="/media/fat/config/"
	fi
	
	load_samvideo
	if [ $? -ne 0 ]; then sv_nextcore="samvideo" && return; fi
	
	if [[ ! ${corelist[*]} ]]; then
		echo "ERROR: FATAL - List of cores is empty."
		echo "Using default corelist"
		declare -ga corelist=("${corelistall[@]}")
		samdebug "Corelist is now ${corelist[*]}"
	fi

	# Pick a core if no corename was supplied as argument (eg "MiSTer_SAM_on.sh psx")
	if [ -z "${1}" ]; then
		corelist_update	
		create_all_gamelists
		if [ "$samvideo" == "yes" ] && [ "$samvideo_tvc" == "yes" ]; then
			nextcore=$(cat /tmp/.SAM_tmp/sv_core)
		else
			pick_core			
		fi
	fi	
	
	special_core_processor
	local scp_status=$?

	case $scp_status in
		1) # Special core was loaded successfully. We are done.
			samdebug "Loading complete of special core $nextcore"
			return 0
			;;
		2) # Special core prerequisite failed. We need to pick a new core and try again.
			samdebug "Loading failed of special core $nextcore"
			next_core
			return $? # Pass the exit code from the new call up the chain
			;;
	esac
	# If we get here, special_core_processor returned 0 → NOT handled, so we continue.
	
	
	check_list "${nextcore}"
	if [ $? -ne 0 ]; then
		samdebug "check_list function returned an error."
		return 1
	fi
	
	pick_rom
	
    declare -g romloadfails=0
    local rom_is_valid=false

    while [ ${romloadfails} -lt ${coreretries} ]; do
        # Call check_rom. It returns 0 on success.
        if check_rom "${nextcore}"; then
            # The ROM is valid! Mark as successful and break out of the loop.
            rom_is_valid=true
            break
        fi

        # If we are here, the ROM was invalid. Increment the failure counter.
        romloadfails=$((romloadfails + 1))

        # If we still have retries left, pick a new ROM to test on the next loop iteration.
        # The check_rom function may have rebuilt the list, so we need to pick again.
        if [ ${romloadfails} -lt ${coreretries} ]; then
            samdebug "ROM check failed. Picking a new ROM to try again (${romloadfails}/${coreretries})..."
            pick_rom
        fi
    done

    # After the loop, check if we ever found a valid ROM.
    if [ "$rom_is_valid" = "false" ]; then
        # All retries have been exhausted. No valid ROM was found.
        return 1
    fi
    
	# Check if new roms got added
	check_gamelistupdate ${nextcore} &
	
	delete_played_game
	
	load_core "${nextcore}" "${rompath}" "${romname%.*}"

	# Capture the exit code from load_core and return it.
	# This passes the success/failure signal up to the main loop.
	return $?
}
	

function load_samvideo() {
	sv_loadcounter=$((sv_loadcounter + 1))
	#Load the actual rom (or play a video)
	if [ "${samvideo}" == "yes" ]; then		
		if [ "${samvideo_freq}" == "only" ]; then
			activity_reset
			samvideo_play &
			return 1
		elif [ "${samvideo_freq}" == "core" ]; then
		  	echo "samvideo load core counter is now $sv_loadcounter"
		  	if ((sv_loadcounter % ${#corelist[@]} == 0)); then
				activity_reset
				samvideo_play &
				sv_loadcounter=0
				return 1
		  	fi
		  	sv_nextcore=""
		  	return 0

		elif [ "${samvideo_freq}" == "alternate" ]; then
			if ((sv_loadcounter % 2 == 1)); then
				activity_reset
				samvideo_play &
				return 1
		  	else
		  		sv_nextcore=""
				return 0
			fi
		fi
		
	fi

}

# Don't repeat same core twice
function corelist_update() {
	
	#Single Core Mode
	if [ -s "${corelistfile}.single" ]; then
		unset corelist
		mapfile -t corelist < "${corelistfile}.single"
		rm "${corelistfile}.single" "${corelistfile}" > /dev/null 2>&1
		
	elif [ -s "${corelistfile}" ]; then
		unset corelist
		mapfile -t corelist < "${corelistfile}"
		rm "${corelistfile}"
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





# ──────────────────────────────────────────────────────────────────────────────
# Main core picker
# ──────────────────────────────────────────────────────────────────────────────
function pick_core() {

    if [[ "$coreweight" == "yes" ]]; then
        pick_core_weighted

    elif [[ "$samvideo" == "yes" ]]; then
        pick_core_samvideo "$1"

    else
        pick_core_standard
    fi

    # fallback
    if [[ -z "$nextcore" ]]; then
        samdebug "nextcore empty. Using arcade core as fallback."
        nextcore="arcade"
    fi
}

# 1) Uniform random selection

function pick_core_standard() {
    nextcore=$(printf "%s\n" "${corelisttmp[@]}" \
               | shuf --random-source=/dev/urandom -n1)
    samdebug "Picked core (standard): $nextcore"
}

# 2) SAM-video mode (Weighted by _tvc.txt)

declare -A SAMVC        # tvc counts per core
SAMVTOTAL=0             # sum of all counts
SAMVIDEO_INIT_SENTINEL="/tmp/.SAM_tmp/samvideo_init"


function init_core_samvideo() {
    local arr_name=$1
    local core cnt tvc
    local -n arr_ref=$arr_name

    # always (re)load counts into SAMVC & SAMVTOTAL
    SAMVTOTAL=0
    if [[ -f "$core_count_file" ]]; then
        while IFS="=" read -r core cnt; do
            if [[ "$core" == total_count ]]; then
                SAMVTOTAL=$cnt
            else
                SAMVC["$core"]=$cnt
            fi
        done < "$core_count_file"
    else
        for core in "${arr_ref[@]}"; do
            tvc="${gamelistpath}/${core}_tvc.txt"
            cnt=0
            [[ -f "$tvc" ]] && cnt=$(jq -r 'keys|length' "$tvc" 2>/dev/null || echo 0)
            SAMVC["$core"]=$cnt
            (( SAMVTOTAL += cnt ))
        done

        mkdir -p "$(dirname "$core_count_file")"
        : > "$core_count_file"
        for core in "${!SAMVC[@]}"; do
            echo "$core=${SAMVC[$core]}" >> "$core_count_file"
        done
        echo "total_count=$SAMVTOTAL" >> "$core_count_file"
    fi

    # print table only once, guarded by sentinel
    if [[ ! -f "$SAMVIDEO_INIT_SENTINEL" ]]; then
        echo -e "\nCore      TVC-Entries   Percent"
        printf '%.0s─' {1..34}; echo
        for core in "${!SAMVC[@]}"; do
            cnt=${SAMVC[$core]}
            if (( SAMVTOTAL > 0 )); then
                pct=$(awk "BEGIN{printf \"%.2f\", ($cnt*100)/$SAMVTOTAL}")
            else
                pct="0.00"
            fi
            printf "%-8s %10d   %6s%%\n" "$core" "$cnt" "$pct"
        done | sort -k2 -nr
        echo "─────────────────────────────────────────────────────────────────────────────"

        # ensure sentinel directory exists and create sentinel
        mkdir -p "$(dirname "$SAMVIDEO_INIT_SENTINEL")"
        touch "$SAMVIDEO_INIT_SENTINEL"
    fi
}


function pick_core_samvideo() {
    local arr_name=$1
    local -n array=$arr_name

	init_core_samvideo "$arr_name" 

    # now do the weighted pick
    nextcore=$(pick_weighted_random SAMVC "$SAMVTOTAL")
    [[ -z "$nextcore" ]] && nextcore="${array[0]}"

    # debug likelihood
    local w=${SAMVC[$nextcore]:-0}
    local likelihood
    likelihood=$(awk "BEGIN{printf \"%.2f\", ($w*100)/$SAMVTOTAL}")
    samdebug "Picked core (samvideo): $nextcore (likelihood: ${likelihood}%)"
}


# 3) Core-weight mode (weighted by games per core)

declare -A COREWC    # raw game counts per core
declare -A COREP     # mirror of COREWC for pick_weighted_random
TOTAL_GAME_COUNT=0
COREWEIGHT_INITIALIZED=0


function init_core_weighted() {
    # only run once
    (( COREWEIGHT_INITIALIZED )) && return
    COREWEIGHT_INITIALIZED=1

    echo -n "Please wait while calculating core weights..."

    # a) ensure every core has a gamelist
    for c in "${corelist[@]}"; do
        f="${gamelistpathtmp}/${c}_gamelist.txt"
        [[ -f "$f" ]] || check_list "$c" >/dev/null
    done

    # b) build raw counts & total
    TOTAL_GAME_COUNT=0
    for c in "${corelist[@]}"; do
        f="${gamelistpathtmp}/${c}_gamelist.txt"
        if [[ -f "$f" ]]; then
            COREWC["$c"]=$(wc -l < "$f")
            (( TOTAL_GAME_COUNT += COREWC["$c"] ))
        fi
    done

    # c) fallback to equal if truly empty
    if (( TOTAL_GAME_COUNT == 0 )); then
        for c in "${corelist[@]}"; do
            COREWC["$c"]=1
        done
        TOTAL_GAME_COUNT=${#corelist[@]}
    fi

    # d) mirror COREWC → COREP for picking
    for c in "${!COREWC[@]}"; do
        COREP["$c"]=${COREWC["$c"]}
    done

    # e) print table of counts & percentages
    echo -e "\nCore      Games   Percent"
    printf '%.0s─' {1..28}; echo
    for core in "${!COREWC[@]}"; do
        cnt=${COREWC[$core]}
        pct=$(awk "BEGIN{printf \"%.2f\", ($cnt*100)/${TOTAL_GAME_COUNT}}")
        printf "%-8s %6d   %6s%%\n" "$core" "$cnt" "$pct"
    done | sort -k2 -nr

    echo " Done."
}



function pick_core_weighted() {
    init_core_weighted

    # fast pick from prebuilt COREP/TOTAL_GAME_COUNT
    nextcore=$(pick_weighted_random COREP "$TOTAL_GAME_COUNT")
    [[ -z "$nextcore" ]] && nextcore="${corelist[0]}"

    # debug likelihood
    local w=${COREP[$nextcore]}
    local likelihood=$(awk "BEGIN{printf \"%.2f\", ($w*100)/$TOTAL_GAME_COUNT}")
    samdebug "Picked core (coreweight): $nextcore (likelihood: ${likelihood}%)"
}


function pick_weighted_random() {
    local -n weights=$1
    local total=$2
    (( total<=0 )) && echo "" && return

    local pick sum=0
    pick=$(shuf --random-source=/dev/urandom -i 1-"$total" -n1)
    for key in "${!weights[@]}"; do
        (( sum += weights[$key] ))
        if (( pick <= sum )); then
            echo "$key"
            return
        fi
    done
    echo ""
}

# Process special cores like ao486, amiga, arcade or X68000 
function special_core_processor() {
    # This function checks prerequisites for special cores.
    # Returns:
    # 0 - Not a special core. The caller should continue standard processing.
    # 1 - Special core was loaded successfully. The caller's job is done.
    # 2 - Special core prerequisite failed. The caller should handle the error (e.g., retry).

    case "${nextcore}" in
        "arcade"|"stv")
            if [[ -n "$cfgarcade_configpath" ]]; then
                configpath="$cfgarcade_configpath"
            fi
            load_core "${nextcore}"
            return 1 
            ;;

        "amiga")
            # This check is fast, so we can leave it as is.
            if [ -f "${amigapath}/MegaAGS.hdf" ] || [ -f "${amigapath}/AmigaVision.hdf" ]; then
                load_core "amiga"
                return 1 
            else
                echo "ERROR - MegaAGS/AmigaVision pack not found in Amiga folder. Skipping core..."
                delete_from_corelist amiga
                return 2 
            fi
            ;;

        "amigacd32")
            # This check is also fast.
            if [ -f "/media/fat/_Console/Amiga CD32.mgl" ]; then
                load_core "amigacd32"
                return 1
            else
                echo "ERROR - /media/fat/_Console/Amiga CD32.mgl not found. Skipping core..."
                delete_from_corelist amigacd32
                return 2
            fi
            ;;

		"ao486")
            if [[ -z "$mgl_check_status_ao486" ]]; then
                samdebug "Performing one-time setup for ao486..."
                
                # Check the gamelist for invalid entries once.
                if [[ -z "$mgl_gamelist_check_status_ao486" && -f "${gamelistpath}/ao486_gamelist.txt" ]]; then
                    local invalid_lines=$(grep -v -c "\.mgl$" "${gamelistpath}/ao486_gamelist.txt")
                    if [ "$invalid_lines" -gt 0 ]; then
                        samdebug "Invalid entries found in ao486_gamelist.txt. Rebuilding list..."
                        build_mgl_list ao486
                    fi
                    # Mark this specific check as done.
                    mgl_gamelist_check_status_ao486="done"
                fi

                # 2. Count the MGL files.
                local dir1="/media/fat/_DOS Games"
                local dir2="/media/fat/_Computer/_DOS Games"
                local count1=$(find "$dir1" -type f -iname '*.mgl' 2>/dev/null | wc -l)
                local count2=$(find "$dir2" -type f -iname '*.mgl' 2>/dev/null | wc -l)

                if [ "$count1" -gt 0 ] || [ "$count2" -gt 0 ]; then
                    mgl_check_status_ao486="pass"
                else
                    mgl_check_status_ao486="fail"
                    echo "ERROR - No ao486 MGL files found in:"
                    echo "  $dir1"
                    echo "  $dir2"
                    echo "Please install the 0Mhz collection."
                fi
            fi

            # 3. Act based on the stored status.
            if [[ "$mgl_check_status_ao486" == "pass" ]]; then
                load_core "ao486"
                return 1
            else
                delete_from_corelist "ao486"
                return 2
            fi
            ;;

        "x68k")
            if [[ -z "$mgl_check_status_x68k" ]]; then
                samdebug "Performing one-time check for x68k MGL files..."
                local dir1="/media/fat/_X68000 Games"
                local dir2="/media/fat/_Computer/_X68000 Games"
                local count1=$(find "$dir1" -type f -iname '*.mgl' 2>/dev/null | wc -l)
                local count2=$(find "$dir2" -type f -iname '*.mgl' 2>/dev/null | wc -l)

                if [ "$count1" -gt 0 ] || [ "$count2" -gt 0 ]; then
                    mgl_check_status_x68k="pass"
                else
                    mgl_check_status_x68k="fail"
                    echo "ERROR - No x68k MGL files found in:"
                    echo "  $dir1"
                    echo "  $dir2"
                    echo "Please install the neon68k collection."
                fi
            fi

            if [[ "$mgl_check_status_x68k" == "pass" ]]; then
                load_core "x68k"
                return 1
            else
                delete_from_corelist "x68k"
                return 2
            fi
            ;;
    esac

    # If the core is not a special one, return 0.
    return 0
}


# ──────────────────────────────────────────────────────────────────────────────
# Game Picker and Checker
# ──────────────────────────────────────────────────────────────────────────────


function pick_rom() {	
	if [ -s ${gamelistpathtmp}/"${nextcore}"_gamelist.txt ]; then
		rompath="$(cat ${gamelistpathtmp}/"${nextcore}"_gamelist.txt | shuf --random-source=/dev/urandom --head-count=1)"
	else
		echo "Gamelist creation failed. Will try again on next core launch. Trying another rom..."	
		rompath="$(cat ${gamelistpath}/"${nextcore}"_gamelist.txt | shuf --random-source=/dev/urandom --head-count=1)"
	fi
	
	#samvideo mode
	# Commercial linked to game through /tmp/SAMvideos.xml. Find this game in Gamelist
	if [ "$samvideo" == "yes" ] && [ "$samvideo_tvc" == "yes" ] && [ -f /tmp/.SAM_tmp/sv_gamename ]; then
		rompath="$(cat ${gamelistpath}/"${nextcore}"_gamelist.txt | grep -if /tmp/.SAM_tmp/sv_gamename |  grep -iv "VGM\|MSU\|Disc 2\|Sega CD 32X" | shuf -n 1)"
		if [ -z "${rompath}" ]; then
			samdebug "Error with picking the corresponding game for the commercial. Playing random game now."
			rompath="$(cat ${gamelistpath}/"${nextcore}"_gamelist.txt | shuf --random-source=/dev/urandom --head-count=1)"
		fi
	fi
	
	#m82 mode
	if [ "$m82" == "yes" ]; then
		rompath="$(cat ${gamelistpathtmp}/nes_gamelist.txt | head -n 1)"
	fi

}

function check_rom(){
	if [ -z "${rompath}" ]; then
    	echo "ERROR: rompath is empty for core '${nextcore}'. Cannot check ROM." >&2
		return 1
	fi
	
	# Make sure file exists since we're reading from a static list
	if [[ "${rompath,,}" != *.zip* ]]; then
		if [ ! -f "${rompath}" ]; then
			echo "ERROR: File not found - ${rompath}"
			echo "Creating new game list now..."
			rm "${gamelistpath}/${1}_gamelist.txt"
			create_gamelist "${1}"
			return 1
		fi
	else
		zipfile="$(echo "$rompath" | awk -F".zip" '{print $1}' | sed -e 's/$/.zip/')"
		if [ ! -f "${zipfile}" ]; then
			echo "ERROR: File not found - ${zipfile}"
			echo "Creating new game list now..."
			rm "${gamelistpath}/${1}_gamelist.txt"
			create_gamelist "${1}"
			return 1
		fi
	fi
	
	romname=$(basename "${rompath}")

	# Make sure we have a valid extension as well
	local extension="${rompath##*.}"
	local extlist="${CORE_EXT[${nextcore}]//,/ }" 
				
	if [[ "$extlist" != *"$extension"* ]]; then
		samdebug "Wrong extension found: '${extension^^}' for core: ${nextcore} rom: ${rompath}"
		# The function now simply reports failure. It does NOT call next_core.
		# The calling function will be responsible for retrying or skipping the core.
		create_gamelist "${nextcore}" & # Rebuilding the list in the background is ok
		return 1
	fi
	
	# If all checks pass, return 0 for success
	return 0
}

function delete_played_game() {
	# Delete played game from list
	samdebug "Selected file: ${rompath}"
	if [ "${norepeat}" == "yes" ]; then
		#Deletes all occurences: awk -vLine="$rompath" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} && cp -f ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
		awk -v Line="$rompath" '
			$0 == Line {
				if (!found) {
					found = 1
					next
				}
			}
			{ print }
		' "${gamelistpathtmp}/${nextcore}_gamelist.txt" > "${tmpfile}" && mv "${tmpfile}" "${gamelistpathtmp}/${nextcore}_gamelist.txt"

	fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Gamelist Builder
# ──────────────────────────────────────────────────────────────────────────────

#Build Gamelists for Arcade and ST-V
function build_mra_list() {
    local core_type=${1}
    local mra_path
    local list_file="${gamelistpath}/${core_type}_gamelist.txt"

    if [[ "${core_type}" == "stv" ]]; then
        mra_path="/media/fat/_Arcade/_ST-V"
        # If no MRAs found for ST-V, exit gracefully
        if ! find "${mra_path}" -type f -iname "*.mra" -print -quit | grep -q .; then
            echo "The path ${mra_path} contains no MRA files!"
            loop_core
            return 1
        fi
        find "${mra_path}" -not -path '*/.*' -type f -iname "*.mra" > "${list_file}"
    else
        # Assumes 'arcade' or other MRA-based cores indexed by samindex
        mra_path="/media/fat/_Arcade"
        ${mrsampath}/samindex -s arcade -o "${gamelistpath}"
        # The above command creates the list, so we just ensure it's named correctly
        # If samindex outputs a different name, a mv or cp might be needed here.
        # Assuming samindex creates a file like arcade_gamelist.txt
    fi

    # Copy the newly created list to the temp directory for use
    cp "${list_file}" "${gamelistpathtmp}/${core_type}_gamelist.txt" 2>/dev/null
}


function build_mgl_list() {
    local core_type=${1}
    local search_paths
    local list_file="${gamelistpath}/${core_type}_gamelist.txt"
    local game_count

    case "${core_type}" in
        "ao486")
            search_paths=(
                "/media/fat/_DOS Games"
                "/media/fat/_Computer/_DOS Games"
            )
            ;;
        "x68k")
            search_paths=(
                "/media/fat/_X68000 Games"
                "/media/fat/_Computer/_X68000 Games"
            )
            ;;
        *)
            samdebug "No MGL search path defined for ${core_type}."
            return 1
            ;;
    esac

    # Find all .mgl files in the specified paths (silence errors for missing dirs)
    find "${search_paths[@]}" -type f -iname '*.mgl' 2>/dev/null > "${list_file}"

    if [ ! -s "${list_file}" ]; then
        samdebug "No .mgl files found for ${core_type}—disabling core."
        delete_from_corelist "${core_type}"
        delete_from_corelist "${core_type}" tmp
        return 1
    fi

    game_count=$(wc -l < "${list_file}")
    samdebug "Created ${core_type} gamelist with ${game_count} entries."
    # Copy the new list to the temp directory for use
    cp "${list_file}" "${gamelistpathtmp}/${core_type}_gamelist.txt" 2>/dev/null
}

function build_amiga_list() {
    local demos_file="${amigapath}/listings/demos.txt"
    local games_file="${amigapath}/listings/games.txt"
    local tmp_list="${gamelistpathtmp}/amiga_gamelist.txt"

    # Check for the existence of the primary games list
    if [ ! -f "${games_file}" ]; then
        echo "ERROR: Can't find Amiga games.txt file at '${games_file}'"
        # The main function will handle the legacy fallback
        return 1
    fi
    
    # Clear the temp list to start fresh
    > "${tmp_list}"

    if [[ "${amigaselect}" == "demos" ]] || [[ "${amigaselect}" == "all" ]]; then
        if [ -f "${demos_file}" ]; then
            sed 's/^/Demo: /' "${demos_file}" >> "${tmp_list}"
        fi
    fi

    if [[ "${amigaselect}" == "games" ]] || [[ "${amigaselect}" == "all" ]]; then
        cat "${games_file}" >> "${tmp_list}"
    fi

    # Persist the generated list for future runs
    cp "${tmp_list}" "${gamelistpath}/amiga_gamelist.txt"

    total_games="$(wc -l < "${tmp_list}")"
    samdebug "${total_games} Amiga Games and/or Demos found."
}


# General Romfinder
function create_gamelist() {
    local core="$1"
    local mode="$2"   # empty = initial build, non-empty = comp build
    local outdir file rc

    if [[ -z "$mode" ]]; then
        # ── INITIAL build into $gamelistpath ────────────────────

        # if samindex is already running, skip
        if ps | grep -q '[s]amindex'; then
            samdebug "samindex already in flight; skipping full build for ${core}"
            return 0
        fi

        samdebug "Creating full gamelist for ${core}"
        outdir="$gamelistpath"

    else
        # ── COMPARISON build into tmp/comp ─────────────────────
        samdebug "Creating comparison gamelist for ${core}"
        outdir="${gamelistpathtmp}/comp"
    fi

    # ensure output dir exists, then sync/fs-settle
    mkdir -p "$outdir"
    sync "$outdir"
    sleep 1

    # run the indexer twice due to the indexer not finding all files on first run for some reason
    "${mrsampath}/samindex" -q -s "$core" -o "$outdir"
	"${mrsampath}/samindex" -q -s "$core" -o "$outdir"
    rc=$?

    if [[ -z "$mode" ]]; then
        # on initial build, error>1 means “no games”
        if (( rc > 1 )); then
            delete_from_corelist "$core"
            echo "Can't find games for ${CORE_PRETTY[$core]}"
            samdebug "create_gamelist returned code $rc for $core"
            return 1
        fi

        # seed the tmp copy for diffs
        mkdir -p "${gamelistpathtmp}"
        cp "${outdir}/${core}_gamelist.txt" \
           "${gamelistpathtmp}/${core}_gamelist.txt" 2>/dev/null
    fi

    # always sort & dedupe the output file
    file="${outdir}/${core}_gamelist.txt"
    if [[ -f "$file" ]]; then
        sort -u "$file" -o "$file"
    fi

    return 0
}


function check_list() { # args ${nextcore} 
	
	if [ ! -f "${gamelistpath}/${1}_gamelist.txt" ]; then
		echo "Creating game list at ${gamelistpath}/${1}_gamelist.txt"
		create_gamelist "${1}"
		if [ $? -ne 0 ]; then 
			samdebug "check_list function returned error code"
			return 1
		fi
	fi
	
	
	if [ "${sam_goat_list}" == "yes" ] && [ ! -s "${gamelistpathtmp}/${1}_gamelist.txt" ]; then
		build_goat_lists
		return
	fi
	
	# m82 populate lists
	if [ "${m82}" == "yes" ]; then
		if [[ -z "$m82_bios_path" ]]; then 
			# process m82_list
			echo -n "M82 mode active. Finding M82 bios..."
			declare -g m82_bios_path="$(fgrep -i "m82 game" "$gamelistpath/nes_gamelist.txt" | head -n 1)"
			echo "Success."
			samdebug "m82 bios found at: "$m82_bios_path""
		fi
		if [[ -z "$m82_bios_path" ]]; then 
			echo "Error: No suitable m82 bios could be found in your nes folder. The file should be called 'M82 Game[..].nes'"
			exit
		fi
		if [ ! -s "${gamelistpathtmp}/${1}_gamelist.txt" ]; then
			samdebug "Creating m82 game list"
			while IFS= read -r line; do 
				echo "$m82_bios_path" 
				fgrep "$line" "${gamelistpath}"/nes_gamelist.txt | head -n 1
			done < "${mrsampath}/SAM_Gamelists/m82_list.txt" > "${gamelistpathtmp}/nes_gamelist.txt"
			samdebug "Found the following games: \n$(cat "${gamelistpathtmp}/nes_gamelist.txt" | grep -iv m82)"
			samdebug "Found $(cat "${gamelistpathtmp}/nes_gamelist.txt" | grep -iv m82 | wc -l) games"
			# If button was pushed to skip game
			if [ "$update_done" -eq 1 ]; then
				sed -i '1d' "$gamelistpathtmp"/nes_gamelist.txt
			fi

		fi
		gametimer="21"
		update_done=0
		return
	fi
	
	# Copy gamelist to tmp
	if [ ! -s "${gamelistpathtmp}/${1}_gamelist.txt" ]; then
		cp "${gamelistpath}/${1}_gamelist.txt" "${gamelistpathtmp}/${1}_gamelist.txt" 2>/dev/null
	
		filter_list "${1}"
		if [ $? -ne 0 ]; then 
			return 1
			samdebug "filter_list encountered an error"
		fi		
	fi
	return 0
}




# Create all gamelists in the background

function create_all_gamelists() {
    # This function now only runs once per script invocation.
    if (( gamelists_created )); then
        return 0
    fi
    gamelists_created=1

    # Run the entire process in a subshell in the background (&)
    # to avoid blocking the main script's startup.
    (
        local c # loop variable
        local core_has_games=false

        echo "Verifying and building gamelists in the background..."

        # --- Step 1: Build any missing gamelists ---
        for c in "${corelist[@]}"; do
            local gamelist_file="${gamelistpath}/${c}_gamelist.txt"
            
            # If the gamelist for a core in our list doesn't exist, create it.
            if [ ! -f "${gamelist_file}" ]; then
                samdebug "Gamelist for '${c}' is missing, creating it now..."
                
                # Check if it's a special core with its own builder function
                if [[ " ${special_cores[*]} " =~ " ${c} " ]] && type -t create_"${c}"list > /dev/null; then
                    # It's a special core, call its dedicated builder
                    create_"${c}"list
                else
                    # It's a standard core, use samindex
                    "${mrsampath}/samindex" -q -s "$c" -o "$gamelistpath"
                fi
            fi
        done

        # --- Step 2: Validate all lists and create the final, active core list ---
        local launchable_cores=() # Start with an empty array
        samdebug "Validating all gamelists to find launchable cores..."

        for c in "${corelist[@]}"; do
            local gamelist_file="${gamelistpath}/${c}_gamelist.txt"
            
            # A core is considered "launchable" if its gamelist exists AND is not empty.
            if [ -s "${gamelist_file}" ]; then
                # The list exists and has games. Add it to our active list.
                launchable_cores+=( "$c" )
                core_has_games=true
            else
                # The list is missing or empty. This core cannot be launched.
                samdebug "Excluding core '${c}' from this session: Gamelist is missing or empty."
            fi
        done

        # --- Step 3: Update the temporary core list for the current session ---
        if [ "$core_has_games" = "true" ]; then
            # Overwrite the temporary list with our new, validated list of launchable cores.
            corelisttmp=( "${launchable_cores[@]}" )
            samdebug "Session core list updated. Launchable cores: ${corelisttmp[*]}"
        else
            echo "FATAL ERROR: No games found for ANY core. Super Attract Mode cannot start." >&2
            # In this fatal case, we might want to prevent the main loop from running,
            # but for now, we'll leave corelisttmp empty.
            corelisttmp=()
        fi
    ) &
}

function check_gamelistupdate() {
	local core="$1"
	local orig="${gamelistpath}/${core}_gamelist.txt"
	local compdir="${gamelistpathtmp}/comp"
	local comp="${compdir}/${core}_gamelist.txt"
	
	# ── only run once per core ──────────────────
	local flag_dir="${gamelistpathtmp}/.checked"
	mkdir -p "$flag_dir"
	local flag_file="$flag_dir/$core"
	[[ -e "$flag_file" ]] && return
	touch "$flag_file"
	
	#sleep 15
	
	if [[ "$m82" == "no" ]]; then
	mkdir -p "$compdir"
	
	# Create the comp gamelist
	create_gamelist "$core" comp
	
	# now compare sorted originals
	if ! diff -q <(sort "$orig") <(sort "$comp") &>/dev/null; then
	  samdebug "[${core}] difference detected, updating gamelist…"
	
	  # show up to 10 unique lines
	  samdebug "[${core}] DIFF:"
	  comm -3 <(sort "$orig") <(sort "$comp") | head -n10 | \
		while read -r ln; do samdebug "   $ln"; done
	
	  # copy back the *sorted* new list
	  sort "$comp" -o "$orig"
	  samdebug "[${core}] Gamelist updated."
	else
	  samdebug "[${core}] No changes detected in ${core} gamelist."
	fi
	fi
}



function build_goat_lists() {
	local goat_flag="/tmp/.SAM_tmp/goatmode.ready"
	local goat_list_path="${gamelistpath}/sam_goat_list.txt"
	
	echo "SAM GOAT Mode active"
	
	# Already built this session?
	[[ -f "$goat_flag" ]] && return
	
	# Ensure working dir
	mkdir -p "${gamelistpathtmp}" /tmp/.SAM_tmp
	
	# Download master list if missing
	if [[ ! -f "$goat_list_path" ]]; then
	samdebug "Downloading GOAT master list..."
	get_samstuff .MiSTer_SAM/SAM_Gamelists/sam_goat_list.txt "$gamelistpath"
	fi
	
	# Parse master list into per-core tmp files
	local current_core=""
	while IFS= read -r line; do
	if [[ "$line" =~ ^\[(.+)\]$ ]]; then
	  current_core="${BASH_REMATCH[1],,}"
	  [[ ! -f "${gamelistpath}/${current_core}_gamelist.txt" ]] && create_gamelist "$current_core"
	elif [[ -n "$current_core" ]]; then
	  fgrep -i -m1 "$line" "${gamelistpath}/${current_core}_gamelist.txt" \
		>> "${gamelistpathtmp}/${current_core}_gamelist.txt"
	fi
	done < "$goat_list_path"
	
	# Gather cores with entries
	readarray -t corelist < <(
	find "${gamelistpathtmp}" -name "*_gamelist.txt" \
	  -exec basename {} \; | cut -d '_' -f1
	)
	printf "%s\n" "${corelist[@]}" > "${corelistfile}"
	
	# Update INI corelist if changed
	local newvalue; newvalue="$(IFS=,; echo "${corelist[*]}")"
	if ! grep -q "^corelist=\"$newvalue\"" "$samini_file"; then
		samini_mod corelist "$newvalue"
	fi
	
	# Enable GOAT flag
	if ! grep -q '^sam_goat_list="yes"' "$samini_file"; then
		samini_mod sam_goat_list yes
	fi
	
	# Mark as built
	touch "$goat_flag"
}

function build_m82_list() {
	[ ! -d "/tmp/.SAM_List" ] && mkdir /tmp/.SAM_List/ 
	[ ! -d "/tmp/.SAM_tmp" ] && mkdir /tmp/.SAM_tmp/

	if [ ! -f "${gamelistpath}"/nes_gamelist.txt ]; then
		samdebug "Creating NES gamelist"
		${mrsampath}/samindex -q -s "nes" -o "${gamelistpath}" 
		if [ $? -gt 1 ]; then
			echo "Error: NES gamelist missing. Make sure you have NES games." 
		fi
	fi
	if [ -f "${gamelistpathtmp}"/nes_gamelist.txt ]; then
		rm "${gamelistpathtmp}"/nes_gamelist.txt
	fi
	local m82_list_path="${gamelistpath}"/m82_list.txt
	# Check if the M82 list file exists
	if [ ! -f "$m82_list_path" ]; then
		echo "Error: The M82 list file ($m82_list_path) does not exist. Updating SAM now. Please try again."
		repository_url="https://github.com/mrchrisster/MiSTer_SAM"
		get_samstuff .MiSTer_SAM/SAM_Gamelists/m82_list.txt "${gamelistpath}"
	fi

	printf "%s\n" nes > "${corelistfile}"
	if [[ "$m82_muted" == "yes" ]]; then
		mute="global"
	else
		mute="no"
		only_unmute_if_needed
	fi
	gametimer="21"
	listenjoy=no
}


# ──────────────────────────────────────────────────────────────────────────────
# Core Loader
# ──────────────────────────────────────────────────────────────────────────────

# This handles list building, filtering, cleaning, random selection, and the 'norepeat' feature.
function pick_random_game() {
    local core_type=${1}
    local master_list="${gamelistpath}/${core_type}_gamelist.txt"
    local session_list="${gamelistpathtmp}/${core_type}_gamelist.txt"
    local build_func

    # Determine which list-builder function to use
    case "${core_type}" in
        "arcade"|"stv") build_func="build_mra_list" ;;
        "ao486"|"x68k") build_func="build_mgl_list" ;;
        "amiga")        build_func="build_amiga_list" ;;
        *) samdebug "Error: pick_random_game called with invalid core ${core_type}"; return 1 ;;
    esac


    # 1. Check if the master gamelist exists and has content.
    if [ ! -s "${master_list}" ]; then
        # The master list is missing or empty. We must build it.
        samdebug "Master gamelist for '${core_type}' not found. Building it now..."
        ${build_func} "${core_type}"
    fi

    # 2. After attempting to build, check one last time. If it's still empty, the core has no games.
    if [ ! -s "${master_list}" ]; then
        samdebug "ERROR: Failed to create or find games for core '${core_type}'." >&2
        return 1 # Signal failure
    fi
    
    # 3. Apply filter
	if [ ! -s "${session_list}" ]; then
    	cp -f "${master_list}" "${session_list}"
	
		filter_list "${core_type}"
		# If filtering resulted in an empty list, we must exit.
		if [ ! -s "${session_list}" ]; then
			samdebug "Warning: Filters for '${core_type}' produced an empty list. No games to play." >&2
			return 1
		fi	
	    # Remove any blank lines from the session list
		sed -i '/^$/d' "${session_list}"
	fi

    # Pick a random line from the now-filtered session list
    local chosen_path
    chosen_path="$(shuf --random-source=/dev/urandom --head-count=1 "${session_list}")"
    
    # Sanitize the path to remove any hidden characters
    chosen_path=$(echo "$chosen_path" | tr -d '[:cntrl:]')

    # Verify the chosen file exists on disk
    if [[ "${core_type}" != "amiga" ]] && [ ! -f "${chosen_path}" ]; then
        samdebug "File not found after pick: ${chosen_path}. Something is wrong with the gamelist entries."
        # We don't retry here anymore, as that could cause loops.
        # We will fail gracefully and let the main loop handle it.
        return 1
    fi

    # If 'norepeat' is enabled, remove the chosen game from the session list
    if [[ "${norepeat}" == "yes" ]]; then
        samdebug "(${core_type}) Removing from list for norepeat: ${chosen_path}"
        # Use a temporary file to safely modify the session list
        awk -vLine="$chosen_path" '!index($0,Line)' "${session_list}" > "${tmpfile}" && mv -f "${tmpfile}" "${session_list}"
    fi

    # Output the chosen path/name so the caller can capture it
    echo "${chosen_path}"
}

function load_core() { # load_core core [/path/to/rom] [name_of_rom]
    local core=${1}
    local rompath_arg=${2}
    local romname_arg=${3}

    # --- Local variables for unified logic ---
    local gamename tty_corename launch_cmd streamtitle mute_target rompath romname post_launch_hook

    # This is the primary router for core-specific setup logic
    case "${core}" in
        "arcade"|"stv")
            ### MRA Core Loader (Arcade, ST-V) ###
            rompath=$(pick_random_game "${core}")
            # Sanitize the variable to remove any hidden control characters
            rompath=$(echo "$rompath" | tr -d '[:cntrl:]')
            
            if [ ! -f "${rompath}" ]; then
                echo "ERROR: MRA file not found after pick and sanitize: '${rompath}'" >&2
                return 1
            fi

            gamename="$(basename "${rompath//.mra/}")"
            tty_corename=$(grep "<setname>" "${rompath}" | sed -e 's/<setname>//' -e 's/<\/setname>//' | tr -cd '[:alnum:]')
            mute_target="${tty_corename:-$gamename}"
            launch_cmd="load_core ${rompath}"
            ;;

        "ao486"|"x68k")
            ### Random MGL Loader (ao486, x68k) ###
            rompath=$(pick_random_game "${core}")
            romname=$(basename "${rompath}")
            gamename="$(echo "${romname%.*}" | tr '_' ' ')"
            tty_corename="${core}"
            mute_target="${core}"
            launch_cmd="load_core ${rompath}"
            [ "${core}" == "ao486" ] && skipmessage_ao486 &
            ;;

        "amiga")
            ### Amiga (MegaAGS) Loader ###
            if [ ! -f "${amigapath}/listings/games.txt" ]; then
                # Legacy fallback
                echo -e "Starting now on the \e[4m${CORE_PRETTY[amiga]}\e[0m: \e[1mMegaAGS Amiga Game\e[0m"
                mute "Minimig"; echo "load_core ${amigacore}" >/dev/MiSTer_cmd
                sleep 13; "${mrsampath}/mbc" raw_seq {6c}; "${mrsampath}/mbc" raw_seq O
                activity_reset; return 0
            fi

            local amiga_title_raw
            amiga_title_raw=$(pick_random_game "amiga")

            if [ -z "${amiga_title_raw}" ]; then
                echo "ERROR: Failed to pick an Amiga game from the list." >&2
                return 1
            fi

            gamename="$(echo "${amiga_title_raw}" | sed 's/Demo: //' | tr '_' ' ')"
            local ags_boot_title="${amiga_title_raw//Demo: /}"
            echo "${ags_boot_title}" > "${amigapath}/shared/ags_boot"
            rompath="${gamename}" # Set rompath for logging consistency

            tty_corename="Minimig"
            mute_target="Minimig"
            if [ -f "/media/fat/_Computer/Amiga.mgl" ]; then
                launch_cmd="load_core /media/fat/_Computer/Amiga.mgl"
                mute_target="Amiga"
            else
                launch_cmd="load_core ${amigacore}"
            fi
            ;;

        "amigacd32")
            ### Amiga CD32 Loader ###
            check_list "${core}"; if [ $? -ne 0 ]; then next_core; return 1; fi
            check_gamelistupdate "${core}" &
            filter_list "${core}"; pick_rom; check_rom "${core}"; if [ $? -ne 0 ]; then return 1; fi
            
            gamename="${romname%.*}"
            mute_target="amigacd32"

            local CONFIG_FILE="/media/fat/config/AmigaCD32.cfg"
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "ERROR - AmigaCD32.cfg not found. Skipping core." >&2
                delete_from_corelist amigacd32; return 1
            fi
            local new_path=$(echo "$rompath" | sed -e 's|^/media||' -e 's|^/||')
            if [[ "$new_path" != ../* ]]; then new_path="../$new_path"; fi
            dd if=/dev/zero bs=1 count=108 seek=3100 of="$CONFIG_FILE" conv=notrunc &>/dev/null
            echo -n "$new_path" | dd of="$CONFIG_FILE" bs=1 seek=3100 conv=notrunc &>/dev/null

            launch_cmd="load_core /media/fat/_Console/Amiga CD32.mgl"
            post_launch_hook="(sleep 10; /media/fat/Scripts/.MiSTer_SAM/mbc raw_seq :30) &"
            ;;

        *)
            ### Default ROM-based MGL Loader (Consoles, NeoGeo, etc.) ###
            # This block correctly handles all standard cores.
            rompath="${rompath_arg}"
            romname="${romname_arg}"
            gamename="${romname_arg}" # This line is the crucial fix.
            
            # Special Neo Geo title lookup
            if [ "${core}" == "neogeo" ] && [ "${useneogeotitles}" == "yes" ]; then
                for e in "${!NEOGEO_PRETTY_ENGLISH[@]}"; do
                    if [[ "$rompath" == *"$e"* ]]; then gamename="${NEOGEO_PRETTY_ENGLISH[$e]}"; break; fi
                done
            fi
            
            tty_corename="${TTY2OLED_PIC_NAME[${core}]}"
            mute_target="${CORE_LAUNCH[${core}]}"

            # Create MGL file
            if [ -s /tmp/SAM_Game.mgl ]; then mv /tmp/SAM_Game.mgl /tmp/SAM_game.previous.mgl; fi
            {
                echo "<mistergamedescription>"
                echo "<rbf>${CORE_PATH_RBF[${core}]}/${MGL_CORE[${core}]}</rbf>"
                echo "<file delay=\"${MGL_DELAY[${core}]}\" type=\"${MGL_TYPE[${core}]}\" index=\"${MGL_INDEX[${core}]}\" path=\"../../../../..${rompath}\"/>"
                [ -n "${MGL_SETNAME[${core}]}" ] && echo "<setname>${MGL_SETNAME[${core}]}</setname>"
            } >/tmp/SAM_Game.mgl
            
            launch_cmd="load_core /tmp/SAM_Game.mgl"
            
            skipmessage "${core}" &
            ;;
    esac

    # --- Common Execution Block (This part remains the same for all cores) ---

    if [[ "${norepeat}" == "yes" ]] && [[ "${core}" == "amigacd32" ]]; then
        delete_played_game
    fi

    mute "${mute_target}"
    if [ "${bgm}" == "yes" ]; then
        streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
    fi

    echo -n "Starting now on the "; echo -ne "\e[4m${CORE_PRETTY[${core}]}\e[0m: "; echo -e "\e[1m${gamename}\e[0m"
    [[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"

    echo "$(date +%H:%M:%S) - ${core} - ${rompath:-$gamename}" >>/tmp/SAM_Games.log
    echo "${gamename} (${core})" >/tmp/SAM_Game.txt

    if [ "${ttyenable}" == "yes" ]; then
        local tty_gamename="${gamename}"
        if [[ "${ttyname_cleanup}" == "yes" ]]; then tty_gamename="$(echo "${tty_gamename}" | sed 's/ *([^)]*) *$//')"; fi
        if [[ -n "$streamtitle" ]]; then tty_gamename="${tty_gamename} - BGM: ${streamtitle}"; fi
        
        tty_currentinfo=(
            [core_pretty]="${CORE_PRETTY[${core}]}" [name]="${tty_gamename}" [core]="${tty_corename}"
            [date]=$EPOCHSECONDS [counter]=${gametimer} [name_scroll]="${tty_gamename:0:21}"
            [name_scroll_position]=0 [name_scroll_direction]=1 [update_pause]=${ttyupdate_pause}
        )
        declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
        write_to_TTY_cmd_pipe "display_info" &
        SECONDS=$((EPOCHSECONDS - tty_currentinfo[date]))
    fi

    echo "${launch_cmd}" >/dev/MiSTer_cmd
    
    if [ -n "${post_launch_hook}" ]; then
        eval "${post_launch_hook}"
    fi

    sleep 1
    activity_reset
    return 0
}

# ========= SAM START AND STOP =========

function sam_start() {
	local core="$1"
	env_check
	# Terminate any other running SAM processes
	there_can_be_only_one
	update_samini	
	read_samini
	mcp_start
	sam_prep
	disable_bootrom # Disable NES Bootrom until Reboot
	bgm_start
	tty_start
	echo "Starting SAM in the background."
	
	[[ "$samvideo" == "yes" ]] && echo "Samvideo mode. Please wait for video to load"
	
	# avoid double‐launch
	if tmux has-session -t SAM 2>/dev/null; then
		samdebug "SAM session already exists—skipping."
		return
	fi
	
	# Launch tmux and background it
	(
	   tmux new-session -d \
		 -x 180 -y 40 \
		 -n "-= SAM Monitor -- Detach with ctrl-b, then push d =-" \
		 -s SAM \
		 "${misterpath}/Scripts/MiSTer_SAM_on.sh loop_core"
	) &

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
  echo "Stopping other running instances of ${samprocess}…"

  # 1) kill any tmux “SAM” session
  tmux kill-session -t SAM 2>/dev/null || true

  # 2) patterns to match in the ps output
  local patterns=(
    "MiSTer_SAM_on.sh initial_start"
    "MiSTer_SAM_on.sh loop_core"
    "MiSTer_SAM_on.sh bootstart"
    "MiSTer_SAM_init start"
  )

  # 3) for each pattern, find and kill all matching PIDs
  local pat pid
  for pat in "${patterns[@]}"; do
    ps -o pid,args \
      | grep "$pat" \
      | grep -v grep \
      | awk '{print $1}' \
      | while read -r pid; do
          [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
        done
  done

  # give it a moment
  sleep 1
}


function kill_all_sams() {
	# Kill all SAM processes except for currently running
	ps -ef | grep -i '[M]iSTer_SAM' | awk -v me=${sampid} '$1 != me {print $1}' | xargs kill &>/dev/null
}

function play_or_exit() {
	sam_cleanup
	if [[ "${playcurrentgame}" == "yes" ]]; then
		if [[ ${mute} == "core" ]]; then
			sleep 1
			if [ "${nextcore}" == "arcade" ]; then
				echo "load_core ${mra}" >/dev/MiSTer_cmd
			elif [ "${nextcore}" == "amiga" ]; then
				echo "${rompath}" > "${amigapath}"/shared/ags_boot
				if [ -f "/media/fat/_Console/Amiga.mgl" ]; then
					echo "load_core /media/fat/_Computer/Amiga.mgl" >/dev/MiSTer_cmd
				else
					echo "load_core ${amigacore}" >/dev/MiSTer_cmd
				fi
			else
				echo "load_core /tmp/SAM_Game.mgl" >/dev/MiSTer_cmd
			fi
		fi
	else
		# Retry up to 3 times until /tmp/CORENAME contains MENU
		for i in {1..3}; do
			echo "load_core /media/fat/menu.rbf" >/dev/MiSTer_cmd
			sleep 2
			if grep -q "MENU" /tmp/CORENAME 2>/dev/null; then
				break
			fi
			echo "Attempt $i: Waiting for MENU..."
			sleep 1
		done
		echo "Thanks for playing!"
	fi

	[ "${samvideo}" == "yes" ] && kill -9 "$(ps -o pid,args | grep '[m]player' | awk '{print $1}' | head -1)" 2>/dev/null
	bgm_stop
	tty_exit

	ps -ef | grep -i '[M]iSTer_SAM_on.sh' | xargs --no-run-if-empty kill &>/dev/null
}





# ======== UTILITY FUNCTIONS ========

function mcp_start() {
	# MCP monitors when SAM should be launched. "menuonly" and "samtimeout" determine when MCP launches SAM
	if [ -z "$(pidof MiSTer_SAM_MCP)" ]; then
		tmux new-session -s MCP -d "${mrsampath}/MiSTer_SAM_MCP"
	fi
}

function activity_reset() {
		truncate -s 0 "$joy_activity_file"
		truncate -s 0 "$mouse_activity_file"
		truncate -s 0 "$key_activity_file"
}
								 
function tmp_reset() {
	[[ -d /tmp/.SAM_List ]] && rm -rf /tmp/.SAM* /tmp/SAM* /tmp/MiSTer_SAM*
	mkdir -p /tmp/.SAM_List  /tmp/.SAM_tmp 
}

function init_paths() {
	# Create folders if they don't exist
	mkdir -p "${mrsampath}/SAM_Gamelists"
	#[ -d "/tmp/.SAM_List" ] && rm -rf /tmp/.SAM_List
	mkdir -p /tmp/.SAM_List
	[ -e "${tmpfile}" ] && { rm "${tmpfile}"; }
	[ -e "${tmpfile2}" ] && { rm "${tmpfile2}"; }
	touch "${tmpfile}"
	touch "${tmpfile2}"
}

function sam_prep() {
	
	# samvideo and ratings filter can't both be set
	if [ "${rating}" == "yes" ]; then
		samvideo=no
	fi
	[ ! -d "/tmp/.SAM_tmp/SAM_config" ] && mkdir -p "/tmp/.SAM_tmp/SAM_config"
	[ ! -d "${misterpath}/video" ] && mkdir -p "${misterpath}/video"
	[[ -f /tmp/SAM_game.previous.mgl ]] && rm /tmp/SAM_game.previous.mgl
	[[ ! -d "${mrsampath}" ]] && mkdir -p "${mrsampath}"
	[[ ! -d "${mrsamtmp}" ]] && mkdir -p "${mrsamtmp}"
	mkdir -p /media/fat/Games/SAM &>/dev/null
	[ ! -d "/tmp/.SAM_tmp/Amiga_shared" ] && mkdir -p "/tmp/.SAM_tmp/Amiga_shared"
	if [ -d "${amigapath}/shared" ] && [ "$(mount | grep -ic "${amigapath}"/shared)" == "0" ]; then
		if [ "$(du -m "${amigapath}/shared" | cut -f1)" -lt 30 ]; then
			cp -r --force "${amigapath}"/shared/* /tmp/.SAM_tmp/Amiga_shared &>/dev/null
			mount --bind "/tmp/.SAM_tmp/Amiga_shared" "${amigapath}/shared"
		else
			echo "WARNING: ${amigapath}/shared folder is bigger than 30 MB. Items in shared folder won't be accessible while SAM is running."
			mount --bind "/tmp/.SAM_tmp/Amiga_shared" "${amigapath}/shared"
		fi
	fi
	
	#Downloads rating lists and sets the corelist to match only cores with rated lists
	if [ "${kids_safe}" == "yes" ]; then
		rating="kids"
	fi

	if [ "${rating}" != "no" ]; then	
	    local missing=()

		# make sure the target dir exists
		mkdir -p "${mrsampath}/SAM_Rated"
		# check each expected file
		for f in "${RATED_FILES[@]}"; do
			if [[ ! -f "${mrsampath}/SAM_Rated/$f" ]]; then
				missing+=( "$f" )
			fi
		done
		if (( ${#missing[@]} )); then
			echo "Missing rating lists: ${missing[*]}"
			echo "Downloading..."
			if ! get_ratedlist; then
				echo "Ratings Filter failed downloading."
				return 1
			fi
		else
			echo "All rating lists present."
		fi

		#Set corelist to only include cores with rated lists
		# build glr from the files on disk
		if [ "${rating}" == "kids" ]; then
			readarray -t glr < <(
			  find "${mrsampath}/SAM_Rated" -name "*_rated.txt" \
				| awk -F'/' '{print $NF}' \
				| awk -F'_'  '{print $1}'
			)
		else
			readarray -t glr < <(
			  find "${mrsampath}/SAM_Rated" -name "*_mature.txt" \
				| awk -F'/' '{print $NF}' \
				| awk -F'_'  '{print $1}'
			)
		fi

		# intersect glr with corelist
		clr=()
		for g in "${glr[@]}"; do
		  for c in "${corelist[@]}"; do
			[[ "$c" == "$g" ]] && clr+=("$c")
		  done
		done

		# if no overlap, warn & use the full rated list
		if (( ${#clr[@]} == 0 )); then
		  echo "Warning: none of your enabled cores match the '${rating}' list."
		  echo "→ Falling back to ALL rated cores."
		  clr=( "${glr[@]}" )
		else
		  # otherwise show which cores have no rating file
		  readarray -t nclr < <(
			printf '%s\n' "${clr[@]}" "${corelist[@]}" \
			  | sort \
			  | uniq -iu
		  )
		  #echo "Rating lists missing for cores: ${nclr[*]}"
		fi

		# finally, write out the new corelist
		printf "%s\n" "${clr[@]}" > "${corelistfile}"

	fi
	
	[ "${coreweight}" == "yes" ] && echo "Weighted core mode active."
	[ "${samdebuglog}" == "yes" ] && rm /tmp/samdebug.log 2>/dev/null
	if [ "${samvideo}" == "yes" ]; then
		# Hide login prompt
		echo -e '\033[2J' > /dev/tty1
		# Hide blinking cursor
		echo 0 > /sys/class/graphics/fbcon/cursor_blink
		echo -e '\033[?17;0;0c' > /dev/tty1 
		
		misterini_mod
		get_dlmanager
		if [ ! -f "${mrsampath}"/mplayer ] || [ ! -f "${mrsampath}"/ytdl ]; then
			if [ -f "${mrsampath}"/mplayer.zip ]; then
				unzip -ojq "${mrsampath}"/mplayer.zip -d "${mrsampath}"
				curl_download "${mrsampath}"/ytdl "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_armv7l"
			else
				get_samvideo
			fi
		fi

		if { [ "$samvideo_source" == "local" ] || [ "$samvideo_source" == "youtube" ]; } && [ "$samvideo_tvc" == "yes" ]; then
			samini_mod samvideo_tvc no
		fi
	fi
	# Mute Global Volume
	# if Volume.dat exists, try to mute only if needed
	if [ "${mute}" != "no" ]; then
		if [ -f "${configpath}/Volume.dat" ]; then
		  only_mute_if_needed
	
		# if Volume.dat doesn’t exist yet, create it *and* mute
		else
		  # create a “level=0 + mute” byte = 0x10
		  write_byte "${configpath}/Volume.dat" "10"
		  echo "volume mute" > /dev/MiSTer_cmd
		  samdebug "Volume.dat created (0x10) and muted."
		fi
	fi
}

function sam_cleanup() {
	# Clean up by umounting any mount binds
	#[ -f "${configpath}/Volume.dat" ] && [ ${mute} == "yes" ] && rm "${configpath}/Volume.dat"
	only_unmute_if_needed
	[ "$(mount | grep -ic "${amigapath}"/shared)" == "1" ] && umount -l "${amigapath}/shared"
	[ -d "${misterpath}/Bootrom" ] && [ "$(mount | grep -ic 'bootrom')" == "1" ] && umount "${misterpath}/Bootrom"
	[ -f "${misterpath}/Games/NES/boot1.rom" ] && [ "$(mount | grep -ic 'nes/boot1.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot1.rom"
	[ -f "${misterpath}/Games/NES/boot2.rom" ] && [ "$(mount | grep -ic 'nes/boot2.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot2.rom"
	[ -f "${misterpath}/Games/NES/boot3.rom" ] && [ "$(mount | grep -ic 'nes/boot3.rom')" == "1" ] && umount "${misterpath}/Games/NES/boot3.rom"
	if [ "${mute}" != "no" ]; then
		readarray -t volmount <<< "$(mount | grep -i _volume.cfg | awk '{print $3}')"
		if [ "${#volmount[@]}" -gt 0 ]; then
			umount -l "${volmount[@]}" >/dev/null 2>&1
		fi
	fi
	if [ "${samvideo}" == "yes" ]; then
		echo 1 > /sys/class/graphics/fbcon/cursor_blink
		echo 'Super Attract Mode Video was used.' > /dev/tty1 
		echo 'Please reboot for proper MiSTer Terminal' > /dev/tty1 
		echo '' > /dev/tty1 
		echo 'Login:' > /dev/tty1 
		[ -f /tmp/.SAM_tmp/sv_corecount ] && rm /tmp/.SAM_tmp/sv_corecount
	fi
	samdebug "Cleanup done."
}

function sam_monitor() {

    tmux attach-session -t SAM
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
	if [ ! -f "${mrsampath}/samindex" ] || [ ! -f "${mrsampath}/MiSTer_SAM_MCP" ]; then
		echo " SAM required files not found."
		echo " Installing now."
		sam_update autoconfig
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



function deletegl() {
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
}


function creategl() {
	init_vars 
	read_samini 
	init_paths 
	init_data
	${mrsampath}/samindex -o "${gamelistpath}"
	
	if [ ${inmenu} -eq 1 ]; then
		sleep 1
		sam_menu
	else
		echo -e "\nGamelist creation successful. Please start SAM now.\n"
		sleep 1
		parse_cmd stop
	fi
}

function skipmessage() {
    local core=${1}

    # Exit immediately if the core argument is missing, for safety.
    if [ -z "${core}" ]; then
        return
    fi

    # Check the global 'skipmessage' setting AND the core-specific setting from the CORE_SKIP array.
    if [ "${skipmessage}" == "yes" ] && [ "${CORE_SKIP[${core}]}" == "yes" ]; then
        # If both are 'yes', wait for the configured time and send the button presses.
        sleep "$skiptime"
        samdebug "Button push sent for '${core}' to skip BIOS"
        "${mrsampath}/mbc" raw_seq :31
        sleep 1
        "${mrsampath}/mbc" raw_seq :31
    fi
}

function skipmessage_ao486() {
		sleep "$skiptime"
		samdebug "Button pushes sent to (hopefully) skip past selection screens"
		"${mrsampath}/mbc" raw_seq :02
		sleep 1
		"${mrsampath}/mbc" raw_seq :22
		sleep 1
		"${mrsampath}/mbc" raw_seq :1C
		sleep 1
		"${mrsampath}/mbc" raw_seq :19
		sleep 1
		"${mrsampath}/mbc" raw_seq :32
		sleep 1
		"${mrsampath}/mbc" raw_seq :3B

}

function mglfavorite() {
	# Add current game to _Favorites folder

	if [ ! -d "${misterpath}/_Favorites" ]; then
		mkdir -p "${misterpath}/_Favorites"
	fi
	cp /tmp/SAM_Game.mgl "${misterpath}/_Favorites/$(cat /tmp/SAM_Game.txt).mgl"

}

function ignoregame() {
	declare -l currentrbf="$(cat /tmp/SAM_Games.log | tail -n1 | awk -F- '{print $2}')"
	currentgame="$(cat /tmp/SAM_Games.log | tail -n1 | awk 'BEGIN{FS=OFS="\-"; }{for(i=3;i<NF;i++) printf "%s", $i OFS; print $NF }')"
	cr=`echo $currentrbf`
	cg=`echo $currentgame`
	if [ ! -f "${gamelistpath}/${cr}_excludelist.txt" ]; then
		touch "${gamelistpath}/${cr}_excludelist.txt"
	fi	
	echo ${cg} >> "${gamelistpath}/${cr}_excludelist.txt"
	echo "${currentgame:1} added to ${cr}_excludelist.txt"
	echo ""
	echo "Tip: If you want to add the game again, go to ${gamelistpath}/${cr}_excludelist.txt"
	echo ""
}
	

function delete_from_corelist() { # delete_from_corelist core tmp
	if [ -z "$2" ]; then
		for i in "${!corelist[@]}"; do
			if [[ ${corelist[i]} = "$1" ]]; then
				unset 'corelist[i]'
				samdebug "Deleted $1 from corelist"
			fi
		done
		samdebug "Corelist now ${corelist[@]}"
		printf "%s\n" "${corelist[@]}" > "${corelistfile}"
	else
		for i in "${!corelisttmp[@]}"; do
			if [[ ${corelisttmp[i]} = "$1" ]]; then
				unset 'corelisttmp[i]'
			fi
		done
	fi
}


function reset_core_gl() { # args ${nextcore}
	echo " Deleting old game lists for ${1^^}..."
	rm "${gamelistpath}/${1}_gamelist.txt" &>/dev/null
	sync "${gamelistpath}"
}



function core_error_checklist() { # core_error core /path/to/ROM
		delete_from_corelist "${1}"
		echo " List of cores is now: ${corelist[*]}"
		declare -g romloadfails=0
		# Load a different core
		next_core

}


function disable_bootrom() {
	if [ "${disablebootrom}" == "yes" ]; then
		# Make Bootrom folder inaccessible until restart
		mkdir -p /tmp/.SAM_List/Bootrom
		[ -d "${misterpath}/Bootrom" ] && [ "$(mount | grep -ic 'bootrom')" == "0" ] && mount --bind /tmp/.SAM_List/Bootrom "${misterpath}/Bootrom"
		# Disable Nes bootroms except for FDS Bios (boot0.rom)
		[ -f "${misterpath}/Games/NES/boot1.rom" ] && [ "$(mount | grep -ic 'nes/boot1.rom')" == "0" ] && touch "$brfake" && mount --bind "$brfake" "${misterpath}/Games/NES/boot1.rom"
		[ -f "${misterpath}/Games/NES/boot2.rom" ] && [ "$(mount | grep -ic 'nes/boot2.rom')" == "0" ] && touch "$brfake" && mount --bind "$brfake" "${misterpath}/Games/NES/boot2.rom"
		[ -f "${misterpath}/Games/NES/boot3.rom" ] && [ "$(mount | grep -ic 'nes/boot3.rom')" == "0" ] && touch "$brfake" && mount --bind "$brfake" "${misterpath}/Games/NES/boot3.rom"
	fi
}

function mute() {
	if [ "${mute}" == "core" ]; then
		samdebug "mute=core"
		only_unmute_if_needed
		# Create empty volume files. Only SD card write operation necessary for mute to work.
		[ ! -f "${configpath}/${1}_volume.cfg" ] && touch "${configpath}/${1}_volume.cfg"
		[ ! -f "/tmp/.SAM_tmp/SAM_config/${1}_volume.cfg" ] && touch "/tmp/.SAM_tmp/SAM_config/${1}_volume.cfg"		
		for i in {1..3}; do
		  if mount | grep -iq "${configpath}/${1}_volume.cfg"; then
			samdebug "${1}_volume.cfg already mounted"
			break
		  fi

		  mount --bind "/tmp/.SAM_tmp/SAM_config/${1}_volume.cfg" "${configpath}/${1}_volume.cfg"
		  
		  if [ $? -eq 0 ]; then
			samdebug "${1}_volume.cfg mounted successfully"
			break
		  else
			echo "ERROR: Failed to mute ${1} (attempt ${i})"
			if [ $i -eq 3 ]; then
			  echo "ERROR: All attempts to mute ${1} failed... Continuing."
			fi
			sleep 2
		  fi
		done
		[[ "$(mount | grep -ic "${1}"_volume.cfg)" != "0" ]] && echo -e "\0006\c" > "/tmp/.SAM_tmp/SAM_config/${1}_volume.cfg"
		# Only keep one volume.cfg file mounted
		if [ -n "${prevcore}" ] && [ "${prevcore}" != "${1}" ]; then
			umount "${configpath}/${prevcore}_volume.cfg"
			sync
		fi	
		prevcore=${1}
	fi
}


# Helper: write_byte
# Writes a single byte (given as a two-digit hex string) into a file, then syncs.
#
# Arguments:
#   $1 = path to file (e.g. "${configpath}/Volume.dat")
#   $2 = two-digit hex string representing the byte to write (e.g. "05", "15")

function write_byte() {
  local f="$1"; local hex="$2"
  printf '%b' "\\x$hex" > "$f" && sync
}

# Sets the “mute” bit in Volume.dat without altering your current volume level.
# Then issues a live “volume mute” command to the running MiSTer core.
function global_mute() {
	local f="${configpath}/Volume.dat"
	local cur m hex
	
	# read the single-byte value, e.g. "05"
	cur=$(xxd -p -c1 "$f")
	
	# OR in the mute-flag (0x10)
	m=$(( 0x$cur | 0x10 ))
	
	# format back to two-digit hex, then write that single byte
	hex=$(printf '%02x' "$m")
	write_byte "$f" "$hex"
	
	# immediately mute the live core
	echo "volume mute" > /dev/MiSTer_cmd
	samdebug "Global mute → Volume.dat=0x${hex}"
}

function global_unmute() {
	local f="${configpath}/Volume.dat"
	local cur hex u
	cur=$(xxd -p -c1 "$f")
	u=$((0x$cur & 0x0F))
	hex=$(printf '%02x' "$u")
	write_byte "$f" "$hex"
	# sent unmute for interactive unmute
	echo "volume unmute" > /dev/MiSTer_cmd
	echo "Restored Volume.dat to 0x$hex"
}


function only_mute_if_needed() {
  local f="${configpath}/Volume.dat"
  local cur

  # 1) read the single byte as two hex digits, e.g. "05" or "15"
  cur=$(xxd -p -c1 "$f")

  # 2) test bit 4 (0x10).  If (cur & 0x10) == 0 then we’re not muted yet.
  if (( (0x$cur & 0x10) == 0 )); then
    samdebug "Volume not yet muted (Volume.dat=0x$cur) → muting now"
    global_mute
  else
    samdebug "Already muted (Volume.dat=0x$cur) → skipping write"
  fi
}


function only_unmute_if_needed() {
  local f="${configpath}/Volume.dat"
  local cur

  # 1) Read the single-byte value, e.g. "15" if muted at level5, or "05" if unmuted
  cur=$(xxd -p -c1 "$f")

  # 2) If bit4 (0x10) *is* set, we’re currently muted → clear it
  if (( (0x$cur & 0x10) != 0 )); then
    samdebug "Volume is muted (Volume.dat=0x$cur) → unmuting now"
    global_unmute
    return 0    # indicate we did an unmute
  else
    samdebug "Volume already unmuted (Volume.dat=0x$cur) → skipping write"
    return 1    # indicate no action taken
  fi
}


function check_zips() { # check_zips core
	# Check if zip still exists
	#samdebug "Checking zips in file..."
	unset zipsondisk
	unset zipsinfile
	unset files
	unset newfiles
	mapfile -t zipsinfile < <(fgrep ".zip" "${gamelistpath}/${1}_gamelist.txt" | awk -F".zip" '!seen[$1]++' | awk -F".zip" '{print $1}' | sed -e 's/$/.zip/')
	if [ ${#zipsinfile[@]} -gt 0 ]; then
		for zips in "${zipsinfile[@]}"; do
			if [ ! -f "${zips}" ]; then
				samdebug "Creating new game list because zip file[s] seems to have changed."
				create_gamelist "${1}"
				unset zipsinfile
				mapfile -t zipsinfile < <(fgrep ".zip" "${gamelistpath}/${1}_gamelist.txt" | awk -F".zip" '!seen[$1]++' | awk -F".zip" '{print $1}' | sed -e 's/$/.zip/')
				break
				return
			fi
		done
		#samdebug "Done."
		#samdebug -n "Checking zips on disk..."
		if [ "${checkzipsondisk}" == "yes" ]; then 
			# Check for new zips
			corepath="$("${mrsampath}"/samindex -q -s "${1}" -d |awk -F':' '{print $2}')"
			readarray -t files <<< "$(find "${corepath}" -maxdepth 2 -type f -name "*.zip")"
			extgrep=$(echo ".${CORE_EXT[${1}]}" | sed -e "s/,/\\\|/g"| sed 's/,/,./g')
			# Check which files have valid roms
			readarray -t newfiles <<< "$(printf '%s\n'  "${zipsinfile[@]}" "${files[@]}"  | sort | uniq -iu )"
			if [[ "${newfiles[*]}" ]]; then
				for f in "${newfiles[@]}"; do
					if [ -f "${f}" ]; then
						if "${mrsampath}"/partun -l "${f}" --ext "${extgrep}" | grep -q "${extgrep}"; then
							zipsondisk+=( "${f}" )
						fi
					else
						samdebug "Zip file ${f} not found"
					fi
				done
			fi
			if [[ "${zipsondisk[*]}" ]]; then
				result="$(printf '%s\n' "${zipsondisk[@]}")"
				if [[ "${result}" ]]; then
					samdebug "Found new zip file[s]: ${result##*/}"
					create_gamelist "${1}"
					return
				fi
			fi
		fi
	fi
	#samdebug "Done."
}
	
	
function check_gamelists() {
    # --- build the list of cores that need a gamelist ---
    unset glcreate
    readarray -t glexistcl <<< "$(
        printf '%s\n' "${corelist[@]}" "${glondisk[@]}" |
        sort | uniq -iu
    )"

    for g in "${glexistcl[@]}"; do
        for c in "${corelist[@]}"; do
            [[ "$c" == "$g" ]] && glcreate+=( "$c" )
        done
    done

    # --- filter out all the special cores completely ---
    local filtered=()
    for c in "${glcreate[@]}"; do
        # only keep if c is NOT in special_cores
        if [[ ! " ${special_cores[*]} " =~ " $c " ]]; then
            filtered+=( "$c" )
        fi
    done
    glcreate=( "${filtered[@]}" )

    # --- if anything left to create, and no samindex already running ---
    if (( ${#glcreate[@]} )) && ! pgrep -f samindex &>/dev/null; then
        nogames=()
        for c in "${glcreate[@]}"; do
            samdebug "Creating $c gamelist"
            "${mrsampath}/samindex" -q -s "$c" -o "$gamelistpath"
            (( $? > 1 )) && nogames+=( "$c" )
        done

        # handle cores for which no games were found
        if (( ${#nogames[@]} )); then
            for f in "${nogames[@],,}"; do
                samdebug "Deleting ${f}"
                delete_from_corelist "$f"
                delete_from_corelist "$f" tmp
            done
            echo "SAM now has the following cores disabled: ${nogames[*]}"
            echo "No games were found for these cores."
        fi
    fi
}

function filter_list() { # args: core
    local core=${1}
    local master_list="${gamelistpath}/${core}_gamelist.txt"
    local session_list="${gamelistpathtmp}/${core}_gamelist.txt"

    # Always start with a fresh copy of the master list in our working file.
    cp -f "${master_list}" "${tmpfile}"

    # --- Each filter now reads from $tmpfile and writes its output back to $tmpfile ---
    # --- ALL informational 'echo' commands are redirected to stderr (>&2) ---

    if [ -n "${PATHFILTER[${core}]}" ]; then
        echo "Applying path filter for '${core}': ${PATHFILTER[${core}]}" >&2
        grep -F "${PATHFILTER[${core}]}" "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    fi

    if [[ "${core}" == "arcade" ]] && [ -n "${arcadeorient}" ]; then
        echo "Applying orientation filter for Arcade: ${arcadeorient}" >&2
        grep -Fi "${arcadeorient}" "${tmpfile}" > "${tmpfile}.filtered"
        if [ -s "${tmpfile}.filtered" ]; then
            mv -f "${tmpfile}.filtered" "${tmpfile}"
        else
            echo "Warning: Orientation filter produced no results." >&2
        fi
    fi

    if [ "$dupe_mode" = "strict" ]; then
        # samdebug already prints to stderr, so it's safe.
        samdebug "Using strict mode to filter duplicates..."
        awk -F'/' '
        {
            full = $0; lowpath = tolower(full)
            if ( lowpath ~ /\/[^\/]*(hack|beta|proto)[^\/]*\// ) next
            fname = $NF; if ( tolower(fname) ~ /\([^)]*(hack|beta|proto)[^)]*\)/ ) next
            name = fname; sub(/\.[^.]+$/, "", name); sub(/\s*\(.*/, "", name)
            sub(/^([0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?|[0-9]+)[^[:alnum:]]*/, "", name)
            key = tolower(name); gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (!seen[key]++) print full
        }' "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    else
        awk -F'/' '!seen[$NF]++' "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    fi

    if [ -f "${gamelistpath}/${core}_gamelist_exclude.txt" ]; then
        echo "Applying category excludelist for '${core}'..." >&2
        awk 'FNR==NR{a[$0];next} !($0 in a)' "${gamelistpath}/${core}_gamelist_exclude.txt" "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    fi

    if [ -f "${gamelistpath}/${core}_excludelist.txt" ]; then
        echo "Applying standard excludelist for '${core}'..." >&2
        awk -v EXCL="${gamelistpath}/${core}_excludelist.txt" 'BEGIN{while(getline line<EXCL){raw[line]=1;name=line;sub(/\.[^.]*$/,"",name);sub(/^.*\//,"",name);names[name]=1}close(EXCL)}{file=$0;base=file;sub(/\.[^.]*$/,"",base);sub(/^.*\//,"",base);if(file in raw||base in names)next;print}' \
        "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}"
    fi

    if [ "${rating}" != "no" ]; then
        apply_ratings_filter "${core}" "${tmpfile}"
    fi

    if [[ "${exclude[*]}" ]]; then
        for e in "${exclude[@]}"; do
            grep -viw "$e" "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}" || true
        done
    fi

    if [ "${disable_blacklist}" == "no" ] && [ -f "${gamelistpath}/${core}_blacklist.txt" ]; then
        echo -n "Applying static screen blacklist for '${core}'..." >&2
        awk "BEGIN{while(getline<\"${gamelistpath}/${core}_blacklist.txt\"){a[\$0]=1}} {gamelistfile=\$0;sub(/\\.[^.]*\$/,\"\",gamelistfile);sub(/^.*\\//,\"\",gamelistfile);if(!(gamelistfile in a))print}" \
        "${tmpfile}" > "${tmpfile}.filtered"
        if [ -s "${tmpfile}.filtered" ]; then
            mv -f "${tmpfile}.filtered" "${tmpfile}"
        fi
    fi

    cp -f "${tmpfile}" "${session_list}"
    echo " $(wc -l <"${session_list}") games are now in the active shuffle list." >&2

    if [ ! -s "${session_list}" ]; then
        echo "Error: All filters combined produced an empty list for '${core}'." >&2
        delete_from_corelist "${core}"
        return 1
    fi

    return 0
}

# Helper function to contain the complex ratings logic
function apply_ratings_filter() {
    local core=${1}
    local target_file=${2} # Pass the file to modify ($tmpfile)
    echo "Ratings Mode '${rating}' active - Filtering Roms for '${core}'..."
    # ... (The full code for apply_ratings_filter from the previous response goes here) ...
}


function samdebug() {
    local ts msg
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    msg="$*"

    if [[ "${samdebug}" == "yes" ]]; then
        # The '>&2' at the end redirects this message to stderr.
        # This prevents it from being captured by command substitution.
        echo -e "\e[1m\e[31m[${ts}] ${msg}\e[0m" >&2
    fi

    if [[ "${samdebuglog}" == "yes" ]]; then
        # Writing to a log file is already separate and is perfectly fine.
        echo "[${ts}] ${msg}" >> /tmp/samdebug.log
    fi
}

samini_mod() {
  local key="$1"
  local value="$2"
  local file="${3:-/media/fat/Scripts/MiSTer_SAM.ini}"
  local formatted="${key}=\"${value}\""

  if grep -q "^${key}=" "$file"; then
    sed -i "/^${key}=/c\\${formatted}" "$file"
  else
    echo "$formatted" >> "$file"
  fi
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

# ======== BACKGROUND MUSIC PLAYER FUNCTIONS ========

function bgm_start() {

	if [ "${bgm}" == "yes" ]; then
		if [ ! "$(ps -o pid,args | grep '[b]gm' | head -1)" ]; then
			/media/fat/Scripts/bgm.sh &>/dev/null &
			sleep 2
		else
			echo "BGM already running."
		fi
		echo -n "set playincore yes" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
		sleep 1
		echo -n "set playback random" | socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
		sleep 1
		echo -n "play" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null

	else
		# In case BGM is running, let's stop it
		if [ "$(ps -o pid,args | grep '[b]gm' | head -1)" ]; then
			bgm_stop force
		fi
	fi
	

}

function bgm_stop() {

	if [ "${bgm}" == "yes" ] || [ "$1" == "force" ]; then
		echo -n "Stopping Background Music Player... "
		echo -n "set playincore no" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
		echo -n "stop" | socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
		sleep 0.2
		if [ "${bgmstop}" == "yes" ]; then
			echo -n "stop" | socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
			sleep 0.2
			echo -n "set playback disabled" | socat - UNIX-CONNECT:/tmp/bgm.sock 2>/dev/null
			kill -9 "$(ps -o pid,args | grep '[b]gm.sh' | awk '{print $1}' | head -1)" 2>/dev/null
			kill -9 "$(ps -o pid,args | grep 'mpg123' | awk '{print $1}' | head -1)" 2>/dev/null
			rm /tmp/bgm.sock 2>/dev/null
			if [ "${gvoladjust}" -ne 0 ]; then
				#local oldvol=$((7 - $currentvol + $gvoladjust))
				#samdebug "Changing global volume back to $oldvol"
				#echo "volume ${oldvol}" > /dev/MiSTer_cmd &
				echo -e "\00$currentvol\c" >"${configpath}/Volume.dat"
			fi
		fi
		echo "Done."
	fi

}

# ======== tty2oled FUNCTIONS ========

function tty_start() {
	if [ "${ttyenable}" == "yes" ]; then 
		[ -f /tmp/.SAM_tmp/tty_currentinfo ] && rm /tmp/.SAM_tmp/tty_currentinfo 
		#[ -f /media/fat/tty2oled/S60tty2oled ] && /media/fat/tty2oled/S60tty2oled restart && sleep 3
		touch "${tty_sleepfile}"
		echo -n "Starting tty2oled... "
		tmux new -s OLED -d "${mrsampath}/MiSTer_SAM_tty2oled" &>/dev/null
		echo "Done."
	fi
}

function tty_exit() {
	if [ "${ttyenable}" == "yes" ]; then
		echo -n "Stopping tty2oled... "
		[[ -p ${TTY_cmd_pipe} ]] && echo "stop" >${TTY_cmd_pipe} &
		tmux kill-session -t OLED &>/dev/null
		rm "${tty_sleepfile}" &>/dev/null
		#/media/fat/tty2oled/S60tty2oled restart 
		#sleep 5

		echo "Done."
	fi
}

function write_to_TTY_cmd_pipe() {
	[[ -p ${TTY_cmd_pipe} ]] && echo "${@}" >${TTY_cmd_pipe}
}

# ======== SAM VIDEO PLAYER FUNCTIONS ========
function misterini_mod() {
    # Check if sv_inimod is set to "no"
    if [ "$sv_inimod" == "no" ]; then
        echo "sv_inimod is set to 'no'. Skipping MiSTer.ini modification."
        return 0
    fi

    echo "Checking and updating /media/fat/MiSTer.ini for samvideo playback."

    # Desired settings
    fb_terminal="1"
    vga_scaler="1"

    if [ "$samvideo_output" == "hdmi" ]; then
        if [ "$samvideo_source" == "youtube" ]; then
            ini_res="640x360"
        else
            ini_res="640x480"
        fi
        if [ "${sv_aspectfix_vmode}" == "yes" ]; then
            video_mode="6"
        else
            video_mode="8"
        fi
    elif [ "$samvideo_output" == "crt" ]; then
        if [ "$samvideo_source" == "youtube" ]; then
            samvideo_crtmode="${samvideo_crtmode320}"
        elif [ "$samvideo_source" == "archive" ]; then
            samvideo_crtmode="${samvideo_crtmode640}"
        fi
        video_mode="$(echo "$samvideo_crtmode" | awk -F'=' '{print $2}')"
    else
        echo "Unknown video output mode: $samvideo_output"
        return 1
    fi

    # Desired `[Menu]` values
    declare -A desired_menu
    desired_menu["video_mode"]="$video_mode"
    desired_menu["fb_terminal"]="$fb_terminal"
    desired_menu["vga_scaler"]="$vga_scaler"

    ini_file="/media/fat/MiSTer.ini"
    temp_file=$(mktemp)

    # Extract all existing `[Menu]` values and comments
    declare -A existing_menu
    declare -A comments
    while IFS="=" read -r key value; do
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')   # Trim spaces
        if [[ "$value" == *";"* ]]; then
            comments["$key"]="${value#*;}"  # Extract comment, preserving its formatting
            value="${value%;*}"            # Remove comment from value
        fi
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') # Trim spaces
        existing_menu["$key"]="$value"
    done < <(awk '
    BEGIN { inside_menu = 0 }
/^[[][Mm][Ee][Nn][Uu][]]/ { inside_menu = 1; next }
/^[[]/ && !/^[[][Mm][Ee][Nn][Uu][]]/ { inside_menu = 0 }
inside_menu && /=/ { print }
' "$ini_file")

    # Merge desired values into existing `[Menu]` values
    for key in "${!desired_menu[@]}"; do
        if [[ -n "${existing_menu[$key]}" && "${existing_menu[$key]}" != "${desired_menu[$key]}" ]]; then
            # Preserve existing `Previous:` comment if it exists
            if [[ "${comments[$key]}" != *"Previous"* ]]; then
                comments["$key"]=" Previous: ${existing_menu[$key]}"
            fi
            existing_menu["$key"]="${desired_menu[$key]}"
        else
            # If no change, retain the existing comment
            existing_menu["$key"]="${desired_menu[$key]}"
        fi
    done

    # Construct the new `[Menu]` section
    new_menu="[Menu]"
    new_menu+=$'\n'"; Modified by SAM Video. Please set video_mode in MiSTer_SAM.ini or disable SAM's ini mod by setting sv_inimod to no"
    for key in "${!existing_menu[@]}"; do
        if [[ -n "${comments[$key]}" ]]; then
            # Include comments with exactly one space after the value
            new_menu+=$'\n'"$key=${existing_menu[$key]} ;${comments[$key]}"
        else
            # Add key-value pair without comments
            new_menu+=$'\n'"$key=${existing_menu[$key]}"
        fi
    done

    # Remove all existing `[Menu]` sections and write the rest of the file to a temp file
    awk '
    BEGIN { inside_menu = 0 }
/^[[][Mm][Ee][Nn][Uu][]]/ { inside_menu = 1; next }
/^[[]/ && !/^[[][Mm][Ee][Nn][Uu][]]/ { inside_menu = 0 }
!inside_menu { print }
' "$ini_file" > "$temp_file"

    # Append the new `[Menu]` section without extra blank lines
    echo "$new_menu" >> "$temp_file"

    # Compare checksums to decide if a write operation is needed
    original_checksum=$(md5sum "$ini_file" | awk '{print $1}')
    new_checksum=$(md5sum "$temp_file" | awk '{print $1}')

    if [ "$original_checksum" == "$new_checksum" ]; then
        rm "$temp_file"
        echo "MiSTer.ini update not needed."
    else
        # Replace the original file with the updated version
        cp "$ini_file" "${ini_file}.bak"
        mv "$temp_file" "$ini_file"
        echo "MiSTer.ini updated successfully."
    fi
}

function dl_video() {
    rm -f "$tmpvideo"

    if [ "$download_manager" = "yes" ]; then
        /media/fat/linux/aria2c \
            --dir="$(dirname "$tmpvideo")" \
            --file-allocation=none \
            -o "$(basename "$tmpvideo")" \
            -s 4 -x 4 -k 1M \
            --summary-interval=0 \
            --console-log-level=warn \
            --download-result=hide \
            --quiet=false \
            --allow-overwrite=true \
            --ca-certificate=/etc/ssl/certs/cacert.pem \
            "${1}"
    else
        wget -q --show-progress -O "$tmpvideo" "${1}"
    fi

    # Check if the download was successful
    if [ $? -eq 0 ] && [ "$keep_local_copy" == "yes" ]; then
        # Reuse `local_svfile` for saving the local copy
        cp "$tmpvideo" "$local_svfile"
    fi
}

function sv_yt_download() {
    local resolution="$1" # Resolution (360 or 240)
    local list_file="$2"  

    samvideo_list="/tmp/.SAM_List/sv_youtube_list.txt"
    local format="best[height=${resolution}][ext=mp4]"

    # Ensure the samvideo_list is populated
    if [ ! -s "${samvideo_list}" ]; then
        cp "${list_file}" "${samvideo_list}"
    fi

    echo "Please wait... downloading file"
    local url=""
    while [ -z "$url" ]; do
        url=$(shuf -n1 ${samvideo_list})
        "${mrsampath}/ytdl" --format "${format}" --no-continue -o "/tmp/%(title)s (YT).mp4" "$url"
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            echo "Download successful!"
            sv_selected=$(ls /tmp | grep "(YT)")
            mv "/tmp/${sv_selected}" "${tmpvideo}"
            break
        else
            echo "Invalid URL or download error. Retrying with another URL..."
            awk -v Line="$url" '!index($0, Line)' "${list_file}" >${tmpfile} && cp -f ${tmpfile} "${list_file}"
            cp "${list_file}" "${samvideo_list}"
            url=""
        fi
    done

    # Update samvideo_list to remove the processed URL
    awk -v Line="$url" '!index($0, Line)' "${samvideo_list}" >${tmpfile} && cp -f ${tmpfile} "${samvideo_list}"

    # Set resolution-specific variables
    if [ "$resolution" -eq 360 ]; then
        res="$(LD_LIBRARY_PATH=${mrsampath} ${mrsampath}/mplayer -vo null -ao null -identify -frames 0 "$tmpvideo" 2>/dev/null | grep "VIDEO:" | awk '{print $3}')"
        res_space=$(echo "$res" | tr 'x' ' ')
    else
        res_space="640 240"
    fi
}

function sv_ar_download() {
    local resolution="$1"   # Resolution, 480 or 240
    local list_file="$2"    # Associated list file, sv_archive_hdmilist or sv_archive_crtlist

    samvideo_list="/tmp/.SAM_List/sv_archive_list.txt"
    local http_archive="${list_file//https/http}"

    # Populate the samvideo_list if it's empty
    if [ ! -s "${samvideo_list}" ]; then
        curl_download /tmp/SAMvideos.xml "${http_archive}"
        grep -o '<file name="[^"]\+\.avi"' /tmp/SAMvideos.xml \
            | sed 's/<file name="//;s/"$//' \
            | sed 's/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/\</g; s/&gt;/\>/g; s/&quot;/\"/g; s/#&#39;/\'"'"'/g; s/&ldquo;/\"/g; s/&rdquo;/\"/g;' \
            > "${samvideo_list}"
    fi

    # Select a video and check availability
    while true; do
        if [ "$samvideo_tvc" == "yes" ]; then
            samvideo_tvc
        else
            sv_selected="$(shuf -n1 "${samvideo_list}")"
        fi
        sv_selected_url="${http_archive%/*}/${sv_selected}"

        # Check if the URL is available using wget
        samdebug "Checking availability of ${sv_selected_url}..."
        if wget --spider --quiet "${sv_selected_url}"; then
            samdebug "URL is available: ${sv_selected_url}"
            break
        else
            samdebug "URL is not available: ${sv_selected_url}. Removing from list and selecting another."
            awk -v Line="$sv_selected" '!index($0, Line)' "${samvideo_list}" >"${tmpfile}" && cp -f "${tmpfile}" "${samvideo_list}"
        fi
    done

    tmpvideo="/tmp/SAMvideo.avi"
	local local_svfile="${samvideo_path}/$(echo "$sv_selected" | sed "s/[\":?]//g")"
	samdebug "Checking if file is available locally...$local_svfile"


    if [ -f "$local_svfile" ]; then
        echo "Local file exists: $local_svfile"
        cp "$local_svfile" "$tmpvideo"
    else
        echo "Preloading ${sv_selected} from archive.org for smooth playback"
        dl_video "${sv_selected_url}"
    fi

    # Update samvideo_list to remove the processed file 
	if [ "$samvideo_tvc" == "no" ]; then
		awk -vLine="$sv_selected" '!index($0,Line)' "${samvideo_list}" >${tmpfile} && cp -f ${tmpfile} "${samvideo_list}"
	fi

    # Set resolution-specific variables
    if [ "$resolution" -eq 480 ]; then
        res_space="640 480"
    else
        res_space="640 240"
    fi
}



function sv_local() {
	samvideo_list="/tmp/.SAM_List/sv_local_list.txt"
	if [ ! -s ${samvideo_list} ]; then
		find "$samvideo_path" -type f > ${samvideo_list}
	fi
	tmpvideo=$(cat ${samvideo_list} | shuf -n1)
	awk -vLine="$tmpvideo" '!index($0,Line)' ${samvideo_list} >${tmpfile} && cp -f ${tmpfile} ${samvideo_list}
	res="$(LD_LIBRARY_PATH=${mrsampath} ${mrsampath}/mplayer -vo null -ao null -identify -frames 0 "$tmpvideo" 2>/dev/null | grep "VIDEO:" | awk '{print $3}')"
	res_space=$(echo "$res" | tr 'x' ' ')
	sv_selected="$(basename "${tmpvideo}")"

}

function samvideo_tvc() {
    if [ ! -f "${gamelistpath}/nes_tvc.txt" ]; then
        get_samvideo
    fi

    # Setting corelist to available commercials
    unset TVC_LIST
    unset SV_TVC_CL
    for g in "${!SV_TVC[@]}"; do 
        for c in "${corelist[@]}"; do 
            if [[ "$c" == "$g" ]]; then 
                SV_TVC_CL+=("$c")
            fi
        done 
    done
    samdebug "samvideo corelist: ${SV_TVC_CL[@]}"
    pick_core SV_TVC_CL
    samdebug "nextcore = $nextcore"

    # Initialize variables
    count=0
    local gamelist_tmp="${gamelistpathtmp}/${nextcore}_tvc.txt"
    local gamelist_original="${gamelistpath}/${nextcore}_tvc.txt"

    # Ensure a local temporary copy exists or reset it if empty
	if [ ! -f "$gamelist_tmp" ] || [ ! -s "$gamelist_tmp" ] || [ "$(cat "$gamelist_tmp")" = "{}" ]; then
        samdebug "Copying original gamelist to temporary file: $gamelist_tmp"
        cp "$gamelist_original" "$gamelist_tmp"
    fi

    while [ $count -lt 15 ]; do
        if [ -f "$gamelist_tmp" ]; then
            samdebug "$gamelist_tmp found."

            # Select a random game and its corresponding entry
            sv_selected=$(jq -r 'keys[]' "$gamelist_tmp" | shuf -n 1)
            tvc_selected=$(jq -r --arg key "$sv_selected" '.[$key]' "$gamelist_tmp")

            # Remove the selected entry from the temporary file
            samdebug "Removing $sv_selected from $gamelist_tmp"
            jq --arg key "$sv_selected" 'del(.[$key])' "$gamelist_tmp" > "${gamelist_tmp}.tmp" && mv "${gamelist_tmp}.tmp" "$gamelist_tmp"
            # Save the selected game information
            echo "${tvc_selected}" > /tmp/.SAM_tmp/sv_gamename
            break
        else
            # If the file is not found, select a new core randomly
            pick_core SV_TVC_CL
            samdebug "${nextcore}_tvc.txt not found, selecting new core."
        fi

        ((count++))
    done

    echo $nextcore > /tmp/.SAM_tmp/sv_core
    samdebug "Searching for ${SV_TVC[$nextcore]}"
    if [ -z "${tvc_selected}" ]; then
        echo "Couldn't find TVC list. Selecting random game from system"
        sv_selected="$(cat ${samvideo_list} | grep -i "${SV_TVC[$nextcore]}" | shuf --random-source=/dev/urandom | head -1)"
    fi
    samdebug "Picked $sv_selected"
}



## Play video
function samvideo_play() {
	if [ "${samvideo_source}" == "youtube" ] && [ "$samvideo_output" == "hdmi" ]; then
		sv_yt_download 360 "${sv_youtube_hdmilist}"
	elif [ "${samvideo_source}" == "youtube" ] && [ "$samvideo_output" == "crt" ]; then
		sv_yt_download 240 "${sv_youtube_crtlist}"
	elif [ "${samvideo_source}" == "archive" ] && [ "$samvideo_output" == "hdmi" ]; then
		sv_ar_download 480 "${sv_archive_hdmilist}"
	elif [ "${samvideo_source}" == "archive" ] && [ "$samvideo_output" == "crt" ]; then
		sv_ar_download 240 "${sv_archive_crtlist}"
	elif [ "${samvideo_source}" == "local" ]; then
		sv_local
	fi
	
	if [ -z "${sv_selected}" ]; then
		echo "Error while downloading"
		echo "1" > "$sv_gametimer_file"
		return
	fi
	
	sv_gametimer="$(LD_LIBRARY_PATH=${mrsampath} ${mrsampath}/mplayer -vo null -ao null -identify -frames 0 "$tmpvideo" 2>/dev/null | grep "ID_LENGTH" | sed 's/[^0-9.]//g' | awk -F '.' '{print $1}')"
	sv_title=${sv_selected%.*}

	#Show tty2oled splash
	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			[core_pretty]="SAM Video Player"
			[name]="${sv_title}"
			[core]=SAM_splash
			[date]=$EPOCHSECONDS
			[counter]=${sv_gametimer}
			[name_scroll]="${sv_title:0:21}"
			[name_scroll_position]=0
			[name_scroll_direction]=1
			[update_pause]=${ttyupdate_pause}
		)
	
		declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
		tty_displayswitch=$(($gametimer / $ttycoresleep - 1))
		write_to_TTY_cmd_pipe "display_info" &		
		local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
		SECONDS=${elapsed}
	fi
	
	
	if [ "$mute" != "no" ] || [ "$bgm" == "yes" ]; then
		options="-nosound"
	fi
	
	
	if [ -s "$tmpvideo" ]; then
		echo load_core /media/fat/menu.rbf > /dev/MiSTer_cmd
		sleep "${samvideo_displaywait}"
		# TODO delete blinking cursor
		#echo "\033[?25l" > /dev/tty1
		#setterm -cursor off
		echo $(("$sv_gametimer" + 2)) > "$sv_gametimer_file"
		${mrsampath}/mbc raw_seq :43
		vmode -r ${res_space} rgb32
		echo -e "\nPlaying video now.\n"
		echo -e "Title: ${sv_selected%.*}"
		echo -e "Resolution: ${res_space}"
		echo -e "Length: ${sv_gametimer} seconds\n"

		nice -n -20 env LD_LIBRARY_PATH=${mrsampath} ${mrsampath}/mplayer -msglevel all=0:statusline=5 "${options}" "$tmpvideo" 2>/dev/null 
		rm "$sv_gametimer_file" 2>/dev/null
	else
		echo "No video was downloaded. Skipping video playback.."
		echo "1" > "$sv_gametimer_file"
		return
	fi
	#echo load_core /media/fat/menu.rbf > /dev/MiSTer_cmd
	#next_core
}



# ======== SAM UPDATE ========


function curl_download() { # curl_download ${filepath} ${URL}

	curl \
		--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
		--insecure \
		--fail \
		--location \
		-o "${1}" \
		"${2}"
}


function check_and_update() {
    local url="$1"
    local tmp_file="$2"
    local local_file="$3"
    local description="$4"

    # Fetch the remote file size (follow redirects)
    remote_size=$(curl -sI --location --insecure "$url" | awk '/^Content-Length:/ {size=$2} END {print size}' | tr -d '\r')
    if [ -z "$remote_size" ]; then
        echo "Error: Unable to determine the size of $description at $url" >&2
        return 1
    fi

    # Get the local file size, if it exists
    if [ -f "$local_file" ]; then
        local_size=$(stat --format="%s" "$local_file")
    else
        local_size=0
    fi

    # Debugging output
    samdebug "Remote size: $remote_size"
    samdebug "Local size: $local_size"

    # Compare sizes and update if needed
    if [ "$remote_size" -eq "$local_size" ]; then
        echo "$description is up-to-date. No update required."
        return 0  # File is up-to-date
    else
        echo "Sizes differ. Updating $description..."
        curl_download "$tmp_file" "$url" || return 1  # Download failed
        mv "$tmp_file" "$local_file" || { echo "Error: Unable to move $tmp_file to $local_file" >&2; return 1; }
        echo "$description updated successfully."
        return 2  # File was updated
    fi
}




function get_samstuff() { #get_samstuff file (path)
	
	if [ -z "${1}" ]; then
		return 1
	fi

	filepath="${2}"
	if [ -z "${filepath}" ]; then
		filepath="${mrsampath}"
	fi

	echo -n " Downloading from ${raw_base}/${1} to ${filepath}/..."
	curl_download "/tmp/${1##*/}" "${raw_base}/${1}"


	if [ ! "${filepath}" == "/tmp" ]; then
		mv --force "/tmp/${1##*/}" "${filepath}/${1##*/}"
	fi

	if [ "${1##*.}" == "sh" ]; then
		chmod +x "${filepath}/${1##*/}"
	fi

	echo " Done."
}

function get_partun() {
    REPOSITORY_URL="https://github.com/woelper/partun"
    echo "Downloading partun - needed for unzipping roms from big archives..."
    echo "Created for MiSTer by woelper - Talk to him at this year's PartunCon"
    echo "${REPOSITORY_URL}"

    # Fetch the latest download URL for partun
    latest=$(curl -s -L --insecure https://api.github.com/repos/woelper/partun/releases/latest | jq -r ".assets[] | select(.name | contains(\"armv7\")) | .browser_download_url")
    if [ -z "$latest" ]; then
        echo "Error: Unable to fetch the latest release URL for partun" >&2
        return 1
    fi

    # Define paths
    tmp_file="/tmp/partun"
    local_file="${mrsampath}/partun"

    # Check and update partun
    check_and_update "$latest" "$tmp_file" "$local_file" "partun"
    result=$?

}




function get_samindex() {
    echo "Downloading samindex - needed for creating gamelists..."
    echo "Created for MiSTer by wizzo"
    echo "https://github.com/wizzomafizzo/mrext"

    # Define URLs and file paths
    latest_url="${raw_base}/.MiSTer_SAM/samindex"
    tmp_file="/tmp/samindex"
    local_file="${mrsampath}/samindex"

    # Check and update samindex
    check_and_update "$latest_url" "$tmp_file" "$local_file" "samindex"

}


function get_samvideo() {
    echo "Checking and updating components for SAM video playback..."
    echo "Created for MiSTer by wizzo"
    echo "https://github.com/wizzomafizzo/mrext"

    # Define URLs and file paths
    latest_mplayer="${raw_base}/.MiSTer_SAM/mplayer.zip"
    tmp_mplayer="/tmp/mplayer.zip"
    local_mplayer="${mrsampath}/mplayer.zip"

    latest_ytdl="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_armv7l"
    tmp_ytdl="/tmp/yt-dlp"
    local_ytdl="${mrsampath}/ytdl"

    # Check and update mplayer
    check_and_update "$latest_mplayer" "$tmp_mplayer" "$local_mplayer" "mplayer" 
	result=$?
	if [ "$result" -eq 2 ] || [ ! -f "${mrsampath}/mplayer" ]; then
        echo "Extracting mplayer..."
        unzip -ojq "$local_mplayer" -d "${mrsampath}" || {
            echo "Error: Failed to extract mplayer.zip" >&2
            return 1
        }
        echo "mplayer updated and extracted successfully."
    fi

    # Check and update yt-dlp
    check_and_update "$latest_ytdl" "$tmp_ytdl" "$local_ytdl" "yt-dlp" 


    # Check and update SAM gamelists
	echo "Checking and updating SAM gamelists..."
	for key in "${!SV_TVC[@]}"; do
		local_file="${mrsampath}/SAM_Gamelists/${key}_tvc.txt"
		tmp_file="/tmp/${key}_tvc.txt"
		remote_url="${raw_base}/.MiSTer_SAM/SAM_Gamelists/${key}_tvc.txt"

		check_and_update "$remote_url" "$tmp_file" "$local_file" "${key}_tvc gamelist"
	done

    echo "Done."
}



function get_mbc() {
    echo "Downloading mbc - Control MiSTer from cmd..."
    echo "Created for MiSTer by pocomane"
    remote_url="${raw_base}/.MiSTer_SAM/mbc"
    tmp_file="/tmp/mbc"
    local_file="${mrsampath}/mbc"

    check_and_update "$remote_url" "$tmp_file" "$local_file" "mbc"
	
}


function get_inputmap() {
    echo "Downloading input maps - needed to skip past BIOS for some systems..."
    [ ! -d "${configpath}/inputs" ] && mkdir -p "${configpath}/inputs"

    for input_file in \
        "GBA_input_1234_5678_v3.map" \
        "MegaCD_input_1234_5678_v3.map" \
        "NES_input_1234_5678_v3.map" \
        "TGFX16_input_1234_5678_v3.map" \
	"NEOGEO_input_1234_5678_v3.map" \
        "SATURN_input_1234_5678_v3.map"; do
        remote_url="${raw_base}/.MiSTer_SAM/inputs/$input_file"
        tmp_file="/tmp/$input_file"
        local_file="${configpath}/inputs/$input_file"

        check_and_update "$remote_url" "$tmp_file" "$local_file" "$input_file"
    done
    echo "Input maps updated."
}


function get_blacklist() {
    echo "Downloading blacklist files - SAM can auto-detect games with static screens and filter them out..."

    for blacklist_file in "${BLACKLIST_FILES[@]}"; do
        remote_url="${raw_base}/.MiSTer_SAM/SAM_Gamelists/$blacklist_file"
        tmp_file="/tmp/$blacklist_file"
        local_file="${mrsampath}/SAM_Gamelists/$blacklist_file"
        check_and_update "$remote_url" "$tmp_file" "$local_file" "$blacklist_file"
    done
    echo "Blacklist files updated."
}


function get_ratedlist() {
	echo "Downloading lists with kids-friendly games..."

	for rated_file in "${RATED_FILES[@]}"; do
		remote_url="${raw_base}/.MiSTer_SAM/SAM_Rated/$rated_file"
		tmp_file="/tmp/$rated_file"
		local_file="${mrsampath}/SAM_Rated/$rated_file"
		check_and_update "$remote_url" "$tmp_file" "$local_file" "$rated_file"
	done
	echo "Rated lists updated."
}


get_dlmanager() {

	if [ "$download_manager" = yes ]; then
	
		aria2_path="/media/fat/linux/aria2c"
		
		if [ ! -f "$aria2_path" ]; then
			
			aria2_urls=(
				"https://raw.githubusercontent.com/mrchrisster/0mhz-collection/main/aria2c/aria2c.zip.001"
				"https://raw.githubusercontent.com/mrchrisster/0mhz-collection/main/aria2c/aria2c.zip.002"
				"https://raw.githubusercontent.com/mrchrisster/0mhz-collection/main/aria2c/aria2c.zip.003"
				"https://raw.githubusercontent.com/mrchrisster/0mhz-collection/main/aria2c/aria2c.zip.004"
				
			)	
			echo ""
			echo -n "Installing aria2c Download Manager... "
			for url in "${aria2_urls[@]}"; do
				file_name=$(basename "${url%%\?*}")
				curl -s --insecure -L $url -o /tmp/"$file_name"
				if [ $? -ne 0 ]; then
					echo "Failed to download $file_name"
					download_manager=no
				fi
			done
			
			# Check if the download was successful
			if [ $? -eq 0 ]; then
				echo "Done."
			else
				echo "Failed."
			fi
		
			cat /tmp/aria2c.zip.* > /tmp/aria2c_full.zip
			unzip -qq -o /tmp/aria2c_full.zip -d /media/fat/linux

		fi
	fi
}


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


# ========= MAIN =========

init_vars

read_samini

init_paths

init_data

if [ "${1,,}" != "--source-only" ]; then
	parse_cmd "${@}" # Parse command line parameters for input
fi
