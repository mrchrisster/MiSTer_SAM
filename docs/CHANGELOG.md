# Recent changes

## 2026-10-09 — Shared module core eligibility

- Add a common requested → allowed → rotation pipeline with normalized IDs,
  module predicates, explicit rejection/error results and useful reasons.
- Replace BGM-specific compatibility filtering with its existing module hook.
  M82 declares its NES request/constraint; video declares matching-game support
  and distinguishes auxiliary playback from game selection.
- Enforce policy for normal/weighted selection, explicit targets, preparation,
  queued launches and Previous using the original game core. Remove unrestricted
  defaults and stop predictable empty/error cases before retrying forever.
- Refresh legacy/video weights from the current allowed pool; keep module count
  arrays global and avoid building every ROM catalog just to calculate weights.
- Freeze session settings. Menu starts validate changed switches in a fresh
  registry before interrupting an existing session. Unsupported artwork/mode
  combinations fail during pure validation, before setup work.
- Move M82 setup behind eligibility, with cancellable indexing and atomic list
  publication. Preserve first-input timing, BIOS order and Next behavior. MCP
  preparation/loading input uses cancellation/Next, with readers unchanged.
- Add focused core-policy and startup/cancellation regression fixtures.
- Bound invalid-ROM/MRA retries in compatibility selection. Keep loading Next
  bursts coalesced with a 50 ms quiet interval; a 1 ms read could expire under
  CPU load with input still pending. Include a private tmux-terminal fixture.
- MiSTer Linux: all 165 tests passed in 107.1 seconds, using isolated roots and
  mocked hardware operations. This includes 28 core-policy fixtures and the
  private tmux test. No production SAM scripts or actual game launches were
  changed by validation; physical M82/video playback remains a separate check.

## 2026-10-09 — Updater MCP shutdown race

- Treat MCP disappearing between a session check and `send-keys`/`kill-session`
  as successful shutdown. Check again after the fallback kill; block installation
  if the session still exists, rather than ignoring a real failure.
- Add regression fixtures for both races and for an unsuccessful shutdown.
- Preserve targeted MCP shutdown, graceful waiting and post-update restart.
- Fourteen installer tests passed on MiSTer Linux. A private tmux server also
  reproduced the exact check/exit/kill race: tmux returned 1 and shutdown still
  completed successfully.

## 2026-10-09 — Smaller update archive

- Exclude `mplayer`, `mplayer.zip` and obsolete `partun` from GitHub source
  archives with `export-ignore`. Native indexing tools remain included.
- Preserve an existing installed player. Optional video mode downloads the
  published executable when missing; fix its previous nonexistent ZIP URL.
- Add regression coverage for installing a release without the optional player
  and for successful/failed optional player downloads.
- The candidate archive shrank from 10.6 MiB to 2.9 MiB. Eleven installer tests
  and thirty shell tests passed on MiSTer Linux. The real optional-player download in temporary storage
  matched the published binary's SHA-256.
- Keep Linux shell/Python files at LF in exported archives. Isolate the synthetic
  queue fixture from real collection rescanning.

## 2026-10-09 — Configuration-only update backup

- Online updates hand off to the installer in the downloaded release, rather
  than applying it with stale installed update logic. The staged source is
  reused, with no second download; offline installs still use bundled source.
- Back up only the existing `MiSTer_SAM.ini` before an update changes files or
  stops sessions. Each backup has its own `install-*` directory.
- Remove the recursive `before.tar` backup of installed scripts, binaries,
  artwork caches, generated lists and historical backups. Existing backups
  remain untouched. A first installation has no configuration to back up.
- Add installer regression checks for exact configuration bytes, repeated
  updates, preserved caches/old backups, and aborting when the backup copy fails.
- Configuration restoration uses the saved INI. Script rollback requires
  reinstalling the desired release or using an older full backup.
- All eight installer tests passed on MiSTer Linux in 22.5 seconds using
  isolated temporary installation roots; production SAM was not updated.
- With the online handoff fix, all ten installer tests passed on MiSTer Linux
  in 27.9 seconds, again using isolated installation roots.

## 2026-10-08 — MCP input update for the test branch

### Controller definitions

- Resolve Start/play and Select/next from supported saved MiSTer global v3 maps,
  then exact controllerdb definitions, then generic activity. No second SAM
  controller setup is required for supported definitions.
- Bridge Linux codes to actual js indices through JSIOCGBTNMAP/JSIOCGAXMAP. DB
  indices are translated through event capabilities, including axes and hats.
- Match bus/vendor/product/version GUIDs; user DB precedes the shipped DB.
  Explicit unassignments stay unassigned. Invalid, unreadable or ambiguous
  saved maps suppress guessed named actions. Unique/alternate/merged identities
  and special map families remain limited; generic activity is the fallback.
- Stop loading legacy SAM controller JSON for MCP actions; older utilities
  retain it. Resolve metadata on discovery and cache DB contents per process.

### Response, debug and reconnect behavior

- Keep repeated js startup snapshots and the 20 ms wait, as requested. Compare
  keyed INIT state once and reuse changes for actions, activity and debug.
  Unchanged snapshots avoid repeated action/debug scans.
- Queue samdebug input messages through a bounded daemon logger; dispatch
  actions before logging. Show the controller once, MiSTer/DB semantic labels
  and the action. Omit source tags and routine tables; show raw js indices
  only when a saved MiSTer map is unavailable.
