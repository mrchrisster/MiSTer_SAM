# SAM catalog and scanner

SAM now uses a Python 3.9+ standard-library scanner and one pinned Zaparoo
catalog reader for generic MGL generation. No pip, compiler, Zaparoo service or
network lookup is needed to scan or launch games. Existing SAM short core IDs,
INI names, gamelist filenames and user filters remain the public interface.

The catalog is the unchanged `mister/catalog/catalog.json` from
[Zaparoo c50f62a](https://github.com/ZaparooProject/zaparoo-core/blob/c50f62a4d34a0cc71cb218cfa9cb7b8938221869/mister/catalog/catalog.json).
`zaparoo_catalog_source.json` records the full revision, GPL-3.0-or-later license,
SHA-256 and the lookup/MGL source files reviewed. The reader verifies its checksum
and schema. `sam_compat.json` contains SAM aliases, ROM extension restrictions,
storage priority, launch group choices and special-handler identities. It does
not duplicate catalog launch numbers.

## Behavior

`samindex -q -s nes -o DIRECTORY` scans every matching NES folder in storage
priority order. `-d` reports only the first active folder per requested system.
Existing `-q`, `-s`, `-o`, `-d`, `-p`, `-nodupes` flags remain; `-version`,
`--refresh`, `--cache`, `--root`, `--lock-timeout` and `--stats` are also available.
`-s all` exposes all catalog systems. The SAM menu rebuilds configured SAM systems
through their appropriate builders, including special systems, rather than using
this broader catalog query.

Full scans use deterministic depth-first ordering and include loose files and
ZIP members without extracting or hashing ROM data. Symlink aliases retain their
display paths; broken links and cycles are skipped. Storage priority is USB0–5,
network, FAT/cifs, then FAT, with `games` before the volume root. Folder case
fallback matches the final component only. `-nodupes` keeps the first identical
basename, case sensitively; ordinary SAM region/revision deduplication remains a
separate later filter. Artwork filtering stays after SAM deduplication.

Corrupt ZIPs are reported and skipped as before. Read/write/storage errors return
failure, preserving previous lists. Each output is staged in its destination
directory, closed/fsynced, then atomically renamed. A directory lock prevents
concurrent writers; a complete multi-system scan finishes before publication.
Publication is atomic per file, not a transaction across every system: a storage
failure during the final rename batch can leave a mixture of complete old and
complete new lists. No partial list is published.

Exit statuses are **0** (games), **8** (successful empty scan), **2** (failure).
SAM no longer treats every nonzero error as an empty collection. Generic builds
run once; the old second pass and one-second settling delay are removed. Empty
results replace stale lists and are handled by existing bounded core selection.

ZIP metadata is cached under `.MiSTer_SAM/index-cache`, keyed by archive path,
size, nanosecond mtime, device and inode. Cache files have a completion record and
payload checksum; incomplete/corrupt caches are rebuilt before emitting paths.
The checksum covers cached filenames, never ROM/CHD contents. Extension policy
is applied on every scan, including cache hits. Changed/deleted archives are
reflected automatically. Force a rebuild after edits that preserve both size and
mtime:

```bash
/media/fat/Scripts/.MiSTer_SAM/samindex --refresh -q -s nes -o /media/fat/SAM/Gamelists
```

`sam_zip.py` streams names instead of allocating a ZipInfo per entry. It uses
Python's standard `zipfile` end-record and ZIP64 parsing plus a bounded central
directory reader. UTF-8, CP437, concatenated ZIP and ZIP64 fixtures are tested on
MiSTer's Python 3.9.6. Review this adapter when changing Python versions because
it uses private `zipfile` constants. SQLite is not required; this MiSTer has none.

Generic MGLs select the first matching catalog slot, respect zero/default integer
values, reset tags, setname/same_dir, canonical RBF names and alias fallback, and
escape XML. Existing custom RBF folders remain supported. The generated file is
complete and atomically published. Special MRA/ST-V, Amiga listings/HDF, Amiga
CD32 configuration, ao486/X68000/custom MGL and CD-i video launch paths remain
separate. Display names, mute names, filters, controller maps and manual MiSTer
launching are unchanged.

One deliberate compatibility exception remains: PSX `.exe` uses the catalog's
`.chd` slot to retain SAM's existing `type=s,index=1,delay=1` behavior. Upstream
instead specifies `type=f`. No `.exe` game/demo was available on this MiSTer;
remove `media_slot_aliases.psx` only after testing that changed method on hardware.

## Installation and rollback

Install this complete release with `m update` once published, or stage a checkout
and run `python3 MiSTer_SAM_install.py --source-dir PATH --branch test`.
The installer validates the entire catalog bundle before modifying installed
files and backs up only `MiSTer_SAM.ini`. The assets updater validates the bundled
scanner; it no longer downloads a compiled scanner from a moving raw URL.

For rollback, stop SAM and install a complete known release (for example
`7c834c04eada33ba27e42806cb0cfb38907a9fd5`), preserving your INI and public lists.
Restore the INI from its named backup only if settings must also be reverted.
Do not restore only the scanner launcher while leaving incompatible catalog
helpers. During validation the original installed executable and source remain
untouched; a copy of the executable is also saved in the local migration work
directory. No ROM collection is modified.

## Maintaining the pin

Choose an explicit upstream commit, download the catalog at that revision, and
update the revision and SHA-256 in its source record. Review changes against
`mister/catalog/catalog.go` and `mister/mgl/mgl.go`, then validate all aliases,
groups, slots, extensions and custom RBF paths. Run the complete test suite and
compare actual storage discovery, sorted gamelists, cold/warm full-build timings
and changed MGL launches against the previous release. Ship the catalog, source
record, compatibility policy and helpers together. Runtime updates never fetch
an unpinned catalog independently.

The active test release has no HDMI capture tool. The old desktop/workspace copy
of `SAM-HDMIcapture.sh` is historical and was not edited or shipped. If that tool
is reintroduced, make it call `samindex` and `sam_mgl.py` rather than copying
system or MGL tables.

See [validation](CATALOG_VALIDATION.md) for measured results and remaining limits.
