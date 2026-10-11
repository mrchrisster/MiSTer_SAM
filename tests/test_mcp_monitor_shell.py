"""Reopening the MCP monitor preserves its input row on tmux 3.1c."""
import os
import subprocess
import unittest
from paths import PACKAGE


@unittest.skipUnless(os.name == 'posix', 'Bash monitor integration requires Linux')
class MonitorReopen(unittest.TestCase):
    def run_monitor(self, initial='', race=False, help_failure=False, start_failure=False):
        script = r'''
source "$1/lib/monitor.sh"
current=$2
sets=0 configurations=0 attaches=0
tmux() {
    case "$1" in
        display-message) echo 'MCP $9';;
        show-option)
            echo query >> "$mrsamtmp/queries"
            [[ -n "$current" ]] || return 0
            printf '@sam-last-input "%s"\n' "$current";;
        set-option)
            sets=$((sets + 1))
            if [[ -n "$current" ]]; then echo 'already set: @sam-last-input' >&2; return 1; fi
            if [[ "$3" == RACE ]]; then current='MCP-INPUT: Racing input'; return 1; fi
            current=${!#};;
        bind-key) configurations=$((configurations + 1));;
        send-keys) :;;
        attach-session) attaches=$((attaches + 1));;
        *) return 97;;
    esac
}
# Exercise the full attachment route without restarting MCP or opening devices.
mcp_start() { :; }
sam_diagnostic() { :; }
mrsamtmp=$(mktemp -d)
trap 'rm -rf "$mrsamtmp"' EXIT
mcp_monitor || exit 91
mcp_monitor || exit 92
[[ $attaches == 2 && $configurations == 2 ]] || exit 93
printf '\nRESULT:%s|%s|%s\n' "$current" "$sets" "$(wc -l < "$mrsamtmp/queries")"
'''
        if race:
            script = script.replace('if [[ "$3" == RACE ]]', 'if true')
        if help_failure:
            script = script.replace('mcp_start() { :; }', 'mcp_start() { :; }\nsam_monitor_help(){ return 1; }')
            script = script.replace('$configurations == 2', '$configurations == 0')
        if start_failure:
            script = script.replace('mcp_start() { :; }', 'mcp_start() { return 1; }')
        result = subprocess.run(['bash', '-c', script, 'fixture', str(PACKAGE / '.MiSTer_SAM'), initial],
                                text=True, capture_output=True, timeout=5)
        if start_failure:
            self.assertEqual(result.returncode, 91)
            self.assertIn('could not start the input monitor', result.stderr)
            self.assertNotIn('MCP monitor: K keyboard', result.stdout)
            return
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('already set:', result.stderr)
        if help_failure:
            self.assertIn('Attaching with standard tmux controls', result.stderr)
            self.assertNotIn('Q / Ctrl-C', result.stdout)
            return
        return result.stdout.split('RESULT:')[1].strip().split('|')

    def test_first_and_repeated_attachments_initialize_only_once(self):
        row, sets, queries = self.run_monitor()
        self.assertEqual(row, 'MCP-INPUT: Waiting for physical input (D toggles debug)')
        self.assertEqual(sets, '1')
        self.assertEqual(queries, '2')

    def test_existing_latest_input_is_preserved_and_both_attachments_succeed(self):
        row, sets, queries = self.run_monitor('MCP-INPUT: #[bold]B BUTTON#[nobold] PUSHED')
        self.assertIn('B BUTTON', row)
        self.assertEqual(sets, '0')
        self.assertEqual(queries, '2')

    def test_worker_initializing_option_during_attachment_is_harmless(self):
        row, sets, queries = self.run_monitor(race=True)
        self.assertEqual(row, 'MCP-INPUT: Racing input')
        self.assertEqual(sets, '1')
        self.assertEqual(queries, '3')

    def test_optional_footer_failure_still_attaches_without_claiming_hotkeys(self):
        self.run_monitor(help_failure=True)

    def test_unavailable_monitor_reports_error_instead_of_claiming_attachment(self):
        self.run_monitor(start_failure=True)

    def test_sam_footer_failure_still_attempts_attachment(self):
        script = r'''
source "$1/lib/monitor.sh"
sam_monitor_help(){ return 1; }
exec(){ [[ "$*" == 'tmux attach-session -t =SAM' ]] || return 97; echo ATTACH_ATTEMPTED; }
sam_monitor
'''
        result = subprocess.run(['bash', '-c', script, 'fixture', str(PACKAGE / '.MiSTer_SAM')],
                                text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ATTACH_ATTEMPTED', result.stdout)
        self.assertIn('Attaching with standard tmux controls', result.stderr)


if __name__ == '__main__':
    unittest.main()
