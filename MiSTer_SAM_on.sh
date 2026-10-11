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
sam_exit_trace backend_entry
# MCP can retry the Menu acknowledgement frequently. This command uses only
# ownership and audio state; it never invokes optional module hooks or gameplay.
if [[ "$sam_gateway_backend" == 1 && "${1,,}" == menu_audio_restore ]]; then
    source "$sam_root/lib/config.sh"
    source "$sam_root/lib/state.sh"
    source "$sam_root/lib/session.sh"
    source "$sam_root/lib/audio.sh"
    source "$sam_root/lib/lifecycle.sh"
    sam_exit_trace libs_loaded
    init_vars
    sam_exit_trace vars_initialized
    read_samini || exit 1
    sam_exit_trace config_loaded
    mkdir -p "$mrsamtmp" || exit 1
    sam_exit_trace paths_initialized
    shift
    sam_exit_trace dispatch
    sam_menu_audio_restore "$@"
    exit $?
fi
source "$sam_root/lib/modules.sh"
source "$sam_root/lib/config.sh"
source "$sam_root/lib/common.sh"
source "$sam_root/lib/diagnostics.sh"
source "$sam_root/lib/cores.sh"
source "$sam_root/lib/state.sh"
source "$sam_root/lib/session.sh"
source "$sam_root/lib/config-reload.sh"
source "$sam_root/lib/audio.sh"
source "$sam_root/lib/catalog.sh"
source "$sam_root/lib/filter.sh"
source "$sam_root/lib/launch.sh"
source "$sam_root/lib/lifecycle.sh"
source "$sam_root/lib/catalog-runtime.sh"
source "$sam_root/lib/policy.sh"
source "$sam_root/lib/engine.sh"
source "$sam_root/lib/dispatch.sh"
sam_exit_trace libs_loaded
init_vars
sam_exit_trace vars_initialized
read_samini || exit 1
sam_exit_trace config_loaded
init_data
sam_exit_trace data_initialized
init_paths
sam_exit_trace paths_initialized
sam_load_modules || exit 1
sam_exit_trace modules_loaded
sam_exit_trace dispatch
[[ "${1:-}" == --source-only ]] || parse_cmd "$@"
