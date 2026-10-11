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

parse_cmd() {
    local first="${1,,}"
    [[ -n "$first" ]] || { source "$mrsampath/lib/menu.sh"; sam_menu_run sam_premenu; return; }
    shift
    case "$first" in
        control|status|pause|resume|play|next|skip|previous|mute|m82_play|start|restart|stop|kill|stop_owner|exit_to_game|exit_to_menu|exit_to_menu_fast|menu_audio_restore|unmute|ignore)
            if [[ "${sam_gateway_backend:-0}" != 1 ]]; then
                python3 "$mrsampath/samctl.py" "$first" "$@"
                return
            fi ;;
    esac
    if [[ -n "${CORE_PRETTY[$first]-}" ]]; then
        if [[ "${sam_gateway_backend:-0}" == 1 ]]; then sam_start "$first"
        else python3 "$mrsampath/samctl.py" start "$first"; fi
        return
    fi
    case "$first" in
        start|restart) sam_start "$@" ;;
        validate_start) sam_core_session_begin "${1:-}" || { printf 'SAM: %s\n' "$sam_core_reason" >&2; return 1; } ;;
        startmonitor|sm) python3 "$mrsampath/samctl.py" start "$@"; sleep 1; sam_monitor ;;
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
        monitor) sam_monitor ;;
        mcp_monitor) mcp_monitor ;;
        bootstart) env_check; boot_sleep; mcp_start ;;
        enable) env_check; sam_enable ;;
        disable) sam_cleanup; kill_all_sams; sam_disable ;;
        unmute) sam_unmute_owner "$@" ;;
        update) sam_update "$@" ;;
        autoconfig|default) sam_update_assets "$@" ;;
        artwork_setup|artwork_refresh)
            [[ -n "${SAM_MODULES[artwork]-}" ]] || { echo 'Artwork module is disabled.' >&2; return 1; }
            [[ "$first" != artwork_refresh ]] || set -- refresh "$@"
            sam_artwork_setup "$@" ;;
        menu|back|help|sshconfig|menu_*)
            source "$mrsampath/lib/menu.sh"
            case "$first" in menu|back) sam_menu ;; help) sam_help ;; sshconfig) sam_sshconfig ;;
                *) load_menu_if_needed || return; declare -F "$first" >/dev/null && sam_menu_run "$first" "$@" ;; esac ;;
        *) echo "Unknown SAM command: $first" >&2; return 1 ;;
    esac
}
