#!/bin/bash

while true; do
	if [[ $(xxd -l 128 -c 8 ${1} | awk '{ print $4 }' | grep 0100) == "0100" ]]; then
		echo "Button pushed" >| /tmp/.SAM_Joy_Activity
	fi
	sleep 0.2 
done
