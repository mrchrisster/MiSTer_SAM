# SAM module interface

Users keep the existing INI switches. SAM automatically loads only the enabled
modules: artwork, Monitor, BGM, tty2oled, curated lists, M82, video and roulette.
The lightweight local-control and category policy modules load by default. No module-list setting is
needed in the user INI. Disabled artwork performs no catalog/image/cache work.

To install a plug-in without editing MiSTer_SAM_on.sh, provide:

- `modules/example.sh`, containing trusted installed functions.
- `modules.d/example.module`, containing literal lines:

```
name=example
enabled_by=Example_enable
```

The user enables it with `Example_enable="Yes"` in the INI. Manifests are parsed
as data; neither their names nor their values are evaluated. A disabled plug-in's
shell implementation is not sourced.

Register callbacks with `sam_register EVENT FUNCTION`, or replace one service
with `sam_bind SERVICE FUNCTION`. Function names are validated and called directly.
Modules are sourced inside the loader function: use `declare -g`, `declare -gA`
or `declare -ga` for shared module state, rather than a local `declare`.
Runtime state, commands and selection records are literal data and never sourced.

| Hook | Purpose |
| --- | --- |
| config_loaded | Initialize enabled module configuration |
| core_requested | Mode adjusts requested cores through an array-name argument |
| session_validate | Pure checks for incompatible session options, before setup/stop |
| session_setup, session_start, session_stop | Set up and release owned resources |
| menu_prepare | Bounded policy handoff before Menu dispatch; no slow player shutdown |
| core_allowed | Reject an incompatible core |
| filter_stamp | Identify inputs that invalidate a cached eligible list |
| candidate_filter | Refine a private list in the background |
| filter_policy | Set dynamically scoped policy flags before standard filters; never add candidates |
| config_refresh | Refresh literal selection settings at a game boundary |
| candidate_prepare | Prepare/validate a selected candidate in the background |
| launch_validate | Cheap final check before dispatch |
| launch_info, launch_observe | Observe a real launch |
| display_start, display_startup, display_launch, display_publish | Publish display state |
| display_off, display_shutdown, display_exit | Preserve/clear status and release display resources |
| countdown_start, countdown_tick, controls_ready | Observe timing and transition readiness |
| audio_stop, update_assets | Stop audio or update enabled module assets |

Services are `choose_core`, `pick_candidate`, `commit`, `mode_key`, `timer_begin`,
`timer_tick`, and `session_loop` for the legacy comparison backend. The resident
engine additionally exposes `engine_take`, `engine_launch`, `engine_timer_begin`,
`engine_timer_tick` and `engine_key`. Defaults are registered before modules load,
so an enabled module can replace them without editing the owner or normal picker.
M82/video bind their programme providers; normal mode keeps the prepared queue.
The fixed protocol and return conventions are described in [SESSION_ENGINE.md](SESSION_ENGINE.md).
`session_loop` replacements apply only to `SAM_ENGINE=legacy`; new programme
modules must provide operations on the shared engine instead of another loop.

Preparation has one owned, low-priority process and private temporary files. It
must not launch cores, publish active-game status, change live configuration, or
consume no-repeat history. Only the foreground owner commits real launches.
Queue records are published atomically and include owner, policy revision and
literal paths. Countdown hooks must not start per-tick helper processes.

Callback failure stops ordinary events. Cleanup events `session_stop`, `audio_stop`,
`display_shutdown` and `display_exit` attempt every registered callback and return
the first failure, so one broken module cannot prevent another from releasing its
resources. Candidate preparation code 3 denotes an artwork
download/validation failure: retain the current game and report an explicit error.
Hooks must release owned resources on stop. Local controls share the existing
atomic-file/ack transport with Monitor; they do not require Monitor or a daemon.

`audio_stop` callbacks must be bounded and safe to retry. The optional first
argument is `menu` or `game`; callers without a destination retain ordinary stop
semantics. Return failure until the requested audio policy is settled; a finalizer can invoke this event once
more after owner cleanup, before restoring volume or completing a keep-game
handoff. Global volume restoration belongs to the lifecycle finalizer, so an
audio-service callback must not bypass its Menu/ownership checks. `session_stop`
is not generically replayed by this retry.
For Menu exits, cancellation of launch jobs and `session_stop` plus
`menu_prepare` happen before the launch barrier is published. Menu can load while
preparation cancellation, `audio_stop` and optional display cleanup continue.
The preparer's publication token is revoked immediately; preparers must obey
the no-launch/no-live-hardware contract above. Failed preparation cleanup blocks
replacement admission and the audio-completion receipt. Keep the game's mute mounts
until a separate owner-specific audio-completion receipt exists and Menu's Main
process/FIFO are confirmed. An accepted Menu command alone never proves audio
cleanup. The receipt prevents duplicate audio shutdown after Menu has resumed
its playlist; missing or mismatched receipts require a bounded retry.

