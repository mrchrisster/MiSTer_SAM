"""Rebuild eligibility tests. SPDX-License-Identifier: GPL-3.0-or-later."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'tools/rebuild_kids_whitelists.py'
spec = importlib.util.spec_from_file_location('kids_rebuild', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WhitelistRebuildTests(unittest.TestCase):
    def test_conflicting_and_older_age_ratings_excluded(self):
        catalog = {'nes': {'safe': {'titles': ['Safe'], 'ratings': ['E', 'KA']},
                          'mixed': {'titles': ['Mixed'], 'ratings': ['E', 'T']},
                          'ten': {'titles': ['Ten'], 'ratings': ['E10+']}}}
        result = module.select_titles('nes', catalog, {'nes': ['Safe', 'Mixed', 'Ten']})
        self.assertEqual([entry['title'] for entry in result], ['Safe'])

    def test_platform_ratings_do_not_transfer(self):
        catalog = {'nes': {'title': {'titles': ['Title'], 'ratings': ['E']}}}
        self.assertEqual(module.select_titles('psx', catalog, {}), [])

    def test_erroneous_metadata_is_not_an_approval(self):
        import json
        manifest = json.loads((path.parents[1] / 'docs/kids-curated.json').read_text(encoding='utf-8'))
        bad = {'genesis': ['Mortal Kombat II', 'Mortal Kombat 3', 'Duke Nukem 3D'],
               'gbc': ['Grand Theft Auto', 'Grand Theft Auto 2', 'Resident Evil Gaiden', 'Perfect Dark']}
        for core, titles in bad.items():
            catalog = {core: {module.title_key(title): {'titles': [title], 'ratings': ['E']} for title in titles}}
            result = module.select_titles(core, catalog, manifest['cores'])
            self.assertTrue({module.title_key(title) for title in titles}.isdisjoint(
                module.title_key(entry['title']) for entry in result))

    def test_neogeo_stock_romset_aliases_are_exact_and_reviewed(self):
        import json
        from sam_kids_filter import filter_candidates
        manifest = json.loads((path.parents[1] / 'docs/kids-curated.json').read_text(encoding='utf-8'))
        entries = module.select_titles('neogeo', {}, manifest['cores'])
        entries = module.include_romset_aliases(entries, manifest['romset_aliases']['neogeo'])
        titles = [entry['title'] for entry in entries]
        good = ['/NEOGEO/' + alias + '.neo' for alias in manifest['romset_aliases']['neogeo']]
        bad = ['/NEOGEO/kof98.neo', '/NEOGEO/garou.neo', '/NEOGEO/pbobblenb.neo',
               '/NEOGEO/neodrift.neo', '/NEOGEO/Hacks/pbobblen.neo']
        self.assertEqual(list(filter_candidates(good + bad, titles)), good)
        with self.assertRaises(ValueError):
            module.include_romset_aliases(entries, {'kof98': {'title': 'King of Fighters 98', 'source': 'test'}})

    def test_altered_releases_rejected_and_keys_deduplicated(self):
        result = module.select_titles('nes', {}, {'nes': ['Puzzle', 'Puzzle (USA)', 'Puzzle (Beta)', 'Hack (Unl)']})
        self.assertEqual([entry['title'] for entry in result], ['Puzzle'])


if __name__ == '__main__':
    unittest.main()
