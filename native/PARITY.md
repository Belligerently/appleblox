# Original AppleBlox screenshot parity

Compared against all seven images in the [upstream README gallery](https://github.com/AppleBlox/appleblox#gallery). Checked items mean implemented; runtime acceptance work is tracked separately below.

- [ ] Server-location lookup and “Server Joined” notifications
- [x] Bloxstrap SDK compatibility — the original app’s SetRichPresence integration; SetLaunchData/server invites remain unsupported
- [x] Game-controlled Discord presence — opt-in text, timers, large/small asset artwork, persistent patches and clear/reset behavior
- [x] Independent Discord play-time toggle — defaults on, preserves existing behavior
- [x] Separate Discord game-activity visibility toggle — suppresses game name, artwork, creator, and game link together
- [x] Discord game artwork and creator attribution — opt-in, public metadata only
- [x] Optional Discord game-page button — public game page, not a server join/invite
- [x] Return to Roblox’s website after the last Player closes — optional, defaults off
- [x] Automatically exit AppleBlox after the last Player closes — optional, defaults off; saves tracked history and stays open during file/launch/install operations
- [ ] Improve and verify multiple-instance support — standard macOS new-instance request exists
- [ ] FPS unlock control
- [ ] Lighting-technology selection
- [ ] Voxel-shadow toggle
- [ ] Separate graphics-quality and render-distance controls
- [ ] Visual-effects toggle
- [ ] Review missing graphics API options — Default, Metal, and OpenGL are implemented
- [x] Visual FastFlag rows with value editing and enable/disable switches
- [x] FastFlag search
- [x] FastFlag selection and bulk removal
- [ ] Review original profile types and flag compatibility — named/per-game profiles, JSON editing, import/export already exist
- [ ] Legacy Resolution mode for mods
- [x] Mod installation guide and community links — native folder instructions, fork support, upstream community, GameBanana, and Bloxstrap resource guide
- [x] Mods-folder rescan — validates registered imported copies, refreshes counts, and reports enabled conflicts; new packs still use Import
- [ ] Live Discord display verification

## Visual FastFlag editor

Engine → Edit now groups Presets, Flags, and JSON in one profile sheet. Flags support allowlist-based addition, Boolean/integer values, persistent enabled/disabled state, name/value search, visible-row selection, and bulk removal. JSON imports replace enabled custom overrides; disabled rows remain unless an imported key enables them. JSON exports omit disabled overrides. Cancel discards draft changes; Save only stores the profile, and Apply remains separate.

## Discord presence controls

More → Integrations offers independent current-game, play-time, artwork/creator, and game-page-button controls. Artwork/creator defaults off; the other controls preserve prior defaults. Hiding the current game suppresses its name, creator, image, and link even if their saved controls are on. Public metadata is read through the existing cookie-free catalog/cache; failed or pending thumbnails fall back to text. Lookups run separately from log tracking, discard cancelled/obsolete sessions, and limit failed retries to once a minute.

## Bloxstrap SDK and game-controlled presence

More → Integrations has separate SDK compatibility and game-control toggles, both defaulting off for new and migrated settings. The bridge recognizes bounded `SetRichPresence` JSON output messages during the current observed game session. Missing/null properties preserve prior values; blank text, zero timestamps, image clear, and field/image reset follow the documented protocol. Deprecated start/end timestamps are accepted for existing games. State resets on leave, a new join, Player exit, disabled SDK/control/presence, or hidden game activity. Existing visibility, artwork, timer, and game-page-button controls take precedence.

Custom large/small artwork resolves numeric or `rbxassetid://` asset IDs through Roblox’s public, cookie-free thumbnails endpoint. Only completed HTTPS Roblox CDN results for the requested IDs are accepted. Lookups run separately from log processing, cache up to 128 assets in memory, and batch at most two IDs with a ten-second request cooldown. Obsolete/cancelled session lookups cannot update displayed artwork. Unavailable custom images are omitted. SDK data is not written to play history or diagnostics. Unknown commands and launch-data messages are ignored; this is the original app’s SDK presence surface, not full invite/deeplink compatibility. Protocol reference: https://bloxstraplabs.com/wiki/developers/bloxstraprpc/.

## Mod library tools

Mods → ••• offers Rescan Library, Scan Results, and a local Mod Guide. Each pack’s ••• menu offers Show Files and Remove from Library. Rescanning checks all registered imported copies, including disabled ones, updates valid file counts without changing identity/selection, and reports invalid/missing packs and resource overlaps. Conflict findings follow enabled selection; known invalid enabled packs block Apply until fixed/rescanned or disabled. Backups, unregistered folders, and removed records are not discovered. Scan only updates library metadata; applying remains explicit or opt-in before launch.

## Native maintenance (outside the screenshot audit)

- [x] Copy a fixed-field diagnostics report without account data, names, paths, URLs, raw logs, or activity messages.
- [x] Clear only the saved game-details cache, including memory/disk entries and obsolete in-flight lookups.
- [x] Appearance-only reset already exists under More → Appearance.

## Acceptance checks

- [x] Isolated SDK settings UI: new controls default off, SDK/game-visibility dependencies disable game control, saved values survive restart, and the section fits the compact window. Live SDK messages inside a Roblox experience and Discord display still need acceptance testing.

- [x] Isolated cache-maintenance UI: Cancel preserves entries, confirmed clear empties the cache, and unrelated files remain byte-for-byte unchanged. Diagnostics menu/report formatter verified; system clipboard contents were not changed during QA.

- [x] Isolated Mods UI: refreshed counts, invalid-pack findings, enabled conflict blocking, disabled conflict resolution, repaired-pack rescanning, Show Files in Finder, and local guide/link layout.

- [x] Isolated visual-editor checks: add/search/edit flags, invalid value/JSON recovery, filtered selection and bulk removal, saved disabled values, and Cancel preserving the profile.

- [x] Isolated Discord settings UI: independent toggles, master/game-visibility dependencies, and persistence after restart.
- [x] SDK unit checks: malformed/oversized messages, state merging/clear/reset, Unicode and timestamps, all visibility gates, settings migration, partial log writes, cookie-free endpoint selection, image validation/caching/retry bounds, and cancelled lookups.
- [x] Mock Discord IPC: visibility changes, late artwork, timestamp toggling, duplicate suppression, ping/pong, and acknowledgments, including SDK custom text and small artwork with hidden-game/time/artwork settings.
- [x] Both Player-close toggles migrate from older settings as off and persist independently.
- [ ] Live Player-close verification: return-to-website alone, exit-launcher alone, both together, and multiple Player instances.
- [ ] Confirm launcher remains open during an in-progress operation and when final history saving fails.
- [ ] Verify in-game icon recoloring and authenticated account switching.

The Appearance, Misc, and Info page contents were not shown in the gallery and need a separate source audit. The online Workshop, server-region selection, background updates while the launcher is closed, and native self-updating also remain outside this screenshot checklist. See README.md for implemented functionality and limitations.
