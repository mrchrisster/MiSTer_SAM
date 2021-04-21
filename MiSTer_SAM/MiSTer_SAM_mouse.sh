#!/bin/bash

while true; do
	if [[ $(xxd -l 8 -c32 /dev/input/mice | cut -c1) == "0" ]]; then
		echo "Mouse moved" >| /tmp/.SAM_Mouse_Activity
	fi
	sleep 0.2
done
