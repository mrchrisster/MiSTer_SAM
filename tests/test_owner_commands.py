"""Authenticated warm-owner command delivery without tmux or hardware."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam import owner_commands as wire
from sam.commands import CommandGateway


class OwnerCommands(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.runtime = Path(temporary.name)
        self.owner = dict(pid='123', start='45', phase='playing', launch='7')
        self.session = (self.runtime / 'fixture-session' if sys.platform == 'win32'
                        else wire.session_path(self.runtime, self.owner))
        # Production PID:start names are Linux paths; map this private fixture
        # directory on Windows while exercising the actual command boundary.
        if sys.platform == 'win32':
            patcher = patch.object(wire, 'session_path', return_value=self.session)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.directory = self.session / 'commands'
        self.directory.mkdir(parents=True)
        self.acknowledgements = wire.acknowledgement_directory(self.runtime)
        self.acknowledgements.mkdir()
        (self.session / 'prototype-controls').write_text('owner_pid=123\nowner_start=45\n')
        self.now = 100.0
        self.request = dict(request_id='1' * 32, action='next', owner_pid='123',
                            owner_start='45', launch='7', expires=102.0)
        self.gateway = CommandGateway(owner_reader=lambda: self.owner,
                                      process_verifier=lambda *_: True,
                                      pane_reader=lambda: self.fail('Warm controls must not query tmux'))

    def deliver(self, duration):
        self.now += duration
        for path in self.directory.glob('req-*.json'):
            request = wire.read(path)
            if wire.valid(request, self.owner, self.now):
                wire.acknowledge(self.acknowledgements, request, ok=True)

    def test_gateway_keys_route_to_bound_warm_owner(self):
        with patch.dict(os.environ, SAM_TMP_ROOT=str(self.runtime)), patch.object(
                wire.time, 'monotonic', side_effect=lambda: self.now), patch.object(
                wire.time, 'sleep', side_effect=self.deliver):
            for action in ('next', 'previous', 'mute', 'm82_play', 'skip', 'stop', 'exit_to_menu'):
                self.assertTrue(self.gateway.execute(action, owner=dict(self.owner)))
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_marker_and_request_reject_replaced_owner_or_selection(self):
        self.assertTrue(wire.enabled(self.runtime, self.owner))
        (self.session / 'prototype-controls').write_text('owner_pid=123\nowner_start=46\n')
        self.assertFalse(wire.enabled(self.runtime, self.owner))
        self.assertTrue(wire.valid(self.request, self.owner, 100))
        for field, value in [('owner_start', '46'), ('owner_pid', '124'),
                             ('launch', '8'), ('action', 'shell'), ('expires', 99),
                             ('expires', float('inf')), ('expires', True)]:
            self.assertFalse(wire.valid(dict(self.request, **{field: value}), self.owner, 100))
        self.assertFalse(wire.valid(dict(self.request, extra='x'), self.owner, 100))

    def test_acceptance_is_not_application_and_expires_without_late_command(self):
        def accepted(duration):
            self.now += duration
            for path in self.directory.glob('req-*.json'):
                wire.acknowledge(self.acknowledgements, wire.read(path), ok=True, state='accepted')
        with patch.object(wire.time, 'monotonic', side_effect=lambda: self.now), patch.object(
                wire.time, 'sleep', side_effect=accepted):
            self.assertFalse(wire.submit(self.runtime, self.owner, 'next', self.gateway.current))
        self.assertAlmostEqual(self.now, 102, delta=.03)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_replacement_while_waiting_cannot_apply_command(self):
        def replaced(duration):
            self.now += duration
            self.owner = dict(pid='124', start='46', phase='playing', launch='7')
        original = dict(self.owner)
        with patch.object(wire.time, 'monotonic', side_effect=lambda: self.now), patch.object(
                wire.time, 'sleep', side_effect=replaced):
            self.assertFalse(wire.submit(self.runtime, original, 'mute', self.gateway.current))
        self.assertLess(self.now, 101)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_foreign_ack_is_not_success(self):
        def foreign(duration):
            self.now += duration
            for path in self.directory.glob('req-*.json'):
                request = wire.read(path)
                wire.acknowledge(self.acknowledgements, dict(request, owner_start='46'), ok=True)
        with patch.object(wire.time, 'monotonic', side_effect=lambda: self.now), patch.object(
                wire.time, 'sleep', side_effect=foreign):
            self.assertFalse(wire.submit(self.runtime, self.owner, 'mute', self.gateway.current))

    def test_bounded_records_and_missing_scratch_are_rejected(self):
        path = self.directory / 'oversize.json'
        path.write_text(json.dumps({'data': 'x' * 4097}))
        self.assertIsNone(wire.read(path))
        path.unlink()
        self.directory.rmdir()
        self.assertFalse(wire.submit(self.runtime, self.owner, 'next', self.gateway.current))
        self.assertFalse(self.directory.exists())

    def test_urgent_stop_keeps_receipt_after_private_scratch_cleanup(self):
        def cleanup_and_complete(duration):
            self.now += duration
            for path in self.directory.glob('req-*.json'):
                request = wire.read(path)
                self.assertTrue(wire.valid(request, dict(self.owner, launch='8'), self.now))
                path.unlink()
                self.directory.rmdir()
                wire.acknowledge(self.acknowledgements, request, ok=True)
        with patch.object(wire.time, 'monotonic', side_effect=lambda: self.now), patch.object(
                wire.time, 'sleep', side_effect=cleanup_and_complete):
            self.assertTrue(wire.submit(self.runtime, self.owner, 'stop', self.gateway.current))
        self.assertFalse(self.directory.exists())
        self.assertEqual(list(self.acknowledgements.iterdir()), [])

    def test_owner_exit_between_ack_read_and_liveness_keeps_completion(self):
        calls = 0
        def current(expected):
            nonlocal calls
            calls += 1
            if calls == 1:
                return self.owner
            for path in self.directory.glob('req-*.json'):
                wire.acknowledge(self.acknowledgements, wire.read(path), ok=True)
            return None
        self.assertTrue(wire.submit(self.runtime, self.owner, 'stop', current))
        self.assertEqual(calls, 2)

    def test_abandoned_receipts_are_bounded_without_touching_unknown_files(self):
        unknown = self.acknowledgements / 'operator-note'
        unknown.write_text('keep')
        for value in range(260):
            wire.acknowledge(self.acknowledgements,
                             dict(self.request, request_id=f'{value:032x}'), ok=True)
        self.assertEqual(len(list(self.acknowledgements.glob('ack-*.json'))), 256)
        self.assertEqual(unknown.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
