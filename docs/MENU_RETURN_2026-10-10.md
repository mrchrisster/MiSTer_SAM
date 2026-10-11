# Menu return ordering — 2026-10-10

This follow-up changes SAM's exit ordering. It does not change input readers,
polling frequency, user INIs, ROMs, or the external BGM binary.

## Findings and changes

- The old early Menu handoff waited for preparation cancellation and BGM
  shutdown. Preparation alone took about 1.0–1.6 seconds in the instrumented
  runs. It now finishes while Menu loads. The foreground immediately revokes
  the preparer's publication token; actual launch jobs still have to be
  cancelled before Menu is requested. The owner remains alive, preventing a
  replacement SAM session from starting during cleanup.
- BGM termination can also overlap Menu loading. With `bgmstop=No`, SAM confirms
  `playincore=no` before requesting Menu. It no longer sends a late Stop that
  could stop Menu's newly resumed playlist. Keep-playing still stops BGM audio
  and restores the game.
- A launch-barrier marker proves that no more games can be launched, not that
  audio cleanup finished. A separate atomic PID/start-tagged RAM receipt records
  successful audio cleanup. Audio restoration requires the matching receipt,
  a dead old owner, and the existing fresh Menu/Main/FIFO checks. Failed
  preparation cleanup withholds the receipt and blocks replacement admission.
- A later Stop can finish a dead owner's pending audio cleanup under the
  admission lock. A replacement owner's audio cannot be restored by that retry.
- The standalone Menu acknowledgement backend skips gameplay tables and module
  initialization. Ordinary stop commands retain the full module context for
  compatibility with teardown callbacks.
- Optional `SAM_EXIT_TRACE=/tmp/name.trace` records stage timestamps using Bash
  builtins. It is disabled by default, adds no INI option or polling process,
  and is intended only for short diagnostics. Runtime receipts are also in RAM.
- Keep-playing commands acknowledge after cleanup. Their five-second reply
  budget could expire while valid teardown was still running. Play now has a
  bounded twenty-second completion budget; command claim expiry and the
  five-second budget for other actions are unchanged. This changes how long a
  caller can wait for completion, not how quickly cleanup executes.

Built-in preparation was audited: it scans/filters catalogs, validates ROM paths,
copies Amiga staging files privately, and prepares artwork caches. It does not
submit core loads, change live audio or mount hardware resources. External
plug-ins must obey this existing contract; none were present in this checkout.
The added `menu_prepare` hook and destination argument to `audio_stop` are
documented in `MODULE_API.md`.

## Validation

98 native ARM regression tests passed in 43.661 seconds. These are isolated
shell/process fixtures, covering actual private process cancellation as well as
mocked hardware: Menu delivery, owner replacement, stale receipts, failed
preparation, failed audio cleanup, recovery after owner death, both BGM stop
policies, module cleanup and command-entry tracing. The deliberate failure
fixtures retain protective state and refuse replacement admission.

The first 98-test run exposed two expectations for the old hook sequence and a
failure fixture whose EXIT trap retried its deliberately failed cleanup. Those
fixtures were corrected, and all 98 tests were rerun successfully.

All 14 native control tests also passed (35.50 seconds), including the new
completion-budget cases and Monitor/native command routing. The first combined
run exposed a Play fixture that extracted the finalizer without its new helper
dependencies; it failed in about three seconds, unrelated to the twenty-second
completion budget. Including those real helpers fixed the fixture.

Real SNES timing runs used RAM-only INI overrides, the installed native BGM
compatibility binary and the existing artwork database. No other tests ran
concurrently with the successful baseline/final timings. Menu means the observed
`CORENAME=MENU` transition, not a camera measurement of the display. Completion
also includes ownership and volume-overlay cleanup.

| Exit | Baseline Menu / completion | Final Menu / completion |
| --- | --- | --- |
| CLI, stop BGM service | 4.674 / 5.282 s | 2.824 / 4.247 s |
| CLI, retain BGM service | 4.874 / 6.132 s | 3.206 / 4.493 s |
| CLI, normal global mute | Not repeated as baseline | 2.544 / 5.892 s |
| Resident gateway, retain BGM service | Not measured on baseline | 2.349 / 4.215 s |

The resident gateway invokes the same owner-bound Bash Menu backend used by MCP,
without starting another Python CLI. Physical input detection was not simulated.
The full-stop trace accepted Menu at 2.152 s, observed Menu at 2.824 s, completed
preparation cancellation at 3.005 s, and restored audio at 4.131 s. This directly
demonstrates Menu loading during cleanup, rather than merely shortening a wait.
Samples confirmed volume protection remained until after Menu in every final
cycle. Persistent Menu music resumed with `playincore=no`.

Additional live checks passed: keep-playing retained the same SNES game with
`game_kept=yes`, released SAM's volume overlays and stopped persistent BGM
playback; Stop issued during actual SNES loading reached Menu, released ownership
and overlays, and produced no late game launch over a further three seconds.
That loading-stop completion took 7.368 seconds, so the faster steady-game Menu
samples above do not establish the same bound during a core load. Original
SAM/BGM INIs and underlying saved volume were unchanged after both checks.

Logs preserve the initial baseline and intermediate candidate, including slower
results. Load varied substantially (including other installed services), so these
are individual integration measurements, not a guaranteed latency benchmark.
The intermediate audio-only change still waited 1.0–1.6 s for preparation and
produced worse results in some runs; that led to the final deferred-preparation
change. The initial staged baseline lacked the installed artwork database; a
read-only directory symlink corrected the test setup before successful timings.
The radio endpoint was already unavailable, and physical button presses or
subjective audio were not tested.

Eight additional bind-mount tests passed on the ARM device in private mount
namespaces using disposable RAM files. They cover saved muted/unmuted values,
missing acknowledgement, failed unmount, overlay reacquisition, atomic file
replacement, killed owner recovery and core-volume protection across fresh
shells. These are real kernel bind mounts, not a physical power-cut test.

On power loss, processes and bind mounts disappear at reboot. SAM's temporary
volume overlays and cleanup receipts are RAM-only; the underlying saved volume
is preserved, including deliberate user mute. There is no boot-time forced
unmute. This does not guarantee filesystem integrity if power fails during an
unrelated write to storage.

## Installation and rollback

The source archive uses the `sam-menu-candidate` directory. Stage the archive in
RAM and use the existing installer, which backs up only `MiSTer_SAM.ini` and
writes changed runtime files:

```sh
tar -xzf /tmp/candidate.tar.gz -C /tmp
python3 /tmp/sam-menu-candidate/MiSTer_SAM_install.py --source-dir /tmp/sam-menu-candidate --mister-root /media/fat --branch test
bash /media/fat/Scripts/MiSTer_SAM_on.sh start
```

The incremental unified diff is against the preceding `sam-audio-policy.tar.gz`
deliverable. For rollback, stage that retained archive, stop the current SAM/MCP
through the current installer/lifecycle, and run its installer from the extracted
`sam-audio-policy` directory. Preserve user INIs and the installed external BGM
compatibility binary. This work is not pushed to GitHub.
