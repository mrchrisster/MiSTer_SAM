"""Isolated Bash catalog errors, publication and cache regressions."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from paths import PACKAGE


class CatalogRuntime(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-catalog-runtime-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        ini = self.root / 'SAM.ini'
        ini.write_text('corelist="arcade,nes"\ncorelistall="arcade,nes"\nrating="no"\n')
        self.env = dict(os.environ, SAM_MODULES_OVERRIDE='', SAM_ROOT=str(PACKAGE / '.MiSTer_SAM'),
                        SAM_INI=str(ini), SAM_LIST_ROOT=str(self.root / 'lists'),
                        SAM_TMP_ROOT=str(self.root / 'tmp'), SAM_SESSION_LIST_ROOT=str(self.root / 'session-lists'),
                        SAM_STATE_FILE=str(self.root / 'state'), SAM_CONFIG_ROOT=str(self.root / 'config'),
                        SAM_MISTER_ROOT=str(self.root / 'media'))

    def shell(self, code):
        prelude = 'set -e\nsource "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only\n'
        setup = 'sam_session="$mrsamtmp/test-session";sam_job="$sam_session/job";sam_catalog_cache="$sam_session/cache"\nmkdir -p "$sam_session" "$sam_job" "$sam_catalog_cache" "$gamelistpath" "$gamelistpathtmp";touch "$sam_session/alive"\n'
        result = subprocess.run(['bash', '-c', prelude + setup + code], env=self.env,
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr + '\n' + result.stdout)

    def test_filter_error_does_not_publish_empty_success(self):
        self.shell("""
printf 'game\n' > "$gamelistpath/nes_gamelist.txt"
printf 'previous\n' > "$sam_catalog_cache/nes.eligible"
filter_list(){ return 2; }; sam_emit(){ :; }
rc=0;sam_catalog_ready nes || rc=$?
[[ $rc == 2 && $(<"$sam_catalog_cache/nes.eligible") == previous && ! -f "$sam_catalog_cache/nes.stamp" ]]
""")

    def test_candidate_filter_error_and_cancellation_are_preserved(self):
        for error in (2, 3, 7):
            self.shell("""
printf 'game\n' > "$gamelistpath/nes_gamelist.txt"
filter_list(){ :; }
sam_emit(){ [[ "$1" != candidate_filter ]] || return ERROR; }
rc=0;sam_catalog_ready nes || rc=$?
[[ $rc == ERROR && ! -f "$sam_catalog_cache/nes.stamp" && ! -f "$sam_catalog_cache/nes.eligible" ]]
""".replace('ERROR', str(error)))

    def test_stamp_error_is_not_cached(self):
        self.shell("""
printf 'game\n' > "$gamelistpath/nes_gamelist.txt"
sam_emit(){ [[ "$1" != filter_stamp ]] || return 2; }
rc=0;sam_catalog_ready nes || rc=$?
[[ $rc == 2 && ! -f "$sam_catalog_cache/nes.stamp" ]]
""")

    def test_changed_inputs_during_filter_are_rechecked_next_time(self):
        self.shell("""
printf 'game\n' > "$gamelistpath/nes_gamelist.txt"
printf 'old' > "$sam_session/revision"
sam_catalog_stamp(){ cat "$sam_session/revision"; }
filter_list(){ printf x >> "$sam_session/filter-calls";printf new > "$sam_session/revision"; }
sam_emit(){ :; }
sam_catalog_ready nes
[[ $(<"$sam_catalog_cache/nes.stamp") == old ]]
sam_catalog_ready nes
[[ $(<"$sam_session/filter-calls") == xx ]]
sam_catalog_ready nes
[[ $(<"$sam_session/filter-calls") == xx ]]
""")

    def test_partial_special_builder_failure_preserves_public_list(self):
        self.shell("""
printf 'original\n' > "$gamelistpath/arcade_gamelist.txt"
touch "$gamelistpath/arcade.partial"
build_mra_list(){ printf 'partial\n' > "$2/arcade_gamelist.txt"; return 2; }
rc=0;sam_build_catalog arcade || rc=$?
[[ $rc == 2 && $(<"$gamelistpath/arcade_gamelist.txt") == original && -f "$gamelistpath/arcade.partial" ]]
""")

    def test_background_failure_propagates_and_is_not_retried(self):
        self.shell("""
corelist=(nes); sam_build_catalog(){ printf x >> "$sam_session/calls"; return 2; }
rc=0;sam_catalog_background_step || rc=$?
[[ $rc == 2 && -f "$sam_session/scanned-nes" ]]
sam_catalog_background_step
[[ $(<"$sam_session/calls") == x ]]
""")

    def test_unchanged_publish_preserves_inode_and_timestamp(self):
        self.shell("""
printf 'same\n' > "$gamelistpath/nes_gamelist.txt"
printf 'same\n' > "$sam_job/new"
before=$(stat -c '%i:%y' "$gamelistpath/nes_gamelist.txt")
sam_publish_catalog "$sam_job/new" "$gamelistpath/nes_gamelist.txt"
[[ $(stat -c '%i:%y' "$gamelistpath/nes_gamelist.txt") == "$before" ]]
""")

    def test_mra_find_failure_and_single_traversal(self):
        self.shell("""
mkdir -p "$misterpath/_Arcade"
printf 'original\n' > "$gamelistpath/arcade_gamelist.txt"
find(){ printf x >> "$sam_session/find-calls"; printf 'partial\n';return 1; }
rc=0;build_mra_list arcade || rc=$?
[[ $rc == 2 && $(<"$gamelistpath/arcade_gamelist.txt") == original && $(<"$sam_session/find-calls") == x ]]
""")

    def test_mgl_find_failure_is_not_valid_empty(self):
        self.shell("""
mkdir -p "$sam_session/mgls";mgls_dirs="$sam_session/mgls"
printf 'original\n' > "$gamelistpath/mgls_gamelist.txt"
find(){ printf 'partial\n';return 1; }
rc=0;build_mgl_list mgls || rc=$?
[[ $rc == 2 && $(<"$gamelistpath/mgls_gamelist.txt") == original ]]
""")

    def test_amiga_no_pack_is_valid_empty_but_adapter_failure_is_error(self):
        self.shell("""
sam_adapter_paths(){ return 1; };sam_build_catalog amiga
[[ -f "$gamelistpath/amiga_gamelist.txt" && ! -s "$gamelistpath/amiga_gamelist.txt" ]]
printf 'original\n' > "$gamelistpath/amiga_gamelist.txt"
sam_adapter_paths(){ return 2; };rc=0;sam_build_catalog amiga || rc=$?
[[ $rc == 2 && $(<"$gamelistpath/amiga_gamelist.txt") == original ]]
""")

    def test_valid_empty_catalog_is_published_and_cached(self):
        self.shell("""
build_mra_list(){ : > "$2/arcade_gamelist.txt"; return 1; }
sam_bootstrap_seed=0;sam_build_catalog arcade
[[ -f "$gamelistpath/arcade_gamelist.txt" && ! -s "$gamelistpath/arcade_gamelist.txt" ]]
sam_emit(){ :; };rc=0;sam_catalog_ready arcade || rc=$?
[[ $rc == 1 && -f "$sam_catalog_cache/arcade.stamp" && ! -s "$sam_catalog_cache/arcade.eligible" ]]
""")


if __name__ == '__main__':
    unittest.main()
