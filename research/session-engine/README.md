# Isolated SAM session-engine research prototype

This is a small executable mock of the proposed control/preparation split. It
does not source production SAM, execute MiSTer commands, open input devices,
change volume, install files, or load games. Only known fixture items can reach
`DriverEngine`, which records a mock dispatch and a delayed mock completion.
It is not a production replacement or physical-input/hardware validation.

## Run on Linux

Requires Bash 4.3+ with `/proc`, standard BusyBox-compatible `mkdir`, `rmdir`,
`mv`, `rm`, `mkfifo`, and the existing Linux `flock` utility for admission. There are no new
packages or Python invocations in the engine/CLI. Bash 5's `EPOCHREALTIME`
provides precise timestamps; older Bash falls back to whole-second `SECONDS`,
so use external monotonic timing for benchmarks on such hosts.

```bash
export TMP_ROOT=/tmp/sam-session-research-example
mkdir -m 700 "$TMP_ROOT"
printf '%s\n' SAM_SESSION_RESEARCH_V1 > "$TMP_ROOT/RESEARCH_MOCK_ONLY"
bash research/session-engine/engine.sh normal 3 2 > "$TMP_ROOT/engine.log" 2>&1 &
bash research/session-engine/command.sh start
bash research/session-engine/command.sh status
bash research/session-engine/command.sh next
bash research/session-engine/command.sh stop
bash research/session-engine/command.sh shutdown
```

`TMP_ROOT` is mandatory and must be an existing, non-symlink directory named
`/tmp/sam-session-research-` plus letters, digits, underscores, or hyphens. The
marker is required for both executables. Use a new private directory per run.
The engine refuses an existing owner lock or clock FIFO; it never takes over a
stale fixture. Do not populate its internal paths with symlinks. All paths live
inside that fixture. `/tmp` is the RAM-mailbox location on MiSTer; on other hosts
verify its mount type before making a RAM-specific performance claim.

Engine arguments are `mode prep_delay_seconds mock_launch_delay_seconds`.
Modes are exactly `normal`, `m82`, or `commercial`; delays are 0–30 whole seconds
with up to three fractional digits (30 may have only zero fractional digits).
Defaults are normal, 3, and 0. `PLAY_SECONDS=0` selects indefinite playing;
otherwise an optional 0–999999 literal integer overrides the mode play timer.
No command string or fixture path is an argument. Timers are declarative policy
and exercised with the `timer` command; this prototype does not schedule elapsed
demo/play expirations itself.

The first candidate is prepared immediately; the single worker then waits the
injected preparation delay before each subsequent fixture candidate. The ready
queue holds at most two records. This permits comparison of start-to-first-ready
with the much later full future queue during 3/20-second preparation, while the
owner stays responsive during a 2-second delayed mock launch. One persistent
worker performs at most one preparation operation. It never dispatches anything.

The owner polls every roughly 50 ms using Bash `read -t` on a private FIFO opened
read/write. The FIFO is only a clock/wait primitive; **commands do not travel
through it**. It cannot return immediate EOF and cause an idle busy-spin. Normal
idle turns use Bash builtins without process forks. State publication, command
claim cleanup, and atomic worker publication use small filesystem utilities.
Standby with no jobs, open UI, or cleanup uses only one inbox glob and the timed
read. Claimed requests are unlinked once per turn, rather than for each command.

## Commands and acknowledgements

The CLI returns one request ID on stdout and exits after atomic admission. It
does not wait for acknowledgement. Read `receipts/ID.accepted` and then
`receipts/ID.applied`. Each is one TSV row:

```text
timestamp<TAB>ok|rejected<TAB>detail
```

Receipts are written once by a single builtin `printf`. Readers must validate a
complete newline-terminated three-field row; file existence alone is insufficient
because creation can be observed before the write completes. Retry an incomplete
read. This avoids two rename processes for every accepted/applied acknowledgement.

