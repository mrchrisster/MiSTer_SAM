# SAM architecture and migration

Normal and roulette sessions use one foreground Bash loop for decisions, timing
and hardware ownership. The experimental Python timer/pipe bridge was removed
after native measurements showed additional CPU and memory cost. MCP retains
its existing Python input service and shared command/ownership components.
M82 and video retain their specialized compatibility loops.

## Runtime responsibilities

| Component | Responsibility | Must not do |
| --- | --- | --- |
| `sam/coordinator.py` | Input action policy, startup cancellation, current-session decisions | Read devices, scan ROMs, write hardware commands |
| `sam/session.py` | Immutable verified PID/start/phase/launch snapshot | Infer liveness from a tmux name or stale display state |
| `sam/commands.py` | Shared local command routing and owner-bound dispatch | Rebind a stale input to a replacement session |
| `MiSTer_SAM_MCP.py` | Existing resident input/idle service and platform wiring | Implement a separate Menu/audio exit sequence |
| `lib/session.sh` | Foreground admission, phase transitions, launch serial, cleanup | Admit two live owners or let a worker publish lifecycle state |
| `lib/engine.sh` | Normal/roulette progression, countdown, at most two prepared candidates, launch validation | Let speculative preparation consume history or load a core |
| `lib/lifecycle.sh` | Existing start/stop, Menu confirmation, audio restoration | Tear down an unverified tmux session by name |
| `lib/catalog*.sh`, `lib/policy.sh`, `lib/filter.sh` | Discovery, candidate restrictions and selection | Change the running core during preparation |
| `lib/launch.sh` | MiSTer launch adapters and owned BIOS-skip jobs | Dispatch after session ownership has been lost |
| `modules/` | Optional modes/services behind the current hook API | Run work when disabled or bypass ownership |
| `control/` | Existing Monitor request/ack/journal bridge and `SAM_state` | Execute caller-supplied shell content |
| `lib/menu.sh`, `MiSTer_SAM_menu.sh` | Menus and configuration presentation | Delete shared ownership state to change a preset |

The installed layout now includes:

```text
Scripts/
  MiSTer_SAM_on.sh              compatibility command entry
  MiSTer_SAM_install.py         release validation and installation
  MiSTer_SAM.ini                existing user options
  .MiSTer_SAM/
    samctl.py                  thin local CLI
    sam/
      commands.py              common local gateway
      coordinator.py           lifecycle decisions with injected dependencies
      session.py               immutable verified owner snapshots
    MiSTer_SAM_MCP.py           existing input/idle service
    lib/session.sh             foreground ownership and transition implementation
    lib/engine.sh              prepared selection, countdown and progression
    lib/lifecycle.sh           single Menu/audio stop implementation
    lib/launch.sh              existing MiSTer adapters
    modules/                   optional implementations
    modules.d/                 literal manifests
    control/                   Monitor-compatible transport
```

## Commands and ownership

CLI and menu commands enter `sam.commands.CommandGateway`; MCP calls the same
class in process. The gateway invokes known Bash operations using the internal
`--gateway-backend` entry, avoiding recursive public dispatch. Single-core
commands such as `m amiga` still resolve through the existing core table and
start validation. Bare `m ignore` retains its exclusion-only behavior; the
acknowledged `control ignore` operation excludes and advances.

Next, Previous, Mute and M82 play verify the owner PID/start and find its exact
pane ID in the exact `SAM` session. They revalidate before dispatch. A missing,
dead, reused, or replaced owner causes rejection rather than a command to a new
pane. Tmux queries and key dispatch have two-second timeouts. Stop captures the
old session ID, pane PID and tmux server PID; any residual pane teardown uses
an atomic tmux predicate so even a restarted server cannot redirect the command.

Start admission uses a separate RAM `session-start.lock`. MCP requests an
automatic start only if idle; under the same lock it preserves a live owner or
an occupied exact `SAM` pane whose owner record is still being initialized.
Manual starts retain explicit replacement behavior. The lock releases before
single-core startup feedback and cannot be retained by spawned processes.

Stop and unmute commands bind to the observed owner. A `0 0` internal sentinel
means the gateway observed no live owner; the backend must reject a session that
appeared in the meantime. It is not a user configuration setting. Unmute holds
the transition lock during bounded audio restoration. The Monitor request schema,
UUID replay behavior, and plain `SAM_state` format remain compatible.

One foreground Bash process still owns each game session. `sam_session_begin`
uses a bounded `flock` on a stable RAM file to reject another live owner; a dead
PID or mismatched start time does not block recovery. Normal, M82 and video loops
use the same admission and cleanup component. A failed start does not receive
permission to clean up another session's resources.

## State and cancellation

```text
no live owner -> preparing -> loading -> playing
                    ^           |          |
                    +-----------+----------+

preparing -> video -> preparing
any active phase -> stopping -> no live owner
```

