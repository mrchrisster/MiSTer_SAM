"""Scripts dismissal is not a request to stop the just-created SAM owner."""
from pathlib import Path
import os
import sys
import tempfile
import unittest
from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam.ui_start import blocked


@unittest.skipUnless(os.name == 'posix', 'MiSTer owner directories use POSIX colon names')
class UiStartTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.owner = dict(pid='123', start='456', phase='video', launch='0')
        self.path = Path(self.temp.name) / 'session-123:456' / 'ui-start'
        self.path.parent.mkdir()

    def test_cli_and_idle_owners_have_no_gate(self):
        self.assertFalse(blocked(self.owner, 10, self.temp.name))

    def test_scripts_input_is_ignored_while_first_game_prepares(self):
        self.path.write_text('owner_pid=123\nowner_start=456\nstate=pending\n')
        self.assertTrue(blocked(self.owner, 10, self.temp.name))

    def test_queued_dismissal_is_rejected_but_new_press_works(self):
        self.path.write_text('owner_pid=123\nowner_start=456\nstate=ready\nready_at=10.125\n')
        self.assertTrue(blocked(self.owner, 10, self.temp.name))
        self.assertFalse(blocked(self.owner, 10.126, self.temp.name))
        self.owner.update(phase='loading', launch='2')
        self.assertFalse(blocked(self.owner, 11, self.temp.name))

    def test_other_owner_marker_does_not_suppress_input(self):
        self.path.write_text('owner_pid=123\nowner_start=999\nstate=pending\n')
        self.assertFalse(blocked(self.owner, 10, self.temp.name))

    def test_invalid_ready_timestamp_does_not_arm_unprepared_session(self):
        for value in ('nan', 'inf', '0', '-1', 'garbage'):
            self.path.write_text('owner_pid=123\nowner_start=456\nstate=ready\nready_at=%s\n' % value)
            self.assertTrue(blocked(self.owner, 10, self.temp.name))
