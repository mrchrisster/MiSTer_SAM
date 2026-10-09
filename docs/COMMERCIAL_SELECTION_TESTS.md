# Commercial ROM selection tests — 2026-10-09

The installed commercial `pick_rom` implementation was exercised on the actual
MiSTer with private copies of its gamelists, Ignore/Blacklist/Rating data and
existing filter settings. Tests used real titles from the VCD commercial JSON
metadata (`samvideo_tvc_cdi` is configured Yes). The selector was called ten
times per target: **34 targets, eight systems, 340 selections**.

No commercials or ROMs were launched for this audit, no ROMs were extracted or
modified, and no CHDs were hashed. The active SAM run and permanent INI were
unchanged. This is native selection/resolution testing, not commercial video
playback or game-boot validation. The diagnostic enabled commercial selection
only in its private shell and omitted the artwork module so it could exercise
the current picker. The installed application presently rejects video plus
`Artwork_only=Yes` at session validation; this audit did not bypass that check
in an actual session or disable artwork-only in the permanent INI.

## Sampled results

Artwork here means a **name/index match in the installed packs**, using the
actual Monitor resolver with ROM metadata reads disabled. Missing name matches
are not proof that a CRC fallback or the online Android catalog cannot resolve
the cover. Every target used the filtered session list; no master-list fallback
was needed in this sample.

| System | Commercial targets | Picks | No name/index artwork match |
|---|---:|---:|---:|
| NES | 9 | 90 | 56 |
| Genesis | 5 | 50 | 28 |
| SNES | 5 | 50 | 30 |
| N64 | 4 | 40 | 15 |
| PSX | 4 | 40 | 0 |
| Saturn | 2 | 20 | 0 |
| SMS | 1 | 10 | 9 |
| TGFX16 | 4 | 40 | 19 |
| Total | 34 | 340 | 157 |

Sampling is random and includes empty/broad hardware-commercial titles. These
counts are observations for this collection, not a predicted failure rate for
all SAM installations. Candidate pools were also enumerated before the random
picker, so the problematic candidates are independently reproducible.

## Reproduced problems

- **Ranked filenames:** the Super Mario Bros. commercial selected
  `003 Super Mario Bros. (World).nes` and `030 Super Mario Bros. (World).nes`.
  Their current name lookups failed even though removing the ranking prefix
  resolved the correct indexed cover. Other collections have `04. ...`,
  `006 - ...`, and date prefixes. A dot-only prefix rule would miss many cases.
- **Wrong games from full-path substring matching:** the Dr. Mario target
  selected `Castlevania High Budget Remake by Dr. Mario (Hack).nes`,
  `Dr. Luigi Lite (Dr. Mario Hack) ...`, and an SMB Zelda hack by Dr. Mario.
  All ten sampled picks were these three hacks. Artist/author tags and parent
  directory names participate in the current grep match.
- **Sequel leakage:** Donkey Kong Country selected Donkey Kong Country 2;
  Army Men – Sarge's Heroes selected Sarge's Heroes 2. This is distinct from
  number-prefix normalization and must not be hidden by fuzzy title matching.
- **Empty targets:** an empty NES metadata title matched 5,629 filtered ROMs;
  the TGFX16 empty title matched 567. It invokes an empty grep pattern instead
  of an explicit, reported generic-commercial policy.
- **Broad/fragile metadata:** `(USA` targets intentionally match many games;
  the SMS metadata contains a compound BRE pattern rather than one game title.
  Some other metadata titles are abbreviations. Replacing every query with a
  literal exact title without auditing this metadata would change behavior.

## Follow-up artwork checks

Twenty sampled archive misses were checked using the ZIP central directory's
existing CRC/size, without extraction or hashing. **Eight** resolved and their
images decoded. The other twelve still had no Monitor match. This confirms that
name-only misses must not all be labelled missing artwork.

A narrow normalization experiment removed one-to-three-digit ranking prefixes
with a space, dot or hyphen, then used the existing exact/index lookup. Across
**31 distinct prefixed names, 28 gained a match**. This was an experiment only:
no runtime matcher or selector was changed. It preserves title numbers such as
`1942` and `1080 Snowboarding`; authoritative exact matches should still win
before any prefix cleanup. Tetris variants demonstrate why edition/licensing
labels and ambiguous catalog titles must be retained rather than guessed away.

One positively matched selected cover from each of the eight systems was
decoded using the MiSTer's existing JPEG decoder; all eight passed.

## Recommended change

Restrict matching to the game basename, prefer exact/indexed canonical titles
and aliases, and normalize recognized collection prefixes only as a fallback.
Keep sequel/edition distinctions. Prefer cleanly named ROMs when equivalent
copies exist. Define an explicit policy for empty or generic hardware-commercial
targets and preserve intentional alternative-title metadata. Finally, make
commercial candidate selection obey verified artwork eligibility before launch.
A broad fuzzy-distance search would not address these failures safely.

Raw selection and follow-up JSON, plus the diagnostic scripts, are saved in the
local workspace `work/commercial-selection-results.json`,
`work/commercial-artwork-followup.json`, `work/commercial_selection_audit.py` and
`work/commercial_artwork_followup.py`. Private native outputs were created under
`/tmp/sam-commercial-selection-opuiuli6`. Ordinary SAM configuration, ROM files
and public lists were not edited.
