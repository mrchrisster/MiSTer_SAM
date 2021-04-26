#!/bin/bash

while true; do
	if [[ $(xxd -l 144 -c 8 ${1} | awk '{ print $4,$5 }' | grep 'ff7f\|0100\|0180') ]]; then
		echo "Button pushed" >| /tmp/.SAM_Joy_Activity
	fi
	sleep 0.2 
done
