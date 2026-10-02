# Optional MiSTer Monitor adapter

SAM itself does not need Monitor. Local integrations can use `MiSTer_SAM_on.sh control ACTION`.

These four Python files contain the tested Monitor server and SAM status/control integration. Install `mister_status_server.py`, `sam_status.py`, `sam_control.py` and `sam_control_legacy.py` together in the existing Monitor server directory, after backing it up, and restart it through its existing startup script. This is an explicit Monitor update; the SAM installer does not replace or restart Monitor.

The adapter preserves the game sequence and existing routes. Every snapshot, including `unchanged=true`, contains fresh SAM status and a MiSTer-clock timestamp. HTTP controls validate selection/owner identity, deduplicate request IDs and wait for SAM acceptance. M82 and commercial modes currently advertise no Android controls; their native SAM input paths remain available. Preserve the existing `sam_control_networks.json` policy. For a new Monitor installation, copy `sam_control_networks.example.json` to that name and set the intended trusted LAN range before enabling HTTP controls. With no policy, network control requests are denied.
