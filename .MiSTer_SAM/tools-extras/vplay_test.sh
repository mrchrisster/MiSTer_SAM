declare -g v640240="http://ia902700.us.archive.org/3/items/640x240_videogame_commercials/"
declare -g v640480="http://ia902700.us.archive.org/3/items/640x480_videogame_commercials/"
declare -g v640240xml="640x240_videogame_commercials_files.xml"

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
#wget -O /tmp/SAMvideo.mp4 "${v640240}$(shuf -n1 /tmp/SAMvideos.txt)"
# Trap the SIGINT signal (Ctrl+C)
vmode -r 640 480 rgb32
trap 'break' SIGINT
# while :; do
	# LD_LIBRARY_PATH=/media/fat/Scripts/.MiSTer_SAM /media/fat/Scripts/.MiSTer_SAM/mplayer -cache 8192 -double 0 "${v640240}$(shuf -n1 /tmp/SAMvideos.txt)"
	# ps aux | grep mplayer | awk '{print $2}' | xargs kill
# done
#LD_LIBRARY_PATH=/media/fat/Scripts/.MiSTer_SAM /media/fat/Scripts/.MiSTer_SAM/mplayer -cache 8192 -double 0 "/media/fat/video/640x480-14_Minutes_Sega_Genesis_Commercials.mpg"
LD_LIBRARY_PATH=/tmp/mrext-mplayer /tmp/mrext-mplayer/mplayer -cache 8192 -vfm ffmpeg -lavdopts lowres=1:fast:skiploopfilter=all -double 0 http://ia902700.us.archive.org/3/items/640x240_videogame_commercials/Gameboy_Commercials_1.mp4
echo load_core /media/fat/menu.rbf > /dev/MiSTer_cmd
