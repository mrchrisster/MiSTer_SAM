#!/bin/bash
# MiSTer's Scripts console prints its own "Press any key to continue".
# That dismissal belongs to the UI, not to the new SAM session.
echo 'Starting SAM automatically. The Scripts console can be dismissed while SAM prepares its first game.'
SAM_START_FROM_UI=1 exec "${SAM_ENTRY:-/media/fat/Scripts/MiSTer_SAM_on.sh}" start
