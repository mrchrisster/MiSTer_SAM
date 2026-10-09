# SPDX-License-Identifier: GPL-3.0-or-later
sam_build_catalog() { # core; private staging, one complete scan
    local c="$1" stage="$sam_job/build-$1" build_func rc
    mkdir -p "$stage"
    case "$c" in
        arcade|stv) build_func=build_mra_list ;;
        ao486|x68k|mgls) build_func=build_mgl_list ;;
        amiga) sam_adapter_paths amiga || return 1; build_func=build_amiga_list ;;
        *) build_func=build_gamelist ;;
    esac
    if [[ "$c" == arcade && "${sam_bootstrap_seed:-1}" == 1 && ! -f "$gamelistpath/arcade_gamelist.txt" && -d "$misterpath/_Arcade" ]]; then
        # A small first batch is eligible only after the same normal filters.
        find "$misterpath/_Arcade" -not -path '*/.*' -type f -iname '*.mra' | head -n 64 > "$stage/arcade_gamelist.txt"
        : > "$gamelistpath/arcade.partial"
    else
        rc=0
        "$build_func" "$c" "$stage" || rc=$?
        # A failed generic scan may have preserved an older staging file. Never
        # publish it as the result of this request or remove partial markers.
        if [[ "$build_func" == build_gamelist ]] && ((rc != 0)); then return "$rc"; fi
        ((rc == 0)) || [[ -f "$stage/${c}_gamelist.txt" ]] || return "$rc"
        rm -f "$gamelistpath/$c.partial"
    fi
    [[ -f "$stage/${c}_gamelist.txt" ]] || return 1
    sort -u "$stage/${c}_gamelist.txt" -o "$stage/${c}_gamelist.txt" || return 1
    [[ -e "$sam_session/alive" ]] || return 1
    # Same-filesystem temporary publication prevents readers seeing partial data.
    cp "$stage/${c}_gamelist.txt" "$gamelistpath/$c.tmp.$BASHPID" &&
        mv -f "$gamelistpath/$c.tmp.$BASHPID" "$gamelistpath/${c}_gamelist.txt"
}

sam_catalog_stamp() { # runs only in preparation, not in the countdown
    stat -c '%n:%s:%y' "$gamelistpath/${1}_gamelist.txt" "$ignorepath/${1}_excludelist.txt" \
        "$blacklistpath/${1}_blacklist.txt" "$blacklistpath/${1}_gamelist_exclude.txt" \
        "$ratedpath/${1}_rated.txt" "$ratedpath/${1}_mature.txt" 2>/dev/null || true
    printf 'settings=%s:%s:%s:%s:%s:%s\n' "$sam_revision" "$rating" "$dupe_mode" "$disable_blacklist" "${exclude[*]}" "${PATHFILTER[$1]}"
    sam_emit filter_stamp "$1"
}

sam_catalog_ready() {
    local c="$1" list="$gamelistpath/${1}_gamelist.txt" stamp old
    [[ -f "$list" ]] || sam_build_catalog "$c" || return $?
    stamp="$(sam_catalog_stamp "$c")"
    [[ ! -r "$sam_catalog_cache/$c.stamp" ]] || IFS= read -r -d '' old < "$sam_catalog_cache/$c.stamp" || true
    if [[ "$old" == "$stamp" && -f "$sam_catalog_cache/$c.eligible" ]]; then
        [[ -s "$sam_catalog_cache/$c.eligible" ]]; return $?
    fi
    [[ -s "$list" ]] || { : > "$sam_catalog_cache/$c.eligible"; printf '%s' "$stamp" > "$sam_catalog_cache/$c.stamp"; return 1; }
    mkdir -p "$gamelistpathtmp/.checked"
    cp "$list" "$gamelistpathtmp/${c}_gamelist.txt" || return 1
    rm -f "$gamelistpathtmp/.checked/$c.filtered"
    local rc=0
    filter_list "$c" || rc=$?
    if ((rc == 0)); then sam_emit candidate_filter "$c" || rc=$?; fi
    ((rc != 3)) || return 3
    ((rc == 0)) || : > "$gamelistpathtmp/${c}_gamelist.txt"
    cp "$gamelistpathtmp/${c}_gamelist.txt" "$sam_catalog_cache/$c.eligible.tmp.$BASHPID" &&
        mv -f "$sam_catalog_cache/$c.eligible.tmp.$BASHPID" "$sam_catalog_cache/$c.eligible" || return 1
    wc -l < "$sam_catalog_cache/$c.eligible" > "$sam_catalog_cache/$c.count"
    printf '%s' "$(sam_catalog_stamp "$c")" > "$sam_catalog_cache/$c.stamp"
    [[ -s "$sam_catalog_cache/$c.eligible" ]]
}

sam_catalog_background_step() {
    local c
    for c in "${corelist[@]}"; do
        if [[ ! -f "$gamelistpath/${c}_gamelist.txt" || -f "$gamelistpath/$c.partial" ]]; then
            sam_bootstrap_seed=0
            sam_build_catalog "$c"
            : > "$sam_session/scanned-$c"
            return $?
        fi
    done
    if [[ "${check_for_new_games,,}" == yes ]]; then
        for c in "${corelist[@]}"; do
            [[ ! -f "$sam_session/scanned-$c" ]] || continue
            sam_bootstrap_seed=0
            sam_build_catalog "$c"
            : > "$sam_session/scanned-$c"
            return $?
        done
    fi
}

sam_catalog_pending() {
    local c
    for c in "${corelist[@]}"; do
        [[ -f "$gamelistpath/${c}_gamelist.txt" && ! -f "$gamelistpath/$c.partial" ]] || return 0
        if [[ "${check_for_new_games,,}" == yes && ! -f "$sam_session/scanned-$c" ]]; then return 0; fi
    done
    return 1
}

sam_adapter_paths() {
    case "$1" in
        amiga)
            if [[ -z "${amigapath:-}" ]]; then
                local report
                report="$("$mrsampath/samindex" -q -s amiga -d)" || return 1
                amigapath="${report#*:}" amigapath="${amigapath# }"
                amigacore="$(find "$misterpath/_Computer" -iname '*minimig*' -print -quit)"
            fi ;;
    esac
}
