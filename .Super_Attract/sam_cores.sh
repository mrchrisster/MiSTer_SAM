#!/bin/bash

# This library defines all core-specific properties.
# Each core is defined as a "module" in its own associative array.

# --- Non-Core-Specific Data Arrays ---
# These are large or special-case data sets that don't fit neatly into a module.

# PATHFILTER is populated from the INI file in read_samini
declare -gA PATHFILTER

# --- Individual Core Module Definitions ---

declare -gA CORE_AMIGA=(
    [pretty_name]="Commodore Amiga"
    [loader]="loader_amiga"
    [builder]="build_amiga_list"
    [valid_exts]="" # No extension check
    [rbf_path]="_Computer"
    [mgl_rbf]="Minimig.rbf"
    [tty_icon]="Minimig"
    [can_skip_bios]="No"
    [launch_name]="Minimig"
    [prereq_file]="${amigapath}/MegaAGS.hdf"
    [rated_list]="amiga_rated.txt"
    [blacklist]="amiga_blacklist.txt"
)

declare -gA CORE_AMIGACD32=(
    [pretty_name]="Commodore Amiga CD32"
    [loader]="loader_amigacd32"
    [builder]="build_gamelist_standard"
    [valid_exts]="chd,cue"
    [rbf_path]="_Computer"
    [mgl_rbf]="Minimig.rbf"
    [mgl_setname]="AmigaCD32"
    [tty_icon]="Minimig"
    [can_skip_bios]="Yes"
    [launch_name]="Minimig"
    [prereq_file]="/media/fat/_Console/Amiga CD32.mgl"
)

declare -gA CORE_AO486=(
    [pretty_name]="PC 486 DX-100"
    [loader]="loader_mgl"
    [builder]="build_mgl_list"
    [valid_exts]="mgl,vhd"
    [rbf_path]="_Computer"
    [mgl_rbf]="ao486.rbf"
    [tty_icon]="ao486"
    [can_skip_bios]="No"
    [launch_name]="ao486"
    [rated_list]="ao486_rated.txt"
)

declare -gA CORE_ARCADE=(
    [pretty_name]="MiSTer Arcade"
    [loader]="loader_arcade"
    [builder]="build_mra_list"
    [valid_exts]="mra"
    [rbf_path]="_Arcade"
    [tty_icon]="Arcade"
    [can_skip_bios]="No"
    [launch_name]="Arcade"
    [rated_list]="arcade_rated.txt"
    [blacklist]="arcade_blacklist.txt"
    [sv_tvc_pattern]="arcade"
)

declare -gA CORE_ATARI2600=(
    [pretty_name]="Atari 2600"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="a26"
    [rbf_path]="_Console"
    [mgl_rbf]="ATARI7800.rbf"
    [tty_icon]="ATARI2600"
    [can_skip_bios]="No"
    [launch_name]="ATARI7800"
    [sv_tvc_pattern]="atari vcs"
)

declare -gA CORE_ATARI5200=(
    [pretty_name]="Atari 5200"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="a52,car"
    [rbf_path]="_Console"
    [mgl_rbf]="ATARI5200.rbf"
    [tty_icon]="ATARI5200"
    [can_skip_bios]="No"
    [launch_name]="ATARI5200"
    [sv_tvc_pattern]="atari 5200"
)

declare -gA CORE_ATARI7800=(
    [pretty_name]="Atari 7800"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="a78"
    [rbf_path]="_Console"
    [mgl_rbf]="ATARI7800.rbf"
    [tty_icon]="ATARI7800"
    [can_skip_bios]="No"
    [launch_name]="ATARI7800"
    [sv_tvc_pattern]="atari 7800"
)

declare -gA CORE_ATARILYNX=(
    [pretty_name]="Atari Lynx"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="lnx"
    [rbf_path]="_Console"
    [mgl_rbf]="AtariLynx.rbf"
    [tty_icon]="AtariLynx"
    [can_skip_bios]="No"
    [launch_name]="AtariLynx"
    [sv_tvc_pattern]="atari lynx"
)

