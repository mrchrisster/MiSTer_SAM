# Preferred commercial ROM copies

Commercial selection now uses `modules/commercial_picker.py`. It reads the
selected core's filtered session list and available local artwork indexes;
it never reads ROM contents, hashes CHDs, downloads metadata, or scans all
systems at initialization. Ordinary random SAM and manual launching are unchanged.

The picker matches basenames rather than directories or author credits. Exact
normalized titles and explicit catalog aliases take priority. A published
abbreviation is accepted only when it identifies one retail title. Sequel
numbers, compilations and licensed/unlicensed editions remain distinct. Existing
BRE-style alternative titles are treated as explicit literal alternatives,
not arbitrary executable regex. Unsupported or ambiguous fragments are skipped.

Ranking is a preference for familiar retail copies, not measured download
popularity. It prefers:

1. Unmodified retail dumps over hacks, translations, prototypes, demos and bad dumps.
2. Names recognized by the available artwork catalog over unfamiliar variants.
3. Standard names over ranked/date-prefixed collection names.
4. USA, World, Europe, then Japan when the commercial does not request a region.
5. Later official revisions among otherwise equivalent copies.

Equal best copies remain random. A generic hardware advertisement first chooses
an eligible game, then its best copy, so revision numbers do not bias the choice
toward unrelated games. Empty/general metadata is handled explicitly rather
than passed to grep as a pattern matching everything.

Rating, path, Ignore and artwork filters remain authoritative. There is no
fallback to the unfiltered master list. A known indexed title removed by filters
is unavailable, not an invitation to guess a similarly named game. Commercial
selection checks that a corresponding ROM remains before playing the ad. Missing
matches are reported and skipped within a bounded batch; failure reports a short
video-timer result rather than leaving the player waiting forever.

The current video-plus-artwork-only auxiliary-launch validation remains in
place. Being a catalogued name is a copy preference, not proof of a freshly
decoded image. This change does not claim to add artwork-only support to video
mode or weaken its existing rejection.

Ranking data is cached in the session list directory. The cache refreshes when
the filename-list contents, metadata indexes or helper change. Only the small
filename text is fingerprinted; no ROM data is hashed. Original filenames,
archives, public gamelists and the permanent INI are not rewritten.

Install the complete test release with `m update`. The installer validates the
new helper and preserves user configuration, with its usual INI-only backup.
To roll back this picker, install the complete prior release `c70be80`; do not
restore only a caller while removing its helper. Prior behavior and its observed
failures are documented in [the selection audit](COMMERCIAL_SELECTION_TESTS.md).
