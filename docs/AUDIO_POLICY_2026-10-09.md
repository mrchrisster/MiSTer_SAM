# Preserve the user's audio settings

SAM's mute is temporary. Boot must not unmute a user-muted MiSTer, and ending
an attract session must restore the saved mute preference rather than force
sound on.

## Changes

- Removed `unmute_on_boot` from the supplied INIs, the boot command and its
  obsolete recovery function. Existing user INIs are preserved; old entries
  are ignored.
- Session audio restoration respects the original mute bit. A saved user mute
  stays muted after Menu return, keep-playing, and the shared M82/BGM restore
  paths. With no SAM volume overlay or pending restoration, cleanup does not
  issue a global-volume command merely because the INI enables SAM muting.
- A failed protective bind mount must not send a mute command to Main.
- Restoration information lives in RAM. The overlay stays mounted while Main
  restores the original mute bit; a differing bit must be observed in Main's
  delayed RAM save before SAM removes the overlay. Failed delivery, missing
  acknowledgment or failed unmount retains protection and a retry record.
  Full reboot discards that temporary state and exposes the original saved file.
- A shared 20-second Menu completion budget prevents repeated two-second audio
  waits from multiplying into minutes. Once fresh Menu is confirmed, audio
  failure alone does not reload Main and reset its delayed-save timer.
- Core mute writes `06` to RAM before mounting it. Exact target and source inode
  checks distinguish SAM overlays from foreign mounts. Mount failures stop game
  dispatch; failed removal of a previous core prevents another overlay being
  added. Mount state is discoverable across fresh shell invocations.
- BGM starts through its `exec` service interface. The installed ARM executable's
  no-argument interface is interactive: closed background stdin let its launcher
  exit before the extracted service was ready, losing the ancestry needed for
  reliable ownership. Native testing reproduced this failure.
- BGM ownership is recorded in RAM using PID, process start ticks, executable
  and socket identity. A wrapper and its service are tracked separately when
  necessary. Cleanup revalidates the instance before signalling it, never kills
  every process named `mpg123`, and reports a bounded shutdown failure.
- BGM commands are serialized through completion. On the installed service,
  stopping or restarting the radio playlist takes about two seconds; successful
  socket delivery alone is insufficient. Startup avoids restarting an already
  playing random playlist unnecessarily.
- `bgmstop=No` leaves the service available for Menu music. A successful early
  stop receipt prevents later Menu cleanup from stopping that playlist again.
  Keep-playing stops music in the game and restores the game's core-volume file.
- SAM no longer rewrites the BGM INI to enable debug logging. Existing external
  logging can still supply track metadata.
- A failed session-start hook now records an error and stops before selecting or
  launching a ROM. Previously a failed BGM start could continue with core audio
  muted and no background music. The normal cleanup trap still runs.
- Stopping/updating MCP now verifies that its Python process exits, including
  orphaned controllers whose tmux pane disappeared. The shared helper verifies
  the Python executable, exact script argument, PID and start ticks before TERM
  and a bounded KILL fallback. Start checks for exactly one controller, launches
  it with `exec`, and updates stop MCP before stopping SAM to prevent autostart
  races. Input monitoring and its polling interval are unchanged.

This does not change the explicit manual mute toggle. It adds no INI option,
resident helper, or countdown work. The existing fresh-Menu and session-owner
checks remain responsible for the timing of Menu audio restoration.

## Failure cases and compatibility

An unremovable bind survives a SAM process exit. The new code reports failure
and retains ownership evidence instead of treating that as restored audio.
Manual launches can still see the temporary mute until cleanup succeeds. A
full Linux reboot removes the RAM mount; no boot-time unmute is needed.

Killing the owner cannot run its EXIT trap. Recovery therefore uses actual
mount ownership and the RAM record rather than depending solely on shell
variables. These tests exercise process death and namespace teardown, not a
physical power cut or filesystem corruption.

The installed Main writes `Volume.dat` directly, which makes the RAM save
acknowledgment usable. A Main version that saves via atomic rename can fail to
replace a mounted file. That case is tested: restoration fails within its
budget and leaves protection in place. Compatibility with such a Main build
still needs a different acknowledgment mechanism; this is not a universal
claim for every Main release.

