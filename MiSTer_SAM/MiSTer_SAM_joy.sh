#!/bin/bash

while true; do
	if [[ $(xxd -l 128 -c 8 ${1} | awk '{ print $4 }' | grep 0100) == "0100" ]]\ # Buttons
	|| [ $(xxd -l 144 -c 8 ${1} | awk '{ print $4, $5}' | grep "0180 8201") ]\ # Dpad up
	|| [ $(xxd -l 144 -c 8 ${1} | awk '{ print $4, $5}' | grep "ff7f 8201") ]\ # Dpad down
	|| [ $(xxd -l 144 -c 8 ${1} | awk '{ print $4, $5}' | grep "ff7f 8200") ]\ # Dpad right
	|| [ $(xxd -l 144 -c 8 ${1} | awk '{ print $4, $5}' | grep "0180 8200") ]; then # Dpad left
		echo "Button pushed" >| /tmp/.SAM_Joy_Activity
	fi
	sleep 0.2 
done
