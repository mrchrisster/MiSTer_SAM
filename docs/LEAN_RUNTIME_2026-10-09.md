# Lean Bash runtime — 2026-10-09

## Change and cause

The experimental normal/roulette controller added a resident Python process
beside the Bash owner. Approximately ten times per second it exchanged timer
requests and replies, while Bash still performed the existing hooks and input
checks. This added interpreter memory, scheduling, parsing and duplicate state
handling without replacing the Bash workload. Native measurements confirmed a
resource regression, so this change removes that bridge.

Normal/roulette now run directly in `lib/engine.sh`. `sam/engine.py`, `sam/game.py`
and `lib/coordinator.sh` are removed from the release. Installer preflight no
longer requires them. Existing installed copies can remain inert; the installer
does not broadly remove unknown files or user modifications.

Retained improvements:

- Shared MCP command routing, verified PID/start ownership and phase transitions.
- Start admission lock, ownership-publication handshake, inherited-lock cleanup
  and the fresh idle interval after a stopped owner disappears.
- Cancellable preparation/launch jobs, a two-candidate queue and Menu-before-audio
  cleanup. Repeated preparation checks are limited to once per second while
  waiting; a launch can request immediate queue replenishment.
- Preparation spawn briefly defers TERM until PID/start registration finishes.
  An intermittent native failure exposed cleanup observing a child before its
  identity was saved. The guard covers fork/registration only and adds no idle
  polling; a deterministic injected-TERM test covers the race.
- Idempotent pause/resume: repeated pause preserves the frozen remaining time;
  repeated resume cannot extend the deadline. Zero duration remains indefinite.
  This applies to the internal handler; the public API still rejects a new
  redundant pause/resume request with 409, and UUID replay remains unchanged.
- Failed commit or playing-phase publication stops the session explicitly.
- Previous, Mute and module keys work while waiting for preparation. A queued
  pause is claimed before checking expiry, allowing it to freeze at zero rather
  than advance without handling the command.
- Countdown input dispatch preserves a received key even when `read` returns
  a timeout/interrupted status. Only empty EOF adds a sleep; ordinary timed
  waits do not receive a second delay. This remains direct builtin shell work.

The countdown uses builtin Bash `SECONDS` with whole-second precision, matching
the earlier shell runtime rather than the discarded fractional Python timer.
Its normal idle path uses builtin input waits and direct hooks, with no timer
child, internal pipe messages or per-tick SD writes. Existing MCP Python input
readers are retained; this change does not alter physical input sampling.
M82/video retain their existing specialized loops.

## Validation

Controlled native ARM measurements used the same hardware-mocked session fixture,
a full two-record queue, one second of warmup and 20-second samples. MiSTer was
in Menu with SAM and MCP stopped outside the fixture; samples ran sequentially.
CPU is a percentage of one ARM core, and memory is summed process RSS.

| Runtime | CPU | RSS | Samples |
| --- | --- | --- | --- |
| Earlier Bash baseline | 2.048%, 2.048% | 3,436 / 3,560 KiB | 2 |
| Python/Bash timer bridge | 5.145% | 11,904 KiB | 1 |
| Restored lean Bash | 2.098%, 2.048% | 3,556 / 3,560 KiB | 2 |
| Final build after cancellation fix | 2.198% | 3,556 KiB | 1 |
| Release after defensive read handling | 2.198% | 3,552 KiB | 1 |

The large timer-process overhead is removed. The last CPU samples remain 0.15
percentage points above the earlier baseline; these short runs cannot establish
whether that small difference is significant. They do not establish physical button-response or
cold-start latency. A native fixture additionally verifies that no persistent
timer child remains once preparation is complete.

The first full suite ran 374 tests in 283.699 seconds: 373 passed and one new
test incorrectly expected a redundant public Pause command to return success.
The API correctly returned 409. The fixture was corrected to preserve that
contract. The following 21-test run passed 20 checks and exposed the worker
registration race described above. After the fix, all 14 focused runtime tests
passed in 88.161 seconds, including both expiry and preparing-Previous cases,
public control behavior and a deterministic TERM-at-registration test. Both
cancellation scenarios then passed ten repetitions each: 20 checks in 24.145
seconds. After the final read adjustment, all three targeted read/Next/Previous
tests passed in 7.430 seconds. Counts overlap and are not additive; the full suite was not repeated
after those final changes. Earlier failure logs remain with the artifacts.

Software fixtures use private state and mocked launch/audio operations; live
checks use actual ROMs and Monitor responses. Neither proves physical button
latency, visible gameplay or audible transitions without a human observer.

One first live Previous command after Next was missed. It was not reproduced
in six traced live Next/Previous pairs or 30 private PTY pairs. Received traced
keys returned status zero. The defensive nonzero-read handling above has its
own deterministic test, but is not established as the cause of that original
miss. Do not describe this as a proven root-cause fix.

The final live rerun passed: SNES ZIP-member launch and Monitor image response
(89,952 bytes), automatic-start preservation of the running owner, pause/resume,
Next/Previous returning to the original ROM, keep-playing with inactive/kept
status and restored volume, and two Menu returns. Volume bindings remained until
Menu was observed and were released afterward (137 and 142 software samples).
Whole stop commands took 3.816 and 4.001 seconds; this does not prove a physical
input latency improvement. No immediate restart occurred during post-stop
checks. Configured normal selection was restored and launched a Neo Geo game
from a FAT ZIP. M82/video have fixture coverage, not new live gameplay evidence.

## Installation and rollback

Installed on `192.168.100.133`. Configuration backup:
`/media/fat/Scripts/.SAM_refactor_backups/install-20261009-205839-cmfvkw9u/MiSTer_SAM.ini`.
No Git commit or push was made in this change.
Installed and backed-up INI hashes match. All 132 packaged runtime files match
the installation by SHA-256, and no retired Python timer controller is running.
Both release patches passed `git apply --check` against their respective bases.

Copy the candidate archive to `/tmp/sam-lean-runtime-candidate.tar.gz`, then:

```sh
tar -xzf /tmp/sam-lean-runtime-candidate.tar.gz -C /tmp
python3 /tmp/sam-lean-runtime/MiSTer_SAM_install.py \
  --source-dir /tmp/sam-lean-runtime --mister-root /media/fat --branch test
```

Only `MiSTer_SAM.ini` is backed up automatically. ROMs, user maps and custom lists
are preserved. No new user setting or large binary download is required.

`remove-timer-bridge.patch` applies to the preceding `sam-phase2-candidate`
source archive. `sam-complete-from-fff2ebf.patch` includes the earlier audit and
ownership refactors and applies to commit `fff2ebf`. Use `git apply --check`
against the matching base before applying either patch.

The previous full source candidate remains in
`outputs/sam-phase2-2026-10-09/sam-phase2-candidate.tar.gz`. To restore that exact
intermediate build (including its resource overhead), extract it into `/tmp`
and invoke its installer with `--source-dir /tmp/sam-phase2-current` and the same
`--mister-root /media/fat --branch test` arguments. This is a source rollback,
not a full backup of the device. Restore an INI backup only if configuration
needs undoing.
