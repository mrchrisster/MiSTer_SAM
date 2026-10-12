# Recent changes

## 2026-10-11 — Resident session owner on test

- Make the Python session coordinator the default owner for normal, roulette,
  M82 and video. Keep one persistent Bash adapter for existing platform functions
  and one preparation job, with shared programme/timer service bindings.
- Route warm controls through authenticated RAM records; prioritize Stop during
  loading and retain applied receipts after scratch cleanup. Keep Menu writer
  quiescence, audio completion and fresh Main/FIFO checks.
- Add parent-death cleanup, old-adapter admission fencing and deferred signals
  during job registration. Preserve Scripts UI owner identity and temporary
  `SAM_ENGINE=legacy` comparison sessions without changing the INI.
- Fix Bash's queued registration STOP notification being mistaken for command
  termination: use `wait -f` on owned setup commands. Before the fix, stress
  reproduced launch status 147; afterward all 100 stressed Stop cases passed.
- Validation: 946 Linux tests ran, 928 passed and 18 host-specific cases skipped.
  Focused ARM owner, mode, control, ownership and Menu/audio suites passed.
  Actual normal SAM selected SMS and N64 games; Monitor's path matched SAM and
  its artwork endpoint served a JPEG. Pause/Resume/Next and Menu Stop succeeded.
  Saved INIs and original Volume.dat were unchanged after cleanup.
- One live Menu timing probe observed the Menu marker after 1.073 s and full
  completion after 4.231 s. This is not a physical button/CRT measurement. Initial
  live Start still took 17.804 s to controls-ready, including selection/artwork/
  setup; research's mock timings must not be presented as actual startup speed.
  Physical reconnect, Echo Show/CRT visual boot and new M82/video hardware runs
  were not revalidated in this switch.

Current boundaries and rollback: [SESSION_ENGINE.md](SESSION_ENGINE.md).

## 2026-10-11 — M82 gameplay and MCP input display

- Stop M82 gameplay mappings from skipping/quitting during startup, loading or
  play. Restore SAM-owned audio before extending the play timer, acknowledge the
  active owner/launch, and suppress repeated play commands.
- Detect external Menu after an M82 game, stop that session, and wait for Menu's
  fresh idle interval before automatic restart.
- Replace repeated physical-input pane lines with one updating footer: bold
  MiSTer button, controller DB information, Linux fallback. Retain detailed
  mapping/action evidence in bounded diagnostics.
- Pause physical device sampling during manual games when Menu-only is enabled;
  resume safely in Menu/SAM without manufactured held-button presses.

## 2026-10-11 — Lightweight command caller

- Separate pre-menu/UI/monitor callers from engine initialization. Defer runtime
  tables, MiSTer.ini volume-path reads and optional session modules until needed.
- Replace the combined command switch with explicit gateway/UI/runtime routing;
  retain `parse_cmd` as a compatibility shim. Remove Start Monitor's fixed sleep.
- Preserve menu/admission locks and active-session pause leases. A menu with no
  owner avoids starting pause/resume helpers. Registry/mount arrays remain global
  under lazy loading. Source-only callers still receive the complete runtime.

## 2026-10-11 — Menu access, monitor controls and start instructions

- After installation or update, show `MiSTer_SAM_on.sh start` rather than
  assuming the optional `m` shortcut is installed.
- Remove the SAM monitor's Y/M82 play shortcut while preserving physical M82
  actions. Simplify both monitor footers to mention Q only as detach.
- Restore menu access during commercial and M82 mode. Those modes continue
  playback behind the locked menu without an unsupported pause/resume request.

## 2026-10-10 — Diagnostics, optional free log upload and clearer updates

- Retain timestamped lifecycle/input decisions in bounded RAM history. Preserve
  the latest exit and latest failure separately across subsequent runs; capture
  exit status/selection before cleanup while preserving existing exit semantics.
