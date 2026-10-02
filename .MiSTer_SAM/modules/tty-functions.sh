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

function tty_exit() {
    if [ "${ttyenable}" == "yes" ]; then
        echo -n "Stopping tty2oled... "

        # 1. Timeout for the pipe
        #    Try to write for 3s, then give up.
        #    '2>/dev/null' hides the "timeout: sending signal" message.
        #    The final '&' runs this whole timeout operation in the background.
        if [[ -p ${TTY_cmd_pipe} ]]; then
            timeout 3s sh -c "echo 'stop' > ${TTY_cmd_pipe}" 2>/dev/null &
        fi

        # 2. Timeout for tmux
        #    Run in background (&) and redirect all output (&>/dev/null)
        timeout 3s tmux kill-session -t OLED &>/dev/null &

        # 3. Timeout for rm
        #    Run in background (&) and redirect all output (&>/dev/null)
        timeout 3s rm "${tty_sleepfile}" &>/dev/null &

        # This will now print immediately
        echo "Done."
    fi
}

function write_to_TTY_cmd_pipe() {
	[[ -p ${TTY_cmd_pipe} ]] && echo "${@}" >${TTY_cmd_pipe}
}
