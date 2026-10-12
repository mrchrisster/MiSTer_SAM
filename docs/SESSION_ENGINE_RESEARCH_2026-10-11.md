# Session engine research — 2026-10-11

This is an executable architecture experiment, not an installed SAM replacement.
This report records the research stage before integration. The subsequent
production backend on `test` is documented in [SESSION_ENGINE.md](SESSION_ENGINE.md).
At that research stage, production scripts, ROMs, saved settings and the running
SAM session were unchanged.
The [functional overview](SAM_FUNCTIONAL_OVERVIEW.md) describes the current system.
The [prototype](../research/session-engine/README.md) documents the runnable experiment.

## Boundaries to keep

Use one session owner, one preparation worker, and the existing MCP. A launch
operation may use one short, explicitly owned job; it is not a second session
engine. Keep the CLI and menu independent of preparation and session setup.

- **Owner:** accept commands, resolve policy, hold phase/timer/selection state,
  validate generations, and authorize hardware effects. It must not scan ROMs,
  download artwork, hash CHDs, wait for full cleanup or run arbitrary module hooks.
- **Preparation worker:** find ROMs, apply deduplication then filters, resolve
  paths/artwork, prepare launch plans, and replenish at most two ready items.
- **MCP:** retain physical device discovery, mappings and snapshot readers.
  Report input to the owner using the current phase policy. Do not start helpers
  or load metadata for each button press.
- **CLI/menu:** publish bounded requests and display acceptance separately from
  completion. Show the menu immediately; a pending pause need not block rendering.

The research compares Bash and Python 3.9 owners with the same protocol. The
Python version replaces the Bash owner; it does not introduce another daemon or
broker. Python 3.9.6 is available on the tested ARMv7 MiSTer.

## Main command delivery is a separate problem

The local upstream Main source at commit
`47221c18987e101f50caafeb3b615f53b62722ca` shows that Main reads a buffer of at most
1023 bytes from its command FIFO as one command. It removes one final newline;
it does not split several lines into several commands. Separate writes can
therefore coalesce. During a core load Main restarts and recreates the FIFO;
successful writes into the previous FIFO do not prove execution by the next Main.
See the [pinned source and binary research](COMMAND_DELIVERY_RESEARCH_2026-10-09.md),
[Menu ordering](MENU_RETURN_2026-10-10.md) and
[owned-job cleanup](OWNED_JOB_CLEANUP_2026-10-09.md). The inspected device binary
is `$VER:260912`, SHA-256
`9f6e5a237c36be6404ab4823d804821491db4bf125827f84aca2a1ca31f0a8a6`.

Private Linux FIFO fixtures reproduce both mechanisms. They never write to
`/dev/MiSTer_cmd`. On the real device, the current core marker timestamp preceded
the command FIFO timestamp by about 38 ms. Opening the FIFO nonblocking and
closing it without writing verified the presence of a reader at observation
time, not command parsing or FPGA/game readiness.

Keep three acknowledgements distinct:

1. SAM accepted the request for the exact owner and session generation.
2. The driver delivered an effect to the correct Main incarnation/transport.
3. An observer confirmed the expected state where that state is observable.

For a core transition, observe expected core plus a fresh Main PID/start identity,
FIFO identity, marker observation and reader availability. A core name alone is
insufficient, including when reloading the same core. These signals establish a
transport opportunity; they cannot confirm a game finished booting or that live
volume was applied. Preserve the existing Menu barrier and separate audio receipt.
Retry only bounded, idempotent desired states such as return-to-Menu or set-mute;
do not blindly retry navigation, toggles or a game load.

## First game without a full preparation pass

A startup seed must be a previously validated, owner-independent launch template.
Revalidate its effective selection-policy fingerprint, allowed core, ROM/container
stamp, artwork evidence and preparation/module/index versions before rebinding it
to the new session. A per-session counter such as `revision=1` cannot establish
cross-session cache validity. A ZIP member needs the containing archive identity
as well as member metadata; a filename match is not eligibility evidence.

Use the first valid seed immediately and replenish in the background. If none is
valid, prepare one eligible item first, then continue. Avoid rebuilding every
system before launching. Existing cached first-line reads on the device took
approximately 0.4–0.7 ms; this is only a read measurement, not proof of complete
seed validation, artwork decoding or game launch speed.

The prototype's first fixture candidate is deliberately immediate, while later
preparation can sleep for 20 seconds. Real selection, artwork matching and seed
invalidation are not integrated. `seed_contract.py` tests supplied evidence and
file stamps; it is not a new catalogue implementation.

## Module contract

Modes supply data and bounded decisions to the same engine: allowed cores,
programme item kinds, demonstration/play timer values, input action per phase,
UI pause policy, and eventual audio requirements. Expensive module work belongs
in preparation. Do not allow arbitrary shell hooks to execute inside the owner.

Resolve one effective policy before preparation. Permit one programme provider,
combine independent core restrictions by intersection, and apply explicit mode
overrides before calculating the eligibility fingerprint. For example, BGM's
incompatible-core exclusions must remain effective regardless of who supplied
the initial core list. An empty intersection needs a named reason, not another
random retry. Define conflicts explicitly instead of making module load order
decide behavior. Apply a requested mode change at the next game boundary, as
selected for SAM; simple live settings can have narrower revision scopes.

The fixtures exercise normal game rotation, M82 BIOS/game sequencing and
commercial clip/game sequencing. M82 input during BIOS/loading is ignored;
demo input enters play; gameplay input does not stop it; observed Menu ends the
session. This needs phase routing, not disabling every physical reader. Normal
mode input during loading must still cancel and request Menu.

