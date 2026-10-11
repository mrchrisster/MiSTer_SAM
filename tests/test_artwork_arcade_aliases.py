"""Arcade set aliases resolve by index; title guesses cannot approve clones."""
from pathlib import Path
import sys
import tempfile
import unittest

ARTWORK = Path(__file__).resolve().parents[1] / '.MiSTer_SAM/artwork'
sys.path.insert(0, str(ARTWORK))
from sam_artwork import Catalogue


class ArcadeArtworkAliases(unittest.TestCase):
    def test_reviewed_clone_index_alias_matches_same_cover(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pack = root / 'docs/Arcade/Artwork'
            pack.mkdir(parents=True)
            # Names-only eligibility does not decode; launch checks decode later.
            (pack / 'gaunt2.jpg').write_bytes(b'fixture image filename')
            (pack / 'index.tsv').write_text('gaunt22p\t\t\tgaunt2\n', encoding='utf-8')
            clone = root / 'Gauntlet II (2 Players, rev 2).mra'
            clone.write_text('<misterromdescription><setname>gaunt22p</setname></misterromdescription>', encoding='utf-8')
            missing = root / 'Gauntlet II (unindexed clone).mra'
            missing.write_text('<misterromdescription><setname>unindexed</setname></misterromdescription>', encoding='utf-8')
            catalogue = Catalogue(str(ARTWORK / 'sam_artwork_resolver.py'), root / 'cache.json')
            catalogue.ns['_PACK_MOUNTS'] = [str(root)]
            found, reason = catalogue.resolve('arcade', str(clone), validate=False)
            self.assertEqual(found, str(pack / 'gaunt2.jpg'))
            self.assertEqual(reason, '')
            self.assertFalse(catalogue.resolve('arcade', str(missing), validate=False)[0])
            # A false console classification cannot route this friendly name to
            # Arcade. This reproduces the inspected Monitor SAM branch limitation.
            self.assertEqual(catalogue.ns['_pack_folders']('Arcade'), [])
            self.assertEqual(catalogue.ns['_pack_key_from_state'](str(clone), True), ['gaunt22p'])


if __name__ == '__main__':
    unittest.main()
