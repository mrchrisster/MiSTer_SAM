"""Source-derived command loss and seed/readiness research, hardware-free."""
from pathlib import Path
import importlib.util
import os
import sys
import tempfile
import unittest
from paths import PACKAGE


def load(name):
    spec = importlib.util.spec_from_file_location(name, PACKAGE / 'research/session-engine' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


backend = load('backend_observation')
seeds = load('seed_contract')


class ReadinessContract(unittest.TestCase):
    def test_core_marker_alone_is_not_readiness(self):
        old = backend.Observation('NES', ('11', '100'), (1, 5), (2, 6, 100), True)
        marker_only = backend.Observation('MENU', old.main, old.fifo, (2, 6, 101), True)
        self.assertFalse(backend.fresh_transport(old, marker_only, 'MENU'))

    def test_new_main_before_fifo_reader_is_not_readiness(self):
        old = backend.Observation('NES', ('11', '100'), (1, 5), (2, 6, 100), True)
        no_reader = backend.Observation('MENU', ('12', '101'), (1, 7), (2, 6, 102), False)
        self.assertFalse(backend.fresh_transport(old, no_reader, 'MENU'))

    def test_new_expected_core_and_main_fifo_marker_are_transport_ready(self):
        old = backend.Observation('NES', ('11', '100'), (1, 5), (2, 6, 100), True)
        ready = backend.Observation('MENU', ('12', '101'), (1, 7), (2, 6, 102), True)
        self.assertTrue(backend.fresh_transport(old, ready, 'MENU'))
        self.assertFalse(backend.fresh_transport(old, ready, 'NES'))

    def test_same_core_reload_still_requires_a_new_incarnation(self):
        old = backend.Observation('NES', ('11', '100'), (1, 5), (2, 6, 100), True)
        self.assertFalse(backend.fresh_transport(old, old, 'NES'))

    def test_navigation_and_toggles_are_never_blindly_retried(self):
        for action in ('next', 'previous', 'toggle_mute', 'launch_game'):
            self.assertEqual(backend.retry_class(action), 'no_blind_retry')
        self.assertEqual(backend.retry_class('return_menu'), 'bounded_desired_state')


@unittest.skipUnless(hasattr(os, 'mkfifo'), 'Linux FIFO behavior')
class MainFifoMechanisms(unittest.TestCase):
    def test_two_complete_writes_can_be_coalesced_into_one_parser_buffer(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'mock-main-fifo'
            os.mkfifo(path)
            descriptor = os.open(path, os.O_RDWR | os.O_NONBLOCK)
            try:
                os.write(descriptor, b'volume unmute\n')
                os.write(descriptor, b'load_core /mock/menu.rbf\n')
                buffer = os.read(descriptor, 1023)
                self.assertEqual(buffer, b'volume unmute\nload_core /mock/menu.rbf\n')
                # Main strips one final newline and compares the complete arg.
                self.assertNotEqual(buffer.rstrip(b'\n')[7:], b'unmute')
            finally:
                os.close(descriptor)

    def test_successfully_written_old_fifo_bytes_do_not_reach_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'mock-main-fifo'
            os.mkfifo(path)
            old = os.open(path, os.O_RDWR | os.O_NONBLOCK)
            new = None
            try:
                self.assertGreater(os.write(old, b'load_core /mock/menu.rbf\n'), 0)
                path.unlink()
                os.mkfifo(path)
                new = os.open(path, os.O_RDWR | os.O_NONBLOCK)
                self.assertNotEqual(os.fstat(old).st_ino, os.fstat(new).st_ino)
                with self.assertRaises(BlockingIOError):
                    os.read(new, 1023)
            finally:
                os.close(old)
                if new is not None:
                    os.close(new)


class StartupSeedContract(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.media, self.cover = root / 'mock.nes', root / 'mock.jpg'
        self.media.write_bytes(b'fixture-media')
        self.cover.write_bytes(b'fixture-cover')
        self.seed = dict(core='nes', policy_revision='rev1', eligibility_complete=True,
                         container=str(self.media), container_stamp=seeds.file_stamp(self.media),
                         cover=str(self.cover), cover_stamp=seeds.file_stamp(self.cover), artwork_decoded=True)

    def check(self, **options):
        options = dict(allowed_cores=['nes'], policy_revision='rev1', artwork_required=True, **options)
        return seeds.usable(self.seed, **options)

    def test_valid_prepared_seed_is_usable(self):
        self.assertTrue(self.check())

    def test_just_a_matching_name_is_insufficient(self):
        self.seed['artwork_decoded'] = False
        self.assertFalse(self.check())

    def test_policy_and_single_core_changes_reject_seed(self):
        self.assertFalse(seeds.usable(self.seed, ['snes'], 'rev1', True))
        self.assertFalse(seeds.usable(self.seed, ['nes'], 'rev2', True))

    def test_removed_or_overwritten_artwork_rejects_seed(self):
        self.cover.write_bytes(b'changed-cover-size')
        self.assertFalse(self.check())
        self.cover.unlink()
        self.assertFalse(self.check())

    def test_changed_rom_or_archive_rejects_seed(self):
        self.media.write_bytes(b'changed-media-size')
        self.assertFalse(self.check())

    def test_cancelled_preparation_never_authorizes_seed(self):
        self.seed['eligibility_complete'] = False
        self.assertFalse(self.check())
