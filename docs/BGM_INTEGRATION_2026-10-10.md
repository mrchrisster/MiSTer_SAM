# BGM control and SAM integration — 10 October 2026

SAM can temporarily control native BGM playback without changing the user's
saved BGM settings. Existing BGM implementations retain the legacy protocol.
No new SAM or BGM INI options are required. This is a SAM-maintained BGM build;
its binary is a separate optional payload, outside SAM's normal update archive.

## Problems addressed

- One idle socket client could block all BGM commands. On the real MiSTer, an
  idle connection delayed a second client's PID query by 4.857 seconds.
- A socket pathname could appear before BGM was listening. Startup now checks
  an actual PID response within a bounded deadline.
- Legacy mutation replies could not distinguish success from an unknown
  command. Optional version 2 requests return explicit applied/error results.
- Core boot sounds and delays held the command lock; stopped work could later
  resume playback or issue a volume command.
- SAM previously forced playback preferences using several separate commands.
  Native BGM now owns a temporary, session-bound playback override and restores
   the previous runtime preferences on release.

## Changes

1. BGM accepts bounded concurrent socket clients, with finite read/write and
   mutation-lock deadlines. Health/status reads remain available during playback
   work. Legacy short commands and their replies remain compatible.
2. Version 2 uses newline-terminated JSON, request IDs and explicit replies.
   Duplicate requests are idempotent; a reused ID with changed content fails.
   SAM negotiates support before using this protocol. A transport failure is
   not treated as proof that the server is an old implementation.
3. Playback, decoder/network work, boot delays and retries are cancellable.
   Shutdown joins the owned workers; obsolete boot work cannot resume later.
4. A policy identifies the SAM process by PID and Linux start ticks, plus a
   monotonically increasing revision. `active` temporarily enables SAM music;
   `menu` restores preferences and Menu music; `game` restores preferences and
   stops SAM music while the user keeps the game. Stale requests are rejected.
5. A SAM-started daemon receives its owner identity before startup sounds or
   volume side effects. While SAM owns playback, BGM suppresses those side
   effects. Owner death releases the override within the one-second polling
   interval, subject to scheduling. No policy writes the INI or volume files.
6. SAM stores negotiation and request acknowledgements in RAM, bound to the
   verified daemon identity. A retry reuses the pending request instead of
   issuing a second transition. Existing lifecycle audio barriers remain in use.
7. Play-in-core is mandatory while SAM owns playback. Socket requests to turn
   it off cannot override that policy; v2 returns an explicit error. Saved
   preference changes are retained for after SAM releases playback.
8. The stop wait includes the rounding allowance required by Bash's integer
   `SECONDS`. Menu exits allow ten full seconds for owned cleanup; start/restart
   retains five. Live cleanup took 5.693 seconds in one run, legitimately
   exceeding the old stop budget. Early Menu delivery and ownership checks are
   unchanged; the longer bound does not insert a fixed delay into successful
   stops or delay Menu dispatch.

Saved `playincore=yes` is deliberately restored as `yes`; it must not be forced
to `no` after SAM exits. Actual saved preference edits made during SAM are also
honored. `bgmstop=Yes` continues to stop the owned BGM process.

## Station repair

