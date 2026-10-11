# SPDX-License-Identifier: GPL-3.0-or-later
# Small transition records in RAM; no timer/input sampling or SD log writes.
sam_diagnostic_directory() {
    local root=${mrsamtmp:-${SAM_TMP_ROOT:-/tmp/.SAM_tmp}} resolved
    if [[ "${sam_diag_root:-}" == "$root" && -d "${sam_diag_dir:-}" && ! -L "$sam_diag_dir" ]]; then return 0; fi
    [[ "$root" == /tmp/* ]] || return 1
    resolved=$(readlink -f -- "$root") || return 1
    [[ "$resolved" == /tmp/* ]] || return 1
    sam_diag_root=$root sam_diag_dir="$resolved/diagnostics"
    [[ ! -L "$sam_diag_dir" ]] || return 1
    mkdir -p -m 700 -- "$sam_diag_dir" || return 1
}

sam_diagnostic_quote() {
    local LC_ALL=C value=${1:-}
    value=${value:0:768}
    value=${value//\\/\\\\}; value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}; value=${value//$'\r'/\\r}; value=${value//$'\t'/\\t}
    value=${value//[[:cntrl:]]/?}
    sam_diag_quoted="\"$value\""
}

sam_diagnostic_append() {
    local record=${1:-} prefix=${2:-events} fd size=0 file suffix=jsonl LC_ALL=C
    [[ "$prefix" == events || "$prefix" == debug ]] || return 0
    [[ "$prefix" != debug ]] || suffix=log
    (( ${#record} < 4096 )) || return 0
    sam_diagnostic_directory || return 0
    [[ ! -L "$sam_diag_dir/events.lock" && ! -L "$sam_diag_dir/$prefix.$suffix" && ! -L "$sam_diag_dir/$prefix.1.$suffix" ]] || return 0
    exec {fd}> "$sam_diag_dir/events.lock" || return 0
    if ! flock -n "$fd"; then exec {fd}>&-; return 0; fi
    file="$sam_diag_dir/$prefix.$suffix"
    [[ ! -e "$file" || -f "$file" ]] || { exec {fd}>&-; return 0; }
    [[ ! -f "$file" ]] || size=$(stat -c %s -- "$file") || size=0
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    if ((size > 131072)); then : > "$file" || { exec {fd}>&-; return 0; }; size=0; fi
    if ((size + ${#record} + 1 > 131072)); then
        mv -f -- "$file" "$sam_diag_dir/$prefix.1.$suffix" || { exec {fd}>&-; return 0; }
    fi
    printf '%s\n' "$record" >> "$file" || true
    # Synchronous helpers have exited; closing this final descriptor releases
    # the kernel lock without spawning another process.
    exec {fd}>&-
    return 0
}

sam_diagnostic() { # event, detail, optional captured owner/component
    local event=${1:-unknown} owner detail=${2:-} component stamp=${EPOCHSECONDS:-0} record LC_ALL=C
    sam_diagnostic_quote "${event:0:64}"; event=$sam_diag_quoted
    owner=${3:-${sam_owner:-}}; sam_diagnostic_quote "${owner:0:64}"; owner=$sam_diag_quoted
    sam_diagnostic_quote "${detail:0:512}"; detail=$sam_diag_quoted
    component=${4:-sam}; sam_diagnostic_quote "${component:0:32}"; component=$sam_diag_quoted
    printf -v record '{"timestamp":%s,"component":%s,"event":%s,"owner":%s,"fields":{"detail":%s}}' "$stamp" "$component" "$event" "$owner" "$detail"
    sam_diagnostic_append "$record" || true
    return 0
} 2>/dev/null

sam_diagnostic_exit() { # status, reason, cleanup status, captured phase/core/game/ROM
    local status=$1 cleanup=$3 reason phase core game rom mode owner record temporary LC_ALL=C
    [[ "$status:$cleanup" =~ ^[0-9]+:[0-9]+$ ]] || return 0
    [[ "${sam_owner:-}" =~ ^[1-9][0-9]{0,9}:[0-9]{1,20}$ ]] || return 0
    sam_diagnostic_directory || return 0
    sam_diagnostic_quote "${2:0:256}"; reason=$sam_diag_quoted
    sam_diagnostic_quote "${4:0:32}"; phase=$sam_diag_quoted
    sam_diagnostic_quote "${5:0:32}"; core=$sam_diag_quoted
    sam_diagnostic_quote "${6:0:256}"; game=$sam_diag_quoted
    sam_diagnostic_quote "$7"; rom=$sam_diag_quoted
    mode=${sam_mode:-${SAM_MODE:-}}; sam_diagnostic_quote "${mode:0:32}"; mode=$sam_diag_quoted
    sam_diagnostic_quote "$sam_owner"; owner=$sam_diag_quoted
    printf -v record '{"timestamp":%s,"component":"sam","event":"session_exit","owner":%s,"fields":{"status":%s,"cleanup_status":%s,"reason":%s,"phase":%s,"mode":%s,"core":%s,"game":%s,"rom_path":%s}}' \
        "${EPOCHSECONDS:-0}" "$owner" "$status" "$cleanup" "$reason" "$phase" "$mode" "$core" "$game" "$rom"
    temporary="$sam_diag_dir/.exit.$sam_owner.tmp"
    if printf '%s\n' "$record" > "$temporary"; then
        chmod 600 "$temporary" || true
        mv -f -- "$temporary" "$sam_diag_dir/last-exit.json" || true
        if ((status != 0 || cleanup != 0)); then
            printf '%s\n' "$record" > "$temporary" && mv -f -- "$temporary" "$sam_diag_dir/last-failure.json" || true
        fi
    fi
    rm -f -- "$temporary"
    sam_diagnostic_append "$record" || true
    return 0
} 2>/dev/null

sam_diagnostic_debug() {
    local LC_ALL=C line=${1:-}
    line=${line:0:2048}
    line=${line//[[:cntrl:]]/?}
    sam_diagnostic_append "$line" debug || true
    return 0
} 2>/dev/null
