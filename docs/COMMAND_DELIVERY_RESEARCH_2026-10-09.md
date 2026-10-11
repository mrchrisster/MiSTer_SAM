# MiSTer Main command delivery research — 2026-10-09

The installed Main binary matches the official September 12 release exactly:
SHA-256 `9f6e5a237c36be6404ab4823d804821491db4bf125827f84aca2a1ca31f0a8a6`,
size 1,166,224 bytes, version `$VER:260912`. The downloaded
[official binary](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/releases/MiSTer_20260912)
and relevant source are pinned to release commit
[47221c18987e101f50caafeb3b615f53b62722ca](https://github.com/MiSTer-devel/Main_MiSTer/commit/47221c18987e101f50caafeb3b615f53b62722ca).
Current upstream at `42e64002280578e01346d0afa37851ea49c24427` retains the same
command behaviors. Downloads and commit metadata are under
`work/main-command-research/`; this research changed no Main or SAM runtime.

## Verified behavior

`/dev/MiSTer_cmd` is a FIFO. On the first input initialization Main unlinks its
path, recreates it and opens it with `O_RDWR | O_NONBLOCK | O_CLOEXEC`.
This agrees with the device's observed FIFO type and changed modification time during core
loads. Existing writer descriptors address the old FIFO, not its replacement.
[Initialization](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/input.cpp#L5132-L5145).

Main reads up to 1,023 bytes and parses that entire buffer as one command. It
removes only a final newline; it does not split multiple lines. Separate atomic
writes can therefore be coalesced into one read. For example, a buffer containing
`volume unmute\nload_core ...\n` does not match the exact unmute argument, and
its second line is not dispatched separately. Partial or oversized commands are
also not assembled into complete lines. A successful write establishes kernel
buffer acceptance, not parsing or application success. The parser emits a log
message but provides no acknowledgement or request identifier.
[Parser](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/input.cpp#L6228-L6267).

A successful RBF load restarts Main. `app_restart` resets hardware, forks, exits
the old process, detaches and executes the next Main process. XML/MGL/MRA loads
resolve the RBF and enter this same route. Commands queued behind a core change
can consequently disappear with the previous FIFO reader or be merged into the
core-load argument before it is parsed.
[RBF loading](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/fpga_io.cpp#L426-L506),
[restart](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/fpga_io.cpp#L620-L646),
[XML loading](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/support/arcade/mra_loader.cpp#L1301-L1324).

`/tmp/CORENAME` is written by `SetUARTMode` during `user_io_init`. Initialization
completes before the first `input_poll`, which creates the command FIFO. Thus a
fresh expected CORENAME can precede the replacement FIFO reader. It identifies
a core; it is not a command acknowledgement or proof that MGL loading has
finished. Reloading the same core also requires evidence of a new incarnation.
[Marker](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/user_io.cpp#L1184-L1196),
[initialization calls](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/user_io.cpp#L1766-L1785),
[startup order](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/main.cpp#L72-L88).

Unmute changes an in-memory flag and sends volume to FPGA immediately, but
schedules configuration persistence one second later. The replacement Main
loads `Volume.dat` and the core volume configuration during initialization.
An unmute applied shortly before restart can therefore be replaced by older
persisted state. File contents alone are not immediate hardware readback.
[Application](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/audio.cpp#L154-L166),
[save and reload](https://github.com/MiSTer-devel/Main_MiSTer/blob/47221c18987e101f50caafeb3b615f53b62722ca/audio.cpp#L229-L267).

## Recommendations and limits

These are design conclusions, not an implemented delivery guarantee:

- Serialize lifecycle intent through core changes. Stop must prevent a competing
  launch and remain pending until the intended Menu transition is observed.
- Confirm the expected fresh core marker, new Main identity and replacement FIFO
  incarnation before sending final audio restoration. CORENAME alone is too early.
- Send one complete command per write, reopen the FIFO for each incarnation and
  avoid adjacent unrelated commands. Atomic writes or a writer lock alone do not
  ensure Main reads commands separately.
- Use bounded, owner-checked retries for idempotent desired states such as Menu
  or unmute. Do not blindly repeat navigation, toggles or successful game loads.
- Distinguish accepted, applied and confirmed results. Exact application receipt
  would require a Main acknowledgement protocol; the existing FIFO offers none.

The source establishes these failure mechanisms, but does not prove which caused
any historical missed Stop, unmute or ready-state Previous. The new loading
Previous regression has separate deterministic before/after evidence. Future
live command tests should include the requested Darkstalkers CPS2 game; this
research contains no new gameplay or audible confirmation.

## Existing MCP safeguards and their lineage

Compared current source with Git HEAD
`fff2ebfa156d5ba7b158752632624314205292c5`. Exact HEAD snapshots are retained in
`work/main-command-research/MCP_HEAD.py`, `lifecycle_HEAD.sh` and `audio_HEAD.sh`.
This comparison separates existing safeguards from later changes:

- **Menu retries already existed.** HEAD MCP's `exit_to_menu_with_retry` first
  awaited `exit_to_menu_fast`, then attempted up to 15 Menu FIFO writes. Each
  write had a one-second timeout and each attempt slept one second; subsequent
  attempts checked CORENAME first. This was 15 attempts, not a strict 15-second
  end-to-end deadline. FIFO write return codes were ignored, and success/failure
  both returned `None`. The old fast cleanup restored audio before loading Menu
  and backgrounded remaining service cleanup.
  [HEAD MCP snapshot](</C:/code/MiSTer_SAM/work/main-command-research/MCP_HEAD.py:644>),
  [HEAD fast cleanup](</C:/code/MiSTer_SAM/work/main-command-research/lifecycle_HEAD.sh:166>).
- **Retries moved into the shared Bash lifecycle; they were not removed.**
  Current MCP delegates through the owner-bound gateway to `stop`. Bash attempts
  up to 15 one-second-timeout Menu writes, polling CORENAME ten times at 100 ms
  between attempts. It cancels owned jobs first, holds admission during final
  effects, rechecks ownership, and defers volume restoration until Menu is
  observed. A failed write or restoration can be retried by that loop; an
  accepted write still has no Main application acknowledgement. The Python
  wrapper now returns a boolean and logs refusal/failure.
  [Current MCP](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/MiSTer_SAM_MCP.py:654>),
  [Menu loop](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/lib/lifecycle.sh:326>),
  [Menu audio check](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/lib/lifecycle.sh:497>).
- **The old unmute retry checked mounts, not live audio.** HEAD MCP invoked
  public `unmute`, which called `unmute_with_retry`: remove the Volume.dat bind,
  then retry removal/unmute up to 15 times while the bind remained. Once the bind
  disappeared it returned success immediately, regardless of whether Main had
  applied unmute. The helper still exists for bootstart. Current public unmute
  instead verifies the observed owner under the admission lock and performs
  bounded mount restoration plus one FIFO unmute write; there is no independent
  retry of a write that succeeds but is subsequently lost.
  [HEAD helper](</C:/code/MiSTer_SAM/work/main-command-research/audio_HEAD.sh:136>),
  [Current routing](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/lib/dispatch.sh:57>),
  [Current unmute](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/lib/lifecycle.sh:387>),
  [Restoration](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/lib/lifecycle.sh:522>).
- **Startup cancellation retains a real barrier.** Both versions track the
  launcher's private process group, TERM it, wait up to two seconds, then KILL
  and join if necessary before cleaning up the owner. Startup buffers one pending
  action, coalesces Next, and checks every 100 ms for up to ten seconds. Current
  code additionally rereads the owner after cancellation and chooses owned
  Menu/keep-game cleanup from the current phase.
  [Current launcher barrier](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/MiSTer_SAM_MCP.py:631>),
  [Startup decisions](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/sam/coordinator.py:105>).

The input-policy gap found during research also existed in HEAD: while an action is running,
`is_stopping` causes additional physical actions to return without buffering,
including a stronger Stop arriving during Next. Current `handle_action` does not
retain failed stop/unmute intent or inspect their false result before releasing
this busy flag. Owner verification protects replacement sessions but does not
provide delivery convergence. The follow-up below addresses one bounded case.
Any broader pending-intent policy must preserve that owner binding,
startup cancellation barrier, and Menu-before-audio ordering.
[Current input policy](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/sam/coordinator.py:36>),
[HEAD policy snapshot](</C:/code/MiSTer_SAM/work/main-command-research/MCP_HEAD.py:792>).

## Follow-up: Menu freshness guard

A live Stop one second after dispatching Darkstalkers reproduced premature audio
resource release: the volume binds disappeared while CORENAME still contained
old MENU and the FIFO had no reader. The actual Menu marker arrived approximately
4.9 seconds later. This establishes mount-order failure, not an audible result.

The shared Menu exit now scopes freshness checks to that pending operation. It
captures the initial Main identity, FIFO and marker signatures, requires a
successful Menu write plus fresh Menu/Main/FIFO state, and verifies that the
exact new Main process has an open descriptor for the current FIFO device/inode.
This coupling is necessary: a fresh Menu process/marker with the predecessor
Darkstalkers FIFO is still too early. Bound identities are checked before unmute
and after restoration. FIFO timestamps can change on writes, so the final bound
endpoint check compares its device/inode; Main PID/start and marker signatures
must remain stable. Failure keeps the pending completion token.

The guard does not add a Main acknowledgement channel or make audio effects
atomic with an external core change. If Main changes during restoration, the
operation reports failure and keeps completion pending; effects already applied
cannot be rolled back. These checks add work only to pending Menu completion,
with no resident process or normal input/countdown polling work. Standalone
recovery keeps its existing owner checks.
[Implementation](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/.MiSTer_SAM/lib/lifecycle.sh:425>),
[private regression fixtures](</C:/code/MiSTer_SAM/work/ini-only-update/github-test/tests/test_menu_delivery.py>).

## Follow-up: Stop during Next

MCP now retains one default/Exit Menu request while a verified ordinary Next or
Ignore operation is awaiting completion. It rechecks the captured PID/start
before delivering that request; a replacement owner is never stopped by stale
input. Repeated Stop requests coalesce. This does not change M82 routing,
keep-playing actions, or startup cancellation, and does not add a general retry
service for failed commands. The brief ownership-discovery window is unchanged.

Menu dispatch now overlaps optional owner cleanup after a private PID/start-tagged
quiescence barrier. All preparation/launch groups, session-stop callbacks
(including video/INI cleanup and custom hooks) and audio-stop callbacks must
finish first. The waiting backend captures its generation baseline before TERM,
then revalidates the barrier, stopping phase, original owner and pending Menu
intent under the admission lock before a bounded early write. It carries that
accepted request into final observation, giving it an observation interval before
another load. The stopped owner continues optional cleanup in its own process;
no separate dispatcher is created, and new session admission remains blocked
while that owner is alive. Audio release still requires owner exit and the fresh
Menu/FIFO proof. The existing five-second owner deadline remains, so visible Menu
alone is not reported as completed cleanup.
