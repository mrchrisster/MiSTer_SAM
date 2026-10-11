"""Empty autostart guards use RAM records and dependency metadata only."""
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
from paths import PACKAGE

sys.path.insert(0,str(PACKAGE/'.MiSTer_SAM'))
with patch.dict(sys.modules, {'fcntl':types.ModuleType('fcntl')} if os.name=='nt' else {}):
    from sam import autostart as auto


class GuardFixture(unittest.TestCase):
    def setUp(self):
        if os.name=='nt':
            replacement=types.SimpleNamespace(LOCK_EX=2,LOCK_NB=4,flock=lambda *args:None)
            guard=patch.object(auto,'fcntl',replacement);guard.start();self.addCleanup(guard.stop)
        self.temporary=tempfile.TemporaryDirectory(prefix='sam-empty-guard-')
        self.addCleanup(self.temporary.cleanup)
        self.base=Path(self.temporary.name)
        self.runtime=self.base/'runtime';self.runtime.mkdir()
        self.lists=self.base/'SAM/Gamelists';self.lists.mkdir(parents=True)
        self.root=self.base/'root';self.root.mkdir()
        self.ini=self.base/'SAM.ini';self.ini.write_text('corelist="nes"\nArtwork_only="No"\n')
        self.master=self.lists/'nes_gamelist.txt';self.master.write_text('')
        self.clock=0
        self.guard=auto.EmptySelectionGuard(self.ini,self.lists,self.root,self.runtime,clock=lambda:self.clock)

    def write_record(self):
        paths=auto.dependency_paths(self.ini,self.lists,self.root,self.runtime,auto.parse_ini(self.ini.read_bytes()))
        data=dict(version=1,reason='no_eligible_games',owner=['123','77'],
                  context=self.guard.context,inputs=auto.metadata(paths))
        self.guard.path.write_text(json.dumps(data))


class GuardTests(GuardFixture):

    def test_missing_guard_and_unchanged_empty_selection(self):
        self.assertFalse(self.guard.poll())
        self.write_record()
        self.assertTrue(self.guard.poll())
        self.clock=600
        self.assertTrue(self.guard.poll())

    def test_ini_or_catalogue_change_unblocks_and_removes_record(self):
        for kind in ('ini','catalogue'):
            with self.subTest(kind=kind):
                self.write_record();self.assertTrue(self.guard.poll())
                path=self.ini if kind=='ini' else self.master
                path.write_text(path.read_text()+'\n# changed\n')
                self.clock+=5
                self.assertFalse(self.guard.poll())
                self.assertFalse(self.guard.path.exists())

    def test_new_or_removed_master_unblocks(self):
        self.master.unlink();self.write_record()
        self.assertTrue(self.guard.poll())
        self.master.write_text('/rom/new.nes\n');self.clock+=5
        self.assertFalse(self.guard.poll())
        self.write_record();self.assertTrue(self.guard.poll())
        self.master.unlink();self.clock+=5
        self.assertFalse(self.guard.poll())

    def test_category_tags_ignore_and_artwork_refresh_invalidate(self):
        for path in (self.runtime/'category-preset',self.lists/'.excludetags',
                     self.base/'SAM/Ignore/nes_excludelist.txt',self.root/'artwork/database/.generation'):
            with self.subTest(path=path):
                self.write_record();self.assertTrue(self.guard.poll())
                path.parent.mkdir(parents=True,exist_ok=True);path.write_text('updated\n')
                self.clock+=5
                self.assertFalse(self.guard.poll())

    def test_unblocked_checker_never_builds_dependencies_or_reads_ini(self):
        with patch.object(auto,'dependency_paths',side_effect=AssertionError('scan')), \
             patch.object(auto,'bounded_bytes',side_effect=AssertionError('ini read')):
            for _ in range(10):self.assertFalse(self.guard.poll())

    def test_blocked_inputs_are_stat_checked_only_once_per_interval(self):
        self.write_record()
        with patch.object(auto,'metadata',wraps=auto.metadata) as probe:
            self.assertTrue(self.guard.poll())
            for _ in range(10):self.assertTrue(self.guard.poll())
            self.assertEqual(probe.call_count,1)
            self.clock=5;self.assertTrue(self.guard.poll())
            self.assertEqual(probe.call_count,2)

    def test_manual_clear_and_mcp_restart_have_no_stale_memory_block(self):
        self.write_record();self.assertTrue(self.guard.poll())
        replacement=auto.EmptySelectionGuard(self.ini,self.lists,self.root,self.runtime)
        self.assertTrue(replacement.poll())
        self.guard.path.unlink()
        self.assertFalse(self.guard.poll());self.assertFalse(replacement.poll())

    def test_foreign_context_corrupt_oversized_and_wrong_reason_are_ignored(self):
        for kind in ('context','reason','corrupt','oversized'):
            self.write_record()
            if kind in ('context','reason'):
                data=json.loads(self.guard.path.read_text())
                data[kind]=[] if kind=='context' else 'network_error'
                self.guard.path.write_text(json.dumps(data))
            else:self.guard.path.write_text('{' if kind=='corrupt' else 'x'*(auto.MAX_RECORD+1))
            self.assertFalse(self.guard.poll())

    def test_newer_record_is_not_unlinked_during_input_change(self):
        self.write_record();self.assertTrue(self.guard.poll())
        self.master.write_text('new\n');self.clock=5
        real=auto.metadata
        def replace(paths):
            current=real(paths)
            item=json.loads(self.guard.path.read_text())
            item['inputs']=current
            self.guard.path.write_text(json.dumps(item))
            return current
        with patch.object(auto,'metadata',side_effect=replace):
            # Replacement guard now reflects the new inputs.
            self.assertFalse(self.guard.poll())
        self.assertTrue(self.guard.path.exists())

    @unittest.skipUnless(sys.platform.startswith('linux'),'Linux transition lock required')
    def test_busy_owner_transition_preserves_record_and_rechecks_after_unlock(self):
        self.write_record();self.assertTrue(self.guard.poll())
        self.master.write_text('new\n');self.clock=5
        with (self.runtime/'session-owner.lock').open('w') as lock:
            auto.fcntl.flock(lock.fileno(),auto.fcntl.LOCK_EX)
            self.assertFalse(self.guard.poll())
            self.assertTrue(self.guard.path.exists())
        self.assertFalse(self.guard.poll())
        self.assertFalse(self.guard.path.exists())


