# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

sam_filter_grep() { # output, grep arguments; no matches is a valid empty result
    local output="$1" rc=0 output_fd
    shift
    # Opening output can fail with status 1 too; distinguish that from grep's
    # legitimate no-match status before executing the matcher.
    exec {output_fd}> "$output" || return 2
    grep "$@" >&"$output_fd" || rc=$?
    exec {output_fd}>&- || return 2
    ((rc <= 1)) || return 2
    return 0
}

function filter_list() { # args: core
    local core=${1} rc=0 e count
    local master_list="${gamelistpath}/${core}_gamelist.txt"
    local session_list="${gamelistpathtmp}/${core}_gamelist.txt"

    local flag_dir="${gamelistpathtmp}/.checked"
    mkdir -p "$flag_dir" || return 2
    local flag_file="$flag_dir/$core.filtered"

    if [ -e "$flag_file" ]; then
        samdebug "Filters for '${core}' already applied this session. Skipping."
        return 0
    fi
    local sam_filter_static_blacklist=yes sam_filter_legacy_orientation=yes sam_filter_path=yes
    sam_emit filter_policy "$core" || return 2
    # If a curated session list already exists (built by GOAT, M82, or any other
    # special mode), start from it so filters refine rather than replace it.
    # Otherwise fall back to the full master list.
    if [[ -f "${session_list}" ]]; then
        cp -f "${session_list}" "${tmpfile}" || return 2
    else
        cp -f "${master_list}" "${tmpfile}" || return 2
    fi

    # --- Each filter now reads from $tmpfile and writes its output back to $tmpfile ---
    # --- ALL informational 'echo' commands are redirected to stderr (>&2) ---

    if [[ "$sam_filter_path" == yes ]] && [ -n "${PATHFILTER[${core}]}" ]; then
        echo "Applying path filter for '${core}': ${PATHFILTER[${core}]}" >&2
        sam_filter_grep "${tmpfile}.filtered" -F -- "${PATHFILTER[${core}]}" "${tmpfile}" && mv -f "${tmpfile}.filtered" "${tmpfile}" || return 2
    fi

    if [[ "$sam_filter_legacy_orientation" == yes && "${core}" == "arcade" ]] && [ -n "${arcadeorient}" ]; then
        echo "Applying orientation filter for Arcade: ${arcadeorient}" >&2
        sam_filter_grep "${tmpfile}.filtered" -Fi -- "${arcadeorient}" "${tmpfile}" && mv -f "${tmpfile}.filtered" "${tmpfile}" || return 2
    fi

    if [ "$dupe_mode" = "strict" ]; then
        # samdebug already prints to stderr, so it's safe.
        samdebug "Using strict mode to filter duplicates..."
        awk -F'/' '
        {
            full = $0; lowpath = tolower(full)
            if ( lowpath ~ /\/[^\/]*(hack|beta|proto)[^\/]*\// ) next
            fname = $NF; if ( tolower(fname) ~ /\([^)]*(hack|beta|proto)[^)]*\)/ ) next
            name = fname; sub(/\.[^.]+$/, "", name); sub(/\s*\(.*/, "", name)
            sub(/^([0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?|[0-9]+)[^[:alnum:]]*/, "", name)
            key = tolower(name); gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (!seen[key]++) print full
        }' "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}" || return 2
    else
        awk -F'/' '!seen[$NF]++' "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}" || return 2
    fi
	if [ -s "${blacklistpath}/${core}_gamelist_exclude.txt" ]; then
		echo "Applying category excludelist for '${core}'..." >&2
		awk 'FNR==NR{a[$0];next} !($0 in a)' "${blacklistpath}/${core}_gamelist_exclude.txt" "${tmpfile}" > "${tmpfile}.filtered" && mv -f "${tmpfile}.filtered" "${tmpfile}" || return 2
	else
		samdebug "Excludelist for '${core}' is empty, skipping filter." >&2
	fi
    sam_apply_exclusions "$core" "$tmpfile" || return 2

    if [ "${rating}" != "no" ]; then
        rc=0; apply_ratings_filter "${core}" "${tmpfile}" || rc=$?
        ((rc <= 1)) || return 2
    fi

    if [[ "${exclude[*]}" ]]; then
        for e in "${exclude[@]}"; do
            sam_filter_grep "${tmpfile}.filtered" -viw -- "$e" "${tmpfile}" && mv -f "${tmpfile}.filtered" "${tmpfile}" || return 2
        done
    fi

    if [ "${disable_blacklist}" == "no" ] && [[ "$sam_filter_static_blacklist" == yes ]] && [ -f "${blacklistpath}/${core}_blacklist.txt" ]; then
        if [ -f "${tmpfile}" ]; then
            echo -n "Applying static screen blacklist for '${core}'... " >&2
            awk -v blacklist="${blacklistpath}/${core}_blacklist.txt" '
                BEGIN {while((rc=getline line < blacklist)>0)a[line]=1;close(blacklist);if(rc<0)exit 2}
                {name=$0;sub(/\.[^.]*$/,"",name);sub(/^.*\//,"",name);if(!(name in a))print}
            ' "${tmpfile}" > "${tmpfile}.filtered" &&
                mv -f "${tmpfile}.filtered" "${tmpfile}" || return 2
        else
            samdebug "Warning: '${tmpfile}' missing before blacklist filter."
            return 2
        fi
	else
		 echo -n "No blacklist filter found for '${core}'... " >&2
    fi

    local staged="${session_list}.filtered.$BASHPID"
    cp -f "${tmpfile}" "$staged" && mv -f "$staged" "$session_list" || {
        rm -f -- "$staged"; return 2;
    }
    count=$(wc -l < "$session_list") || return 2
    echo "$count games are now in the active shuffle list." >&2

    if [ ! -s "${session_list}" ]; then
        echo "Error: All filters combined produced an empty list for '${core}'." >&2
        return 1
    fi
	touch "$flag_file" || return 2

    return 0
}

function apply_ratings_filter() { # refine the already filtered candidates only
    local core="$1" target="$2" rated="$ratedpath/${1}_mature.txt"
    [[ -f "$target" ]] || return 2
    if [[ "$rating" == kids ]]; then
        rated="$ratedpath/${core}_rated.txt"
        [[ ! -e "$rated" || -f "$rated" ]] || return 2
        [[ -s "$rated" ]] || { : > "$target" || return 2; return 1; }
        # Match reviewed titles, never directory/franchise substrings. The
        # helper preserves post-deduplication order and rejects altered releases.
        python3 "$mrsampath/sam_kids_filter.py" --list "$target" --ratings "$rated"
        return $?
    else
        [[ -e "$rated" ]] || return 0
        [[ -f "$rated" ]] || return 2
        awk -v rated="$rated" 'BEGIN{while((rc=getline x < rated)>0){sub(/\r$/, "", x);if(length(x))names[++n]=tolower(x)}close(rated);if(rc<0)exit 2}
            $0 !~ /^Demo: / {base=$0;sub(/^.*\//,"",base);sub(/\.[^.]*$/,"",base);base=tolower(base);
                for(i=1;i<=n;i++)if(index(base,names[i])){if(!seen[base]++)print;break}}
        ' "$target" > "$tmpfilefilter" || return 2
    fi
    mv -f "$tmpfilefilter" "$target" || return 2
    [[ -s "$target" ]]
}

function sam_apply_exclusions() { # core, candidate file
    local core="$1" file="$2" exclude_file="${ignorepath}/${1}_excludelist.txt"
    [[ -s "$exclude_file" ]] || return 0
    [[ -f "$exclude_file" && -f "$file" ]] || return 2
    awk -v EXCL="$exclude_file" 'BEGIN{while((rc=getline line<EXCL)>0){raw[line]=1;name=line;sub(/\.[^.]*$/,"",name);sub(/^.*\//,"",name);names[name]=1}close(EXCL);if(rc<0)exit 2}{file=$0;base=file;sub(/\.[^.]*$/,"",base);sub(/^.*\//,"",base);if(file in raw||base in names)next;print}'         "$file" > "${file}.excluded" && mv -f "${file}.excluded" "$file" || return 2
}

function sam_is_excluded() { # core, ROM path (covers previous-game replay)
    local line name base="${2##*/}"
    base="${base%.*}"
    [[ -s "${ignorepath}/${1}_excludelist.txt" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        name="${line##*/}" name="${name%.*}"
        [[ "$line" == "$2" || "$name" == "$base" ]] && return 0
    done < "${ignorepath}/${1}_excludelist.txt"
    return 1
}

function ignoregame() { # optional validated core/path; no arguments preserves CLI
    local cr="$1" cg="$2"
    if [[ -z "$cr" ]]; then
        cr="$(tail -n1 "$sam_game_log" | awk -F- '{print $2}')"
        cg="$(tail -n1 "$sam_game_log" | awk 'BEGIN{FS=OFS="\-"; }{for(i=3;i<NF;i++) printf "%s", $i OFS; print $NF }')"
        cr="${cr// /}" cg="${cg# }"
    fi
    cr="${cr,,}"
    [[ "$cr" =~ ^[a-zA-Z0-9_]+$ && -n "$cg" && "$cg" != *$'\n'* && "$cg" != *$'\r'* ]] || return 1
    mkdir -p "$ignorepath"
    local file="${ignorepath}/${cr}_excludelist.txt"
    # Atomic update of the existing list; the live game stays running on failure.
    { [[ ! -f "$file" ]] || cat "$file"; printf '%s\n' "$cg"; } > "${file}.tmp.$$" && mv -f "${file}.tmp.$$" "$file" || return 1
    # The modular engine keeps candidates in worker-private lists. Its
    # foreground may have no compatibility list to edit; the durable Ignore
    # entry plus cache invalidation remains authoritative for future picks.
    if [[ -f "${gamelistpathtmp}/${cr}_gamelist.txt" ]]; then
        sam_apply_exclusions "$cr" "${gamelistpathtmp}/${cr}_gamelist.txt" || return 1
    fi
    rm -f "${gamelistpathtmp}/.checked/${cr}.filtered"
    echo "$cg added to ${cr}_excludelist.txt"
    echo "To undo, remove its line from $file and restart SAM to rebuild its session list."
}
