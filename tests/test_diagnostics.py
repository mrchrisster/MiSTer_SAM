"""Bounded RAM diagnostic fixtures; flock writer cases require Linux."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam.diagnostics import DiagnosticLog, MAX_FILE_BYTES, MAX_LINE_BYTES, fcntl, render_history


class DiagnosticTests(unittest.TestCase):
    def test_sd_root_is_rejected_without_file_operations(self):
        tempfile.gettempdir()
        with patch('sam.diagnostics.os.open') as opened:
            self.assertFalse(DiagnosticLog('/media/fat/.SAM_tmp').emit('mcp', 'action'))
            opened.assert_not_called()

    def test_viewer_ignores_invalid_and_truncated_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / 'diagnostics'
            directory.mkdir()
            record = dict(timestamp=0, component='mcp', event='done', owner='12:34', fields={'reason':'literal $(false)'})
            (directory / 'events.jsonl').write_text(json.dumps(record) + '\ninvalid\n' + json.dumps(record))
            (directory / 'last-exit.json').write_text('{broken')
            output = render_history(tmp)
            self.assertIn('1970-01-01 00:00:00 UTC mcp done owner=12:34', output)
            self.assertIn('2 invalid/truncated', output)
            self.assertIn('last-exit.json: invalid', output)

    @unittest.skipUnless(fcntl, 'Linux flock writer')
    def test_emission_sanitizes_and_bounds_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = DiagnosticLog(tmp)
            self.assertTrue(log.emit('mcp', 'action', owner='12:34', long='\u2603' * 10000, values=list(range(1000))))
            data = (Path(tmp) / 'diagnostics/events.jsonl').read_bytes()
            self.assertLessEqual(len(data), MAX_LINE_BYTES)
            record = json.loads(data)
            self.assertEqual(record['owner'], '12:34')
            self.assertIsInstance(record['timestamp'], int)
            self.assertIn('fields', record)

    @unittest.skipUnless(fcntl, 'Linux flock writer')
    def test_rotation_retains_lock_inode_and_two_bounded_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = DiagnosticLog(tmp)
            log.emit('mcp', 'begin')
            directory = Path(tmp) / 'diagnostics'
            inode = (directory / 'events.lock').stat().st_ino
            for number in range(400):
                self.assertTrue(log.emit('mcp', 'decision', number=number, detail='x' * 512))
            self.assertEqual((directory / 'events.lock').stat().st_ino, inode)
            for name in ('events.jsonl', 'events.1.jsonl'):
                self.assertLessEqual((directory / name).stat().st_size, MAX_FILE_BYTES)
                for line in (directory / name).read_bytes().splitlines(keepends=True):
                    self.assertLessEqual(len(line), MAX_LINE_BYTES)
                    json.loads(line)

    @unittest.skipUnless(fcntl, 'Linux flock writer')
    def test_busy_lock_drops_event(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = DiagnosticLog(tmp)
            log.emit('mcp', 'begin')
            path = Path(tmp) / 'diagnostics/events.jsonl'
            before = path.read_bytes()
            with (path.parent / 'events.lock').open('r+') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.assertFalse(log.emit('mcp', 'busy'))
            self.assertEqual(path.read_bytes(), before)

    @unittest.skipUnless(fcntl, 'Linux flock writer')
    def test_file_errors_and_symlink_redirect_fail_open(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = DiagnosticLog(tmp)
            with patch('sam.diagnostics.os.write', side_effect=OSError('full')):
                self.assertFalse(log.emit('mcp', 'full'))
            (Path(tmp) / 'diagnostics/events.jsonl').unlink()
            (Path(tmp) / 'diagnostics/events.jsonl').symlink_to('/media/forbidden')
            self.assertFalse(log.emit('mcp', 'symlink'))

    @unittest.skipUnless(fcntl, 'Linux flock writer')
    def test_bad_field_cannot_escape(self):
        class Bad:
            def __str__(self):
                raise ValueError('bad representation')
        with tempfile.TemporaryDirectory() as tmp:
            self.assertFalse(DiagnosticLog(tmp).emit('mcp', 'bad', value=Bad()))
