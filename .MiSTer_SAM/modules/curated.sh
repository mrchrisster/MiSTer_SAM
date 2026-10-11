# SPDX-License-Identifier: GPL-3.0-or-later
sam_goat_list=yes
declare -gA SAM_CURATED_CORES=()
sam_curated_cores_loaded=0
sam_curated_core_allowed() {
    [[ "${2:-candidate}" != auxiliary ]] || return 0
    if ((sam_curated_cores_loaded == 0)); then
        local source="$gamelistpath/sam_goat_list_custom.txt" line section=
        [[ -r "$source" ]] || source="$gamelistpath/sam_goat_list.txt"
        [[ -r "$source" ]] || { sam_core_reason='GOAT list is missing'; return 2; }
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=${line%$'\r'}
            if [[ "$line" =~ ^\[(.+)\]$ ]]; then section="${BASH_REMATCH[1],,}"
            elif [[ "$section" =~ ^[a-z0-9_]+$ && -n "$line" && "$line" != \#* ]]; then
                SAM_CURATED_CORES[$section]=1
            fi
        done < "$source"
        sam_curated_cores_loaded=1
    fi
    [[ -n "${SAM_CURATED_CORES[$1]-}" ]] && return 0
    sam_core_reason="GOAT list has no entries for $1"
    return 1
}
sam_register core_allowed sam_curated_core_allowed
sam_curated_filter() {
    local c="$1" list="$gamelistpathtmp/${1}_gamelist.txt" names="${sam_job:-$mrsamtmp}/curated-names" line section=
    local source="$gamelistpath/sam_goat_list_custom.txt"
    [[ -r "$source" ]] || source="$gamelistpath/sam_goat_list.txt"
    [[ -r "$source" ]] || { echo 'SAM: curated list is missing.' >&2; return 1; }
    : > "$names"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then section="${BASH_REMATCH[1],,}"
        elif [[ "$section" == "$c" && -n "$line" ]]; then printf '%s\n' "$line" >> "$names"; fi
    done < "$source"
    awk -v core="$c" 'FILENAME==ARGV[1]{names[++n]=tolower($0);next}
        {p[++m]=$0;low[m]=tolower($0)}
        END{for(i=1;i<=n;i++){first=usa=japan=world=canonical="";
            for(j=1;j<=m;j++)if(index(low[j],names[i])){
                if(first=="")first=p[j];
                if(canonical==""&&low[j]!~/_alternatives/)canonical=p[j];
                if(usa==""&&index(low[j],"(usa"))usa=p[j];
                if(japan==""&&index(low[j],"(japan"))japan=p[j];
                if(world==""&&index(low[j],"(world"))world=p[j];}
            chosen=(core=="arcade"&&canonical!="")?canonical:(usa!=""?usa:(japan!=""?japan:(world!=""?world:first)));
            if(chosen!=""&&!seen[chosen]++)print chosen}}
        ' "$names" "$list" > "$list.curated" && mv "$list.curated" "$list"
    [[ -s "$list" ]]
}
sam_register candidate_filter sam_curated_filter
sam_curated_stamp() {
    stat -c '%n:%s:%y' "$gamelistpath/sam_goat_list_custom.txt" "$gamelistpath/sam_goat_list.txt" 2>/dev/null || true
}
sam_register filter_stamp sam_curated_stamp