declare -gA CORE_C64=(
    [pretty_name]="Commodore 64"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="crt,prg"
    [rbf_path]="_Computer"
    [mgl_rbf]="C64.rbf"
    [tty_icon]="C64"
    [can_skip_bios]="No"
    [launch_name]="C64"
)

declare -gA CORE_CDI=(
    [pretty_name]="Philips CD-i"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="chd,cue"
    [rbf_path]="_Console"
    [mgl_rbf]="CDi.rbf"
    [tty_icon]="CD-i"
    [can_skip_bios]="No"
    [launch_name]="CDi"
)

declare -gA CORE_COCO2=(
    [pretty_name]="TRS-80 Color Computer 2"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="ccc"
    [rbf_path]="_Computer"
    [mgl_rbf]="CoCo2.rbf"
    [tty_icon]="CoCo2"
    [can_skip_bios]="No"
    [launch_name]="CoCo2"
)

declare -gA CORE_FDS=(
    [pretty_name]="Nintendo Disk System"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="fds"
    [rbf_path]="_Console"
    [mgl_rbf]="NES.rbf"
    [tty_icon]="fds"
    [can_skip_bios]="Yes"
    [launch_name]="NES"
    [rated_list]="fds_rated.txt"
    [blacklist]="fds_blacklist.txt"
)

declare -gA CORE_GB=(
    [pretty_name]="Nintendo Game Boy"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="gb"
    [rbf_path]="_Console"
    [mgl_rbf]="GAMEBOY.rbf"
    [tty_icon]="GAMEBOY"
    [can_skip_bios]="No"
    [launch_name]="GAMEBOY"
    [rated_list]="gb_rated.txt"
    [sv_tvc_pattern]="gb\|game boy"
)

declare -gA CORE_GBC=(
    [pretty_name]="Nintendo Game Boy Color"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="gbc"
    [rbf_path]="_Console"
    [mgl_rbf]="GAMEBOY.rbf"
    [mgl_setname]="GBC"
    [tty_icon]="GAMEBOY"
    [can_skip_bios]="No"
    [launch_name]="GAMEBOY"
    [rated_list]="gbc_rated.txt"
    [sv_tvc_pattern]="gb\|game boy"
)

declare -gA CORE_GBA=(
    [pretty_name]="Nintendo Game Boy Advance"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="gba"
    [rbf_path]="_Console"
    [mgl_rbf]="GBA.rbf"
    [tty_icon]="GBA"
    [can_skip_bios]="No"
    [launch_name]="GBA"
    [rated_list]="gba_rated.txt"
    [blacklist]="gba_blacklist.txt"
)

declare -gA CORE_GENESIS=(
    [pretty_name]="Sega Genesis / Megadrive"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="md,gen"
    [rbf_path]="_Console"
    [mgl_rbf]="MegaDrive.rbf"
    [tty_icon]="Genesis"
    [can_skip_bios]="No"
    [launch_name]="MEGADRIVE"
    [rated_list]="genesis_rated.txt"
    [blacklist]="genesis_blacklist.txt"
    [sv_tvc_pattern]="genesis"
)

declare -gA CORE_GG=(
    [pretty_name]="Sega Game Gear"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="gg"
    [rbf_path]="_Console"
    [mgl_rbf]="SMS.rbf"
    [mgl_setname]="GameGear"
    [tty_icon]="gamegear"
    [can_skip_bios]="No"
    [launch_name]="SMS"
    [rated_list]="gg_rated.txt"
    [sv_tvc_pattern]="sega game"
)

declare -gA CORE_JAGUAR=(
    [pretty_name]="Atari Jaguar"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="j64,rom,bin,jag"
    [rbf_path]="_Console"
    [mgl_rbf]="Jaguar.rbf"
    [tty_icon]="Jaguar"
    [can_skip_bios]="No"
    [launch_name]="Jaguar"
)

