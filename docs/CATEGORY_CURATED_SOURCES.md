# Curated category fallback provenance

`modules/category-aliases.json` is a deliberately limited, manually reviewed
seed list. It is not a downloaded genre database and never classifies an unknown
game by a word in its filename. Each row is an exact per-core title alias;
region/revision annotations and conventional punctuation normalize through the
shared `sam_titles.py` helper. Different sequels or compilation titles require
their own reviewed entry.
Numbered generic CD leaves may use only their immediate directory's exact title
key; a title anywhere else in a path is never an alias. This supports layouts
such as `Pro-Pinball - The Web/disc1.chd` without matching a whole directory tree.

The collection's explicit `Genre` folders remain the first source of genre
classification. Cached folders were inspected on October 10, 2026, including
NES, SNES, Genesis, GB/GBC, GBA, N64 and TGFX16. Observed labels include `Pinball`,
`Puzzle`, `Racing`, `Shoot 'em Up(s)`, `Fighters (1v1)` and `Fighting (1v1)`.
First/third-person shooter folders are deliberately excluded from shmups.
CD title directories are not genre evidence. A folder category present in the
master list prevents curated fallback even if other filters remove all its
eligible titles. Its exact title membership also applies to a regional copy
retained by normal deduplication, without adding any candidate back to the list.

The initial fallback set covers familiar, reviewed genre titles with conservative
system-specific aliases. It is incomplete by design: zero matched aliases means
that system is skipped. Cached master lists supply spelling/region evidence,
not automatic genre inference. The read-only `work/sam_category_audit.py` reports
folder, curated and MRA counts separately and lists unmatched pinball candidates
for human review; those discovery candidates are never fed into SAM's filter.
Additional seeds cover NeoGeo fighting families (King of Fighters, Samurai
Shodown, Fatal Fury, Art of Fighting and Last Blade), exact puzzle/racing ROM-set
aliases, and familiar Amiga/DOS puzzle/racing titles such as Lemmings, Pushover,
Lotus, Stunts and Grand Prix. The seed distinguishes reviewed stock title names
from merely containing one of those words. Cached coverage remains an audit
result, not a guarantee that every seed title is present on a particular system.

Orientation eligibility prefers the already-installed Arcade Organizer cache.
The inspected cache contains 3,001 setname records, each with an explicit file
name and rotation. File names match literally (case-insensitive); normalized
title aliases are used only when all corresponding records agree on the same
axis. Missing/conflicting metadata remains unknown. The database's declared
rotation semantics are documented by [MiSTer Arcade Database](https://github.com/MiSTer-devel/ArcadeDatabase_MiSTer),
and the installed cache layout is documented in the [Organizer implementation](https://github.com/theypsilon/_arcade-organizer/blob/master/_arcade-organizer.sh).
If that cache is missing, a deliberately small exact-title orientation seed
provides candidates. Both index and seed candidates must then pass their actual
bounded MRA header check, so old or incorrect metadata cannot authorize the
wrong orientation. Catalogue eligibility itself never opens every MRA.

The PSX additions from the October 10 review were checked against cached exact
filenames and release/game references:

| Exact alias | Classification/release evidence |
|---|---|
| `Pro-Pinball` / `Pro Pinball` | [Original PlayStation manual](https://db.hfsplay.fr/files/2020/06/19/Pro_Pinball_The_Web_-_1996_-_Interplay_Productions_Y1onh4B.pdf), [release listing](https://gamefaqs.gamespot.com/ps/198352-pro-pinball/data) |
| `Austin Powers Pinball` | [MobyGames game entry](https://www.mobygames.com/game/12215/austin-powers-pinball/) |
| `KISS Pinball` | [MobyGames game entry](https://www.mobygames.com/game/4899/kiss-pinball/) |
| `Patriotic Pinball` | [MobyGames game entry](https://www.mobygames.com/game/36748/patriotic-pinball/) |
| `Saban's Power Rangers Zeo - Full Tilt Battle Pinball` | Exact publisher-prefixed spelling in the cached PSX master list; alias of the already-reviewed Full Tilt Battle Pinball title |

The bare `Pro-Pinball` alias fixes the actual North American cached filename;
the same normalized title also works with a European region suffix. It does not
match an unreviewed `Pro-Pinball ... Compilation` title. The audit reads only
existing master-list text and MRA metadata: it never opens ROMs or ZIP members,
hashes collections, modifies installed files, or changes current settings.
