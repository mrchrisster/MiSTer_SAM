# SPDX-License-Identifier: GPL-3.0-or-later
# Category policy is applied only to preparation lists, never the collection.
sam_category_valid() {
    case "$1" in off|pinball|arcade_horizontal|arcade_vertical|shmups|fighting|puzzle|racing) return 0;; *) return 1;; esac
}

sam_category_tags_valid() {
    local tag
    local -a tags=()
    IFS=, read -ra tags <<< "$1"
    for tag in "${tags[@]}"; do
        case "${tag,,}" in beta|hack|homebrew|prototype|unlicensed|translations|usa|japan|europe|'') ;;
            *) return 1;; esac
    done
    return 0
}

sam_category_read_scope() {
    local line key value preset= boot= current_boot= exclusions= have_exclusions=0
    sam_category_preset=${category_preset:-off}
    sam_category_scope=permanent
    sam_category_exclusions=
    sam_category_valid "$sam_category_preset" || { echo 'SAM: invalid category_preset.' >&2; return 2; }
    if [[ -r "$gamelistpath/.excludetags" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] || continue
            sam_category_tags_valid "$line" || { echo 'SAM: invalid legacy category exclusion tag.' >&2; return 2; }
            sam_category_exclusions+="${sam_category_exclusions:+,}${line,,}"
        done < "$gamelistpath/.excludetags"
    fi
    [[ -r "${SAM_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}" ]] &&
        IFS= read -r current_boot < "${SAM_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
    if [[ -r "$mrsamtmp/category-preset" ]]; then
        while IFS= read -r line; do
            key=${line%%=*} value=${line#*=}
            case "$key" in preset) preset=$value;; boot_id) boot=$value;; exclude_tags) exclusions=$value; have_exclusions=1;; esac
        done < "$mrsamtmp/category-preset"
        if [[ -n "$current_boot" && "$boot" == "$current_boot" ]]; then
            sam_category_valid "$preset" || { echo 'SAM: invalid temporary category preset.' >&2; return 2; }
            sam_category_preset=$preset
            sam_category_scope=reboot
            if ((have_exclusions)); then
                sam_category_tags_valid "$exclusions" || { echo 'SAM: invalid temporary category exclusion tag.' >&2; return 2; }
                sam_category_exclusions=${exclusions,,}
            fi
        fi
    fi
    return 0
}

sam_category_save() { # preset permanent|reboot; trusted menu enum only
    sam_category_store "$1" "${sam_category_exclusions:-}" "$2"
}

sam_category_store() { # preset, literal comma-separated exclusion tags, scope
    sam_category_valid "$1" && sam_category_tags_valid "$2" || return 2
    local boot= temporary="$mrsamtmp/category-preset.tmp.$BASHPID" tag tags_temp="$gamelistpath/.excludetags.tmp.$BASHPID"
    local -a tags=()
    case "$3" in
        permanent)
            mkdir -p "$gamelistpath" || return 1
            IFS=, read -ra tags <<< "$2"
            printf '%s\n' "${tags[@]}" > "$tags_temp" && mv -f "$tags_temp" "$gamelistpath/.excludetags" || return 1
            samini_mod category_preset "$1" "$samini_file" || return 1
            rm -f "$mrsamtmp/category-preset" || return 1
            category_preset=$1 ;;
        reboot)
            IFS= read -r boot < "${SAM_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}" || return 1
            [[ -n "$boot" ]] || return 1
            mkdir -p "$mrsamtmp" || return 1
            printf 'boot_id=%s\npreset=%s\nexclude_tags=%s\n' "$boot" "$1" "$2" > "$temporary" &&
                mv -f "$temporary" "$mrsamtmp/category-preset" || return 1 ;;
        *) return 2 ;;
    esac
    sam_module_config_dirty=1
    sam_category_read_scope
}

sam_category_core_allowed() {
    [[ "$sam_category_preset" != off ]] || return 0
    if [[ "${2:-candidate}" == auxiliary ]]; then
        sam_core_reason='Category presets require normal or roulette game mode'; return 1
    fi
    case "$sam_category_preset" in
        arcade_*) [[ "$1" == arcade ]] || { sam_core_reason='This category contains arcade games only'; return 1; } ;;
    esac
    return 0
}

sam_category_filter() {
    [[ "$sam_category_preset" != off || -n "$sam_category_exclusions" ]] || return 0
    local list="$gamelistpathtmp/${1}_gamelist.txt" output="$gamelistpathtmp/${1}.category.$BASHPID" rc=0
    python3 "$mrsampath/modules/category_filter.py" --core "$1" --preset "$sam_category_preset" \
        --list "$list" --master "$gamelistpath/${1}_gamelist.txt" \
        --aliases "$mrsampath/modules/category-aliases.json" --exclude-tags "$sam_category_exclusions" --output "$output" || rc=$?
    ((rc <= 1)) || { rm -f "$output"; return 2; }
    mv -f "$output" "$list" || return 2
    return "$rc"
}

sam_category_stamp() {
    printf 'category=%s:exclude=%s\n' "$sam_category_preset" "$sam_category_exclusions"
    stat -c '%n:%s:%y' "$gamelistpath/.excludetags" 2>/dev/null || true
    if [[ "$sam_category_preset" != off || -n "$sam_category_exclusions" ]]; then
        stat -c '%n:%s:%y' "$mrsampath/modules/category-aliases.json" \
            "$mrsampath/modules/category_filter.py" "$mrsampath/sam_titles.py"
    fi
    if [[ "$sam_category_preset" == arcade_* ]]; then
        if [[ -n "${SAM_ARCADE_ORGANIZER_DATA:-}" ]]; then
            printf 'organizer=%s\n' "$SAM_ARCADE_ORGANIZER_DATA"
            stat -c '%n:%s:%y' "$SAM_ARCADE_ORGANIZER_DATA" 2>/dev/null || true
        else
            stat -c '%n:%s:%y' "$misterpath/Scripts/.config/arcade-organizer/data.zip" \
                "$misterpath/Scripts/.cache/arcade-organizer/data.zip" 2>/dev/null || true
        fi
    fi
    return 0
}

sam_category_prepare_candidate() {
    [[ "$sam_category_preset" == arcade_* ]] || return 0
    [[ "$1" == arcade ]] || return 1
    # Index/folder/seed eligibility never authorizes the wrong actual core.
    # Read exactly the proposed MRA's bounded header before artwork preparation.
    python3 "$mrsampath/modules/category_filter.py" --core "$1" --preset "$sam_category_preset" --check-orientation "$2"
}

sam_category_filter_policy() {
    # Static pinball tables are useful attract content. This does not bypass
    # Kids, Ignore, category exclusions or artwork eligibility.
    [[ "$sam_category_preset" != pinball ]] || sam_filter_static_blacklist=no
    if [[ "$1" == arcade && "$sam_category_preset" == arcade_* ]]; then
        sam_filter_legacy_orientation=no
        case "${PATHFILTER[arcade],,}" in _horizontal|_vertical) sam_filter_path=no;; esac
    fi
    return 0
}

sam_category_read_scope || return $?
sam_register core_allowed sam_category_core_allowed
sam_register candidate_filter sam_category_filter
sam_register filter_stamp sam_category_stamp
sam_register filter_policy sam_category_filter_policy
sam_register candidate_prepare sam_category_prepare_candidate
sam_register config_refresh sam_category_read_scope