The compatibility record stays `pid`, `start`, `phase`, `launch`. `loading`
increments the launch serial. Repeated unchanged phases avoid a write; repeated
loading denotes another launch attempt. Transition errors propagate before a
hardware launch. A stopped session cannot return to playing. A worker can publish
a prepared record only while its original session is alive and current, under
the same short publication lock.

Startup cancellation first joins the tracked launcher, then reads the current
owner. This prevents a late launch after cleanup. Ordinary Stop cancels owned
work while retaining mute, loads Menu, checks its marker every 100 ms, and only
then restores audio. Failed Menu loading leaves audio muted and reports failure.
The coordinator and CLI use this same backend.

External stop finalization rechecks the captured owner while holding the
admission lock, including display shutdown and the Menu/audio sequence. A new
start cannot slip between the check and those effects. Lock acquisition is
bounded to two seconds and reports a busy/unavailable transition rather than
waiting indefinitely.
External finalization explicitly releases the lock before closing its descriptor,
so background teardown helpers cannot retain it. Ordinary phase transitions
still use builtin descriptor closure without an extra unlock process.

Cleanup cancels private work, marks stopping, releases its transition lock, then
runs module cleanup in the foreground so shell job ownership and callback state
remain available. The live stopping PID prevents replacement admission during
cleanup. Locks support cleanup after TERM interrupts a transition; repeated
cleanup is harmless. Ownership lock files must never be unlinked while SAM runs.
Preparation fork/registration briefly defers TERM until the parent has captured
the worker PID/start identity, then honors the pending stop before continuing.
Cleanup cannot miss a child created in that window. Private preparation and
delayed-launch groups now register PID/start, process-group and session IDs
before the stopped child is released. Cancellation retains a verified leader
while terminating the group, including late forks; failed cleanup retains RAM
evidence and blocks admission. No timer-tick work is added.

For Menu exits, cancelled launch jobs and completed critical stop hooks publish
an owner-tagged quiescence marker. The external stop can request Menu while the
same owner finishes optional housekeeping. The owner still blocks replacement;
audio restoration requires its exit and fresh Main/FIFO readiness. OLED shutdown
joins its own bounded helpers. See [owned job cleanup](OWNED_JOB_CLEANUP_2026-10-09.md)
and [response results](RESPONSE_2026-10-09.md).

## Adding behavior

Use the existing [module API](MODULE_API.md) for an optional service or mode.
Core restrictions belong in `core_allowed`, list restrictions in
`candidate_filter`, and expensive candidate work in `candidate_prepare`.
Preparation may propose a game; only the foreground engine commits and launches.
Use `session_stop` to release owned resources. Modes can retain their established
ordering through service bindings during this migration.

A new local control belongs in the gateway's explicit command contract, with
tests for stale owners and its valid phases. A new input source emits semantic
actions to the coordinator; it does not write to `/dev/MiSTer_cmd`. A new system
layout belongs in a launch/catalog adapter, not in the input or menu code.

## Resources and compatibility

Normal/roulette adds no persistent timer process or internal pipe protocol.
The foreground shell calls module hooks directly and uses a builtin 100 ms input
wait. Preparation is checked at most once per second and stops spawning workers
when the small ready queue is full and discovery is complete. Expensive catalogue
and artwork work remains outside the timer path. Zero duration means indefinitely
until an action; pause/resume uses the shell timer's whole-second precision.

Idle timer ticks use builtins and do not write status/catalogue files to SD.
Headless EOF uses a bounded sleep to avoid a busy loop. Readers retain their
existing 20 ms joystick snapshots. Runtime records stay in RAM; the Monitor
command journal remains persistent for UUID replay. Python is invoked for an
actual pending Monitor command, not on each idle tick.

Release validation checks the retained MCP coordination package before stopping
SAM or modifying installation files. Installation still
backs up only the INI and preserves ROMs, custom maps, plugins and Ignore lists.

## Remaining migration

Module boundaries are function/hook contracts, not process boundaries. Bash owns
normal/roulette sequencing, bounded preparation, catalogue policy, launch and
commit. Reader/mapping code remains in MCP. Prepared records carry the original
location, owner/revision, artwork and Amiga adapter data. The launch resolver
preserves FAT/USB paths and title-only Amiga selection.

M82 requires a foreground sequence adapter preserving BIOS versus game behavior
and its one-time play extension. Video also needs explicit asynchronous playback
ready/failure events and foreground authorization of worker hardware operations.
Those modes retain existing loops. Further unification should use direct shell
contracts and demonstrate no steady-state resource regression. Release-wide atomic switching also
remains future work; the installer uses per-file atomic replacement.

## Validation

See `RESPONSE_2026-10-09.md` for current test results, installation and rollback.
`LEAN_RUNTIME_2026-10-09.md` records the preceding lean-runtime stage.
`PHASE2_2026-10-09.md` records the superseded Python bridge experiment;
`REFACTOR_2026-10-09.md` records the preceding stage.
Unit fixtures exercise injected dependencies; native integration fixtures use
private state directories and mocked MiSTer hardware operations. Dedicated tmux
tests use UUID-named private servers and never target the production server.
