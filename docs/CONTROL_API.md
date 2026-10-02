# Local SAM control API

Existing CLI commands remain available. The additional stable local interface is:

```
MiSTer_SAM_on.sh control status
MiSTer_SAM_on.sh control next
MiSTer_SAM_on.sh control pause
MiSTer_SAM_on.sh control resume
MiSTer_SAM_on.sh control play
MiSTer_SAM_on.sh control ignore
```

Returns one JSON result. Exit zero means accepted; it does not mean the next game
has finished booting. Errors are reported explicitly. The interface never retries
a timed-out command automatically. Status lists supported actions; callers must
not assume every mode supports every action.

Optional request ID, game path, PID, start ticks, and generation allow callers to
target a previously observed selection and deduplicate a repeated request.
MiSTer Monitor retains its existing HTTP API and sequence-number validation.
Local programs do not need Monitor or a network connection.

Commands use the existing bounded atomic-file/acknowledgement protocol. SAM owns
acceptance and performs transitions in its event loop. Literal paths are data.
No socket, new resident process, command evaluation, or write to SAM_state is used
as a substitute for commanding SAM.

The existing Zaparoo activity-file handoff remains supported. New integrations
may use the CLI rather than writing private state files.
