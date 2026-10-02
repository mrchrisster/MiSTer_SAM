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
