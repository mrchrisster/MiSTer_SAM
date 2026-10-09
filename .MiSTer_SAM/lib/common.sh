# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function samdebug() {
    [[ "$samdebug" == yes || "$samdebuglog" == yes ]] || return 0
    local ts msg
    printf -v ts '%(%Y-%m-%d %H:%M:%S)T' -1
    msg="$*"

    if [[ "${samdebug}" == "yes" ]]; then
        # The '>&2' at the end redirects this message to stderr.
        # This prevents it from being captured by command substitution.
        echo -e "\e[1m\e[31m[${ts}] ${msg}\e[0m" >&2
    fi

    if [[ "${samdebuglog}" == "yes" ]]; then
        # Writing to a log file is already separate and is perfectly fine.
        echo "[${ts}] ${msg}" >> /tmp/samdebug.log
    fi
}

function init_paths() {
    mkdir -p "$gamelistpath" "$ratedpath" "$blacklistpath" "$ignorepath" "$gamelistpathtmp" "$mrsamtmp"
}

function tmp_reset() {
	if [[ -d /tmp/.SAM_List ]]; then
        local reset_path
        local -a reset_paths=()
        for reset_path in /tmp/.SAM* /tmp/SAM* /tmp/MiSTer_SAM*; do
            # Keep the complete display snapshot across stop/session cleanup.
            [[ "$reset_path" == "$sam_display_state_file" || "$reset_path" == "$sam_display_state_file.tmp."* ]] && continue
            reset_paths+=("$reset_path")
        done
        (( ${#reset_paths[@]} == 0 )) || rm -rf -- "${reset_paths[@]}"
    fi
	mkdir -p /tmp/.SAM_List  /tmp/.SAM_tmp
}

function delete_from_corelist() {
    local target="$1" kind="${2:-}" index
    if [[ "$kind" == tmp ]]; then
        for index in "${!corelisttmp[@]}"; do
            [[ "${corelisttmp[$index]}" != "$target" ]] || unset 'corelisttmp[index]'
        done
    else
        if [[ "${sam_core_policy_ready:-0}" == 1 ]]; then
            sam_core_id "$target" || return 2
            sam_session_core_excluded[$sam_core_id_result]=1
            sam_core_policy_refresh
            return $?
        fi
        for index in "${!corelist[@]}"; do
            [[ "${corelist[$index]}" != "$target" ]] || unset 'corelist[index]'
        done
        if (( ${#corelist[@]} )); then printf '%s\n' "${corelist[@]}" > "$corelistfile"
        else : > "$corelistfile"; fi
    fi
    return 0
}


function reset_core_gl() { # args ${nextcore}
	echo " Deleting old game lists for ${1^^}..."
	rm "${gamelistpath}/${1}_gamelist.txt" &>/dev/null
	sync "${gamelistpath}"
}