declare -gA CORE_MEGACD=(
    [pretty_name]="Sega CD / Mega CD"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="chd,cue"
    [rbf_path]="_Console"
    [mgl_rbf]="MegaCD.rbf"
    [tty_icon]="MegaCD"
    [can_skip_bios]="Yes"
    [launch_name]="MegaCD"
    [rated_list]="megacd_rated.txt"
    [blacklist]="megacd_blacklist.txt"
    [sv_tvc_pattern]="megacd"
)

declare -gA CORE_N64=(
    [pretty_name]="Nintendo N64"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="n64,z64"
    [rbf_path]="_Console"
    [mgl_rbf]="N64.rbf"
    [tty_icon]="N64"
    [can_skip_bios]="No"
    [launch_name]="N64"
    [rated_list]="n64_rated.txt"
    [rated_mature_list]="n64_mature.txt"
    [blacklist]="n64_blacklist.txt"
    [sv_tvc_pattern]="n64-\|n64"
)

declare -gA CORE_NEOGEO=(
    [pretty_name]="SNK NeoGeo"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="neo"
    [rbf_path]="_Console"
    [mgl_rbf]="NEOGEO.rbf"
    [tty_icon]="NEOGEO"
    [can_skip_bios]="No"
    [launch_name]="NEOGEO"
    [rated_list]="neogeo_rated.txt"
    [blacklist]="neogeo_blacklist.txt"
)

declare -gA CORE_NEOGEOCD=(
    [pretty_name]="SNK NeoGeo CD"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="cue,chd"
    [rbf_path]="_Console"
    [mgl_rbf]="NEOGEO.rbf"
    [tty_icon]="NEOGEO"
    [can_skip_bios]="Yes"
    [launch_name]="NEOGEO"
)

declare -gA CORE_NES=(
    [pretty_name]="Nintendo Entertainment System"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="nes"
    [rbf_path]="_Console"
    [mgl_rbf]="NES.rbf"
    [tty_icon]="NES"
    [can_skip_bios]="No"
    [launch_name]="NES"
    [rated_list]="nes_rated.txt"
    [blacklist]="nes_blacklist.txt"
    [sv_tvc_pattern]="^nes-\| nes"
)

declare -gA CORE_S32X=(
    [pretty_name]="Sega 32x"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="32x"
    [rbf_path]="_Console"
    [mgl_rbf]="S32X.rbf"
    [tty_icon]="S32X"
    [can_skip_bios]="No"
    [launch_name]="S32X"
    [blacklist]="s32x_blacklist.txt"
    [sv_tvc_pattern]="sega 32x"
)

declare -gA CORE_SATURN=(
    [pretty_name]="Sega Saturn"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="cue,chd"
    [rbf_path]="_Console"
    [mgl_rbf]="SATURN.rbf"
    [tty_icon]="SATURN"
    [can_skip_bios]="Yes"
    [launch_name]="SATURN"
    [rated_mature_list]="saturn_mature.txt"
    [sv_tvc_pattern]="sega saturn"
)

declare -gA CORE_SGB=(
    [pretty_name]="Super Gameboy"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="gb,gbc"
    [rbf_path]="_Console"
    [mgl_rbf]="SGB.rbf"
    [tty_icon]="SGB"
    [can_skip_bios]="No"
    [launch_name]="SGB"
    [sv_tvc_pattern]="super game boy\|gb-super game boy\|snes-super game boy"
)

declare -gA CORE_SMS=(
    [pretty_name]="Sega Master System"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="sms,sg"
    [rbf_path]="_Console"
    [mgl_rbf]="SMS.rbf"
    [tty_icon]="SMS"
    [can_skip_bios]="No"
    [launch_name]="SMS"
    [rated_list]="sms_rated.txt"
    [blacklist]="sms_blacklist.txt"
    [sv_tvc_pattern]="sega master"
)

