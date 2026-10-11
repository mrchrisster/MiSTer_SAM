# Smart category presets

Use **Game modes and presets → Smart category presets**, or the same submenu
under **Games, filters and controller → Filters**. Pick a category, then **Save
permanently** or **Until reboot**. A running normal/roulette session changes its
selection at the next game boundary. Canceling either question changes nothing.

Choices are Pinball, horizontal arcade, vertical arcade, shoot 'em ups, fighting,
puzzle and racing. **All categories** removes only the category restriction;
other filters remain active. Mode presets reset the category to `off`.

Permanent category selection uses `category_preset` in the SAM INI. Temporary
selection is literal data in RAM at `category-preset` under SAM's temporary root,
bound to the Linux boot ID. It never sources shell text and cannot survive a
reboot as an active override. Temporary choices do not change the saved INI.

Genre folders are preferred. The device's cached console lists use explicit
`Genre/Pinball`, `Genre/Puzzle`, `Genre/Fighters (1v1)`, and `Genre/Shoot 'em Up`
components, including paths inside ZIP collections. CD collections often use
title-named directories; those are not genre declarations. If a core's master
list has no folder for the chosen category, a conservative per-core exact-title
alias list in `modules/category-aliases.json` supplies the fallback. It is a
starting selection, not a complete genre database. Unknown titles and systems
with no eligible matches are skipped. Nothing falls back to unrestricted games.
Genre membership is derived from exact title keys in that core's master list.
This retains a regional/all-games copy selected by normal deduplication when a
separate Genre copy proves the same title's category. It does not add a removed
candidate, match a sequel by substring, or borrow another system's genre list.
For a numbered generic CD leaf such as `disc1.chd` or `Track01.bin`, only its
immediate parent can supply an exact reviewed title key. An unrelated basename
or a title farther up the directory tree cannot borrow that classification.

Arcade orientation first uses the existing Arcade Organizer metadata cache. It
matches exact filenames, then exact normalized titles only when every matching
record agrees on the same horizontal/vertical axis. Missing rotation never
defaults to horizontal; conflicting or unknown clone metadata cannot certify a
title alias. The local `data.zip` and its JSON member are each limited to 2 MiB;
no archive is extracted or downloaded. If the cache is unavailable, explicit
orientation folders or a conservative reviewed orientation seed supply the
initial candidates. Eligibility never opens the full MRA catalogue.

Every proposed orientation candidate must pass its actual MRA header check
before artwork preparation or launch. Unknown or mismatching orientation is
excluded. The MRA reader streams root metadata in 4 KiB chunks, caps its header
at 256 KiB, and stops before the first root-level `rom` element. A declaration
after that payload boundary is intentionally unknown; embedded ROM payloads are
not scanned for category selection. An explicit orientation preset replaces the old `arcadeorient` rule
and the exact legacy `_Horizontal`/`_Vertical` path sentinel for this selection.
Other per-core path filters still apply; the saved orientation settings are not
rewritten by a temporary choice.
Changing Organizer data or either Python helper invalidates cached eligibility.

Pinball allows static-screen titles because a stationary table is useful attract
content. Its policy skips only the standard static-screen blacklist; it does not
change `disable_blacklist` or bypass Kids, Ignore, artwork, curated restrictions,
or category/user exclusion lists. All category filtering refines the existing
eligible candidates; it cannot restore a row another filter removed.

The category exclusion menu saves literal release/region tags in the established
`.excludetags` file, or temporarily in the boot-bound RAM override. Matching uses
exact folder labels and parenthesis/bracket release metadata, not arbitrary title
substrings. Clearing its checkboxes clears these tag rules only. Existing legacy
or user `Blacklists/*_gamelist_exclude.txt` files remain authoritative and the menu
explains that they must be managed separately. Master collections, Ignore files
and generated collection lists are never rebuilt or deleted by these menus.

Collection traversal and indexing remain preparation work. Loading the category
module reads only settings and the small literal override/tag files. It does not
scan collections at startup or put genre matching in the countdown polling loop.
