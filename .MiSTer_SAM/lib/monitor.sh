# SPDX-License-Identifier: GPL-3.0-or-later
# Monitor attachment needs paths and owner checks, not game-selection state.

function mcp_start() {
	# MCP monitors when SAM should be launched.
	# "menuonly" and "samtimeout" determine when MCP launches SAM

	if tmux has-session -t MCP 2>/dev/null && python3 "${mrsampath}/sam_mcp_process.py" --single "${mrsampath}/MiSTer_SAM_MCP.py"; then
		return
	fi

    # A vanished tmux pane does not prove its Python child exited.
    mcp_stop || return 1
    # A Scripts-origin marker is for one foreground SAM start. Never let a
    # long-lived MCP or an existing tmux server apply it to future idle starts.
    tmux new-session -s MCP -d "SAM_START_FROM_UI=0 exec '${mrsampath}/MiSTer_SAM_MCP.py'"
}

function mcp_stop() {
    python3 "${mrsampath}/sam_mcp_process.py" "${mrsampath}/MiSTer_SAM_MCP.py" || return 1
    tmux kill-session -t MCP 2>/dev/null || ! tmux has-session -t MCP 2>/dev/null
}

sam_monitor_help() { # Static session-local footer; never runs in input/timer loops.
    local session=$1 line0 line1 line2 table target input_option
    case "$session" in
        SAM)
            line0=' SAM monitor | N/P: next/previous game | M: toggle mute'
            line1=' Q: detach; SAM and game keep running'
            line2=' S: scroll history | Arrows/PgUp: browse'
            ;;
        MCP)
            line0=' MCP | K: keyboard | J: joystick | M: mouse | temporary toggles'
            line1=' D: debug | R: restore INI | H/?: help | S: scroll | Q: detach'
            line2='#{@sam-last-input}'
            ;;
        *) return 2 ;;
    esac
    table="sam-monitor-$session"
    # MiSTer's tmux 3.1c option parser treats '=SAM' literally. Resolve and
    # verify the named session, then address its exact server-assigned ID.
    target=$(tmux display-message -p -t "$session" '#{session_name} #{session_id}') || return 1
    [[ "$target" == "$session "\$* ]] || return 1
    target=${target#* }
    [[ "$target" =~ ^\$[0-9]+$ ]] || return 1
    if [[ "$session" == MCP ]]; then
        # set-option -o returns failure when already set (tmux 3.1c). Reopening
        # a monitor must preserve its latest input and continue attachment.
        # A missing user option can return success with empty output. Query the
        # full option so an existing empty value still counts as initialized.
        input_option=$(tmux show-option -t "$target" @sam-last-input 2>/dev/null) || input_option=
        if [[ -z "$input_option" ]]; then
            tmux set-option -o -t "$target" @sam-last-input 'MCP-INPUT: Waiting for physical input (D toggles debug)' 2>/dev/null || {
                input_option=$(tmux show-option -t "$target" @sam-last-input 2>/dev/null) || return 1
                [[ -n "$input_option" ]] || return 1
            }
        fi
    fi
    # Dedicated key tables leave other sessions alone. tmux handles Q before
    # the owner sees it, so detachment also works during preparation/core loads.
    tmux bind-key -T "$table" q detach-client \; \
        bind-key -T "$table" Q detach-client \; \
        bind-key -T "$table" s copy-mode \; \
        bind-key -T "$table" S copy-mode \; \
        set-option -t "$target" key-table "$table" \; \
        set-option -t "$target" status-position bottom \; \
        set-option -t "$target" status 3 \; \
        set-option -t "$target" 'status-format[0]' "$line0" \; \
        set-option -t "$target" 'status-format[1]' "$line1" \; \
        set-option -t "$target" 'status-format[2]' "$line2" || return 1
    if [[ "$session" == SAM ]]; then
        tmux bind-key -T "$table" C-c detach-client || return 1
        # Swallow terminal Y without a helper process. The internal M82 command
        # uses send-keys directly and still reaches the owner's verified pane.
        tmux bind-key -T "$table" y if-shell -F 0 '' \; \
            bind-key -T "$table" Y if-shell -F 0 ''
    fi
}

