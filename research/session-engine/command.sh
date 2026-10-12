#!/usr/bin/env bash
# RESEARCH ONLY. Literal mailbox writer; never signals the owner or uses Python.
set -u
umask 077
root=${TMP_ROOT:?Set TMP_ROOT to a private /tmp/sam-session-research-* fixture}
[[ "$root" =~ ^/tmp/sam-session-research-[A-Za-z0-9_-]+$ && ! -L "$root" &&
   -f "$root/RESEARCH_MOCK_ONLY" && $(<"$root/RESEARCH_MOCK_ONLY") == SAM_SESSION_RESEARCH_V1 ]] || exit 64
action=${1:-status}; shift || true
case "$action" in
    start|next|stop|status|shutdown|input|timer|menu-observed) (($# == 0)) || exit 64 ;;
    launch|ui-close) (($# == 1)) || exit 64 ;;
    ui-open) (($# == 3)) || exit 64 ;;
    *) exit 64 ;;
esac
for arg in "$@"; do [[ ${#arg} -le 96 && "$arg" =~ ^[A-Za-z0-9_.:-]+$ ]] || exit 64; done
[[ -f "$root/owner" && ! -L "$root/owner" ]] || exit 69
IFS=$'\t' read -r owner ticks token epoch extra < "$root/owner" || exit 69
[[ "$owner" =~ ^[1-9][0-9]*$ && "$ticks" =~ ^[0-9]+$ && "$token" =~ ^[A-Za-z0-9_-]+$ && "$epoch" =~ ^[0-9]+$ && -z "$extra" ]] || exit 69
IFS= read -r stat < "/proc/$owner/stat" || exit 69
read -ra fields <<< "${stat##*) }"
[[ ${fields[19]:-} == "$ticks" && ${fields[0]:-Z} != Z ]] || exit 69
# Kernel-released writer locks; urgent admission never waits on ordinary admission.
prefix=control; [[ "$action" != stop && "$action" != shutdown ]] || prefix=urgent
exec {writer_fd}> "$root/$prefix-writer.lock" || exit 75
flock -w .5 "$writer_fd" || exit 75
shopt -s nullglob
pending=("$root"/inbox/"$prefix".*.req)
limit=32; [[ "$prefix" != urgent ]] || limit=1
((${#pending[@]} < limit)) || exit 75
id="$BASHPID-$RANDOM-$RANDOM"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$owner" "$ticks" "$token" "$epoch" "$action" "${1:--}" "${2:--}" "${3:--}" > "$root/inbox/.$id.tmp"
mv -f "$root/inbox/.$id.tmp" "$root/inbox/$prefix.$id.req" || exit 74
printf '%s\n' "$id"