Persistent BGM sets and confirms `playincore=no` in `menu_prepare`. Its Menu
`audio_stop` confirms that policy without stopping the playlist; a game exit
still stops playback. Full player termination can overlap Menu loading. Plug-ins
must keep any configuration changes required by Menu in `session_stop` or
`menu_prepare`, and must not release SAM's volume protection themselves.

Developer-only `SAM_MODULES_OVERRIDE` can isolate modules during tests. An empty
value disables all; a comma-separated value loads exactly those named modules.
It is an environment override, not a regular user setting.

Public lists: `/media/fat/SAM/{Gamelists,Rated,Blacklists,Ignore}`. Updates never
replace custom Ignore files. Remove an exclusion's line to undo it; a cached
candidate list is invalidated by the file change and the launch boundary also
checks exclusions immediately.

## Core rules

The shared implementation is `lib/cores.sh`. A session has three distinct lists:
`sam_requested_cores` (normalized configuration, adjusted by the mode),
`sam_allowed_cores` (all module predicates plus session exclusions), and
`corelisttmp` (remaining rotation). Compatibility `corelist` mirrors the allowed
list. Refilling a rotation never uses the unfiltered configuration/default list.
Temporary exclusions do not modify the requested list or the INI.

A feature registers a cheap predicate, loaded only when that feature is enabled:

```sh
example_core_allowed() {
    case "$1" in
        n64|psx|saturn)
            sam_core_reason="This feature requires per-core volume control"
            return 1 ;;
        *) return 0 ;;
    esac
}
sam_register core_allowed example_core_allowed
```

The callback receives a canonical core ID and a role (`candidate` by default,
or `auxiliary` for a playback resource). Return 0 to allow, 1 to reject, or any
other status for an error. All predicates must approve; errors stop preparation
or launch rather than becoming an empty list. An optional one-line
`sam_core_reason` explains rejection. Predicates must not modify lists, scan ROMs,
download files or start processes. They run during selection and at launch/replay.

`sam_normalize_cores INPUT OUTPUT` and `sam_filter_cores INPUT OUTPUT` accept
indexed-array variable names, including in-place operation. They trim, lowercase,
deduplicate and remove blank entries; unknown core IDs are errors. Output is
assigned only after success. `__sam_*` variable names are private and forbidden as
array arguments. `sam_filter_cores` returns 0 for a successfully filtered empty
list; `sam_core_policy_refresh` returns 1 when no session cores remain, and 2 for
rule/input errors. `sam_core_require CORE` verifies the actual selected game
against rules and the session's allowed list; use the original core for MGL replay.

Modes can register `core_requested CALLBACK`. Its argument is the requested-array
name; M82 sets that array to `(nes)` and separately registers its NES-only
predicate. Explicit CLI targets replace the requested array after this hook,
then still pass every predicate, so a conflicting target is rejected clearly.
Features should constrain cores through predicates rather than override requests.

Module switches and settings are fixed for a session. Restart SAM after changes.
Menus that reread settings mark their registry stale; `sam_start` validates the
new options in a fresh process before stopping an existing session. Pure
`session_validate` hooks reject unsupported combinations without running setup.
The normal CLI start path needs no extra preflight process.

Long foreground mode setup uses `sam_run_owned_command COMMAND ARG...`, which
registers a private process group with PID/start/group/session identity before
releasing the callback, and joins the cancellation/cleanup path. Callbacks must
not detach with `setsid`, create new process groups, or leave untracked services.
They receive `/dev/null` as stdin. M82
indexes into a private staging directory and publishes its list only after
successful completion. It releases staging on stop. Input readers are unchanged;
M82 preparation/loading still accepts cancellation and Next rather than play.

Normal and compatibility selectors share these core rules. Legacy M82/video
sequence and timing loops remain separate; this change does not migrate them to
the normal prepared-selection queue or introduce a new transport/daemon.

