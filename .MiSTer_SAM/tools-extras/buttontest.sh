#!/bin/bash

pyfile="/media/fat/Scripts/.MiSTer_SAM/MiSTer_SAM_joy.py"
id="$($pyfile /dev/input/js0 id)"
name="$(grep -iwns "js0" /proc/bus/input/devices -B 4 | grep Name | awk -F'"' '{print $2}')"

echo Please press start button now
startbutton="$($pyfile /dev/input/js0 start)"
echo start button: $startbutton
echo controller id: $id


if [ "$(grep -c $id $pyfile)" == "0" ]; then 
	sed -i '16 a\    \"'"$id"'": { \
		"name": "'"$name"'", \
		"button": { \
			"start": '"$startbutton"', \
		}, \
		"axis": {}, \
	},' $pyfile
		echo "$name added successfully."
else
	echo "$name already added"
fi
