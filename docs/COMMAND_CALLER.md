# Command caller and runtime loading

`MiSTer_SAM_on.sh` is the public router. It checks installation availability and
forwards control/update/diagnostics commands before loading configuration. A
short-lived CLI process does not own ROM selection or session resources.

| File | Responsibility |
| --- | --- |
| `lib/caller.sh` | Pre-menu, UI initialization and lazy maintenance forwarding |
| `lib/dispatch.sh` | Explicit command families and their UI/runtime handlers |
| `lib/runtime.sh` | One-time foreground session/maintenance initialization |
| `lib/config.sh` | Configuration defaults and trusted INI loading |
| `lib/core-names.sh` | Small core ID/display-name map |
| `lib/data.sh` | Launch metadata, ROM aliases and shipped-list tables |
| `lib/monitor.sh` | Monitor attachment, help and MCP ownership checks |

`parse_cmd` remains a compatibility shim calling `sam_dispatch`. Command families
are explicit: gateway commands submit requests; UI commands open a view; runtime
commands require initialized services. Unknown commands fail without starting a
session. Adding a command means choosing its family and adding its handler, not
adding global initialization to the public entry. Installed menu functions keep
the existing allowlist and dialog/result isolation.

The pre-menu and settings UI share one trusted INI load, preserving shell
expressions, exports and includes. Sourcing it is faster on ARM than interpreting
each line in a second shell parser. The interactive prompt and ten-second
auto-start countdown begin after menu admission and the owner pause handshake.
Contested admission displays a startup wait; a running owner displays pause
progress. Arrow escape bytes and unrelated keys do not shorten the countdown.
Settings UI loads defaults/INI and core names, without scanning ROMs, reading
MiSTer.ini's volume paths or enabling optional modules. Maintenance actions load
their dependencies only when chosen. The full engine reads and validates the
complete INI and retains the existing foreground ownership/cleanup model.

Menu locks, start admission, owner-bound pause/resume and atomic dialog choice
files remain in RAM. No resident command daemon, new INI option or eligibility
cache is added. `startmonitor` attaches after successful Start without its old
unconditional one-second sleep.

An internal menu pause/resume lease uses the existing serialized RAM mailbox,
owner/selection/generation checks, expiry and acknowledgement. It does not read
or fsync the persistent replay journal. Public CLI and HTTP submissions still
reserve and complete their durable request IDs. The menu never treats an
unacknowledged pause as success or resumes a replacement selection.

Native control submissions and engine mailbox claims do not import the HTTP,
email or SSL stack. `urllib.request` is loaded only when an HTTP Monitor request
requires sequence validation. ARM profiling found those imports on both sides
of the pause handshake to be a major source of pre-menu input delay.
Canonical request IDs and the engine's fixed `claim --owner PID` invocation also
avoid loading UUID/platform and argument-parser machinery. Alternate public
request-ID formats retain the standard UUID parser; generated IDs remain UUID4.

An isolated ARMv7 engine fixture reproduced 5–8 seconds until an active owner's
menu accepted UP before these import changes. Final samples accepted UP in
3.5–4.0 seconds, with no journal writes, while the live device had no idle CPU
(Zaparoo, MiSTer, MCP and a transfer were running). An inactive private session
accepted UP within one second. These are measurements under that load, not a
latency guarantee. The active case still waits for the exact owner's pause
acknowledgement. The fixture replaced hardware launch/audio and preserved the
live owner and saved INI hashes; it does not establish physical game input behavior.

`SAM_EXIT_TRACE` records `menu_admission_wait`, `menu_admission_ready`,
`menu_pause_wait`, `menu_pause_done`, `premenu_ready`, `premenu_input_ready` and
the selected `premenu_action_*`. These distinguish loading, lock contention,
pause acknowledgement and real input readiness; rendering alone is not an
input-latency measurement.

Function-based loading requires global registry declarations (`declare -gA`)
and global owned-mount arrays (`declare -ga`). Otherwise Bash discards those
arrays when the loader returns. Modules must retain their registry/hook contracts
and defer resource acquisition to lifecycle hooks, rather than sourcing.

`source MiSTer_SAM_on.sh --source-only` still exposes the full runtime for existing
trusted custom scripts. Updates validate all new loader files before modifying
the installation.
