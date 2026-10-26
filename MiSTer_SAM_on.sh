#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SAM entry point. Optional modules are loaded once through the registry.
# Copyright (c) 2026 mrchrisster and Mellified; modular refactor 2026.
trap '' HUP
# Optional RAM-file diagnostics: all timestamps are shell builtins so measuring
# startup does not add date processes to the Menu return path.
sam_exit_trace() {
    [[ -n "${SAM_EXIT_TRACE:-}" ]] || return 0
    local stamp=${EPOCHREALTIME:-}
    [[ -n "$stamp" ]] || printf -v stamp '%(%s)T' -1
    printf '%s %s pid=%s\n' "$stamp" "$1" "$BASHPID" 2>/dev/null >> "$SAM_EXIT_TRACE" || true
}
sam_exit_trace entry
sam_root="${SAM_ROOT:-/media/fat/Scripts/.MiSTer_SAM}"
if [[ "${1:-}" == --engine-hosted-adapter ]]; then
    source "$sam_root/lib/engine-adapter.sh" || exit 1
    source "$sam_root/lib/engine-hosted.sh" || exit 1
    sam_engine_hosted_parent_valid || { echo 'SAM: invalid hosted adapter controller.' >&2; exit 64; }
    exec 3>&1
    exec 1>&2
    trap 'sam_engine_stop_pending=1' USR1
    # Cover blocking configuration helpers too. The same guardian switches to
    # guarded session cleanup once the unique adapter owner is published.
    source "$sam_root/lib/state.sh" || exit 1
    sam_engine_guardian_preflight_begin || exit 1
    trap 'sam_engine_guardian_preflight_exit "$?"' EXIT
    shift
    source "$sam_root/lib/runtime.sh" || exit 1
    sam_load_runtime || exit 1
    sam_engine_adapter_main "${1:-}"
    exit $?
fi
if [[ "${1:-}" == --engine-adapter ]]; then
    source "$sam_root/lib/engine-adapter.sh" || exit 1
    sam_engine_parent_valid || { echo 'SAM: invalid session adapter owner.' >&2; exit 64; }
    exec 3>&1
    exec 1>&2
    trap 'sam_engine_stop_pending=1' USR1
    shift
    source "$sam_root/lib/runtime.sh" || exit 1
    sam_load_runtime || exit 1
    sam_engine_adapter_main "${1:-}"
    exit $?
fi
if [[ "${1,,}" == loop_core && "${SAM_ENGINE:-python}" != legacy ]]; then
    shift
    exec python3 -S "$sam_root/sam/session_engine.py" --root "$sam_root" \
        --entry "${SAM_ENTRY:-${BASH_SOURCE[0]}}" --target "${1:-}"
fi
if [[ "${1,,}" == diagnostics ]]; then
    [[ -r "$sam_root/sam/diagnostics.py" ]] || { echo 'Diagnostics tool is missing; reinstall SAM.' >&2; exit 1; }
    shift
    exec python3 "$sam_root/sam/diagnostics.py" --runtime "${SAM_TMP_ROOT:-/tmp/.SAM_tmp}" "$@"
fi
if [[ ! -r "$sam_root/lib/modules.sh" || ! -r "$sam_root/lib/cores.sh" || ! -r "$sam_root/lib/diagnostics.sh" ]]; then
    [[ -z "${SAM_ROOT:-}" ]] || { echo 'SAM installation is incomplete.' >&2; exit 1; }
    sam_installer=$(mktemp /tmp/sam-install.XXXXXX.py) || exit 1
    sam_release_branch=${SAM_INSTALL_BRANCH:-test}
    if [[ -z "${CURL_CA_BUNDLE:-}" ]]; then
        for sam_ca_bundle in /media/fat/Scripts/.config/downloader/cacert.pem /etc/ssl/cert.pem /etc/ssl/certs/cacert.pem; do
            if [[ -r "$sam_ca_bundle" && -f "$sam_ca_bundle" ]]; then
                export CURL_CA_BUNDLE="$sam_ca_bundle"
                break
            fi
        done
    fi
    curl --fail --location --connect-timeout 15 --max-time 60 \
        -o "$sam_installer" "https://raw.githubusercontent.com/mrchrisster/MiSTer_SAM/$sam_release_branch/MiSTer_SAM_install.py" || { rm -f "$sam_installer"; exit 1; }
    python3 "$sam_installer" --download --branch "$sam_release_branch"
    sam_install_result=$?
    rm -f "$sam_installer"
    ((sam_install_result == 0)) || exit "$sam_install_result"
    exec bash /media/fat/Scripts/MiSTer_SAM_on.sh "$@"
fi
# Short command path: external programs never parse the engine/core tables merely
# to submit a command. The active session owns validation and acceptance.
sam_gateway_backend=0
if [[ "${1:-}" == --gateway-backend ]]; then
    sam_gateway_backend=1
    shift
fi
case "${1,,}" in
    start|restart|next|previous|mute|m82_play|pause|resume|play|ignore|stop|kill|exit_to_menu|exit_to_game)
        # The tracked MCP Start launcher uses --gateway-backend too. Other
        # backend actions deliberately keep their existing implementation so
        # the resident controller's legacy gateway cannot recurse into itself.
        if [[ "$sam_gateway_backend" != 1 || "${1,,}" == start || "${1,,}" == restart ]]; then
            if [[ -r "$sam_root/lib/controller-client.sh" ]]; then
                source "$sam_root/lib/controller-client.sh" || exit 1
                sam_controller_result=0
                sam_controller_try "$@" || sam_controller_result=$?
                ((sam_controller_result == 125)) || exit "$sam_controller_result"
            fi
        fi ;;
esac
case "${1,,}" in
    update)
        sam_release_branch=${SAM_INSTALL_BRANCH:-test}
        [[ ! -r "$sam_root/release-branch" ]] || read -r sam_release_branch < "$sam_root/release-branch"
        shift
        exec python3 "$sam_root/../MiSTer_SAM_install.py" --download --branch "$sam_release_branch" "$@" ;;
    control|status|pause|resume|play|next|skip|previous|mute|m82_play|start|restart|stop|kill|stop_owner|exit_to_game|exit_to_menu|exit_to_menu_fast|menu_audio_restore|unmute|ignore)
        if [[ "$sam_gateway_backend" != 1 ]]; then
            exec python3 "$sam_root/samctl.py" "$@"
        fi ;;
esac
if [[ "$sam_gateway_backend" == 1 || "${1:-}" == --source-only || "${1,,}" == loop_core || "${1,,}" == validate_start ]]; then
    source "$sam_root/lib/runtime.sh" || exit 1
    sam_runtime_dispatch "$@"
else
    source "$sam_root/lib/caller.sh" || exit 1
    sam_caller_dispatch "$@"
fi
