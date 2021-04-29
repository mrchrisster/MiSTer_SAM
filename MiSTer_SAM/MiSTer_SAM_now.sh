#!/bin/bash

# ======== INI VARIABLES ========
# Change these in the INI file
samtimeout=300
gametimer=120
menuonly="No"
listenmouse="Yes"
listenkeyboard="Yes"
listenjoy="Yes"
corelist="arcade,gba,genesis,megacd,neogeo,nes,snes,tgfx16,tgfx16cd"
arcadepath="/media/fat/_arcade"
gbapath="/media/fat/games/GBA"
genesispath="/media/fat/games/Genesis"
megacdpath="/media/fat/games/MegaCD"
neogeopath="/media/fat/games/NeoGeo"
nespath="/media/fat/games/NES"
snespath="/media/fat/games/SNES"
tgfx16path="/media/fat/games/TGFX16"
tgfx16cdpath="/media/fat/games/TGFX16-CD"
usezip="Yes"
disablebootrom="Yes"
mrapath="/media/fat/_Arcade"
orientation=All
mbcpath="/media/fat/Scripts/.MiSTer_SAM/mbc"
partunpath="/media/fat/Scripts/.MiSTer_SAM/partun"
mrsampath="/media/fat/Scripts/.MiSTer_SAM"
misterpath="/media/fat"
mrapathvert="/media/fat/_Arcade/_Organized/_6 Rotation/_Vertical CW 90 Deg" 
mrapathhoriz="/media/fat/_Arcade/_Organized/_6 Rotation/_Horizontal"

# ======== DEBUG VARIABLES ========
startupsleep="Yes"
samquiet="Yes"


# Read INI
if [ -f "${misterpath}/Scripts/MiSTer_SAM.ini" ]; then
	. "${misterpath}/Scripts/MiSTer_SAM.ini"
	IFS=$'\n'
fi

# Remove trailing slash from paths
for var in mrsampath misterpath; do
	declare -g ${var}="${!var%/}"
done

#======== Launch MiSTer SAM ========
"${mrsampath}/MiSTer_SAM.sh" "$@" &
exit 0
