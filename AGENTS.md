# SAM development context

Before changing MCP, idle detection, mappings or input monitoring, read
[docs/MCP_INPUT.md](docs/MCP_INPUT.md). Update it when behavior changes.

MiSTer Main normally grabs Linux input devices during gameplay. Persistent
evdev/joydev streams cannot be assumed to receive new events. Current MCP
intentionally reopens jsX for startup-state snapshots. EVIOCGKEY/EVIOCGABS are
separate state queries available despite the grab; do not grab devices from Main.
The user selected js snapshots for the current update.

Configure once in MiSTer Main: supported saved global maps precede controllerdb,
then generic activity. Honor explicit unassignments and do not guess actions for
invalid/ambiguous unique/merged/alternate definitions. Keep metadata/DB reads out
of the 20 ms polling path and debug output conditional and queued.

Preserve modular MCP dedicated reader threads, startup cancellation, ownership
checks, phase-aware routing and cleanup/unmute ordering. Ignore direct software
virtual/input hotplug churn, but retain Bluetooth UHID and unknown identities.

When restarting MCP, target only its tmux session or verify both the Python
executable and exact script argument. The tmux server can retain the MCP path in
argv; matching that path anywhere can stop all sessions.

Use the standalone input diagnostic for physical gameplay/reconnect evidence.
Host fixtures and Scripts/Menu-only captures do not prove gameplay support.
Do not spawn subagents unless explicitly requested by the user.