function mcp_monitor() {
    mcp_start || { echo 'MCP monitor: could not start the input monitor.' >&2; return 1; }
    local monitor_fd keyboard_fd= rc=0 terminal controls_ready=1
    # Presentation is optional. A footer/key-table error must not prevent
    # observation of a running MCP session or restart that session.
    sam_monitor_help MCP || controls_ready=0
    mkdir -p "$mrsamtmp" || return 1
    exec {monitor_fd}> "$mrsamtmp/mcp-monitor.lock" || return 1
    flock -s "$monitor_fd" || { exec {monitor_fd}>&-; return 1; }
    # SSH terminal hotkeys are separate from the MiSTer's physical keyboard.
    # Reserve physical keys only when this client uses the local virtual console.
    terminal=$(readlink /proc/$$/fd/0) || terminal=
    if [[ "$terminal" =~ ^/dev/tty[0-9]+$ ]]; then
        exec {keyboard_fd}> "$mrsamtmp/mcp-console-keyboard.lock" || { exec {monitor_fd}>&-; return 1; }
        flock -s "$keyboard_fd" || { exec {keyboard_fd}>&-; exec {monitor_fd}>&-; return 1; }
    fi
    if ((controls_ready)); then
        echo 'MCP monitor: K keyboard, J joystick, M mouse, D debug, R restore INI, H help.'
        echo 'Q / Ctrl-C or Ctrl-b then d detaches; MCP keeps running.'
        echo 'S opens history; arrows/PgUp scroll.'
    else
        echo 'Monitor controls could not be configured. Attaching with standard tmux controls; Ctrl-b then d detaches.' >&2
    fi
    sam_diagnostic monitor_attach "terminal=$terminal local_keyboard_reserved=${keyboard_fd:+yes}" '' cli
    tmux send-keys -t MCP h
    tmux attach-session -t MCP || rc=$?
    if [[ -n "$keyboard_fd" ]]; then flock -u "$keyboard_fd"; exec {keyboard_fd}>&-; fi
    flock -u "$monitor_fd"
    exec {monitor_fd}>&-
    sam_diagnostic monitor_detach "terminal=$terminal" '' cli
    return "$rc"
}

function sam_monitor() {
    local root=${sam_root:-${mrsampath:-/media/fat/Scripts/.MiSTer_SAM}}
    local runtime=${SAM_TMP_ROOT:-/tmp/.SAM_tmp} owner_pid= owner_start= existing= command pane_id
    if [[ -r "$runtime/hosted-controller" && -r "$root/lib/controller-client.sh" && -r "$root/lib/session-view.sh" ]]; then
        source "$root/lib/controller-client.sh" || return 1
        source "$root/lib/session-view.sh" || return 1
        if sam_controller_read "$runtime/session-owner"; then
            owner_pid=${sam_controller_record[pid]-} owner_start=${sam_controller_record[start]-}
        fi
        if sam_view_owner_valid "$root" "$runtime" "$owner_pid" "$owner_start"; then
            if tmux has-session -t '=SAM' 2>/dev/null; then
                existing=$(tmux show-option -v -t SAM @sam-view-owner 2>/dev/null) || existing=
                if [[ "$existing" != "$owner_pid:$owner_start" ]]; then
                    echo 'SAM monitor: another SAM pane is still open; wait for it to close.' >&2
                    return 1
                fi
            else
                printf -v command 'exec bash %q %q %q %q %q' "$root/lib/session-view.sh" "$root" "$runtime" "$owner_pid" "$owner_start"
                tmux new-session -d -x 180 -y 40 -s SAM -n 'SAM monitor' "$command" || return 1
                tmux set-option -t SAM @sam-view-owner "$owner_pid:$owner_start" || return 1
            fi
        fi
    fi
    if ! tmux has-session -t '=SAM' 2>/dev/null; then
        echo 'SAM monitor: SAM is not running or is still initializing.' >&2
        echo 'Use MiSTer_SAM_on.sh diagnostics for the last exit, or start SAM first.' >&2
        return 1
    fi
    sam_monitor_help SAM || echo 'Monitor controls could not be configured. Attaching with standard tmux controls; Ctrl-b then d detaches.' >&2
    exec tmux attach-session -t '=SAM'
}
