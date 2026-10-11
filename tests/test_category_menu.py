"""Smart presets ask for scope without resetting or destroying lists."""
import unittest
import test_menu


class CategoryMenu(unittest.TestCase):
    shell = test_menu.Menu.shell

    def context(self):
        return r'''
sam_category_menu_ready(){ sam_category_preset=off; sam_category_exclusions=; }
sam_category_valid(){ case "$1" in off|pinball|arcade_horizontal|arcade_vertical|shmups|fighting|puzzle|racing) return 0;; *) return 1;; esac; }
sam_category_tags_valid(){ [[ "$1" == Beta,USA || -z "$1" ]]; }
sam_category_store(){ printf 'STORE:%s:%s:%s\n' "$1" "$2" "$3"; }
reset_ini(){ echo FORBIDDEN_RESET; }
blacklistpath=/missing/category-fixture
'''

    def test_cancel_category_and_cancel_scope_do_not_save_or_reset(self):
        self.assertEqual(self.shell(self.context() + r'''
sam_dialog(){ echo pinball >&2; return 255; }; menu_smart_presets
'''), '')
        self.assertEqual(self.shell(self.context() + r'''
n=0; sam_dialog(){ case " $* " in *" --menu "*) ((n+=1));
if ((n==1)); then echo pinball >&2; else echo permanent >&2; return 255; fi;; esac; }
menu_smart_presets
'''), '')

    def test_permanent_and_reboot_scopes_forward_only_validated_policy(self):
        for scope in ('permanent', 'reboot'):
            with self.subTest(scope=scope):
                out = self.shell(self.context() + r'''
n=0; sam_dialog(){ case " $* " in *" --menu "*) ((n+=1));
if ((n==1)); then echo pinball >&2; else echo ''' + scope + r''' >&2; fi;; esac; }
menu_smart_presets
''')
                self.assertEqual(out.strip(), 'STORE:pinball::' + scope)

    def test_category_exclusions_save_metadata_tags_without_rebuilding_lists(self):
        out = self.shell(self.context() + r'''
sam_dialog(){ case " $* " in
*" --checklist "*) printf 'Beta\nUSA\n' >&2;; *" --menu "*) echo reboot >&2;; esac; }
find(){ echo FORBIDDEN_SCAN; }; sync(){ echo FORBIDDEN_SYNC; }
menu_cat_exclude
''')
        self.assertEqual(out.strip(), 'STORE:off:Beta,USA:reboot')


if __name__ == '__main__':
    unittest.main()
