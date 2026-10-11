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
        sam_audio_set_live unmute || return 1
    else
        val=$((val | 16))
        echo -e "\nMuting..."
        sam_audio_set_live mute || return 1
    fi
    printf "\\x$(printf %02x $val)" | dd of="$volfile" bs=1 count=1 conv=notrunc 2>/dev/null
}

function mute() {
	if [[ "${mute}" == "yes" || "${mute}" == "global" ]]; then
		# The helper proves ownership; a substring in mount output cannot do so.
		only_mute_if_needed
	elif [ "${mute}" == "core" ]; then
        sam_core_volume_mute "${1:-}"
	fi
}

sam_core_volume_owned() { # exact target and original RAM-source inode
    sam_volume_is_mounted "$1" && [[ -f "$2" && "$1" -ef "$2" ]]
}

sam_core_volume_source_for_target() { # canonical FAT spelling need not match RAM
    local candidate
    sam_core_volume_resolved=
    for candidate in "$mrsamtmp"/SAM_config/*_volume.cfg; do
        if [[ -f "$candidate" && "$1" -ef "$candidate" ]]; then
            sam_core_volume_resolved=$candidate
            return 0
        fi
    done
    return 1
}

sam_core_volume_release_other() { # mount state survives fresh launch shells
    local keep=$1 mount_source target kind rest source
    while IFS=' ' read -r mount_source target kind rest; do
        target=${target//\\040/ }; target=${target//\\011/$'\t'}; target=${target//\\134/\\}
        [[ "$target" != "$keep" && ! "$target" -ef "$keep" ]] || continue
        [[ "$target" == *_volume.cfg ]] || continue
        if sam_core_volume_source_for_target "$target" &&
           sam_core_volume_owned "$target" "$sam_core_volume_resolved"; then
            timeout 1s umount -l "$target" || return 1
            sam_volume_is_mounted "$target" && return 1
        elif [[ "$target" == "${sam_core_volume_target:-}" ]]; then
            return 1 # previous ownership was replaced; never adopt it
        fi
        :
    done < "${SAM_MOUNTS_FILE:-/proc/mounts}" || return 1
    return 0
}

sam_core_volume_mute() {
    local core=$1 target source mounted=0
    [[ -n "$core" && "$core" != . && "$core" != .. &&
       "$core" != */* && "$core" != *$'\n'* && "$core" != *$'\r'* ]] || return 1
    target="${configpath%/}/${core}_volume.cfg"
    source="$mrsamtmp/SAM_config/${core}_volume.cfg"
    # Restoring a SAM-owned global bind may fail; never proceed over that error.
    # A user's independent global mute is not ours to clear for BGM.
    if [[ -e "$mrsamtmp/volume-restore" ]] || sam_volume_owned_mount "${configpath%/}/Volume.dat"; then
        only_unmute_if_needed || return 1
    fi
    if sam_volume_is_mounted "$target"; then
        sam_core_volume_source_for_target "$target" || return 1
        source=$sam_core_volume_resolved
        sam_core_volume_owned "$target" "$source" || return 1
        mounted=1
    fi
    sam_core_volume_release_other "$target" || return 1
    if ((mounted)); then
        sam_core_volume_owned "$target" "$source" || return 1
        printf '\x06' > "$source" || return 1
        prevcore=$core sam_core_volume_target=$target sam_core_volume_source=$source
        return 0
    fi
    mkdir -p "$mrsamtmp/SAM_config" "$configpath" || return 1
    [[ ! -e "$target" || -f "$target" ]] || return 1
    [[ -f "$target" ]] || : > "$target" || return 1
    # Main reads this byte on load. Publish the mute value before binding it,
    # rather than exposing an empty/unmuted temporary file during the mount.
    printf '\x06' > "$source" || return 1
    timeout 1s mount --bind "$source" "$target" || return 1
    sam_core_volume_owned "$target" "$source" || return 1
    prevcore=$core sam_core_volume_target=$target sam_core_volume_source=$source
}