- Add one `m diagnostics` command and a Diagnostics and logs menu: view history,
  verbose debug, preview upload content, or explicitly upload a filtered log.
  Free 0x0.st uploads return a shareable link and request a random secret URL
  and seven-day expiry. No account, new INI setting or automatic telemetry.
- Bound optional SAM debug files in RAM. No unchanged input samples, timer ticks,
  ROM scans or ROM hashing are added to logging. Busy diagnostic locks fail open.
- Fix physical keyboard actions being suppressed during SSH MCP monitoring;
  reserve console hotkeys only on the actual local MiSTer virtual console.
  Add S scrollback in both monitors, with Q returning to the live view.
- Show update stages, download size/time, settings backup and updated/current
  file counts. Replace tracebacks with concise network/TLS/validation/install
  errors, retain certificate verification and explain device-time checks.
- Exported Linux suite: 762 tests passed, nine existing socat-dependent BGM cases
  skipped on that host. Controlled native Python 3.9 checks passed 99 of 100,
  with the remaining HTTP-error fixture corrected and all 15 upload cases then
  passing. A loaded native run timed out and is not counted as a pass. Real
  installed checks are recorded separately.

## 2026-10-10 — Lean runtime, reliable cleanup and configurable selection

- Keep normal/roulette timing in the foreground Bash owner; remove the discarded
  resident Python timer bridge. Share command routing and verified owner/phase
  handling across CLI, menus and MCP. No new control daemon is introduced.
- Serialize starts, fence preparation/launch cancellation, coalesce loading input
  and release resources through bounded owner-specific cleanup. Deliver Menu as
  soon as critical launch/module work is quiescent; finish optional cleanup after.
- Require fresh Menu/Main/FIFO identities before restoring audio. Preserve saved
  global/core volume and mute preferences with owned RAM bind mounts, including
  reboot/error recovery. Remove startup unmute that changed user preferences.
- Add bounded BGM negotiation, acknowledgements and session playback policy, with
  legacy compatibility. The separately built native BGM remains an optional
  payload; it is not added to SAM's regular source archive.
- Refresh timers/input settings live and apply validated mode/module selection
  changes at the next game boundary. M82/commercial sessions disable artwork-only
  filtering without changing the saved normal-mode preference.
- Replace broad Kids franchise matches with conservative platform-specific
  all-ages lists and exact reviewed Neo Geo aliases. Add persistent or boot-only
  category presets, genre-folder membership and conservative exact-title fallback.
- Distinguish failed scans/filters from valid empty catalogues. Suspend autostart
  after confirmed exhaustion; configuration/catalogue changes or explicit start
  permit a fresh attempt. Preserve master ROM collections and manual launching.
- Make dialog ownership, result handling and pause/resume safe across concurrent
  menus, cancellations and reused process identities. Retain shared lock inodes.
- Report observed physical buttons with js/Linux codes, MiSTer/DB labels, mapping
  source and action. Exclude software virtual inputs; cache labels outside the
  20 ms joystick snapshots and queue conditional debug output.
- Add temporary MCP monitor K/J/M/D toggles, R restore and H/? help. Both monitor
  views have persistent bottom help bars and Q detachment handled directly by
  tmux. Preserve SAM/MCP owners, INIs and other tmux sessions on detachment.
- Native and live validation is recorded in the focused audit, audio, BGM, Kids,
  category, lean-runtime and MCP documents. The final MCP suite passed 102 native
  tests; installed 80-column terminal checks verified help, toggles, history and
  detachment. Final payload checks matched 167 runtime/public files. Physical
  button/CRT/audio observations are distinguished from software fixtures.
- Publication check: 720 exported-source tests ran on desktop Linux; 711 passed
  and nine BGM integration cases were skipped because that host lacks socat.
  Those integration cases have earlier native MiSTer coverage in the 121-test
  BGM suite. Correct stale startup/filter fixtures and export INIs, lists, JSON
  and documentation with LF; preserve the pinned upstream catalogue bytes.

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
