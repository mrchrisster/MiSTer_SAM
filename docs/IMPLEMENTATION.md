# SAM refactor

The first coordinator migration stage is described in
[ARCHITECTURE.md](ARCHITECTURE.md). Local commands share `sam/commands.py`, MCP's
input lifecycle policy lives in `sam/coordinator.py`, and normal/special loops
share foreground admission and cleanup in `lib/session.sh`. The existing Bash
game engine remains the launch backend during this staged migration.

Approved design: a foreground session owner, a bounded prepared-selection queue,
and at most one background preparation job. Disabled optional modules are not
loaded and perform no checks or downloads. Existing entry commands and Monitor
contracts remain compatible. No socket or additional resident control daemon.

Confirmed behavior decisions:

- Build each catalog with one samindex invocation; successful scans publish atomically,
  failed scans preserve the previous list. No unconditional scan delay is needed.
- Bootstrap respects enabled cores, active modes, and filters.
- Coalesce Next events during loading into one pending skip.
- Remove partun. Archive discovery remains the responsibility of samindex.
- Keep user-accessible lists in /media/fat/SAM/{Gamelists,Rated,Blacklists,Ignore}.
  Ignore lists are custom, separate, visible, and never overwritten by updates.

Implementation gates:

1. Preserve installed reference and recoverable backup; characterize behavior.
2. Extract components behind documented interfaces without changing launches.
3. Isolate background outputs and publish atomically with ownership/generations.
4. Prepare normal-mode candidates and covers before Next; validate cancellation,
   exclusions, no-repeat, failures, and pause.
5. Add progressive cold-start discovery and reuse warm catalogs.
6. Preserve mode-specific ordering, timing, audio/config cleanup, and controls.
7. Native isolated tests, measured performance, and live verification before
   declaring the replacement ready.

The reference directory is historical evidence, not an installation payload.
Production files must not include partun or the historical monolithic script.

Menu organization: immediate Start, Stop, Next, keep playing and exclude commands
come first. Game modes retain their existing presets. Games groups core selection,
filters and input behavior; Settings groups timing, autoplay, mute and artwork.
Advanced and maintenance retains Monitor, updates, direct INI editing and reset
operations. No new user INI switches are introduced. Dialog output is held in
PID-scoped RAM scratch files; a cancelled selection never dispatches an action.
