# SPDX-License-Identifier: GPL-3.0-or-later
sam_publish_catalog() { # staged complete list, destination; avoid unchanged SD writes
    local source="$1" destination="$2" temporary="$2.tmp.$BASHPID"
    if [[ -f "$destination" ]] && cmp -s "$source" "$destination"; then return 0; fi
    cp "$source" "$temporary" && mv -f "$temporary" "$destination" || {
        rm -f -- "$temporary"; return 2;
    }
}

sam_build_catalog() { # core; private staging, one complete scan
    local c="$1" stage="$sam_job/build-$1" build_func rc partial=0 adapter_empty=0
    mkdir -p "$stage" || return 2
    case "$c" in
        arcade|stv) build_func=build_mra_list ;;
        ao486|x68k|mgls) build_func=build_mgl_list ;;
        amiga)
            rc=0; sam_adapter_paths amiga || rc=$?
            ((rc <= 1)) || return "$rc"
            ((rc == 0)) || adapter_empty=1
            build_func=build_amiga_list ;;
        *) build_func=build_gamelist ;;
    esac
    if [[ "$c" == arcade && "${sam_bootstrap_seed:-1}" == 1 && ! -f "$gamelistpath/arcade_gamelist.txt" && -d "$misterpath/_Arcade" ]]; then
        # head intentionally closes find after the first batch; SIGPIPE is not
        # an index error, but find traversal errors and head write errors are.
        find "$misterpath/_Arcade" -not -path '*/.*' -type f -iname '*.mra' | head -n 64 > "$stage/arcade_gamelist.txt"
        local pipeline_status=("${PIPESTATUS[@]}")
        (( (pipeline_status[0] == 0 || pipeline_status[0] == 141) && pipeline_status[1] == 0 )) || return 2
        partial=1
    else
        rc=0
        # Runtime performs the final sort; standalone callers still sort.
        if ((adapter_empty)); then
            : > "$stage/${c}_gamelist.txt" || return 2
            rc=1
        else
            sam_catalog_runtime_sort=1 "$build_func" "$c" "$stage" || rc=$?
        fi
        ((rc <= 1)) || return "$rc"
        [[ -f "$stage/${c}_gamelist.txt" ]] || return 2
        # Return 1 means a valid empty result, never a partially failed scan.
        ((rc == 0)) || [[ ! -s "$stage/${c}_gamelist.txt" ]] || return 2
    fi
    [[ -f "$stage/${c}_gamelist.txt" ]] || return 2
    sort -u "$stage/${c}_gamelist.txt" -o "$stage/${c}_gamelist.txt" || return 2
    [[ -e "$sam_session/alive" ]] || return 3
    sam_publish_catalog "$stage/${c}_gamelist.txt" "$gamelistpath/${c}_gamelist.txt" || return $?
    if ((partial)); then : > "$gamelistpath/$c.partial" || return 2
    else rm -f "$gamelistpath/$c.partial" || return 2; fi
}

sam_catalog_stamp() { # runs only in preparation, not in the countdown
    stat -c '%n:%s:%y' "$gamelistpath/${1}_gamelist.txt" "$ignorepath/${1}_excludelist.txt" \
        "$blacklistpath/${1}_blacklist.txt" "$blacklistpath/${1}_gamelist_exclude.txt" \
        "$ratedpath/${1}_rated.txt" "$ratedpath/${1}_mature.txt" 2>/dev/null || true
    printf 'settings=%s:%s:%s:%s:%s:%s\n' "$sam_revision" "$rating" "$dupe_mode" "$disable_blacklist" "${exclude[*]}" "${PATHFILTER[$1]}"
    if [[ "$rating" == kids ]]; then
        stat -c '%n:%s:%y' "$mrsampath/sam_kids_filter.py" "$mrsampath/sam_titles.py" || return 2
    fi
    sam_emit filter_stamp "$1"
}

sam_catalog_ready() {
    local c="$1" list="$gamelistpath/${1}_gamelist.txt" stamp old
    [[ -f "$list" ]] || sam_build_catalog "$c" || return $?
    stamp="$(sam_catalog_stamp "$c")" || return 2
    [[ ! -r "$sam_catalog_cache/$c.stamp" ]] || IFS= read -r -d '' old < "$sam_catalog_cache/$c.stamp" || true
    if [[ "$old" == "$stamp" && -f "$sam_catalog_cache/$c.eligible" ]]; then
        [[ -s "$sam_catalog_cache/$c.eligible" ]]; return $?
    fi
    [[ -s "$list" ]] || {
        : > "$sam_catalog_cache/$c.eligible" && printf '0\n' > "$sam_catalog_cache/$c.count" &&
            printf '%s' "$stamp" > "$sam_catalog_cache/$c.stamp" || return 2
        return 1
    }
    mkdir -p "$gamelistpathtmp/.checked" || return 2
    cp "$list" "$gamelistpathtmp/${c}_gamelist.txt" || return 2
    rm -f "$gamelistpathtmp/.checked/$c.filtered"
    local rc=0
    filter_list "$c" || rc=$?
    if ((rc == 0)); then sam_emit candidate_filter "$c" || rc=$?; fi
    ((rc <= 1)) || return "$rc"
    ((rc == 0)) || : > "$gamelistpathtmp/${c}_gamelist.txt" || return 2
    # Keep the inputs we actually filtered. If a list/index changes during the
    # work, the next preparation must see that change and rebuild eligibility.
    cp "$gamelistpathtmp/${c}_gamelist.txt" "$sam_catalog_cache/$c.eligible.tmp.$BASHPID" &&
        mv -f "$sam_catalog_cache/$c.eligible.tmp.$BASHPID" "$sam_catalog_cache/$c.eligible" || return 2
    wc -l < "$sam_catalog_cache/$c.eligible" > "$sam_catalog_cache/$c.count" || return 2
    printf '%s' "$stamp" > "$sam_catalog_cache/$c.stamp" || return 2
    [[ -s "$sam_catalog_cache/$c.eligible" ]]
}

sam_catalog_background_scan() {
    local c="$1" rc=0
    sam_bootstrap_seed=0
    sam_build_catalog "$c" || rc=$?
    # Record failures as attempts too; preparation receives the error instead
    # of silently rescanning the same incomplete core at every timer tick.
    : > "$sam_session/scanned-$c" || return 2
    ((rc <= 1)) || return "$rc"
    return 0
}

sam_catalog_background_step() {
    local c
    # Finish missing/partial lists before optional collection refreshes.
    for c in "${corelist[@]}"; do
        [[ ! -f "$sam_session/scanned-$c" ]] || continue
        if [[ ! -f "$gamelistpath/${c}_gamelist.txt" || -f "$gamelistpath/$c.partial" ]]; then
            sam_catalog_background_scan "$c"; return $?
        fi
    done
    if [[ "${check_for_new_games,,}" == yes ]]; then
        for c in "${corelist[@]}"; do
            [[ ! -f "$sam_session/scanned-$c" ]] || continue
            sam_catalog_background_scan "$c"; return $?
        done
    fi
    return 0
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
                report="$("$mrsampath/samindex" -q -s amiga -d)" || return 2
                [[ -n "$report" ]] || return 1
                [[ "$report" == amiga:* ]] || return 2
                amigapath="${report#*:}" amigapath="${amigapath# }"
                amigacore="$(find "$misterpath/_Computer" -iname '*minimig*' -print -quit)"
            fi ;;
    esac
}
