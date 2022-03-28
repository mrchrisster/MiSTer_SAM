#!/bin/bash

while true; do
	if [[ $(hexdump -n 8 -ve '1/1 "%.2x"' "/dev/${1}" | cut -c1) == "0" ]]; then
		echo "Keyboard used" >| /tmp/.SAM_Keyboard_Activity
	fi
	sleep 0.2
done