Legacy binds created by older SAM have no original-byte record. Their
compatibility path reads the original after unmounting, so it cannot provide
the new ordering guarantee during that one transition. Newly created binds
use the protected acknowledgment path.

BGM's installed `exec` interface and its PID/status/configuration socket replies
were verified on this device. An unknown socket or a detached external service
whose executable/ancestry cannot be verified is rejected; SAM does not adopt it
just because its filename resembles BGM. Integrations with a different external
BGM build must verify that service contract. BGM settings in `bgm.ini` are not
rewritten. Reply waits have a three-second timeout, and full service shutdown has
one shared three-to-four-second wait rather than a separate wait per process.
Readiness permits five-to-six seconds for a cold script-based service, returning
as soon as the PID and socket are verified. This is a maximum, not a startup sleep.
Repeated stops consult the recorded service rather than rescanning all processes
or taking ownership of a replacement service. Fresh starts retain discovery.

## Commands versus saved bytes

The installed Main source routes `volume mute/unmute` to `set_volume`, which
updates live audio and starts a one-second save timer. `load_volume` reads
`Volume.dat` during initialization; a direct edit alone does not update live
audio. A live command and temporary file protection therefore serve different
purposes, even when SAM exposes one control interface.

All live global mute/unmute commands now pass through `sam_audio_set_live`.
The explicit manual toggle retains its immediate byte update after successful
command delivery, preserving rapid-toggle and next-core behavior; it no longer
edits that byte after a failed command write. During protected global mute the
target is RAM. Without an overlay this explicit user action changes the saved
setting, unlike automatic boot/session restoration. The unused `write_byte`
helper was removed. File edits are not an alternate live-audio control path.

