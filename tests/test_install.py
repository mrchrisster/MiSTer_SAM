"""Release deployment preserves user configuration, custom code and exclusions."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from paths import PACKAGE
spec = importlib.util.spec_from_file_location('sam_install', PACKAGE / 'MiSTer_SAM_install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class Install(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='sam-install-test-')
        self.addCleanup(self.tmp.cleanup)
        self.mister = Path(self.tmp.name) / 'media'
        self.scripts = self.mister / 'Scripts'
        self.scripts.mkdir(parents=True)

    def test_complete_first_install_has_public_lists_and_executable_entry(self):
        source = installer.checked_source(PACKAGE)
        installer.install(source, self.mister, 'test')
        for name in ['Gamelists', 'Rated', 'Blacklists', 'Ignore']:
            self.assertTrue((self.mister / 'SAM' / name).is_dir(), name)
        self.assertTrue((self.scripts / '.MiSTer_SAM/lib/engine.sh').is_file())
        self.assertTrue((self.scripts / 'MiSTer_SAM_on.sh').stat().st_mode & 0o111)
        self.assertFalse((self.scripts / '.MiSTer_SAM/partun').exists())
        self.assertFalse((self.scripts / '.SAM_refactor_backups').exists())

    def test_update_preserves_custom_settings_mappings_plugins_and_lists(self):
        payload = self.scripts / '.MiSTer_SAM'
        (payload / 'modules.d').mkdir(parents=True)
        (payload / 'modules').mkdir()
        (payload / 'sam_controllers.custom.json').write_text('{"custom": true}')
        (payload / 'modules.d/custom.module').write_text('name=custom\nenabled_by=Custom_enable\n')
        (payload / 'modules/custom.sh').write_text('custom_function(){ :; }\n')
        (payload / 'partun').write_text('obsolete')
        ini = 'corelist="nes"\nmute="no"\nCustom_enable="yes"\nbranch="main"\n'
        (self.scripts / 'MiSTer_SAM.ini').write_text(ini)
        public = self.mister / 'SAM'
        (public / 'Ignore').mkdir(parents=True)
        (public / 'Gamelists').mkdir()
        ignored = public / 'Ignore/nes_excludelist.txt'
        ignored.write_text('/games/Name = literal (USA).nes\n')
        selected = public / 'Gamelists/m82_list.txt'
        selected.write_text('My custom twelve-slot list\n')
        installer.install(installer.checked_source(PACKAGE), self.mister, 'test')
        self.assertEqual((self.scripts / 'MiSTer_SAM.ini').read_text(), ini.replace('branch="main"', 'branch="test"'))
        self.assertEqual(ignored.read_text(), '/games/Name = literal (USA).nes\n')
        self.assertEqual(selected.read_text(), 'My custom twelve-slot list\n')
        self.assertTrue((payload / 'modules/custom.sh').is_file())
        self.assertTrue((payload / 'modules.d/custom.module').is_file())
        self.assertEqual((payload / 'sam_controllers.custom.json').read_text(), '{"custom": true}')
        self.assertFalse((payload / 'partun').exists())
        saved = list((self.scripts / '.SAM_refactor_backups').glob('install-*/MiSTer_SAM.ini'))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].read_text(), ini)
        self.assertEqual(list(saved[0].parent.iterdir()), saved)

    def test_backup_only_copies_ini_leaving_caches_and_old_backups_untouched(self):
        ini = self.scripts / 'MiSTer_SAM.ini'
        contents = b'corelist="nes"\r\n# custom UTF-8: \xc3\xa9\r\nbranch="main"\r\n'
        ini.write_bytes(contents)
        cache = self.scripts / '.MiSTer_SAM/artwork/downloads/cover.jpg'
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b'existing cover cache')
        old = self.scripts / '.SAM_refactor_backups/install-old/before.tar'
        old.parent.mkdir(parents=True)
        old.write_bytes(b'old backup retained')
        source = installer.checked_source(PACKAGE)
        with patch.object(installer.tarfile, 'open', side_effect=AssertionError('No full archive allowed')):
            installer.install(source, self.mister, 'test')
            installer.install(source, self.mister, 'test')
        saved = list(old.parents[1].glob('install-*/MiSTer_SAM.ini'))
        self.assertEqual(len(saved), 2)
        self.assertTrue(any(path.read_bytes() == contents for path in saved))
        for path in saved:
            self.assertEqual(list(path.parent.iterdir()), [path])
        self.assertEqual(cache.read_bytes(), b'existing cover cache')
        self.assertEqual(old.read_bytes(), b'old backup retained')

    def test_backup_failure_aborts_before_installed_files_change(self):
        ini = self.scripts / 'MiSTer_SAM.ini'
        ini.write_text('branch="main"\n')
        entry = self.scripts / 'MiSTer_SAM_on.sh'
        entry.write_text('old script')
        source = installer.checked_source(PACKAGE)
        with patch.object(installer, 'copy_file', side_effect=OSError('Cannot write config backup')):
            with self.assertRaises(OSError):
                installer.install(source, self.mister, 'test')
        self.assertEqual(ini.read_text(), 'branch="main"\n')
        self.assertEqual(entry.read_text(), 'old script')
        self.assertFalse((self.scripts / '.MiSTer_SAM').exists())

    def test_legacy_custom_lists_migrate_without_losing_existing_exclusions(self):
        legacy = self.scripts / '.MiSTer_SAM/SAM_Gamelists'
        legacy.mkdir(parents=True)
        (legacy / 'nes_excludelist.txt').write_text('Already excluded\nNew exclusion\n')
        (legacy / 'm82_list.txt').write_text('Custom M82 game\n')
        public = self.mister / 'SAM/Ignore'
        public.mkdir(parents=True)
        (public / 'nes_excludelist.txt').write_text('Already excluded\n')
        installer.install(installer.checked_source(PACKAGE), self.mister, 'test')
        self.assertEqual((public / 'nes_excludelist.txt').read_text(), 'Already excluded\nNew exclusion\n')
        self.assertEqual((self.mister / 'SAM/Gamelists/m82_list.txt').read_text(), 'Custom M82 game\n')

    def test_incomplete_release_cannot_modify_installation(self):
        sentinel = self.scripts / 'MiSTer_SAM.ini'
        sentinel.write_text('keep this configuration')
        with self.assertRaises(RuntimeError):
            installer.checked_source(Path(self.tmp.name))
        self.assertEqual(sentinel.read_text(), 'keep this configuration')
        self.assertFalse((self.scripts / '.SAM_refactor_backups').exists())

    def test_download_selects_readable_bundle_without_disabling_verification(self):
        bundle = Path(self.tmp.name) / 'cacert.pem'
        bundle.write_text('test CA bundle')
        with patch.dict(installer.os.environ, {}, clear=True), patch.object(installer, 'CA_BUNDLES', [str(bundle) + '.missing', str(bundle)]):
            self.assertEqual(installer.curl_ca_options(), ['--cacert', str(bundle)])

    def test_download_respects_explicit_curl_certificate_bundle(self):
        with patch.dict(installer.os.environ, {'CURL_CA_BUNDLE': '/custom/ca.pem'}, clear=True):
            self.assertEqual(installer.curl_ca_options(), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
