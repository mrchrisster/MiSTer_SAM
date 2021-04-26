#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/media/fat/linux:/media/fat/Scripts:/media/fat/Scripts/.MiSTer_SAM:.

# ======== INI VARIABLES ========
# Change these in the INI file
samtimeout=300
gametimer=120
menuonly="Yes"
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
mraexclude="
Example Bad Game.mra
Another Bad Game.mra
"

# ======== DEBUG VARIABLES ========
startupsleep="Yes"
samquiet="Yes"


# ======== INTERNAL VARIABLES ========
declare -i coreretries=3
declare -i romloadfails=0
mralist="/tmp/.SAMmras"

# ======== CORE CONFIG ========
init_data()
{
	# Core to long name mappings
	declare -gA CORE_PRETTY=( \
		["arcade"]="MiSTer Arcade" \
		["gba"]="Nintendo Game Boy Advance" \
		["genesis"]="Sega Genesis / Megadrive" \
		["megacd"]="Sega CD / Mega CD" \
		["neogeo"]="SNK NeoGeo" \
		["nes"]="Nintendo Entertainment System" \
		["snes"]="Super Nintendo Entertainment System" \
		["tgfx16"]="NEC TurboGrafx-16 / PC Engine" \
		["tgfx16cd"]="NEC TurboGrafx-16 CD / PC Engine CD" \
		)
	
	# Core to file extension mappings
	declare -gA CORE_EXT=( \
		["arcade"]="mra" \
		["gba"]="gba" \
		["genesis"]="md" \
		["megacd"]="chd" \
		["neogeo"]="neo" \
		["nes"]="nes" \
		["snes"]="sfc" \
		["tgfx16"]="pce" \
		["tgfx16cd"]="chd" \
		)
	
	# Core to path mappings
	declare -gA CORE_PATH=( \
		["arcade"]="${arcadepath}" \
		["gba"]="${gbapath}" \
		["genesis"]="${genesispath}" \
		["megacd"]="${megacdpath}" \
		["neogeo"]="${neogeopath}" \
		["nes"]="${nespath}" \
		["snes"]="${snespath}" \
		["tgfx16"]="${tgfx16path}" \
		["tgfx16cd"]="${tgfx16cdpath}" \
		)
	
	# Can this core use ZIPped ROMs
	declare -gA CORE_ZIPPED=( \
		["arcade"]="No" \
		["gba"]="Yes" \
		["genesis"]="Yes" \
		["megacd"]="No" \
		["neogeo"]="Yes" \
		["nes"]="Yes" \
		["snes"]="Yes" \
		["tgfx16"]="Yes" \
		["tgfx16cd"]="No" \
		)
}


# ======== BASIC FUNCTIONS ========
there_can_be_only_one() # there_can_be_only_one PID Process
{
	# If another attract process is running kill it
	# This can happen if the script is started multiple times
	if [ ! -z "$(pidof -o ${1} $(basename ${2}))" ]; then
		echo ""
		echo "Removing other running instances of $(basename ${2})..."
		kill -9 $(pidof -o ${1} $(basename ${2})) &>/dev/null
	fi
}

parse_cmdline()
{
	for arg in "${@}"; do
		case ${arg,,} in
			arcade)
				echo "${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="Arcade"
				;;
			gba)
				echo "${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="GBA"
				;;
			genesis)
				echo "${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="Genesis"
				;;
			megacd)
				echo "${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="MegaCD"
				;;
			neogeo)
				echo "${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="NeoGeo"
				;;
			nes)
				echo "${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="NES"
				;;
			snes)
				echo "${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="SNES"
				;;
			tgfx16cd)
				echo "${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="TGFX16CD"
				;;
			tgfx16)
				echo "${CORE_PRETTY[${arg,,}]} selected!"
				declare -g corelist="TGFX16"
				;;
			next) # Load one random core and exit
				gonext="next_core"
				;;
		esac
	done

	# If we need to go somewhere special - do it here
	if [ ! -z "${gonext}" ]; then
		${gonext}
		exit 0
	fi
}


# ======== MISTER CORE FUNCTIONS ========
loop_core()
{
	while :; do
		counter=${gametimer}
		next_core
		while [ ${counter} -gt 0 ]; do
			sleep 1
			((counter--))
			
			if [ -s /tmp/.SAM_Mouse_Activity ]; then
				if [ "${listenmouse,,}" == "yes" ]; then
					echo "Mouse activity detected!"
					exit
				else
					echo "Mouse activity ignored!"
					echo "" |>/tmp/.SAM_Mouse_Activity
				fi
			fi
			
			if [ -s /tmp/.SAM_Keyboard_Activity ]; then
				if [ "${listenkeyboard,,}" == "yes" ]; then
					echo "Keyboard activity detected!"
					exit
				else
					echo "Keyboard activity ignored!"
					echo "" |>/tmp/.SAM_Keyboard_Activity
				fi
			fi
			
			if [ -s /tmp/.SAM_Joy_Activity ]; then
				if [ "${listenjoy,,}" == "yes" ]; then
					echo "Controller activity detected!"
					exit
				else
					echo "Controller activity ignored!"
					echo "" |>/tmp/.SAM_Joy_Activity
				fi
			fi
		done
	done
}

