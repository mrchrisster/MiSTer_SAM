# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function toggle_mute() {
    local volfile="${configpath}/Volume.dat"
    if [ ! -f "$volfile" ]; then echo -ne "\x00" > "$volfile"; fi

    local hexval=$(xxd -p -l 1 -s 0 "$volfile")
    local val=$((16#$hexval))

    if (( (val & 16) == 16 )); then
        val=$((val & ~16))
        echo -e "\nUnmuting..."
        timeout 1s sh -c "echo 'volume unmute' > /dev/MiSTer_cmd"
    else
        val=$((val | 16))
        echo -e "\nMuting..."
        timeout 1s sh -c "echo 'volume mute' > /dev/MiSTer_cmd"
    fi
    printf "\\x$(printf %02x $val)" | dd of="$volfile" bs=1 count=1 conv=notrunc 2>/dev/null
}

function mute() {
	if [[ "${mute}" == "yes" || "${mute}" == "global" ]]; then
		# Global mute is a one-time bind mount for the whole session; skip if already active.
		mount | grep -q "${configpath%/}/Volume.dat" && return
		only_mute_if_needed
	elif [ "${mute}" == "core" ]; then
		samdebug "mute=core"
		only_unmute_if_needed
		# Create empty volume files. Only SD card write operation necessary for mute to work.
		[ ! -f "${configpath}/${1}_volume.cfg" ] && touch "${configpath}/${1}_volume.cfg"
		[ ! -f "/tmp/.SAM_tmp/SAM_config/${1}_volume.cfg" ] && touch "/tmp/.SAM_tmp/SAM_config/${1}_volume.cfg"
		for i in {1..3}; do
		  if mount | grep -iq "${configpath}/${1}_volume.cfg"; then
			samdebug "${1}_volume.cfg already mounted"
			break
		  fi

		  mount --bind "/tmp/.SAM_tmp/SAM_config/${1}_volume.cfg" "${configpath}/${1}_volume.cfg"

		  if [ $? -eq 0 ]; then
			samdebug "${1}_volume.cfg mounted successfully"
			break
		  else
			echo "ERROR: Failed to mute ${1} (attempt ${i})"
			if [ $i -eq 3 ]; then
			  echo "ERROR: All attempts to mute ${1} failed... Continuing."
			fi
			sleep 2
		  fi
		done
		[[ "$(mount | grep -ic "${1}"_volume.cfg)" != "0" ]] && echo -e "\0006\c" > "/tmp/.SAM_tmp/SAM_config/${1}_volume.cfg"
		# Only keep one volume.cfg file mounted
		if [ -n "${prevcore}" ] && [ "${prevcore}" != "${1}" ]; then
			umount "${configpath}/${prevcore}_volume.cfg"
			sync
		fi
		prevcore=${1}
	fi
}

function write_byte() {
  local f="$1"; local hex="$2"
  printf '%b' "\\x$hex" > "$f" && sync
}

function global_mute() {
	local real="${configpath%/}/Volume.dat"
	local tmp="/tmp/.SAM_tmp/Volume.dat"

	# Nothing to do if already bind-mounted
	if mount | grep -q "${real}"; then
		samdebug "Volume.dat already bind-mounted, skipping"
		return
	fi

	# If Volume.dat doesn't exist yet create a silent (level 0) real file so
	# there is something to bind-mount over.
	if [ ! -f "${real}" ]; then
		printf '%b' "\\x00" > "${real}" && sync
		samdebug "Volume.dat created (0x00) as placeholder"
	fi

	# Read the real byte and set the mute bit in the tmpfs copy
	local cur m hex
	cur=$(xxd -p -c1 "${real}")
	m=$(( 0x$cur | 0x10 ))
	hex=$(printf '%02x' "$m")
	mkdir -p /tmp/.SAM_tmp
	printf '%b' "\\x$hex" > "${tmp}"

	mount --bind "${tmp}" "${real}"
	timeout 1s sh -c "echo 'volume mute' > /dev/MiSTer_cmd"
	samdebug "Global mute: bind-mounted tmpfs Volume.dat (0x$hex), SD card untouched"
}

function global_unmute() {
	local real="${configpath%/}/Volume.dat"

	if mount | grep -q "${real}"; then
		umount -l "${real}" 2>/dev/null || umount "${real}" 2>/dev/null
		samdebug "Global unmute: bind mount removed, SD card Volume.dat restored"
	else
		samdebug "Global unmute: no bind mount active, nothing to do"
	fi
	timeout 1s sh -c "echo 'volume unmute' > /dev/MiSTer_cmd"
}

function only_mute_if_needed() {
	local real="${configpath%/}/Volume.dat"

	# If bind mount already active we're already muted
	if mount | grep -q "${real}"; then
		samdebug "Volume.dat already bind-mounted (muted) -> skipping"
		return
	fi

	samdebug "Volume not yet muted -> muting via bind mount"
	global_mute
}

function only_unmute_if_needed() {
	local real="${configpath%/}/Volume.dat"

	if mount | grep -q "${real}"; then
		samdebug "Volume.dat bind-mounted -> unmuting"
		global_unmute
		return 0
	else
		samdebug "Volume.dat not bind-mounted -> already unmuted, skipping"
		return 1
	fi
}

function unmute_with_retry() {
    local max_wait=15
    local real="${configpath%/}/Volume.dat"
    local counter=0

    samdebug "Attempting to unmute volume..."

    # First ensure the bind mount is gone
    only_unmute_if_needed

    # Then confirm MiSTer's live audio state is unmuted
    while [ $counter -lt $max_wait ]; do
        if ! mount | grep -q "${real}"; then
            samdebug "SUCCESS: Volume.dat bind mount gone, volume restored."
            return 0
        fi
        samdebug "Attempt $(($counter + 1))/$max_wait: bind mount still present, retrying umount..."
        umount -l "${real}" 2>/dev/null
        timeout 1s sh -c "echo 'volume unmute' > /dev/MiSTer_cmd"
        sleep 1
        counter=$(($counter + 1))
    done

    samdebug "FAILED: Timed out trying to unmute volume."
}
