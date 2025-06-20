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
	declare -g corelisttmpfile="/tmp/.SAM_List/corelisttmp.tmp"
	declare -g corelistfile="/tmp/.SAM_List/corelist.tmp"
	declare -g core_count_file="/tmp/.SAM_tmp/sv_corecount"	
	declare -gi disablecoredel="0"	
	declare -gi gametimer=120
	declare -gl corelist="amiga,amigacd32,ao486,arcade,atari2600,atari5200,atari7800,atarilynx,c64,cdi,coco2,fds,gb,gbc,gba,genesis,gg,jaguar,megacd,n64,neogeo,neogeocd,nes,s32x,saturn,sgb,sms,snes,tgfx16,tgfx16cd,psx,x68k"
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
		sam_goat_mode	
	fi

	#NES M82 Mode
	if [ "$m82" == "yes" ]; then	
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
		fi
		gametimer="21"
		listenjoy=no
		
	fi
	
}

function update_samini() {
	[ ! -f /media/fat/Scripts/.config/downloader/downloader.log ] && return
	[ ! -f ${samini_file} ] && return
	if [[ "$(cat /media/fat/Scripts/.config/downloader/downloader.log | grep -c "MiSTer_SAM.default.ini")" != "0" ]] && [ "${samini_update_file}" -nt "${samini_file}" ]; then
		echo "New MiSTer_SAM.ini version downloaded from update_all. Merging with new ini."
		echo "Backing up MiSTer_SAM.ini to MiSTer_SAM.ini.bak"
		cp /media/fat/Scripts/MiSTer_SAM.ini /media/fat/Scripts/MiSTer_SAM.ini.bak
		echo -n "Merging ini values.."
		# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
		sed -i 's/==/--/g' /media/fat/Scripts/MiSTer_SAM.ini
		sed -i 's/-=/--/g' /media/fat/Scripts/MiSTer_SAM.ini
		awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' "${samini_file}" "${samini_update_file}" >/tmp/MiSTer_SAM.tmp && cp -f --force /tmp/MiSTer_SAM.tmp /media/fat/Scripts/MiSTer_SAM.ini
		echo "Done."
	fi

}

# ============== PARSE COMMANDS ===============

# FLOWCHART
# If core is supplied as first argument, we start SAM in single core mode - parse_cmd ${nextcore} start. In function next_core, corelist shuffle is ignored and nextcore always stays the same
# If no argument is passed to SAM, we shuffle the corelist in next_core


function parse_cmd() {
	VALID_CORES=("${!CORE_PRETTY[@]}")
    local args=("$@")
    local nextcore=""
    local recognized_core="no"
    local commands=()

    # 1. Detect if a recognized core was passed.
    for arg in "${args[@]}"; do
        # Convert to lowercase
        local lower="${arg,,}"

        # Check if in VALID_CORES array
        if [[ " ${VALID_CORES[*]} " =~ " ${lower} " ]]; then
            echo "${CORE_PRETTY[$lower]} selected!"
            nextcore="$lower"
            recognized_core="yes"
        else
            # Not a recognized core, so treat it as a possible command
            commands+=("$arg")
        fi
    done

    # 2. If no arguments given at all...
    if [ ${#args[@]} -eq 0 ]; then
        sam_premenu
        return
    fi

    # 3. If we have a recognized core but no subsequent commands,
    #    re-enter parse_cmd so that it calls "start" once.
    if [[ "$recognized_core" == "yes" && ${#commands[@]} -eq 0 ]]; then
        # Move cursor up a line to avoid duplicate message if you want
        echo -n -e "\033[A"
        parse_cmd "${nextcore}" "start"
        return
    fi

    # 4. Otherwise, parse the rest of the commands in a single case statement.
    #    Each time we shift a command, we handle it. 
    #    If you only want to handle the *first* command and ignore the rest, 
    #    you can "break" inside the case statement. 
    #    If you want to handle *all* commands, loop over them.

    while [ ${#commands[@]} -gt 0 ]; do
        case "${commands[0],,}" in

            # ——— Major commands ———
            default)
                sam_update autoconfig
                ;;
            autoconfig | defaultb)
                tmux kill-session -t MCP &>/dev/null
                there_can_be_only_one
                sam_update
                mcp_start
                sam_enable
                ;;
            bootstart)
                env_check "${commands[0]}"
                boot_sleep
                mcp_start
                ;;
            start | restart)
                sam_start
                ;;
            start_real)
                # If we recognized a core, pass it to loop_core
                loop_core "$nextcore"
                ;;
            skip | next)
                echo "Skipping to next game..."
                tmux send-keys -t SAM C-c ENTER
                ;;
            juststop)
                kill_all_sams
				playcurrentgame=no
                play_or_exit
                ;;
            stop | kill)
                [[ -d /tmp/.SAM_List ]] && rm -rf /tmp/.SAM* && rm -rf /tmp/SAM* && rm -rf /tmp/MiSTer_SAM*
                kill_all_sams
				playcurrentgame=no
                play_or_exit
                ;;
            update)
                sam_cleanup
                sam_update
                ;;
            enable)
                env_check "${commands[0]}"
                sam_enable
                ;;
            ignore)
            	ignoregame
            	;;
            disable)
                sam_cleanup
                sam_disable
                ;;
            monitor)
                sam_monitor
                ;;
            playcurrent)
				playcurrentgame=yes
                play_or_exit
                ;;
            startmonitor | sm)
                sam_start
				sleep 1
                sam_monitor
                ;;
            
            # ——— Additional submenus ———
            single)
                sam_singlemenu
                ;;
            autoplay)
                sam_autoplaymenu
                ;;
            favorite)
                mglfavorite
                ;;
            reset)
                sam_resetmenu
                ;;
            config)
                sam_configmenu
                ;;
            back | menu)
                sam_menu
                ;;
            cancel)
                echo " It's pitch dark; You are likely to be eaten by a Grue."
                inmenu=0
                ;;
            deleteall)
                deleteall
                ;;
            resetini)
                resetini
                ;;
            exclude)
                samedit_excltags
                ;;
            settings)
                sam_settings
                ;;
            include)
                samedit_include
                ;;
            gamemode)
                sam_gamemodemenu
                ;;
            bgm)
                sam_bgmmenu
                ;;
            gamelists)
                sam_gamelistmenu
                ;;
            creategl)
                creategl
                ;;
            deletegl)
                deletegl
                ;;
            help)
                sam_help
                ;;
            sshconfig)
                sam_sshconfig
                ;;
            
            # ——— Unknown command fallback ———
            *)
                echo " ERROR! ${commands[0]} is unknown."
                echo " Try $(basename -- "${0}") help"
                echo " Or check the GitHub readme."
                ;;
        esac
        
        # Now drop this command and move on
        commands=("${commands[@]:1}")
    done
}


# ======== SAM OPERATIONAL FUNCTIONS ========


