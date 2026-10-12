#!/usr/bin/env bash
# RESEARCH ONLY. One sequential preparation worker, fixed mode fixtures only.
# This file is sourced by the owner, never from mailbox data.
research_worker() {
    local root=$1 epoch=$2 token=$3 delay=$4 mode=$5 line tag kind core title index=0 slot=0
    local -a kinds=() cores=() titles=()
    trap 'exit 0' TERM INT
    trap - EXIT
    while IFS=$'\t' read -r tag kind core title; do
        [[ "$tag" == item ]] || continue
        kinds+=("$kind"); cores+=("$core"); titles+=("$title")
    done < "$SCRIPT_DIR/modes/$mode.tsv"
    if ((${#kinds[@]} == 0)); then
        printf '%s\t%s\tempty_fixture\n' "$epoch" "$token" > "$root/preparation.failed"
        return
    fi
    while :; do
        # Only the first candidate is immediate; expensive future preparation is injectable.
        if ((index > 0)); then IFS= read -r -t "$delay" -u "$clock_fd" line || true; fi
        [[ -f "$root/session" && $(<"$root/session") == "$epoch:$token" ]] || return
        # The bounded queue has two immutable records. Wait without forks when full.
        while [[ -e "$root/ready/1.tsv" && -e "$root/ready/2.tsv" ]]; do
            IFS= read -r -t .05 -u "$clock_fd" line || true
            [[ -f "$root/session" && $(<"$root/session") == "$epoch:$token" ]] || return
        done
        slot=1; [[ ! -e "$root/ready/1.tsv" ]] || slot=2
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$epoch" "$token" "$index" \
            "$epoch:$index" "${kinds[index % ${#kinds[@]}]}" \
            "${cores[index % ${#cores[@]}]}" "${titles[index % ${#titles[@]}]}" > "$root/ready/.$epoch.tmp"
        # A stopped worker may reach this rename, but the owner revalidates epoch/token.
        mv -f "$root/ready/.$epoch.tmp" "$root/ready/$slot.tsv" || return
        ((index+=1))
    done
}
