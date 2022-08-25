#!/bin/bash

id="$(/media/fat/Scripts/.MiSTer_SAM/MiSTer_SAM_joy.py /dev/input/js0 id)"

echo Please press start button now
startbutton="$(/media/fat/Scripts/.MiSTer_SAM/MiSTer_SAM_joy.py /dev/input/js0 start)"
echo This is start value: $startbutton
echo id is: $id
name="$(grep -iwns "js0" /proc/bus/input/devices -B 4 | grep Name | awk -F'"' '{print $2}')"
pyfile="/media/fat/Scripts/.MiSTer_SAM/MiSTer_SAM_joy.py"


if [ "$(grep -c $id $pyfile)" == "0" ]; then 
	sed -i '16 a\    \},' "$pyfile"
	sed -i '16 a\        \"axis": {},' "$pyfile"
	sed -i '16 a\        \},' "$pyfile"
	sed -i '16 a\            \"start": '"$startbutton"',' "$pyfile"
	sed -i '16 a\        \"button": {' "$pyfile"
	sed -i '16 a\        \"name": "'"$name"'",' "$pyfile"
	sed -i '16 a\    \"'"$id"'": {' "$pyfile"
else
	echo "$name already added"
fi








