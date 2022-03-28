#!/bin/bash

while true; do
	if [[ $( hexdump -n 8 -ve '1/1 "%.2x"' /dev/input/mice | cut -c1) == "0" ]]; then
		echo "Mouse moved" >| /tmp/.SAM_Mouse_Activity
	fi
	sleep 0.2
done
