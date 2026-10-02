# MCP input detection and ghost-session fixes

Compared against the upstream [test-branch MCP](https://raw.githubusercontent.com/mrchrisster/MiSTer_SAM/refs/heads/test/.MiSTer_SAM/MiSTer_SAM_MCP.py), fetched on 2026-10-02. The fetched reference is kept under `reference/`.

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

Hotplug notifications observe node changes under `/dev/input`; these also occur for virtual devices. On this MiSTer, `event4` is named `MiSTer virtual input` and is recreated during core changes. This schedules a rescan, but original device discovery excludes virtual inputs. Existing hidraw watchers are tracked to avoid duplicate readers. The inotify child is reaped on shutdown.

SAM's existing owner file now atomically includes `phase` and `launch` alongside `pid` and `start`. The phases are preparing, loading, playing, video and stopping. Publication occurs only at transitions. Optional Monitor/artwork modules and `/tmp/SAM_state`'s format are unchanged.

MCP validates the owner PID and process start ticks, including zombie rejection and correct parsing of parenthesized process names. A game launch must be observed outside Menu before a sustained Menu state can stop it. Two seconds of stable Menu are required; preparation, loading, unavailable CORENAME, and deliberate video playback do not arm this check. Normal-mode external Menu detection works independently of the input switches.

Input during startup cancels and reaps the tracked launcher before owner cleanup. Buffered Next coalesces and is delivered after launch. Next during loading bypasses the menu shutdown branch. Start/Zaparoo preserve the current game; ordinary input returns to Menu. M82 retains its BIOS/game input routing. Targeted shutdown passes expected owner PID/start ticks to the shell cleanup path and rejects a replaced/reused owner.

M82 input routing reads the mode of the current verified SAM owner when input arrives. Changing modes no longer requires restarting MCP; stale state cannot change routing. Original HID/joystick detection is unchanged.

No socket, new command daemon, full artwork dependency, Android change or new user setting was added.

## Validation

`tests/test_mcp.py`: 19 regression tests covering original joystick mapping/batch behavior, original HID reader routing and USB remote discovery, menu transitions, unavailable core state, video's deliberate Menu, valid/dead/zombie/reused ownership, startup cancellation and late starts, duplicate exit bursts, stale owners, M82 routing, disabled joystick with active keyboard/Zaparoo, executor exhaustion, and concurrent hotplug rescans.

`tests/test_shell.py`: 27 tests, including atomic lifecycle publication, old-owner publication rejection targeted shutdown rejection, and zombie/PID-reuse handling while waiting for exit, blocking descendant cancellation, and rejection of incorrect root start ticks. `tests/test_engine.py`: two real event-loop fixtures covering prepared Next, loading bursts, cleanup and external controls. These run against native MiSTer Bash/Python with isolated files and hardware effects replaced.

`tests/live_mcp_verify.py` sends the existing remote-log keyboard and Zaparoo signals. Live checks passed for owner/pane shutdown, kept-game state, external Menu cleanup, and restoration of normal configured SAM. An unchanged snapshot retained sequence 26, advertised all five controls, and returned a fresh timestamp. Normal SAM was restored after testing. Injecting text into the live remote log can race its producer, so this validates the MCP signal path rather than a physical keyboard or actual network-client key press. After restoring original detection, the user confirmed physical remote input keeps M82 games running and activates their play timer. Physical controller testing remains outstanding: this MiSTer currently has no joystick device. M82/video routing was tested with fixtures, not full hardware playback.

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