Acceptance means the owner parsed and authenticated the request. Application
means the policy/state action happened. Neither acknowledges hardware. For
`start`, applied `preparing` precedes first ready and mock presentation. For
`next`, applied contains the selected ID once a candidate is dispatched; a Stop
instead resolves outstanding Next receipts as `rejected canceled_by_stop`.
Only 32 outstanding coalesced Next receipts are retained. Requests beyond that
receive `pending_next_full` without adding memory or preparation jobs.

| Command | Arguments | Effect |
| --- | --- | --- |
| `start` | none | Starts fixture programme; active start is idempotent |
| `next` | none | Coalesces into one pending advance |
| `stop` | none | Invalidates generation, cancels dispatch, records Menu intent |
| `shutdown` | none | Stop, then owner exits and removes its own lock/owner |
| `status` | none | Acknowledges current phase |
| `launch` | current selection ID | Rejects stale selections; mock redispatch only |
| `input` | none | Injects a **mock policy event**, never physical input |
| `timer` | none | Injects a mock timer event; indefinite playing ignores it |
| `menu-observed` | none | Records mock Menu observation, then stops session |
| `ui-open` | lease owner-PID owner-start-ticks | Immediately records UI visibility; pause follows asynchronously |
| `ui-close` | exact lease | Closes/resumes only the matching lease |

For a UI fixture, obtain the live UI process's start ticks from field 22 of
`/proc/PID/stat` (split after its final `) `, then index 19). Keep that process
alive while its UI lease is open. A dead client is rejected, and a client that
dies later has its lease canceled by the owner. `ui-open` publishes visibility
without waiting for preparation or launch. Normal mode applies its exact pause
lease on a following owner turn; M82/commercial declare continue policy. A
close-before-pause cancels the lease, and an old close cannot resume a replacement
lease. Lease IDs must be unique per UI opening. The owner remembers the latest
32 closed IDs so even a close claimed before its queued open prevents a stranded
pause (`ui-open` then receives `closed_lease`). Pause only gates new selections
here; it cannot suspend physical hardware.

The mailbox admits at most 32 requests plus one emergency Stop/Shutdown slot.
Writers hold kernel-released locks only for admission; SIGKILL of a writer cannot
strand a lock. Urgent admission uses its own lock and bypasses ordinary admission.
CLI exit 75 means busy
or full; exit 64 means invalid input/fixture; exit 69 means unavailable owner.
Stop/Shutdown files are claimed before regular commands. Stop supersedes
start/next/launch/input/timer already queued in that claim turn. UI and status
commands can still apply. The owner processes at most 32 claims per turn.

Internal request records, written to `inbox/control.ID.req` or
`inbox/urgent.ID.req`, contain exactly nine bounded literal TSV fields:

```text
ID<TAB>engine-PID<TAB>engine-start-ticks<TAB>session-token<TAB>expected-epoch<TAB>action<TAB>arg1<TAB>arg2<TAB>arg3
```

Absent arguments are `-`. IDs/arguments use constrained ASCII characters and
requests are limited to 512 characters. Nonregular files, FIFOs, and symlinks are
rejected before opening request paths, so malformed inbox entries cannot block
the control loop. This is a guard inside a private trusted fixture, not a hostile
shared-directory security boundary; callers must not mutate paths concurrently
with the owner. The owner identity plus a fresh random
runtime session token and expected epoch are required on every request. `owner`
contains PID, start ticks, token, and epoch in one atomic TSV snapshot. The CLI
captures that snapshot; old owner tokens/start ticks and old epochs are rejected.
The token identifies this owner lifetime; `session_epoch` increments on start/
stop to invalidate queued requests, worker results, and selection IDs within
that lifetime. A command concurrent with Start/Stop can therefore receive
`stale_epoch`; the caller can reread the current owner before intentionally
resubmitting. Data is never evaluated or sourced. Only the engine's fixed
`worker.sh` implementation is sourced; mode TSV is read as data.

## State, events, and mode contract