function loop_core() { # loop_core (core)
	echo -e "Starting Super Attract Mode...\nLet Mortal Kombat begin!\n"
	# Reset game log for this session
	echo "" >/tmp/SAM_Games.log
	samdebug "corelist: ${corelist[*]}"
	while :; do

		while [ ${counter} -gt 0 ]; do
			trap 'counter=0' INT #Break out of loop for skip & next command
			
			#Only show game counter when samvideo is not active
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

			if [ -s "$mouse_activity_file" ]; then
				if [ "${listenmouse}" == "yes" ]; then
					echo "Mouse activity detected!"
						truncate -s 0 "$mouse_activity_file"
						play_or_exit &
				else
					#echo " Mouse activity ignored!"
					truncate -s 0 "$mouse_activity_file"
				fi
			fi

			if [ -s "$key_activity_file" ]; then
				if [ "${listenkeyboard}" == "yes" ]; then
					echo "Keyboard activity detected!"
						truncate -s 0 "$mouse_activity_file"
						play_or_exit &

				else
					echo " Keyboard activity ignored!"
					truncate -s 0 "$key_activity_file"
				fi
			fi

			if [ -s "$joy_activity_file" ]; then
				
				if [ "${listenjoy}" == "yes" ]; then
					echo "Controller activity detected"
					if [[ "$(cat "$joy_activity_file")" == "Start" ]]; then
						#Play game
						samdebug "Start button pushed. Exiting SAM."
						playcurrentgame="yes"
						truncate -s 0 "$joy_activity_file"
						play_or_exit &
					elif [[ "$(cat "$joy_activity_file")" == "Next" ]]; then
						echo "Starting next Game"
						if [[ "$ignore_when_skip" == "yes" ]]; then
							ignoregame
						fi
						counter=0
						truncate -s 0 "$joy_activity_file"
					#Support zaparoo	
					elif [[ "$(cat "$joy_activity_file")" == "zaparoo" ]]; then
						echo "Zaparoo starting. SAM exiting"
						truncate -s 0 "$joy_activity_file"
						# SAM will restart core if mute=core which is set by bgm
						mute="yes"
						playcurrentgame="yes"
						play_or_exit &
					else
						truncate -s 0 "$joy_activity_file"
						play_or_exit &
					fi
				else # ignore gamepad input
					#special case for m82
					if [ "$m82" == "yes" ]; then
						romname="${romname,,}"
						local m82bios_active="$romname"
						if [[ "$(cat "$joy_activity_file")" == "Next" ]]; then
							#Next game is M82 bios, so skip
							if [[ "$romname" != *"m82"* ]]; then 
								samdebug "romname: $romname"
								samdebug "Skipping M82 and jump to next game"
								sed -i '1d' "$gamelistpathtmp"/nes_gamelist.txt
								sync
							else
								echo "Starting next Game"
							fi
							update_done=1
							counter=0
							truncate -s 0 "$joy_activity_file"
						fi
						#Next game is not M82 bios. Let's play some NES!
						if [[ "$romname" != *"m82"* ]] && [ "$update_done" -eq 0 ]; then 
							# Unmute game
							if [[ "$m82_muted" == "yes" ]]; then
								only_unmute_if_needed
								#echo "load_core /tmp/SAM_Game.mgl" >/dev/MiSTer_cmd
							fi
							counter=$m82_game_timer
							update_done=1
							truncate -s 0 "$joy_activity_file"
						fi

					fi
					#echo " Controller activity ignored!"
					truncate -s 0 "$joy_activity_file"			
				fi
			fi

		done

		counter=${gametimer}
		next_core "${1}"

	done
	trap - INT
	sleep 1
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
	
	load_special_core
	if [ $? -ne 0 ]; then return; fi
		
	check_list "${nextcore}"
	if [ $? -ne 0 ]; then 
		next_core
		samdebug "check_list function returned an error."
		return
	fi
	
	# Check if new roms got added
	check_gamelistupdate ${nextcore} &
	
	pick_rom
	
	check_rom "${nextcore}"
	if [ $? -ne 0 ]; then return; fi
	
	delete_played_game
	
	load_core "${nextcore}" "${rompath}" "${romname%.*}"
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
	
	# TODO avoid tmp file here
	if [ -s "${corelistfile}" ]; then
		unset corelist 
		mapfile -t corelist <${corelistfile}
		rm ${corelistfile}
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

# Create all gamelists in the background

function create_all_gamelists() {
    # ——— only do this once per script invocation ———
    if (( gamelists_created )); then
        return
    fi
    gamelists_created=1
	
    (
        # — 1) find exactly *_gamelist.txt in gamelistpath —
        readarray -t glondisk < <(
            find "$gamelistpath" -maxdepth 1 -type f -name '*_gamelist.txt' \
                -printf '%f\n' | sed 's/_gamelist\.txt$//'
        )
        samdebug "Game lists on SD: ${glondisk[*]}"

        # — 2) build special cores first —
        for c in "${special_cores[@]}"; do
            if [[ " ${corelist[*]} " =~ " $c " ]] && \
               [[ ! " ${glondisk[*]} "   =~ " $c " ]]; then
                samdebug "Creating special gamelist for $c"
                nextcore="$c"
                create_"$c"list
                unset nextcore
            fi
        done

        # — 3) reload after specials —
        readarray -t glondisk < <(
            find "$gamelistpath" -maxdepth 1 -type f -name '*_gamelist.txt' \
                -printf '%f\n' | sed 's/_gamelist\.txt$//'
        )

        # — 4) figure out non-special cores still missing —
        local need=()
        for c in "${corelist[@]}"; do
            if [[ ! " ${glondisk[*]} " =~ " $c " ]] && \
               [[ ! " ${special_cores[*]} " =~ " $c " ]]; then
                need+=( "$c" )
            fi
        done

        # — 5) run samindex on those —
        if (( ${#need[@]} )); then
            samdebug "Gamelist missing: ${need[*]}"
            for c in "${need[@]}"; do
                samdebug "  → creating $c gamelist"
                "${mrsampath}/samindex" -q -s "$c" -o "$gamelistpath"
            done

            # — 6) reload once more —
            readarray -t glondisk < <(
                find "$gamelistpath" -maxdepth 1 -type f -name '*_gamelist.txt' \
                    -printf '%f\n' | sed 's/_gamelist\.txt$//'
            )
        else
            samdebug "All gamelists are present."
        fi

        # — 7) intersect into glclondisk —
        unset glclondisk
        for g in "${glondisk[@]}"; do
            for c in "${corelist[@]}"; do
                [[ "$c" == "$g" ]] && glclondisk+=( "$c" )
            done
        done
        samdebug "Now have gamelists for: ${glondisk[*]}"

        # — 8) update corelisttmp —
        corelisttmp=( "${glclondisk[@]}" )
        samdebug "corelisttmp ← ${corelisttmp[*]}"
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

# ──────────────────────────────────────────────────────────────────────────────
# 1) Uniform random selection
# ──────────────────────────────────────────────────────────────────────────────
function pick_core_standard() {
    nextcore=$(printf "%s\n" "${corelisttmp[@]}" \
               | shuf --random-source=/dev/urandom -n1)
    samdebug "Picked core (standard): $nextcore"
}

# ──────────────────────────────────────────────────────────────────────────────
# 2) SAM-video mode (Weighted by _tvc.txt)
# ──────────────────────────────────────────────────────────────────────────────


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


# ──────────────────────────────────────────────────────────────────────────────
# 3) Core-weight mode (weighted by games per core)
# ──────────────────────────────────────────────────────────────────────────────

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


# ──────────────────────────────────────────────────────────────────────────────
# Load special cores like ao486, amiga, arcade or X68000 
# ──────────────────────────────────────────────────────────────────────────────
function load_special_core() {
	# If $nextcore is ao486, amiga, arcade or X68000 
	if [ "${nextcore}" == "arcade" ]; then
		# If this is an arcade core we go to special code
		if [[ -n "$cfgarcade_configpath" ]]; then
			configpath="$cfgarcade_configpath"
		fi
		load_core_arcade
		return 2
	fi
	if [ "${nextcore}" == "amiga" ]; then
		
		if [ -f "${amigapath}/MegaAGS.hdf" ] || [ -f "${amigapath}/AmigaVision.hdf" ]; then
			load_core_amiga
		else
			echo "ERROR - MegaAGS Pack not found in Amiga folder. Skipping to next core..."
			delete_from_corelist amiga
			next_core
		fi
		return 2
	fi
	if [ "${nextcore}" == "amigacd32" ]; then
		
		if [ -f "/media/fat/_Console/Amiga CD32.mgl" ]; then
			load_core_amigacd32
		else
			echo "ERROR - /media/fat/_Console/Amiga CD32.mgl not found. Skipping to next core..."
			delete_from_corelist amiga
			next_core
		fi
		return 2
	fi
	if [ "${nextcore}" = "ao486" ]; then
		dir1="/media/fat/_DOS Games"
		dir2="/media/fat/_Computer/_DOS Games"
	
		# count in dir1, or dir2 if dir1 is empty
		count1=$(find "$dir1"  -type f -iname '*.mgl' 2>/dev/null | wc -l)
		count2=$(find "$dir2"  -type f -iname '*.mgl' 2>/dev/null | wc -l)
	
		if [ "$count1" -gt 0 ] || [ "$count2" -gt 0 ]; then
			load_core_ao486
		else
			echo "ERROR - No ao486 screensavers found in either:"
			echo "  $dir1"
			echo "  $dir2"
			echo "Please install the 0Mhz collection."
			delete_from_corelist ao486
			next_core
		fi
	
		return 2
	fi
	if [ "${nextcore}" = "x68k" ]; then
		dir1="/media/fat/_X68000 Games"
		dir2="/media/fat/_Computer/_X68000 Games"
	
		# count in dir1, or dir2 if dir1 is empty
		count1=$(find "$dir1"  -type f -iname '*.mgl' 2>/dev/null | wc -l)
		count2=$(find "$dir2"  -type f -iname '*.mgl' 2>/dev/null | wc -l)
	
		if [ "$count1" -gt 0 ] || [ "$count2" -gt 0 ]; then
			load_core_x68k
		else
			echo "ERROR - No x68k mgls found in either:"
			echo "  $dir1"
			echo "  $dir2"
			echo "Please install the neon68k collection."
			delete_from_corelist x68k
			next_core
		fi
	
		return 2
	fi

}


# Romfinder
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
		sam_goat_mode
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
		core_error_rom "${nextcore}" "${rompath}"
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
	extension="${rompath##*.}"
	extlist="${CORE_EXT[${nextcore}]//,/ }" 
				
	if [[ "$extlist" != *"$extension"* ]]; then
		create_gamelist "${nextcore}" &
		if [ ${romloadfails} -lt ${coreretries} ]; then
			declare -g romloadfails=$((romloadfails + 1))
			samdebug "Wrong extension found: '${extension^^}' for core: ${nextcore} rom: ${rompath}"
			samdebug "Picking new rom.."
			next_core "${nextcore}"
		else
			echo "ERROR: Failed ${romloadfails} times. No valid game found for core: ${1} rom: ${2}"
			echo "ERROR: Core ${nextcore} is blacklisted!"
			delete_from_corelist "${nextcore}"
			echo "List of cores is now: ${corelist[*]}"
			declare -g romloadfails=0
			# Load a different core
			next_core	
		fi
		return 1
	fi

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

# Load selected core and rom
function load_core() { # load_core core /path/to/rom name_of_rom 
	# Load arcade, ao486 or amiga cores
	local core=${1}
	local rompath=${2}
	local romname=${3}
	local gamename
	local tty_corename
	if [ "${1}" == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then
		for e in "${!NEOGEO_PRETTY_ENGLISH[@]}"; do
			if [[ "$rompath" == *"$e"* ]]; then
				gamename="${NEOGEO_PRETTY_ENGLISH[$e]}"
			fi
		done
	fi

	if [ ! "${gamename}" ]; then
		gamename="${3}"
	fi
	
	mute "${CORE_LAUNCH[${1}]}"
	
	#BGM title
	if [ "${bgm}" == "yes" ]; then
		streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
	fi

	echo -n "Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${1}]}\e[0m: "
	echo -e "\e[1m${gamename}\e[0m"
	[[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"
	echo "$(date +%H:%M:%S) - ${1} - $([ "${samdebug}" == "yes" ] && echo ${rompath} || echo ${3})" "$(if [ "${1}" == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then echo "(${gamename})"; fi)" >>/tmp/SAM_Games.log
	echo "${3} (${1}) $(if [ "${1}" == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then echo "(${gamename})"; fi)" >/tmp/SAM_Game.txt
	

	
	#TTY2OLED
	tty_corename="${TTY2OLED_PIC_NAME[${1}]}"	
	if [[ "${ttyname_cleanup}" == "yes" ]]; then
		gamename="$(echo "${gamename}" | awk -F "(" '{print $1}')"
	fi
	
	if [[ -n "$streamtitle" ]]; then
		gamename="${gamename} - BGM: ${streamtitle}"
	fi

	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			[core_pretty]="${CORE_PRETTY[${nextcore}]}"
			[name]="${gamename}"
			[core]=${tty_corename}
			[date]=$EPOCHSECONDS
			[counter]=${gametimer}
			[name_scroll]="${gamename:0:21}"
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


	# Create mgl file and launch game
	if [ -s /tmp/SAM_Game.mgl ]; then
		mv /tmp/SAM_Game.mgl /tmp/SAM_game.previous.mgl
	fi
	
	{
	  echo "<mistergamedescription>"
	  echo "<rbf>${CORE_PATH_RBF[${nextcore}]}/${MGL_CORE[${nextcore}]}</rbf>"
	  echo "<file delay=\"${MGL_DELAY[${nextcore}]}\" type=\"${MGL_TYPE[${nextcore}]}\" index=\"${MGL_INDEX[${nextcore}]}\" path=\"../../../../..${rompath}\"/>"
	  [ -n "${MGL_SETNAME[${nextcore}]}" ] && echo "<setname>${MGL_SETNAME[${nextcore}]}</setname>"
	} >/tmp/SAM_Game.mgl


	echo "load_core /tmp/SAM_Game.mgl" >/dev/MiSTer_cmd

	sleep 1
	activity_reset

	# Skip bios screen for FDS or MegaCD
	skipmessage &

}


# ARCADE MODE
function build_mralist() {

	${mrsampath}/samindex -s arcade -o "${gamelistpath}" 
	cp "${gamelistpath}/${1}_gamelist.txt" "${gamelistpathtmp}/${1}_gamelist.txt" 2>/dev/null

}

function load_core_arcade() {

	# Check if the MRA list is empty or doesn't exist - if so, make a new list

	if [ ! -s "${gamelistpath}/${nextcore}_gamelist.txt" ]; then
		samdebug "Rebuilding mra list."
		build_mralist 
	fi
	
	#Check blacklist and copy gamelist to tmp
	if [ ! -s "${gamelistpathtmp}/${nextcore}_gamelist.txt" ]; then
		cp "${gamelistpath}/${nextcore}_gamelist.txt" "${gamelistpathtmp}/${nextcore}_gamelist.txt" 2>/dev/null
		
		filter_list arcade
		
	fi
	
	sed -i '/^$/d' "${gamelistpathtmp}/${nextcore}_gamelist.txt"
	
	
	#samvideo mode
	if [ "$samvideo" == "yes" ] && [ "$samvideo_tvc" == "yes" ] && [ -f /tmp/.SAM_tmp/sv_gamename ]; then
		mra="$(cat ${gamelistpathtmp}/"${nextcore}"_gamelist.txt | grep -if /tmp/.SAM_tmp/sv_gamename | shuf -n 1)"
		if [ -z "${mra}" ]; then
			samdebug "Error with picking the corresponding game for the commercial. Playing random game now."
			mra="$(cat ${gamelistpathtmp}/"${nextcore}"_gamelist.txt | shuf --random-source=/dev/urandom --head-count=1)"
		fi
		sleep 5   #anything lower than 5 doesn't work
	else
		# Get a random game from the list
		mra="$(shuf --random-source=/dev/urandom --head-count=1 ${gamelistpathtmp}/${nextcore}_gamelist.txt)"
	fi
	
	# Check if Game exists
	if [ ! -f "${mra}" ]; then
		build_mralist 
		mra=$(shuf --random-source=/dev/urandom --head-count=1 ${gamelistpathtmp}/${nextcore}_gamelist.txt)
	fi
	
	
	#mraname="$(basename "${mra}" | sed -e 's/\.[^.]*$//')"	
	mraname="$(basename "${mra//.mra/}")"
	mrasetname=$(grep "<setname>" "${mra}" | sed -e 's/<setname>//' -e 's/<\/setname>//' | tr -cd '[:alnum:]')
	tty_corename="${mrasetname}"

	samdebug "Selected file: ${mra}"

	# Delete mra from list so it doesn't repeat
	if [ "${norepeat}" == "yes" ]; then
		awk -vLine="$mra" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} && cp -f ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
	fi
	
	mute "${mrasetname}"

	#BGM title
	if [ "${bgm}" == "yes" ]; then
		streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
	fi



	echo -n "Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore}]}\e[0m: "
	echo -e "\e[1m${mraname}\e[0m"
	[[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"
	echo "$(date +%H:%M:%S) - Arcade - ${mraname}" >>/tmp/SAM_Games.log
	echo "${mraname} (${nextcore})" >/tmp/SAM_Game.txt
	

	#TTY2OLED
	
	if [[ -n "$streamtitle" ]]; then
		gamename="${mraname} - BGM: ${streamtitle}"
	fi
	
	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			[core_pretty]="${CORE_PRETTY[${nextcore}]}"
			[name]="${mraname}"
			[core]=${tty_corename}
			[date]=$EPOCHSECONDS
			[counter]=${gametimer}
			[name_scroll]="${mraname:0:21}"
			[name_scroll_position]=0
			[name_scroll_direction]=1
			[update_pause]=${ttyupdate_pause}
		)
		declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
		write_to_TTY_cmd_pipe "display_info" &
		local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
		SECONDS=${elapsed}
	fi
	
	# Tell MiSTer to load the next MRA
	echo "load_core ${mra}" >/dev/MiSTer_cmd
	
	sleep 1
	activity_reset
	

}

function create_amigalist () {

	# Create List in gamelistpath
	if [ ! -f "${gamelistpath}/amiga_gamelist.txt" ]; then
		cat "${amigapath}/listings/demos.txt" > ${gamelistpathtmp}/amiga_gamelist.txt
		sed -i -e 's/^/Demo: /' ${gamelistpathtmp}/amiga_gamelist.txt
		cat "${amigapath}/listings/games.txt" >> ${gamelistpathtmp}/amiga_gamelist.txt
		cp ${gamelistpathtmp}/amiga_gamelist.txt ${gamelistpath}/amiga_gamelist.txt
	fi
	
	if [ -f "${amigapath}/listings/games.txt" ]; then
		if [[ "${amigaselect}" == "demos" ]]; then
			cat "${amigapath}/listings/demos.txt" > ${gamelistpathtmp}/amiga_gamelist.txt
			sed -i -e 's/^/Demo: /' ${gamelistpathtmp}/amiga_gamelist.txt
		elif [[ "${amigaselect}" == "games" ]]; then
			cat "${amigapath}/listings/games.txt" > ${gamelistpathtmp}/amiga_gamelist.txt
		elif [[ "${amigaselect}" == "all" ]]; then
			cat "${amigapath}/listings/demos.txt" > ${gamelistpathtmp}/amiga_gamelist.txt
			sed -i -e 's/^/Demo: /' ${gamelistpathtmp}/amiga_gamelist.txt
			cat "${amigapath}/listings/games.txt" >> ${gamelistpathtmp}/amiga_gamelist.txt			
			
		else
			samdebug "Invalid option specified for amigaselect variable."
		fi
		total_games="$(wc -l < "${gamelistpathtmp}/amiga_gamelist.txt")"
		samdebug "${total_games} Games and/or Demos found."
	else
		echo "ERROR: Can't find Amiga games.txt or demos.txt file"
	fi

}


function load_core_amiga() {


	if [ ! -s "${gamelistpathtmp}/amiga_gamelist.txt" ]; then
		create_amigalist
		filter_list amiga
	fi
		
	if [ -f "/media/fat/_Computer/Amiga.mgl" ]; then
		mute Amiga
	else
		mute Minimig
	fi

	if [ ! -f "${amigapath}/listings/games.txt" ]; then
		# This is for MegaAGS version June 2022 or older
		echo -n "Starting now on the "
		echo -ne "\e[4m${CORE_PRETTY[amiga]}\e[0m: "
		echo -e "\e[1mMegaAGS Amiga Game\e[0m"

		# Tell MiSTer to load the next MRA

		echo "load_core ${amigacore}" >/dev/MiSTer_cmd
		sleep 13
		"${mrsampath}/mbc" raw_seq {6c
		"${mrsampath}/mbc" raw_seq O
		activity_reset
	else
		# This is for MegaAGS version July 2022 or newer

		rompath="$(shuf --random-source=/dev/urandom --head-count=1 ${gamelistpathtmp}/amiga_gamelist.txt)"
		agpretty="$(echo "${rompath}" | tr '_' ' ')"
		
		# Special case for demo
		if [[ "${rompath}" == *"Demo:"* ]]; then
			rompath=${rompath//Demo: /}
		fi

		# Delete played game from list
		samdebug "Selected file: ${rompath}"
		if [ "${norepeat}" == "yes" ]; then
			awk -vLine="$rompath" '!index($0,Line)' "${gamelistpathtmp}/amiga_gamelist.txt" >${tmpfile} && cp -f ${tmpfile} "${gamelistpathtmp}/amiga_gamelist.txt"
		fi

		echo "${rompath}" > "${amigapath}"/shared/ags_boot
		tty_corename="Minimig"
		

		#BGM title
		if [ "${bgm}" == "yes" ]; then
			streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
		fi

		echo -n "Starting now on the "
		echo -ne "\e[4m${CORE_PRETTY[amiga]}\e[0m: "
		echo -e "\e[1m${agpretty}\e[0m"
		[[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"
		echo "$(date +%H:%M:%S) - ${nextcore} - ${rompath}" >>/tmp/SAM_Games.log
		echo "${rompath} (${nextcore})" >/tmp/SAM_Game.txt
		
		#TTY2OLED
		
		if [[ -n "$streamtitle" ]]; then
			gamename="${agpretty} - BGM: ${streamtitle}"
		fi		
		
		if [ "${ttyenable}" == "yes" ]; then
			tty_currentinfo=(
				[core_pretty]="${CORE_PRETTY[amiga]}"
				[name]="${agpretty}"
				[core]=${tty_corename}
				[date]=$EPOCHSECONDS
				[counter]=${gametimer}
				[name_scroll]="${agpretty:0:21}"
				[name_scroll_position]=0
				[name_scroll_direction]=1
				[update_pause]=${ttyupdate_pause}
			)
			declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
			write_to_TTY_cmd_pipe "display_info" &
			local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
			SECONDS=${elapsed}
		fi
		
		
		# Amigavision uses Amiga.mgl instead of minimig core
		if [ -f "/media/fat/_Computer/Amiga.mgl" ]; then
			echo "load_core /media/fat/_Computer/Amiga.mgl" >/dev/MiSTer_cmd
		else
			echo "load_core ${amigacore}" >/dev/MiSTer_cmd
		fi
		activity_reset
	fi
}


function load_core_amigacd32() {

	check_list "${nextcore}"
	if [ $? -ne 0 ]; then next_core; return; fi
	
	# Check if new roms got added
	check_gamelistupdate ${nextcore} &
	
	pick_rom
	
	check_rom "${nextcore}"
	if [ $? -ne 0 ]; then return; fi
	
	delete_played_game

	local gamename
	local tty_corename

	if [ ! "${gamename}" ]; then
		gamename="${romname%.*}"
	fi
	
	mute amigacd32 
	
	#BGM title
	if [ "${bgm}" == "yes" ]; then
		streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
	fi


	echo -n "Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore}]}\e[0m: "
	echo -e "\e[1m${gamename}\e[0m"
	[[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"
	echo "$(date +%H:%M:%S) - ${nextcore} - $([ "${samdebug}" == "yes" ] && echo ${rompath} || echo ${romname})" "$(if [ "${nextcore}" == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then echo "(${gamename})"; fi)" >>/tmp/SAM_Games.log
	echo "${romname} (${nextcore}) $(if [ "${nextcore}" == "neogeo" ] && [ ${useneogeotitles} == "yes" ]; then echo "(${gamename})"; fi)" >/tmp/SAM_Game.txt
	tty_corename="${TTY2OLED_PIC_NAME[${nextcore}]}"
	
	#TTY2OLED
	if [[ "${ttyname_cleanup}" == "yes" ]]; then
		gamename="$(echo "${gamename}" | awk -F "(" '{print $nextcore}')"
	fi
	
	if [[ -n "$streamtitle" ]]; then
		gamename="${gamename} - BGM: ${streamtitle}"
	fi	

	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			[core_pretty]="${CORE_PRETTY[${nextcore}]}"
			[name]="${gamename}"
			[core]=${tty_corename}
			[date]=$EPOCHSECONDS
			[counter]=${gametimer}
			[name_scroll]="${gamename:0:21}"
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


	# Write game to AmigaCD32

	CONFIG_FILE="/media/fat/config/AmigaCD32.cfg"

	if [ ! -f "$CONFIG_FILE" ]; then
		echo "ERROR - Please make sure AmigaCD32 is installed. Skipping to next core..."
		delete_from_corelist amigacd32
		next_core
	fi
	
	# **Always write at offset 3100**
	START_BYTE=3100
	CLEAR_LENGTH=108  # Make sure we clear enough for full filename
	NEW_GAME_PATH="$rompath"
	
	# **Zero out only the path section (not the header)**
	dd if=/dev/zero bs=1 count=$CLEAR_LENGTH seek=$START_BYTE of="$CONFIG_FILE" conv=notrunc 2>/dev/null

	# **Remove '/media' prefix if present**
	NEW_GAME_PATH=$(echo "$NEW_GAME_PATH" | sed 's|^/media||')

	# **Ensure no leading double slashes**
	NEW_GAME_PATH=$(echo "$NEW_GAME_PATH" | sed 's|^/||')

	# Ensure the path starts with `../` (if needed)
	if [[ "$NEW_GAME_PATH" != ../* ]]; then
		NEW_GAME_PATH="../$NEW_GAME_PATH"
	fi

	# Convert the new game path to a clean hex string
	NEW_GAME_HEX=$(echo -n "$NEW_GAME_PATH" | xxd -p | tr -d '\n')

	# Ensure proper padding with 00 bytes if path is shorter than max allowed length
	HEX_PADDING=$(yes "00" | head -n $((CLEAR_LENGTH - ${#NEW_GAME_HEX} / 2)) | tr -d '\n')

	# Combine actual data and padding
	FINAL_GAME_HEX="${NEW_GAME_HEX}${HEX_PADDING}"

	# Convert hex string into binary and write at the correct path offset
	echo -n "$FINAL_GAME_HEX" | xxd -r -p | dd of="$CONFIG_FILE" bs=1 seek=$START_BYTE conv=notrunc 2>/dev/null


	echo "load_core /media/fat/_Console/Amiga CD32.mgl" >/dev/MiSTer_cmd

	sleep 10
	activity_reset

	# Boot game
	/media/fat/Scripts/.MiSTer_SAM/mbc raw_seq :30
}

function create_ao486list () {
    local dir1="/media/fat/_DOS Games"
    local dir2="/media/fat/_Computer/_DOS Games"
    local out="${gamelistpath}/${nextcore}_gamelist.txt"

    # look in both dirs (silence errors if a dir is missing)
    find "$dir1" "$dir2" -type f -iname '*.mgl' 2>/dev/null > "$out"

    # if the resulting list is empty, disable this core
    if [ ! -s "$out" ]; then
        samdebug "No ao486 screensavers found—disabling ao486 core."
        delete_from_corelist ao486
        delete_from_corelist ao486 tmp
        return 1
    fi

    samdebug "Created AO486 gamelist with $(wc -l <"$out") entries."
}



function load_core_ao486() {

	if [ ! -f "${gamelistpath}/${nextcore}_gamelist.txt" ]; then
		samdebug "No AO486 list found — creating one now."
		create_ao486list
	fi

	if [ ! -s "${gamelistpathtmp}/${nextcore}_gamelist.txt" ]; then
		cp "${gamelistpath}/${nextcore}_gamelist.txt" "${gamelistpathtmp}/${nextcore}_gamelist.txt" &>/dev/null
		filter_list ao486
		if [ $? -eq 1 ]; then
			next_core
			return
		fi
	fi
		
	mute ao486
	rompath="$(shuf --random-source=/dev/urandom --head-count=1 ${gamelistpathtmp}/"${nextcore}"_gamelist.txt)"
	romname=$(basename "${rompath}")
	aopretty="$(echo "${romname%.*}" | tr '_' ' ')"		

	# Delete played game from list
	samdebug "Selected file: ${rompath}"
	if [ "${norepeat}" == "yes" ]; then
		awk -vLine="$rompath" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} && cp -f ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
	fi
	

	#BGM title
	if [ "${bgm}" == "yes" ]; then
		streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
	fi


	echo -n "Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore}]}\e[0m: "
	echo -e "\e[1m${aopretty}\e[0m"
	[[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"
	echo "$(date +%H:%M:%S) - ${nextcore} - ${romname}" >>/tmp/SAM_Games.log
	echo "${romname} (${nextcore})" >/tmp/SAM_Game.txt

	#tty2oled
	tty_corename="ao486"
	if [[ -n "$streamtitle" ]]; then
		gamename="${aopretty} - BGM: ${streamtitle}"
	fi	
	
	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			[core_pretty]="${CORE_PRETTY[${nextcore}]}"
			[name]="${aopretty}"
			[core]=${tty_corename}
			[date]=$EPOCHSECONDS
			[counter]=${gametimer}
			[name_scroll]="${aopretty:0:21}"
			[name_scroll_position]=0
			[name_scroll_direction]=1
			[update_pause]=${ttyupdate_pause}
		)
		declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
		write_to_TTY_cmd_pipe "display_info" &
		local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
		SECONDS=${elapsed}
	fi
	
	skipmessage_ao486 &
	echo "load_core ${rompath}" >/dev/MiSTer_cmd

	sleep 1
	activity_reset


}


function create_x68klist () {
    local dir1="/media/fat/_X68000 Games"
    local dir2="/media/fat/_Computer/_X68000 Games"
    local out="${gamelistpath}/${nextcore}_gamelist.txt"

    # look in both dirs (silence errors if a dir is missing)
    find "$dir1" "$dir2" -type f -iname '*.mgl' 2>/dev/null \
        > "$out"

    if [ ! -s "$out" ]; then
        samdebug "No X68000 games found—disabling x68k core."
        delete_from_corelist x68k
        return 1
    fi

    samdebug "Created X68000 gamelist with $(wc -l <"$out") entries."
}

function load_core_x68k() {

	if [ ! -f "${gamelistpath}/${nextcore}_gamelist.txt" ]; then
		samdebug "No X68000 list found — creating one now."
		create_x68klist
	fi
	if [ ! -s "${gamelistpathtmp}/${nextcore}_gamelist.txt" ]; then
		cp "${gamelistpath}/${nextcore}_gamelist.txt" "${gamelistpathtmp}/${nextcore}_gamelist.txt" &>/dev/null
		#filter_list x68k
		if [ $? -eq 1 ]; then
			next_core
			return
		fi
	fi
		
	mute X68000
	rompath="$(shuf --random-source=/dev/urandom --head-count=1 ${gamelistpathtmp}/"${nextcore}"_gamelist.txt)"
	romname=$(basename "${rompath}")
	aopretty="$(echo "${romname%.*}" | tr '_' ' ')"		

	# Delete played game from list
	samdebug "Selected file: ${rompath}"
	if [ "${norepeat}" == "yes" ]; then
		awk -vLine="$rompath" '!index($0,Line)' "${gamelistpathtmp}/${nextcore}_gamelist.txt" >${tmpfile} && cp -f ${tmpfile} "${gamelistpathtmp}/${nextcore}_gamelist.txt"
	fi
	

	#BGM title
	if [ "${bgm}" == "yes" ]; then
		streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
	fi


	echo -n "Starting now on the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore}]}\e[0m: "
	echo -e "\e[1m${aopretty}\e[0m"
	[[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"
	echo "$(date +%H:%M:%S) - ${nextcore} - ${romname}" >>/tmp/SAM_Games.log
	echo "${romname} (${nextcore})" >/tmp/SAM_Game.txt

	#tty2oled
	tty_corename="X68000"
	if [[ -n "$streamtitle" ]]; then
		gamename="${aopretty} - BGM: ${streamtitle}"
	fi	
	
	if [ "${ttyenable}" == "yes" ]; then
		tty_currentinfo=(
			[core_pretty]="${CORE_PRETTY[${nextcore}]}"
			[name]="${aopretty}"
			[core]=${tty_corename}
			[date]=$EPOCHSECONDS
			[counter]=${gametimer}
			[name_scroll]="${aopretty:0:21}"
			[name_scroll_position]=0
			[name_scroll_direction]=1
			[update_pause]=${ttyupdate_pause}
		)
		declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' >"${tty_currentinfo_file}"
		write_to_TTY_cmd_pipe "display_info" &
		local elapsed=$((EPOCHSECONDS - tty_currentinfo[date]))
		SECONDS=${elapsed}
	fi
	
	#skipmessage_x68k &
	echo "load_core ${rompath}" >/dev/MiSTer_cmd

	sleep 1
	activity_reset


}



# ========= SAM START AND STOP =========

function sam_start() {
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

    # Launch tmux in a subshell detached, then background it
    (
       exec tmux new-session -d \
         -x 180 -y 40 \
         -n "-= SAM Monitor -- Detach with ctrl-b, then push d =-" \
         -s SAM \
         "${misterpath}/Scripts/MiSTer_SAM_on.sh" start_real "${nextcore}" 
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

function there_can_be_only_one() { # there_can_be_only_one
	# If another attract process is running kill it
	# This can happen if the script is started multiple times
	
	echo "Stopping other running instances of ${samprocess}..."

	kill_1=$(ps -o pid,args | grep '[M]iSTer_SAM_init start' | awk '{print $1}' | head -1)
	kill_2=$(ps -o pid,args | grep '[M]iSTer_SAM_on.sh start_real' | awk '{print $1}')
	kill_3=$(ps -o pid,args | grep '[M]iSTer_SAM_on.sh bootstart_real' | awk '{print $1}' | head -1)

	[[ -n ${kill_1} ]] && kill -9 "${kill_1}" >/dev/null
	for kill in ${kill_2}; do
		[[ -n ${kill_2} ]] && kill -9 "${kill}" >/dev/null
	done
	[[ -n ${kill_3} ]] && kill -9 "${kill_3}" >/dev/null

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
				# Amigavision uses Amiga.mgl instead of minimig core
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
		echo "load_core /media/fat/menu.rbf" >/dev/MiSTer_cmd
		sleep 1
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
	if [ "${kids_safe}" == "yes" ]; then
		if [ ! -f "${mrsampath}"/SAM_Rated/amiga_rated.txt ]; then
			echo "No kids safe rating lists found."
			get_ratedlist
			if [ $? -ne 0 ]; then 
				echo "Kids Safe Filter failed downloading."
				return 1
			else
				echo "Kids Safe Filter active."
			fi
		else
			echo "Kids Safe Filter active."
		fi
		#Set corelist to only include cores with rated lists
		readarray -t glr <<< "$(find "${mrsampath}/SAM_Rated" -name "*_rated.txt" | awk -F'/' '{ print $NF }' | awk -F'_' '{print$1}')"
		unset clr
		for g in "${glr[@]}"; do 
			for c in "${corelist[@]}"; do 
				if [[ "$c" == "$g" ]]; then 
					clr+=("$c")
				fi
			done 
		done
		readarray -t nclr <<< "$(printf '%s\n'  "${clr[@]}" "${corelist[@]}"  | sort | uniq -iu )"		
		echo "Kids Safe lists missing for cores: ${nclr[@]}"
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
			sed -i '/samvideo_tvc=/c\samvideo_tvc="no"' /media/fat/Scripts/MiSTer_SAM.ini
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

function resetini() {
    # Remove temporary files
    rm -rf "/tmp/.SAM_List"
    rm -rf "/tmp/.SAM_tmp"
    sam_cleanup
    # Check if at least one argument is provided
    if [ $# -eq 0 ]; then
        # No arguments provided, reset INI file to default
        if [ -f "${mrsampath}/MiSTer_SAM.default.ini" ]; then
            cp "${mrsampath}/MiSTer_SAM.default.ini" /media/fat/Scripts/MiSTer_SAM.ini
        else
            get_samstuff MiSTer_SAM.ini /tmp
            cp /tmp/MiSTer_SAM.ini /media/fat/Scripts/MiSTer_SAM.ini
        fi
    else
        # Iterate over each argument
        for arg in "$@"
        do
            case "$arg" in
                "bgm")
                    # Example: Reset background music setting
					bgm_stop force
                    sed -i '/bgm=/c\bgm="no"' /media/fat/Scripts/MiSTer_SAM.ini
                    ;;
                "samvideo")
                    # Example: Reset samvideo setting
                    sed -i '/samvideo=/c\samvideo="no"' /media/fat/Scripts/MiSTer_SAM.ini
                    ;;
                "m82")
                    # Example: Reset samvideo setting
                    sed -i '/m82=/c\m82="no"' /media/fat/Scripts/MiSTer_SAM.ini
                    ;;
                *)
                    echo "Invalid option ($arg). No changes made."
                    ;;
            esac
        done
    fi
}



function deleteall() {
	# In case of issues, reset SAM

	there_can_be_only_one
	
	mkdir -p /media/fat/Scripts/.SAM_Backup
	find "${mrsampath}/SAM_Gamelists" -name "*_excludelist.txt" -exec cp '{}' "/media/fat/Scripts/.SAM_Backup" \;
	cp /media/fat/Scripts/MiSTer_SAM.ini "/media/fat/Scripts/.SAM_Backup" 2>/dev/null
	
	if [ -d "${mrsampath}" ]; then
		echo "Deleting MiSTer_SAM folder"
		rm -rf "${mrsampath}"
	fi
	if [ -f "/media/fat/Scripts/MiSTer_SAM.ini" ]; then
		echo "Deleting MiSTer_SAM.ini"
		cp /media/fat/Scripts/MiSTer_SAM.ini /media/fat/Scripts/MiSTer_SAM.ini.bak
		rm /media/fat/Scripts/MiSTer_SAM.ini
	fi
	if [ -f "/media/fat/Scripts/MiSTer_SAM_off.sh" ]; then
		echo "Deleting MiSTer_SAM_off.sh"
		rm /media/fat/Scripts/MiSTer_SAM_off.sh
	fi
	
	if [ -d "/tmp/.SAM_List" ]; then
		echo "Deleting temporary files"
		rm -rf "/tmp/.SAM_List"
	fi
	
	if ls "${configpath}/inputs*_input_1234_5678_v3.map" 1>/dev/null 2>&1; then
		echo "Deleting Keyboard mapping files"
		rm "${configpath}/inputs*_input_1234_5678_v3.map"
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

	sed -i '/MiSTer_SAM/d' ${userstartup}
	sed -i '/Super Attract/d' ${userstartup}

	printf "\nAll files deleted except for MiSTer_SAM_on.sh\n"
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

# Check if gamelists exist
function checkgl() {
	if ! compgen -G "${gamelistpath}/*_gamelist.txt" >/dev/null; then
		echo "Creating Game Lists"
		read_samini
		creategl
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
	if [ "${skipmessage}" == "yes" ] && [ "${CORE_SKIP[${nextcore}]}" == "yes" ]; then
		sleep "$skiptime"
		samdebug "Button push sent to skip BIOS"
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
		#printf "%s\n" ${corelisttmp[@]} > ${corelisttmpfile}
	fi
}


function reset_core_gl() { # args ${nextcore}
	echo " Deleting old game lists for ${1^^}..."
	rm "${gamelistpath}/${1}_gamelist.txt" &>/dev/null
	sync "${gamelistpath}"
}

function reset_ini() { # args ${nextcore}
	#Reset gamelists
	[[ -d /tmp/.SAM_List ]] && rm -rf /tmp/.SAM_List
	mkdir -p "${gamelistpathtmp}"
	mkdir -p /tmp/.SAM_tmp

	sed -i '/bgm=/c\bgm="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
    sed -i '/samvideo=/c\samvideo="No"' /media/fat/Scripts/MiSTer_SAM.ini
    sed -i '/samvideo_tvc=/c\samvideo_tvc="No"' /media/fat/Scripts/MiSTer_SAM.ini
    sed -i '/kids_safe=/c\kids_safe="no"' /media/fat/Scripts/MiSTer_SAM.ini
    sed -i '/coreweight=/c\coreweight="no"' /media/fat/Scripts/MiSTer_SAM.ini
	sed -i '/sam_goat_list=/c\sam_goat_list="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini	
}

function core_error_rom() { # core_error core /path/to/ROM
	if [ ${romloadfails} -lt ${coreretries} ]; then
		declare -g romloadfails=$((romloadfails + 1))
		echo " ERROR: Failed ${romloadfails} times. No valid game found for core: ${1} rom: ${2}"
		echo " Trying to find another rom..."
		next_core "${1}"
	else
		echo " ERROR: Failed ${romloadfails} times. No valid game found for core: ${1} rom: ${2}"
		echo " ERROR: Core ${1} is blacklisted!"
		delete_from_corelist "${1}"
		echo " List of cores is now: ${corelist[*]}"
		declare -g romloadfails=0
		# Load a different core
		next_core
	fi
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





#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# global_mute
# Sets the “mute” bit in Volume.dat without altering your current volume level.
# Then issues a live “volume mute” command to the running MiSTer core.
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# only_mute_if_needed
# Checks Volume.dat’s mute-bit and mutes only if it isn’t already set.
#-------------------------------------------------------------------------------
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

function filter_list() { # args ${nextcore} 	
		
	# Check path filter
	if [ -n "${PATHFILTER[${1}]}" ]; then 
		echo "Found path filter for ${1} core: ${PATHFILTER[${1}]}."
		fgrep "${PATHFILTER[${1}]}" "${gamelistpath}/${1}_gamelist.txt"  > "${tmpfile}"
		cp -f "${tmpfile}" "${gamelistpathtmp}/${1}_gamelist.txt"
	fi
	
	if [ -n "${arcadeorient}" ] && [[ "${1}" == "arcade" ]]; then
		echo "Setting orientation for Arcade Games to ${arcadeorient} only."
		cat "${gamelistpath}/${1}_gamelist.txt" | fgrep "Rotation/" | fgrep -i "${arcadeorient}" > "${tmpfile}_rotation"
		echo "Found $(cat "${tmpfile}_rotation" | wc -l) ${arcadeorient} games"
		
		if [ -s "${tmpfile}_rotation" ]; then 
			if [ -n "${PATHFILTER[${1}]}" ]; then
				# Apply both path filter and orientation filter
				awk -F/ '{print $NF}' "${gamelistpathtmp}/${1}_gamelist.txt" > "${tmpfile}_filenames"
				fgrep -f "${tmpfile}_filenames" "${tmpfile}_rotation" > "${tmpfile}"
				mv -f $tmpfile "${gamelistpathtmp}/${1}_gamelist.txt"
			else
				# Apply only orientation filter
				mv -f "${tmpfile}_rotation" "${gamelistpathtmp}/${1}_gamelist.txt"
			fi
		else
			echo "Arcade Orientation Filter Error."
		fi
		
	fi

	# Strip dupes	
	if [ "$dupe_mode" = "strict" ]; then
		samdebug "Using strict mode for finding duplicate roms"

		awk -F'/' '
		{
			full = $0
			lowpath = tolower(full)

			# ── A) skip if any directory in the path contains hack/beta/proto
			if ( lowpath ~ /\/[^\/]*(hack|beta|proto)[^\/]*\// )
				next

			# ── B) skip if the filename has hack/beta/proto inside parentheses
			fname = $NF
			if ( tolower(fname) ~ /\([^)]*(hack|beta|proto)[^)]*\)/ )
				next

			# ── C) strip extension
			name = fname
			sub(/\.[^.]+$/, "", name)

			# ── D) remove any parentheses and all that follows
			sub(/\s*\(.*/, "", name)

			# ── E) strip leading date (YYYY-MM or YYYY-MM-DD) or any numeric prefix
			sub(/^([0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?|[0-9]+)[^[:alnum:]]*/, "", name)

			# ── F) normalize to lowercase key
			key = tolower(name)

			# ── G) trim whitespace
			gsub(/^[ \t]+|[ \t]+$/, "", key)

			# ── H) dedupe
			if (!seen[key]++)
				print full
		}
		' "${gamelistpathtmp}/${1}_gamelist.txt" > "${tmpfile}"
	else
		awk -F'/' '!seen[$NF]++' \
			"${gamelistpathtmp}/${1}_gamelist.txt" > "${tmpfile}"
	fi




	cp -f "${tmpfile}" "${gamelistpathtmp}/${1}_gamelist.txt"
	samdebug "$(wc -l < "${gamelistpathtmp}/${1}_gamelist.txt") Games in list after removing duplicates."

	#Check exclusion or kids safe white lists
	#First check for category exclusion
	if [ -f "${gamelistpath}/${1}_gamelist_exclude.txt" ]; then
		echo "Found category excludelist for core ${1}. Stripping out unwanted games now."
		# Process full file paths from gamelist_exclude
		awk 'FNR==NR{a[$0];next} !($0 in a)' "${gamelistpath}/${1}_gamelist_exclude.txt" "${gamelistpathtmp}/${1}_gamelist.txt" > "${tmpfilefilter}" 
		mv "${tmpfilefilter}" "${gamelistpathtmp}/${1}_gamelist.txt"
	fi
	if [ -f "${gamelistpath}/${1}_excludelist.txt" ]; then
		echo "Found excludelist for core ${1}. Stripping out unwanted games now."
		# Process file names without extensions from excludelist
		awk "BEGIN { while (getline < \"${gamelistpath}/${1}_excludelist.txt\") { a[\$0] = 1 } close(\"${gamelistpath}/${1}_excludelist.txt\"); } \
		{ gamelistfile = \$0; sub(/\\.[^.]*\$/, \"\", gamelistfile); sub(/^.*\\//, \"\", gamelistfile); if (!(gamelistfile in a)) print }" \
		"${gamelistpathtmp}/${1}_gamelist.txt" > "${tmpfilefilter}"
		mv "${tmpfilefilter}" "${gamelistpathtmp}/${1}_gamelist.txt"
	fi

	
	if [ "${kids_safe}" == "yes" ]; then
		samdebug "Kids Safe Mode - Filtering Roms..."
			if [ ${1} == amiga ]; then
				fgrep -f "${mrsampath}/SAM_Rated/amiga_rated.txt" <(fgrep -v "Demo:" "${gamelistpath}/amiga_gamelist.txt") | awk -F'(' '!seen[$1]++ {print $0}' > "${tmpfilefilter}"
			else
				fgrep -f "${mrsampath}/SAM_Rated/${1}_rated.txt" "${gamelistpathtmp}/${1}_gamelist.txt" | awk -F "/" '{split($NF,a," \\("); if (!seen[a[1]]++) print $0}' > "${tmpfilefilter}"
			fi
			if [ -s "${tmpfilefilter}" ]; then 
				samdebug "$(wc -l <"${tmpfilefilter}") games after kids safe filter applied."
				cp -f "${tmpfilefilter}" "${gamelistpathtmp}/${1}_gamelist.txt"
			else
				delete_from_corelist "${1}"
				delete_from_corelist "${1}" tmp
				echo "${1} kids safe filter produced no results and will be disabled."
				echo "List of cores is now: ${corelist[*]}"
				return 1
			fi
	fi
	
	#Check ini exclusion
	if [[ "${exclude[*]}" ]]; then 
		for e in "${exclude[@]}"; do
			fgrep -viw "$e" "${gamelistpathtmp}/${1}_gamelist.txt" > "${tmpfilefilter}" && cp -f "${tmpfilefilter}" "${gamelistpathtmp}/${1}_gamelist.txt" || true
		done

	fi
 
	#Check blacklist	
	if [ "${disable_blacklist}" == "no" ] && [ -f "${gamelistpath}/${1}_blacklist.txt" ]; then
		# Sometimes fails, can't use --line-buffered in busybox fgrep which would probably fix error. 
		echo -n "Disabling static screen games for ${1} core..."
		
		# Process file names without extensions from blacklist
		awk "BEGIN { while (getline < \"${gamelistpath}/${1}_blacklist.txt\") { a[\$0] = 1 } close(\"${gamelistpath}/${1}_blacklist.txt\"); } \
		{ gamelistfile = \$0; sub(/\\.[^.]*\$/, \"\", gamelistfile); sub(/^.*\\//, \"\", gamelistfile); if (!(gamelistfile in a)) print }" \
		"${gamelistpathtmp}/${1}_gamelist.txt" > "${tmpfilefilter}"
		if [ -s "${tmpfilefilter}" ]; then 
			cp -f "${tmpfilefilter}" "${gamelistpathtmp}/${1}_gamelist.txt"
		else
			samdebug "Blacklist filter failed" 
		fi
		echo " $(wc -l <"${gamelistpathtmp}/${1}_gamelist.txt") games will be shuffled."
	fi
	return 0
}


function samdebug() {
    local ts msg
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    msg="$*"

    if [[ "${samdebug}" == "yes" ]]; then
        # coloured console output
        echo -e "\e[1m\e[31m[${ts}] ${msg}\e[0m"
    fi

    if [[ "${samdebuglog}" == "yes" ]]; then
        # plain timestamped log
        echo "[${ts}] ${msg}" >> /tmp/samdebug.log
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
		bgm_stop

	fi
	

}

function bgm_stop() {

	if [ "${bgm}" == "yes" ] || [ "$1" == "force" ]; then
		echo -n "Stopping Background Music Player... "
		echo -n "set playincore no" | socat - UNIX-CONNECT:/tmp/bgm.sock &>/dev/null
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

    for blacklist_file in \
        "amiga_blacklist.txt" \
        "arcade_blacklist.txt" \
        "fds_blacklist.txt" \
        "gba_blacklist.txt" \
        "genesis_blacklist.txt" \
        "megacd_blacklist.txt" \
        "n64_blacklist.txt" \
        "nes_blacklist.txt" \
        "neogeo_blacklist.txt" \
        "psx_blacklist.txt" \
        "s32x_blacklist.txt" \
        "sms_blacklist.txt" \
        "snes_blacklist.txt" \
        "tgfx16_blacklist.txt" \
        "tgfx16cd_blacklist.txt"; do
        remote_url="${raw_base}/.MiSTer_SAM/SAM_Gamelists/$blacklist_file"
        tmp_file="/tmp/$blacklist_file"
        local_file="${mrsampath}/SAM_Gamelists/$blacklist_file"

        check_and_update "$remote_url" "$tmp_file" "$local_file" "$blacklist_file"
    done
    echo "Blacklist files updated."
}


function get_ratedlist() {
    if [ "${kids_safe}" == "yes" ]; then
        echo "Downloading lists with kids-friendly games..."

        for rated_file in \
            "arcade_rated.txt" \
            "amiga_rated.txt" \
            "ao486_rated.txt" \
            "fds_rated.txt" \
            "gb_rated.txt" \
            "gbc_rated.txt" \
            "gba_rated.txt" \
            "gg_rated.txt" \
            "genesis_rated.txt" \
            "megacd_rated.txt" \
            "nes_rated.txt" \
            "neogeo_rated.txt" \
            "psx_rated.txt" \
            "sms_rated.txt" \
            "snes_rated.txt" \
            "tgfx16_rated.txt" \
            "tgfx16cd_rated.txt"; do
            remote_url="${raw_base}/.MiSTer_SAM/SAM_Rated/$rated_file"
            tmp_file="/tmp/$rated_file"
            local_file="${mrsampath}/SAM_Rated/$rated_file"

            check_and_update "$remote_url" "$tmp_file" "$local_file" "$rated_file"
        done
        echo "Rated lists updated."
    fi
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
		

		if [ -f /media/fat/Scripts/MiSTer_SAM.ini ]; then
			echo " MiSTer SAM INI already exists... Merging with new ini."
			get_samstuff MiSTer_SAM.ini /tmp
			echo " Backing up MiSTer_SAM.ini to MiSTer_SAM.ini.bak"
			cp /media/fat/Scripts/MiSTer_SAM.ini /media/fat/Scripts/MiSTer_SAM.ini.bak
			echo -n " Merging ini values.."
			# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
			sed -i 's/==/--/g' /media/fat/Scripts/MiSTer_SAM.ini
			sed -i 's/-=/--/g' /media/fat/Scripts/MiSTer_SAM.ini
			awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' /media/fat/Scripts/MiSTer_SAM.ini /tmp/MiSTer_SAM.ini >/tmp/MiSTer_SAM.tmp && cp -f --force /tmp/MiSTer_SAM.tmp /media/fat/Scripts/MiSTer_SAM.ini
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
	inmenu=1
	dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Exit" \
		--backtitle "Super Attract Mode" --title "[ Main Menu ]" \
		--menu "Use the arrow keys and enter \nor the d-pad and A button" 0 0 0 \
		Start "Start SAM" \
		Startmonitor "Start SAM And Monitor (SSH)" \
		Stop "Stop SAM" \
		Skip "Skip Game" \
		Update "Update to latest" \
		Ignore "Ignore current game and exclude" \
		----- "-----------------------------" \
		gamemode "Presets and Game Modes" \
		sam_coreconfig "Configure Core List" \
		sam_exittask "Configure Exit Behavior" \
		sam_controller "Configure Gamepad" \
		sam_filters "Filters" \
		sam_bgm "Add-ons" \
		config "MiSTer_SAM.ini Editor" \
		Settings "Settings" \
		Reset "Reset or uninstall SAM" 2>"${sam_menu_file}"
	
	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	clear
	
	if [ "$opt" != "0" ]; then
		exit
	elif [[ "${menuresponse,,}" == "start" ]]; then
		/media/fat/Scripts/MiSTer_SAM_on.sh start
	elif [[ "${menuresponse,,}" == "startmonitor" ]]; then
		/media/fat/Scripts/MiSTer_SAM_on.sh sm
	elif [[ "${menuresponse,,}" == "sam_coreconfig" ]]; then
		sam_coreconfig
	elif [[ "${menuresponse,,}" == "-----" ]]; then
		sam_menu
	elif [[ "${menuresponse,,}" == "sam_exittask" ]]; then
		sam_exittask
	elif [[ "${menuresponse,,}" == "sam_controller" ]]; then
		sam_controller
	elif [[ "${menuresponse,,}" == "sam_bgm" ]]; then
		sam_bgmmenu	
	elif [[ "${menuresponse,,}" == "sam_filters" ]]; then
		sam_filters
	else 
		parse_cmd "${menuresponse}"
	fi

}


function changes_saved () {
	dialog --clear --ascii-lines --no-cancel \
	--backtitle "Super Attract Mode" --title "[ Settings ]" \
	--msgbox "Changes saved!" 0 0
}

function sam_settings() {
	dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Back" \
		--backtitle "Super Attract Mode" --title "[ Settings ]" \
		--menu "Use the arrow keys and enter \nor the d-pad and A button" 0 0 0 \
		sam_timer "Select Timers - When SAM should start" \
		sam_mute "Mute Cores while SAM is on" \
		autoplay "Autoplay Configuration" \
		enablekidssafe "Enable Kids Safe Filter" \
		disablekidssafe "Disable Kids Safe Filter" \
		sam_misc "Advanced Settings" 2>"${sam_menu_file}"
	
	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	clear
	
	if [ "$opt" != "0" ]; then
		sam_menu
	elif [[ "${menuresponse,,}" == "sam_timer" ]]; then
		sam_timer
	elif [[ "${menuresponse,,}" == "sam_mute" ]]; then
		sam_mute
	elif [[ "${menuresponse,,}" == "sam_misc" ]]; then
		sam_misc	
	elif [[ "${menuresponse,,}" == "arcade_orient" ]]; then
		arcade_orient
	elif [[ "${menuresponse,,}" == "enablekidssafe" ]]; then
		if [[ "$shown" == "0" ]]; then
		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super Attract Mode" --title "[ KIDS SAFE FILTER ]" \
			--msgbox "Good to use if you have young children. Limits rom selection to ESRB rated games with the 'All Ages' label\n\nOn first boot, SAM will download the ESRB game whitelists. \n\nAlso 'Alternative Core Selection Mode' will be enabled. " 0 0
		fi
		sed -i '/kids_safe=/c\kids_safe="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
		sed -i '/coreweight=/c\coreweight="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
		changes_saved
		sam_settings
	elif [[ "${menuresponse,,}" == "disablekidssafe" ]]; then
		sed -i '/kids_safe=/c\kids_safe="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
		sed -i '/coreweight=/c\coreweight="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
		changes_saved
		sam_settings
	else 
		parse_cmd "${menuresponse}"
	fi

}

function sam_filters() {
	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ MISCELLANEOUS OPTIONS ]" \
		--menu "Select from the following options?" 0 0 0 \
		Include "Select Single Category/Genre" \
		exclude "Exclude Categories/Genres" \
		arcadehoriz "Only show Horizontal Arcade Games" \
		arcadevert "Only show Vertical Arcade Games" \
		arcadedisable "Show all Arcade Games" 2>"${sam_menu_file}" 

	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	
	if [ "$opt" != "0" ]; then
		sam_menu
	elif [[ "${menuresponse,,}" == "arcadehoriz" ]]; then
		#sed -i '/arcadepathfilter=/c\arcadepathfilter="'"_Horizontal"'"' /media/fat/Scripts/MiSTer_SAM.ini
		sed -i '/arcadeorient=/c\arcadeorient="'"horizontal"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "arcadevert" ]]; then
		sed -i '/arcadeorient=/c\arcadeorient="'"vertical"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "arcadedisable" ]]; then
		sed -i '/arcadeorient=/c\arcadeorient="'""'"' /media/fat/Scripts/MiSTer_SAM.ini
	else 
		parse_cmd "${menuresponse}"
	fi
	changes_saved
	sam_filters
}


function sam_misc() {
	if [[ "$shown" == "0" ]]; then
		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super Attract Mode" --title "[ ALT CORE MODE ]" \
			--msgbox "Alternative Core Mode will prefer cores with larger libraries so you don't have many game repeats.\n\nPlease set up controller in main menu instead of using Play Current Game if possible." 0 0
	fi
	dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Back" \
		--backtitle "Super Attract Mode" --title "[ MISCELLANEOUS OPTIONS ]" \
		--menu "Select from the following options?" 0 0 0 \
		enablemenuonly "Start SAM only in MiSTer Menu" \
		disablemenuonly "Start SAM outside of MiSTer Menu" \
		----- "-----------------------------" \
		enablealtcore "Enable Alternative Core Selection Mode" \
		disablealtcore "Disable Alternative Core Selection Mode" \
		----- "-----------------------------" \
		enablelistenjoy "Enable Joystick detection" \
		disablelistenjoy "Disable Joystick detection" \
		enablelistenkey "Enable Keyboard detection" \
		disablelistenkey "Disable Keyboard detection" \
		enablelistenmouse "Enable Mouse detection" \
		disablelistenmouse "Disable Mouse detection" \
		----- "-----------------------------" \
		enabledebug "Enable Debug" \
		disabledebug  "Disable Debug" \
		enabledebuglog "Enable Debug Log File" \
		disabledebuglog  "Disable Debug Log File" 2>"${sam_menu_file}" 

	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	
	if [ "$opt" != "0" ]; then
		sam_menu
	elif [[ "${menuresponse,,}" == "enablemenuonly" ]]; then
		sed -i '/menuonly=/c\menuonly="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "-----" ]]; then
		shown=1	
		sam_misc
	elif [[ "${menuresponse,,}" == "disablemenuonly" ]]; then
		sed -i '/menuonly=/c\menuonly="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "enablealtcore" ]]; then
		sed -i '/coreweight=/c\coreweight="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "disablealtcore" ]]; then
		sed -i '/coreweight=/c\coreweight="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "enablelistenjoy" ]]; then
		sed -i '/listenjoy=/c\listenjoy="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "disablelistenjoy" ]]; then
		sed -i '/listenjoy=/c\listenjoy="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "enablelistenkey" ]]; then
		sed -i '/listenkeyboard=/c\listenkeyboard="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "disablelistenkey" ]]; then
		sed -i '/listenkeyboard=/c\listenkeyboard="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "enablelistenmouse" ]]; then
		sed -i '/listenmouse=/c\listenmouse="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "disablelistenmouse" ]]; then
		sed -i '/listenmouse=/c\listenmouse="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "enabledebug" ]]; then
		sed -i '/samdebug=/c\samdebug="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "disabledebug" ]]; then
		sed -i '/samdebug=/c\samdebug="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini	
	elif [[ "${menuresponse,,}" == "enabledebuglog" ]]; then
		sed -i '/samdebuglog=/c\samdebuglog="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "disabledebuglog" ]]; then
		sed -i '/samdebuglog=/c\samdebuglog="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
	fi
	dialog --clear --ascii-lines --no-cancel \
	--backtitle "Super Attract Mode" --title "[ Settings ]" \
	--msgbox "Changes saved!" 0 0
	shown=1	
	sam_misc
}



function sam_mute() {
	dialog --clear --no-cancel --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ MUTE ]" \
		--msgbox "SAM uses the core mute feature of MiSTer which will turn the volume low.\n\nYou might still hear a bit of the core's sounds.\n\nYou can also use global mute but it's not as well supported with SAM." 0 0

	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ BACKGROUND MUSIC ENABLER ]" \
		--menu "Select from the following options?" 0 0 0 \
		globalmute "Mute Global Volume" \
		disablemute "Unmute Volume for all Cores" 2>"${sam_menu_file}" 

	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	
	if [ "$opt" != "0" ]; then
		sam_menu
	elif [[ "${menuresponse,,}" == "disablemute" ]]; then
		sed -i '/mute=/c\mute="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
	elif [[ "${menuresponse,,}" == "globalmute" ]]; then
		sed -i '/mute=/c\mute="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
	fi
	dialog --clear --ascii-lines --no-cancel \
	--backtitle "Super Attract Mode" --title "[ Settings ]" \
	--msgbox "Changes saved!" 0 0
	sam_settings
			
}

function sam_exittask() {
	if [[ "$shown" == "0" ]]; then
		if [[ "${playcurrentgame}" == "yes" ]]; then
			dialog --clear --no-cancel --ascii-lines \
				--backtitle "Super Attract Mode" --title "[ SAM EXIT ]" \
				--msgbox "Currently, SAM will play the current game when you push a button." 0 0
		else
			dialog --clear --no-cancel --ascii-lines \
				--backtitle "Super Attract Mode" --title "[ SAM EXIT ]" \
				--msgbox "Currently, SAM will exit back to the MiSTer menu when you push a button.\n\nIf you configured your controller, SAM will still play the current game if you push the Start button." 0 0
		fi
	shown=1
	fi
	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ SAM EXIT ]" \
		--menu "Select from the following options?" 0 0 0 \
		enableplaycurrent "On Exit, Play current Game" \
		disableplaycurrent "On Exit, Return to Menu (Except Start Button)" 2>"${sam_menu_file}" 

	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	
	if [ "$opt" != "0" ]; then
		sam_menu
	elif [[ "${menuresponse,,}" == "enableplaycurrent" ]]; then
		sed -i '/playcurrentgame=/c\playcurrentgame="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
		changes_saved
	elif [[ "${menuresponse,,}" == "disableplaycurrent" ]]; then
		sed -i '/playcurrentgame=/c\playcurrentgame="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
		changes_saved
	elif [[ "${menuresponse,,}" == "globalmute" ]]; then
		sed -i '/mute=/c\mute="'"Global"'"' /media/fat/Scripts/MiSTer_SAM.ini
	fi
	dialog --clear --ascii-lines --no-cancel \
	--backtitle "Super Attract Mode" --title "[ SAM EXIT ]" \
	--msgbox "Changes saved!" 0 0
	sam_exittask		
}

function sam_controller() {
    dialog --clear --no-cancel --ascii-lines \
        --backtitle "Super Attract Mode" --title "[ CONTROLLER SETUP ]" \
        --msgbox "Configure your controller so that pushing the start button will play the current game.\nNext button will shuffle to next game.\n\nAny other button will exit SAM. " 0 0
    dialog --clear --no-cancel --ascii-lines \
        --backtitle "Super Attract Mode" --title "[ CONTROLLER SETUP ]" \
        --msgbox "Connect one controller at a time.\n\nPress ok and push start button on blank screen" 0 0
    c_json="${mrsampath}/sam_controllers.json"
    c_custom_json="${mrsampath}/sam_controllers.custom.json"
    id="$(${mrsampath}/MiSTer_SAM_joy.py /dev/input/js0 id)"
    name="$(grep -iwns "js0" /proc/bus/input/devices -B 4 | grep Name | awk -F'"' '{print $2}')"
    startbutton="$(${mrsampath}/MiSTer_SAM_joy.py /dev/input/js0 button)"
    echo start button: "$startbutton"
    echo controller id: "$id"

    # New dialog to capture the "next" button
    dialog --clear --no-cancel --ascii-lines \
        --backtitle "Super Attract Mode" --title "[ NEXT BUTTON SETUP ]" \
        --msgbox "Now, push the button you want to use for the 'next' action.\nThis button will be used to navigate to the next game in SAM." 0 0
    nextbutton="$(${mrsampath}/MiSTer_SAM_joy.py /dev/input/js0 button)"
    echo next button: "$nextbutton"

    if [[ "$startbutton" == *"not exist"* ]]; then
        dialog --clear --no-cancel --ascii-lines \
        --backtitle "Super Attract Mode" --title "[ CONTROLLER SETUP ]" \
        --msgbox "No joysticks connected. " 0 0
        sam_exittask
    else
    	if [ -e "${c_custom_json}" ]; then
        	jq --arg name "$name" --arg id "$id" --argjson start "$startbutton" --argjson next "$nextbutton" \
            '. + {($id): {"name": $name, "button": {"start": $start, "next": $next}, "axis": {}}}' ${c_custom_json} > /tmp/temp.json && mv /tmp/temp.json "${c_custom_json}"
        else 
            jq --arg name "$name" --arg id "$id" --argjson start "$startbutton" --argjson next "$nextbutton" \
            '. + {($id): {"name": $name, "button": {"start": $start, "next": $next}, "axis": {}}}' ${c_json} > /tmp/temp.json && mv /tmp/temp.json "${c_custom_json}"
        fi

        dialog --clear --no-cancel --ascii-lines \
        --backtitle "Super Attract Mode" --title "[ CONTROLLER SETUP COMPLETED ]" \
        --msgbox "Added $name with Start and Next buttons configured." 0 0
        # New Yes/No dialog to recommend setting playcurrentgame to no
		dialog --clear --yesno "Since you now have a button to start a game,\nI recommend we set playcurrentgame variable to no. \nThis will quit SAM and exit to the menu except if start button is pushed." 0 0
		response=$?
		
		if [ $response -eq 0 ]; then
			sed -i '/playcurrentgame=/c\playcurrentgame="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
			dialog --clear --msgbox "playcurrentgame has been set to no. Please reboot MiSTer or reconnect controller for changes to take effect." 0 0
		else
			dialog --clear --msgbox "Keeping current playcurrentgame setting. Please reboot MiSTer or reconnect controller for changes to take effect." 0 0
		fi
		sam_menu

    fi
}

function sam_timer() {
	if [[ "$shown" == "0" ]]; then
		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
			--msgbox "Super Attract Mode starts after you haven't used your controller for a certain amount of time\n\n\nConfigure when SAM should start showing games and how long SAM shows games for." 0 0
	fi
	dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Back" \
		--backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
		--menu "Select an option" 0 0 0 \
		samtimeout1 "Wait 1 minute before showing games" \
		samtimeout2 "Wait 2 minutes before showing games" \
		samtimeout3 "Wait 3 minutes before showing games" \
		samtimeout5 "Wait 5 minutes before showing games" \
		gametimer1 "Show Games for 1 minute" \
		gametimer2 "Show Games for 2 minutes" \
		gametimer3 "Show Games for 3 minutes" \
		gametimer5 "Show Games for 5 minutes" \
		gametimer10 "Show Games for 10 minutes" \
		gametimer15 "Show Games for 15 minutes" 2>"${sam_menu_file}"	
	
		opt=$?
		menuresponse=$(<"${sam_menu_file}")
		
		if [ "$opt" != "0" ]; then
			sam_menu
		elif [[ "${menuresponse}" == *"samtimeout"* ]]; then
			timemin=${menuresponse//samtimeout/}
			samtimeout=$((timemin*60))
			sed -i '/samtimeout=/c\samtimeout="'"$samtimeout"'"' /media/fat/Scripts/MiSTer_SAM.ini
			dialog --clear --ascii-lines --no-cancel \
			--backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
			--msgbox "Changes saved. Wait now for $samtimeout seconds" 0 0
			shown=1
			sam_timer
		elif [[ "${menuresponse}" == *"gametimer"* ]]; then
			timemin=${menuresponse//gametimer/}
			gametimer=$((timemin*60))
			sed -i '/gametimer=/c\gametimer="'"$gametimer"'"' /media/fat/Scripts/MiSTer_SAM.ini
			dialog --clear --ascii-lines --no-cancel \
			--backtitle "Super Attract Mode" --title "[ GAME TIMER ]" \
			--msgbox "Changes saved. Show games now for $gametimer seconds" 0 0
			shown=1
			sam_timer
		fi
}


function sam_coreconfig() {
	if [[ "$shown" == "0" ]]; then
		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super Attract Mode" --title "[ CORE CONFIG ]" \
			--msgbox "Current corelist:\n\n${corelist[*]}" 0 0
	fi
	shown=1
	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ CORE CONFIG ]" \
		--menu "Select from the following options?" 0 0 0 \
		sam_corelist_preset "Presets for Core List" \
		sam_corelist "Enable/Disable cores (Keyboard support only)" \
		single "Only play Games from one Core (until reboot)" 2>"${sam_menu_file}" 

	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	
	if [ "$opt" != "0" ]; then
		sam_menu
	elif [[ "${menuresponse,,}" == "sam_corelist_preset" ]]; then
		sam_corelist_preset
	elif [[ "${menuresponse,,}" == "sam_corelist" ]]; then
		sam_corelist
	else 
		parse_cmd "${menuresponse}"
	fi
	sam_menu
			
}

function sam_corelist() {
	dialog --clear --no-cancel --ascii-lines \
	--backtitle "Super Attract Mode" --title "[ CORE CONFIGURATION]" \
	--msgbox "Joystick is currently not supported to select cores. You need a keyboard to enable/disable cores with space key.\n\nPlease exit this menu if you are using a joystick." 0 0
	declare -a corelistmenu=()
	for core in "${corelistall[@]}"; do
		corelistmenu+=("${core}")
		corelistmenu+=("Show ${CORE_PRETTY[${core}]} Games")
		if [[ "${corelist[*]}" == *"$core"* ]]; then
			corelistmenu+=("ON")
		else
			corelistmenu+=("OFF")
		fi
	done

	dialog --ok-label "Save Selection" --cancel-label "Back" \
	--separate-output --checklist "Corelist Config:" 0 0 0 \
	"${corelistmenu[@]}" 2>"${sam_menu_file}"
	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	clear
	
	if [ "$opt" != "0" ]; then
		sam_menu
	else 
		declare -a corelistnew=()
		for choice in ${menuresponse}; do
			case $choice in
				"$choice")
					corelistnew+=("$choice")
					;;															
			esac
		done
	fi
	if [[ "${corelistnew[*]}" ]]; then
		unset corelist
		corelistmod="$(echo "${corelistnew[@]}" | tr ' ' ',' | tr -s ' ')"
		sed -i '/corelist=/c\corelist="'"$corelistmod"'"' /media/fat/Scripts/MiSTer_SAM.ini
		dialog --clear --ascii-lines --no-cancel \
		--backtitle "Super Attract Mode" --title "[ Settings ]" \
		--msgbox "Changes saved. Core list is now: $corelistmod" 0 0
	fi
	sam_menu
}

function sam_corelist_preset() {
	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ CORELIST PRESET ]" \
		--menu "Select an option" 0 0 0 \
		2 "Only Arcade & Console Cores" \
		1 "Only Arcade and NeoGeo games" \
		6 "Only Arcade and NeoGeo games from the 1990s" \
		3 "Only Handheld Cores" \
		4 "Only Computer Cores" \
		5 "Only Cores from the 1990s (no handheld)" \
		7 "mrchrisster's Selection of favorite cores" 2>"${sam_menu_file}"	
	
		opt=$?
		menuresponse=$(<"${sam_menu_file}")
		
		if [ "$opt" != "0" ]; then
			sam_menu
		elif [[ "${menuresponse}" == "1" ]]; then
			sed -i '/corelist=/c\corelist="'"arcade,neogeo"'"' /media/fat/Scripts/MiSTer_SAM.ini
		elif [[ "${menuresponse}" == "2" ]]; then
			sed -i '/corelist=/c\corelist="'"arcade,atari2600,atari5200,atari7800,fds,genesis,megacd,neogeo,nes,saturn,s32x,sms,snes,tgfx16,tgfx16cd,psx"'"' /media/fat/Scripts/MiSTer_SAM.ini
		elif [[ "${menuresponse}" == "3" ]]; then
			sed -i '/corelist=/c\corelist="'"gb,gbc,gba,gg,atarilynx"'"' /media/fat/Scripts/MiSTer_SAM.ini
		elif [[ "${menuresponse}" == "4" ]]; then
			sed -i '/corelist=/c\corelist="'"amiga,c64,coco2"'"' /media/fat/Scripts/MiSTer_SAM.ini
		elif [ "${menuresponse}" -eq "5" ]; then
			dialog --clear --ascii-lines --no-cancel \
			--backtitle "Super Attract Mode" --title "[ CORELIST PRESET ]" \
			--yesno "This will set Arcade Path Filter to 1990's\nYou can remove the filter later by clicking No here." 0 0
			response=$?
			case $response in
			   0) sed -i '/arcadepathfilter=/c\arcadepathfilter="'"_The 1990s"'"' /media/fat/Scripts/MiSTer_SAM.ini	   
				;;
			   1) sed -i '/arcadepathfilter=/c\arcadepathfilter="'""'"' /media/fat/Scripts/MiSTer_SAM.ini
				;;
			   255) exit;;
			esac
			sed -i '/corelist=/c\corelist="'"arcade,genesis,megacd,neogeo,saturn,s32x,snes,tgfx16,tgfx16cd,psx"'"' /media/fat/Scripts/MiSTer_SAM.ini
		elif [ "${menuresponse}" -eq "6" ]; then
			dialog --clear --ascii-lines --no-cancel \
			--backtitle "Super Attract Mode" --title "[ CORELIST PRESET ]" \
			--yesno "This will set Arcade Path Filter to 1990's\nYou can remove the filter later by clicking No here." 0 0
			response=$?
			case $response in
			   0) sed -i '/arcadepathfilter=/c\arcadepathfilter="'"_The 1990s"'"' /media/fat/Scripts/MiSTer_SAM.ini
				;;
			   1) sed -i '/arcadepathfilter=/c\arcadepathfilter="'""'"' /media/fat/Scripts/MiSTer_SAM.ini
				;;
			   255) exit;;
			esac
			sed -i '/corelist=/c\corelist="'"arcade,neogeo"'"' /media/fat/Scripts/MiSTer_SAM.ini
		elif [[ "${menuresponse}" == "7" ]]; then
			sed -i '/corelist=/c\corelist="'"amiga,amigacd32,ao486,arcade,fds,genesis,megacd,neogeo,neogeocd,n64,nes,saturn,s32x,sms,snes,tgfx16,tgfx16cd,psx"'"' /media/fat/Scripts/MiSTer_SAM.ini
		fi
		dialog --clear --ascii-lines --no-cancel \
		--backtitle "Super Attract Mode" --title "[ CORELIST PRESET ]" \
		--msgbox "Changes saved!" 0 0
		sam_menu
}


function sam_singlemenu() {
	declare -a menulist=()
	for core in "${corelistall[@]}"; do
		menulist+=("${core^^}")
		menulist+=("${CORE_PRETTY[${core}]} games only")
	done

	dialog --clear --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ Single System Select ]" \
		--menu "Which system?" 0 0 0 \
		"${menulist[@]}" 2>"${sam_menu_file}"
	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	clear
	
	if [ "$opt" != "0" ]; then
		sam_menu
	else 
		parse_cmd "${menuresponse}"
	fi

}


function sam_resetmenu() {
	inmenu=1
	dialog --clear --no-cancel --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ Reset ]" \
		--menu "Select an option" 0 0 0 \
		Gamelists "Reset Game Lists" \
		Resetini "Reset MiSTer_SAM.ini to defaults" \
		Deleteall "Uninstall SAM" \
		Default "Reinstall SAM" \
		Back 'Previous menu' 2>"${sam_menu_file}"
	menuresponse=$(<"${sam_menu_file}")
	clear

	samdebug "menuresponse: ${menuresponse}"
	parse_cmd "${menuresponse}"
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
		Back 'Previous menu' 2>"${sam_menu_file}"
	menuresponse=$(<"${sam_menu_file}")
	clear

	samdebug  "menuresponse: ${menuresponse}"
	parse_cmd "${menuresponse}"
}

function sam_autoplaymenu() {
	dialog --clear --no-cancel --ascii-lines --no-tags \
		--backtitle "Super Attract Mode" --title "[ Configure Autoplay ]" \
		--menu "Select an option" 0 0 0 \
		Enable "Enable Autoplay" \
		Disable "Disable Autoplay" \
		Back 'Previous menu' 2>"${sam_menu_file}"
	menuresponse=$(<"${sam_menu_file}")

	clear
	samdebug  "menuresponse: ${menuresponse}"
	parse_cmd "${menuresponse}"
}

function sam_configmenu() {
	dialog --clear --ascii-lines --no-cancel \
		--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
		--msgbox "Here you can configure the INI settings for SAM.\n\nUse TAB to switch between editing, the OK and Cancel buttons." 0 0

	dialog --clear --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
		--editbox "${samini_file}" 0 0 2>"${sam_menu_file}"

	if [ -s "${sam_menu_file}" ] && [ "$(diff -wq "${sam_menu_file}" "${samini_file}")" ]; then
		cp -f "${sam_menu_file}" "${samini_file}"
		dialog --clear --ascii-lines --no-cancel \
			--backtitle "Super Attract Mode" --title "[ INI Settings ]" \
			--msgbox "Changes saved!" 0 0
	fi

	parse_cmd menu
}
function sam_gamemodemenu() {
	inmenu=1
	dialog --clear --ascii-lines --no-tags --ok-label "Select" --cancel-label "Exit" \
		--backtitle "Super Attract Mode" --title "[ Main Menu ]" \
		--menu "Use the arrow keys and enter \nor the d-pad and A button" 0 0 0 \
		sam_standard "Default Setting - Play all cores muted" \
		sam_goat_mode "Play the Greatest of All Time Attract modes." \
		sam_80s "Play 80s Music, no Handhelds and only Horiz. games." \
		sam_svc "Play TV commercials and then show the advertised game." \
		sam_m82_mode "Turn your MiSTer into a NES M82 unit." \
		sam_roulettemenu "Game Roulette" 2>"${sam_menu_file}"	
	
	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	clear
	
	if [ "$opt" != "0" ]; then	
		sam_menu
	else 
		resetini bgm samvideo m82
		"${menuresponse}"
	fi
}

# M82 mode
sam_m82_mode() {
	reset_ini
	if [ "${menuresponse}" == "sam_m82_mode" ]; then
		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super Attract Mode" --title "[ M82 MODE ]" \
			--msgbox "SAM will act as an M82 unit for NES. MiSter will restart now. To disable this, go to MiSTer_SAM.ini and find m82 option.\n\n" 0 0
			sed -i '/m82=/c\m82="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
			sam_start
	fi	
	

}

sam_standard() {
	if [ "${menuresponse}" == "sam_standard" ]; then
		reset_ini
		# Build corelistall dynamically from CORE_PRETTY keys
		corelistall=$(printf "%s\n" "${!CORE_PRETTY[@]}" | sort | paste -sd "," -)
		sed -i '/mute=/c\mute="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
		sed -i "/^corelist=/c\corelist=\"$corelistall\"" /media/fat/Scripts/MiSTer_SAM.ini		
	    sed -i '/arcadeorient=/c\arcadeorient="'"horizontal"'"' /media/fat/Scripts/MiSTer_SAM.ini
	    sam_start
	fi
}

# Function to process the GOAT list and create game list files
sam_goat_mode() {
	reset_ini
	if [ "${menuresponse}" == "sam_goat_mode" ]; then
		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super Attract Mode" --title "[ GOAT MODE ]" \
			--msgbox "SAM will only play games deemed to have the Greatest of All Time Attract Modes.\n\nPress start now." 0 0
	fi	
	samdebug "SAM GOAT mode active"
    local current_core=""
    local goat_list_path="${gamelistpath}"/sam_goat_list.txt
	# Check if the GOAT list file exists
    if [ ! -f "$goat_list_path" ]; then
        echo "Error: The GOAT list file ($goat_list_path) does not exist. Updating SAM now. Please try again."
		repository_url="https://github.com/mrchrisster/MiSTer_SAM"
		get_samstuff .MiSTer_SAM/SAM_Gamelists/sam_goat_list.txt "${gamelistpath}"
        #return 1  # Exit the function with an error status
    fi
	
	# process files
	
	while read -r line; do
		if [[ "$line" =~ ^\[.+\]$ ]]; then
			current_core=${line:1:-1}
			current_core=${current_core,,} 
			if [ ! -f "${gamelistpath}/${current_core}_gamelist.txt" ]; then
                # Create the gamelist if it doesn't exist
                create_gamelist "$current_core"
            fi
       elif [ -n "$current_core" ]; then
            # Filter the existing gamelist for the current core
            fgrep -i -m 1 "$line" "${gamelistpath}/${current_core}_gamelist.txt" >> "${gamelistpathtmp}/${current_core}_gamelist.txt"
        fi
	done < "$goat_list_path"
	readarray -t corelist <<< "$(find "${gamelistpathtmp}" -name "*_gamelist.txt" -exec basename \{} \; | cut -d '_' -f 1)"
	printf "%s\n" "${corelist[@]}" > "${corelistfile}"
	sed -i '/sam_goat_list=/c\sam_goat_list="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini

	if [ "${menuresponse}" == "sam_goat_mode" ]; then
		sam_menu
	fi
}

function sam_80s() {
	reset_ini
	sed -i '/corelist=/c\corelist="'"amiga,arcade,fds,genesis,megacd,n64,neogeo,nes,saturn,s32x,sms,snes,tgfx16,tgfx16cd,psx"'"' /media/fat/Scripts/MiSTer_SAM.ini
	sed -i '/arcadeorient=/c\arcadeorient="'"horizontal"'"' /media/fat/Scripts/MiSTer_SAM.ini
	enablebgm
	sam_start
}


function sam_svc() {
	reset_ini
    # Display initial message
    dialog --clear --ascii-lines --no-cancel \
        --backtitle "Super Attract Mode" --title "[ INI Settings ]" \
        --msgbox "SAM can play video on your MiSTer. This mode will download commercials from archive.org and then play them.\n\nIt will try and find the game that was advertised afterwards." 0 0

    # Ask the user to choose between HDMI and CRT
    exec 3>&1
    selection=$(dialog --clear --ascii-lines --no-cancel --backtitle "Super Attract Mode" \
        --title "[ Output Selection ]" \
        --menu "Choose your video output device:" 15 50 2 \
        "1" "HDMI" \
        "2" "CRT" \
        2>&1 1>&3)
    exit_status=$?
    exec 3>&-

    # Check if user pressed cancel or escape
    if [ $exit_status != 0 ]; then
        echo "Operation cancelled."
        return
    fi

    # Update configuration based on the selection
    case $selection in
        1) # HDMI selected
            echo "Setting up for HDMI output..."
            sed -i '/samvideo_output=/c\samvideo_output="HDMI"' /media/fat/Scripts/MiSTer_SAM.ini
            ;;
        2) # CRT selected
            echo "Setting up for CRT output..."
            sed -i '/samvideo_output=/c\samvideo_output="CRT"' /media/fat/Scripts/MiSTer_SAM.ini
            ;;
    esac

    # Ask if the user wants to keep local copies of videos
    exec 3>&1
    keep_local_copy=$(dialog --clear --ascii-lines --no-cancel --backtitle "Super Attract Mode" \
        --title "[ Local Copy Option ]" \
        --menu "Do you want to keep local copies of videos? (Make sure you have around 4GB available on SD)" 15 50 2 \
        "1" "Yes" \
        "2" "No" \
        2>&1 1>&3)
    exec 3>&-

    # Set the keep_local_copy variable in the configuration file
    if [ "$keep_local_copy" == "1" ]; then
        sed -i '/keep_local_copy=/c\keep_local_copy="yes"' /media/fat/Scripts/MiSTer_SAM.ini
    else
        sed -i '/keep_local_copy=/c\keep_local_copy="no"' /media/fat/Scripts/MiSTer_SAM.ini
    fi

    # Additional configuration settings
	sed -i '/corelist=/c\corelist="'"arcade,atarilynx,gb,gbc,genesis,gg,megacd,n64,nes,psx,saturn,s32x,sgb,sms,snes,tgfx16,tgfx16cd"'"' /media/fat/Scripts/MiSTer_SAM.ini
    sed -i '/samvideo=/c\samvideo="Yes"' /media/fat/Scripts/MiSTer_SAM.ini
    sed -i '/samvideo_source=/c\samvideo_source="Archive"' /media/fat/Scripts/MiSTer_SAM.ini
    sed -i '/samvideo_tvc=/c\samvideo_tvc="Yes"' /media/fat/Scripts/MiSTer_SAM.ini
	
    # Check for specific game list for the chosen output device
    if [ ! -f "${gamelistpath}/nes_tvc.txt" ]; then
        get_samvideo
    fi

    # Final confirmation message
    dialog --clear --ascii-lines --no-cancel \
        --backtitle "Super Attract Mode" --title "[ INI Settings ]" \
        --msgbox "All set.\n\nIf nothing happens after you press OK, please allow some time for the commercial to download first." 0 0

    # Start the SAM video mode or any other service
    
    sam_start
}


	