- Ignore direct software virtual/input hotplug notifications before debounce.
  Cache DELETE identity, reclassify CREATE, preserve unknown devices and
  Bluetooth UHID, and retain physical reader registration/reconnect handling.
- Restore the idle countdown, updating one line once per second while stopped
  and autostart is eligible. Input resets it; running, stopping, launch,
  menu-only blocking and cancellation clear it. Launch/ownership logic stays
  unchanged.

### Diagnostic and documentation

- Add a standalone stdlib-only diagnostic comparing js snapshots, EVIOCGKEY,
  EVIOCGABS and raw events with MiSTer/DB labels, debug logs and hotplug rescans.
  It does not grab/inject input or dispatch SAM actions.
- Expand MCP architecture/input documentation and add agent instructions so
  future work distinguishes blocked event delivery from available state
  queries. Preserve dedicated input threads and modular ownership/lifecycle.
- Add mapping, hotplug, countdown and diagnostic regression fixtures against
  the actual branch source; no test depends on an inspection snapshot.

### Hardware evidence and performance

Keyboard A was visible through EVIOCGKEY under SNES with zero raw evdev events.
HuiJia/Mayflash 0e8f_3013 version0110 Start was js9/Linux297 and Select was
js8/Linux296, matching its saved global map; snapshots and state queries saw
presses/releases during SNES. The PS3 production-reader capture recorded
Start/Select, removal/recreation and a correctly labelled Up after reconnect.
Post-reconnect Start/Select were not separately captured. Production core
cycling produced zero virtual-event4 scheduling lines after filtering.

Short quiet two-interface measurements at 50 Hz, percent of one CPU core:

| Path | CPU | Median work/interface | p95 |
| --- | ---: | ---: | ---: |
| Original js reader/action scan | 16.59% | 5.931 ms | 7.656 ms |
| Initial mapped js path | 20.87% | 6.409 ms | 8.154 ms |
| Optimized mapped js path | 17.74% | 5.973 ms | 8.093 ms |
| EVIOCGKEY only comparison | 1.53% | 0.059 ms | 0.116 ms |
| EVIOCGKEY + six ABS queries comparison | 3.44% | 0.264 ms | 0.359 ms |

State-query polling was measured but not enabled in production. These samples
exclude full MCP/SAM costs and do not measure physical button-to-quit latency.
Broader controller/identity/axis coverage and complete action/audio transitions
still require hardware validation. A production stop showed cleanup 0.98s,
Menu request 1.10s and confirmation 2.12s, but its physical input source was not
established. Cleanup/owner waits remain separate from polling cost.

The deployed MCP checksum is
f0a57f5e299e2043ff2bae6eb7ce8c9c5259ab182630db7b4c1a532181518be3; this branch
uses that tested modular variant. The downloaded workspace's older monolithic
launcher/MCP were not copied over the modular release. Deployments used
checksum guards, compilation and backups. SAM was restarted with samdebug Yes;
later debug/hotplug/countdown patches restarted only MCP.

During the first restart, matching a script path anywhere in argv also matched
the tmux server. SAM/MCP were restored. Subsequent restarts verified a Python
executable plus exact script argument or targeted only the MCP session.

Before branch integration, 55 workspace monitor fixtures passed. Branch
integration validation is recorded below.

## Other recent device work, recorded separately

These observations/fixes are documented here for continuity. This MCP commit
does not change the video module or install a DVD integration.

- Commercial count array: the deployed modular module's function-scoped
  declare -A lost SAMVC after loading, causing 3do arithmetic errors and
  index 0 counts. The device fix uses declare -gA. Cold/cache count generation
  and 40 weighted selections passed; a bounded live N64 commercial played.
- A separate staged patch guards temporary MiSTer.ini display overrides for
  CD-i commercial mode. It is recorded as a patch, not claimed here as a
  verified deployment.
- DVD core 0.9.0 test: direct playback of SAM's commercial CHD produced garbled
  output. A losslessly extracted MODE2/2352 track 2 BIN played correctly,
  confirmed by the user. DVD MGL uses index 0. Production remains CD-i;
  automatic DVD switching and collection-wide compatibility are unverified.

See [MCP_INPUT.md](MCP_INPUT.md) for behavior, constraints and the test procedure.

## Test-branch integration validation

- Host: 50 MCP mapping/hotplug/countdown/lifecycle tests and 17 standalone
  diagnostic tests passed. Status tests: 13 run, 12 passed, one Linux-only
  ownership test skipped on macOS. git diff --check passed.
- The deployed modular MCP matches the test branch baseline byte for byte
  before these patches. An AST comparison found only joystick_poller_thread,
  idle_and_status_checker, get_input_devices, hotplug_monitor_native and main
  changed among existing module functions; none were removed.
- MiSTer Linux: the complete suite ran 124 tests in 109.2 seconds. 121 passed;
  three installer fixtures encountered binary AppleDouble ._ files introduced
  by macOS tar, rather than repository content. After removing the 209 archive
  metadata artifacts from the isolated /tmp checkout, all six installer
  fixtures passed in 10.6 seconds. All 124 test cases therefore passed across
  the full run and affected-suite rerun. Production SAM/MCP remained active;
  fixtures do not install the candidate into /media/fat.
- Implementation committed and pushed to test as 71a711e. HTTPS credentials
  were unavailable; the push succeeded using the user's GitHub SSH key.
