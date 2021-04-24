#!/bin/bash

#======== DEFAULT VARIABLES ========
misterpath="/media/fat"
mrsampath="/media/fat/Scripts/.MiSTer_SAM"

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
echo "misterpath: ${misterpath}"
echo "mrsampath: ${mrsampath}"

"${mrsampath}/MiSTer_SAM.sh" &
exit 0
