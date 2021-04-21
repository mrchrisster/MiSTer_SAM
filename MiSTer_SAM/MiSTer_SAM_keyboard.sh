#!/bin/bash

while true; do
	if [[ $(xxd -l 8 -c32 "/dev/${1}" | cut -c1) == "0" ]]; then
		echo "Keyboard used" >| /tmp/.SAM_Keyboard_Activity
	fi
	sleep 0.2
done
