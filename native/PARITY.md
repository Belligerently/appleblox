# Original AppleBlox screenshot parity

Compared against all seven images in the [upstream README gallery](https://github.com/AppleBlox/appleblox#gallery). Checked items mean implemented; runtime acceptance work is tracked separately below.

- [ ] Server-location lookup and “Server Joined” notifications
- [ ] Bloxstrap SDK compatibility
- [ ] Game-controlled Discord presence
- [x] Independent Discord play-time toggle — defaults on, preserves existing behavior
- [ ] Separate Discord game-activity visibility toggle
- [ ] Discord game artwork and creator attribution
- [x] Return to Roblox’s website after the last Player closes — optional, defaults off
- [x] Automatically exit AppleBlox after the last Player closes — optional, defaults off; saves tracked history and stays open during file/launch/install operations
- [ ] Improve and verify multiple-instance support — standard macOS new-instance request exists
- [ ] FPS unlock control
- [ ] Lighting-technology selection
- [ ] Voxel-shadow toggle
- [ ] Separate graphics-quality and render-distance controls
- [ ] Visual-effects toggle
- [ ] Review missing graphics API options — Default, Metal, and OpenGL are implemented
- [ ] Visual FastFlag rows with value editing and enable/disable switches
- [ ] FastFlag search
- [ ] FastFlag selection and bulk removal
- [ ] Review original profile types and flag compatibility — named/per-game profiles, JSON editing, import/export already exist
- [ ] Legacy Resolution mode for mods
- [ ] Mod installation guide and community links
- [ ] Mods-folder rescan — explicit pack imports already exist
- [ ] Live Discord display verification

## Acceptance checks

- [x] Both Player-close toggles migrate from older settings as off and persist independently.
- [ ] Live Player-close verification: return-to-website alone, exit-launcher alone, both together, and multiple Player instances.
- [ ] Confirm launcher remains open during an in-progress operation and when final history saving fails.
- [ ] Verify in-game icon recoloring and authenticated account switching.

The Appearance, Misc, and Info page contents were not shown in the gallery and need a separate source audit. The online Workshop, server-region selection, background updates while the launcher is closed, and native self-updating also remain outside this screenshot checklist. See README.md for implemented functionality and limitations.
