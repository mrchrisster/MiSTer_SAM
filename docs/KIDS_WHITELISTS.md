# Kids whitelists

The Kids lists select stock games reviewed for an all-ages/Everyone audience. They exclude E10+, Teen, Mature and conflicting rating records. Everyone is an age/content category, not a guarantee of easy gameplay or an absence of mild cartoon violence. Each line is a complete game title; regional punctuation and articles normalize through the shared exact-title helper. A franchise name never grants approval to its sequels.

This rebuild deliberately uses modest content-reviewed lists. The original lists mixed partial franchise names, unreviewed entries and older-age games. All 19 system lists were replaced. Unlisted titles fail closed. Altered releases (hacks, betas, prototypes, translations, unlicensed/aftermarket editions and demos) are excluded by the runtime filter even when their base title matches.

## Evidence and limitations

The local libretro ESRB DAT snapshot is community-maintained metadata, not official certification. Every selected title is explicitly present in [kids-curated.json](kids-curated.json). If a same-platform metadata record has any value outside E, EC, KA or K-A, it vetoes that selection. Ratings from another platform, remake or compilation never approve a game. An absent record is clearly recorded as a content-review decision with no claimed official rating.

Community records alone are insufficient: the snapshot incorrectly tags Grand Theft Auto and Grand Theft Auto 2 for Game Boy Color as E, and Mortal Kombat II for Genesis as KA. Those games, Duke Nukem, Resident Evil and other mature/combat selections were not carried into the reviewed manifests. The rebuild test specifically prevents these erroneous metadata rows from adding them.

Sparse PlayStation data and platforms with no DAT coverage use explicit conservative puzzle, platformer, racing, sports and educational selections. These are review decisions, not official ESRB ratings. No inference is made from a similarly named release on a different console. This intentionally omits many games until someone reviews their exact platform version.

Primary rating spot checks: [Spyro the Dragon](https://www.esrb.org/ratings/3475/spyro-the-dragon/) is E on PlayStation/PS one; [Sonic R](https://www.esrb.org/ratings/3019/sonic-r/) is E on Sega Saturn. The manifests retain these exact releases. These checks do not certify the remainder of the lists.

## Neo Geo filenames

Neo Geo selection can receive short `.neo` filenames before artwork name resolution. The exact stock ROM-set aliases for the 12 existing reviewed games are recorded in `kids-curated.json`; they do not approve any additional game. `pbobblen` and `pbobbl2n` also agree with the existing category aliases. The remaining mappings were checked against [MAME's Neo Geo driver registrations](https://github.com/mamedev/mame/blob/master/src/mame/snk/neogeo.cpp). Its stock identifiers are `pnyaa` for Pochi and Nyaa and `wjammers` for Windjammers; guessed identifiers are not added. Bootlegs, alternate unreviewed sets and mature fighting titles such as `kof98` and `garou` remain excluded. The ROM-set evidence establishes filename identity, not an age rating.

## Rebuild results

| Core | Original lines | Reviewed titles | Added exact titles | Removed original lines |
| --- | ---: | ---: | ---: | ---: |
| amiga | 59 | 18 | 0 | 41 |
| ao486 | 124 | 31 | 1 | 94 |
| arcade | 213 | 41 | 0 | 167 |
| fds | 6 | 9 | 3 | 0 |
| gb | 100 | 35 | 24 | 89 |
| gba | 494 | 43 | 32 | 482 |
| gbc | 263 | 27 | 18 | 254 |
| genesis | 122 | 39 | 22 | 105 |
| gg | 39 | 26 | 16 | 29 |
| megacd | 28 | 11 | 3 | 19 |
| n64 | 99 | 35 | 19 | 83 |
| neogeo | 15 | 22 | 13 | 6 |
| nes | 140 | 35 | 20 | 125 |
| psx | 523 | 34 | 8 | 494 |
| saturn | 166 | 38 | 1 | 129 |
| sms | 44 | 23 | 15 | 36 |
| snes | 125 | 35 | 29 | 119 |
| tgfx16 | 51 | 18 | 12 | 41 |
| tgfx16cd | 8 | 3 | 0 | 5 |

Total: 513 reviewed human game titles, plus 12 verified Neo Geo stock ROM-set aliases. Two aliases already normalize to their human title (`neomrdo`, `zupapa`), so the output has 523 distinct match keys across 19 platform lists. Added/removed counts compare exact normalized title keys; canonicalizing a previously partial or misspelled line can appear as both a removal and an addition. Per-title evidence, additions, removals and output SHA-256 values are in `work/kids-audit/whitelist-evidence.json`. DAT source URLs and Git blob identities are preserved in `work/kids-audit/metadata-source.json` and copied into that report.

## Offline rebuild and rollback

Run from the workspace root:

```sh
python work/ini-only-update/github-test/tools/rebuild_kids_whitelists.py --audit work/kids-audit
python work/ini-only-update/github-test/tools/rebuild_kids_whitelists.py --audit work/kids-audit --check
python -m unittest discover -s work/ini-only-update/github-test/tests -p test_kids_whitelist_rebuild.py
```

The script consumes the captured metadata and exact review manifest, performs no network requests, and generates only the rated lists plus the local evidence report. `--check` verifies reproducibility without writing. It does not auto-approve metadata candidates. A future addition requires explicit review in the same-platform manifest first.

The original 19 whitelist files are preserved locally under `work/kids-audit/originals/` for rollback. These backups and audit artifacts are offline workspace files; nothing was written to a MiSTer or an SD card. Existing mature-list files were left unchanged.