@unittest.skipUnless(sys.platform.startswith('linux'),'Linux ownership/flock required')
class RecordTests(GuardFixture):
    def setUp(self):
        super().setUp()
        pid=str(os.getpid())
        ticks=Path('/proc',pid,'stat').read_text().rsplit(') ',1)[1].split()[19]
        self.owner=pid+':'+ticks
        self.session=self.runtime/('session-'+self.owner);self.session.mkdir()
        (self.session/'alive').touch()
        (self.session/'config.ini').write_bytes(self.ini.read_bytes())
        (self.session/'outcome').write_text('reason=no_eligible_games\nrevision=1\n')
        self.owner_path=self.runtime/'session-owner'
        self.owner_path.write_text('pid='+pid+'\nstart='+ticks+'\nphase=preparing\nlaunch=0\n')

    def record(self,mode='ALL',target=''):
        return auto.record_empty(self.session,mode,target,self.ini,self.lists,self.root,self.runtime,self.owner)

    def test_exact_current_empty_owner_records_then_survives_cleanup(self):
        self.assertTrue(self.record())
        (self.session/'alive').unlink()
        self.owner_path.unlink()
        self.assertTrue(self.guard.poll())

    def test_single_core_testing_does_not_block_normal_automatic_selection(self):
        self.assertFalse(self.record('SINGLE','nes'))
        self.assertFalse(self.guard.path.exists())

    def test_cancelled_stale_owner_or_nonempty_failure_never_records(self):
        for kind in ('cancelled','owner','generic'):
            with self.subTest(kind=kind):
                (self.session/'alive').touch()
                (self.session/'outcome').write_text('reason=no_eligible_games\nrevision=1\n')
                self.owner_path.write_text('pid='+self.owner.split(':')[0]+'\nstart='+self.owner.split(':')[1]+'\nphase=preparing\n')
                if kind=='cancelled':(self.session/'alive').unlink()
                elif kind=='owner':self.owner_path.unlink()
                else:(self.session/'outcome').write_text('reason=network_error\n')
                self.assertFalse(self.record());self.assertFalse(self.guard.path.exists())

    def test_configuration_changed_during_preparation_does_not_latch_new_settings(self):
        self.ini.write_text('corelist="snes"\n')
        self.assertFalse(self.record());self.assertFalse(self.guard.path.exists())

    def test_stale_revision_and_duplicate_outcome_are_not_recorded(self):
        for content in ('reason=no_eligible_games\nrevision=2\n',
                        'reason=no_eligible_games\nrevision=1\nreason=no_eligible_games\n'):
            (self.session/'outcome').write_text(content)
            self.assertFalse(self.record());self.assertFalse(self.guard.path.exists())


if __name__=='__main__':unittest.main()
