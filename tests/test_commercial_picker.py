"""Title matching and copy preferences; no ROM reads or hardware actions."""
import json
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import unittest

from paths import PACKAGE
sys.path.insert(0,str(PACKAGE/'.MiSTer_SAM/modules'))
from commercial_picker import Catalogue,choose,matching,candidate,prepared


class CommercialPicker(unittest.TestCase):
    def pick(self,paths,query,**kwargs):
        return choose(paths,query,rng=random.Random(3),**kwargs)

    def test_original_does_not_select_sequels(self):
        paths=['/games/Super Mario Bros. 2 (USA).nes','/games/Super Mario Bros. 3 (USA).nes','/games/Super Mario Bros. (World).nes']
        self.assertEqual(self.pick(paths,'Super Mario Bros. (')[0],paths[2])
        self.assertIsNone(self.pick(paths[:2],'Super Mario Bros.')[0])

    def test_sequel_title_retains_its_number(self):
        paths=['/games/Army Men - Sarge\'s Heroes 2 (USA).z64','/games/Army Men - Sarge\'s Heroes (USA).z64']
        self.assertEqual(self.pick(paths,"Army Men - Sarge's Heroes")[0],paths[1])
        self.assertEqual(self.pick(paths,"Army Men - Sarge's Heroes 2")[0],paths[0])

    def test_author_and_directory_cannot_identify_a_game(self):
        paths=['/Dr. Mario/Castlevania.nes','/games/Castlevania Remake by Dr. Mario.nes','/games/Dr. Luigi (Dr. Mario Hack).nes']
        self.assertIsNone(self.pick(paths,'Dr. Mario')[0])

    def test_prefer_retail_over_hacks_betas_and_bad_dumps(self):
        paths=['/games/Game (USA) (Hack).nes','/games/Game (USA) (Beta).nes','/games/Game (USA) [b1].nes','/games/Game (Japan).nes']
        self.assertEqual(self.pick(paths,'Game')[0],paths[3])

    def test_prefer_standard_name_over_ranked_and_dated_copies(self):
        paths=['/games/06. Game (USA).nes','/games/003 Game (USA).nes','/games/1985-10-18 Game (USA).nes','/games/Game (World).nes']
        self.assertEqual(self.pick(paths,'Game')[0],paths[3])
        self.assertIn(self.pick(paths[:3],'Game')[0],paths[:3])

    def test_legitimate_numbers_and_catalogued_007_are_preserved(self):
        for name in ['1942','1080 Snowboarding','3-D WorldRunner']:
            path='/games/'+name+' (USA).nes'
            self.assertEqual(self.pick([path],name)[0],path)
        catalogue=Catalogue();catalogue.names.add('007 - Everything or Nothing (USA)'.casefold())
        path='/games/007 - Everything or Nothing (USA).gba'
        self.assertEqual(self.pick([path],'007 - Everything or Nothing',catalogue=catalogue)[0],path)

    def test_default_region_and_latest_official_revision(self):
        paths=['/games/Game (Japan).nes','/games/Game (Europe).nes','/games/Game (World).nes','/games/Game (USA).nes','/games/Game (USA) (Rev A).nes']
        self.assertEqual(self.pick(paths,'Game')[0],paths[4])

    def test_explicit_region_from_metadata_is_honored(self):
        paths=['/games/Game (USA).nes','/games/Game (Japan).nes']
        self.assertEqual(self.pick(paths,'Game (Japan')[0],paths[1])

    def test_catalogued_name_precedes_unrecognized_equivalent(self):
        catalogue=Catalogue();catalogue.names.add('game (world)')
        paths=['/games/Game (USA) [!].nes','/games/Game (World).nes']
        self.assertEqual(self.pick(paths,'Game',catalogue=catalogue)[0],paths[1])

    def test_unique_abbreviation_is_supported_but_ambiguity_is_rejected(self):
        paths=['/games/Boogerman - A Pick and Flick Adventure (USA).md']
        self.assertEqual(self.pick(paths,'Boogerman - A Pick')[0],paths[0])
        self.assertIsNone(self.pick(['/games/Mega Man 2.nes','/games/Mega Man 3.nes'],'Mega Man')[0])

    def test_unavailable_indexed_game_does_not_become_a_prefix_guess(self):
        catalogue=Catalogue();catalogue.aliases['drmario']={'drmario'}
        self.assertIsNone(self.pick(['/games/Dr. Mario RPG Adventure (USA).nes'],'Dr. Mario',catalogue=catalogue)[0])

    def test_explicit_alternatives_and_generic_metadata(self):
        paths=['/games/Virtua Fighter 2 (USA).chd','/games/Virtua Cop 2 (USA).chd','/games/Other (USA).chd']
        found,info=self.pick(paths,r'Virtua Fighter 2 \| Virtua Cop 2')
        self.assertIn(found,paths[:2]);self.assertEqual(info['mode'],'matched')
        self.assertEqual(self.pick(paths,'')[1]['mode'],'generic')
        self.assertEqual(self.pick(paths,'(USA')[1]['mode'],'generic')

    def test_multi_game_compilation_is_not_an_abbreviated_match(self):
        self.assertIsNone(self.pick(['/games/Super Mario All-Stars + Super Mario World (USA).sfc'],'Super Mario World')[0])

    def test_fallback_is_explicit_and_empty_list_stays_empty(self):
        path='/games/Other (USA).nes'
        self.assertEqual(self.pick([path],'Absent',fallback=True),(path,dict(mode='fallback',candidates=1,title='Other',catalogued=False,modified=False,labelled=False)))
        self.assertIsNone(self.pick([],'Absent',fallback=True)[0])

    def test_generic_game_choice_is_not_biased_by_revision_numbers(self):
        paths=['/games/A (USA).nes','/games/B (USA) (Rev 9).nes']
        outcomes={choose(paths,'',rng=random.Random(seed))[0] for seed in range(20)}
        self.assertEqual(outcomes,set(paths))

    def test_published_alias_can_match_without_fuzzy_search(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory);(p/'index.tsv').write_text('Alternate Name (USA)\tcrc\t1\tActual Name (USA)\n')
            catalogue=Catalogue([p]);path='/games/Actual Name (USA).nes'
            self.assertEqual(self.pick([path],'Alternate Name',catalogue=catalogue)[0],path)

    def test_explicit_unlicensed_alias_does_not_select_licensed_edition(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)
            (p/'index.tsv').write_text('Tetris (USA)\tc\t1\tTetris (USA)\nTetris Tengen (USA)\tc\t2\tTetris (USA) (Unl)\n')
            catalogue=Catalogue([p]);paths=['/games/Tetris (USA).nes','/games/Tetris Tengen (USA).nes']
            self.assertEqual(self.pick(paths,'Tetris Tengen',catalogue=catalogue)[0],paths[1])

    def test_literal_title_precedes_related_anniversary_alias(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)
            (p/'index.tsv').write_text('Game (World)\tc\t1\tGame (World)\nGame - Anniversary (Japan)\tc\t2\tGame (World)\n')
            catalogue=Catalogue([p]);paths=['/games/Game (World).nes','/games/Game - Anniversary (Japan).nes']
            self.assertEqual(self.pick(paths,'Game',catalogue=catalogue)[0],paths[0])
            self.assertEqual(self.pick(paths,'Game - Anniversary',catalogue=catalogue)[0],paths[1])

    def test_region_preference_applies_across_translated_title_aliases(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)
            (p/'index.tsv').write_text('Other Name (Japan)\tc\t1\tGame (World)\nGame (World)\tc\t2\tGame (World)\n')
            catalogue=Catalogue([p]);paths=['/games/Other Name (Japan).nes','/games/Game (World).nes']
            self.assertEqual(self.pick(paths,'',catalogue=catalogue)[0],paths[1])

    def test_session_cache_refreshes_after_list_or_catalog_change(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory);listing=p/'list';cache=p/'cache';index=p/'index.tsv'
            listing.write_text('/games/A (USA).nes\n');index.write_text('A (USA)\tc\t1\tA (USA)\n')
            _,items=prepared(listing,[p],cache);self.assertTrue(items[0].catalogued)
            _,again=prepared(listing,[p],cache);self.assertEqual(items,again)
            listing.write_text('/games/B (USA).nes\n')
            _,items=prepared(listing,[p],cache);self.assertFalse(items[0].catalogued)
            index.write_text('B (USA)\tc\t1\tB (USA)\n')
            _,items=prepared(listing,[p],cache);self.assertTrue(items[0].catalogued)
            cache.write_text('{"broken": true}')
            _,items=prepared(listing,[p],cache);self.assertTrue(items[0].catalogued)

    def test_cli_literal_paths_and_result_report(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory);path='/games/Game = $literal (USA).nes'
            (p/'list').write_text(path+'\n');(p/'query').write_text('Game = $literal')
            command=[sys.executable,str(PACKAGE/'.MiSTer_SAM/modules/commercial_picker.py'),'--core','nes','--list',str(p/'list'),'--query-file',str(p/'query'),'--result-file',str(p/'result')]
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout.strip(),path)
            self.assertEqual(json.loads((p/'result').read_text())['mode'],'matched')


if __name__=='__main__':unittest.main(verbosity=2)