sam_audio_restore_in_budget() {
    if [[ "${sam_menu_delivery_active:-0}" == 1 && "${sam_menu_deadline:-}" =~ ^[0-9]+$ ]]; then
        (( SECONDS < sam_menu_deadline )) || return 1
    fi
}

sam_audio_set_live() { # the only live mute command path
    [[ "$1" == mute || "$1" == unmute ]] || return 1
    sam_audio_restore_in_budget || return 1
    if [[ "${sam_menu_delivery_active:-0}" == 1 ]]; then sam_menu_delivery_still_current || return 1; fi
    timeout 1s sh -c 'printf "volume %s\n" "$1" > "$2"' _ "$1" "${SAM_MISTER_CMD_FILE:-/dev/MiSTer_cmd}"
}

sam_volume_read_byte() {
    sam_volume_byte=$(xxd -p -l 1 "$1") || return 1
    [[ "$sam_volume_byte" =~ ^[0-9a-fA-F]{2}$ ]]
}

sam_volume_record_read() {
    local line
    sam_volume_path= sam_volume_saved= sam_volume_phase=
    [[ -r "$mrsamtmp/volume-restore" ]] || return 1
    while IFS= read -r line; do
        case "$line" in path=*) sam_volume_path=${line#*=};; byte=*) sam_volume_saved=${line#*=};; phase=*) sam_volume_phase=${line#*=};; esac
    done < "$mrsamtmp/volume-restore"
    [[ "$sam_volume_path" == /* && "$sam_volume_saved" =~ ^[0-9a-fA-F]{2}$ &&
       ( "$sam_volume_phase" == bound || "$sam_volume_phase" == pending ) ]]
}

sam_volume_record_write() { # path original-byte bound|pending; RAM only
    local temp="$mrsamtmp/volume-restore.tmp.$BASHPID"
    printf 'path=%s\nbyte=%s\nphase=%s\n' "$1" "$2" "$3" > "$temp" &&
        mv -f "$temp" "$mrsamtmp/volume-restore"
}

sam_volume_is_mounted() {
    local source target rest
    while IFS=' ' read -r source target rest; do
        target=${target//\\040/ }; target=${target//\\011/$'\t'}; target=${target//\\134/\\}
        if [[ "$target" == "$1" || "$target" -ef "$1" ]]; then return 0; fi
    done < "${SAM_MOUNTS_FILE:-/proc/mounts}"
    return 1
}

sam_volume_owned_mount() {
    sam_volume_is_mounted "$1" && [[ "$1" -ef "$mrsamtmp/Volume.dat" ]]
}

function global_mute() {
    local real="${configpath%/}/Volume.dat" tmp="$mrsamtmp/Volume.dat" original hex
    if [[ -e "$mrsamtmp/volume-restore" ]]; then
        sam_volume_record_read || return 1
        if [[ "$sam_volume_phase" == bound ]] && sam_volume_owned_mount "$sam_volume_path"; then
            sam_volume_read_byte "$sam_volume_path" || return 1
            if (( (0x$sam_volume_byte & 0x10) == 0 )); then
                # A restored but still bound file may remain after failed
                # unmount. Reacquire live mute before another attract session.
                sam_audio_set_live mute || return 1
                sam_volume_owned_mount "$sam_volume_path" || return 1
                sam_volume_read_byte "$sam_volume_path" || return 1
                printf -v hex '%02x' "$((0x$sam_volume_byte | 0x10))"
                printf '%b' "\\x$hex" > "$tmp" || return 1
            fi
            return 0
        fi
        global_unmute || return 1
    fi
    # An unrelated bind must never be replaced or adopted as SAM's mute.
    sam_volume_is_mounted "$real" && return 1
    mkdir -p "$mrsamtmp" || return 1
    # A first-time mount target needs a file; 00 is the normal default byte,
    # not an instruction to clear an existing user's mute setting.
    [[ -f "$real" ]] || printf '\x00' > "$real" || return 1
    sam_volume_read_byte "$real" || return 1
    original=$sam_volume_byte
    printf -v hex '%02x' "$((0x$original | 0x10))"
    printf '%b' "\\x$hex" > "$tmp" || return 1
    mount --bind "$tmp" "$real" || return 1
    if ! sam_volume_owned_mount "$real"; then return 1; fi
    if ! sam_volume_record_write "$real" "$original" bound; then
        timeout 1s umount -l "$real" >/dev/null 2>&1 || true
        return 1
    fi
    # A failed delivery retains the bind and saved byte for safe cleanup/retry.
    sam_audio_set_live mute
}

function global_unmute() {
    sam_audio_restore_in_budget || return 1
    local real="${configpath%/}/Volume.dat" original= phase= action
    if [[ -e "$mrsamtmp/volume-restore" ]]; then
        sam_volume_record_read || return 1
        real=$sam_volume_path original=$sam_volume_saved phase=$sam_volume_phase
    fi
    if sam_volume_is_mounted "$real"; then
        sam_volume_owned_mount "$real" || return 1
        if [[ -n "$original" ]]; then
            action=unmute
            (( (0x$original & 0x10) == 0 )) || action=mute
            sam_volume_read_byte "$real" || return 1
            if (( (0x$sam_volume_byte & 0x10) != (0x$original & 0x10) )); then
                sam_audio_set_live "$action" || return 1
                local attempt acknowledged=0
                # Main saves live volume after its command delay. Keep the SD
                # original hidden until that save acknowledges the desired bit.
                for ((attempt=0; attempt<20; attempt++)); do
                    sam_audio_restore_in_budget || return 1
                    sam_volume_owned_mount "$real" || return 1
                    if [[ "${sam_menu_delivery_active:-0}" == 1 ]]; then
                        sam_menu_delivery_still_current || return 1
                    fi
                    sam_volume_read_byte "$real" || return 1
                    if (( (0x$sam_volume_byte & 0x10) == (0x$original & 0x10) )); then
                        acknowledged=1; break
                    fi
                    sleep 0.1
                done
                [[ "$acknowledged" == 1 ]] || return 1
            fi
            sam_volume_owned_mount "$real" || return 1
            if [[ "${sam_menu_delivery_active:-0}" == 1 ]]; then
                sam_menu_delivery_still_current || return 1
            fi
            sam_audio_restore_in_budget || return 1
            timeout 1s umount -l "$real" >/dev/null 2>&1 || return 1
            sam_volume_is_mounted "$real" && return 1
            rm -f "$mrsamtmp/volume-restore"
            return
        fi
        # Old installed binds have no record; read their underlying byte after
        # unmount. New binds retain the premount byte against delayed Main saves.
        if [[ -n "$original" ]]; then sam_volume_record_write "$real" "$original" pending || return 1; fi
        sam_audio_restore_in_budget || return 1
        timeout 1s umount -l "$real" >/dev/null 2>&1 || return 1
        sam_volume_is_mounted "$real" && return 1
        sam_volume_read_byte "$real" || return 1
        [[ -n "$original" ]] || original=$sam_volume_byte
        sam_volume_record_write "$real" "$original" pending || return 1
    elif [[ "$phase" != pending ]]; then
        # No actual SAM bind and no pending restore: preserve live user state.
        return 0
    fi
    action=unmute
    (( (0x$original & 0x10) == 0 )) || action=mute
    sam_audio_set_live "$action" || return 1
    rm -f "$mrsamtmp/volume-restore"
}

function only_mute_if_needed() {
    # An owned bind can contain a restored byte after an unmount failure.
    # The record-aware path verifies/reacquires mute instead of assuming it.
    global_mute
}

function only_unmute_if_needed() {
    if [[ -e "$mrsamtmp/volume-restore" ]] || sam_volume_owned_mount "${configpath%/}/Volume.dat"; then
        global_unmute
    else return 1; fi
}
