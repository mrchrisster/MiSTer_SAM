# SPDX-License-Identifier: GPL-3.0-or-later
sam_update() {
    python3 "$mrsampath/../MiSTer_SAM_install.py" --download --branch "$branch"
}

sam_update_assets() {
    source "$mrsampath/lib/downloads.sh"
    mkdir -p "$ratedpath" "$blacklistpath" "$ignorepath"
    local rc=0
    get_samindex || rc=$?
    ((rc == 0 || rc == 2)) || return 1
    chmod +x "$mrsampath/samindex"
    rc=0; get_mbc || rc=$?
    ((rc == 0 || rc == 2)) || return 1
    chmod +x "$mrsampath/mbc"
    get_inputmap || return 1
    get_blacklist || return 1
    get_ratedlist || return 1
    sam_emit update_assets
    echo 'SAM assets updated. Custom ignore lists preserved.'
}

# Compatibility name for existing menus and third-party sourced callers.
parse_cmd() { sam_dispatch "$@"; }

sam_dispatch_gateway() {
    # Menu actions use the same small transport as the command entry point.
    local rc=125
    if [[ -r "$mrsampath/lib/controller-client.sh" ]]; then
        source "$mrsampath/lib/controller-client.sh" || return 1
        rc=0
        sam_controller_try "$@" || rc=$?
    fi
    ((rc == 125)) || return "$rc"
    python3 "$mrsampath/samctl.py" "$@"
}

sam_command_family() { # Explicit loading policy; no runtime function guessing.
    case "$1" in
        control|status|pause|resume|play|next|skip|previous|mute|m82_play|start|restart|stop|kill|stop_owner|exit_to_game|exit_to_menu|exit_to_menu_fast|menu_audio_restore|unmute|ignore)
            sam_command_kind=gateway ;;
        validate_start|loop_core|bootstart|enable|disable|autoconfig|default|artwork_setup|artwork_refresh)
            sam_command_kind=runtime ;;
        monitor|mcp_monitor|startmonitor|sm|update|menu|back|help|sshconfig|menu_*)
            sam_command_kind=ui ;;
        *) sam_command_kind=unknown ;;
    esac
}

sam_dispatch() {
    local first="${1,,}"
    [[ -n "$first" ]] || { source "$mrsampath/lib/menu.sh"; sam_menu_run sam_premenu; return; }
    shift
    sam_command_family "$first"
    if [[ "$sam_command_kind" == gateway && "${sam_gateway_backend:-0}" != 1 ]]; then
        sam_dispatch_gateway "$first" "$@"
        return $?
    fi
    if [[ "$sam_command_kind" == unknown ]]; then
        if [[ "$first" =~ ^[a-z0-9_]+$ && -n "${CORE_PRETTY[$first]-}" ]]; then
            if [[ "${sam_gateway_backend:-0}" == 1 ]]; then sam_start "$first" "$@"
            else sam_dispatch_gateway start "$first" "$@"; fi
            return $?
        fi
        printf 'Unknown SAM command: %s\n' "$first" >&2
        return 1
    fi
    if [[ "$sam_command_kind" == ui ]]; then
        sam_dispatch_ui "$first" "$@"
        return $?
    fi
    if declare -F sam_caller_require_runtime >/dev/null; then
        sam_caller_require_runtime || return $?
    fi
    sam_dispatch_runtime "$first" "$@"
}

sam_dispatch_ui() {
    local first=$1
    shift
    case "$first" in
        monitor) sam_monitor ;;
        mcp_monitor) mcp_monitor ;;
        startmonitor|sm) sam_dispatch_gateway start "$@" && sam_monitor ;;
        update) sam_update "$@" ;;
        menu|back|help|sshconfig|menu_*)
            source "$mrsampath/lib/menu.sh" || return 1
            case "$first" in
                menu|back) sam_menu ;;
                help) sam_help ;;
                sshconfig) sam_sshconfig ;;
                *) load_menu_if_needed || return
                   declare -F "$first" >/dev/null && sam_menu_run "$first" "$@" ;;
            esac ;;
        *) return 2 ;;
    esac
}

sam_dispatch_runtime() {
    local first=$1
    shift
    case "$first" in
        start|restart|stop|kill|stop_owner|exit_to_game|exit_to_menu|exit_to_menu_fast|loop_core)
            if declare -F sam_diagnostic >/dev/null; then
                sam_diagnostic command_received "command=$first" "${sam_owner:-}" gateway || true
            fi ;;
    esac
    case "$first" in
        start|restart) sam_start "$@" ;;
        validate_start) sam_core_session_begin "${1:-}" || { printf 'SAM: %s\n' "$sam_core_reason" >&2; return 1; } ;;
        control) python3 "$mrsampath/control/samctl.py" "$@" ;;
        pause|resume|play) python3 "$mrsampath/control/samctl.py" "$first" "$@" ;;
        status) python3 "$mrsampath/control/samctl.py" status ;;
        next|skip|previous|mute|m82_play) python3 "$mrsampath/samctl.py" "$first" "$@" ;;
        ignore) ignoregame "$@" ;;
        stop_owner) there_can_be_only_one "$@" ;;
        stop|kill) sam_exit_menu=1; there_can_be_only_one "$@" || return; exit_sam menu ;;
        exit_to_game) there_can_be_only_one "$@" || return; exit_sam game ;;
        exit_to_menu) sam_exit_menu=1; there_can_be_only_one "$@" || return; exit_sam menu ;;
        exit_to_menu_fast) sam_exit_menu=1; there_can_be_only_one "$@" || return; exit_sam_fast ;;
        menu_audio_restore) sam_menu_audio_restore "$@" ;;
        loop_core) loop_core "$@" ;;
        bootstart) env_check; boot_sleep; mcp_start ;;
        enable) env_check; sam_enable ;;
        disable) sam_cleanup; kill_all_sams; sam_disable ;;
        unmute) sam_unmute_owner "$@" ;;
        autoconfig|default) sam_update_assets "$@" ;;
        artwork_setup|artwork_refresh)
            [[ -n "${SAM_MODULES[artwork]-}" ]] || { echo 'Artwork module is disabled.' >&2; return 1; }
            [[ "$first" != artwork_refresh ]] || set -- refresh "$@"
            sam_artwork_setup "$@" ;;
        *) return 2 ;;
    esac
}