function sam_roulettemenu() {
	reset_ini
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
		Roulettetimer "Play a random game for ${roulettetimer} secs (roulettetimer in MiSTer_SAM.ini). " 2>"${sam_menu_file}"	
	
		opt=$?
		menuresponse=$(<"${sam_menu_file}")
		
		if [ "$opt" != "0" ]; then
			sam_menu
		elif [ "${menuresponse}" == "Roulettetimer" ]; then
			{
			echo "gametimer=${roulettetimer}"
			echo "mute=no"
			echo "listenmouse=No"
			echo "listenkeyboard=No"
			echo "listenjoy=No"
			} >/tmp/.SAM_tmp/gameroulette.ini
		else
			timemin=${menuresponse//Roulette/}
			{		
			echo "gametimer=$((timemin*60))"
			echo "mute=no"
			echo "listenmouse=No"
			echo "listenkeyboard=No"
			echo "listenjoy=No"
			} >/tmp/.SAM_tmp/gameroulette.ini
		fi
		sam_start
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
		kiosk "Only Kiosk mode games" \
		translations "Only Translated Games" \
		homebrew "Only Homebrew" 2>"${sam_menu_file}"

	opt=$?
	menuresponse=$(<"${sam_menu_file}")
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
		find ${gamelistpathtmp} -type f -name "*_gamelist.txt" -exec rm {} \;
		readarray -t gamelists <<< "$(find "${gamelistpath}" -name "*_gamelist.txt")"

		# echo ${gamelists[@]}
		for list in "${gamelists[@]}"; do
			listfile=$(basename "${list}")
			# awk -v category="$categ" 'tolower($0) ~ category' "${list}" > "${gamelistpathtmp}/${listfile}"
			fgrep -i "${categ}" "${list}" >"${tmpfile}"
			if [ $? -eq 0 ]; then
				awk -F'/' '!seen[$NF]++' "${tmpfile}" >"${gamelistpathtmp}/${listfile}"
			fi
		done

		#corelist=$(find "${gamelistpathtmp}" -name "*_gamelist.txt" -exec basename \{} \; | cut -d '_' -f 1)
		readarray -t corelist <<< "$(find "${gamelistpathtmp}" -name "*_gamelist.txt" -exec basename \{} \; | cut -d '_' -f 1)"
		dialog --clear --no-cancel --ascii-lines \
			--backtitle "Super Attract Mode" --title "[ CATEGORY SELECTION ]" \
			--msgbox "SAM will start now and only play games from the '${categ^^}' category.\n\nOn cold reboot, SAM will get reset automatically to play all games again. " 0 0
		printf "%s\n" "${corelist[@]}" > "${corelistfile}"
		sam_start

	fi

}

function samedit_excltags() {
	excludetags="${gamelistpath}/.excludetags"
	
	function process_tag() {
		for core in "${corelist[@]}"; do
			[[ -f "${gamelistpathtmp}/${core}_gamelist.txt" ]] && rm "${gamelistpathtmp}/${core}_gamelist.txt"
			if [[ -e "${gamelistpath}/${core}_gamelist.txt" ]]; then
				grep -i "$categ" "${gamelistpath}/${core}_gamelist.txt" >>"${gamelistpath}/${core}_gamelist_exclude.txt"
			else
				grep -i "$categ" "${gamelistpath}/${core}_gamelist.txt" >"${gamelistpath}/${core}_gamelist_exclude.txt"
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
		Prototype "Prototypes"  \
		Unlicensed "Unlicensed Games" \
		Translations "Translated Games" \
		USA "USA" \
		Japan "Japan" \
		Europe "Europe" \
		'' "Reset Exclusion Lists" 2>"${sam_menu_file}" 

	opt=$?
	menuresponse=$(<"${sam_menu_file}")
	
	categ="${menuresponse}"
	
	if [ "$opt" != "0" ]; then
		sam_menu
	else
		echo " Please wait... creating exclusion lists."
		if [ -n "${categ}" ]; then
			if [ ! -s "${excludetags}" ]; then
				echo "${categ} " > "${excludetags}"
				process_tag
			else
				# Check if tag is already excluded
				if grep -qi "${categ}" "${excludetags}"; then
					dialog --clear --no-cancel --ascii-lines \
					--backtitle "Super Attract Mode" --title "[ EXCLUDE CATEGORY SELECTION ]" \
					--msgbox "${categ} has already been excluded. \n\n" 0 0
				else
					echo "${categ} " >> "${excludetags}"
					# TO DO: What if we don't have gamelists
					process_tag
				fi
			fi
		else
			for core in "${corelist[@]}"; do
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

function samedit_excltags_old() {
	# Looks better but doesn't work with gamepad
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
		"Sweden" "" OFF 2>"${sam_menu_file}"

	opt=$?
	menuresponse=$(<"${sam_menu_file}")

	if [ "$opt" != "0" ]; then
		sam_menu
	else
		echo " Please wait... creating exclusion lists."
		categ="$(echo "${menuresponse}" | tr ' ' '|')"
		if [ -n "${categ}" ]; then
			# TO DO: What if we don't have gamelists
			for core in "${corelist[@]}"; do
				[[ -f "${gamelistpathtmp}/${core}_gamelist.txt" ]] && rm "${gamelistpathtmp}/${core}_gamelist.txt"
				# Find out how to do this with grep, might be faster
				awk -v category="$categ" 'BEGIN {IGNORECASE = 1}  $0 ~ category' "${gamelistpath}/${core}_gamelist.txt" >"${gamelistpath}/${core}_gamelist_exclude.txt"
			done
		else
			for core in "${corelist[@]}"; do
				rm "${gamelistpath}/${core}_gamelist_exclude.txt"
			done
		fi
		find "${gamelistpath}" -name "*_excludelist.txt" -size 0 -exec rm '{}' \;
		samedit_taginfo
	fi

}

function sam_bgmmenu() {
	if [ "$sam_bgmmenu" == "0" ]; then
		dialog --clear --no-cancel --ascii-lines \
		--backtitle "Super Attract Mode" --title "[ SAMVIDEO, BGM & TTY2OLED ]" \
		--msgbox "SAMVIDEO\n----------------\nSAM can play back video on the MiSTer\nBy default, playback alternates with other cores. You can change more settings in MiSTer_SAM.ini\n\n\nBGM\n----------------\nWhile SAM is shuffling games, play some music.\nThis installs wizzomafizzo's BGM script to play music in SAM.\n\nWe'll drop one playlist in the music folder (80s.pls) as a default playlist. You can customize this later or to your liking by dropping mp3's or pls files in /media/fat/music folder.\n\n\nTTY2OLED\n----------------\nTTY2OLED is a hardware display for the MiSTer. ONLY ENABLE THIS IF YOU HAVE A TTY2OLED DISPLAY, or else SAM might not work correctly." 0 0
		sam_bgmmenu=1
		sam_bgmmenu
	else
		dialog --clear --ascii-lines --no-tags \
			--backtitle "Super Attract Mode" --title "[ SAMVIDEO, BGM & TTY2OLED ]" \
			--menu "Select from the following options?" 0 0 0 \
			enablesv "SAMVIDEO: Enable Video Playback for SAM" \
			disablesv "SAMVIDEO: Disable Video Playback for SAM" \
			enablecrt "SAMVIDEO: CRT output" \
			enablehdmi "SAMVIDEO: HDMI output" \
			enableyt "SAMVIDEO: Youtube Playback" \
			enablear "SAMVIDEO: Archive Playback" \
			enablebgm "BGM: Enable BGM for SAM" \
			disablebgm "BGM: Disable BGM for SAM" \
			enabletty "TTY2OLED: Enable TTY2OLED support for SAM" \
			disabletty "TTY2OLED: Disable TTY2OLED support for SAM" 2>"${sam_menu_file}" 

		opt=$?
		menuresponse=$(<"${sam_menu_file}")
		
		if [ "$opt" != "0" ]; then
			sam_menu
		else
			if [ -f /media/fat/Scripts/MiSTer_SAM.ini ]; then
				if [[ "${menuresponse,,}" == "enablebgm" ]]; then
					enablebgm
				elif [[ "${menuresponse,,}" == "disableplay" ]]; then
					sed -i '/bgmplay=/c\bgmplay="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini

				elif [[ "${menuresponse,,}" == "disablebgm" ]]; then
					echo " Uninstalling BGM, please wait..."
					bgm_stop
					[[ -e /media/fat/Scripts/bgm.sh ]] && rm /media/fat/Scripts/bgm.sh
					[[ -e /media/fat/music/bgm.ini ]] && rm /media/fat/music/bgm.ini
					rm /tmp/bgm.sock 2>/dev/null
					sed -i '/bgm.sh/d' ${userstartup}
					sed -i '/Startup BGM/d' ${userstartup}
					sed -i '/bgm=/c\bgm="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
					#echo " Done."
				elif [[ "${menuresponse,,}" == "enabletty" ]]; then
					sed -i '/ttyenable=/c\ttyenable="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
				elif [[ "${menuresponse,,}" == "disabletty" ]]; then
					sed -i '/ttyenable=/c\ttyenable="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
				elif [[ "${menuresponse,,}" == "enablesv" ]]; then
					sed -i '/samvideo=/c\samvideo="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
				elif [[ "${menuresponse,,}" == "disablesv" ]]; then
					sed -i '/samvideo=/c\samvideo="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
				elif [[ "${menuresponse,,}" == "enableyt" ]]; then
					sed -i '/samvideo_source=/c\samvideo_source="'"Youtube"'"' /media/fat/Scripts/MiSTer_SAM.ini
				elif [[ "${menuresponse,,}" == "enablear" ]]; then
					sed -i '/samvideo_source=/c\samvideo_source="'"Archive"'"' /media/fat/Scripts/MiSTer_SAM.ini
				elif [[ "${menuresponse,,}" == "enablehdmi" ]]; then
					sed -i '/samvideo_output=/c\samvideo_output="'"HDMI"'"' /media/fat/Scripts/MiSTer_SAM.ini
				elif [[ "${menuresponse,,}" == "enablecrt" ]]; then
					sed -i '/samvideo_output=/c\samvideo_output="'"CRT"'"' /media/fat/Scripts/MiSTer_SAM.ini
				fi
				dialog --clear --ascii-lines --no-cancel \
				--backtitle "Super Attract Mode" --title "[ BACKGROUND MUSIC PLAYER ]" \
				--msgbox "Changes saved!" 0 0
				sam_bgmmenu
			else
				echo "Error: MiSTer_SAM.ini not found. Please update SAM first"
			fi
		fi
	fi
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
	#sed -i '/mute=/c\mute="'"No"'"' /media/fat/Scripts/MiSTer_SAM.ini
	/media/fat/Scripts/bgm.sh &>/dev/null &
	sync
	get_samstuff Media/80s.pls /media/fat/music
	[[ ! $(grep -i "bgm" /media/fat/Scripts/MiSTer_SAM.ini) ]] && echo "bgm=Yes" >> /media/fat/Scripts/MiSTer_SAM.ini
	sed -i '/bgm=/c\bgm="'"Yes"'"' /media/fat/Scripts/MiSTer_SAM.ini
	echo " Enabling BGM debug so SAM can see what's playing.."
	sleep 5
	if grep -q '^debug = no' /media/fat/music/bgm.ini; then
		sed -i 's/^debug = no/debug = yes/' /media/fat/music/bgm.ini
		sleep 1
	fi
	#echo " All Done. Starting SAM now."
	#/media/fat/Scripts/MiSTer_SAM_on.sh start
}


# ========= MAIN =========

init_vars

read_samini

init_paths

init_data

if [ "${1,,}" != "--source-only" ]; then
	parse_cmd "${@}" # Parse command line parameters for input
fi
