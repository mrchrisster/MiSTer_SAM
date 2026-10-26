# SPDX-License-Identifier: GPL-3.0-or-later
# Short-lived command/UI caller. Session state and optional modules are lazy.
sam_caller_paths() {
    mrsampath=$sam_root
    misterpath=${SAM_MISTER_ROOT:-/media/fat}
    mrsamtmp=${SAM_TMP_ROOT:-/tmp/.SAM_tmp}
}

sam_caller_require_runtime() {
    [[ "${sam_runtime_loaded:-0}" != 1 ]] || return 0
    source "$sam_root/lib/runtime.sh" || return $?
    sam_load_runtime
}

sam_caller_premenu() {
    # Bash parses the trusted INI faster than a per-line shell display parser,
    # and preserves includes, exports and expressions without a second load
    # when UP opens the full menu. Runtime/core tables remain lazy.
    sam_caller_ui || return 1
    sam_premenu_shown=0
    sam_menu_run sam_premenu
}

sam_caller_ui() {
    [[ "${sam_ui_initialized:-0}" != 1 ]] || return 0
    source "$sam_root/lib/config.sh" || return 1
    source "$sam_root/lib/common.sh" || return 1
    source "$sam_root/lib/modules.sh" || return 1
    source "$sam_root/lib/diagnostics.sh" || return 1
    source "$sam_root/lib/monitor.sh" || return 1
    source "$sam_root/lib/menu.sh" || return 1
    source "$sam_root/lib/dispatch.sh" || return 1
    init_vars
    # UI preferences do not need to parse MiSTer.ini's core-volume paths.
    read_samini --ui || return 1
    init_core_names || return 1
    sam_ui_initialized=1
    sam_exit_trace ui_ready
}

# These menu actions explicitly need runtime services. Loading runtime replaces
# the forwarding function before its second call. Ordinary menus never load it.
sam_enable() { sam_caller_require_runtime || return; sam_enable "$@"; }
sam_disable() { sam_caller_require_runtime || return; sam_disable "$@"; }
sam_rebuild_all_lists() { sam_caller_require_runtime || return; sam_rebuild_all_lists "$@"; }
there_can_be_only_one() { sam_caller_require_runtime || return; there_can_be_only_one "$@"; }
bgm_stop() {
    sam_caller_require_runtime || return
    source "$mrsampath/modules/bgm-functions.sh" || return
    bgm_stop "$@"
}
get_samstuff() {
    source "$mrsampath/lib/downloads.sh" || return
    get_samstuff "$@"
}
curl_download() {
    source "$mrsampath/lib/downloads.sh" || return
    curl_download "$@"
}

sam_caller_dispatch() {
    sam_caller_paths
    case "${1,,}" in
        '') sam_caller_premenu; return $? ;;
        monitor|mcp_monitor)
            source "$sam_root/lib/diagnostics.sh" || return 1
            source "$sam_root/lib/monitor.sh" || return 1
            sam_exit_trace monitor_ready
            if [[ "${1,,}" == monitor ]]; then sam_monitor; else mcp_monitor; fi
            return $? ;;
        help)
            source "$sam_root/lib/menu.sh" || return 1
            sam_help
            return $? ;;
        menu|back|sshconfig|menu_*|startmonitor|sm|bootstart|enable|disable|autoconfig|default|artwork_setup|artwork_refresh)
            ;;
        *)
            # Single-core requests are just messages. The session validates its
            # INI and ROM availability; the caller needs only core IDs/names.
            source "$sam_root/lib/core-names.sh" || return 1
            init_core_names || return 1
            if [[ "${1,,}" =~ ^[a-z0-9_]+$ && -n "${CORE_PRETTY[${1,,}]-}" ]]; then
                local core=${1,,}
                shift
                if [[ -r "$sam_root/lib/controller-client.sh" ]]; then
                    source "$sam_root/lib/controller-client.sh" || return 1
                    local rc=0
                    sam_controller_try start "$core" "$@" || rc=$?
                    ((rc == 125)) || return "$rc"
                fi
                exec python3 "$sam_root/samctl.py" start "$core" "$@"
            fi
            printf 'Unknown SAM command: %s\n' "$1" >&2
            return 1 ;;
    esac
    sam_caller_ui || return 1
    parse_cmd "$@"
}