next_core() # next_core (nextcore)
{
	if [ -z "${corelist[@]//[[:blank:]]/}" ]; then
		echo "ERROR: FATAL - List of cores is empty. Nothing to do!"
		exit 1
	fi

	if [ -z "${1}" ]; then
		nextcore="$(echo ${corelist}| xargs shuf -n1 -e)"
	else
		nextcore="${1}"
	fi

	if [ "${nextcore,,}" == "arcade" ]; then
		load_core_arcade
		return
	elif [ "${CORE_ZIPPED[${nextcore,,}],,}" == "yes" ]; then
		# If not ZIP in game directory OR if ignoring ZIP
		if [ -z "$(find ${CORE_PATH[${nextcore,,}]} -maxdepth 1 -type f \( -iname "*.zip" \))" ] || [ "${usezip,,}" == "no" ]; then
			rompath="$(find ${CORE_PATH[${nextcore,,}]} -type d \( -name *BIOS* -o -name *Eu* -o -name *Other* -o -name *VGM* -o -name *NES2PCE* -o -name *FDS* -o -name *SPC* -o -name Unsupported \) -prune -false -o -name *.${CORE_EXT[${nextcore,,}]} | shuf -n 1)"
			romname=$(basename "${rompath}")
		else # Use ZIP
			romname=$("${partunpath}" "$(find ${CORE_PATH[${nextcore,,}]} -maxdepth 1 -type f \( -iname "*.zip" \) | shuf -n 1)" -i -r -f ${CORE_EXT[${nextcore,,}]} --rename /tmp/Extracted.${CORE_EXT[${nextcore,,}]})
			# Partun returns the actual rom name to us so we need a special case here
			romname=$(basename "${romname}")
			rompath="/tmp/Extracted.${CORE_EXT[${nextcore,,}]}"
		fi
	else
		rompath="$(find ${CORE_PATH[${nextcore,,}]} -type f \( -iname *.${CORE_EXT[${nextcore,,}]} \) | shuf -n 1)"
		romname=$(basename "${rompath}")
	fi

	if [ -z "${rompath}" ]; then
		core_error "${nextcore}" "${rompath}"
	else
		load_core "${nextcore}" "${rompath}" "${romname%.*}" "${1}"
	fi
}

load_core() 	# load_core core /path/to/rom name_of_rom (countdown)
{	
	echo -n "Next up on the "
	echo -ne "\e[4m${CORE_PRETTY[${1,,}]}\e[0m: "
	echo -e "\e[1m${3}\e[0m"
	echo "${3} (${1})" > /tmp/SAM_Game.txt

	if [ "${4}" == "countdown" ]; then
		echo "Loading in..."
		for i in {5..1}; do
			echo "${i} seconds"
			sleep 1
		done
	fi

	"${mbcpath}" load_rom ${1^^} "${2}" > /dev/null 2>&1
}

core_error() # core_error core /path/to/ROM
{
	if [ ${romloadfails} -lt ${coreretries} ]; then
		declare -g romloadfails=$((romloadfails+1))
		echo "ERROR: Failed ${romloadfails} times. No valid game found for core: ${1} rom: ${2}"
		echo "Trying to find another rom..."
		next_core ${1}
	else
		echo "ERROR: Failed ${romloadfails} times. No valid game found for core: ${1} rom: ${2}"
		echo "ERROR: Core ${1} is blacklisted!"
		declare -g corelist=("${corelist[@]/${1}}")
		echo "List of cores is now: ${corelist[@]}"
		declare -g romloadfails=0
		next_core
	fi	
}

disable_bootrom()
{
	if [ "${disablebootrom}" == "Yes" ]; then
		if [ -d "${misterpath}/Bootrom" ]; then
			mount --bind /mnt "${misterpath}/Bootrom"
		fi
		if [ -f "${misterpath}/Games/NES/boot0.rom" ]; then
			touch /tmp/brfake
			mount --bind /tmp/brfake ${misterpath}/Games/NES/boot0.rom
		fi
		if [ -f "${misterpath}/Games/NES/boot1.rom" ]; then
			touch /tmp/brfake
			mount --bind /tmp/brfake ${misterpath}/Games/NES/boot1.rom
		fi
		if [ -f "${misterpath}/Games/NES/boot2.rom" ]; then
			touch /tmp/brfake
			mount --bind /tmp/brfake ${misterpath}/Games/NES/boot2.rom
		fi
		if [ -f "${misterpath}/Games/NES/boot3.rom" ]; then
			touch /tmp/brfake
			mount --bind /tmp/brfake ${misterpath}/Games/NES/boot3.rom
		fi
	fi
}


