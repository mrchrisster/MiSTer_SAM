import sys
from pathlib import Path
import unittest
from paths import PACKAGE
sys.path.insert(0,str(PACKAGE/'.MiSTer_SAM'))
from sam.input_options import InputOptions


class Options(unittest.TestCase):
    def setUp(self):
        self.base=dict(listenjoy=True,listenkeyboard=True,listenmouse=True,samdebug=False)
        self.options=InputOptions(self.base)

    def test_toggles_are_temporary_and_do_not_mutate_base(self):
        self.options.toggle('listenkeyboard')
        self.assertFalse(self.options.effective()['listenkeyboard'])
        self.assertTrue(self.options.base['listenkeyboard'])
        self.assertTrue(self.base['listenkeyboard'])
        self.options.toggle('listenkeyboard')
        self.assertTrue(self.options.effective()['listenkeyboard'])

    def test_same_ini_does_not_clear_override_but_changed_option_does(self):
        self.options.toggle('listenkeyboard');self.options.toggle('samdebug')
        self.options.update_ini(dict(self.base))
        self.assertFalse(self.options.effective()['listenkeyboard'])
        new=dict(self.base,listenkeyboard=False)
        self.options.update_ini(new)
        self.assertNotIn('listenkeyboard',self.options.overrides)
        self.assertIn('samdebug',self.options.overrides)
        self.assertTrue(self.options.effective()['samdebug'])

    def test_restore_returns_to_current_ini(self):
        for key in self.base:self.options.toggle(key)
        self.options.reset();self.assertEqual(self.options.effective(),self.base)


if __name__=='__main__':unittest.main()
