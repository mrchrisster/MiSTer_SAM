# SPDX-License-Identifier: GPL-3.0-or-later
# Modules are trusted installed shell programs, loaded once, only when enabled.
# State/command files are always data and must never be sourced or evaluated.
declare -A SAM_HOOKS=() SAM_SERVICES=() SAM_MODULES=()

sam_register() { # event function
    [[ "$1" =~ ^[a-z_]+$ && "$2" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2
    declare -F "$2" >/dev/null || return 2
    SAM_HOOKS[$1]+=" $2"
}

sam_bind() { # service function
    [[ "$1" =~ ^[a-z_]+$ && "$2" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2
    declare -F "$2" >/dev/null || return 2
    SAM_SERVICES[$1]="$2"
}

sam_emit() { # event [literal arguments]; first failure stops the event
    local event="$1" handler
    shift
    for handler in ${SAM_HOOKS[$event]-}; do
        "$handler" "$@" || return $?
    done
    return 0
}

sam_service() {
    local handler="${SAM_SERVICES[$1]-}"
    shift
    [[ -n "$handler" ]] || return 2
    "$handler" "$@"
}

sam_load_module() {
    local name="$1" file="$mrsampath/modules/$1.sh"
    [[ "$name" =~ ^[a-z][a-z0-9_]*$ ]] || return 2
    [[ -z "${SAM_MODULES[$name]-}" ]] || return 0
    [[ -r "$file" ]] || { echo "SAM: enabled module missing: $name" >&2; return 1; }
    source "$file" || return $?
    SAM_MODULES[$name]=1
}

sam_load_modules() {
    local enabled="${SAM_MODULES_OVERRIDE-auto}" module
    if [[ "$enabled" == auto ]]; then
        enabled="controls"
        [[ ! -f "$mrsamtmp/gameroulette.ini" ]] || enabled+=" roulette"
        [[ "${monitorenable,,}" == yes ]] && enabled+=" monitor"
        [[ "${sam_goat_list,,}" == yes ]] && enabled+=" curated"
        [[ "${Artwork_only,,}" == yes ]] && enabled+=" artwork"
        [[ "${bgm,,}" == yes ]] && enabled+=" bgm"
        [[ "${ttyenable,,}" == yes ]] && enabled+=" tty"
        [[ "${m82,,}" == yes ]] && enabled+=" m82"
        [[ "${samvideo,,}" == yes ]] && enabled+=" video"
    fi
    enabled="${enabled//,/ }"
    if [[ " $enabled " == *" m82 "* && " $enabled " == *" video "* ]]; then
        echo 'SAM: M82 and video modes cannot own the session simultaneously.' >&2
        return 1
    fi
    for module in $enabled; do sam_load_module "$module" || return $?; done
    [[ "${SAM_MODULES_OVERRIDE-auto}" != auto ]] || sam_load_plugins || return $?
    sam_emit config_loaded
}

# Optional installed plug-ins declare a name and their own INI enable switch.
# Manifests are literal data; disabled plug-in implementations are never opened.
sam_load_plugins() {
    local manifest line key value name flag
    for manifest in "$mrsampath/modules.d/"*.module; do
        [[ -f "$manifest" ]] || continue
        name= flag=
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" == *=* ]] || continue
            key="${line%%=*}" value="${line#*=}"
            case "$key" in name) name=$value ;; enabled_by) flag=$value ;; esac
        done < "$manifest"
        [[ "$name" =~ ^[a-z][a-z0-9_]*$ && "$flag" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || {
            printf 'SAM: invalid plug-in manifest: %s\n' "$manifest" >&2; return 1;
        }
        [[ "${!flag}" == [Yy][Ee][Ss] ]] || continue
        sam_load_module "$name" || return $?
    done
}
