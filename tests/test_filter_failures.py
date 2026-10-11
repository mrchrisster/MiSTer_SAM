"""Real filter return-code and partial-output regressions; isolated Bash."""
import unittest
import test_catalog_runtime as harness


class FilterFailures(unittest.TestCase):
    def setUp(self):
        self.fixture = harness.CatalogRuntime()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def shell(self, code):
        self.fixture.shell("""
rating=no;dupe_mode=normal;exclude=();disable_blacklist=yes
mkdir -p "$ratedpath" "$ignorepath" "$blacklistpath"
printf '/games/Original.nes\n' > "$gamelistpathtmp/nes_gamelist.txt"
""" + code)

    def test_initial_copy_failure_does_not_filter_stale_scratch(self):
        self.shell("""
printf '/stale/Other.nes\n' > "$tmpfile"
cp(){ return 1; }
rc=0;filter_list nes || rc=$?
[[ $rc == 2 && $(<"$gamelistpathtmp/nes_gamelist.txt") == /games/Original.nes && ! -f "$gamelistpathtmp/.checked/nes.filtered" ]]
""")

    def test_grep_error_preserves_session_and_never_flags_success(self):
        self.shell("""
PATHFILTER[nes]=Original
grep(){ printf '/partial/Bad.nes\n';return 2; }
rc=0;filter_list nes || rc=$?
[[ $rc == 2 && $(<"$gamelistpathtmp/nes_gamelist.txt") == /games/Original.nes && ! -f "$gamelistpathtmp/.checked/nes.filtered" ]]
""")

    def test_grep_output_open_failure_is_not_no_matches(self):
        self.shell("""
mkdir "$sam_session/output-directory"
rc=0;sam_filter_grep "$sam_session/output-directory" -F -- Missing "$gamelistpathtmp/nes_gamelist.txt" || rc=$?
[[ $rc == 2 ]]
""")

    def test_awk_and_move_errors_do_not_publish_partial_results(self):
        for failure in ('awk(){ printf partial;return 1; }', 'mv(){ return 1; }'):
            self.shell(failure + """
rc=0;filter_list nes || rc=$?
[[ $rc == 2 && $(<"$gamelistpathtmp/nes_gamelist.txt") == /games/Original.nes && ! -f "$gamelistpathtmp/.checked/nes.filtered" ]]
""")

    def test_partial_publication_copy_failure_preserves_previous_session(self):
        self.shell("""
cp(){
    if [[ "$3" == *.filtered.* ]]; then printf partial > "$3"; return 1; fi
    command cp "$@"
}
rc=0;filter_list nes || rc=$?
[[ $rc == 2 && $(<"$gamelistpathtmp/nes_gamelist.txt") == /games/Original.nes && ! -f "$gamelistpathtmp/.checked/nes.filtered" ]]
""")

    def test_no_matches_and_leading_dash_are_valid_empty(self):
        self.shell("""
PATHFILTER[nes]=-does-not-match
rc=0;filter_list nes || rc=$?
[[ $rc == 1 && ! -s "$gamelistpathtmp/nes_gamelist.txt" && ! -f "$gamelistpathtmp/.checked/nes.filtered" ]]
""")

    def test_invalid_exclusion_regex_is_error(self):
        self.shell("""
exclude=('[')
rc=0;filter_list nes || rc=$?
[[ $rc == 2 && $(<"$gamelistpathtmp/nes_gamelist.txt") == /games/Original.nes ]]
""")

    def test_ratings_matcher_errors_preserve_candidates(self):
        # Inject failure into each current backend, not the removed grep path.
        for rating, filename, tool in (('mature', 'nes_mature.txt', 'awk'),
                                       ('kids', 'nes_rated.txt', 'python3')):
            self.shell('rating='+rating+';printf Original > "$ratedpath/'+filename+'"\n'+
                       tool+'(){ printf partial;return 2; }\n'+"""
rc=0;apply_ratings_filter nes "$gamelistpathtmp/nes_gamelist.txt" || rc=$?
[[ $rc == 2 && $(<"$gamelistpathtmp/nes_gamelist.txt") == /games/Original.nes ]]
""")

    def test_missing_kids_ratings_and_no_matches_are_valid_empty(self):
        self.shell("""
rating=kids
rc=0;apply_ratings_filter nes "$gamelistpathtmp/nes_gamelist.txt" || rc=$?
[[ $rc == 1 && ! -s "$gamelistpathtmp/nes_gamelist.txt" ]]
printf '/games/Original.nes\n' > "$gamelistpathtmp/nes_gamelist.txt"
printf Missing > "$ratedpath/nes_rated.txt"
rc=0;apply_ratings_filter nes "$gamelistpathtmp/nes_gamelist.txt" || rc=$?
[[ $rc == 1 && ! -s "$gamelistpathtmp/nes_gamelist.txt" ]]
""")

    def test_bad_exclusion_input_is_error_not_infinite_getline_loop(self):
        self.shell("""
mkdir "$ignorepath/nes_excludelist.txt"
rc=0;sam_apply_exclusions nes "$gamelistpathtmp/nes_gamelist.txt" || rc=$?
[[ $rc == 2 && $(<"$gamelistpathtmp/nes_gamelist.txt") == /games/Original.nes ]]
""")

    def test_exclusion_and_rating_move_failures_are_errors(self):
        self.shell("""
printf Missing > "$ignorepath/nes_excludelist.txt"
printf Original > "$ratedpath/nes_mature.txt"
mv(){ return 1; }
rc=0;sam_apply_exclusions nes "$gamelistpathtmp/nes_gamelist.txt" || rc=$?
[[ $rc == 2 ]]
rating=mature;rc=0;apply_ratings_filter nes "$gamelistpathtmp/nes_gamelist.txt" || rc=$?
[[ $rc == 2 && $(<"$gamelistpathtmp/nes_gamelist.txt") == /games/Original.nes ]]
""")

    def test_ignore_persists_when_foreground_has_no_worker_candidate_list(self):
        self.shell("""
rm "$gamelistpathtmp/nes_gamelist.txt"
mkdir -p "$gamelistpathtmp/.checked";touch "$gamelistpathtmp/.checked/nes.filtered"
ignoregame nes /games/Original.nes
sam_is_excluded nes /games/Original.nes
[[ ! -f "$gamelistpathtmp/.checked/nes.filtered" ]]
# The generic helper still treats a requested missing candidate as an error.
rc=0;sam_apply_exclusions nes "$gamelistpathtmp/nes_gamelist.txt" || rc=$?
[[ $rc == 2 ]]
""")

    def test_blacklist_filename_is_not_awk_source(self):
        self.shell(r"""
blacklistpath="$sam_session/blacklist-with-a-quote-\"";mkdir -p "$blacklistpath"
printf 'Other\n' > "$blacklistpath/nes_blacklist.txt"
disable_blacklist=no;filter_list nes
[[ $(<"$gamelistpathtmp/nes_gamelist.txt") == /games/Original.nes ]]
""")


if __name__ == '__main__':
    unittest.main()
