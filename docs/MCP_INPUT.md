# MCP input detection and ghost-session fixes

## Bounded diagnostics, SSH keyboard actions and scroll shortcut: 2026-10-10

`m diagnostics` is the single history/support command; there is no separate
report command. It reads bounded literal data in `/tmp/.SAM_tmp/diagnostics`:
two 128 KiB decision-history files, atomic latest-exit/latest-failure snapshots,
and optional two 128 KiB SAM debug files. Default history stays below 264 KiB;
enabling `samdebuglog` adds at most 256 KiB. A successful later session replaces
latest-exit but preserves latest-failure. Reboot clears RAM history.

Foreground EXIT snapshots status, phase, mode, core, game and ROM before cleanup
removes session scratch. The wrapper preserves original exit status, records
TERM/keep-game intent, and retains cleanup failure status. Background workers
cannot publish foreground exit evidence. Unexplained nonzero exits produce a
generic error; supplied engine errors are not duplicated. Existing Menu/audio
ordering remains intact. `SIGKILL`/power loss cannot run EXIT; MCP may observe
owner disappearance, but that observation does not invent an exit status/cause.

MCP records accepted/suppressed input decisions, source/device, requested
commands, owner identity/phase, results and startup decisions. These are action
boundary/lifecycle writes, never unchanged joystick snapshots or timer ticks.
The shared JSONL writer rotates under a retained nonblocking flock. A busy lock
or IO error drops a history event rather than delaying/failing dispatch; this is
best-effort history, not a lossless event stream. Exit/failure snapshots are
separate atomic files. Diagnostic data is never sourced or evaluated.

S/s opens tmux history in both monitor views. Arrows/PgUp browse; Q returns to
the live view, where Q detaches. The original tmux prefix shortcuts remain.
SSH monitor attachment does not reserve MiSTer's physical keyboard. Only an
attachment on `/dev/ttyN` holds `mcp-console-keyboard.lock`, with the established
release grace; its reserved status is shown in monitor help. This fixes enabled
physical keyboard activity being observed but suppressed during SSH monitoring.

`m diagnostics --preview` renders the exact filtered upload content locally.
`m diagnostics --upload` explicitly sends it to 0x0.st and prints a share link.
This is not automatic crash telemetry. Full INI data is excluded; storage paths
and obvious credential values are filtered, with a 512 KiB payload cap. The
client identifies SAM, requests a longer random link and seven-day expiry, uses
verified HTTPS and bounded replies. Local logs remain after upload failures.
Custom multipart endpoints can be supplied with `--upload URL` or the optional
`SAM_LOG_UPLOAD_URL` environment variable; no new INI option is introduced.