References: installed Main revision `47221c18987e101f50caafeb3b615f53b62722ca`,
`input.cpp` lines 6262–6266, `audio.cpp` functions `set_volume`, `save_volume`
and `load_volume`. Its [FileSave implementation](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/file_io.cpp#L725)
writes the target directly; the bind overlay redirects those saves to RAM.

## Verification

Before this change, the installed MiSTer had a RAM overlay byte `10` and an
underlying saved byte `00`. The underlying byte was read through an isolated
mount namespace without removing SAM's real overlay or writing the user's file.
That observation does not establish the cause of previously reported mute
incidents.

Eight real bind-mount scenarios passed in private Linux mount namespaces on the
MiSTer: original unmuted and muted settings, absent save acknowledgment, failed
unmount, restarting after failed unmount, atomic-rename save failure, owner
SIGKILL, and core-volume changes across fresh shells. These tests exercise real
mounts with simulated Main saves; they do not establish audible behavior.

Live global-audio tests also completed two mute/return-to-Menu cycles and a
keep-playing cycle. The original saved global byte remained `00`. The first live
BGM integration run exposed an orphaned service and failed cleanup; that failure
led to the service-entry and command-completion fixes described above.

The extended live run also exposed three orphaned MCP controllers alongside the
current controller. All four were identified by executable, exact script and
kernel start time before recovery. Thirteen old `sam_read_probe.sh` diagnostic
processes from earlier tests were removed separately; they are not evidence that
the current engine creates those helpers. Old commercial-selection/download test
files were archived locally and removed from RAM. Available memory increased
from about 47 MB during the incident to about 170 MB. The full suite then ran
with SAM/MCP paused in Menu, avoiding competing automatic launches.

Two live-harness mistakes were corrected without changing production selection
or volume behavior: the core ID is `genesis`, and FAT paths must be compared
without case sensitivity (`MEGADRIVE_volume.cfg` and `MegaDrive_volume.cfg` refer
to the same saved file). The original MegaDrive file remained byte `00` with its
April 12 timestamp. Temporary tmux INI/entry overrides are removed during test
teardown, and MCP teardown now uses the verified process helper.

A subsequent live Genesis run exposed a production regression in the new
strict mount checks as well: `/proc/mounts` reported FAT's canonical
`MegaDrive_volume.cfg` spelling, while the caller and RAM source used
`MEGADRIVE_volume.cfg`. Post-mount verification incorrectly failed, so ROM
retries stacked 24 overlays. The test was stopped and each layer was removed
only after matching its inode to SAM's RAM source; the underlying byte remained
`00`. Mount lookup now recognizes filesystem identity, and source recovery
matches actual RAM inodes without lowercasing names on case-sensitive storage.
Failed audio protection now stops selection with status 2 and a clear error
instead of retrying every ROM. New regressions cover reuse without another
mount, foreign-overlay rejection, canonical global paths and fatal dispatch
failure.

Automated checks on the MiSTer's ARM Linux environment:

- Full regression run: 505 tests, 504 passed and one control-fixture failure
  (436.3 seconds). The fixture omitted the audio-restoration provider now checked
  by keep-playing. After adding its no-hardware stub, all eight control tests
  passed (32.8 seconds). The entire suite was not repeated after that fixture-only
  correction.
- 24 BGM unit/process/socket integration tests passed, including delayed command
  completion, cold startup, repeated stop, persistent reuse, failed startup,
  detached service ownership and rejection of foreign endpoints.
- 27 MCP cleanup, installer and engine startup tests passed, including actual
  TERM-ignoring Linux processes and startup failure before ROM dispatch.
- Eight private-namespace mount scenarios passed as described above.
- After the FAT regression fix, 72 audio/core/Menu tests passed (33.1 seconds).
  The preceding 132-test run passed its 60 shell tests but exposed two mocked
  mount-owner fixtures needing the new resolver stub; both corrected fixtures
  are included in the passing 72-test run.
- On actual FAT storage, five mixed-case MegaDrive mute calls reused exactly
  one overlay, and restoration preserved the original `00` byte and timestamp.
- The separate native BGM ARM Go suites passed all 73 package and 21 CLI tests.
- All four engine tests passed after persisting fatal launch reasons for CLI
  feedback. The eight private-namespace mount cases also passed again against
  the final implementation.

These automated checks are distinct from real Main/BGM game-launch tests. No
physical reboot, power-cut or subjective listening test is part of this change.

Real SAM launches with the installed native BGM service passed SNES next-game
and Menu exit with `bgmstop=Yes`, and Genesis keep-playing with restored core
volume. N64, PSX and Saturn were rejected before launch because BGM requires
per-core volume support. A deliberately missing BGM executable produced the
startup error, left Main in Menu and removed the session without launching a
muted game. The saved global byte remained `00`; SAM and BGM INIs remained
byte-for-byte unchanged.

The configured radio stream was unreachable during the final live run
(`no route to host`). Service status and process/socket checks therefore prove
control behavior, not successful stream decoding or audible music.

The persistent-service test exposed a separate native BGM compatibility bug in
the installed `bgm v20260928-1 (d200ea0)`: its core watcher reloads `playincore`
from the INI on every CORENAME event, overwriting remote commands. In the live
test, SAM's acknowledged `set playincore no` became `yes` after Menu loaded,
matching the user's unchanged saved INI. With a saved `no`, the inverse can
stop music during SAM. This is separate from SAM's command-delivery and process
ownership fixes; a repeated socket write cannot guarantee ordering against the
watcher. A native BGM compatibility patch is supplied separately from SAM.
The patch retains socket overrides when the saved preference is unchanged,
while still applying an actual edit to that preference on a later core event.
It adds no polling, bind mount or configuration write. Its source baseline is
`d200ea0c5d8be05bd08975a8c62251baf2d1f082`, matching the installed version.
See the upstream [core watcher](https://github.com/wizzomafizzo/mrext/blob/d200ea0c5d8be05bd08975a8c62251baf2d1f082/pkg/bgm/service.go)
and [remote command handler](https://github.com/wizzomafizzo/mrext/blob/d200ea0c5d8be05bd08975a8c62251baf2d1f082/pkg/bgm/remote.go).

The original ARM binary also reproduced both failures in a private `--root`
fixture with its own CORENAME, socket, INI and silent local MP3. All eight
distinct/duplicate core events overwrote the requested policy. The fixture
observed the real `mpg123` decoder using that exact private track; it did not
write the actual MiSTer command interface or change the displayed core.
The fixed ARM build passed the same eight events in both policy combinations,
including decoder behavior and unchanged INI/command/startup sentinels. This
proves native decoding and policy control in isolation, not subjective sound
quality or physical speaker output.

The complete real SAM matrix then passed with the fixed native BGM executable:
SNES launch and Next, full-stop Menu return, Genesis keep-playing with restored
core volume, persistent Menu return, reuse of the same daemon for Genesis,
persistent keep-playing with music stopped, a further SNES/Menu cycle using
that same daemon, and explicit final termination. Normal SAM was restored with
the original INIs and saved global byte. This includes the previously failing
FAT and native-policy paths, not just isolated fixtures.

Measured CLI exit times in this last run were 5.684 seconds with full BGM stop,
and 7.631/7.062 seconds for persistent-player exits. Menu was observed after
4.716, 6.520 and 5.987 seconds respectively; audio-bind cleanup completed later.
These are integration traces under varying load, not controlled performance
benchmarks or physical button latency measurements. No instantaneous-return or
audible-output claim is made.

## Install and rollback

Installed and verified on `192.168.100.133`: 133 SAM runtime files matched the
candidate, and external BGM reports `v20260928-1-sam-policy (d200ea0-sam-policy)`.
The final INI-only installation backup is
`/media/fat/Scripts/.SAM_refactor_backups/install-20261010-004432-bvfhhoyg/MiSTer_SAM.ini`.
Normal SAM was restored and reached playing phase with exactly one MCP process,
no BGM daemon, no core-volume overlays and no temporary tmux configuration
overrides. Its one global RAM volume overlay is expected while normal SAM mute
is active; the underlying saved byte is still `00`.

The archive is a complete source/runtime package excluding large optional
binaries; the installer preserves installed optional binaries, user INI,
controller maps, plug-ins and Ignore lists. It backs up the INI only and writes
only changed runtime files.

```sh
tar -xzf /tmp/sam-audio-policy.tar.gz -C /tmp
python3 /tmp/sam-audio-policy/MiSTer_SAM_install.py --source-dir /tmp/sam-audio-policy --mister-root /media/fat --branch test
bash /media/fat/Scripts/MiSTer_SAM_on.sh start
```

The external native BGM fix is separate: SAM's installer deliberately preserves
`/media/fat/Scripts/bgm.sh`. The accompanying `bgm-compatibility` directory has
the ARMv7 executable, exact upstream source, unified patch, license, checksums,
build instructions and original device binary. Stage its candidate in `/tmp`,
stop SAM/BGM, then replace the external executable atomically:

```sh
bash /media/fat/Scripts/MiSTer_SAM_on.sh stop
/media/fat/Scripts/bgm.sh stop
cp /tmp/bgm-v20260928-1-sam-policy.arm /media/fat/Scripts/.bgm-sam-policy.tmp
chmod +x /media/fat/Scripts/.bgm-sam-policy.tmp
mv /media/fat/Scripts/.bgm-sam-policy.tmp /media/fat/Scripts/bgm.sh
/media/fat/Scripts/bgm.sh --version
bash /media/fat/Scripts/MiSTer_SAM_on.sh start
```

For external-BGM rollback, stop the service and replace that same executable
with the supplied `bgm-original-v20260928-1.sh` using the same staged-copy/rename
sequence. Its SHA-256 is
`59c0f7b68b8459a964498f6f04cb8836df13f6523744cdc3d489bc80e2f83a4c`.
Do not replace `bgm.ini`. A later external BGM update can overwrite this custom
build; this compatibility payload is not downloaded by routine SAM updates.

The unified patch applies to the preceding `sam-response-candidate.tar.gz`
deliverable. To roll back the SAM runtime, first use the current verified MCP
shutdown helper, then stop SAM, extract that retained archive and run its
installer. This also restores the preceding forced-unmute behavior; user
configuration and ROMs are not replaced. No GitHub push is included.
