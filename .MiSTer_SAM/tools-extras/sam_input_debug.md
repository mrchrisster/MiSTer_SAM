# MiSTer input diagnostic

[sam_input_debug.py](sam_input_debug.py) compares the button state MCP obtains
from repeated `jsX` opens against live `EVIOCGKEY` queries, alongside raw evdev
events, axis state, MiSTer map decoding and installed controllerdb bindings.
It requires Python 3 and no packages.
It changes no SAM settings and sends no game/core commands. The only file it
writes is the diagnostic log. See the [MCP architecture guide](../MiSTer_SAM_MCP.md)
for the input-grab constraints and the production monitor's behavior.

## Copy and run

From your computer, copy this single file to MiSTer. Replace `MISTER_IP` with
your device's address. From the repository root:

```sh
scp .MiSTer_SAM/tools-extras/sam_input_debug.py root@MISTER_IP:/tmp/
ssh root@MISTER_IP
```

On MiSTer, first identify the devices:

```sh
python3 /tmp/sam_input_debug.py --list
```

Then run without device arguments to watch all current and newly connected
controllers:

```sh
python3 /tmp/sam_input_debug.py --log /tmp/sam-input-debug.log
```

Release all inputs before the baseline appears. With a game core running,
press **physical Start**, hold for one second, release, and repeat with Select,
A, B and Menu. Move the d-pad and stick. Compare the names printed by the
script with what you physically pressed. Repeat in MiSTer Menu and note which
phase produced each result. Main and a running MCP still react normally to
your input, so Menu/Start can change the game or SAM session during this test.
`CORENAME` lines record those transitions.

Press Ctrl-C for the summary. The script also prints a heartbeat every ten
seconds so silence between presses can be distinguished from a stopped poller.
Copy the log back **before rebooting**, because `/tmp` is temporary:

```sh
scp root@MISTER_IP:/tmp/sam-input-debug.log ./sam-input-debug.log
```

Other options:

```sh
# All current and newly connected js devices (including interfaces MCP might exclude)
python3 /tmp/sam_input_debug.py --duration 60

# Select an event-only keyboard encoder; no js comparison if it lacks a js node
python3 /tmp/sam_input_debug.py /dev/input/event3 --duration 60

# Inspect a related map explicitly; specify exactly one device
python3 /tmp/sam_input_debug.py /dev/input/js0 --map /media/fat/config/inputs/input_054c_0ce6_v3.map

# More detailed axis changes
python3 /tmp/sam_input_debug.py /dev/input/js0 --axis-delta 1
```

Use `--config-dir` or `--sam-dir` if the configuration is stored somewhere else.
Use `--controllerdb-dir` to select another database directory; the default is
`/media/fat/linux/gamecontrollerdb`.
Run `--help` for all options. The default sample interval is 0.02 seconds;
`--interval` changes it. Logging and multiple devices add overhead, so this is
a temporary diagnostic, not a replacement idle-monitor daemon. It rescans input
devices every two seconds. With no device arguments, it adds newly connected
joysticks automatically. Explicit paths restrict the test to those paths:
`js0 js1` will not include a new `js2`. Removed or replaced devices have their
descriptors closed; reconnection reloads the map and captures a fresh baseline.
Restart after changing the mapping of a device that remains connected.

## What the startup output establishes

| Output | Purpose |
| --- | --- |
| `INVENTORY` / `DEVICE` | Controller identity and the js/event handlers from the same `/proc` device block |
| `HOTPLUG ADDED` / `REMOVED` | Readers added or closed after connection changes; replacements get a fresh baseline |
| `EVIOCGID` | Identity queried from the paired event descriptor |
| `EV_KEY` / `EV_ABS` capabilities | Keys/buttons/axes the event interface claims to support |
| `JSIOCGBTNMAP` table | Actual js button number -> Linux key code translation |
| `JSIOCGAXMAP` table | js axis number -> Linux ABS axis code translation |
| `CONTROLLERDB loaded` / `DB GUID` / `DB MATCH` | Database file, exact bus/vendor/product/version GUID, selected entry and line number |
| `DB` binding rows | Database control -> original binding -> Linux button/ABS axis -> actual js number |
| `MAP CANDIDATE` | Related model, unique-device, alternate-mode and per-core filenames |
| `DECODED MAP` | The file explicitly inspected, not proof of Main's active file |
| Slot rows `[00]`–`[31]` | All 32 little-endian uint32 values, decimal/hex, with special-field interpretation |
| `SAM CONFIG` | Legacy SAM JSON file/model/default selection, retained for comparison with older utilities |
| `JS baseline` | INIT state and exact record order/type/number from MCP's 512-byte read |
| `EVIOCGKEY baseline` | Initially held Linux keys/buttons |
| `EVIOCGABS baseline` | Axis value, minimum, maximum, fuzz, flat and resolution |

Ordinary global lookup tries `config/inputs` before `config` for
`input_<vendor>_<product>_v3.map`. Unique or alternate names are **listed, not
guessed**. Use `--map` to inspect one explicitly. Invalid size is an error;
the script does not silently substitute another map. High/flagged uint32 values
remain intact. A zero assignment remains unassigned. Menu OK/BACK and axis fields
are not treated as ordinary button codes. A slot assigned to a synthetic axis
edge will correctly show no js **button** match.

