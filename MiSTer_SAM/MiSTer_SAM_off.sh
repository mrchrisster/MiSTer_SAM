#!/bin/bash

/etc/init.d/S93mistersam stop

mount | grep -q "on / .*[(,]ro[,$]" && RO_ROOT="true"
[ "$RO_ROOT" == "true" ] && mount / -o remount,rw
rm -f /etc/init.d/S93mistersam > /dev/null 2>&1
sync
[ "$RO_ROOT" == "true" ] && mount / -o remount,ro
sync

echo "MiSTer SAM (Super Attract Mode)"
echo "is off and inactive at startup."

exit 0
