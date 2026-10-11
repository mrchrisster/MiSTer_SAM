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

The pre-menu loads only its three display preferences, with a fallback to the
trusted INI loader for expressions/includes. Its existing ten-second auto-start
countdown begins after menu admission; it is separate from startup overhead.
Settings UI loads defaults/INI and core names, without scanning ROMs, reading
MiSTer.ini's volume paths or enabling optional modules. Maintenance actions load
their dependencies only when chosen. The full engine reads and validates the
complete INI and retains the existing foreground ownership/cleanup model.

Menu locks, start admission, owner-bound pause/resume and atomic dialog choice
files remain in RAM. No resident command daemon, new INI option or eligibility
cache is added. `startmonitor` attaches after successful Start without its old
unconditional one-second sleep.

Function-based loading requires global registry declarations (`declare -gA`)
and global owned-mount arrays (`declare -ga`). Otherwise Bash discards those
arrays when the loader returns. Modules must retain their registry/hook contracts
and defer resource acquisition to lifecycle hooks, rather than sourcing.

`source MiSTer_SAM_on.sh --source-only` still exposes the full runtime for existing
trusted custom scripts. Updates validate all new loader files before modifying
the installation.