# ======== ARCADE MODE ========
build_mralist()
{
	# If no MRAs found - suicide!
	find "${mrapath}" -maxdepth 1 -type f \( -iname "*.mra" \) &>/dev/null
	if [ ! ${?} == 0 ]; then
		echo "The path ${mrapath} contains no MRA files!"
		loop_core
	fi
	
	# This prints the list of MRA files in a path,
	# Cuts the string to just the file name,
	# Then saves it to the mralist file.
	
	# If there is an empty exclude list ignore it
	# Otherwise use it to filter the list
	if [ ${#mraexclude[@]} -eq 0 ]; then
		find "${mrapath}" -maxdepth 1 -type f \( -iname "*.mra" \) | cut -c $(( $(echo ${#mrapath}) + 2 ))- >"${mralist}"
	else
		find "${mrapath}" -maxdepth 1 -type f \( -iname "*.mra" \) | cut -c $(( $(echo ${#mrapath}) + 2 ))- | grep -vFf <(printf '%s\n' ${mraexclude[@]})>"${mralist}"
	fi
}

load_core_arcade()
{
	# Get a random game from the list
	mra="$(shuf -n 1 ${mralist})"

	# If the mra variable is valid this is skipped, but if not we try 10 times
	# Partially protects against typos from manual editing and strange character parsing problems
	for i in {1..10}; do
		if [ ! -f "${mrapath}/${mra}" ]; then
			mra=$(shuf -n 1 ${mralist})
		fi
	done

	# If the MRA is still not valid something is wrong - suicide
	if [ ! -f "${mrapath}/${mra}" ]; then
		echo "There is no valid file at ${mrapath}/${mra}!"
		return
	fi

	echo -n "Next up at the "
	echo -ne "\e[4m${CORE_PRETTY[${nextcore,,}]}\e[0m: "
	echo -e "\e[1m$(echo $(basename "${mra}") | sed -e 's/\.[^.]*$//')\e[0m"
	echo "$(echo $(basename "${mra}") | sed -e 's/\.[^.]*$//') (${nextcore})" > /tmp/SAM_Game.txt

	if [ "${1}" == "countdown" ]; then
		echo "Loading quarters in..."
		for i in {5..1}; do
			echo "${i} seconds"
			sleep 1
		done
	fi

  # Tell MiSTer to load the next MRA
  echo "load_core ${mrapath}/${mra}" > /dev/MiSTer_cmd
}


# ======== MAIN ========
echo "Starting up, please wait a minute..."

# Parse INI
basepath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if [ -f "${misterpath}/Scripts/MiSTer_SAM.ini" ]; then
	. "${misterpath}/Scripts/MiSTer_SAM.ini"
	IFS=$'\n'
fi

# Remove trailing slash from paths
for var in mrsampath mrapath mrapathvert mrapathhoriz arcadepath gbapath genesispath megacdpath neogeopath nespath snespath tgfx16path tgfx16cdpath; do
	declare -g ${var}="${!var%/}"
done


# Set mrapath based on orientation
if [ "${orientation,,}" == "vertical" ]; then
	mrapath="${mrapathvert}"
elif [ "${orientation,,}" == "horizontal" ]; then
	mrapath="${mrapathhoriz}"
fi

# Setup corelist
corelist="$(echo ${corelist} | tr ',' ' ')"

if [ "${samquiet,,}" == "no" ]; then
	echo "basepath: ${basepath}"
	echo "mrsampath: ${mrsampath}"
	echo "misterpath: ${misterpath}"
	echo "corelist: ${corelist}"
	echo "gametimer: ${gametimer}"
	echo "mbcpath: ${mbcpath}"
	echo "partunpath: ${partunpath}"
	echo "mralist: ${mralist}"
	echo "mrapath: ${mrapath}"
	echo "mrapathvert: ${mrapathvert}"
	echo "mrapathhoriz: ${mrapathhoriz}"
	echo "orientation: ${orientation}"
	echo "usezip: ${usezip}"
	echo "disablebootrom: ${disablebootrom}"
	echo "saminterrupt: ${saminterrupt}"
	echo "arcadepath: ${arcadepath}"
	echo "gbapath: ${gbapath}"
	echo "genesispath: ${genesispath}"
	echo "megacdpath: ${megacdpath}"
	echo "neogeopath: ${neogeopath}"
	echo "nespath: ${nespath}"
	echo "snespath: ${snespath}"
	echo "tgfx16path: ${tgfx16path}"
	echo "tgfx16cdpath: ${tgfx16cdpath}"
fi	

disable_bootrom							# Disable Bootrom until Reboot 
build_mralist								# Generate list of MRAs
init_data										# Setup data arrays
parse_cmdline ${@}					# Parse command line parameters for input
there_can_be_only_one "$$" "${0}"	# Terminate any other running Attract Mode processes
echo "Let Mortal Kombat begin!"
loop_core										# Let Mortal Kombat begin!

exit
