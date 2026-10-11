"""Exact genre metadata, curated fallback and category scope fixtures."""
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
import zipfile
from unittest.mock import patch

from paths import PACKAGE
import test_shell

MODULES = PACKAGE / '.MiSTer_SAM/modules'
spec = importlib.util.spec_from_file_location('sam_category_filter_test', MODULES / 'category_filter.py')
category = importlib.util.module_from_spec(spec)
spec.loader.exec_module(category)
ALIASES = json.loads((MODULES / 'category-aliases.json').read_text())


class CategoryMetadata(unittest.TestCase):
    def select(self, preset, paths, master=None, core='snes'):
        return category.filter_paths(core, preset, paths, paths if master is None else master, ALIASES)

    def test_explicit_genre_folders_and_no_title_substrings(self):
        selected = '/games/SNES/3 Genres/Pinball/Pinball Dreams (USA).sfc'
        wrong = '/games/SNES/3 Genres/Platformers/Pinball Impostor.sfc'
        title_folder = '/games/SNES/Pinball/Unknown.sfc'
        self.assertEqual(self.select('pinball', [selected, wrong, title_folder]), [selected])

    def test_numbered_all_pinball_label_requires_the_explicit_genre_parent(self):
        valid = '/games/SNES/Genre/1AllPinballGames/Example.sfc'
        title_folder = '/games/SNES/1AllPinballGames/Unclassified.sfc'
        self.assertEqual(self.select('pinball', [valid, title_folder]), [valid])

    def test_verified_fighters_labels_and_no_first_person_shooter_misclassification(self):
        fighter = '/games/NES/Genre/Fighters (1v1)/Example.nes'
        fps = '/games/SNES/Genre/First Person Shooters/Example.sfc'
        self.assertEqual(self.select('fighting', [fighter], core='nes'), [fighter])
        self.assertEqual(self.select('shmups', [fps]), [])

    def test_folder_presence_in_master_prevents_fallback_after_other_filters(self):
        master = ['/games/SNES/Genres/Pinball/Pinball Dreams.sfc',
                  '/games/SNES/All/Pinball Fantasies.sfc']
        # Kids/Ignore/artwork already removed the sole folder candidate.
        self.assertEqual(self.select('pinball', master[1:], master), [])

    def test_master_genre_membership_survives_dedup_retaining_the_regional_copy(self):
        genre = '/games/NES/Genre/Pinball/Pinball Dreams (USA).nes'
        retained = '/games/NES/1 USA/Pinball Dreams (USA).nes'
        sequel = '/games/NES/1 USA/Pinball Dreams II (USA).nes'
        unrelated = '/games/NES/1 USA/Pinball Fantasies (USA).nes'
        master = [retained, sequel, unrelated, genre]
        self.assertEqual(self.select('pinball', [retained, sequel, unrelated], master, core='nes'), [retained])
        # The core's own master supplies membership; a SNES genre entry is not
        # consulted when filtering a separate NES master with no such title.
        self.assertEqual(self.select('pinball', [retained],
            ['/games/NES/Genre/Pinball/Unrelated Title.nes'], core='nes'), [])

    def test_generic_cd_disc_key_never_becomes_global_genre_membership(self):
        genre = '/games/PSX/Genre/Pinball/Pro-Pinball - The Web/disc1.chd'
        retained = '/games/PSX/All/Pro-Pinball - The Web/disc1.chd'
        wrong = '/games/PSX/All/Unrelated Game/disc1.chd'
        self.assertEqual(self.select('pinball', [retained, wrong], [genre, retained, wrong], core='psx'), [retained])

    def test_absent_genre_folders_use_exact_curated_titles(self):
        exact = '/games/SNES/All/Pinball Dreams (USA) (Rev 1).sfc'
        containing = '/games/SNES/All/Pinball Dreams Collection.sfc'
        self.assertEqual(self.select('pinball', [exact, containing]), [exact])

    def test_cd_title_directories_are_not_genre_metadata(self):
        valid = '/games/PSX/Pro-Pinball - The Web/Pro Pinball - The Web (Europe).chd'
        unknown = '/games/PSX/Pinball/Unclassified Game.chd'
        self.assertEqual(self.select('pinball', [valid, unknown], core='psx'), [valid])

    def test_generic_cd_leaf_can_use_only_its_exact_immediate_title_directory(self):
        paths = ['/games/PSX/Pro-Pinball - The Web/disc1.chd',
                 '/games/PSX/Pro-Pinball - The Web/Track01.bin',
                 '/games/PSX/Pro-Pinball - The Web/Unreviewed Game.chd',
                 '/games/PSX/Pro-Pinball - The Web/Extras/disc1.chd',
                 '/games/PSX/Pinball/disc1.chd']
        self.assertEqual(self.select('pinball', paths, core='psx'), paths[:2])

    def test_psx_regional_short_title_alias_and_publisher_prefix_are_exact(self):
        paths = ['/games/PSX/Pro-Pinball (Europe).chd',
                 '/games/PSX/Pro-Pinball (USA).chd',
                 "/games/PSX/Saban's Power Rangers Zeo - Full Tilt Battle Pinball (USA).chd",
                 '/games/PSX/Pro-Pinball Unreviewed Compilation.chd']
        self.assertEqual(self.select('pinball', paths, core='psx'), paths[:3])

    def test_neogeo_short_romset_aliases_do_not_match_other_versions(self):
        self.assertEqual(self.select('fighting', ['/games/NeoGeo/kof98.neo', '/games/NeoGeo/kof98hack.neo'], core='neogeo'), ['/games/NeoGeo/kof98.neo'])
        self.assertEqual(self.select('puzzle', ['/games/NeoGeo/PBobbl2N.neo'], core='neogeo'), ['/games/NeoGeo/PBobbl2N.neo'])
        self.assertEqual(self.select('racing', ['/games/NeoGeo/Neo Drift Out (USA).neo'], core='neogeo'), ['/games/NeoGeo/Neo Drift Out (USA).neo'])

    def test_amiga_and_dos_fallbacks_cover_reviewed_title_families(self):
        self.assertEqual(self.select('puzzle', ['Game: Lemmings', 'Game: Lemmings Unreviewed Sequel'], core='amiga'), ['Game: Lemmings'])
        self.assertEqual(self.select('racing', ['/media/fat/_DOS Games/Stunts.mgl', '/media/fat/_DOS Games/Stunts Again.mgl'], core='ao486'), ['/media/fat/_DOS Games/Stunts.mgl'])

    def test_unknown_core_or_empty_category_never_returns_unfiltered_rows(self):
        self.assertEqual(self.select('pinball', ['/games/n64/Super Mario 64.z64'], core='n64'), [])
        self.assertEqual(self.select('puzzle', []), [])

    def test_orientation_accepts_only_arcade_and_declared_metadata(self):
        paths = ['/_Arcade/_Horizontal/Some Game.mra', '/_Arcade/_Vertical/Another.mra',
                 '/_Arcade/_HorizontalSomething/Unknown.mra']
        self.assertEqual(self.select('arcade_horizontal', paths, core='arcade'), paths[:1])
        self.assertEqual(self.select('arcade_horizontal', paths, core='snes'), [])

    def test_mra_orientation_fallback_never_guesses_missing_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            horizontal = Path(directory) / 'Horizontal Title.mra'
            vertical = Path(directory) / 'Vertical Title.mra'
            missing = Path(directory) / 'Horizontal Fake.mra'
            horizontal.write_text('<misterromdescription><rotation>0</rotation></misterromdescription>')
            vertical.write_text('<misterromdescription><rotation>vertical (cw)</rotation></misterromdescription>')
            missing.write_text('<misterromdescription><name>Horizontal Fake</name></misterromdescription>')
            paths = [str(horizontal), str(vertical), str(missing)]
            self.assertTrue(category.orientation_matches(paths[0], 'arcade_horizontal'))
            self.assertTrue(category.orientation_matches(paths[1], 'arcade_vertical'))
            self.assertFalse(category.orientation_matches(paths[2], 'arcade_horizontal'))
            vertical.write_text('<misterromdescription><rotation>90</rotation></misterromdescription>')
            self.assertTrue(category.orientation_matches(paths[1], 'arcade_vertical'))

    def test_organizer_exact_filename_and_agreeing_axis_aliases_need_no_mra_opens(self):
        index = category.orientation_index_from_data({
            'a': dict(file='Alpha Game (World).mra', rotation=0),
            'b': dict(file='Alpha Game (Europe).mra', rotation=180),
            'c': dict(file='Beta Game (World).mra', rotation=90),
            'd': dict(file='Beta Game (Europe).mra', rotation=0),
            'missing': dict(file='Missing Rotation.mra'),
            'bool': dict(file='Invalid Boolean.mra', rotation=True),
            'g': dict(file='Gamma Game (World).mra', rotation=0),
            'g-unknown': dict(file='Gamma Game (Japan).mra'),
        })
        rows = ['/_Arcade/Alpha Game (USA).mra', '/_Arcade/Beta Game (Japan).mra',
                '/_Arcade/Beta Game (World).mra', '/_Arcade/Missing Rotation.mra']
        with patch.object(category, 'orientation_fields', side_effect=AssertionError('bulk MRA open')):
            self.assertEqual(category.filter_paths('arcade', 'arcade_horizontal', rows, rows, ALIASES, index), rows[:1])
            self.assertEqual(category.filter_paths('arcade', 'arcade_vertical', rows, rows, ALIASES, index), rows[2:3])
        self.assertIsNone(index.axis(rows[1]))
        self.assertIsNone(index.axis('/_Arcade/Gamma Game (USA).mra'))

    def test_missing_organizer_cache_uses_reviewed_seeds_without_catalogue_reads(self):
        rows = ['/_Arcade/Out Run (USA).mra', '/_Arcade/Galaga (USA).mra', '/_Arcade/Unknown Game.mra']
        with patch.object(category, 'orientation_fields', side_effect=AssertionError('bulk MRA open')):
            self.assertEqual(self.select('arcade_horizontal', rows, core='arcade'), rows[:1])
            self.assertEqual(self.select('arcade_vertical', rows, core='arcade'), rows[1:2])

    def test_organizer_zip_payload_is_bounded_and_does_not_default_missing_rotation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'data.zip'
            with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr('mad_db.json', json.dumps({'game': dict(file='Game.mra', rotation=0)}))
            self.assertEqual(category.load_orientation_index([path]).axis('/_Arcade/Game.mra'), 'horizontal')
            with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr('mad_db.json', b' ' * (2 * 1024 * 1024 + 1))
            self.assertIsNone(category.load_orientation_index([path]))
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('mad_db.json', json.dumps({'game': dict(file='Game.mra')}))
            self.assertIsNone(category.load_orientation_index([path]))

    def test_selected_header_validation_rejects_stale_index_axis(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Out Run (USA).mra'
            path.write_text('<misterromdescription><rotation>vertical</rotation><rom/></misterromdescription>')
            index = category.orientation_index_from_data({'outrun': dict(file=path.name, rotation=0)})
            self.assertEqual(category.filter_paths('arcade', 'arcade_horizontal', [path.as_posix()], [path.as_posix()], ALIASES, index), [path.as_posix()])
            self.assertFalse(category.orientation_matches(str(path), 'arcade_horizontal'))

    def test_cli_preserves_legacy_path_bytes_and_unknown_title_bytes_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / 'list.txt', root / 'selected.txt'
            selected = b'/games/legacy-\xe9/Pinball (USA).nes\n'
            source.write_bytes(b'/games/NES/Unrelated \xe9.nes\n' + selected + b'/games/NES/Pinball\xff.nes\n')
            result = subprocess.run([sys.executable, str(MODULES / 'category_filter.py'),
                '--core', 'nes', '--preset', 'pinball', '--list', str(source), '--master', str(source),
                '--aliases', str(MODULES / 'category-aliases.json'), '--output', str(output)],
                capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_bytes().replace(b'\r\n', b'\n'), selected)

    def test_mra_header_stops_before_embedded_rom_and_ignores_late_metadata(self):
        class Reader(io.BytesIO):
            def read(self, count=-1):
                chunk = super().read(count)
                self.bytes_read += len(chunk)
                return chunk
        for header, expected in ((b'<rotation>vertical (ccw)</rotation>', True), (b'', False)):
            source = Reader(b'<misterromdescription>' + header + b'<rom><data>' +
                            b'A' * (1024 * 1024) + b'</data></rom><rotation>vertical</rotation></misterromdescription>')
            source.bytes_read = 0
            with patch.object(Path, 'open', return_value=source):
                self.assertEqual(category.orientation_matches('/fixture.mra', 'arcade_vertical'), expected)
            self.assertLessEqual(source.bytes_read, category.MRA_HEADER_CHUNK)

    def test_mra_header_limit_is_bounded_and_nested_metadata_is_not_authoritative(self):
        source = io.BytesIO(b'<misterromdescription><!--' + b'A' * (category.MRA_HEADER_LIMIT + 4096) +
                            b'--><rotation>vertical</rotation></misterromdescription>')
        with patch.object(Path, 'open', return_value=source):
            self.assertFalse(category.orientation_matches('/fixture.mra', 'arcade_vertical'))
        source = io.BytesIO(b'<misterromdescription><note><rotation>vertical</rotation></note></misterromdescription>')
        with patch.object(Path, 'open', return_value=source):
            self.assertFalse(category.orientation_matches('/fixture.mra', 'arcade_vertical'))

    def test_release_exclusions_use_metadata_not_arbitrary_title_words(self):
        self.assertTrue(category.excluded_by_tags('/games/NES/2 Japan/Example.nes', {'japan'}))
        self.assertTrue(category.excluded_by_tags('/games/NES/Example (USA, Europe).nes', {'usa'}))
        self.assertTrue(category.excluded_by_tags('/games/NES/Example [Hack 1].nes', {'hack'}))
        self.assertTrue(category.excluded_by_tags('/games/NES/Example (Proto).nes', {'prototype'}))
        self.assertTrue(category.excluded_by_tags('/games/NES/Example [T+Eng].nes', {'translations'}))
        self.assertFalse(category.excluded_by_tags('/games/NES/USA Racer.nes', {'usa'}))
        self.assertFalse(category.excluded_by_tags('/games/NES/Hack Attack.nes', {'hack'}))


class CategoryScope(unittest.TestCase):
    setUp = test_shell.Shell.setUp
    shell = test_shell.Shell.shell
    assertShell = test_shell.Shell.assertShell

    def context(self):
        return '''
SAM_BOOT_ID_FILE="$mrsamtmp/boot-id"; printf 'boot-one\\n' > "$SAM_BOOT_ID_FILE"
sam_load_module category
'''

    def test_until_reboot_overrides_saved_choice_without_ini_write(self):
        self.assertShell(self.context() + '''
category_preset=puzzle
before=$(<"$samini_file")
sam_category_read_scope
sam_category_save pinball reboot
[[ "$sam_category_preset" == pinball && $(<"$samini_file") == "$before" ]]
printf 'boot-two\\n' > "$SAM_BOOT_ID_FILE"
sam_category_read_scope
[[ "$sam_category_preset" == puzzle ]]
''')

    def test_permanent_choice_clears_temporary_override_and_persists_tags(self):
        self.assertShell(self.context() + '''
sam_category_store pinball usa reboot
sam_category_store racing japan permanent
[[ ! -e "$mrsamtmp/category-preset" ]]
[[ "$sam_category_preset:$sam_category_exclusions" == racing:japan ]]
grep -qx 'category_preset="racing"' "$samini_file"
[[ $(<"$gamelistpath/.excludetags") == japan ]]
''')

    def test_temporary_state_is_literal_and_invalid_matching_boot_fails_closed(self):
        self.assertShell(self.context() + '''
printf 'boot_id=boot-one\\npreset=$(touch unsafe)\\n' > "$mrsamtmp/category-preset"
! sam_category_read_scope
[[ ! -e unsafe ]]
''')

    def test_pinball_policy_skips_only_static_screen_blacklist(self):
        self.assertShell(self.context() + '''
category_preset=pinball; sam_category_read_scope
sam_filter_static_blacklist=yes
sam_emit filter_policy snes
[[ "$sam_filter_static_blacklist:$disable_blacklist" == no:no ]]
category_preset=puzzle; sam_category_read_scope
sam_filter_static_blacklist=yes
sam_emit filter_policy snes
[[ "$sam_filter_static_blacklist" == yes ]]
''')

    def test_active_category_stamp_tracks_filter_and_title_helper_changes(self):
        self.assertShell(self.context() + '''
category_preset=pinball; sam_category_read_scope
mrsampath="$mrsamtmp/stamp-fixture"; mkdir -p "$mrsampath/modules"
printf '{}\\n' > "$mrsampath/modules/category-aliases.json"
printf 'filter\\n' > "$mrsampath/modules/category_filter.py"
printf 'titles\\n' > "$mrsampath/sam_titles.py"
before=$(sam_category_stamp snes)
printf 'changed\\n' >> "$mrsampath/modules/category_filter.py"
after_filter=$(sam_category_stamp snes)
[[ "$before" != "$after_filter" ]]
printf 'changed\\n' >> "$mrsampath/sam_titles.py"
[[ "$after_filter" != "$(sam_category_stamp snes)" ]]
''')

    def test_orientation_cache_stamp_tracks_organizer_updates(self):
        self.assertShell(self.context() + '''
category_preset=arcade_horizontal; sam_category_read_scope
SAM_ARCADE_ORGANIZER_DATA="$mrsamtmp/data.zip"; printf 'first\\n' > "$SAM_ARCADE_ORGANIZER_DATA"
before=$(sam_category_stamp arcade)
printf 'changed\\n' >> "$SAM_ARCADE_ORGANIZER_DATA"
[[ "$before" != "$(sam_category_stamp arcade)" ]]
''')

    def test_selected_orientation_guard_precedes_artwork_and_rejects_unknown(self):
        self.assertShell(self.context() + '''
category_preset=arcade_horizontal; sam_category_read_scope
path="$mrsamtmp/Out Run.mra"
printf '<misterromdescription><rotation>horizontal</rotation><rom/></misterromdescription>\\n' > "$path"
sam_emit candidate_prepare arcade "$path"
printf '<misterromdescription><rotation>vertical</rotation><rom/></misterromdescription>\\n' > "$path"
! sam_emit candidate_prepare arcade "$path"
printf '<misterromdescription><rom/><rotation>horizontal</rotation></misterromdescription>\\n' > "$path"
! sam_emit candidate_prepare arcade "$path"
''')

    def test_orientation_overrides_only_the_legacy_orientation_sentinel(self):
        self.assertShell(self.context() + '''
category_preset=arcade_vertical; sam_category_read_scope
PATHFILTER[arcade]=_Horizontal
sam_filter_static_blacklist=yes sam_filter_legacy_orientation=yes sam_filter_path=yes
sam_emit filter_policy arcade
[[ "$sam_filter_static_blacklist:$sam_filter_legacy_orientation:$sam_filter_path" == yes:no:no ]]
PATHFILTER[arcade]=1990s
sam_filter_path=yes; sam_emit filter_policy arcade
[[ "$sam_filter_path" == yes ]]
''')

    def test_pinball_static_exception_does_not_restore_ignored_candidates(self):
        self.assertShell(self.context() + '''
category_preset=pinball; sam_category_read_scope
sam_session_begin
sam_job="$sam_session/jobs/test"; mkdir -p "$sam_job/lists"
gamelistpathtmp="$sam_job/lists"; tmpfile="$sam_job/filter"; tmpfilefilter="$sam_job/rating"
printf '%s\\n' '/games/SNES/Genre/Pinball/Pinball Dreams.sfc' '/games/SNES/Genre/Pinball/Pinball Fantasies.sfc' > "$gamelistpath/snes_gamelist.txt"
printf 'Pinball Dreams\\nPinball Fantasies\\n' > "$blacklistpath/snes_blacklist.txt"
printf '%s\\n' '/games/SNES/Genre/Pinball/Pinball Fantasies.sfc' > "$ignorepath/snes_excludelist.txt"
filter_list snes
sam_category_filter snes
[[ $(<"$gamelistpathtmp/snes_gamelist.txt") == '/games/SNES/Genre/Pinball/Pinball Dreams.sfc' ]]
[[ "$disable_blacklist" == no ]]
''')

    def test_pinball_membership_survives_real_dedup_retaining_first_regional_path(self):
        self.assertShell(self.context() + '''
category_preset=pinball; sam_category_read_scope
sam_session_begin
sam_job="$sam_session/jobs/test"; mkdir -p "$sam_job/lists"
gamelistpathtmp="$sam_job/lists"; tmpfile="$sam_job/filter"; tmpfilefilter="$sam_job/rating"
printf '%s\\n' '/games/NES/1 USA/Pinball (USA).nes' '/games/NES/Genre/Pinball/Pinball (USA).nes' '/games/NES/1 USA/Unrelated (USA).nes' > "$gamelistpath/nes_gamelist.txt"
filter_list nes
[[ $(wc -l < "$gamelistpathtmp/nes_gamelist.txt") == 2 ]]
sam_category_filter nes
[[ $(<"$gamelistpathtmp/nes_gamelist.txt") == '/games/NES/1 USA/Pinball (USA).nes' ]]
''')

    def test_empty_category_stops_instead_of_publishing_any_candidate(self):
        self.assertShell(self.context() + '''
category_preset=pinball; sam_category_read_scope
corelist=(snes); corelistall=(snes)
sam_core_session_begin snes
sam_session_begin
sam_job_serial=1; check_for_new_games=no
printf '%s\\n' "$mrsamtmp/Unclassified.sfc" > "$gamelistpath/snes_gamelist.txt"
: > "$mrsamtmp/Unclassified.sfc"
sam_prepare_worker
[[ $(<"$sam_session/error") == 'No eligible games found for the enabled cores and filters' ]]
sam_queue_files
[[ ${#sam_queue[@]} == 0 ]]
''')


if __name__ == '__main__':
    unittest.main()
