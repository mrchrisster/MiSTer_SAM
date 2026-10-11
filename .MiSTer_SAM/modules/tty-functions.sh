# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function tty_start() {
	if [ "${ttyenable}" == "yes" ]; then
		[ -f /tmp/.SAM_tmp/tty_currentinfo ] && rm /tmp/.SAM_tmp/tty_currentinfo
		#[ -f /media/fat/tty2oled/S60tty2oled ] && /media/fat/tty2oled/S60tty2oled restart && sleep 3
		touch "${tty_sleepfile}"
		echo -n "Starting tty2oled... "
		tmux new -s OLED -d "${mrsampath}/MiSTer_SAM_tty2oled" &>/dev/null
		echo "Done."
	fi
}

sam_tty_oled_process_matches() { # only the OLED program started by this module
    local pid=$1
    local -a argv=()
    [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/cmdline" ]] || return 1
    mapfile -d '' -t argv < "/proc/$pid/cmdline" || return 1
    [[ "${argv[0]##*/}" == bash && "${argv[1]:-}" == "$mrsampath/MiSTer_SAM_tty2oled" ]]
}

sam_tty_wait_job() { # only our unreaped helper, never wait for unrelated jobs
    local pid=$1 ticks=$2 rc
    while :; do
        rc=0; wait "$pid" || rc=$?
        # A trapped TERM can interrupt wait while the helper is still running.
        ((rc >= 128)) || return 0
        if [[ -n "$ticks" ]] && declare -F sam_pid_start >/dev/null; then
            sam_pid_start "$pid" && [[ "$sam_proc_start" == "$ticks" ]] || return 0
        else
            kill -0 "$pid" 2>/dev/null || return 0
        fi
    done
}

function tty_exit() {
    [[ "${ttyenable}" == yes ]] || return 0
    echo -n "Stopping tty2oled... "
    local panes= sid= pane_pid= server= record_sid record_pane record_server
    local sleep_identity= current_identity= pipe_pid= kill_pid= pipe_ticks= kill_ticks=
    local kill_command
    # Capture before helpers start. Admission remains blocked by the live SAM
    # owner, and Menu has already passed the private quiescence barrier.
    sleep_identity=$(stat -Lc '%d:%i|%z' "$tty_sleepfile" 2>/dev/null) || sleep_identity=
    panes=$(timeout -k 1s 1s tmux list-panes -t '=OLED' -F '#{session_id} #{pane_pid} #{pid}' 2>/dev/null) || panes=
    while read -r record_sid record_pane record_server; do
        [[ "$record_sid" =~ ^\$[0-9]+$ && "$record_pane" =~ ^[1-9][0-9]*$ &&
           "$record_server" =~ ^[1-9][0-9]*$ ]] || continue
        sam_tty_oled_process_matches "$record_pane" || continue
        sid=$record_sid pane_pid=$record_pane server=$record_server
        break
    done <<< "$panes"
    if [[ -n "$sid" ]]; then
        if [[ -p "$TTY_cmd_pipe" ]]; then
            # A short best-effort graceful notification must finish before
            # killing the reader. Parallel kill/open made every shutdown wait
            # a full second when the reader disappeared before the handshake.
            timeout -k 0.1s 0.2s bash -c '
                [[ -p "$1" ]] && printf "stop\n" > "$1"
            ' sam-tty-stop "$TTY_cmd_pipe" >/dev/null 2>&1 &
            pipe_pid=$!
            if declare -F sam_pid_start >/dev/null && sam_pid_start "$pipe_pid"; then pipe_ticks=$sam_proc_start; fi
            sam_tty_wait_job "$pipe_pid" "$pipe_ticks"
        fi
        # Session names and IDs can be reused. Check server and pane identity in
        # the same tmux connection that removes the captured session ID.
        printf -v kill_command "kill-session -t '%s'" "$sid"
        timeout -k 1s 2s tmux if-shell -F -t "$sid"             "#{&&:#{==:#{pid},$server},#{==:#{pane_pid},$pane_pid}}"             "$kill_command" >/dev/null 2>&1 &
        kill_pid=$!
        if declare -F sam_pid_start >/dev/null && sam_pid_start "$kill_pid"; then kill_ticks=$sam_proc_start; fi
    fi
    # Collect precisely these bounded helpers before the owner exits. No late
    # kill-session or rm can affect the next SAM/OLED instance after admission.
    [[ -z "$kill_pid" ]] || sam_tty_wait_job "$kill_pid" "$kill_ticks"
    current_identity=$(stat -Lc '%d:%i|%z' "$tty_sleepfile" 2>/dev/null) || current_identity=
    if [[ -n "$sleep_identity" && "$current_identity" == "$sleep_identity" ]]; then
        rm -f -- "$tty_sleepfile" || return 1
    fi
    echo "Done."
}

function write_to_TTY_cmd_pipe() {
    if ((BASH_SUBSHELL > 0)); then
        # Existing callers background this optional notification. Do not keep
        # the SAM owner's EXIT cleanup or admission-lock descriptor alive,
        # including when the FIFO has already disappeared.
        trap - EXIT TERM INT
        if [[ "${sam_session_lock_fd:-}" =~ ^[0-9]+$ ]]; then
            exec {sam_session_lock_fd}>&-
        fi
    fi
    [[ -p "${TTY_cmd_pipe}" ]] || return 0
    local payload
    printf -v payload '%s ' "$@"
    payload="${payload% }"
    if ((BASH_SUBSHELL > 0)); then
        # Replace this helper shell, so a receiver-less FIFO cannot leave an
        # orphan SAM shell. A hard deadline also covers a full receiver buffer.
        exec timeout -k 1s 1s bash -c '
            [[ -p "$1" ]] && printf "%s\n" "$2" > "$1"
        ' sam-tty-write "$TTY_cmd_pipe" "$payload" >/dev/null 2>&1
    fi
    timeout -k 1s 1s bash -c '
        [[ -p "$1" ]] && printf "%s\n" "$2" > "$1"
    ' sam-tty-write "$TTY_cmd_pipe" "$payload" >/dev/null 2>&1 || true
}