Programme items carry a selection identity and a typed launch plan. The driver
accepts only the current selection/generation. Commercial video and M82 do not
get their own competing launch loops. Real countdown deadlines, playback, BIOS
actions and audio leases remain to be connected; prototype timer events are
manually injected policy events.

## Race and cleanup rules exercised

- Owner PID/start/token plus session epoch accompany every request. Old-session
  Start, Next and launch completions cannot revive a stopped/restarted session.
- Stop has its own urgent admission path and is processed before ordinary work.
  Ordinary admission has a bounded queue and kernel-released lock.
- Preparation and dispatch use private groups with captured PID/start/group/session
  identities. They cannot publish until their registration gate is valid.
- Failed dispatch cancellation withholds simulated Menu intent and leaves an
  explicit stopping/cleanup-blocked state. Identity failure must not be treated
  as successful cleanup. A later proven Stop can recover.
- Once dispatch is safely canceled, Menu intent precedes worker cleanup/reaping.
  This demonstrates ordering, not real Main acceptance or permission to restore
  volume before Menu is ready.
- UI leases include exact client PID/start identity. Old closes, dead clients and
  close-before-open batches cannot strand a pause or release a newer lease.
- Request records are bounded literal data. FIFO, symlink, malformed and shell-like
  payloads cannot block the reader or execute as commands.
- Empty preparation reports failure instead of silently launching or retrying
  forever. State and requests live under a private RAM fixture directory.

This does not yet prove recovery from power loss, arbitrary module descendants,
abandoned owners, production bind mounts or BGM ownership. Those need the existing
resource ledger and completion receipts integrated before a replacement is safe.
In particular, successfully signaling a mock job is not proof a real command
writer has quiesced. Epoch checks can reject a late result but cannot retract a
hardware write already issued. The production driver must establish writer
quiescence and handle Main restart before authorizing the Menu transition.

## Measurements and validation

Five interleaved trials per variant ran on the actual ARMv7 MiSTer, with all
launches and input events mocked. Each Start used an immediately available fixture
candidate, a 20-second delay before further preparation and a two-second simulated
launch job. The producer was an already running Python fixture; these numbers
exclude CLI startup, physical input polling and hardware loading. Medians:

| Measurement | Bash owner | Python owner, fixed worker fork |
| --- | ---: | ---: |
| Cold owner initialization | 236 ms | 804 ms |
| Warm Start to first mock dispatch | 286 ms | 113 ms |
| UI-open applied receipt | 161 ms | 54 ms |
| UI-close applied receipt | 168 ms | 28 ms |
| Stop to simulated Menu intent | 158 ms | 37 ms |
| Stop applied receipt | 236 ms | 44 ms |
| Standby owner CPU, five-second sample | 1.60% | 0.60% |

The earlier Python version launched a fresh interpreter for each worker, including
with `-S`: first mock dispatch had a 1056 ms median, while Stop intent was 33 ms.
Replacing that child startup with a fixed-function fork of the single-threaded
owner reduced first dispatch to 113 ms. Fork is an isolated comparison; do not
fork the existing threaded MCP or permit arbitrary module callbacks in children.

The warmed Python owner meets the research targets of 100 ms for control/Stop
intent and 500 ms for cached first dispatch. Cold startup does **not**: the paired
median of initialization plus warm first dispatch was approximately 922 ms,
excluding CLI overhead. Do not gate menu rendering on cold owner initialization.
Investigate a warmed preparation/owner lifecycle and lean cold imports before
claiming the first-game target is met. Bash still misses the warm Stop target.
Timing varied with the running device workload; these are small-sample comparisons,
not worst-case guarantees or controlled idle-core results.

All **47** fixtures pass in Linux/WSL and on the real ARM MiSTer. The final native
run took 0.128 seconds for the 13 contract fixtures and 51.414 seconds for the 34
process fixtures. Checks include both owners' normal/M82/commercial
policies, loading cancellation, urgent admission, old epoch/selection rejection,
UI lease races, malformed requests, failed cleanup recovery, empty preparation,
private FIFO loss mechanisms and seed evidence invalidation. They do not prove
real button/hotplug behavior, image decoding or hardware command acceptance.

Every native timing run verified identical saved SAM, MiSTer and BGM INI hashes
and the same live SAM owner identity before and after. Nothing was installed or
committed. Benchmark records are under the workspace's
`outputs/session-engine-research-2026-10-11/` directory.

The evidence favors a warm Python 3.9 session owner with Bash retained for the
small caller, UI and platform adapters. It does not justify putting another
interpreter startup on every preparation/launch, nor blocking menu display on
owner startup. Validate the owner/worker lifecycle and real driver boundary in
the first implementation slice before making this the default.

## Implementation gates

Before enabling the engine in production:

1. Choose the owner from native timing and CPU evidence, then connect the current
   command gateway without forcing heavy imports onto menu/control paths.
2. Connect the existing picker to the bounded preparation contract and validate
   real cross-session seeds, empty/sparse collections and storage removal.
3. Route existing MCP events through phase policy and test Bluetooth reconnect and
   the first physical press during preparation, dispatch and gameplay.
4. Integrate the single hardware driver and Menu/audio completion receipts; test
   Stop during a slow real core load, competing Next/Stop and mode changes.
5. Integrate volume/bind/BGM resource ownership and test owner crashes, canceled
   launches, recovery and reboot behavior without altering saved user settings.

Do these as small vertical slices behind an opt-in engine selection. Do not
replace all modules at once or remove the proven cleanup guards for a benchmark.
