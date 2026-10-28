# Original AppleBlox screenshot parity

For the combined remaining-feature and release checklist, see [CHECKLIST.md](CHECKLIST.md).

Compared against all seven images in the [upstream README gallery](https://github.com/AppleBlox/appleblox#gallery). Checked items mean implemented; runtime acceptance work is tracked separately below.

- [x] Server-location lookup and “Server Joined” notifications — independent opt-in settings; public IPv4 only, native macOS alerts, optional sounds, fallback and duplicate/rate suppression
- [x] Bloxstrap SDK compatibility — the original app’s SetRichPresence integration; SetLaunchData/server invites remain unsupported
- [x] Game-controlled Discord presence — opt-in text, timers, large/small asset artwork, persistent patches and clear/reset behavior
- [x] Independent Discord play-time toggle — defaults on, preserves existing behavior
- [x] Separate Discord game-activity visibility toggle — suppresses game name, artwork, creator, and game link together
- [x] Discord game artwork and creator attribution — opt-in, public metadata only
- [x] Optional Discord game-page button — public game page, not a server join/invite
- [x] Return to Roblox’s website after the last Player closes — optional, defaults off
- [x] Automatically exit AppleBlox after the last Player closes — optional, defaults off; saves tracked history and stays open during file/launch/install operations
- [x] Improved multiple-instance handling — process snapshots, new/reused/replaced/unconfirmed launch outcomes, per-Player management, last-Player cleanup, and paused ambiguous game activity; real concurrent-session acceptance remains pending
- [x] Experimental FPS workaround control — default-off temporary 240 Hz mirrored display, single online display, main-thread cleanup and rollback; real display/FPS behavior remains unverified
- [ ] Lighting-technology selection — unavailable under the inherited local-client allowlist; removed from the current original app
- [x] Voxel-shadow toggle — opt-in voxelizer pause; not a promise to disable every shadow type
- [x] Separate graphics-quality and render-distance controls — independent base-quality override and CSG object-detail distances; streamed object loading remains game-controlled
- [ ] Visual-effects toggle — old general post-processing flag is unavailable under the inherited allowlist
- [x] Review missing graphics API options — restored the original Vulkan request as experimental alongside Default, Metal, and OpenGL; runtime backend support remains unverified
- [x] Visual FastFlag rows with value editing and enable/disable switches
- [x] FastFlag search
- [x] FastFlag selection and bulk removal
- [x] Review original profile types and flag compatibility — global/game distinction, reviewed transactional imports, disabled-row preservation/warnings, and selected-profile overlays for assigned-game launches
- [x] Legacy Resolution mode for mods — opt-in fresh-launch arguments, defaults off; voice chat may be unavailable
- [x] Mod installation guide and community links — native folder instructions, fork support, upstream community, GameBanana, and Bloxstrap resource guide
- [x] Mods-folder rescan — validates registered imported copies, refreshes counts, and reports enabled conflicts; new packs still use Import
- [ ] Live Discord display verification — deferred; real Player/Discord acceptance must be performed separately

## Final screenshot-item audit

Status: **21 implemented (some experimental), two unavailable with current Roblox flags, and one live Discord check pending**. This is not a claim that all 24 features passed real-game acceptance.

FPS now has an explicit opt-in confirmation under Engine, separate from engine flag profiles. It uses an independently implemented small Objective-C runtime bridge for the same private `CGVirtualDisplay` approach described by [AppleBlox’s helper](https://github.com/AppleBlox/virtualdisplay). Native launch/ownership/lifecycle logic remains Swift. The bridge checks selector availability without creating a display. It starts only for a fresh Player, requires one online display without existing mirroring, requests a matching Retina/pixel mode at 240 Hz, and keeps the original physical mode for restoration. Failed launches with no remaining Player, last-Player exit, service/window shutdown, manual Stop, and normal app quit request restoration. Failed restoration retains ownership for retry and blocks ordinary app termination. Forced termination, OS changes, hotplug behavior and actual FPS still require live acceptance; a 240 Hz virtual mode does not guarantee 240 FPS. No FPS FastFlag bypass was added. Unit tests use fake display drivers; the real bridge test only probes availability and stops an inactive object.

Player tracking uses process-ID sets instead of a single Boolean. Launch Services results are checked after a short asynchronous settle period and distinguish a new process, a reused existing Player, replacement of prior Players, and an unconfirmed result. Integrations shows a count plus per-Player Show/Quit actions. Closing one of several Players does not trigger last-Player actions. New-instance launching remains best effort with shared Player login; no client restrictions are bypassed. Per-game history, SDK data, server alerts and game-specific Discord fields pause with multiple Players to avoid mixing sessions. Tracking resumes after a new single-Player join, with a fresh baseline. Per-file log cursors retain partial lines and prevent old joins being replayed when the newest file changes. Symlinked logs are ignored.

Lighting selection and a general effects/post-processing toggle are not implemented as inert controls: their old flags are absent from the inherited allowlist, and the [current upstream engine page](https://github.com/AppleBlox/appleblox/blob/main/frontend/src/windows/main/pages/Engine.svelte) no longer includes them. [Bloxstrap’s v2.10.0 notes](https://bloxstraplabs.com/versions/2.10.0/) document the corresponding removed controls. Engine → Feature Support explains these limitations and the experimental FPS/instance behavior. Existing sky, texture, CSG detail and voxelizer options remain distinct supported flag requests. Revisit only if Roblox provides a supported mechanism.

## Server activity and original-profile import cluster

More → Integrations → Game activity adds independent server-location lookup and Server Joined alerts, plus notification sounds. All three migrate/default off. Location lookup sends only the confirmed server’s validated public IPv4 address to `https://ipinfo.io/{address}/json`, through a cookie-free session. It does not request device location, use the provider’s self-IP endpoint, persist raw server addresses, or publish them to Discord/history/diagnostics. The provider receives the normal network connection as well. Private/reserved, malformed, IPv6, and Output-spoofed endpoints are ignored. Location is approximate and service limits/offline errors fall back to a generic connection notice. Requests run outside the log/Discord loop, cache up to 100 addresses in memory, and have a ten-second request cooldown. New connections reset lookup state; obsolete/cancelled results cannot replace a newer session’s display. Status is shown in Integrations.

Notifications request macOS alert/sound permission only when explicitly enabled. Permission denial leaves a newly enabled preference off; macOS Focus, banner and sound settings still govern delivery. Confirmed duplicate connections are ignored, alerts have a ten-second global limit, and leaving/Player exit or disabling alerts cancels pending work. Generic alerts work without location lookup. Foreground banners are supported. Sound uses the system default only when its separate switch is on. Provider contract reference: [IPinfo’s lookup guidance](https://community.ipinfo.io/t/how-to-determine-the-district-for-a-current-ip-address-and-put-it-on-a-map/5669); notification authorization follows [Apple’s API](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).

Original profile imports now distinguish `default` and `game`, inferring missing older type fields from assignments. A review lists profile types, enabled/disabled counts, place IDs, changed assignments, and skipped-row warnings before committing. Supported disabled values are preserved. Unsupported/empty/invalid disabled rows are skipped with warnings; unsupported or invalid enabled rows, duplicate flags/games, unknown types, empty game assignments, or ambiguous same-game batch mappings reject the batch. Global-profile game lists are ignored with a warning. Cancel and failed/stale reviews preserve current settings and source files. Import is bounded to 50 files, 1 MiB each/8 MiB total. Existing saved-game IDs/titles survive reassignment; new globals are not auto-selected.

Imported game profiles include the currently selected profile’s resolved flags, then overlay their enabled flags, matching the original global/game precedence without generating unsupported `_PlaceFilter` flags. The option is also editable in Engine → Edit; choosing the game profile as the main profile uses its own flags without recursion. Game shortcuts and reviewed browser links with a known place ID use the same mapping. Opaque launch URLs without a readable place ID cannot preselect a game profile. Applying still requires a fresh Player and uses the existing backup/restore service. The original allowlist is unchanged; unsupported lighting/FPS/effects remain unimplemented rather than writing ineffective flags.

## Graphics and Legacy Resolution cluster

Engine → Edit → Presets adds an explicit Separate graphics quality and distance switch with remembered base-quality level (1–21), independent CSG object-detail distances (default, 50, 100, 250, 1000 studs), and Disable voxel shadows. Existing profiles with a saved quality override migrate with separation enabled; new profiles leave all new overrides off/default. Disabling separation retains its saved level but emits no quality flag. Distance presets write the four allowlisted CSG detail-switching flags; they do not change experience streaming. Shadow control writes `DFFlagDebugPauseVoxelizer` and depends on the game’s lighting. Enabled custom rows retain precedence, and disabled custom rows do not suppress presets.

The Graphics API picker restores the inherited Vulkan flag pair (`FFlagDebugGraphicsPreferVulkan`, `FFlagDebugGraphicsDisableMetal`) as **experimental**. These options are client flag requests, not installed rendering backends. Mac Player may ignore/fall back from any request. No unsupported lighting/FPS/effect flags were added. The inherited allowlist is unchanged; Roblox can change which flags it honors. References: inherited `legacy/frontend/src/windows/main/ts/roblox/fflags.ts` and [Roblox’s allowlist announcement](https://devforum.roblox.com/t/allowlist-for-local-client-configuration-via-fast-flags/3966569).

Mods adds Legacy Resolution for older mods, default off for new/migrated settings. A fresh launch sends `-AppleMagnifiedMode YES` through Launch Services arguments, with any reviewed game/browser launch URL preserved as a single argument. Normal launches retain URL handling. It does not edit Info.plist or resources. Reusing a running Player is blocked before applying profiles/mods; the user can quit Player or explicitly request a new instance. Voice chat and low-resolution rendering still need live acceptance testing.

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

- [x] Native custom-theme library: versioned JSON, create/edit, light/dark previews, accent and surface colors, apply, reload, import/export, reveal, recoverable removal and original-palette recovery. Legacy CSS/XML are not accepted.
- [x] Reviewed recoverable reset: typed RESET, all Players closed, original login restored first, drained writers, private native-data archive, scoped Keychain cleanup and quit. Player files remain unchanged; native backups stay in recovery. Real authenticated-account cleanup and Player-backup restoration remain live acceptance work.

- [x] Saved Dock-icon library: Native default plus six original AppleBlox styles, local previews, bounded ICNS imports, apply confirmation, recoverable removal, default restoration, and automatic Dock restoration on launch.
- [ ] Finder icon customization. A live system-call stall was reproduced in isolated QA; the final implementation does not call that API or replace bundled icon resources.

- [x] Persistent native event logs and a separate Launcher Logs folder action. One atomic private journal rotates up to four 64 KiB segments; unrelated files are untouched. Timestamps, typed codes, bounded counts and numeric errors only; raw session messages stay in memory.
- [x] Reviewed local support ZIP: exact file previews, optional events, fixed preference summary and diagnostics. Unreadable sources are omitted with notes; no directory scanning, credentials, full settings, raw logs or automatic upload. Existing destinations are never replaced. This is not a settings backup.

- [x] Offline Native Guide, expanded About credits/inspiration, support/community/license resources, and validated Player Contents folder shortcuts.

- [x] Audit original Appearance, Misc, and Info source and nested controls — see [SOURCE-PARITY.md](SOURCE-PARITY.md) for the resulting backlog.

- [x] Optional notification sound control from the original Misc page; alternative AppleScript notifications remain unported.

- [x] Copy a fixed-field diagnostics report without account data, names, paths, URLs, raw logs, or activity messages.
- [x] Clear only the saved game-details cache, including memory/disk entries and obsolete in-flight lookups.
- [x] Appearance-only reset already exists under More → Appearance.

- [x] Public experience browser: explicit unauthenticated searches, paging, duplicate-safe saving, website links and launch through the existing pipeline. Authenticated recents and recorded-server rejoin remain separate gaps.
- [x] Portable settings backup/restore: versioned bounded JSON, profile/game/palette/preferences review, local-account/mod/path preservation, automation disabled on restore, stale-review rejection and private previous-settings recovery.
- [x] Complete inherited route/nested-action source inventory — [FULL-SOURCE-AUDIT.md](FULL-SOURCE-AUDIT.md). Newly identified omissions are recorded in CHECKLIST.md; the audit does not close those features.

## Acceptance checks

- [x] 2026-10-28 cluster: 168 native tests and 12 release tests pass; universal build and signature validation pass. Isolated UI verified empty browser, a live public search, paging, saving with the saved state, local export review/save, restore confirmation gating and a one-game → two-game → restored-one-game round trip. The two-game pre-restore file remains in a 0600 recovery file under a 0700 directory. No Player launched, credentials imported or flags applied. Search failures/cancellation, malformed/oversized/linked backups, stale reviews, existing destinations and first-save/migrated defaults are covered by fixtures. Real-game launch and old-OS/Intel runtime acceptance remain open.

- [x] Profile-editor bounds regression: reproduced the header moving outside the sheet when Presets (430 points) changed to Flags (500 points). All three sections now share a stable compact 430-point sheet, with bounded scrollable content. Isolated UI verified empty/populated Flags, no-results search, JSON error feedback, repeated section changes and Cancel preserving the saved profile. No Player flags were applied.

- [x] Isolated native-theme UI: library loads, existing palette applies, light/dark editor previews fit, unreadable accent is rejected, valid theme saves, and original palette recovers. Core tests cover strict native JSON, import limits, local reload/edit, duplicate names, linked/corrupt files, recoverable removal, migration and support-summary exclusion.
- [x] Isolated reset UI: reviewed counts/folders/recovery path, exact RESET gate, archive plus recovery instructions opening in Finder, dismissal before automatic quit, and a fresh relaunch. Archived fixture backup and both saved themes were verified intact; archive permissions are private. Tests use fake credential cleanup; UI used a new isolated namespace with zero accounts. No real login, Player resources, Discord session or display mode was changed.

- [x] Isolated Dock-icon UI: seven bundled previews, apply confirmation, successful persisted original-style selection, default recovery, responsive dismissal and ordinary quit. Signed resources still verify after these actions. 12 new tests cover imports, duplicate names, invalid/oversized/linked assets, actual bundled image decoding, selection persistence, failure/rollback, corruption recovery, recoverable removal, concurrent mutation and library limits.
- [x] Default app icon refreshed to the original AppleBlox dark burgundy tile/bevel style while retaining the fork’s red-body/blue-leaf logo.

- [x] Isolated support UI: exact README/event previews, cancel, optional event omission, local ZIP save and separate Launcher Logs opening in Finder. Inspected the resulting ZIP (events omitted as chosen, three fixed files, private permissions). 11 new automated tests cover bounded rotation/restart, safe fields, corrupt/oversized/linked journals, unrelated-file preservation, immutable snapshots, exact archive bytes and failure/collision cleanup. No Player, Discord, account or display changes.

- [x] Isolated resources UI: compact About links/layout, offline guide from About and Diagnostics, full credits/inspiration/legacy-stack scrolling, selected Player Contents opening in Finder, and the Installation shortcut layout. Fixture tests validate normal/aliased app paths and reject stale bundles or redirected Contents. No Player was started or resources applied.

- [x] Isolated runtime UI: FPS defaults off, confirmation explains future display changes, Cancel keeps it off, Feature Support sheet is readable, and ordinary quit works with the display inactive. Navigation to the new instance-management UI was interrupted, so live instance controls remain unverified. No Player launch or virtual-display creation occurred.

- [x] Runtime unit checks: new/reused/replaced/exited process outcomes, last-exit policy, simulated FPS ownership/rollback/failed-restoration retry, off-by-default migration, inert native bridge probe/stop, multiple-Player presence privacy, switching log files without replay, preserved partial lines, reset baselines and symlink exclusion.
- [ ] Live runtime acceptance: actual second Player creation/reuse/replacement, per-Player window actions, 240 Hz mode/FPS, normal/failed launch restoration, quit/hotplug behavior, and Discord display. These tests were deliberately deferred; no Player was launched and no real virtual display was created during this phase.

- [x] Isolated server/import UI: off-by-default controls and provider disclosure, permission-not-requested status, disabled sound control, readable global/game import review and warning, Cancel preserving exact settings bytes, imported disabled rows, existing game identity/title preservation, unchanged selected profile/automatic apply, and persisted imported games/lookup preference after restart. Native notification permission was not requested. A recent existing Player log’s server-entry shape matched the parser without sending its IP anywhere.

- [x] Server/profile unit checks: public IPv4/parser bounds, output spoofing, initial-log baselines and partial lines, provider response/IP validation, cached/cancelled/rate-limited lookup behavior, connection deduplication, generic notice/sound formatting, off-by-default migration, profile type/row compatibility, global/game flag precedence, transactional review, stale/conflicting batch rejection, and size bounds.
- [ ] Live server/notification acceptance: actual Player network-log format, provider availability/accuracy, macOS permission grant/denial, foreground/background banners, sounds/Focus, and rapid teleports. No permission changes or live server-IP lookups were made during automated testing.

- [x] Isolated graphics/Mods UI: default states, experimental renderer explanation, independent quality/distance selection, remembered disabled quality value, voxel control, Save/Cancel behavior, summary fields, Legacy Resolution help/layout, and persistence of all four feature settings after restart.
- [x] Graphics/launch unit checks: migration, independent quality/distance settings, custom override precedence, renderer mappings, strict saved-value validation, URL/argument preservation, fresh-launch guard, settings round-trip, and exact fixture backup restoration.
- [ ] Live graphics acceptance: verify actual Vulkan backend/fallback, CSG distance and voxelizer effects, Legacy Resolution rendering, game-link joining, and voice chat on supported Macs.

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

The Appearance, Misc, and Info source audit is complete; [SOURCE-PARITY.md](SOURCE-PARITY.md) lists native equivalents, partial mappings, and the exact remaining implementation gaps. The online Workshop, server-region selection, background updates while the launcher is closed, and native self-updating also remain outside this screenshot checklist. See README.md for implemented functionality and limitations.
