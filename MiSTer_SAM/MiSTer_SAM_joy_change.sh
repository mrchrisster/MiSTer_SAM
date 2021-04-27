#!/bin/bash

inotifywait --quiet --monitor --event create --event moved_to --event close_write /dev/input/ | while read path action file; do echo "Device change" >> /tmp/.SAM_Joy_Change; done
