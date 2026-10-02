# Live mode checks — 2026-10-02

Tested the actual MiSTer with original HID keyboard and joystick detection retained.

## M82

- BIOS loaded from the installed NES ZIP collection.
- BIOS/demo advanced to Zelda in the configured twelve-slot list.
- User confirmed physical 123 COM remote input keeps the game running and activates play time.
- With a temporary 30-second play setting, first input extended the deadline; repeated input did not keep resetting it. Natural expiry returned to the BIOS.
- Restored `m82_game_timer=180`: the live deadline reflected the 180-second extension from first input (the elapsed portion was already counted when sampled).
- Native Next from BIOS to Mario took 0.420 seconds; game-to-game Next to Punch-Out took 0.522 seconds and skipped the BIOS interlude. These measure command-to-state publication, not HDMI frame latency.
- External Menu caused the owner and SAM tmux pane to exit. Monitor reported inactive. The old state file can remain present; owner validation makes it inactive.

## Commercial followed by matching game

- Used installed CHD files, CD-i core and SNES title mappings.
- Looney Tunes Sunsoft Collection advanced automatically to Daffy Duck: The Marvin Missions. DOOM advanced to Doom (USA).
- Missing sound was the configured `mute="Yes"` and its active global mute bind. With `mute="No"`, the user confirmed commercial audio works.
- Fixed video module's state mode from `video` to canonical `samvideo`. Monitor now reports active video mode during both commercial and matching-game playback.
- Video display settings use a temporary MiSTer.ini bind; the original file is backed up before testing.

Artwork-only filtering was disabled for these tests: the optional artwork module currently rejects M82/video auxiliary launches. This restriction remains explicit; no full artwork packs or Android changes are required. Physical joystick, M82 infinite timer, CRT and mplayer/AVI playback are not covered by these live checks.
