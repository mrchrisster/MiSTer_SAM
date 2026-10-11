# Owned preparation and launch cleanup

This candidate changes only SAM-owned preparation, foreground mode setup and
delayed launch/BIOS-skip jobs. The normal Bash timer loop and input backend are
unchanged. It adds no daemon, user option, disk-backed registry or idle polling.

The division of responsibilities stays small: `state.sh` owns process identity
and private-job primitives; `engine.sh` registers/cancels preparation;
`launch.sh` registers/cancels setup and skip jobs; `session.sh` owns shutdown
ordering and evidence; `lifecycle.sh` coordinates external Menu handoff.

## Why the faster tree snapshot was withheld

An isolated 21-process sleeping tree improved from a median 8.71 seconds to
0.95 seconds with one `/proc` snapshot. Every sleeping fixture was reclaimed.
That result did not establish safe cancellation of work that continues forking.
A subsequent active-fork fixture left 16 live descendants with the snapshot
proposal and 14 with the older recursive fallback. The fixture then reclaimed
only its recorded PID/start-matching processes. The snapshot proposal was
removed from the release and preserved under `work/cancellation-research`.

These are cancellation-fixture timings, not physical controller-to-Menu times.
The older fallback remains available for third-party jobs without a registered
private group; its dynamic-fork limitation has not been fixed by a faster scan.

## Private group ownership

The owner briefly enables Bash job control for each background fork and restores
its previous mode immediately. The child disables job control, closes inherited
session-lock descriptors without unlocking the parent's description, and stops
before executing its callback. Background stdin explicitly remains `/dev/null`,
as it was before briefly enabling job control; workers cannot consume the
owner's keyboard stream or stop waiting for foreground terminal access.
The owner records PID, process start ticks, PGID
and session ID, confirms the child's stopped state and parent identity, then
resumes it. PGID must equal the child PID and differ from the owner's group.
The existing TERM registration barrier now covers this complete handshake.

The wrapper waits for direct asynchronous helpers before normal completion.
Preparation's ordinary EXIT publication remains intact. Hard cancellation need
not publish a completed preparation marker. Optional module cleanup still runs
in the SAM owner, rather than a forcibly terminated preparation/skip child.

## Bounded cancellation

Cancellation validates the original group leader and freezes that leader as an
identity anchor. Its group cannot become an unrelated reused group while the
original leader remains present. A process snapshot supplies children-first
TERM/CONT routing for currently observed descendants. The leader remains
stopped during a short, conditional grace period; no delay is imposed once the
observed descendants have exited. A final group KILL, guarded again by the same
leader PID/start/PGID/session identity, includes late forks and TERM-handler
forks. The owner verifies that no live group member remains before reaping its
registered child and discarding job metadata.

An already absent leader with no surviving group is normal completion. An
absent leader with live members has lost its proof of identity: cleanup refuses
to signal that group and reports failure. It never adopts a process group by
name or numeric ID alone.

The code uses Bash and `/proc`; no `setsid` executable or new runtime package is
required. The distinction between process and group identity follows Linux's
[PID structures and membership accounting](https://github.com/torvalds/linux/blob/master/kernel/pid.c).

## Failure and admission

Uninterruptible kernel I/O (`D` state) can defer even SIGKILL. Cleanup performs
bounded checks and reports remaining work rather than waiting indefinitely.
Failure keeps the private job records, a RAM `cleanup-failure` marker and a
tagged `last-error.log`; it does not mark the session cleaned or release audio
and global mounts as though all work had exited. Internal Play cannot reload a
game after failed cleanup. External stop/start and new session admission refuse
while the recorded blocker remains. Once its exact identity/group is gone,
the marker can be cleared at the next command boundary.

Job liveness also retains a zombie main/leader thread when its process still
reports more than one thread. A main thread may exit while worker threads
retain memory and descriptors; a blocked worker may defer even group SIGKILL.
The job snapshot, member checks and failure marker therefore must not equate
every `Z` leader with a reclaimed process. General SAM-owner zombie rejection
is unchanged. The distinction follows
[`pthread_exit`](https://man7.org/linux/man-pages/man3/pthread_exit.3.html) and
[`/proc/PID/stat` field 20, `num_threads`](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html).
This edge case is covered with deterministic metadata and blocked-thread
fixtures; no physical uninterruptible-I/O experiment is claimed.

Programs deliberately creating another session or moving themselves into
another process group can escape this boundary. Such daemonizing third-party
work is outside the private-group contract; this is not universal containment.
Processes cannot be forcibly reclaimed while the kernel holds them in blocked
I/O. No global `pkill`, player-name kill or unrelated group signal is used.

## Early Menu handoff

Only a verified Menu exit can publish the private, owner-tagged `quiesced`
barrier. Preparation and delayed launch groups must first be gone. The owner
then completes `session_stop` hooks (including temporary video-INI restoration)
and `audio_stop` before publishing the barrier under the session lock, after
checking both current ownership and the pending Menu/audio marker again.
Failed critical hooks do not publish the barrier and retain the conservative
Menu path. Each critical event runs once.

The foreground owner continues mount, display and private-directory cleanup
after the barrier; cleanup is not detached into an unowned background process.
The Menu coordinator may overlap the visible transition with this remaining
work. It still waits for the old owner to exit and for Menu confirmation before
restoring volume. A live stopping owner continues to exclude replacement
sessions. Keep-game exits preserve their existing cleanup ordering.

## Validation

All thirteen isolated owned-job tests passed on native MiSTer Bash/Python as part
of the final 104-test affected-suite run (190.640 seconds). They cover active forks, TERM-handler forks, ignored TERM,
identity rejection, absent leaders, mode/trap restoration, bounded blocked-I/O
failure, retained evidence and admission refusal. A regression checks
that a grouped callback cannot retain the owner's flock after the parent closes
its descriptor; two more cover critical-hook ordering and quiescence refusal
after a failed hook. The final two cover zombie leaders with retained threads
and bounded failure while a worker thread remains. Integrated results are
recorded in the response report.

The matched 21-process sleeping-tree benchmark measured 7.07 seconds for the
older recursive fallback and 1.08 seconds for private-group cancellation;
both had zero live survivors. The active-fork group fixture completed in
0.74 seconds with seven recorded processes and zero survivors. The process
count differs because stopping its leader prevents further forks; this is
functional coverage, not a matched performance comparison. Single runs are
not an estimate of universal Menu-return latency.

The controlled benchmark is
`work/cancellation-research/benchmark_owned_group_cancel.sh`. It creates only
its own sleeping/active-fork tree, records exact PID/start pairs, checks live
survivors and performs narrowly scoped fixture cleanup. It never launches a
core or edits the installed SAM.

### Saved global mute policy

SAM records the original global mute byte in RAM before its Volume.dat bind. On restoration, an owned recorded bind remains in place while the live command is delivered. A differing mute bit must be acknowledged by Main saving the desired bit into the RAM file (at most twenty 0.1-second polls); only then is the bind removed. A matching bit needs no redundant command. Failed delivery, acknowledgement, identity validation or unmount preserves the protection and retry record. The installed Main uses direct file writes, verified during this audit. A Main build that replaces Volume.dat by atomic rename may not acknowledge through a bind; SAM then fails boundedly and retains protection rather than guessing success. Legacy mounts without a premount record cannot recover the original byte until unmount and retain the documented conservative fallback. Boot no longer sends an unconditional unmute.
