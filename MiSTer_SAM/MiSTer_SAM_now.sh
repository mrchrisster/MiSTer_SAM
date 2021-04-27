#!/bin/bash

#======== INI VARIABLES ========
# Change these in the INI file

#======== GLOBAL VARIABLES =========
declare -g mrsampath="/media/fat/Scripts/.MiSTer_SAM"
declare -g misterpath="/media/fat"

#======== DEBUG VARIABLES ========
samquiet="Yes"

#======== LOCAL VARIABLES ========


#========= PARSE INI =========
# Read INI
if [ -f "${misterpath}/Scripts/MiSTer_SAM.ini" ]; then
	. "${misterpath}/Scripts/MiSTer_SAM.ini"
	IFS=$'\n'
fi

# Remove trailing slash from paths
for var in mrsampath misterpath mrapathvert mrapathhoriz arcadepath gbapath genesispath megacdpath neogeopath nespath snespath tgfx16path tgfx16cdpath; do
	declare -g ${var}="${!var%/}"
done


#======== DEBUG OUTPUT =========
if [ "${samquiet,,}" == "no" ]; then
	echo "********************************************************************************"
	#======== GLOBAL VARIABLES =========
	echo "mrsampath: ${mrsampath}"
	echo "misterpath: ${misterpath}"
	#======== LOCAL VARIABLES ========
	echo "********************************************************************************"
fi

#======== NUCLEAR LAUNCH DETECTED ========
"${mrsampath}/MiSTer_SAM.sh" ${@} &
exit 0
