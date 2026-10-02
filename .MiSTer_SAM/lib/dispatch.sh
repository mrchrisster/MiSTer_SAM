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
    [[ -n "$first" ]] || { source "$mrsampath/lib/menu.sh"; sam_premenu; return; }
    shift
    if [[ -n "${CORE_PRETTY[$first]-}" ]]; then sam_start "$first"; return; fi
    case "$first" in
        start|restart) sam_start "$@" ;;
        startmonitor|sm) sam_start "$@"; sleep 1; sam_monitor ;;
        control) python3 "$mrsampath/control/samctl.py" "$@" ;;
        pause|resume|play) python3 "$mrsampath/control/samctl.py" "$first" "$@" ;;
        status) python3 "$mrsampath/control/samctl.py" status ;;
        next|skip) tmux send-keys -t SAM n ;;
        ignore) ignoregame "$@" ;;
        stop_owner) there_can_be_only_one "$@" ;;
        previous) tmux send-keys -t SAM p ;;
        mute) tmux send-keys -t SAM m ;;
        stop|kill) kill_all_sams; exit_sam menu ;;
        exit_to_game) there_can_be_only_one "$@" || return; exit_sam game ;;
        exit_to_menu) there_can_be_only_one; exit_sam menu ;;
        exit_to_menu_fast) there_can_be_only_one "$@" || return; exit_sam_fast ;;
        loop_core) loop_core "$@" ;;
        monitor) sam_monitor ;;
        mcp_monitor) mcp_monitor ;;
        bootstart) env_check; [[ "$unmute_on_boot" != yes ]] || unmute_with_retry; boot_sleep; mcp_start ;;
        enable) env_check; sam_enable ;;
        disable) sam_cleanup; kill_all_sams; sam_disable ;;
        unmute) unmute_with_retry ;;
        update) sam_update "$@" ;;
        autoconfig|default) sam_update_assets "$@" ;;
        artwork_setup|artwork_refresh)
            [[ -n "${SAM_MODULES[artwork]-}" ]] || { echo 'Artwork module is disabled.' >&2; return 1; }
            [[ "$first" != artwork_refresh ]] || set -- refresh "$@"
            sam_artwork_setup "$@" ;;
        menu|back|help|sshconfig|menu_*)
            source "$mrsampath/lib/menu.sh"
            case "$first" in menu|back) sam_menu ;; help) sam_help ;; sshconfig) sam_sshconfig ;;
                *) load_menu_if_needed; declare -F "$first" >/dev/null && "$first" "$@" ;; esac ;;
        *) echo "Unknown SAM command: $first" >&2; return 1 ;;
    esac
}
