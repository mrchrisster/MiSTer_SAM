"""Catalog and scanner fixtures. Linux provides the same flock API as MiSTer."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import struct
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile

from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam_catalog import Catalog, CatalogError, DirectLaunch
from sam_mgl import generate, atomic_write
from samindex import Scanner, scan_outputs, acquire_lock
from sam_zip import DirectoryZip


class CatalogTests(unittest.TestCase):
    def setUp(self): self.catalog = Catalog()

    def test_every_sam_alias_and_canonical_boundary(self):
        for alias, key in self.catalog.compat['aliases'].items():
            if key is None: continue
            self.assertEqual(self.catalog.sam_system(alias)['id'], key)
            self.assertEqual(self.catalog.sam_id(alias), alias)
        self.assertEqual(self.catalog.sam_system('gb')['id'], 'Gameboy')
        self.assertEqual(self.catalog.sam_system('gg')['id'], 'GameGear')

    def test_group_lookup_order_and_sam_systems_do_not_mix(self):
        group = self.catalog.lookup('NES')
        self.assertTrue(any('.fds' in x.get('extensions', []) for x in group['slots']))
        self.assertFalse(any('.fds' in x.get('extensions', []) for x in self.catalog.sam_system('nes')['slots']))
        self.assertEqual(self.catalog.slot(self.catalog.lookup('X68000'), '/test.d88')['index'], 0)

    def test_defaults_zero_reset_setname_and_xml_escaping(self):
        import xml.etree.ElementTree as ET
        snes = ET.fromstring(generate(self.catalog, 'snes', '/games/A & B <one> "x".sfc', sd='/absent'))
        self.assertEqual(snes.find('file').attrib['index'], '0')
        self.assertEqual(snes.find('file').attrib['path'], '../../../../../games/A & B <one> "x".sfc')
        jag = ET.fromstring(generate(self.catalog, 'jaguar', '/games/A.jag', sd='/absent'))
        self.assertEqual(jag.find('reset').attrib, {'delay':'1', 'hold':'1'})
        gbc = ET.fromstring(generate(self.catalog, 'gbc', '/games/A.gbc', sd='/absent'))
        self.assertEqual(gbc.find('setname').text, 'GBC')

    def test_extension_selects_slot_and_unsupported_is_not_guessed(self):
        core = self.catalog.sam_system('psx')
        self.assertEqual(self.catalog.slot(core, '/A.chd')['method'], 's')
        self.assertEqual(self.catalog.slot(core, '/A.exe')['method'], 'f')
        self.assertEqual(self.catalog.launch_slot('psx', '/A.exe')['method'], 's')
        with self.assertRaises(CatalogError): self.catalog.slot(core, '/A.xyz')
        with self.assertRaises(DirectLaunch): self.catalog.slot(self.catalog.sam_system('arcade'), '/A.mra')
        with self.assertRaises(DirectLaunch): generate(self.catalog, 'nes', '/A.mgl')

    def test_pin_and_numeric_validation(self):
        from sam_catalog import validate_core
        core = dict(id='test', slots=[dict(extensions=['.rom'], mgl=dict(method='f', index=0))])
        validate_core(core)
        core['slots'][0]['mgl']['index'] = True
        with self.assertRaises(CatalogError): validate_core(core)
        with tempfile.TemporaryDirectory() as root:
            record=Path(root)/'source.json';record.write_text('{"sha256":"wrong"}')
            with self.assertRaises(CatalogError): Catalog(source=record)

    def test_rbf_aliases_are_only_fallback_and_keep_non_date_suffixes(self):
        with tempfile.TemporaryDirectory() as directory:
            sd=Path(directory);folder=sd/'_Console';folder.mkdir()
            core=dict(id='test',rbf='_Console/NES',rbfAliases=['NES_*'])
            (folder/'NES_Alt.rbf').touch();(folder/'NES_Unrelated.txt').touch()
            self.assertEqual(self.catalog.rbf_path(core,str(sd)),'_Console/NES_Alt')
            (folder/'NES_20250101.rbf').touch()
            self.assertEqual(self.catalog.rbf_path(core,str(sd)),'_Console/NES')

    def test_all_sam_media_extensions_have_explicit_slots(self):
        for alias, extensions in self.catalog.compat['extensions'].items():
            if alias in self.catalog.compat['handlers']: continue
            for extension in extensions:
                self.catalog.slot(self.catalog.launch_core(alias), '/fixture' + extension)


class ScannerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.games = self.root/'GaMeS'; self.games.mkdir()
        self.nes = self.games/'nEs'; self.nes.mkdir()
        self.out = self.root/'out'; self.cache = self.root/'cache'
        self.catalog = Catalog()

    def scanner(self, refresh=False):
        return Scanner(self.catalog, [str(self.root/'games')], self.cache, refresh)

    def zip(self, names, path=None):
        path=path or self.nes/'pack.zip'
        with zipfile.ZipFile(path, 'w') as bundle:
            for name in names: bundle.writestr(name, b'fixture')
        return path

    def lines(self, core='nes'):
        return (self.out/(core+'_gamelist.txt')).read_text().splitlines()

    def test_case_loose_nested_archive_and_shared_systems(self):
        (self.nes/'A.NES').write_bytes(b'x');(self.nes/'Ignored.sfc').write_bytes(b'x')
        self.zip(['nested/B.nes','C.fds','.hidden.nes','../bad.nes'])
        scanner=self.scanner();scan_outputs(scanner,['nes','fds'],self.out,quiet=True)
        self.assertEqual(self.lines(),[str(self.nes/'A.NES'),str(self.nes/'pack.zip')+'/nested/B.nes'])
        self.assertEqual(self.lines('fds'),[str(self.nes/'pack.zip')+'/C.fds'])

    def test_cache_reuse_change_remove_and_current_extension_policy(self):
        self.zip(['A.nes','Other.xyz'])
        first=self.scanner();scan_outputs(first,['nes'],self.out,quiet=True)
        self.assertEqual(first.misses,1)
        second=self.scanner();scan_outputs(second,['nes'],self.out,quiet=True)
        self.assertEqual(second.hits,1)
        self.catalog.compat['extensions']['nes']=['.xyz']
        third=self.scanner();scan_outputs(third,['nes'],self.out,quiet=True)
        self.assertEqual(third.hits,1);self.assertTrue(self.lines()[0].endswith('Other.xyz'))
        self.catalog.compat['extensions']['nes']=['.nes']
        self.zip(['Added.nes'])
        changed=self.scanner();scan_outputs(changed,['nes'],self.out,quiet=True)
        self.assertEqual(changed.misses,1);self.assertTrue(self.lines()[0].endswith('Added.nes'))
        (self.nes/'pack.zip').unlink();scan_outputs(self.scanner(),['nes'],self.out,quiet=True)
        self.assertEqual(self.lines(),[])

    def test_truncated_cache_is_rebuilt_without_emitting_partial_data(self):
        self.zip(['A.nes','B.nes']);scan_outputs(self.scanner(),['nes'],self.out,quiet=True)
        cache=next(self.cache.glob('*.members'));data=cache.read_bytes();cache.write_bytes(data[:data.rfind(b'\n',0,len(data)-1)+1])
        scanner=self.scanner();scan_outputs(scanner,['nes'],self.out,quiet=True)
        self.assertEqual(scanner.misses,1);self.assertEqual(len(self.lines()),2)

    def test_filename_dedupe_is_separate_deterministic_and_case_sensitive(self):
        (self.nes/'A.nes').write_bytes(b'x');self.zip(['nested/A.nes','a.nes'])
        scan_outputs(self.scanner(),['nes'],self.out,no_dupes=True,quiet=True)
        self.assertEqual(len(self.lines()),2);self.assertEqual(self.lines()[0],str(self.nes/'A.nes'))

    def test_symlinks_broken_links_and_cycles(self):
        extra=self.root/'extra';extra.mkdir();(extra/'B.nes').write_bytes(b'x')
        (self.nes/'alias').symlink_to(extra, target_is_directory=True)
        (extra/'cycle').symlink_to(self.nes, target_is_directory=True)
        (self.nes/'broken').symlink_to(self.root/'missing')
        scan_outputs(self.scanner(),['nes'],self.out,quiet=True)
        self.assertEqual(self.lines(),[str(self.nes/'alias/B.nes')])

    def test_corrupt_archive_is_reported_and_other_games_survive(self):
        (self.nes/'bad.zip').write_bytes(b'broken');(self.nes/'A.nes').write_bytes(b'x')
        scanner=self.scanner();scan_outputs(scanner,['nes'],self.out,quiet=True)
        self.assertEqual(scanner.corrupt,1);self.assertEqual(len(self.lines()),1)

    def test_storage_or_write_failure_keeps_previous_output(self):
        (self.nes/'A.nes').write_bytes(b'x');scan_outputs(self.scanner(),['nes'],self.out,quiet=True)
        original=(self.out/'nes_gamelist.txt').read_bytes()
        scanner=self.scanner();real_scandir=os.scandir
        def failed(path):
            if str(path)==str(self.nes): raise PermissionError('storage unavailable')
            return real_scandir(path)
        with patch('samindex.os.scandir', side_effect=failed):
            with self.assertRaises(PermissionError): scan_outputs(scanner,['nes'],self.out,quiet=True)
        self.assertEqual((self.out/'nes_gamelist.txt').read_bytes(),original)
        with patch('samindex.os.fsync', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): scan_outputs(self.scanner(),['nes'],self.out,quiet=True)
        self.assertEqual((self.out/'nes_gamelist.txt').read_bytes(),original)

    def test_lock_rejects_another_writer(self):
        self.out.mkdir()
        with acquire_lock(self.out/'lock',timeout=0):
            with self.assertRaises(OSError): acquire_lock(self.out/'lock',timeout=0)

    def test_storage_priority_active_folder_and_full_scan(self):
        other=self.root/'usb1';other.mkdir();(other/'NES').mkdir();(other/'NES/B.nes').touch()
        (self.nes/'A.nes').touch()
        scanner=Scanner(self.catalog,[str(self.games),str(other)],self.cache)
        self.assertEqual(scanner.folders('nes',active=True),[str(self.nes)])
        scan_outputs(scanner,['nes'],self.out,quiet=True)
        self.assertEqual(self.lines(),[str(self.nes/'A.nes'),str(other/'NES/B.nes')])

    def test_refresh_forces_metadata_cache_rebuild(self):
        self.zip(['A.nes']);scan_outputs(self.scanner(),['nes'],self.out,quiet=True)
        scanner=self.scanner(refresh=True);scan_outputs(scanner,['nes'],self.out,quiet=True)
        self.assertEqual((scanner.hits,scanner.misses),(0,1))

    def test_disappearing_storage_does_not_publish_empty(self):
        (self.nes/'A.nes').touch();scanner=self.scanner()
        scan_outputs(scanner,['nes'],self.out,quiet=True);before=self.lines()
        self.games.rename(self.root/'removed')
        with self.assertRaises(FileNotFoundError): scan_outputs(scanner,['nes'],self.out,quiet=True)
        self.assertEqual(self.lines(),before)

    def test_corrupt_later_zip_entry_cannot_publish_first_entry(self):
        path=self.zip(['A.nes','B.nes']);raw=path.read_bytes()
        positions=[i for i in range(len(raw)) if raw.startswith(b'PK\x01\x02',i)]
        path.write_bytes(raw[:positions[1]]+b'BAD!'+raw[positions[1]+4:])
        scanner=self.scanner();scan_outputs(scanner,['nes'],self.out,quiet=True)
        self.assertEqual(self.lines(),[]);self.assertEqual(scanner.corrupt,1)

    def test_cli_version_empty_and_unknown_statuses(self):
        command=[sys.executable,str(PACKAGE/'.MiSTer_SAM/samindex.py')]
        version=subprocess.run(command+['-version'],capture_output=True,text=True)
        self.assertEqual(version.returncode,0);self.assertIn('samindex-python',version.stdout)
        empty=subprocess.run(command+['-q','-s','nes','--root',str(self.games),'--cache',str(self.cache),'-o',str(self.out)],capture_output=True,text=True)
        self.assertEqual(empty.returncode,8);self.assertEqual(self.lines(),[])
        bad=subprocess.run(command+['-q','-s','invalid_core','-o',str(self.out)],capture_output=True,text=True)
        self.assertEqual(bad.returncode,2);self.assertEqual(self.lines(),[])

    def test_sigterm_keeps_previous_list_and_removes_staging_file(self):
        self.out.mkdir();(self.out/'nes_gamelist.txt').write_text('previous-valid\n')
        ready=self.root/'ready'
        code='''import sys,time
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import samindex
root,output,ready=sys.argv[2:]
def delayed(self,identifier,folder):
    yield folder+'/A.nes'
    Path(ready).touch()
    time.sleep(30)
samindex.Scanner.walk=delayed
sys.argv=['samindex','-q','-s','nes','--root',root,'-o',output]
sys.exit(samindex.main())
'''
        child=subprocess.Popen([sys.executable,'-c',code,str(PACKAGE/'.MiSTer_SAM'),str(self.games),str(self.out),str(ready)])
        try:
            deadline=time.monotonic()+10
            while not ready.exists() and time.monotonic()<deadline: time.sleep(.05)
            self.assertTrue(ready.exists())
            child.terminate();self.assertEqual(child.wait(timeout=5),143)
            self.assertEqual(self.lines(),['previous-valid'])
            self.assertEqual(list(self.out.glob('*.tmp.*')),[])
        finally:
            if child.poll() is None: child.kill();child.wait()


class ZipDirectoryTests(unittest.TestCase):
    def test_unicode_cp437_concatenated_and_zip64_names(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'test.zip'
            with zipfile.ZipFile(path,'w') as bundle:
                bundle.writestr('é.nes',b'fixture');bundle.writestr('a.nes',b'fixture')
            with DirectoryZip(path) as bundle: self.assertEqual(list(bundle.names()),['é.nes','a.nes'])
            raw=path.read_bytes().replace(b'a.nes',b'\x82.nes')
            path.write_bytes(b'concatenated-prefix'+raw)
            with DirectoryZip(path) as bundle: self.assertEqual(list(bundle.names()),['é.nes','é.nes'])
            # Add true ZIP64 end records to the small fixture, without allocating
            # a multi-gigabyte ROM. Central directory contents remain unchanged.
            end=raw.rfind(b'PK\x05\x06');fields=struct.unpack('<4s4H2LH',raw[end:end+22])
            count,size,offset=fields[4],fields[5],fields[6]
            end64=struct.pack('<4sQ2H2L4Q',b'PK\x06\x06',44,45,45,0,0,count,count,size,offset)
            locator=struct.pack('<4sLQL',b'PK\x06\x07',0,end,1)
            ordinary=struct.pack('<4s4H2LH',b'PK\x05\x06',0,0,65535,65535,0xffffffff,0xffffffff,0)
            path.write_bytes(raw[:end]+end64+locator+ordinary)
            with DirectoryZip(path) as bundle: self.assertEqual(list(bundle.names()),['é.nes','é.nes'])


if __name__ == '__main__': unittest.main(verbosity=2)
