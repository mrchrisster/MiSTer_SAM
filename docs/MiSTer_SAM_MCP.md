# MiSTer SAM — Master Control Program (MCP)

`MiSTer_SAM_MCP.py` is the background daemon that drives the SAM attract-mode loop.
It replaces the older `MiSTer_SAM_joy.py` with a fully async architecture, hot-plug
device support, and richer state management.

---

## Overview

MCP runs as a persistent process (in a `tmux` session named **MCP**) and does three things:

1. **Idle timer** — tracks user inactivity and launches SAM when the threshold is reached.
2. **Input monitoring** — watches joysticks, keyboards, mice, and the remote log for any
   user input and either resets the idle timer or stops/skips SAM accordingly.
3. **State management** — tracks whether SAM is running, starting up, or stopping, and
   prevents race conditions between concurrent input events.

---

## Configuration

MCP reads `MiSTer_SAM.ini` at startup. Relevant keys:

| INI key          | Default | Description                                              |
|------------------|---------|----------------------------------------------------------|
| `samtimeout`     | `60`    | Seconds of idle time before SAM starts                   |
| `menuonly`       | `yes`   | Only start SAM when the MiSTer main menu is visible      |
| `listenjoy`      | `yes`   | Monitor joystick / gamepad devices                       |
| `listenkeyboard` | `yes`   | Monitor keyboard hidraw devices and `/tmp/remote.log`    |
| `listenmouse`    | `yes`   | Monitor `/dev/input/mice`                                |

Controller button mappings are read from `sam_controllers.json` (same directory).
Devices are matched by `vendor_product` ID (e.g. `"2dc8_6002"`), falling back to the
`"default"` entry for unrecognised controllers.

---

## Architecture

MCP uses Python `asyncio` as its main thread, with blocking I/O pushed into OS threads
via `asyncio.to_thread()`. Communication from threads back to the async loop uses
`loop.call_soon_threadsafe()`.

```
asyncio event loop
├── idle_and_status_checker   (coroutine, runs every 1 s)
├── hotplug_monitor_native    (coroutine, reads inotifywait stdout)
├── watch_joystick_device     (per device — wraps joystick_poller_thread)
├── watch_keyboard_device     (per device — wraps keyboard_poller_thread)
├── watch_mouse_device        (wraps mouse_poller_thread)
└── watch_remote_log          (wraps remote_log_poller_thread)

OS threads (via asyncio.to_thread)
├── joystick_poller_thread    (one per /dev/input/jsX)
├── keyboard_poller_thread    (one per /dev/hidrawX)
├── mouse_poller_thread       (/dev/input/mice)
└── remote_log_poller_thread  (/tmp/remote.log)
```

---

## State machine (`SamState`)

Thread-safe state container. All fields are protected by a `threading.Lock`.

| Field / property         | Meaning                                                          |
|--------------------------|------------------------------------------------------------------|
| `last_activity`          | Monotonic timestamp of last user input                           |
| `idle_timeout`           | Seconds until SAM starts (from `samtimeout`)                     |
| `menu_only`              | Whether `menuonly` is enabled                                    |
| `_sam_is_running`        | Python's belief of whether the SAM tmux session is live          |
| `_log_activity`          | Enables "Activity detected" log lines (only while SAM is running)|
| `_is_stopping`           | Lock flag — prevents concurrent stop actions                     |
| `_boot_complete`         | Set once the MiSTer boot phase is detected as finished           |
| `_sam_is_starting`       | True between `start_sam()` call and tmux session confirmation    |
| `_pending_action`        | User input buffered while SAM is in its startup window           |
| `_sam_run_confirmed_at`  | Timestamp when SAM was last confirmed running (for grace period) |

---

## Idle timer and SAM startup (`idle_and_status_checker`)

Runs every second:

1. Syncs `_sam_is_running` from tmux (`tmux has-session -t SAM`) — skipped while stopping.
2. If SAM is **not** running:
   - Checks if menu is active (`is_in_menu`).
   - If `menuonly=yes` and not in menu → countdown pauses.
   - On timeout: calls `start_sam()` (non-blocking `Popen`), then polls for up to 10 s for
     the SAM tmux session to appear.
   - **Startup window**: any user input during startup is buffered as `_pending_action`.
     Once SAM is confirmed running, the buffered action is replayed. If SAM never started,
     the launch is aborted.

### Menu detection (`is_in_menu`)

Two-phase detection:

- **Boot phase** (before `_boot_complete`): reads `/tmp/CORENAME`. Sets boot complete on
  first non-empty value. Returns `True` only if `CORENAME == "MENU"`.
- **Normal phase**: checks `/proc` for a `MiSTer` process with `menu.rbf` as argument,
  with `/tmp/CORENAME` as a fallback.

---

## Input handling (`handle_action`)

Called from any poller thread via `loop.call_soon_threadsafe`.

1. Always calls `state.update_activity()` — resets the idle timer regardless.
2. Returns immediately if `_is_stopping` is set (prevents double-stop).
3. Sets `_is_stopping = True` (lock).
4. Inside the async coroutine:
   - If SAM is **running**: performs a menu reality check first.
     - If already in menu (zombie session): cleans up and exits.
     - If in a game: dispatches the action.
   - If SAM is **not running** but **starting**: buffers the action as `_pending_action`.
