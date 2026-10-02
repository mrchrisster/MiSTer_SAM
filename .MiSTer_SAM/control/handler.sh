# Optional Monitor handoff. Idle countdown ticks use only a Bash file test.
# No socket, broker, daemon, or changes to SAM_state's format.
sam_control_root=${SAM_CONTROL_ROOT:-/tmp/mister_sam_control}
sam_control_helper=${SAM_CONTROL_HELPER:-$mrsampath/control/sam_control.py}
sam_control_generation=0

sam_control_publish() {
    [[ "${sam_status_enabled,,}" == yes && -r "$sam_control_helper" ]] || return 0
    sam_display_read
    [[ "$sam_display_owner_pid" == "$$" && "$sam_display_active" == yes ]] || return 0
    mkdir -p "$sam_control_root"
    local temp="$sam_control_root/status.tmp.$$"
    {
        printf 'owner_pid=%s\nowner_start=%s\nstart_time=%s\nrom_path=%s\n' \
            "$$" "$sam_display_owner_start" "$sam_display_start_time" "$sam_display_rom_path"
        printf 'generation=%s\nready=%s\npaused=%s\nremaining_seconds=%s\n' \
            "$sam_control_generation" "$1" "${sam_paused:-0}" "${sam_frozen:-0}"
    } > "$temp" && mv -f "$temp" "$sam_control_root/status"
}

sam_request_next() {
    SAM_ACTION=next
    sam_control_publish 0
    sam_display_publish
}

sam_control_tick() {
    [[ -s "$sam_control_root/pending.json" && -r "$sam_control_helper" ]] || return 0
    local request action
    read -r request action <<< "$(python3 "$sam_control_helper" claim --owner "$$")"
    [[ -n "$request" ]] || return 0
    case "$action" in
        pause)
            sam_frozen=$((end_time - SECONDS))
            (( sam_frozen < 0 )) && sam_frozen=0
            sam_paused=1
            sam_control_publish 1
            ;;
        resume)
            end_time=$((SECONDS + sam_frozen))
            sam_paused=0
            sam_display_publish "$sam_frozen" "$((EPOCHSECONDS + sam_frozen))"
            sam_control_publish 1
            ;;
        ignore)
            sam_display_read
            if ! ignoregame "$sam_display_core" "$sam_display_rom_path" >/dev/null; then
                sam_control_ack "$request" 503
                return 0
            fi
            sam_request_next
            sam_control_ack "$request" 200
            return 1
            ;;
        next)
            sam_request_next
            sam_control_ack "$request" 200
            return 1
            ;;
        play)
            sam_control_publish 0
            exit_sam game
            sam_control_ack "$request" 200
            exit 0
            ;;
        *) return 0;;
    esac
    sam_control_ack "$request" 200
    return 0
}

# The sender already durably reserved the UUID. A fixed acknowledgement needs
# no Python interpreter or shell quoting of caller-controlled content.
sam_control_ack() {
    local request="$1" code="$2" temp="$sam_control_root/ack-$1.tmp.$BASHPID"
    [[ "$request" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || return 1
    case "$code" in
        200) printf '{"code":200,"body":{"ok":true}}\n' > "$temp" ;;
        503) printf '{"code":503,"body":{"ok":false,"error":"Exclusion could not be saved"}}\n' > "$temp" ;;
        *) return 1 ;;
    esac
    mv -f "$temp" "$sam_control_root/ack-$request.json"
}
