#!/bin/bash

# Read the contents of the INI file
declare -g ini_file="/media/fat/MiSTer.ini"
declare -g ini_contents=$(cat "$ini_file")
declare -g v640240="http://ia902700.us.archive.org/3/items/640x240_videogame_commercials/"
declare -g v640480="http://ia902700.us.archive.org/3/items/640x480_videogame_commercials/"
declare -g v640240xml="640x240_videogame_commercials_files.xml"

url="http://archive.org/download/videogamecommmercials1993/Videogame%20Commmercials%201993.mp4" 

res="$(LD_LIBRARY_PATH=/media/fat/Scripts/.MiSTer_SAM /media/fat/Scripts/.MiSTer_SAM/mplayer -vo null -ao null -identify -frames 0 $url | grep "VIDEO:" | awk '{print $3}')"
res_comma=$(echo "$res" | tr 'x' ',')
res_space=$(echo "$res" | tr 'x' ' ')

# Check if the [menu] entry exists
if [[ $ini_contents =~ \[menu\] ]]; then
    echo "[menu] entry already exists."
else
    # Append [menu] entry if it doesn't exist
    echo -e "\n[menu]" >> "$ini_file"
    echo "[menu] entry created."
fi

# Replace video_mode if it exists within [menu] entry
if [[ $ini_contents =~ \[menu\].*video_mode=([^,[:space:]]+) ]]; then
    awk -v res_comma="$res_comma" '/\[menu\]/{p=1} p&&/video_mode/{sub(/=.*/, "="res_comma",60"); p=0} 1' "$ini_file" > "$ini_file.tmp" && mv "$ini_file.tmp" "$ini_file"
    echo "video_mode replaced in [menu] entry."
else
    # Append video_mode within [menu] entry
    awk -v res_comma="$res_comma" '/\[menu\]/{p=1} p&&!/video_mode/{print "video_mode="res_comma",60"; p=0} 1' "$ini_file" > "$ini_file.tmp" && mv "$ini_file.tmp" "$ini_file"
    echo "video_mode added to [menu] entry."
fi


function curl_download() { # curl_download ${filepath} ${URL}

	curl \
		--connect-timeout 15 --max-time 600 --retry 3 --retry-delay 5 --silent --show-error \
		--insecure \
		--fail \
		--location \
		-o "${1}" \
		"${2}"
}

echo load_core /media/fat/menu.rbf > /dev/MiSTer_cmd
sleep 2
curl_download /tmp/SAMvideos.xml  "${v640240}${v640240xml}"
grep -o '<file name="[^"]\+\.mp4"' /tmp/SAMvideos.xml | sed 's/<file name="//;s/"$//' > /tmp/SAMvideos.txt 

/media/fat/Scripts/.MiSTer_SAM/mbc raw_seq :43
echo "\033[?25l" > /dev/tty1
chvt 2
#vmode -r ${res_space} rgb32
#wget -O /tmp/SAMvideo.mp4 "${v640240}$(shuf -n1 /tmp/SAMvideos.txt)"
# Trap the SIGINT signal (Ctrl+C)

trap 'break' SIGINT
# while :; do
	# LD_LIBRARY_PATH=/media/fat/Scripts/.MiSTer_SAM /media/fat/Scripts/.MiSTer_SAM/mplayer -cache 8192 -double 0 "${v640240}$(shuf -n1 /tmp/SAMvideos.txt)"
	# ps aux | grep mplayer | awk '{print $2}' | xargs kill
# done
#LD_LIBRARY_PATH=/media/fat/Scripts/.MiSTer_SAM /media/fat/Scripts/.MiSTer_SAM/mplayer -cache 8192 -double 0 "/media/fat/video/640x480-14_Minutes_Sega_Genesis_Commercials.mpg"


LD_LIBRARY_PATH=/media/fat/Scripts/.MiSTer_SAM /media/fat/Scripts/.MiSTer_SAM/mplayer -cache 8192 "$url"
echo load_core /media/fat/menu.rbf > /dev/MiSTer_cmd