declare -gA CORE_SNES=(
    [pretty_name]="Super Nintendo"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="sfc,smc"
    [rbf_path]="_Console"
    [mgl_rbf]="SNES.rbf"
    [tty_icon]="SNES"
    [can_skip_bios]="No"
    [launch_name]="SNES"
    [rated_list]="snes_rated.txt"
    [blacklist]="snes_blacklist.txt"
    [sv_tvc_pattern]="snes"
)

declare -gA CORE_STV=(
    [pretty_name]="Sega Titan Video"
    [loader]="loader_arcade" # Shares arcade loader
    [builder]="build_mra_list"
    [valid_exts]="mra"
    [rbf_path]="_Arcade"
    [tty_icon]="S-TV"
    [can_skip_bios]="No"
    [launch_name]="S-TV"
)

declare -gA CORE_TGFX16=(
    [pretty_name]="NEC TurboGrafx-16"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="pce,sgx"
    [rbf_path]="_Console"
    [mgl_rbf]="TurboGrafx16.rbf"
    [tty_icon]="TGFX16"
    [can_skip_bios]="No"
    [launch_name]="TGFX16"
    [rated_list]="tgfx16_rated.txt"
    [blacklist]="tgfx16_blacklist.txt"
    [sv_tvc_pattern]="turboduo\|turbografx-16"
)

declare -gA CORE_TGFX16CD=(
    [pretty_name]="NEC TurboGrafx-16 CD"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="chd,cue"
    [rbf_path]="_Console"
    [mgl_rbf]="TurboGrafx16.rbf"
    [tty_icon]="TGFX16"
    [can_skip_bios]="Yes"
    [launch_name]="TGFX16"
    [rated_list]="tgfx16cd_rated.txt"
    [rated_mature_list]="tgfx16cd_mature.txt"
    [blacklist]="tgfx16cd_blacklist.txt"
    [sv_tvc_pattern]="turboduo"
)

declare -gA CORE_PSX=(
    [pretty_name]="Sony Playstation"
    [loader]="loader_standard"
    [builder]="build_gamelist_standard"
    [valid_exts]="chd,cue,exe"
    [rbf_path]="_Console"
    [mgl_rbf]="PSX.rbf"
    [tty_icon]="PSX"
    [can_skip_bios]="No"
    [launch_name]="PSX"
    [rated_list]="psx_rated.txt"
    [blacklist]="psx_blacklist.txt"
    [sv_tvc_pattern]="psx\|playstation"
)

declare -gA CORE_X68K=(
    [pretty_name]="Sharp X68000"
    [loader]="loader_mgl"
    [builder]="build_mgl_list"
    [valid_exts]="mgl"
    [rbf_path]="_Computer"
    [mgl_rbf]="X68000.rbf"
    [tty_icon]="X68000"
    [can_skip_bios]="No"
    [launch_name]="X68000"
)