## Reading a button test

An illustrative successful chain (actual numbers depend on your driver):

```text
js button 9 -> Linux 315 BTN_START
[11] Start decimal=315 ... js button=9; event capability=YES
EVIOCGKEY DOWN Linux=315 BTN_START MiSTer=Start DB=start
JS DOWN button=9 Linux=315 MiSTer=Start SAM=start EVIOCGKEY=1 DB=start
EVIOCGKEY UP Linux=315 BTN_START MiSTer=Start DB=start
JS UP button=9 Linux=315 MiSTer=Start SAM=start EVIOCGKEY=0 DB=start
```

The `MiSTer=` name is a **prediction from the inspected map**, not confirmation
from Main. `SAM=` describes the legacy controller JSON lookup for comparison; it does not
execute that action or describe the current MCP resolver. An UP line identifies the binding but MCP normally acts
only on a button's change to DOWN. A mismatch between `MiSTer=Start` and
`SAM=next` shows why adopting that map could change behavior.

`BTN_TL2`, `BTN_START` and similar names are Linux code names from the script's
name table. `DB=` comes from the installed database. The diagnostic checks
`gamecontrollerdb_user.txt` before `gamecontrollerdb.txt`, selects the last
eligible exact-GUID entry in each file, and reports unavailable or unsupported
bindings. It accepts Linux and generic MiSTer entries. Core-specific MiSTer
entries are explicitly skipped because `/tmp/CORENAME` alone does not establish
Main's internal core aliases. There is no name-only or vendor/product-only guess.
The database is read once per run; restart after editing it.

Database button indices are translated through event capabilities using Main's
enumeration (codes from `BTN_JOYSTICK` upward, then lower codes), then matched
against `JSIOCGBTNMAP`. Axis indices use supported non-hat ABS codes below
`ABS_HAT0X`; hats use their explicit axis and cardinal direction. Axis bindings
appear on both `EVIOCGABS` and JS axis lines. `dpup(-)` or `leftx(~)` describes
the binding's half/inversion, not a newly detected digital action. Raw axis
values/ranges remain visible; the script does not apply SDL trigger thresholds.

For example, the tested PS3 Bluetooth database entry binds `lefttrigger:a2`.
Its Linux button 312 (`BTN_TL2`) can therefore show `DB=unmapped`, while an
axis movement shows `DB=lefttrigger`. These are different input signals.
`DB=unavailable` means no usable matching entry/capabilities; `DB=unmapped`
means the matched entry has no binding for that particular button or axis.

Database labels are displayed alongside the saved MiSTer map, never substituted
for explicit unassigned slots. MCP now has its own cached resolver for ordinary
saved maps and DB fallback; see its guide for remaining identity limitations.
`SAM=` in this standalone script still reports legacy JSON for comparison, not
MCP's current action resolution. Database `back` names
Select/Share, and SDL face-button names can differ from MiSTer's A/B/X/Y slots.
References: [database format](https://github.com/mdqinc/SDL_GameControllerDB) and
[Main's database lookup](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/gamecontroller_db.cpp).

`STREAM` lines are events delivered to a separate persistent evdev descriptor.
The state-query descriptor is separate because `EVIOCGKEY` can flush its own
client's queued key events. **Empty STREAM output with changing snapshots is
consistent with Main's input grab**. Zero stream events alone cannot distinguish
a grab from an idle/wrong device. The diagnostic never attempts an `EVIOCGRAB`
probe and does not interrupt the game's input ownership.

`DISAGREE for 3 samples` means the paired js button and `EVIOCGKEY` value differed
for three consecutive samples. Queries occur sequentially, so one-sample
differences can be caused by a press occurring between them. Hold still and
reproduce a persistent disagreement before concluding the interfaces differ.

`JS list shape changed` identifies a length/order/type change relative to the
first read. MCP compares equal-length lists by position, so queued events or
partial snapshots can invalidate that assumption. The diagnostic tracks INIT
records by `(type, number)` separately; it is designed to expose this difference,
not to claim it reproduces every MCP action-routing decision.

`EVIOCGABS` reports raw axis values/ranges, whereas JS axes use joydev's normalized
and corrected values. Compare movement/direction rather than demanding identical
numbers. The raw-axis log threshold is capped at a quarter of its range, so
small-range hats remain visible even with the default 2000 threshold. Both
methods sample current state: very short taps may be missed. `ERROR` lines
include failures that must be resolved before interpreting silence.

## Evidence to return

Return the full log plus the controller model/connection and a short note of
the physical buttons pressed during game/Menu phases. The log includes kernel,
architecture, Python version, native event-record size, map tables and summary
counts. If it is large, first send the startup tables, relevant press/release
lines, ERROR/DISAGREE lines and summary, retaining the full file for follow-up.

Fixture tests run on the development computer with:

```sh
python3 -m unittest discover -s monitor -p test_sam_input_debug.py -v
```

These verify ioctl request construction, buffer mutation, map/database decoding,
exact-GUID and user-file selection, button/axis/hat translations and
simulated observations. They cannot verify actual MiSTer hardware or its kernel.
