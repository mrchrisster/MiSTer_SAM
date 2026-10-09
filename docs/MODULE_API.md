# SAM module interface

Users keep the existing INI switches. SAM automatically loads only the enabled
modules: artwork, Monitor, BGM, tty2oled, curated lists, M82, video and roulette.
The lightweight local-control module loads by default. No module-list setting is
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
Runtime state, commands and selection records are literal data and never sourced.

| Hook | Purpose |
| --- | --- |
| config_loaded | Initialize enabled module configuration |
| core_requested | Mode adjusts requested cores through an array-name argument |
| session_validate | Pure checks for incompatible session options, before setup/stop |
| session_setup, session_start, session_stop | Set up and release owned resources |
| core_allowed | Reject an incompatible core |
| filter_stamp | Identify inputs that invalidate a cached eligible list |
| candidate_filter | Refine a private list in the background |
| candidate_prepare | Prepare/validate a selected candidate in the background |
| launch_validate | Cheap final check before dispatch |
| launch_info, launch_observe | Observe a real launch |
| display_start, display_startup, display_launch, display_publish | Publish display state |
| display_off, display_shutdown, display_exit | Preserve/clear status and release display resources |
| countdown_start, countdown_tick, controls_ready | Observe timing and transition readiness |
| audio_stop, update_assets | Stop audio or update enabled module assets |

Services are `choose_core`, `pick_candidate`, `commit`, `mode_key`, `timer_begin`,
`timer_tick`, and `session_loop`. Normal mode uses the prepared queue. M82 and video
retain their ordered/timed transition implementations inside compatibility modules.

Preparation has one owned, low-priority process and private temporary files. It
must not launch cores, publish active-game status, change live configuration, or
consume no-repeat history. Only the foreground owner commits real launches.
Queue records are published atomically and include owner, policy revision and
literal paths. Countdown hooks must not start per-tick helper processes.

Callback failure stops that event. Candidate preparation code 3 denotes an artwork
download/validation failure: retain the current game and report an explicit error.
Hooks must release owned resources on stop. Local controls share the existing
atomic-file/ack transport with Monitor; they do not require Monitor or a daemon.

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
tracks PID/start ticks and joins the existing cancellation/cleanup path. M82
indexes into a private staging directory and publishes its list only after
successful completion. It releases staging on stop. Input readers are unchanged;
M82 preparation/loading still accepts cancellation and Next rather than play.

Normal and compatibility selectors share these core rules. Legacy M82/video
sequence and timing loops remain separate; this change does not migrate them to
the normal prepared-selection queue or introduce a new transport/daemon.
