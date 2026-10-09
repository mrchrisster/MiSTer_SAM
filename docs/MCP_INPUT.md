# MCP input detection and ghost-session fixes

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
Concise MCP debug shows MiSTer/DB labels and action, with raw js indices only
when a saved MiSTer map is unavailable and warnings for exceptional fallbacks. Start/Select were subsequently verified on
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

With samdebug=yes, a bounded 256-message daemon output queue shows semantic
presses after dispatching the action. A full queue drops/counts messages instead
of blocking input. Controller names appear once; routine GUID/path/binding
tables and source tags are omitted. Example:

```text
MCP-INPUT: PLAYSTATION(R)3 Controller: DOWN MiSTer=Start DB=start action=start
```

Saved-map output omits js indices; DB/generic fallback includes them. Setup
prints Ready: Start/Select and exceptional mapping reasons. The standalone
[diagnostic](../.MiSTer_SAM/tools-extras/sam_input_debug.md) retains full metadata,
Linux codes, map/DB labels, snapshot comparison and automatic hotplug rescans.
Metadata/maps are resolved when the reader is created. The DB is cached once
per MCP process. Restart MCP after changing definitions; reconnect reloads maps,
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
