#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SAM entry point. Optional modules are loaded once through the registry.
# Copyright (c) 2026 mrchrisster and Mellified; modular refactor 2026.
trap '' HUP
sam_root="${SAM_ROOT:-/media/fat/Scripts/.MiSTer_SAM}"
if [[ ! -r "$sam_root/lib/modules.sh" ]]; then
    [[ -z "${SAM_ROOT:-}" ]] || { echo 'SAM installation is incomplete.' >&2; exit 1; }
    sam_installer=$(mktemp /tmp/sam-install.XXXXXX.py) || exit 1
    sam_release_branch=${SAM_INSTALL_BRANCH:-test}
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
case "${1,,}" in
    update)
        sam_release_branch=${SAM_INSTALL_BRANCH:-test}
        [[ ! -r "$sam_root/release-branch" ]] || read -r sam_release_branch < "$sam_root/release-branch"
        shift
        exec python3 "$sam_root/../MiSTer_SAM_install.py" --download --branch "$sam_release_branch" "$@" ;;
    control) shift; exec python3 "$sam_root/control/samctl.py" "$@" ;;
    status|pause|resume|play) exec python3 "$sam_root/control/samctl.py" "$@" ;;
    next|skip) exec tmux send-keys -t SAM n ;;
esac
source "$sam_root/lib/modules.sh"
source "$sam_root/lib/config.sh"
source "$sam_root/lib/common.sh"
source "$sam_root/lib/state.sh"
source "$sam_root/lib/audio.sh"
source "$sam_root/lib/catalog.sh"
source "$sam_root/lib/filter.sh"
source "$sam_root/lib/launch.sh"
source "$sam_root/lib/lifecycle.sh"
source "$sam_root/lib/catalog-runtime.sh"
source "$sam_root/lib/policy.sh"
source "$sam_root/lib/engine.sh"
source "$sam_root/lib/dispatch.sh"
init_vars
read_samini || exit 1
init_data
init_paths
sam_load_modules || exit 1
[[ "${1:-}" == --source-only ]] || parse_cmd "$@"