The installed `80s.pls` refers to Pure Classix. Its old port-8001 URL was
unreachable from this MiSTer. The station's current official site,
[Pure Classics](https://www.pureclassics.nl/), embeds
`https://mscp4.live-streams.nl:8142/live.mp3`.

The endpoint returned HTTP 200 and MPEG audio. The installed native BGM decoded
the stream in a silent test using its HTTPS reader and mpg123 stdin path. The
playlist URL was replaced atomically; the original playlist is in the output
bundle. This station is not exclusively 1980s music.

## Validation

- Real ARM socket fixture: the idle-client case improved from 4.857 seconds to
  0.0018 seconds for the second PID query. This measures socket responsiveness,
  not end-to-end Menu latency.
- SAM's 121 BGM/client/integration/Menu/audio/owned-job/installer tests passed
  on the MiSTer's Python 3.9 and Bash environment.
- Native BGM package and CLI suites passed on ARM; focused cancellation/socket/
  policy tests passed under the Linux race detector.
- Full repository tests passed on Linux with uncached test execution. The Mage
  test target was run with an isolated Go wrapper adding `-count=1` because the
  cached Go runner stalled; no source or test was skipped for this workaround.
- Full repository lint reported zero issues and `mage mister bgm` built the
  native ARM executable.
- Five native Bash tests cover the stop rounding boundary, bounded timeout,
  PID reuse and early Menu dispatch during longer cleanup.
- Real SNES runs passed stop with BGM terminated, stop with BGM retained,
  stop without BGM, keep-playing and cancellation during ROM loading. Saved
  SAM/BGM INIs and underlying volume remained unchanged. Menu was observed
  after 3.236, 4.695 and 2.522 seconds in the first three cases; full command
  completion including audio cleanup took 4.352, 6.110 and 5.686 seconds.
  These are individual observations, not controlled performance guarantees.
- The final resident-gateway test passed with mandatory play-in-core rejection
  verified on the device: Menu appeared at 3.644 seconds, the owner finished
  cleanup at 5.015 seconds, and command completion was 5.844 seconds. Mute was
  retained until Menu. The earlier deadline failures are retained in the logs.

Final live outcomes and installation verification are recorded in the output
bundle's verification logs. Fixture tests do not prove audible output, physical
controller latency or behavior during a physical power cut.

## Installation and rollback

Installed and verified on the development MiSTer. All 134 runtime files matched
the package, one MCP remained, no test BGM process remained, and both INI hashes
and the underlying saved volume matched their pre-test values. Normal SAM was
restored to playing with its original settings. The obsolete temporary OLED
test pane and inactive RAM test payloads were removed using ownership checks.
The INI-only backup is
`/media/fat/Scripts/.SAM_refactor_backups/install-20261010-084608-lbnxyvha/MiSTer_SAM.ini`.

The output bundle contains the complete SAM source archive, a SAM diff against
the preceding Menu-return build, the native BGM binary, its full source patch
against upstream d200ea0, and the previously installed native BGM binary.
The complete corresponding BGM source archive and upstream license accompany
the binary for hosting this fork. No release or download URL is published by
this package.
The SAM installer preserves the user's settings and backs up only the SAM INI.

Copy the archive and BGM binary to MiSTer's `/tmp`. Stop SAM through its normal
stop command, extract the archive there, and run its installer:

```sh
bash /media/fat/Scripts/MiSTer_SAM_on.sh stop
tar -xzf /tmp/sam-bgm-integration.tar.gz -C /tmp
python3 /tmp/sam-bgm-integration/MiSTer_SAM_install.py \
  --source-dir /tmp/sam-bgm-integration --branch test
```

Replace `/media/fat/Scripts/bgm.sh` only while that exact daemon is stopped.
Verify the supplied SHA-256, copy to a temporary sibling file, mark it executable,
then rename it over `bgm.sh`. The supplied deployment helper performs those
checks and atomic replacement. For the preceding installed native build:

```sh
python3 /tmp/install_bgm.py /tmp/bgm-sam-control.arm \
  --sha256 5215436f403297313ff4a04f25ad46175cd1aac3a86538828204601e6b2c6e3b \
  --expected-old d2289efa4f92cb2b40aaadf0c356223fedadf1c25517cbfb431db08e35fdf06d
bash /media/fat/Scripts/MiSTer_SAM_on.sh start
```

The expected-old check deliberately refuses a different installed binary;
verify and retain that binary before adapting the command for another device.

To roll back, stop SAM/BGM, install the preceding
`sam-menu-return-2026-10-10/candidate.tar.gz` using its installer, and atomically
restore `bgm-previous.arm` as `/media/fat/Scripts/bgm.sh`. The extra unused Python
client file can remain. Restore `80s.pls.original` only if reverting the station
URL is also wanted. Neither code rollback requires overwriting the user INIs.