`state.tsv` is an atomic snapshot of key/value TSV rows. Its keys are:
`engine_pid`, `engine_start`, `session_token`, `session_epoch`, `mode`, `active`,
`phase`, `selection`, `ready_count`, `ui_open`, `ui_lease`, `paused`, `input_role`,
`demo_timer`, `play_timer`, `worker_pid`, `worker_start`, `launch_pid`,
`launch_start`, `cleanup_blocked`. Phase is standby, preparing, dispatching, bios,
demonstration, commercial, playing, stopped, stopping, or failed. A selection is
`epoch:index`; `-` means none. An empty/no-eligible-item descriptor rejects Start
and records `preparation_failed`; a worker exiting without its initial candidate
also produces a bounded failure outcome instead of indefinite preparing.

`events.tsv` is append-only, with five columns:

```text
timestamp<TAB>event<TAB>session_epoch<TAB>selection<TAB>detail
```

Useful events are `engine_ready`, `accepted` (ID:action), `session_started`,
`first_ready` (kind:core:title for each newly selected item), `mock_dispatch`,
`mock_launch_applied`, `next_coalesced`, `mock_input`, `mock_timer`, `play_entered`,
`ui_visible`, `ui_pause_applied`, `ui_closed`, `ui_client_gone`,
`sim_menu_intent`, `sim_menu_observed`, `cleanup_signaled`, `cleanup_reaped`,
`command_rejected`, and `launch_result_rejected`. Compare timestamps of accepted
and applied receipts for policy responsiveness; measure CLI invocation-to-receipt
externally to include CLI startup and mailbox polling. `first_ready` establishes
selection readiness, while `mock_launch_applied` establishes mock presentation.

Mode TSV uses `policy key value` and `item kind core title` rows. Policy describes
core restrictions, demonstration/play duration, input decisions for transition/demo/play,
and UI pause/continue behavior. Items are trusted, fixed `Fixture_*` constants.
Transition covers preparation and dispatch. Policy actions must be exactly
ignore, stop, play, or advance; missing/unknown actions fail before owner admission.
The owner builds a named `dispatch_plan` array, validates its epoch/token/
selection, and passes that array name to `DriverEngine`. It dispatches no shell
payload. `mode_decision` receives an explicit event and phase context and returns
one of ignore, stop, play, or advance through a bounded builtin-only callback.
There is no scanning, downloading, arbitrary callback, or blocking mode hook.

| Mode | First presentations | Demo/play policy | Core/input/UI policy |
| --- | --- | --- | --- |
| normal | NES game, SNES game, Genesis game | 120 / indefinite | allowed cores declared; transition/demo/play input stops; UI pauses selection |
| m82 | NES BIOS, game 1, BIOS, game 2 | 21 / 300 | NES only; transition/BIOS ignores input, demo enters play, playing ignores; UI continues |
| commercial | NES clip, NES game, SNES clip, SNES game | 30 / 300 | NES/SNES; transition/demo/commercial/play input stops; Next/Timer advances; UI continues |

The fixtures intentionally omit production random selection, real BIOS runtime,
clip playback, audio ownership, filters, actual readiness observers, and physical
reader lifecycle. They demonstrate a programme contract and event routing only.

## Cancellation scope

Preparation and delayed mock dispatch run in separate private Bash process
groups. Children stop at a registration barrier until the owner records PID,
start ticks, process group, and session ID. Signals require all identity fields
to match; unrelated processes are never targeted. A dead leader with remaining
group members is treated as unproven ownership. Jobs contain timed builtin
waits and brief filesystem publications, without persistent descendants. Stop
invalidates the epoch before canceling the dispatch group; no completion from
that generation can subsequently apply. Unproven dispatch cancellation withholds
Menu intent, retains the job identity, sets stopping/cleanup_blocked, and rejects
the Stop receipt. Unproven preparation cancellation blocks further admission of
Start/Next/launch/input/timer; UI/status and a retry of Stop remain available.
With proven dispatch cancellation it publishes `sim_menu_intent` before
preparation cancellation/reaping, so a slow worker cannot hold up Menu intent.
Child reaping is observed asynchronously during ordinary turns.
For a normal completed mock launch, the fixed dispatch function joins its children
then atomically publishes an epoch/token/selection/PID/start/group/session proof
marker. A matching marker plus an already-dead leader permits reaping without a
full `/proc` group scan. Missing or mismatched proof retains the conservative
scan and refusal behavior. The marker proves only this mock function's completion.

