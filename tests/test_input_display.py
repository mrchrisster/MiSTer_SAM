import sys
import unittest
from types import SimpleNamespace
from unittest.mock import Mock
from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam.input_display import LatestInputLine, format_activity


class InputDisplay(unittest.TestCase):
    def message(self, mister='B', database='a', code='304 BTN_SOUTH', device='PLAYSTATION(R)3 Controller'):
        return 'MCP-INPUT: %s: DOWN MiSTer=%s DB=%s js_button=0 Linux=%s source=MiSTer-map action=default detection=enabled' % (device, mister, database, code)

    def test_mister_button_is_bold_and_database_is_secondary(self):
        self.assertEqual(format_activity(self.message()),
            'MCP-INPUT: PLAYSTATION(R)3 Controller: #[bold]B BUTTON#[nobold] PUSHED (DB: A)')
        self.assertNotIn('BTN_SOUTH', format_activity(self.message()))

    def test_database_and_linux_fallbacks_do_not_invent_mister_labels(self):
        self.assertIn('A BUTTON', format_activity(self.message('unmapped', 'a')))
        self.assertIn('#[bold]BTN_SOUTH#[nobold]', format_activity(self.message('unmapped', 'unmapped')))
        self.assertNotIn('(DB:', format_activity(self.message('B', 'unavailable')))
        self.assertIn('BUTTON 0', format_activity(self.message('unavailable', 'unavailable', 'unknown')))

    def test_labels_cannot_inject_terminal_or_tmux_formats(self):
        text = format_activity(self.message(device='Pad#(bad)\x1b'))
        self.assertIn('Pad##(bad)', text)
        self.assertNotIn('\x1b', text)
        self.assertIsNone(format_activity('MCP-INPUT: Pad: GUID=known source=generic'))
        self.assertIn('raw', format_activity('MCP-INPUT: Keyboard device=/dev/hidraw0 report=000004 source=generic'))

    def line(self, attached=True):
        now = [0.0]
        active = Mock(return_value=attached)
        runner = Mock(side_effect=lambda args, **kw: SimpleNamespace(returncode=0, stdout='MCP $9\n'))
        return LatestInputLine(active, runner, lambda: now[0]), now, active, runner

    def test_inputs_coalesce_and_never_do_io_in_producer(self):
        line, now, active, runner = self.line()
        for button in ('A', 'B', 'X'):
            line.update(self.message(button))
        runner.assert_not_called(); active.assert_not_called()
        line.flush()
        self.assertEqual(runner.call_count, 2)
        self.assertIn('X BUTTON', runner.call_args.args[0][-1])
        self.assertEqual(runner.call_args.args[0][3], '$9')
        line.update(self.message('Y')); line.flush()
        self.assertEqual(runner.call_count, 2)
        now[0] = .21; line.flush()
        self.assertEqual(runner.call_count, 3)
        self.assertIn('Y BUTTON', runner.call_args.args[0][-1])

    def test_detached_monitor_uses_no_tmux_and_reattach_replays_latest(self):
        line, now, active, runner = self.line(False)
        line.update(self.message()); line.flush(); runner.assert_not_called()
        active.return_value = True; now[0] = .3; line.flush()
        self.assertEqual(runner.call_count, 2)
        line.update(self.message('X'))
        active.return_value = False; now[0] = .6; line.flush()
        active.return_value = True; now[0] = .9; line.flush()
        self.assertEqual(runner.call_count, 4)

    def test_target_validation_and_render_failures_are_harmless(self):
        line, now, active, runner = self.line()
        runner.side_effect = None; runner.return_value = SimpleNamespace(returncode=0, stdout='SAM $9\n')
        line.update(self.message()); line.flush()
        self.assertEqual(runner.call_count, 1)
        runner.side_effect = OSError('server unavailable'); now[0] = .3; line.flush()
        self.assertIsNone(line.target)


if __name__ == '__main__': unittest.main()
