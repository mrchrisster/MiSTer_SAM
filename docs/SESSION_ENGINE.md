# Resident session engine

The `test` branch starts `sam/session_engine.py` directly in SAM's tmux pane.
Its PID/start pair remains the public owner identity. One persistent Bash adapter
loads existing trusted INI configuration and platform/module functions once.
Normal, roulette, M82 and commercial modes share the Python progression loop.
The research fixture implementation is kept under `research/`; it is never
installed or used for real ROM selection.

## Responsibilities

```text
CLI/menu/Monitor ----> authenticated command gateway
MCP physical input -> authenticated command gateway
                               |
                     Python session owner
                      | fixed operations
                  persistent Bash adapter
                      |             |
             one preparation job    existing hardware/resource services
```

The adapter is a platform compatibility component of the session, not another
public owner or broker. It adds one resident process while existing Bash services
are retained. Python handles command admission, priority and progression; the
adapter retains timer/mode state, protected launches and resource ownership.
It does not repeatedly start an interpreter to consume button/control commands.

Normal/roulette preparation continues to use at most two ready records and one
owned worker. Existing filters, archive paths, artwork validation, history commit
and storage selection remain in that worker/launch boundary. M82 and video retain
their existing one-step selectors; their separate infinite loops are bypassed.
Mode timers are split into begin/tick/key functions in `lib/engine-modes.sh`.
Video download/player work now uses a registered private launch group, canceled
before the next presentation. Existing module hooks remain active.

## Fixed adapter protocol

Only the verified immediate Python parent can start `--engine-adapter`. Its
PID/start and exact engine script argument must match. Standard output becomes
the private reply pipe; ordinary messages stay in the SAM pane through stderr.
Neither protocol carries a ROM path or arbitrary shell code.

Owner request: `sequence<TAB>operation<TAB>argument`.
Reply: `sequence<TAB>code<TAB>mode<TAB>phase<TAB>timer<TAB>paused<TAB>remaining<TAB>action`.
An initial `ready` reply follows session setup. Operations are boundary, prepare,
take, launch, timer_begin, timer_tick, key, control and cleanup. Code 1 is a pending
selection or accepted Next/Previous transition as appropriate; fatal preparation/
launch errors differ from rejected, nonfatal user commands.

The owner permits one outstanding adapter operation. It continues reading urgent
requests while the adapter is loading. Ordinary input is bounded and revalidated
before dispatch; expired or old-launch requests fail explicitly. Terminal Next/
Previous bursts coalesce, and keyboard/command queues are capped at 256.

## Stop and cleanup

Stop/exit-to-Menu use a priority RAM request. The owner signals only the adapter
with its captured PID/start identity. USR1 requests Menu; ordinary TERM retains
the existing external teardown contract. USR1 and TERM during child registration
are deferred until job PID/start/group/session identity has been recorded.

The adapter captures the existing Main/FIFO/marker context and binds the pending
Menu audio receipt to this owner. It cancels real launch writers and publishes
the launch-quiescence barrier before requesting Menu. Preparation and optional
service cleanup may continue while Menu loads. Audio restoration still requires
the separate completion receipt and fresh Menu transport observations.

Only this verified adapter, after successful own cleanup, may finish Menu while
its Python parent remains alive. This keeps replacement admission closed until
completion. Applied Stop receipts live in bounded RAM storage outside removed
session scratch. Acceptance alone is not success; cleanup failures propagate.

Linux parent-death notification signals the adapter if the owner crashes. The
registered adapter identity prevents a replacement from starting while old
cleanup is still running. Existing cleanup-failure evidence remains authoritative.
Power-loss and Main command-delivery limitations still apply; guards are retained.

## Configuration and rollback

No INI migration or extra engine option is needed. Existing settings and mode
changes retain their current next-game boundary behavior. Ordinary manual MiSTer
launching is unchanged.

Install/update from `test` normally, then use `MiSTer_SAM_on.sh start`.
For a temporary legacy comparison session:

```sh
MiSTer_SAM_on.sh stop
SAM_ENGINE=legacy MiSTer_SAM_on.sh start
```

The launcher carries this override into the tmux pane. A subsequent ordinary
Start selects Python again. To revert the release, reinstall the previous tested
revision. Update backs up only `MiSTer_SAM.ini`; custom settings/lists remain intact.

## Validation scope

Focused fixtures cover the real picker with mocked hardware, public pause/play,
Next bursts, invalid adapter parents, urgent Stop during owned loading, parent
SIGKILL, bounded queues, stale requests, failed audio activation, M82 BIOS/game/
play/indefinite timing, video synchronization and private video cancellation.
They also cover signal cleanup while the adapter is blocked on protocol input.
Native and actual-game results are recorded in the [changelog](CHANGELOG.md).
Research's 37 ms simulated Menu intent is not a production button-to-Menu claim.

The actual normal-mode smoke run passed Pause/Resume/Next and Stop, served matching
Monitor artwork, and preserved saved settings/Volume.dat. Initial Start took
17.804 seconds to controls-ready; its selection/artwork/setup path still needs
optimization. A separate Menu marker appeared at 1.073 seconds and completion at
4.231 seconds. Neither is physical input-to-visible-display validation.