# --- Master Core Map ---
# This maps the core name to the name of its config array.
declare -gA CORES=(
    [amiga]="CORE_AMIGA"
    [amigacd32]="CORE_AMIGACD32"
    [ao486]="CORE_AO486"
    [arcade]="CORE_ARCADE"
    [atari2600]="CORE_ATARI2600"
    [atari5200]="CORE_ATARI5200"
    [atari7800]="CORE_ATARI7800"
    [atarilynx]="CORE_ATARILYNX"
    [c64]="CORE_C64"
    [cdi]="CORE_CDI"
    [coco2]="CORE_COCO2"
    [fds]="CORE_FDS"
    [gb]="CORE_GB"
    [gbc]="CORE_GBC"
    [gba]="CORE_GBA"
    [genesis]="CORE_GENESIS"
    [gg]="CORE_GG"
    [jaguar]="CORE_JAGUAR"
    [megacd]="CORE_MEGACD"
    [n64]="CORE_N64"
    [neogeo]="CORE_NEOGEO"
    [neogeocd]="CORE_NEOGEOCD"
    [nes]="CORE_NES"
    [s32x]="CORE_S32X"
    [saturn]="CORE_SATURN"
    [sgb]="CORE_SGB"
    [sms]="CORE_SMS"
    [snes]="CORE_SNES"
    [stv]="CORE_STV"
    [tgfx16]="CORE_TGFX16"
    [tgfx16cd]="CORE_TGFX16CD"
    [psx]="CORE_PSX"
    [x68k]="CORE_X68K"
)
		
		
# NEOGEO to long name mappings English
declare -gA NEOGEO_PRETTY_ENGLISH=(
	["3countb"]="3 Count Bout" ["2020bb"]="2020 Super Baseball" ["alpham2"]="Alpha Mission II"
	["androdun"]="Andro Dunos" ["aodk"]="Aggressors of Dark Kombat" ["aof"]="Art of Fighting"
	["aof2"]="Art of Fighting 2" ["aof3"]="Art of Fighting 3" ["bakatono"]="Bakatonosama Mahjong Manyuuki"
	["bangbead"]="Bang Bead" ["bjourney"]="Blue's Journey" ["blazstar"]="Blazing Star"
	["breakers"]="Breakers" ["breakrev"]="Breakers Revenge" ["burningf"]="Burning Fight"
	["bstars"]="Baseball Stars Professional" ["bstars2"]="Baseball Stars 2" ["cabalng"]="Cabal"
	["columnsn"]="Columns" ["crsword"]="Crossed Swords" ["ctomaday"]="Captain Tomaday"
	["cyberlip"]="Cyber-Lip" ["diggerma"]="Digger Man" ["doubledr"]="Double Dragon"
	["eightman"]="Eight Man" ["fatfury1"]="Fatal Fury" ["fatfury2"]="Fatal Fury 2"
	["fatfury3"]="Fatal Fury 3" ["fatfursp"]="Fatal Fury Special" ["fbfrenzy"]="Football Frenzy"
	["fightfev"]="Fight Fever" ["flipshot"]="Battle Flip Shot" ["galaxyfg"]="Galaxy Fight"
	["ganryu"]="Ganryu" ["garou"]="Garou: Mark of the Wolves" ["ghostlop"]="Ghostlop"
	["goalx3"]="Goal! Goal! Goal!" ["gowcaizr"]="Voltage Fighter Gowcaizer" ["gpilots"]="Ghost Pilots"
	["gururin"]="Gururin" ["ironclad"]="Ironclad" ["irrmaze"]="The Irritating Maze"
	["janshin"]="Janshin Densetsu" ["joyjoy"]="Puzzled" ["kabukikl"]="Kabuki Klash"
	["karnovr"]="Karnov's Revenge" ["kizuna"]="Kizuna Encounter" ["kof94"]="The King of Fighters '94"
	["kof95"]="The King of Fighters '95" ["kof96"]="The King of Fighters '96" ["kof97"]="The King of Fighters '97"
	["kof98"]="The King of Fighters '98" ["kof99"]="The King of Fighters '99" ["kof2000"]="The King of Fighters 2000"
	["kof2001"]="The King of Fighters 2001" ["kof2002"]="The King of Fighters 2002" ["kof2003"]="The King of Fighters 2003"
	["kotm"]="King of the Monsters" ["kotm2"]="King of the Monsters 2" ["lastblad"]="The Last Blade"
	["lastbld2"]="The Last Blade 2" ["lasthope"]="Last Hope" ["lbowling"]="League Bowling"
	["legendos"]="Legend of Success Joe" ["lresort"]="Last Resort" ["magdrop2"]="Magical Drop II"
	["magdrop3"]="Magical Drop III" ["maglord"]="Magician Lord" ["mahretsu"]="Mahjong Kyo Retsuden"
	["matrim"]="Power Instinct Matrimelee" ["miexchng"]="Money Puzzle Exchanger" ["minasan"]="Minasan no Okagesamadesu!"
	["moshougi"]="Shougi no Tatsujin" ["mslug"]="Metal Slug" ["mslug2"]="Metal Slug 2"
	["mslug3"]="Metal Slug 3" ["mslug4"]="Metal Slug 4" ["mslug5"]="Metal Slug 5"
	["mslugx"]="Metal Slug X" ["mutnat"]="Mutation Nation" ["nam1975"]="NAM-1975"
	["ncombat"]="Ninja Combat" ["ncommand"]="Ninja Commando" ["neobombe"]="Neo Bomberman"
	["neocup98"]="Neo-Geo Cup '98" ["neodrift"]="Neo Drift Out" ["neomrdo"]="Neo Mr. Do!"
	["neothund"]="Neo Thunder" ["ninjamas"]="Ninja Master's" ["nitd"]="Nightmare in the Dark"
	["overtop"]="OverTop" ["panicbom"]="Panic Bomber" ["pbobblen"]="Puzzle Bobble"
	["pbobbl2n"]="Puzzle Bobble 2" ["pgoal"]="Pleasure Goal" ["pnyaa"]="Pochi and Nyaa"
	["popbounc"]="Pop 'n Bounce" ["preisle2"]="Prehistoric Isle 2" ["pspikes2"]="Power Spikes II"
	["pulstar"]="Pulstar" ["puzzldpr"]="Puzzle De Pon! R!" ["puzzledp"]="Puzzle De Pon!"
	["quizdai2"]="Quiz Meitantei Neo & Geo" ["quizdais"]="Quiz Daisousa Sen" ["quizkof"]="Quiz King of Fighters"
	["ragnagrd"]="Ragnagard" ["rbff1"]="Real Bout Fatal Fury" ["rbff2"]="Real Bout Fatal Fury 2"
	["rbffspec"]="Real Bout Fatal Fury Special" ["ridhero"]="Riding Hero" ["roboarmy"]="Robo Army"
	["rotd"]="Rage of the Dragons" ["s1945p"]="Strikers 1945 Plus" ["samsho"]="Samurai Shodown"
	["samsho2"]="Samurai Shodown II" ["samsho3"]="Samurai Shodown III" ["samsho4"]="Samurai Shodown IV"
	["samsho5"]="Samurai Shodown V" ["samsh5sp"]="Samurai Shodown V Special" ["savagere"]="Savage Reign"
	["scbrawl"]="Soccer Brawl" ["sdodgeb"]="Super Dodge Ball" ["sengoku"]="Sengoku"
	["sengoku2"]="Sengoku 2" ["sengoku3"]="Sengoku 3" ["shocktro"]="Shock Troopers"
	["shocktr2"]="Shock Troopers: 2nd Squad" ["sonicwi2"]="Aero Fighters 2" ["sonicwi3"]="Aero Fighters 3"
	["spinmast"]="Spinmaster" ["ssideki"]="Super Sidekicks" ["ssideki2"]="Super Sidekicks 2"
	["ssideki3"]="Super Sidekicks 3" ["ssideki4"]="The Ultimate 11" ["stakwin"]="Stakes Winner"
	["stakwin2"]="Stakes Winner 2" ["strhoop"]="Street Hoop" ["superspy"]="The Super Spy"
	["svc"]="SNK vs. Capcom: SVC Chaos" ["teot"]="The Eye of Typhoon" ["tophuntr"]="Top Hunter"
	["tpgolf"]="Top Player's Golf" ["trally"]="Thrash Rally" ["turfmast"]="Neo Turf Masters"
	["twinspri"]="Twinkle Star Sprites" ["tws96"]="Tecmo World Soccer '96" ["viewpoin"]="Viewpoint"
	["wakuwak7"]="Waku Waku 7" ["wh1"]="World Heroes" ["wh2"]="World Heroes 2"
	["wh2j"]="World Heroes 2 Jet" ["whp"]="World Heroes Perfect" ["wjammers"]="Windjammers"
	["zedblade"]="Zed Blade" ["zintrckb"]="ZinTricK" ["zupapa"]="Zupapa!"
)

