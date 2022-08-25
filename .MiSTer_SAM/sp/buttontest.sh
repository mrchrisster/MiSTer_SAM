#!/bin/bash

pyfile="/media/fat/Scripts/.MiSTer_SAM/MiSTer_SAM_joy.py"
id="$($pyfile /dev/input/js0 id)"
name="$(grep -iwns "js0" /proc/bus/input/devices -B 4 | grep Name | awk -F'"' '{print $2}')"

echo Please press start button now
startbutton="$($pyfile /dev/input/js0 start)"
echo This is start value: $startbutton
echo id is: $id


if [ "$(grep -c $id $pyfile)" == "0" ]; then 
	sed -i '16 a\    \},' "$pyfile"
	sed -i '16 a\        \"axis": {},' "$pyfile"
	sed -i '16 a\        \},' "$pyfile"
	sed -i '16 a\            \"start": '"$startbutton"',' "$pyfile"
	sed -i '16 a\        \"button": {' "$pyfile"
	sed -i '16 a\        \"name": "'"$name"'",' "$pyfile"
	sed -i '16 a\    \"'"$id"'": {' "$pyfile"
	echo "$name added successfully."
else
	echo "$name already added"
fi