Zaparoo uses the same multipart-file/URL pattern on its own Rustypaste service:
[announcement](https://zaparoo.org/blog/core-v2.9.1/),
[uploader source](https://github.com/ZaparooProject/zaparoo-core/blob/main/pkg/helpers/logupload.go).
SAM uses the free public [0x0.st API](https://0x0.st/) rather than Zaparoo's server.
Shared links are publicly readable by anyone who obtains them.

## Current MCP diagnostics and monitor keys: 2026-10-10

`m mcp_monitor` supports K (keyboard detection), J (joystick detection), M
(mouse detection), D (debug), R (restore current INI values and refresh mapping
labels), H/? (help and status), and Q/Ctrl-C (detach). Keys are case insensitive.
The ordinary `m monitor` retains its game controls. Detaching leaves MCP and SAM
running; Q detaches the current monitor client only.

Toggles are temporary for the current MCP process. They never rewrite an INI.
An edit to the corresponding INI option supersedes its temporary override;
unrelated edits preserve the other overrides. R clears all overrides and rereads
the current INI. Enabling debug rebuilds cached joystick labels without requiring
a controller reconnect. The status line shows enabled detectors and physical
reader counts. A detector may be disabled while debug continues observing it;
these observations do not dispatch actions or reset idle time for that detector.

With `samdebug` enabled, each observed physical joystick button DOWN reports its
device, js button index, Linux button code, MiSTer label, controller-DB label,
selected mapping source, resolved action, and detector state. Setup reports the
GUID and selected map/DB definitions. Unmapped and explicitly unassigned buttons
are included. Held startup state, releases and unchanged snapshots do not invent
presses. Labels are cached during discovery; the 20 ms reader performs no DB or
metadata reads. Debug uses a bounded 256-message output queue, not an SD log.
A completed tap between snapshots can be missed, and a saturated queue can drop
diagnostics; this is observation of sampled state, not a complete event history.

Raw physical keyboard debug identifies the device and HID report; it does not
claim decoded key names without a HID descriptor decoder. Existing keyboard
debouncing remains. Remote-log and NFC commands retain their separate action
paths and are not presented as physical button presses.

Discovery excludes software `/devices/virtual/input/` devices for joysticks,
keyboards and mice. Bluetooth UHID and unknown identities retain their existing
fallback handling. Mouse readers use individual physical `mouseN` nodes, never
the aggregate `/dev/input/mice`, which could mix in virtual activity. No virtual
devices are admitted solely for debug. Changes to virtual input nodes continue
to be ignored by hotplug scheduling.

An attached MCP monitor holds a shared RAM flock at
`/tmp/.SAM_tmp/mcp-monitor.lock`. The retained inode is never unlinked. MCP reserves
physical keyboard actions only for local `/dev/ttyN` attachments using the
separate `mcp-console-keyboard.lock`, with a 1.2-second release grace. SSH viewers
leave physical keyboard actions enabled; joystick actions remain available. The probe runs
at the action boundary and existing one-second checker, outside the 20 ms reader.
The console uses the existing event loop and restores terminal settings on close;
escape sequences cannot accidentally toggle options. No new input daemon, INI
option, persistent override file or diagnostic SD writes are introduced.

Both monitor views have a persistent three-line bottom tmux help bar. SAM shows
N/P next/previous, M mute, Y play (M82 only), Q detach, and tmux history/detach
shortcuts. MCP explains its detector/debug toggles, R restore, H/? help, Q detach
and temporary scope. Session-local key tables intercept Q/q for both views,
including during preparation or a core load; these keys do not enter the game
loop or send a stop command. Other tmux sessions retain their own options and
bindings. The footer is static and configured only on monitor attachment, adding
no input polling, timer work, helper process, INI change or SD write.

Live footer validation on tmux 3.1c: both views rendered all three lines in an
80-column terminal. Q/q detached SAM and Q detached MCP without replacing either
runtime owner. Ctrl-b [ history and Ctrl-b d detachment still worked; MCP toggles,
R restore, H help and Ctrl-C detach were rechecked. Other session/global tmux
options and the saved SAM, MiSTer and BGM INIs stayed unchanged. The option parser
requires session IDs rather than `=SAM`/`=MCP`; attachment resolves and verifies
the session name before configuring that exact ID.

Validation: 102 native ARM/Python 3.9 tests passed, including mapping/debug,
bounded readers, Linux PTY console behavior, temporary options, coordinator and
configuration reload. Installed MCP monitor K/J/M/D/R/H, Q and Ctrl-C passed real
terminal checks while the same MCP PID/start and SAM owner remained running;
saved SAM, MiSTer and BGM INIs remained byte-identical. This installation currently
exposes only software virtual input devices, so physical controller button labels
have fixture coverage but no new physical gameplay confirmation.

## Preset transitions: 2026-10-10

Preset starts stop the exact MCP instance before launching SAM so its startup
snapshot rereads the current INI and roulette sidecar. Otherwise entering or
leaving Roulette could retain the preceding listener policy. The existing
verified Python executable/script ownership checks remain in use. Reader and
polling behavior is unchanged. Canceling a preset does not restart MCP.

## Fresh Menu completion during a core change: 2026-10-09

A live Stop during Darkstalkers CPS2 loading exposed a stale Menu marker:
volume binds were released while the next core was still loading and its command
FIFO had no reader. Main publishes CORENAME before recreating/opening the FIFO.
The shared Bash stop path now captures the preceding Main PID/start, FIFO and
marker signatures before requesting Menu. Audio restoration requires a fresh
Menu marker, a new verified Main process and replacement FIFO, with that exact
Main holding the current FIFO inode. It rechecks the bound identities before
unmute and after restoration; a changed process or failed write retains pending
completion. Standalone audio recovery retains its existing ownership checks.

These checks run only during pending Menu completion. They add no input polling
work, resident process or ordinary countdown file writes. FIFO write success is
still transport acceptance, not an application acknowledgement or proof of
audible output. See [command delivery research](COMMAND_DELIVERY_RESEARCH_2026-10-09.md).

Menu dispatch can now overlap optional cleanup. The stopped owner first cancels
its private preparation/launch groups, runs all session-stop hooks (including
video/INI cleanup) and stops BGM, then publishes its exact PID/start in a private
quiescence marker. Only then may the waiting stop backend issue an early Menu
request. It captures the Main/FIFO/marker baseline before TERM and carries the
accepted request into final observation, avoiding an immediate duplicate reload.
The owner continues mount/display cleanup in its own process; it blocks new
session admission while alive. Audio still waits for owner exit and confirmed
fresh Menu/FIFO state. Failed critical cleanup does not publish the barrier.
The existing five-second owner-exit deadline remains: Menu can be visible while
completion is still reported as pending/failed. No extra dispatcher is spawned.

## Normal-loop migration and start admission: 2026-10-09

During an ordinary verified Next/Ignore operation, MCP retains one default/Exit
Menu request and delivers it after checking that the same PID/start still owns
SAM. Repeated requests coalesce; replacement owners, M82 actions and keep-playing
actions do not inherit this request. Startup retains its separate cancellation
barrier. This adds no reader polling or persistent process.

MCP automatic launches now use the shared gateway's conditional start path.
Automatic and manual starts serialize on a RAM start-admission lock; an automatic
request preserves a live owner or an exact SAM pane still initializing its owner
record. Explicit manual starts still replace a verified session; an occupied
pane without a verified owner produces a clear retry error. Admission waits up
to three seconds for the new foreground to publish ownership before unlocking,
but does not wait for ROM preparation. Spawned daemon children close inherited
lock descriptors. The lock releases before single-core startup feedback.

MCP resets idle activity once when a previously verified owner disappears,
including a CLI stop. This gives Menu a fresh idle interval instead of restarting
immediately from an old expired deadline. These changes address the two start
races found during live checks; they add no input polling change.

Normal/roulette timing is again handled directly by the foreground Bash owner.
The experimental Python timer/pipe bridge was removed after resource regression
measurements. Shared MCP input policy, command routing, ownership and the start
fixes above are retained. Input mappings, joystick snapshots, phase-aware routing
and Menu/audio ordering remain unchanged. See `LEAN_RUNTIME_2026-10-09.md`.

## Coordinator migration: 2026-10-09

MCP retains its device discovery, mappings, dedicated readers and joystick
snapshot backend. Its input/startup/cancellation policy now lives in
`sam/coordinator.py` with injected platform callbacks; `sam/session.py` supplies
bounded immutable PID/start/phase/launch snapshots. Compatibility wrappers in
MCP preserve the existing input diagnostic and regression-test boundaries.

MCP calls the shared local command gateway in process. Next and M82 play bind to
the captured owner and its exact tmux pane; Ignore also carries owner identity.
Startup retains a tracked launcher and the existing cancellation barrier.
MCP no longer writes Menu load commands or runs a separate audio-restore loop:
it uses the same owner-bound Bash stop path as the CLI. Keep-game requires a
playing/video phase, and stale Zaparoo input cannot unmute a replacement owner.
No input polling interval or mapping precedence changed. Native software and
private tmux tests do not establish physical button-to-Menu latency.


## DJ Wars cover reproduction: 2026-10-09

The earlier blank DJ Wars display was investigated separately from the Saturn
BIOS timing issue. The actual Monitor 2.11.1 resolver matched and decoded the
installed `DJ Wars (Japan) (Rev A) (10M).jpg` without loading or hashing the CHD.
An isolated temporary INI then selected that exact ROM through normal SAM
artwork filtering. From the first snapshot naming DJ Wars, all 67 sampled
`/media/artwork` responses returned HTTP 200 with the same valid 113,357-byte
JPEG (SHA-256 `8ff125cce660f11fe1bde744a7bfe54d76abae746243c2d066fd3539baabbb7e`).
SAM's current record also contained its decoded prepared DJ Wars cover.

The user confirmed the cover loaded on the display during this exact replay.
The original blank display was not reproduced, so its historical cause is not
established. No client retry/sequence issue is claimed as proven, and no artwork
matching or Android behavior was changed. Echo Show debugging was deferred at
the user's request. The permanent INI and ROM collection were unchanged; normal
Saturn selection was restored after the temporary test.

## Saturn BIOS timing: 2026-10-09

DJ Wars stayed in BIOS with the generic ten-second skip delay. The disc and
virtual keyboard map were present; a later manual retry of the same key started
the game. Saturn now has a twenty-second minimum delay in `CORE_SKIP_MIN_DELAY`,
which the generic skip helper applies after launch. A longer user `skiptime`
still takes priority. Other cores retain their configured delay; no extra
initialization work or timer process is added.

All 35 native shell tests passed, including the minimum, longer user settings,
fractional delays, unchanged FDS timing and cancellation. The user confirmed
automatic Saturn startup after installation. The reported missing DJ Wars cover
was also subsequently showing; artwork-only remains enabled. During diagnosis,
Monitor served valid covers for Dark Hunter and Rayman with HTTP 200 and SAM
had a decoded prepared cover. No Android/server artwork behavior was changed.

## Single-core startup and BIOS skip: 2026-10-09

Explicit core commands announce startup and observe the owned session's existing
phase/error records until the first launch, failure, or a 180-second feedback
timeout. They do not scan an additional list. Automatic starts remain asynchronous.
The pane shell uses exec so its PID is the SAM owner PID; feedback checks process
start ticks and ignores stale errors from other owners. A timeout leaves the
session running and reports that preparation is ongoing. Artwork-only single
Amiga/ao486/X68000/custom-MGL launches fail explicitly before stopping the current
session, since the artwork matcher has no catalog for those title/MGL layouts.

Delayed BIOS-skip jobs now begin after the load command and use the existing
owned launch-job cancellation on Next/Stop. CD32's separate delayed job is
preserved. The FDS catalog setname requires an FDS virtual keyboard profile;
the installer seeds missing bundled synthetic maps without replacing existing
maps. Input readers, physical mappings and polling frequency are unchanged.

Validation: 197 native tests passed in 137.282 seconds. The exact interactive
`m amiga` command printed its startup message and unsupported-artwork error,
returning status 1. A live `m fds` run reported preparation and then running;
the user confirmed Bomberman passed the FDS BIOS and reached the game. The FDS
single-core session was left running for further testing. Existing NES and
physical-controller maps were preserved; only the previously absent FDS virtual
keyboard profile was seeded.

## Core-policy refactor: 2026-10-09

M82 list setup now runs after its NES-only core policy and pure session validation,
inside the owned session setup phase. Its indexer uses an owned cancellable job
and private staging; a stopped setup cannot publish a partial list. MCP treats
input during M82 preparation/loading as cancellation (or Next), rather than
sending the play-timer signal before a game exists. Playing/BIOS routing retains
its existing behavior. Dedicated readers, mappings, 20 ms joystick snapshots,
owner validation and startup-launcher cancellation are unchanged.
Rejected starts are reported promptly rather than waiting for a nonexistent
owner until the startup timeout. The ordinary configured idle interval remains
in effect; no reader backend or polling frequency was changed.

## Installer shutdown race: 2026-10-09

The updater targets only the MCP tmux session. It requests Ctrl-C, allows two
seconds for graceful exit, then removes that session if necessary. MCP may exit
between a session check and either tmux command; a missing session/server is
successful shutdown. After the fallback kill, the installer checks liveness
again and aborts if MCP still exists. It restarts MCP after installation when
MCP was running at the start of the update. No input reader or mapping behavior
changes. Regression fixtures cover both disappearing-session races and a real
stop failure that leaves the session alive.

Compared against the upstream [test-branch MCP](https://raw.githubusercontent.com/mrchrisster/MiSTer_SAM/refs/heads/test/.MiSTer_SAM/MiSTer_SAM_MCP.py), fetched on 2026-10-02. That comparison describes the earlier deployed revision.

## Findings

A live reproduction exposed executor exhaustion. On this two-core MiSTer, Python's default executor has six workers. Three keyboard readers, a mouse reader, the remote-log reader and the Zaparoo reader occupied all six. Both SAM's status check and its stop command used that same executor, so input could be logged while shutdown waited indefinitely. This establishes a failure mechanism on this installation; it does not establish the cause of every historical user report.

Another live shutdown failure exposed kernels without CONFIG_PROC_CHILDREN: the background artwork downloader survived the old cancellation path and kept its shell parent waiting. Cancellation now falls back to builtin reads of `/proc/*/stat`, only at shutdown, validating each descendant’s parent and start ticks. Exit waiting also checks process state rather than using `kill -0`, which treats zombies as live.

A second live failure was an asyncio lock created before `asyncio.run()`. Concurrent hotplug rescans on Python 3.9 could fail with “Future attached to a different loop.” The lock is now created inside the running event loop.

Other defects found in the source:

- An untracked startup process could create a session after a stop attempt.
- A tmux pane alone does not establish SAM ownership or liveness.
- A fixed 15-second menu grace period cannot distinguish slow preparation, transient core loading and deliberate Menu-based video playback.
- The global joystick switch also disabled otherwise enabled keyboard, mouse and Zaparoo handling.
- Keyboard hotplug tracking omitted its own hidraw paths, allowing duplicate watchers.

## Implementation

The original upstream keyboard HID, joystick batch polling, mouse polling and device discovery are retained at the user's request. The attempted evdev keyboard replacement was reverted: MiSTer grabs event devices during core playback, preventing those readers from receiving keys. No HID descriptor decoder is included. Long-lived input readers use dedicated daemon threads so blocking reads cannot exhaust asyncio's command executor. Original blocking HID/mouse reads may remain asleep until input arrives; cancelling their asyncio wrappers does not interrupt a kernel read. Process shutdown releases the descriptors.

Hotplug notifications observe node changes under `/dev/input`; these also occur for virtual devices. On this MiSTer, `event4` is named `MiSTer virtual input` and is recreated during core changes. The 2026-10-08 filter below now ignores these notifications before scheduling a rescan; device discovery also excludes virtual inputs. Existing hidraw watchers are tracked to avoid duplicate readers. The inotify child is reaped on shutdown.

SAM's existing owner file now atomically includes `phase` and `launch` alongside `pid` and `start`. The phases are preparing, loading, playing, video and stopping. Publication occurs only at transitions. Optional Monitor/artwork modules and `/tmp/SAM_state`'s format are unchanged.

MCP validates the owner PID and process start ticks, including zombie rejection and correct parsing of parenthesized process names. A game launch must be observed outside Menu before a sustained Menu state can stop it. Two seconds of stable Menu are required; preparation, loading, unavailable CORENAME, and deliberate video playback do not arm this check. Normal-mode external Menu detection works independently of the input switches.

Input during startup cancels and reaps the tracked launcher before owner cleanup. Buffered Next coalesces and is delivered after launch. Next during loading bypasses the menu shutdown branch. Start/Zaparoo preserve the current game; ordinary input returns to Menu. M82 retains its BIOS/game input routing. Targeted shutdown passes expected owner PID/start ticks to the shell cleanup path and rejects a replaced/reused owner.

M82 input routing reads the mode of the current verified SAM owner when input arrives. Changing modes no longer requires restarting MCP; stale state cannot change routing. Original HID/joystick detection is unchanged.

No socket, new command daemon, full artwork dependency, Android change or new user setting was added.

## Validation

`tests/test_mcp.py`: 19 regression tests covering original joystick mapping/batch behavior, original HID reader routing and USB remote discovery, menu transitions, unavailable core state, video's deliberate Menu, valid/dead/zombie/reused ownership, startup cancellation and late starts, duplicate exit bursts, stale owners, M82 routing, disabled joystick with active keyboard/Zaparoo, executor exhaustion, and concurrent hotplug rescans.

`tests/test_shell.py`: 27 tests, including atomic lifecycle publication, old-owner publication rejection targeted shutdown rejection, and zombie/PID-reuse handling while waiting for exit, blocking descendant cancellation, and rejection of incorrect root start ticks. `tests/test_engine.py`: two real event-loop fixtures covering prepared Next, loading bursts, cleanup and external controls. These run against native MiSTer Bash/Python with isolated files and hardware effects replaced.

`tests/live_mcp_verify.py` sends the existing remote-log keyboard and Zaparoo signals. Live checks passed for owner/pane shutdown, kept-game state, external Menu cleanup, and restoration of normal configured SAM. An unchanged snapshot retained sequence 26, advertised all five controls, and returned a fresh timestamp. Normal SAM was restored after testing. Injecting text into the live remote log can race its producer, so this validates the MCP signal path rather than a physical keyboard or actual network-client key press. After restoring original detection, the user confirmed physical remote input keeps M82 games running and activates their play timer. At that earlier test there was no joystick device. Subsequent physical controller evidence is recorded in the 2026-10-08 update below. M82/video routing was tested with fixtures, not full hardware playback.

## Installed files and rollback

Changed files under `/media/fat/Scripts/.MiSTer_SAM`:

- `MiSTer_SAM_MCP.py`
- `lib/state.sh`, `lib/lifecycle.sh`, `lib/dispatch.sh`
- `lib/engine.sh`, `lib/launch.sh`
- `modules/compat-loop.sh`, `modules/video-functions.sh`

Backup: `/media/fat/Scripts/.SAM_refactor_backups/20261002-mcp-input/before.tar`.

SHA-256: `25c9d52df1814f6793f741a19ef566feabccbfb708c04f20ff72c550b28f5000`.

To restore the version installed immediately before this patch, run:

```sh
/media/fat/Scripts/.SAM_refactor_backups/20261002-mcp-input/rollback.sh
```

It verifies the backup, stops SAM/MCP, restores only the eight changed files through FAT-compatible copies, and restarts MCP and normal SAM. It preserves user configuration and lists. The earlier full-refactor rollback remains separate under `20261002-fresh-start`.

The HID restoration is separately backed up under `/media/fat/Scripts/.SAM_refactor_backups/20261002-mcp-hid-restore/`; `before.py` preserves the immediately preceding MCP. This small backup contains the rejected evdev revision and is for diagnosis, not the recommended rollback.

Live installation confirmed one reader each on `/dev/hidraw0`, `/dev/hidraw2` and `/dev/input/mice`. Restarting MCP preserved the existing SAM owner PID/start instance and active Monitor status.


## Input update: 2026-10-08

## Read this before changing input detection

**While a game core is running, MiSTer Main normally grabs Linux input devices
with `EVIOCGRAB`. Another process opening `/dev/input/eventX` does not thereby
receive its event stream. A persistent `/dev/input/jsX` event reader is also
affected by the underlying device grab.** Testing an event reader only during a
Scripts session or on desktop Linux does not establish gameplay compatibility.

**State queries are a different interface.** `EVIOCGKEY` reads the kernel's
current pressed-key/button bitmap through an evdev descriptor, even while
Main owns event delivery. Python can use it directly through the standard
library's `fcntl.ioctl`. `EVIOCGABS` queries an absolute axis's current value and
range. Neither operation requires taking the device away from Main.

**Current MCP does not read evdev events and does not call `EVIOCGKEY`.** It
reopens each joystick's `jsX` node every approximately 20 ms and reads synthetic
startup records. The button startup records contain current button state,
rather than requiring new event delivery to MCP. This repeated-open behavior is
intentional. Replacing it with one permanently open joystick event stream can
break input detection while a game is running.

Do not add an exclusive input grab to SAM's monitor: SAM must observe the
controller while the game continues receiving it. A zero-event read is not
evidence that Linux cannot query the device's state, and is not by itself proof
that a device is grabbed. No movement, a wrong node, permissions and other
errors must also be distinguished.

| Interface | What it supplies | Relevant constraint |
| --- | --- | --- |
| evdev `read(eventX)` | Press/release/movement events | Other readers normally receive no new events while Main holds the grab |
| joydev persistent `read(jsX)` | Startup state, then queued events | After the startup records, event delivery can be blocked |
| joydev reopen/read/close | A new startup snapshot on each open | MCP's current method; finite read size and sampling interval matter |
| `EVIOCGKEY` on `eventX` | Current keyboard/button bitmap | Does not include analog axes or hat positions; cannot recover completed taps |
| `EVIOCGABS` on `eventX` | One absolute axis's value/min/max/etc. | Separate query per axis; needs threshold and direction handling |
| `hidraw` reads | Raw HID reports | Device/report dependent; cannot assume every keyboard exposes a usable node |

Both state-polling methods can miss a press released between samples. A short
tap is not retained as history in the bitmap. A held button at initial capture
is baseline state, not a new press. Buttons and axes must be verified separately:
joydev's axis startup values involve its own corrected state, which must not be
assumed to behave identically to live `EVIOCGABS` values on every kernel/device.

Linux primary references:
[joystick startup records](https://docs.kernel.org/input/joydev/joystick-api.html),
[joydev implementation](https://github.com/torvalds/linux/blob/master/drivers/input/joydev.c),
[evdev implementation](https://github.com/torvalds/linux/blob/master/drivers/input/evdev.c),
[input ioctls](https://github.com/torvalds/linux/blob/master/include/uapi/linux/input.h),
[joystick ioctls](https://github.com/torvalds/linux/blob/master/include/uapi/linux/joystick.h).
These explain the interfaces; live tests on MiSTer's installed kernel remain
necessary. SNAC input does not appear as ordinary Linux input and is outside
these detection methods.

## MiSTer controller definitions and action resolution

Current MCP loads ordinary saved global v3 maps for action resolution.
`JSIOCGBTNMAP` translates js button indices to Linux key codes; `JSIOCGAXMAP`
translates js axis indices to ABS codes. Metadata queries bridge existing startup
snapshots to semantic definitions without replacing the input backend. MCP does
not add EVIOCGKEY polling or persistent evdev readers.

The ordinary global map paths used by the diagnostic, in order, are:

```text
/media/fat/config/inputs/input_<vendor>_<product>_v3.map
/media/fat/config/input_<vendor>_<product>_v3.map
```

A v3 map is normally **128 bytes**, containing **32 little-endian uint32 values**.
For the standard global mapping layout:

| Index | Meaning |
| --- | --- |
| 0–3 | Right, Left, Down, Up |
| 4–9 | A, B, X, Y, L, R |
| 10 | Select |
| 11 | Start |
| 21–22 | Menu button and its combo partner |
| 23 | Packed MENU OK in low 16 bits, MENU BACK in high 16 bits |
| 24–27 | Stick axis fields |
| 28–29 | Menu-stick axis fields |

Button slots contain Linux key codes, not joystick indices. Directions or even
buttons can be assigned synthetic axis-edge codes: `0x300 + axis*2 + direction`,
where direction 0 is negative and 1 is positive. Hat axes 16/17 consequently
use codes 800–803. Keyboard-coded bindings and synthetic axes do not appear in
the js button map. Zero means unassigned in the ordinary button slots. Special
fields require their own interpretation; do not run every uint32 through a
button lookup, truncate high bits, or guess at corrupt/flagged values.

**An existing ordinary map is not proof that Main is using it.** Main also has
per-core maps, `_m` alternate modes, unique-device suffixes/hashes, special adapter
identities and merged device interfaces. Some can share vendor/product IDs but
report the needed keys on another node. A global map's Start may also be explicitly
unassigned. Never silently replace a valid reassignment with `BTN_START=315`.
Do not confuse a game core's action layout with the global controller-definition
slots above. The diagnostic lists related files and allows `--map` selection;
that is an explicit inspection choice, not detection of Main's active map.

Before broadening identity support, prove the physical button -> js index ->
Linux code -> decoded slot chain during gameplay. Ordinary global Start=play /
Select=next definitions now work without a second SAM configuration. Zero slots
are honored. Invalid/unreadable maps never silently become database actions.
Related global unique/alternate filenames and known special adapter identity
families produce a reported generic fallback. This deliberately limits coverage:
Main's active unique/merged/alternate identity is not universally established.

### Lookup precedence and remaining identity work

The live device's `/media/fat/linux/gamecontrollerdb/gamecontrollerdb.txt` exists
and identifies itself as an SDL-format database modified to remove non-Linux
platforms and add MiSTer entries. MiSTer Main already consumes this format;
its [parser](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/gamecontroller_db.cpp)
is a useful primary reference for translating DB fields into Linux codes.
The [upstream database](https://github.com/mdqinc/SDL_GameControllerDB) is organized
by controller GUID and platform. The product requirement is **configure once in
MiSTer Main; SAM inherits it automatically**. Do not introduce a second SAM
controller setup requirement. Main's global controller definition (`mmap`) is
distinct from its per-core game-action mapping (`map`). Its
[input loader](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/input.cpp)
tries a saved global map, then the controller database, then built-in defaults.
Mirror that precedence rather than allowing DB defaults to override a saved
MiSTer assignment. Current supported lookup and remaining work are:

1. Load the ordinary saved global `.map` for supported model identities.
   Unique/alternate/merged identity resolution requires further validation;
   ambiguous identities use generic activity.
2. When no saved definition is available, inspect `gamecontrollerdb_user.txt`
   before the shipped `gamecontrollerdb.txt`, following Main's user-file precedence.
3. For a correctly identified compatible DB entry, use `start` for SAM's play
   action and `back` for Select/Share/next. SDL `back` is this physical control,
   not the B/cancel action from a user interface.
4. Retain generic activity when the definition cannot be established.
   Main-specific built-in defaults are not guessed by this implementation.
   An unknown js button press alone cannot establish which printed button is
   Start or Select. Avoid inventing those labels from an arbitrary index.

Translate the resulting Start/Select Linux codes to actual js button numbers
using `JSIOCGBTNMAP`, validating capabilities. An explicit unassignment in a
saved MiSTer definition stays unassigned; do not fill it from the DB or a guessed
button. Missing/unreadable/unsupported assignments have distinct debug reasons.
Legacy SAM controller JSON does not compete with this definition.

DB `bN` references the DB/SDL input enumeration. Main constructs its button
index table from event-node capability bits: supported codes from `BTN_JOYSTICK`
upwards first, then supported lower codes. For robust translation, resolve
DB button index -> Linux code -> index in the actual `JSIOCGBTNMAP` table.
Do not assume the second index equals the first, especially with keyboard-like
inputs, driver/backend differences or a modified joydev button map. Axes and
hat bindings (`aN`, signed axis halves, `hN.mask`) require their own translation;
do not treat them as button indices. MiSTer entries can also contain platform,
core-selection and Menu-combo extensions that a parser must handle deliberately.

GUID matching must distinguish bus type, vendor/product and version, including
USB/Bluetooth or other device modes. Follow the applicable Main/SDL identity
rules instead of matching only a name or vendor/product pair. Reject unsupported
or ambiguous candidates with a reason in the log. Parse/cache the database and
resolve mappings on discovery, rather than scanning it on every 20 ms poll.
Linux/generic MiSTer DB entries are supported. Core-specific entries are skipped;
when they make a matched identity ambiguous, named DB actions are suppressed.
Main's internal core aliases are not inferred from CORENAME alone. The USB
bcdDevice version exception for Reflex Adapt/RetroZord is followed at setup;
those adapters' special map identities still require further work.

**Mapping lookup does not change the input-access contract.** All three mapping
sources can feed the existing repeated js startup-snapshot reader. The final
fallback should remain this grab-compatible reader; a persistent stream of pure
js events can still be blocked while Main owns the device. The standalone diagnostic exposes selected files, entries, GUIDs and bindings.
MCP debug shows MiSTer/DB labels, raw js indices and Linux codes, selected mapping
source and resolved action for every observed digital press, including generic
and unmapped buttons. Start/Select were subsequently verified on
one adapter in the [controller hardware report](CHANGELOG.md).
Broader identity/axis/controller coverage and full action-transition validation
remain pending. The mapping update preserved registration, action dispatch and lifecycle.
Subsequent patches changed hotplug notification filtering and idle display only.

### Polling, debug and hotplug

The input backend remains repeated open/read/close of jsX, reading 512-byte
startup snapshots with a 20 ms wait. Initially held buttons are baseline state;
releases do not trigger actions. Cached keyed INIT snapshots are compared once
per sample; unchanged state avoids action/debug scans. Named axis roles cross
16384 of the normalized joydev half-range. Subthreshold role-axis movement
updates inactivity without prematurely exiting SAM. Generic detection retains
its existing 2000 axis-change threshold and positional snapshot limitations.

With samdebug=yes, a bounded 256-message daemon output queue shows observed
presses after action dispatch. A full queue drops/counts messages instead of
blocking input. Setup reports the exact GUID, selected map path and DB file/line
match once per reader. Each press includes both label sets, raw identity and
the chosen mapping/action source. Example:

```text
MCP-INPUT: PLAYSTATION(R)3 Controller: DOWN MiSTer=Start DB=start js_button=3 Linux=315 BTN_START source=MiSTer-map action=start detection=enabled
```

Debug remains able to observe joysticks and keyboards when their action gates
are disabled; those observations do not dispatch actions or reset idle time.
Initial/held states, releases and queued-only joystick events cannot create a
digital press. Debug output is conditional even when a queue already exists;
a closed terminal marks its queue dead so a later debug enable can recreate it.
Keyboard output identifies the hidraw device and a bounded raw report, with
key names explicitly unavailable: the existing byte reader has no verified HID
descriptor decoder. Its existing one-second debounce remains. Joystick samples
remain 20 ms startup snapshots, so taps entirely between snapshots are not
observable; queue overflow also prevents a guarantee of every physical tap.
Setup prints Ready: Start/Select and exceptional mapping reasons. The standalone
[diagnostic](../.MiSTer_SAM/tools-extras/sam_input_debug.md) retains full metadata,
Linux codes, map/DB labels, snapshot comparison and automatic hotplug rescans.
Metadata/maps are resolved when the reader is created. Enabling debug recreates
readers through the existing rescan so saved-map readers also gain cached DB
comparison labels. No metadata or DB I/O enters button polling. The DB is cached
once per MCP process. Restart MCP after changing definitions; reconnect reloads maps,
but DB file edits still require a restart. Legacy SAM controller JSON remains
for older utilities and does not configure current MCP actions.

InputHotplugFilter ignores direct /sys/devices/virtual/input software nodes,
including Main's virtual keyboard recreated by core loads. Classification is
cached for DELETE and always refreshed on CREATE so node reuse is safe. Unknown
identities and Bluetooth UHID under /sys/devices/virtual/misc/uhid remain
eligible. Ignored notifications do not cancel a physical debounce timer. The
existing two-second physical debounce and reader registration are retained.
This filter adds no work to button polling.

### Idle display and lifecycle preservation

The idle checker prints Starting SAM in Ns on one line once per second while
SAM is stopped and automatic launch is allowed. Activity resets the remaining
time. The line clears on running/stopping state, menu-only blocking, launch or
cancellation. The launch threshold and verified-owner checks are unchanged.

Dedicated input reader threads, startup cancellation, phase-aware Menu checks,
source-specific listener gates and targeted cleanup from the modular MCP are
preserved. Do not copy the older monolithic workspace MCP over this version.
When restarting MCP, target only its tmux session or verify a Python executable
with the exact script argument; the tmux server can retain the MCP path in argv.

### Verification and limits

Keyboard A was observed through EVIOCGKEY with SNES loaded and zero raw evdev
events. HuiJia/Mayflash Start (js9/Linux297) and Select (js8/Linux296) matched the
saved global map under SNES; both snapshots and state queries saw presses and
releases with zero raw evdev events. Different DB entries for the same VID/PID
but different versions had different indices.

The isolated production-reader PS3 capture recorded Start/Select, disconnect,
reader recreation, and a correctly labelled Up after reconnect. Start/Select
were not separately recorded after reconnect. A normal production Next/core
transition generated zero virtual-event4 rescan messages. Broader controller,
unique/merged/alternate map, axis-role and full action/audio coverage remains
pending. See [change log](CHANGELOG.md) for performance measurements and scope.

Run the mapping, hotplug, countdown and diagnostic fixtures together with the
existing modular lifecycle suite using the README's unittest command. Fixtures
cannot establish physical button-to-exit latency or universal gameplay support.


## Bounded reader audit: 2026-10-09

Joystick polling retains the 20 ms repeated-open startup-snapshot backend.
The raw, unbuffered read now covers the button-plus-axis count discovered once
at setup, rather than truncating every sample at 64 records. If metadata is
unavailable, its bounded fallback accommodates both byte-sized count fields.
Generic activity compares keyed INIT changes, avoiding positional mismatches
when queued records or record order differ; unchanged and queued-only samples
cannot replay a press. No extra metadata queries enter the polling loop.

Hidraw and mouse byte readers now use nonblocking descriptors with select.
Readiness wakes immediately; the 250 ms timeout only bounds idle cancellation.
The existing one-second flood debounce/reopen behavior remains, but cancellation
interrupts it. A removed silent reader closes its descriptor instead of leaving
a blocked daemon behind for each reconnect. This retains hidraw/mice semantics
and does not add evdev reads or exclusive grabs. Remote-log error waits are also
interruptible. No poll-rate option or additional SD writes were introduced.

Activity diagnostics also use the existing bounded debug queue after releasing
the state lock. Routine nondebug action output no longer blocks dispatch on a
slow terminal.

Eight isolated regression fixtures cover complete large-controller snapshots,
keyed generic matching, cancellation and descriptor closure for silent keyboard
and mouse readers, and immediate report readiness during cancellation debounce.
The integrated native suite passed all 304 tests; the final input subset passed
61 tests after the last logging adjustment. Pipe readiness and fixtures cannot
prove physical controller-to-Menu latency or universal hidraw compatibility;
no hardware input/reconnect evidence is claimed for this audit.


## Menu/audio ordering and runtime audit: 2026-10-09

Menu exit now writes a PID/start-tagged RAM marker before terminating the owner.
The owner cancels preparation and launch jobs and releases services while keeping
volume binds. MCP confirms Menu at 100 ms intervals, then the shell rechecks
CORENAME and ownership before restoring audio. CLI Menu retries also reject a
new live owner before issuing another load. Failed Menu loads stay muted and
report failure. No detached background cleanup may restore a newer session.

Startup input uses the same cancellation barrier and Menu stop; Start/Zaparoo
can preserve an already playing game. BGM Keep playing captures the verified
actual launch path before cleanup. Internal Monitor Play cancels owned work and
publishes inactive/kept status before reloading; failed handoff is reported.

The native 304-test suite covered lifecycle, both control routes, Menu failure,
replacement owners, stale markers, exact mount selection, and BGM reload paths.
An observation-only probe measured pipe-ready callback median 0.363 ms and max
1.132 ms (30 samples), silent cancellation max 249.810 ms (five samples), and
zero descriptor growth. Isolated five-second joystick samples used 6.41–6.56%
of one CPU versus baseline 6.56–7.46%; these overlapping short runs do not prove
a significant CPU improvement. No physical press-to-Menu or audible verification
was possible. See [the audit](AUDIT_2026-10-09.md) for scope, files and rollback.

## Bounded MCP shutdown and orphan recovery: 2026-10-09

Killing the MCP tmux pane can leave Python alive, including command executor threads during a core transition. Stop/restart and installer updates now stop every exact MCP script process before removing its pane or stopping SAM. The shutdown helper verifies Python executable, exact script argument and kernel PID/start identity before each signal: TERM gets three seconds, then verified survivors receive KILL with one second to disappear. Failure blocks restart/update. Start retains one verified MCP in its pane; duplicate or orphan instances are removed before replacement. No reader strategy, input polling or resident process changes. Test harnesses must use this helper instead of tmux-only teardown.

## Menu-first cleanup: 2026-10-10

The shared stop backend now allows Menu loading to overlap preparation-process
cancellation and BGM termination, after actual launch jobs and critical Menu
configuration have been settled. Audio restoration requires its own matching
cleanup receipt; Menu dispatch alone is insufficient. MCP still uses the same
owner-bound gateway and input readers. See [Menu return validation](MENU_RETURN_2026-10-10.md).

## Live SAM INI settings: 2026-10-10

The existing one-second MCP checker watches the SAM INI identity. It reads a
changed file only after two stable checker samples, validates literal assignments,
and keeps the last valid settings during incomplete edits. Idle timeout, Menu-only,
listener gates, Ignore-on-Next and debug settings update promptly. Gate changes
rescan the existing readers; unchanged settings do not rescan devices or read
controller metadata. The 20 ms joystick startup-snapshot loop is unchanged.

The verified owner receives a literal request in its private RAM session folder.
The ordinary game timer adjusts remaining time by the timer change, including a
paused timer; zero selects an indefinite countdown. M82 keeps its fixed demo
timer and applies changes to its separate play timer. Commercial video duration
remains controlled by the selected video. Reload checks use builtin file reads
at existing whole-second timer work, without a Python process on timer ticks.

Core/filter/category changes apply before the next game: the foreground cancels
and reaps its preparation worker, discards old proposals, advances the policy
revision and refreshes the existing module policy. Current gameplay continues
until its countdown or Next reaches that boundary. Temporary category choices
and permanent category exclusions use the same boundary notification.

Mode/module changes wait at that boundary. MCP validates the new configuration,
stops the exact old owner through normal Menu/audio cleanup, then uses the existing
tracked, cancellable launcher to create a new PID/start owner. A brief Menu
transition is expected. Human Stop/Play during that handoff suppresses automatic
restart; Next and ordinary activity preserve the requested mode change. Rejected
mode configurations retain the current game and report one error per revision.
No runtime record is sourced/evaluated, no additional user option or daemon is
introduced, and reload bookkeeping writes only RAM.

Native fixtures cover literal parsing, stable edits, owner-specific publication,
timer/pause adjustment, preparation fencing, mode validation and a human Stop
overriding replacement. Hardware input/audio behavior still requires live checks.

## Interactive menu ownership: 2026-10-10

The SAM menu owns a kernel flock for its complete premenu/dialog lifecycle in
`${SAM_MENU_TMP_ROOT:-/tmp/.SAM_menu}/menu.lock`. The lock stays outside session
scratch and is never unlinked. An existing unlocked file or an exited holder is
inactive; a symlink, nonregular file or unavailable existing lock blocks actions
conservatively. No PID-file timeout or new resident process is used.

MCP records activity but suppresses game actions while that lock is held. It
checks once at the actual action boundary, without changing the 20 ms joystick
startup-snapshot loop. Its existing one-second checker suppresses countdown
autostart, external Menu cleanup and configuration mode handoff while the UI is
open. Direct mode-boundary handoff also rechecks before stopping/restarting.

The short-lived `sam/menu_session.py` helper uses the existing owner-bound,
acknowledged Pause command before opening the UI. It refuses an active owner
that is preparing/loading, lacks ready control status, or uses M82/video mode
(the existing control transport supports Pause only for normal/roulette).
Inactive SAM remains configurable. An already paused owner stays paused.

A lease token is returned only after the UI changes Pause from false to true
and verifies the acknowledgement/status against the same PID/start, countdown
generation, start time and ROM path. On exit, Resume requires that exact ready,
still-paused selection. Stop, Next, an owner replacement or an external Resume
cannot transfer the lease to another game. Tokens are literal data and never
evaluated. Failed or uncertain acknowledgements report a clear retry/resume
message instead of claiming the timer was safely held.

Fixtures cover pause ownership, stale selections, unsupported/loading states,
uncertain acknowledgement, unchanged polling boundaries, suppressed autostart
and deferred mode handoff. Linux flock tests cover live/dead holders and retained
lock inodes; these fixtures do not establish physical gameplay input behavior.

The menu shares start-admission serialization before attempting Pause. New
manual starts are refused while the UI is locked; conditional autostarts skip
without disturbing the owner. A shell flock probe handles that admission check,
avoiding a Python startup probe. The one-second checker refreshes idle activity
while the UI is open so dismissal receives a fresh inactivity interval.

Dialog result tags use `--output-fd 3`; diagnostic stderr is separate. SAM sets
`DIALOG_ERROR=254` and `DIALOG_ESC=255` to distinguish internal errors from
Escape. Harmless terminal warnings do not convert cancellation into failure.
Nested dialogs reuse the same UI lifetime; each outer UI has private RAM result
and diagnostic files. These files are removed at normal/signal cleanup, and
exec paths release UI resources first. Menu Next/Stop/Play acts on the paused
selection before cleanup attempts an owner/selection-bound Resume; this avoids
advancing the old timer immediately before delivering Next.

Preset startup no longer stops MCP before exec, because changed INI settings
are already reloaded live. Reset INI deliberately quiesces MCP and stops the
verified SAM owner before clearing private list/mode scratch, preserves the
runtime root/lock inodes, and restores previously running MCP on ordinary
failure paths. Its presence check includes verified duplicate/orphan instances.

## Empty catalogue autostart suspension: 2026-10-10

Only exhausted discovery with no eligible/queued games publishes the typed
`reason=no_eligible_games` outcome. The foreground validates its policy revision
and live ownership, then records suppression in RAM before ordinary cleanup.
Generic errors, cancelled preparation and cleanup never create this outcome.
Single-core testing does not veto the separately configured automatic selection.

The record binds to the INI, public list and installed runtime paths. Publishing
holds the existing owner transition lock and rechecks PID/start, alive, exact
outcome/revision and applied INI/category/roulette/tag snapshots. A configuration
changed while the failed preparation ran cannot silently inherit the suspension.

MCP checks the RAM marker in its existing one-second checker. While blocked it
checks cached metadata of selected master lists, filter data, artwork indexes/
generation and installed code at five-second intervals. It never walks ROM trees,
hashes CHDs or runs this work in the 20 ms input loop. Dependency changes or
marker removal resume ordinary autostart. The marker survives MCP restart within
the current boot and disappears with RAM at reboot. Nested ROM additions require
a normal catalogue refresh; no collection scan is added by this guard.

Validated explicit starts clear suppression only after old-owner cleanup and
before spawning the replacement. Conditional automatic starts preserve it. A
fast empty owner can exit between MCP samples: its typed record ends startup
confirmation without a timeout or redundant Menu/core cleanup command. The same
quiet completion covers a conditional start skipped because a menu is open.

The original ROM collection, manual MiSTer game launching and saved INI are
unchanged. No new user option, SD marker or resident process is introduced.
