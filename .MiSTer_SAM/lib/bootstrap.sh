# SPDX-License-Identifier: GPL-3.0-or-later
# First-game seed work stays in RAM; a seed is never a complete collection.
sam_bootstrap_catalog() { # arcade; 0 ready, 1 no seed, >1 error
    [[ "$1" == arcade && "${SAM_MODE:-ALL}" != SINGLE &&
       "${sam_core_registry_active:-0}" == 1 ]] || return 1
    local rc=0
    sam_core_require arcade || rc=$?
    ((rc == 0)) || return "$rc"
    [[ -e "$sam_session/alive" ]] && sam_session_is_current || return 3
    local seed="$sam_session/bootstrap" old= stamp count complete=1
    local source="$gamelistpath/arcade_gamelist.txt"
    # Reuse a valid filtered cache immediately. Do not validate every system
    # or invoke the full arcade matcher merely to choose the initial core.
    stamp="$(sam_catalog_stamp arcade)" || return 2
    [[ ! -r "$sam_catalog_cache/arcade.stamp" ]] ||
        IFS= read -r -d '' old < "$sam_catalog_cache/arcade.stamp" || true
    if [[ "$old" == "$stamp" && -s "$sam_catalog_cache/arcade.eligible" ]]; then
        read -r count < "$sam_catalog_cache/arcade.count" || return 2
        [[ -f "$gamelistpath/arcade.partial" ]] && complete=0
        if ((complete == 0)); then
            mkdir -p "$seed" || return 2
            cp -- "$sam_catalog_cache/arcade.eligible" "$seed/arcade.eligible" || return 2
        fi
        sam_core_registry_publish arcade ready "$count" "$complete" || return 3
        sam_bootstrap_catalog_source="$sam_catalog_cache/arcade.eligible"
        ((complete)) || sam_bootstrap_catalog_source="$seed/arcade.eligible"
        return 0
    fi
    mkdir -p "$seed/lists/.checked" "$seed/artwork" || return 2
    # Existing master lists provide a random sample without touching ROMs.
    # With no master, bound traversal before shuffling the initial batch.
    if [[ -s "$source" ]]; then
        shuf -n 64 "$source" > "$seed/lists/arcade_gamelist.txt" || return 2
    elif [[ -d "$misterpath/_Arcade" ]]; then
        find "$misterpath/_Arcade" -not -path '*/.*' -type f -iname '*.mra' |
            head -n 64 > "$seed/discovered"
        local statuses=("${PIPESTATUS[@]}")
        (( (statuses[0] == 0 || statuses[0] == 141) && statuses[1] == 0 )) || return 2
        shuf "$seed/discovered" > "$seed/lists/arcade_gamelist.txt" || return 2
    else return 1; fi
    [[ -s "$seed/lists/arcade_gamelist.txt" ]] || return 1
    # All regular filters and module hooks remain in force. The artwork helper
    # gets a private eligibility cache; this subset cannot replace its SD cache.
    local gamelistpathtmp="$seed/lists" tmpfile="$seed/filter" tmpfilefilter="$seed/rating"
    local gamelistpath="$gamelistpath"
    # Candidate-filter hooks require a master for metadata context. Until one
    # exists, the bounded seed is that context; never force a full scan here.
    [[ -f "$source" ]] || gamelistpath="$seed/lists"
    local sam_artwork_eligibility_root="$seed/artwork"
    filter_list arcade || rc=$?
    ((rc == 0)) || return "$rc"
    sam_emit candidate_filter arcade || rc=$?
    ((rc == 0)) || return "$rc"
    [[ -s "$gamelistpathtmp/arcade_gamelist.txt" ]] || return 1
    [[ -e "$sam_session/alive" ]] && sam_session_is_current || return 3
    cp -- "$gamelistpathtmp/arcade_gamelist.txt" "$seed/arcade.eligible.tmp.$BASHPID" &&
        mv -f -- "$seed/arcade.eligible.tmp.$BASHPID" "$seed/arcade.eligible" || return 2
    count=$(wc -l < "$seed/arcade.eligible") || return 2
    sam_core_registry_publish arcade ready "$count" 0 || return 3
    sam_bootstrap_catalog_source="$seed/arcade.eligible"
}
