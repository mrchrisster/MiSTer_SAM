# SPDX-License-Identifier: GPL-3.0-or-later
# Selectors return proposals; the foreground engine commits policy state.
sam_mode=normal

sam_random_below() { # rejection sampling; no shuf/date subprocess for small picks
    local bound="$1" random limit
    (( bound > 0 && bound <= 1073741824 )) || return 1
    limit=$((1073741824 / bound * bound))
    while :; do
        random=$(( (RANDOM << 15) | RANDOM ))
        (( random < limit )) && break
    done
    sam_random=$((random % bound))
}

sam_normal_choose_core() {
    local candidates=() c count total=0 weight random
    if [[ "$SAM_MODE" == SINGLE ]]; then nextcore="$SAM_TARGET_CORE"; return 0; fi
    for c in "${corelisttmp[@]}"; do
        sam_emit core_allowed "$c" || continue
        candidates+=("$c")
    done
    (( ${#candidates[@]} )) || candidates=("${corelist[@]}")
    (( ${#candidates[@]} )) || return 1
    if [[ "${sam_bootstrap:-0}" == 1 ]]; then
        for c in "${candidates[@]}"; do
            [[ "$c" == arcade ]] && { nextcore=arcade; sam_bootstrap=0; return 0; }
        done
        sam_bootstrap=0
    fi
    if [[ "${coreweight,,}" == yes ]]; then
        # Counts are persisted with filtered catalogs. Missing collections are
        # prepared by the single background job, never by the foreground timer.
        local -A weights=()
        for c in "${candidates[@]}"; do
            sam_catalog_ready "$c" || continue
            read -r count < "$sam_catalog_cache/$c.count" || count=0
            [[ "$count" =~ ^[0-9]+$ ]] || count=0
            weights[$c]=$count; total=$((total + count))
        done
        if (( total > 0 )); then
            sam_random_below "$total" || return 1; random=$sam_random
            for c in "${candidates[@]}"; do
                weight=${weights[$c]:-0}
                if (( random < weight )); then nextcore=$c; return 0; fi
                random=$((random - weight))
            done
        fi
    fi
    sam_random_below "${#candidates[@]}" || return 1
    nextcore="${candidates[$sam_random]}"
}

sam_normal_pick() {
    local c="$1" source="$sam_catalog_cache/$1.eligible" candidate_file="$sam_job/candidates" path
    sam_catalog_ready "$c" || return $?
    if [[ "${norepeat,,}" != yes ]]; then
        sam_candidate_reset=no
        IFS= read -r rompath < <(shuf -n 1 "$source")
        [[ -n "$rompath" ]]
        return $?
    fi
    # Match literal complete paths. Reserved queue entries and committed history
    # are excluded together; no source list is rewritten for each random pick.
    awk 'FILENAME!=ARGV[ARGC-1]{if(length($0))seen[$0]=1;next} !($0 in seen)' \
        "$sam_session/consumed/$c" "$sam_job/reserved-$c" "$source" > "$candidate_file"
    if [[ ! -s "$candidate_file" ]]; then
        # A cycle is reset on commit, not speculatively. Record that decision.
        cp "$source" "$candidate_file"
        sam_candidate_reset=yes
        if [[ -s "$sam_job/reserved-$c" ]]; then
            awk 'NR==FNR{a[$0];next}!($0 in a)' "$sam_job/reserved-$c" "$source" > "$candidate_file"
        fi
    else sam_candidate_reset=no; fi
    [[ -s "$candidate_file" ]] || return 1
    IFS= read -r rompath < <(shuf -n 1 "$candidate_file")
    [[ -n "$rompath" ]]
}

sam_normal_commit() { # core path reset-cycle
    local c="$1"
    if [[ "${norepeat,,}" == yes ]]; then
        [[ "$3" != yes ]] || : > "$sam_session/consumed/$c"
        printf '%s\n' "$2" >> "$sam_session/consumed/$c"
    fi
    delete_from_corelist "$c" tmp
    (( ${#corelisttmp[@]} )) || corelisttmp=("${corelist[@]}")
}

sam_normal_key() { return 1; }
sam_normal_timer_begin() { :; }
sam_normal_timer_tick() { :; }
sam_bind choose_core sam_normal_choose_core
sam_bind pick_candidate sam_normal_pick
sam_bind commit sam_normal_commit
sam_bind mode_key sam_normal_key
sam_bind timer_begin sam_normal_timer_begin
sam_bind timer_tick sam_normal_timer_tick
