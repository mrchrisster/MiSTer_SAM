"""INI changes are literal, owner-bound, and staged independently of input polls."""
from pathlib import Path
import sys
import tempfile
import unittest
from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam.config_reload import IniWatcher, parse_ini


class LiteralConfig(unittest.TestCase):
    def test_installed_ini_parses_without_losing_array_words_or_case(self):
        values = parse_ini((PACKAGE / 'MiSTer_SAM.ini').read_bytes())
        self.assertIn('Artwork_only', values)
        self.assertIn('exclude', values)
        self.assertEqual(parse_ini(b'exclude=( "read me" bios )\n')['exclude'], ('read me', 'bios'))

    def test_partial_quotes_and_shell_expressions_are_rejected(self):
        for data in (b'gametimer="unfinished\n', b'gametimer=$(touch /tmp/bad)\n', b'exclude=( "$(touch /tmp/bad)" )\n', b'gametimer=08;touch /tmp/bad\n'):
            with self.assertRaises(ValueError):
                parse_ini(data)


@unittest.skipIf(sys.platform == 'win32', 'native Linux session directory names required')
class ConfigReload(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ini = self.root / 'SAM.ini'
        self.initial = 'gametimer=180\nsamtimeout=60\ncorelist="snes,nes"\nm82="no"\nArtwork_only="Yes"\nexclude=( "read me" bios )\n'
        self.ini.write_text(self.initial)
        self.owner = dict(pid='321', start='77', phase='playing')
        self.session = self.root / 'session-321:77'
        self.session.mkdir()
        (self.session / 'config.ini').write_text(self.initial)
        self.watcher = IniWatcher(self.ini, self.root, self.root / 'lists')
        self.watcher.poll(self.owner)

    def marker(self):
        return dict(line.split('=', 1) for line in (self.session / 'config-update').read_text().splitlines())

    def edit(self, content):
        self.ini.write_text(content)
        self.assertIsNone(self.watcher.poll(self.owner))
        return self.watcher.poll(self.owner)

    def test_timer_idle_and_input_changes_need_no_selection_or_mode_restart(self):
        values = self.edit(self.initial.replace('gametimer=180', 'gametimer=30').replace('samtimeout=60', 'samtimeout=10') + 'listenjoy="No"\n')
        self.assertEqual(values['gametimer'], '30')
        marker = self.marker()
        self.assertEqual((marker['structural'], marker['selection']), ('0', '0'))
        self.assertEqual((marker['pid'], marker['start']), ('321', '77'))

    def test_selection_change_invalidates_policy_without_structural_restart(self):
        self.edit(self.initial.replace('snes,nes', 'nes') + 'rating="yes"\n')
        marker = self.marker()
        self.assertEqual((marker['structural'], marker['selection']), ('0', '1'))
        self.assertEqual(marker['setting_corelist'], 'nes')
        self.assertEqual((marker['exclude_0'], marker['exclude_1']), ('read me', 'bios'))

    def test_mode_changes_wait_for_structural_boundary(self):
        self.edit(self.initial.replace('m82="no"', 'm82="yes"'))
        self.assertEqual(self.marker()['structural'], '1')
        # A subsequent timer edit must not erase an unapplied mode change.
        self.edit(self.ini.read_text().replace('gametimer=180', 'gametimer=20'))
        self.assertEqual(self.marker()['structural'], '1')

    def test_case_sensitive_artwork_setting_is_preserved(self):
        values = parse_ini(b'Artwork_only="Yes"\nartwork_style="box2d"\n')
        self.assertIn('Artwork_only', values)
        self.assertNotIn('artwork_only', values)

    def test_partial_invalid_edit_retains_prior_marker(self):
        before = (self.session / 'config-update').read_bytes()
        self.ini.write_text('gametimer="unfinished\n')
        self.watcher.poll(self.owner)
        with self.assertRaises(ValueError):
            self.watcher.poll(self.owner)
        self.assertEqual((self.session / 'config-update').read_bytes(), before)
        self.assertEqual(self.watcher.values['gametimer'], '180')

    def test_literal_expression_cannot_become_reload_data(self):
        for content in (b'gametimer=$(touch /tmp/bad)\n', b'exclude=( "$(touch /tmp/bad)" )\n', b'gametimer=10;touch /tmp/bad\n'):
            with self.assertRaises(ValueError):
                parse_ini(content)

    def test_selection_can_revert_after_applied_snapshot(self):
        self.edit(self.initial.replace('snes,nes', 'nes'))
        revision = self.marker()['revision']
        (self.session / ('config-' + revision + '.ini')).replace(self.session / 'config.ini')
        self.edit(self.initial)
        self.assertEqual(self.marker()['selection'], '1')
        self.assertEqual(self.marker()['setting_corelist'], 'snes,nes')

    def test_ram_category_change_waits_for_selection_boundary(self):
        (self.root / 'category-preset').write_text('boot_id=fixture\npreset=pinball\n')
        self.assertIsNone(self.watcher.poll(self.owner))
        self.watcher.poll(self.owner)
        self.assertEqual((self.marker()['structural'], self.marker()['selection']), ('0', '1'))

    def test_permanent_exclusion_change_waits_for_selection_boundary(self):
        self.watcher.tags_path.parent.mkdir()
        self.watcher.tags_path.write_text('Vertical\n')
        self.watcher.poll(self.owner)
        self.watcher.poll(self.owner)
        self.assertEqual((self.marker()['structural'], self.marker()['selection']), ('0', '1'))

    def test_replacement_owner_gets_only_its_own_marker(self):
        replacement = self.root / 'session-322:78'
        replacement.mkdir()
        (replacement / 'config.ini').write_text(self.initial)
        self.watcher.poll(dict(pid='322', start='78'))
        record = dict(line.split('=', 1) for line in (replacement / 'config-update').read_text().splitlines())
        self.assertEqual((record['pid'], record['start']), ('322', '78'))


if __name__ == '__main__':
    unittest.main()
