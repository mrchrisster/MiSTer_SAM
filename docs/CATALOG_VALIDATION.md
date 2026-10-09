# Catalog migration validation — 2026-10-09

## Environment and baseline

Real MiSTer: Python 3.9.6, no sqlite3 module; FAT and USB0 exFAT mounted with
`sync,dirsync`. Monitor server 2.11.1 runs on port 8081. The user stopped Plex;
MCP and the autostarted SAM session were stopped for measurements. MiSTer Main
remained in Menu for scanner timing. Background services and kernel cache state
still introduce variation, so these are paired observed timings, not guarantees.

The installed compiled scanner is 4,342,788 bytes, SHA-256
`16dedc1da73513c6977dbaca2afd02509192cbeed6b36bb4483e948525702d64`.
Build strings identify Go 1.21.9 and mrext revision
`d0e71ca00acd6156107f2a90f8c3182b1fd53c61` (2026-04-08).
That revision could not be retrieved from the current upstream repository;
comparisons use the preserved actual executable, not assumed source equivalence.

## Actual collection comparisons

All entries and ordering matched the installed executable for these eight
collections; none were only in one result. This covers **66,798 paths**.

| SAM core | Game paths |
|---|---:|
| nes | 22,535 |
| snes | 28,283 |
| gb | 7,961 |
| n64 | 2,979 |
| psx | 2,322 |
| fds | 1,310 |
| neogeo | 843 |
| megacd | 565 |

Counts are raw scanner paths, before SAM duplicate, rating, ignore and artwork
filters. They are not artwork eligibility counts. Folder detection was also
compared against the installed scanner. Not every catalog system has been
scanned or launched on this device.

## Full generic-build timings on the FAT volume

This includes output creation and `sort -u`. The old path includes its directory
sync, one-second sleep and two scanner passes. The new path uses one complete
pass with atomic publication. Cold means fresh ZIP metadata cache, not a forced
kernel page-cache drop. Warm means reusable ZIP metadata.

| Core | Old first / repeat (s) | New cold / warm (s) |
|---|---:|---:|
| nes | 16.18 / 12.36 | 12.26 / 9.18 |
| psx | 2.35 / 2.09 | 2.19 / 2.00 |
| n64 | 4.72 / 2.89 | 2.64 / 2.40 |
| gb | 11.05 / 6.15 | 6.81 / 5.26 |
| snes | 77.70 / 65.78 | 44.89 / 34.99 |

Every sorted output was byte-identical. NES/PSX/N64 were remeasured after adding
bounded 1 MiB write buffering for synchronous FAT. GB and SNES measurements also
use that buffering. Earlier unbuffered full-build measurements showed a small
PSX regression; that is not the final implementation.

Scanner-only measurements to `/tmp` tell a different story: warm NES Python
3.98 s versus Go 2.00 s for one pass, SNES 29.16 versus 28.33 s. The improvement
comes from removing the redundant second pass and delay, archive metadata reuse
and batching writes; the interpreter is not universally faster than Go.
An additional NES run launched from a small shell parent measured peak RSS of
64,256 KiB for Python versus 45,984 KiB for Go. Python uses more memory for this
collection; neither timing nor memory is claimed to improve for every single
scanner invocation. Preserve this evidence when evaluating future changes.

## Launch evidence

The catalog-generated MGLs were sent directly to `/dev/MiSTer_cmd`, separately
from SAM selection. MiSTer's `CORENAME`, `CURRENTPATH` and `FULLPATH`, plus Monitor
snapshot core/game/path, acknowledged the expected media for Atari2600, FDS,
GB, GBC, GBA, Genesis, NES, S32X, Saturn CHD, 3DO CHD, TGFX16 PCE, TGFX16 SGX,
NeoGeo and NeoGeoCD CHD. This includes ZIP members. The user additionally
confirmed visual gameplay for these **14 launches**.

A subsequent pass acknowledged Atari5200 `.car` and Jaguar `.j64` (`Aircars`),
including Jaguar's catalog reset tag. These two have core/media readback but no
separate recorded visual confirmation. Jaguar `boot.rom` was also opened as a
slot/reset smoke check; it is not counted as a game or gameplay validation.

No PSX `.exe` fixture was installed. Its old SAM disk-slot method is explicitly
preserved in `sam_compat.json`; the upstream `type=f` change has not been enabled.
Other extensions sharing the tested slots have schema/slot checks, not individual
hardware launches. Special Amiga/CD32/ao486/X68000/custom-MGL/CD-i video workflows
were preserved; this migration does not claim new real-game coverage for them.

## Installed SAM run

Release `68626f0` was then installed from its complete exported archive. The
installer backed up only `MiSTer_SAM.ini`. A normal single-core NES SAM run picked
`Wrecking Crew (World) (Virtual Console)` from the FAT ZIP collection while USB0
also had NES collections. SAM's candidate path, generated MGL, MiSTer's loaded
`FULLPATH`, core process and Monitor snapshot agreed on that precise FAT archive
member. Monitor `/media/artwork` returned HTTP 200; the downloaded JPEG decoded
successfully and showed the matching Wrecking Crew cover. This verifies served
artwork, not a separately observed Echo Show screen.

The test was stopped afterward. `SAM_state` remained with `active=no`; MiSTer
returned to Menu and MCP was restored. The installed scanner reports
`samindex-python 1.0`, and the installed catalog matches the recorded SHA-256.
The desktop `MiSTer_SAM-test` source was synchronized only after verifying all
affected existing files still matched the previous source revision.

## Isolated fixtures on the actual MiSTer

The complete pre-existing suite plus new shell integration checks passed:
**167 tests in 103.931 s**. It covers module/core eligibility, preparation,
cancellation, ownership, input/control behavior, config-only backup, installer
shutdown races, Amiga shared staging and the one-pass builder's failure handling.

Catalog/scanner fixtures separately cover aliases/groups, slot order and zero
defaults, setname/reset/XML escaping, checksum/schema validation, RBF aliases,
loose files, archives, case matching, storage priority, symlink aliases/cycles,
deterministic optional filename deduplication, archive mutation/removal/refresh,
cache corruption, partial corrupt ZIP rejection, storage/write errors, locking,
CLI statuses, UTF-8/CP437, concatenated ZIP, ZIP64 and SIGTERM staging cleanup.
These fixtures use temporary synthetic files; they do not constitute gameplay.
All **22** passed in **5.553 s**, for **189 passing checks** across the two runs.

The staged release is approximately 630 KiB compressed, versus approximately
2.94 MiB before replacing the compiled scanner. Optional mplayer/partun binaries
remain excluded from regular update archives. The runtime still needs existing
`mbc`; this migration does not replace it.

## Evidence and remaining scope

Raw JSON timings, launch readback and the preserved scanner live in the local
`work/sam-catalog-migration` directory outside the release checkout. Native logs
and isolated outputs were staged under `/tmp/sam-*`, with full-build timings in
private `.sam-build-bench-*` directories under Scripts. The original installed
scanner was used throughout side-by-side validation. No ROMs or artwork were
added, deleted, renamed or extracted for these checks.

USB0, FAT output, large ZIP collections and loose files were measured. No mounted
network ROM collection was available for network performance testing. Storage
failure and disappearing-media behavior were checked with fixtures. Native
readback and user-observed gameplay are explicitly distinguished above.
