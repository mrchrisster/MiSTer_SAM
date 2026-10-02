# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function sam_display_read() {
    sam_display_game="" sam_display_rom_path="" sam_display_core="" sam_display_setname=""
    sam_display_mode=normal sam_display_timer=0 sam_display_start_time=0
    sam_display_active=no sam_display_game_kept=no sam_display_owner_pid=""
    local line key value
    [[ -r "$sam_display_state_file" ]] || return 0
    # Data only: never source/eval a state file or interpret quotes/backslashes.
    while IFS= read -r line; do
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}" value="${line#*=}"
        case "$key" in
            game|rom_path|core|setname|mode|timer|start_time|active|game_kept|owner_pid)
                printf -v "sam_display_$key" '%s' "$value" ;;
        esac
    done < "$sam_display_state_file"
}

function sam_display_write() {
    [[ "${sam_status_enabled,,}" == yes ]] || return 0
    local active="$1" mode="$2" duration="$3" started="$4" kept="${5:-no}"
    local proc_line proc_fields key value temp="${sam_display_state_file}.tmp.${BASHPID}"
    if [[ -z "$sam_display_owner_start" ]]; then
        read -r proc_line < "/proc/$$/stat" || return 0
        read -ra proc_fields <<< "${proc_line##*) }"
        sam_display_owner_start="${proc_fields[19]}"
    fi
    [[ "$duration" =~ ^[0-9]+$ ]] || duration=0
    [[ "$started" =~ ^[0-9]+$ ]] || started=0
    {
        printf 'active=%s\nmode=%s\n' "$active" "$mode"
        for key in game rom_path core setname; do
            local var="sam_display_$key"
            value="${!var}"
            # One value per line; equals signs and UTF-8 remain literal.
            value="${value//$'\n'/ }" value="${value//$'\r'/ }"
            printf '%s=%s\n' "$key" "$value"
        done
        printf 'start_time=%s\ntimer=%s\ngame_kept=%s\nowner_pid=%s\nowner_start=%s\n' \
            "$started" "$duration" "$kept" "$$" "$sam_display_owner_start"
    } > "$temp" && mv -f "$temp" "$sam_display_state_file"
    [[ ! -f "$temp" ]] || rm -f "$temp"
    return 0
}

function sam_display_start() {
    [[ "${sam_status_enabled,,}" == yes ]] || return 0
    sam_display_read
    sam_display_game="" sam_display_rom_path="" sam_display_core="" sam_display_setname=""
    local mode="${sam_mode:-normal}"
    sam_display_write yes "$mode" 0 0
}

function sam_display_set_path() {
    local candidate="$1" remaining="$1" prefix="" part
    sam_display_rom_path=""
    [[ "$candidate" == /* ]] || return 0
    if [[ -f "$candidate" ]]; then
        sam_display_rom_path="$candidate"
        return 0
    fi
    # MiSTer ZIP/member paths are virtual, but their ZIP must exist on disk.
    # Only test file existence: no archive scan, hashing or subprocess here.
    while [[ "$remaining" == */* ]]; do
        part="${remaining%%/*}" remaining="${remaining#*/}"
        prefix="${prefix}${part}/"
        if [[ "${part,,}" == *.zip && -n "$remaining" && -f "${prefix%/}" ]]; then
            sam_display_rom_path="$candidate"
            break
        fi
    done
    return 0
}

function sam_display_launch() { # game, ROM path, core, arcade setname, [mode], [timer]
    [[ "${sam_status_enabled,,}" == yes ]] || return 0
    sam_display_read
    # Stop/another session may have taken ownership while this game was loading.
    [[ "$sam_display_owner_pid" == "$$" && "$sam_display_active" == yes ]] || return 0
    sam_display_game="$1" sam_display_core="$3" sam_display_setname="$4"
    sam_display_set_path "$2"
    local mode="${5:-normal}"
    if [[ "$mode" == normal ]]; then
        mode="${sam_mode:-normal}"
    fi
    sam_display_write yes "$mode" "${6:-$gametimer}" "$EPOCHSECONDS"
}

function sam_display_publish() { # timer, deadline; omitted means no countdown
    [[ "${sam_status_enabled,,}" == yes ]] || return 0
    sam_display_read
    [[ "$sam_display_owner_pid" == "$$" && "$sam_display_active" == yes ]] || return 0
    local duration="${1:-0}" deadline="${2:-0}" started="$sam_display_start_time"
    [[ "$started" =~ ^[0-9]+$ ]] || started=0
    if [[ "$duration" =~ ^[0-9]+$ && "$deadline" =~ ^[0-9]+$ ]] && (( duration > 0 && deadline >= duration )); then
        if (( started > 0 && deadline >= started )); then
            # Preserve launch time when M82/video timing is extended or synced.
            duration=$((deadline - started))
        else
            started=$((deadline - duration))
        fi
    fi
    sam_display_write yes "$sam_display_mode" "$duration" "$started"
}

function sam_display_off() {
    [[ "${sam_status_enabled,,}" == yes ]] || return 0
    sam_display_read
    local kept=no
    [[ "${1:-menu}" == game && -n "$sam_display_game" ]] && kept=yes
    sam_display_write no "$sam_display_mode" "$sam_display_timer" "$sam_display_start_time" "$kept"
}

function sam_display_exit() {
    [[ "${sam_status_enabled,,}" == yes ]] || return 0
    sam_display_read
    # An older session exiting must not erase a newer session's status.
    if [[ "$sam_display_owner_pid" == "$$" && "$sam_display_active" == yes ]]; then
        sam_display_off
    fi
}
