# MiSTer Super Attract Mode — modular test branch

SAM selects and launches games while MiSTer is idle. This `test` branch contains the modular refactor: normal mode prepares two eligible selections while the current game runs, so Next consumes a ready selection. One foreground session owns launches and at most one background preparation worker. Optional features load only when their existing INI switches enable them.

The HID keyboard and mouse readers and repeated joystick startup snapshots are retained. MCP resolves supported saved MiSTer controller definitions automatically, then controllerdb, then generic activity. Owner validation, startup cancellation and cleanup prevent stopped sessions from surviving or starting late. There is no Unix socket or additional control daemon. `partun` has been removed; archive discovery uses `samindex`, retaining its two indexing passes and delay.

## Installation and update

MiSTer needs Bash, Python 3.9 or newer, tmux and its usual SAM tools. The release includes the native indexing and controller assets. Regular GitHub archives exclude the optional mplayer binary and obsolete partun. Existing mplayer installations are retained; video mode downloads it separately when missing. Normal SAM does not need mplayer.

For an online installation, run through SSH:

```sh
curl -fL https://raw.githubusercontent.com/mrchrisster/MiSTer_SAM/test/MiSTer_SAM_install.py -o /tmp/MiSTer_SAM_install.py
python3 /tmp/MiSTer_SAM_install.py --download --branch test
/media/fat/Scripts/MiSTer_SAM_on.sh
```

The installer validates the complete release before changing installed files. It backs up only the existing `MiSTer_SAM.ini` under `/media/fat/Scripts/.SAM_refactor_backups/install-*/MiSTer_SAM.ini`, then stops active SAM/MCP sessions for the update. It preserves the user INI, custom controller mappings, plug-ins and ignore lists. It records `branch="test"` as the installed release channel. An existing MCP is restarted; SAM starts again through its normal idle or Start path. First installations have no existing INI to back up. Caches, generated lists, binaries and historical backups are not copied into a new backup.

Online updates run the installer included in the downloaded release, using that staged source without a second download. When updating from an older installer that lacks this handoff, that one update still follows its old backup behavior; subsequent updates use the new installer.

To update an installed modular release:

```sh
/media/fat/Scripts/MiSTer_SAM_on.sh update
```

Offline: download this branch's ZIP, extract it, copy the extracted folder to MiSTer, and run `python3 MiSTer_SAM_install.py` from that folder. The installer uses the bundled files. Copying only `MiSTer_SAM_on.sh` still bootstraps the full release when its modules are missing; Internet access is required for that path.

## Configuration and lists

Edit `/media/fat/Scripts/MiSTer_SAM.ini` or use the existing configuration menu. There is no user-facing module-list setting. Artwork and Monitor are optional and disabled in the distribution defaults.

Lists are accessible under `/media/fat/SAM/`:

| Folder | Contents |
| --- | --- |
| Gamelists | Generated core lists, M82 slots and curated attract lists |
| Rated | Age/rating lists |
| Blacklists | Shipped exclusions |
| Ignore | User exclusions; updates preserve these |

Legacy custom ignore and M82 lists migrate into these folders during installation. Remove an exclusion's line to undo it. Cached candidates are checked against current exclusions at launch.

Core eligibility is shared across normal, M82 and video selection. Enabled modules register core rules; all must approve a system, including explicit single-core requests and Previous. Empty allowed lists stop with an explanation. Temporary exclusions preserve the configured list. Module settings are fixed for a session; restart after editing them. See [core-rule API](docs/MODULE_API.md#core-rules) to add a module's restrictions without editing the shared picker.

Normal mode starts with a small eligible arcade batch on a cold installation when arcade is configured and permitted. It builds the remaining catalogs in the background. Enabled cores, mode and filters are respected. Repeated Next presses during loading coalesce into one pending skip.

## Commands and integrations

```sh
MiSTer_SAM_on.sh start             # configured cores/mode
MiSTer_SAM_on.sh start snes        # one system
MiSTer_SAM_on.sh next
MiSTer_SAM_on.sh previous
MiSTer_SAM_on.sh stop
MiSTer_SAM_on.sh exit_to_game
MiSTer_SAM_on.sh status
MiSTer_SAM_on.sh control pause
MiSTer_SAM_on.sh control resume
MiSTer_SAM_on.sh control ignore
```

The local `control` API accepts only supported actions, validates selection and process ownership, waits for acceptance and deduplicates supplied request IDs. It is suitable for Monitor and Zaparoo integrations without a new daemon. See [CONTROL_API.md](docs/CONTROL_API.md). The optional [Monitor adapter](adapters/monitor/README.md) preserves existing HTTP routes and publishes fresh SAM status/timestamps even on unchanged snapshots; SAM installation does not modify Monitor or Android.

## Optional modes

M82 retains BIOS/game order and phase-aware input. A game starts as a demo; first input activates `m82_game_timer`, and later input does not restart that timer. Next skips the BIOS interlude between games. Customize `/media/fat/SAM/Gamelists/m82_list.txt`.

Commercial mode retains CD-i CHD and mplayer playback. `samvideo_tvc="yes"` selects a commercial and then its mapped game; `samvideo_tvc_cdi="yes"` selects CHD/CD-i playback. Display overrides are temporary bind mounts. `mute="Yes"` also mutes commercials; use `mute="No"` for sound.

The artwork module currently rejects M82/video auxiliary launches. Set `Artwork_only="No"` for those modes. M82/video retain their existing transition loops inside modules; the prepared queue currently applies to normal mode. Android controls are advertised only for supported normal/roulette states. Physical joystick, CRT and AVI playback still need broader hardware testing.

Artwork-only normal mode uses small catalogs and downloads/validates selected covers during preparation. It does not need complete local artwork packs; uncached images require Internet access and download failures are reported explicitly.

## Development and validation

[MODULE_API.md](docs/MODULE_API.md) describes plug-in hooks and services. Add a manifest and module with its own enable switch; no edits to the main entry are needed. [MCP_INPUT.md](docs/MCP_INPUT.md) covers lifecycle, input-access constraints and mapping/debug behavior. [CHANGELOG.md](docs/CHANGELOG.md) records recent changes and validation limits. [LIVE_MODE_TESTS.md](docs/LIVE_MODE_TESTS.md) records actual M82 and commercial checks and their limits.

Run on Linux/MiSTer:

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Tests isolate their game lists, state, configuration and control files. Hardware effects are replaced in fixtures; the separate `live_*.py` scripts operate a real MiSTer and require intentional use.

To restore settings, copy a selected saved `MiSTer_SAM.ini` back to `/media/fat/Scripts/MiSTer_SAM.ini` and restart SAM. New update backups contain configuration only; reverting scripts requires reinstalling the desired release. Existing full `before.tar` backups remain untouched and can still be restored through ordinary copies from a temporary extraction directory; do not restore tar ownership directly onto FAT.

## Credits

Original concept and implementation: mrchrisster. Script layout and watchdog functionality: Mellified. tty2oled: Paradox. Indexing and input tools: wizzomafizzo. Thanks to the SAM contributors and testers.
