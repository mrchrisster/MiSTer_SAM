#!/bin/bash

inotifywait --monitor -e create -e moved_to -e close_write /dev/input/ | while read path action file; do echo "change" > /tmp/.SAM_Joy_Change; done