5. Always clears `_is_stopping = False` in `finally`.

### Actions

| Action    | Source                                  | Behaviour while SAM running         |
|-----------|-----------------------------------------|--------------------------------------|
| `"start"` | Button mapped to `"start"` in JSON      | Exit SAM, stay on current game       |
| `"next"`  | Button mapped to `"next"` in JSON       | Skip to next game (Ctrl-C to tmux)   |
| `"exit"`  | Button mapped to `"exit"` in JSON       | Stop SAM, return to menu             |
| `"default"` | Any other button, axis, key, or mouse | Stop SAM, return to menu             |

---

## Joystick polling (`joystick_poller_thread`)

Runs at 50 Hz (every 20 ms, `JOY_POLL_RATE = 0.02`).

- Opens `/dev/input/jsX` non-blocking each poll cycle, reads up to 512 bytes.
- On first read: captures the INIT state snapshot as `previous_events` (baseline).
- On subsequent reads: calls `get_js_activity(prev, current, config)` to detect changes.
- **SAM state reset**: when SAM transitions running → stopped, `previous_events` is cleared.
  This prevents a button held across the stop boundary from re-triggering.
- Uses `stop_event.wait(JOY_POLL_RATE)` so the thread exits immediately on hot-unplug.

### `get_js_activity` — event comparison

Compares previous and current INIT snapshots (delta approach):

- **Button**: fires if a button transitions `0 → 1` (press-down only).
  Maps button number → action via `sam_controllers.json`. Unmapped buttons → `"default"`.
- **Axis**: fires if `|prev_value - current_value| > AXIS_DEADZONE (2000)`.
  Compares axis number + value against the `"next"` axis config; any other axis → `"default"`.

---

## Keyboard polling (`keyboard_poller_thread`)

Blocking read on `/dev/hidrawX`. Any byte received = user input → dispatches `"default"`.
1-second debounce sleep after each trigger.

**Gamepad exclusion**: `get_input_devices` cross-references the `P: Phys` USB parent path
of every keyboard candidate against the joystick list. If the stripped path matches
(e.g. both are `usb-musb.../input*`), the device is excluded. This prevents USB HID
gamepads (which enumerate with a `kbd` handler) from continuously resetting the idle timer.

---

## Mouse polling (`mouse_poller_thread`)

Blocking read on `/dev/input/mice`. Any byte received → `"default"`. 1-second debounce.

---

## Remote log polling (`remote_log_poller_thread`)

Tails `/tmp/remote.log`. Lines containing `"kbd"` → `"default"`.
Handles file rotation (seeks to end on open, re-opens if file disappears).
Active only when `listenkeyboard = yes`.

---

## Hot-plug (`hotplug_monitor_native`)

Uses `inotifywait -m -r /dev/input` watching for `create`/`delete` events under
`/dev/input/by-path/`. On any event, a 2-second debounced rescan is scheduled.

`rescan_devices` diffs the current device set against monitored tasks:
- **Added** device → starts the appropriate poller thread.
- **Removed** device → sets its `stop_event`, cancels its asyncio task.

---

## Stop sequence (`stop_sam` / `exit_to_menu_with_retry`)

1. Runs `MiSTer_SAM_on.sh exit_to_menu` (BGM + tty2oled cleanup).
2. Sends `load_core /media/fat/menu.rbf` to `/dev/MiSTer_cmd` up to 15 times (1 s apart)
   until `is_in_menu()` returns `True`.
3. Calls `kill_sam_processes()` — kills the SAM tmux session and any orphan
   `MiSTer_SAM_on.sh loop_core/start` processes.

For `"start"` action: calls `MiSTer_SAM_on.sh exit_to_game` instead (stays on current game).

---

## Startup

MCP is launched by `mcp_start()` in `MiSTer_SAM_on.sh`:

```bash
tmux new-session -s MCP -d "${mrsampath}/MiSTer_SAM_MCP"
```

The `MiSTer_SAM_MCP` shell wrapper calls:

```bash
exec python3 "${mrsampath}/MiSTer_SAM_MCP.py"
```

To attach for monitoring/debugging:

```bash
m mcp_monitor   # alias for: tmux attach-session -t MCP
```

---

## Files

| Path                                          | Role                              |
|-----------------------------------------------|-----------------------------------|
| `/media/fat/Scripts/.MiSTer_SAM/MiSTer_SAM_MCP.py` | This daemon                 |
| `/media/fat/Scripts/.MiSTer_SAM/MiSTer_SAM_MCP`    | Bash wrapper (exec launcher)|
| `/media/fat/Scripts/MiSTer_SAM.ini`           | User configuration                |
| `/media/fat/Scripts/.MiSTer_SAM/sam_controllers.json` | Controller button maps    |
| `/tmp/CORENAME`                               | Active core name (MiSTer kernel)  |
| `/tmp/remote.log`                             | Virtual/network input events      |
| `/dev/MiSTer_cmd`                             | MiSTer command pipe               |
| `/dev/input/jsX`                             | Joystick devices                  |
| `/dev/hidrawX`                               | HID raw keyboard devices          |
| `/dev/input/mice`                            | Aggregate mouse device            |