On Menu exit, `session_stop` and `audio_stop` are critical barriers: they must
finish stopping core-writing work and restoring launch-sensitive configuration
before returning. SAM may then request Menu while the owner completes mount and
display housekeeping. Display shutdown hooks must not launch cores or leave
untracked helpers; keep their work bounded. These hooks still run in the owner
with its variables available, and admission remains blocked until it exits.
See [owned job cleanup](OWNED_JOB_CLEANUP_2026-10-09.md).

## Where to make changes

- `sam/commands.py`, `sam/coordinator.py`: shared local commands and input lifecycle policy.
- `sam/session.py`: immutable verified session snapshots for Python callers.
- `lib/session.sh`: foreground admission, transitions, worker publication and cleanup.
- `lib/engine.sh`, `lib/lifecycle.sh`: foreground selection, countdown and platform start/stop.
- `lib/catalog*.sh`, `lib/filter.sh`, `lib/policy.sh`: prepared candidates and policy.
- `lib/modules.sh`: manifest parsing, hooks and service bindings.
- `modules/*.sh`, `modules.d/*.module`: optional feature implementations and switches.
- `lib/menu.sh`: entry menu and lazy loading; `MiSTer_SAM_menu.sh`: settings dialogs.
- `MiSTer_SAM_MCP.py`: input readers and routing; consult `docs/MCP_INPUT.md` before edits.

Normal/roulette timing and hooks execute directly in the foreground Bash process.
There is no Python timer controller or pipe protocol. Configure `gametimer`
before the session. Timer hooks share the shell countdown context; expensive
work belongs in preparation hooks, not `countdown_tick` or `timer_tick`.
Returning nonzero from either tick hook requests normal advancement. The
foreground processes pending controls before checking expiry, so a claimed
pause can freeze a game at zero remaining seconds. The public control API
continues rejecting a new pause of an already paused game with 409.
Existing M82/video adapters retain their specialized timing implementations.

Call `sam_session_begin` in a foreground shell before starting a custom session
loop. Only the admitted foreground owner publishes lifecycle phases. Use
`sam_publish_phase` and propagate failure before hardware operations; a stale
worker cannot publish phases. Do not unlink `session-owner.lock` or reset the
shared runtime directory. See [ARCHITECTURE.md](ARCHITECTURE.md) for the boundaries
between the coordinator, command gateway and compatibility engine.

Menu changes take effect for the next session. UI functions write existing INI
keys through `samini_mod`; they must not mutate the running owner's settings or
launch a background candidate directly. Main menu `play` uses the same acknowledged
control path as other local controls. A new optional feature should register its
hooks when sourced, keep expensive initialization in `session_setup`, and release
only its own resources in `session_stop`. Keep scratch/cache activity under the
runtime temporary root; persistent files belong in the documented public lists.

For a new menu group, use `sam_menu_group TITLE PROMPT TAG LABEL ...`; only the
listed tags dispatch through `parse_cmd`. Avoid recursive `sam_menu` calls from
submenus: return to the caller so repeated visits do not accumulate shell frames.

BGM controls use bounded socket operations and identify its installed script by
exact native executable path, or Python/shell executable plus the exact script
argument, never an argv substring. Native ELF installations are started through
their foreground `exec` service interface.
Stopping BGM requests its owned player's cleanup through the service and sends
TERM only after revalidation. The bundled Python player reaps its own media child; these Python changes do not
modify a separately installed native ARM BGM executable. SAM
does not terminate arbitrary processes named `mpg123`. Existing installations
are reused until explicitly updated.

Native BGM builds advertising v2 policy support receive one acknowledged
temporary policy per lifecycle transition. `sam_bgm_client.py` uses Python 3.9
stdlib sockets, with bounded deadlines and a RAM record keyed to the verified
daemon PID/start/socket identity. Request IDs and increasing revisions make
retries idempotent. `active` acquires playback, `menu` restores normal Menu
preferences, and `game` restores preferences while stopping playback. Exact
service termination for `bgmstop=Yes` is unchanged. Unsupported completed
capability replies use the legacy path; transport failures block the audio
barrier and can be retried. A timed-out request is not proof of application.

`sam_finish_audio_stop` supplies its verified cleanup owner through dynamic
`sam_bgm_policy_owner`, avoiding accidental ownership by the helper shell.
Policy records and readiness do not replace the existing independent Menu/audio
completion receipt or the exact process and socket ownership checks.
