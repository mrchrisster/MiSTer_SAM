"""Internal menu pause leases keep the mailbox checks without SD replay writes."""
import importlib.util
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import types
import unittest
from unittest.mock import Mock, patch
from paths import PACKAGE

sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM/control'))
spec = importlib.util.spec_from_file_location('sam_menu_transport_test', PACKAGE / '.MiSTer_SAM/control/sam_control.py')
transport = importlib.util.module_from_spec(spec)
with patch.dict(sys.modules, {'fcntl': types.ModuleType('fcntl')} if os.name == 'nt' else {}):
    spec.loader.exec_module(transport)


@unittest.skipUnless(os.name == 'posix', 'Linux mailbox flock required')
class MenuTransport(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-menu-transport-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.request = dict(action='pause', expected_seq=None, game_path='/games/a.sfc',
                            request_id='12345678-1234-1234-1234-123456789abc')
        self.expected = dict(generation='123:45:1', identity=dict(owner_pid='123', owner_start='45',
                             start_time='10', rom_path='/games/a.sfc'))

    def test_transient_pause_and_resume_preserve_envelope_and_ack_without_journal(self):
        for action in ('pause', 'resume'):
            request = dict(self.request, action=action)
            with patch.object(transport, 'ROOT', self.root), \
                 patch.object(transport, 'check_current', return_value=(200, self.expected)) as check, \
                 patch.object(transport, 'journal_lookup', side_effect=AssertionError('SD journal read')), \
                 patch.object(transport, 'journal', side_effect=AssertionError('SD journal write')), \
                 patch.object(transport, 'atomic') as atomic, \
                 patch.object(transport, 'read_json', return_value={'code': 200, 'body': {'ok': True}}):
                self.assertEqual(transport.submit(request, self.expected, journaled=False), (200, {'ok': True}))
                check.assert_called_once_with(request, self.expected)
                envelope = atomic.call_args.args[1]
                self.assertEqual(envelope['identity'], self.expected['identity'])
                self.assertEqual(envelope['generation'], self.expected['generation'])
                self.assertEqual(envelope['request'], request)
                self.assertGreater(envelope['expires'], transport.time.monotonic())

    def test_public_submission_still_reserves_and_completes_durable_request(self):
        with patch.object(transport, 'ROOT', self.root), \
             patch.object(transport, 'check_current', return_value=(200, self.expected)), \
             patch.object(transport, 'journal_lookup', return_value=None) as lookup, \
             patch.object(transport, 'journal') as journal, \
             patch.object(transport, 'atomic'), \
             patch.object(transport, 'read_json', return_value={'code': 200, 'body': {'ok': True}}):
            self.assertEqual(transport.submit(self.request, self.expected), (200, {'ok': True}))
            lookup.assert_called_once_with(self.request)
            self.assertEqual(journal.call_count, 2)
            self.assertEqual(journal.call_args_list[0].args, (self.request,))
            self.assertEqual(journal.call_args_list[1].args, (self.request, 200, {'ok': True}))

    def test_stale_selection_never_posts_and_failed_ack_is_reported(self):
        with patch.object(transport, 'ROOT', self.root), \
             patch.object(transport, 'check_current', return_value=(409, 'SAM selection changed')), \
             patch.object(transport, 'atomic') as atomic:
            self.assertEqual(transport.submit(self.request, self.expected, journaled=False)[0], 409)
            atomic.assert_not_called()
        with patch.object(transport, 'ROOT', self.root), \
             patch.object(transport, 'check_current', return_value=(200, self.expected)), \
             patch.object(transport, 'journal', side_effect=AssertionError('SD journal write')), \
             patch.object(transport, 'atomic'), \
             patch.object(transport, 'read_json', return_value={'code': 503, 'body': {'ok': False}}):
            self.assertEqual(transport.submit(self.request, self.expected, journaled=False), (503, {'ok': False}))

    def test_transient_mode_rejects_unbound_or_nonlease_commands(self):
        for action, expected in (('next', self.expected), ('play', self.expected), ('pause', None),
                                 ('resume', dict(generation='x'))):
            with self.assertRaises(ValueError):
                transport.submit(dict(self.request, action=action), expected, journaled=False)

    def test_native_transport_does_not_load_http_ssl_or_email(self):
        code = ('import sys; sys.path.insert(0, sys.argv[1]); import sam_control; '
                'sam_control.canonical_request_id(sam_control.new_request_id()); '
                'assert not any(name in sys.modules for name in '
                '("urllib.request", "http.client", "ssl", "email.parser", "uuid", "argparse"))')
        result = subprocess.run([sys.executable, '-c', code, str(PACKAGE/'.MiSTer_SAM/control')],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_request_ids_preserve_uuid4_and_cli_alternate_forms(self):
        import uuid
        generated = [transport.new_request_id() for _ in range(10)]
        self.assertEqual(len(set(generated)), len(generated))
        for value in generated:
            parsed = uuid.UUID(value)
            self.assertEqual(parsed.version, 4)
            self.assertEqual(parsed.variant, uuid.RFC_4122)
            self.assertEqual(transport.canonical_request_id(value.upper()), value)
            self.assertEqual(transport.canonical_request_id('{'+value+'}'), value)
            self.assertEqual(transport.canonical_request_id(value.replace('-', '')), value)
        for value in ('', 'wrong', 'z'*36, '1'*36):
            with self.assertRaises(ValueError): transport.canonical_request_id(value)

    def test_engine_claim_fastpath_keeps_exact_owner_without_argparse(self):
        with patch.object(transport, 'claim') as claim, patch.dict(sys.modules, {'argparse': None}):
            transport.main(['claim', '--owner', '321'])
            claim.assert_called_once_with(321)


if __name__ == '__main__': unittest.main()
