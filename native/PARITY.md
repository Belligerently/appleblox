# Original AppleBlox screenshot parity

Compared against all seven images in the [upstream README gallery](https://github.com/AppleBlox/appleblox#gallery). Checked items mean implemented; runtime acceptance work is tracked separately below.

- [ ] Server-location lookup and “Server Joined” notifications
- [ ] Bloxstrap SDK compatibility
- [ ] Game-controlled Discord presence
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
- [ ] Mod installation guide and community links
- [ ] Mods-folder rescan — explicit pack imports already exist
- [ ] Live Discord display verification

## Visual FastFlag editor

Engine → Edit now groups Presets, Flags, and JSON in one profile sheet. Flags support allowlist-based addition, Boolean/integer values, persistent enabled/disabled state, name/value search, visible-row selection, and bulk removal. JSON imports replace enabled custom overrides; disabled rows remain unless an imported key enables them. JSON exports omit disabled overrides. Cancel discards draft changes; Save only stores the profile, and Apply remains separate.

## Discord presence controls

More → Integrations offers independent current-game, play-time, artwork/creator, and game-page-button controls. Artwork/creator defaults off; the other controls preserve prior defaults. Hiding the current game suppresses its name, creator, image, and link even if their saved controls are on. Public metadata is read through the existing cookie-free catalog/cache; failed or pending thumbnails fall back to text. Lookups run separately from log tracking, discard cancelled/obsolete sessions, and limit failed retries to once a minute.

## Acceptance checks

- [x] Isolated visual-editor checks: add/search/edit flags, invalid value/JSON recovery, filtered selection and bulk removal, saved disabled values, and Cancel preserving the profile.

- [x] Isolated Discord settings UI: independent toggles, master/game-visibility dependencies, and persistence after restart.
- [x] Mock Discord IPC: visibility changes, late artwork, timestamp toggling, duplicate suppression, ping/pong, and acknowledgments.
- [x] Both Player-close toggles migrate from older settings as off and persist independently.
- [ ] Live Player-close verification: return-to-website alone, exit-launcher alone, both together, and multiple Player instances.
- [ ] Confirm launcher remains open during an in-progress operation and when final history saving fails.
- [ ] Verify in-game icon recoloring and authenticated account switching.

The Appearance, Misc, and Info page contents were not shown in the gallery and need a separate source audit. The online Workshop, server-region selection, background updates while the launcher is closed, and native self-updating also remain outside this screenshot checklist. See README.md for implemented functionality and limitations.