`sim_menu_intent` is an intent/state boundary; `menu-observed` is a separately
injected mock observer event. Neither proves MiSTer Main received a command or
displayed Menu. General arbitrary-process-tree cleanup, robust abandoned-owner
recovery, and physical pause semantics remain production research work.

## Python owner comparison

`python_owner.py` is an alternative research owner using only the Python 3.9
standard library. It replaces the Bash owner in a separate private fixture;
it does not add another daemon or change production SAM. The shared `command.sh`,
mode TSV files, owner/request/receipt/event formats, state keys, UI leases,
input/timer decisions, bounded queues, and mock-only limits remain the same.

```bash
export TMP_ROOT=/tmp/sam-session-research-python-example
mkdir -m 700 "$TMP_ROOT"
printf '%s\n' SAM_SESSION_RESEARCH_V1 > "$TMP_ROOT/RESEARCH_MOCK_ONLY"
python3 research/session-engine/python_owner.py normal 20 2 > "$TMP_ROOT/engine.log" 2>&1 &
bash research/session-engine/command.sh start
bash research/session-engine/command.sh stop
bash research/session-engine/command.sh shutdown
```

Use the same three positional arguments and optional `PLAY_SECONDS`. A fresh
directory is mandatory when switching owners. The Python owner validates mode
policy before admission, then uses `os.replace`/`os.unlink` for mailbox and state
operations without launching a shell process per command. Its active loop sleeps
20 ms; idle standby uses one inbox listing and a 50 ms sleep. Its private clock
does not require a FIFO. It still uses the shared Bash CLI so CLI startup/admission
cost is directly comparable. Measure a warm producer separately to identify the
owner's control-loop contribution to latency.

The three roles are the owner, one preparation worker, and an optional delayed
mock dispatch job. `RESEARCH_CHILD_START=fork` is the default comparison: this
single-threaded owner forks a fixed internal function, closes the inherited event
stream, resets signals, redirects stdin, and calls `setsid` before registration.
It does not restart an interpreter or add a process. Nonblocking `waitpid` observes
cleanup. This is a bounded research experiment, not a general fork framework for
production's threaded services.

`RESEARCH_CHILD_START=exec` reproduces the earlier comparison using
`Popen(start_new_session=True)` and fixed `--worker`/`--launch` functions in
this same source, with Python `-S` to skip site initialization. Those internal
roles are not a public command API. Invalid child-start values fail before owner
admission. Both variants create a private process group/session and use the same
registration gate. Before publishing that gate, the owner captures and
checks PID/start/group/session/parent. A child must match the exact gate and live
owner PID/start/token/epoch before publishing any fixture data. It cannot execute
an arbitrary command or write hardware. Stop invalidates a private session record
before cancellation and rejects later results from that epoch.

Cancellation signals require the original PID/start/group/session/parent tuple.
Ownership or signal failure retains the job, withholds Menu intent for an
unproven dispatch, and blocks further session mutations. A dead leader without
its matching completion proof triggers the conservative `/proc` group check.
The fixed launch role has no children and atomically publishes completion proof
after finishing its mock writes; cleanup observation uses nonblocking `poll`.
Regular-file checks, `O_NONBLOCK`, `O_NOFOLLOW`, bounded reads, and descriptor
kind validation protect mailbox reads from FIFO/symlink blockage. The private
directory is still the trust boundary.

This comparison does not choose a production language. Native measurements must
include cold owner start, first ready/presentation, warm command responsiveness,
CLI overhead, idle CPU, and child cleanup. Compare fork/exec explicitly: Python
interpreter startup is part of the exec variant's first-ready latency and must
not be hidden. Neither alternative proves physical input,
MiSTer command delivery, core readiness, or Menu display.
