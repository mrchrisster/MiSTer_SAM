"""Reviewed titles cannot whitelist unrelated sequels, directories or hacks."""
from pathlib import Path
import importlib.util
import sys
import tempfile
import unittest
from paths import PACKAGE

sys.path.insert(0,str(PACKAGE/'.MiSTer_SAM'))
from sam_kids_filter import filter_candidates
from sam_titles import title_key


class KidsFilter(unittest.TestCase):
    def test_exact_title_regions_archive_and_number_prefix(self):
        paths=['/NES/collection.zip/06. Super Mario Bros. (USA) (Rev 1).nes',
               '/NES/collection.zip/Super Mario Bros. 2 (USA).nes',
               '/NES/Super Mario Bros./Mature Game.nes']
        self.assertEqual(list(filter_candidates(paths,['Super Mario Bros.\r\n','\n'])),paths[:1])

    def test_altered_releases_are_not_certified_by_base_title(self):
        paths=['/NES/Hacks/Super Mario Bros. (USA).nes',
               '/NES/Super Mario Bros. (Hack 1).nes',
               '/NES/Super Mario Bros. (Proto).nes',
               '/NES/Super Mario Bros. (USA) [T-En].nes',
               '/NES/Super Mario Bros. (USA) [T+Eng].nes',
               '/NES/Super Mario Bros. (bootleg).nes',
               'Demo: Super Mario Bros. (USA).nes',
               'demo: Super Mario Bros. (USA).nes',
               '/NES/Super Mario Bros. (USA).nes']
        self.assertEqual(list(filter_candidates(paths,['Super Mario Bros.'])),paths[-1:])

    def test_punctuation_articles_unicode_and_duplicates(self):
        paths=['/GB/Pokemon Pinball (USA).gbc','/GB/Pokémon Pinball (Europe).gbc',
               '/SNES/Lion King, The (USA).sfc']
        self.assertEqual(list(filter_candidates(paths,['Pokémon Pinball','The Lion King'])),[paths[0],paths[2]])

    def test_ambiguous_franchise_is_not_an_alias(self):
        self.assertEqual(list(filter_candidates(['/PSX/Final Fantasy VII.chd'],['Final Fantasy'])),[])

    def test_generic_cd_layout_requires_exact_immediate_reviewed_parent(self):
        paths=['/PSX/Spyro the Dragon (USA)/Disc 1.chd',
               '/PSX/Spyro the Dragon (USA)/Unrelated Game.chd',
               '/PSX/Spyro the Dragon (USA)/other/Disc1.chd']
        self.assertEqual(list(filter_candidates(paths,['Spyro the Dragon'])),paths[:1])

    def test_empty_and_comment_only_lists_exclude_everything(self):
        self.assertEqual(list(filter_candidates(['/NES/Super Mario Bros.nes'],['','#Super Mario Bros.'])),[])

    def test_legacy_directory_bytes_survive_but_bad_title_bytes_are_unknown(self):
        good='/legacy-\udce9/Pinball (USA).nes'
        bad='/games/Pi\udce9nball (USA).nes'
        self.assertEqual(list(filter_candidates([good,bad],['Pinball'])),[good])


if __name__=='__main__':unittest.main()
