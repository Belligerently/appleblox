# AppleBlox Native — developer guide

A native macOS 14+ app developed inside the AppleBlox fork. The original Svelte/Neutralino implementation is self-contained under `legacy/` at the repository root. AppleBlox's GPL-3.0 license and attribution continue to apply.

## Build and run

Requires macOS and full Xcode 27 or later with its macOS SDK and Swift toolchain. The resulting app supports macOS 14+. No third-party Swift dependencies. The scripts prefer `/Applications/Xcode.app` when standalone Command Line Tools are selected, without changing the system selection. Override with `DEVELOPER_DIR` if needed. Current SDK 27 Command Line Tools omit the SwiftUI macro plugin needed by `@State`.

```sh
cd native
bash build.sh
open 'dist/AppleBlox Native.app'
```

Open `native/Package.swift` in Xcode to edit the package. The bundle script supplies the app metadata and a local ad-hoc signature. Automated development releases use the same ad-hoc signature and are not Apple notarized.

```sh
bash test.sh
```

Swift language mode is explicitly 6, with complete concurrency checking. There is no default actor isolation or upcoming-feature override. UI state and AppKit operations are isolated to `MainActor`; the core uses Sendable value types. Launching uses the async NSWorkspace API and targets the selected Roblox Player bundle directly.

## Compact Liquid Glass interface

The default window is 660 × 460 points (minimum 580 × 390), with top navigation for Launcher, My Games, Engine, and Mods, plus a More menu for Accounts, Integrations, History, Installation, Diagnostics, Appearance, and About instead of a sidebar. On macOS 26+, navigation and launch controls use native Liquid Glass. Earlier systems use material and bordered-control fallbacks. The window uses native translucency on macOS 15+ and respects Reduce Transparency and Reduce Motion. Game rows, editing sheets, installation details, and diagnostics use compact spacing.

The native palette is derived directly from `legacy/frontend/src/theme.css`: rose primary `hsl(346.19, 64.65%, 42.16%)` (`#B12646`), neutral backgrounds (`#171717` / `#E6E6E6`), and the original card and foreground colors. Glass retains some translucency, so composited window pixels vary with the desktop.

Tab selection uses one moving highlight; page changes crossfade in a fixed content area. Navigation from Quick Play follows the same path as the tabs. Refresh feedback and launch-progress changes animate locally; saved game rows animate on insert/remove. Reduce Motion disables these custom animations.

## Fork branding

The original AppleBlox geometry is preserved exactly: tilted square, square opening, bite, and leaf. The body retains the original rose gradient (`#CE0D3E` → `#850828`); the leaf uses a blue gradient (`#58BFFF` → `#0A84FF`) to distinguish this fork. The main macOS app icon uses a neutral dark charcoal tile, with the rose body and blue leaf as the central mark. The bundle names this icon explicitly, and the app sets its Dock icon from that same bundled resource at startup. There is no fork badge or fork-shaped cutout. Original logo credit: @typeofnull, as credited by AppleBlox. The inherited GPL-3.0 license continues to apply.

- `Resources/Branding/AppleBloxFork.svg` is the reusable vector mark.
- `ForkLogoGeometry.swift` shares the mark geometry between the SwiftUI view and the icon renderer.
- `AppleBloxForkLogo.swift` draws the mark at native resolution in the header and launcher.
- `Scripts/RenderBranding.swift` generates a transparent PNG and a complete icon set. The bundle script converts it to ICNS for the Dock and Finder. Generated assets live under `.build/branding/`.

## Launcher and engine features

- Detect Player in system/user Applications folders or through Launch Services; select another app with a native file picker.
- Validate the exact Player bundle identifier and executable, excluding Studio.
- Open Roblox, with an error alert if the installation disappears or Launch Services rejects the request.
- Create, edit, and remove saved game shortcuts using a numeric place ID. Play sends a deep link to the selected Player; joining depends on Roblox authentication and game availability.
- Inspect the detected version/path, reveal the app, open Roblox logs, and read session activity. Running status follows workspace launch/termination notifications; Quit Roblox requests a graceful exit from Player windows.
- Create, edit, select, delete, import, and export named engine profiles. Presets cover automatic/Metal/OpenGL rendering and an experimental inherited Vulkan request, textures, fractional-scaling resolution, gray sky, voxelizer shadow control, and independent quality/CSG detail distance. The quality separation switch retains its level while disabled; old explicit quality overrides migrate enabled. CSG distance presets (50/100/250/1000 studs) affect mesh detail, not streamed object loading. The shadow toggle pauses the voxelizer; it does not remove all shadow types. Vulkan is a request using the original flag pair, not an added macOS backend; Roblox may ignore it or fall back. Custom JSON overrides presets and validates keys/types against the inherited AppleBlox local-client allowlist. Roblox may ignore flags depending on client version.
- Edit profiles with Presets, Flags, and JSON tabs. The visual flag list supports Boolean/integer editing, allowlist-based addition, name/value search, enabled/disabled switches, visible-row selection, and bulk removal. Disabled values persist across restarts but are excluded from applied flags and JSON exports; disabling an override lets its preset take effect again. JSON imports replace enabled custom overrides while retaining disabled rows unless an imported key enables them. Invalid imports preserve the draft; invalid saves preserve settings. Cancel discards the complete sheet draft.
- Apply a profile now or opt into applying it before launch. Applying requires Roblox to be closed and replaces `Contents/MacOS/ClientSettings/ClientAppSettings.json`. The actor-backed file service stores the exact original bytes (or original absence) in `engine-backups/` before writing. Repeated applies preserve that original. Restore returns to those bytes and disables automatic application. Outside edits, symlinks, and corrupt backups block changes instead of being overwritten. File permission errors are surfaced; the app does not request administrator privileges.
- Save validated settings atomically. Invalid existing settings are preserved and block saving until moved aside and the app restarted.

Native settings live in `~/Library/Application Support/AppleBlox Native/native-settings.json`. Set `APPLEBLOX_NATIVE_DATA_DIR` to isolate test/demo data. Original AppleBlox engine-profile JSON files can be imported from Integrations. Other legacy preference panels are not automatically migrated.

## Mods, accounts, updates, and integrations

- **Content mods:** Import resource folders beginning with `content/`, `PlatformContent/`, or `ExtraContent/`. Toggle individual packs, apply explicitly or before fresh launches, and restore original resources. Textures, sounds, fonts, and JSON are supported; meshes, scripts, executables, symlinks, and conflicting replacements are rejected. Apply stages a complete resource tree and rolls back a failed replacement. Resource digests detect outside edits or a changed backup. Removed library entries keep their imported files in the Mods folder for recovery. Mods → ••• adds Rescan Library, Scan Results, and a local installation guide with community/support links. Each pack has Show Files to open its imported copy. Scan refreshes counts and validates all registered packs, reports missing/invalid files and case-insensitive resource overlaps, and follows enable/disable changes when displaying active conflicts. Known invalid enabled packs or enabled conflicts block Apply in the UI; apply-time validation still checks the actual files. Disabled invalid packs are reported but do not block other packs. Scan never changes Player or backups. Folder read errors are reported; removed/unregistered folders are not rediscovered. Fix a pack and rescan to clear its findings. Import new packs explicitly.
- **Legacy Resolution:** Mods offers an opt-in low-resolution launch mode for older mods. Fresh launches pass `-AppleMagnifiedMode YES` as arguments, preserving any game/launch URL as one argument without using a shell or editing the app bundle. A running Player requires quitting first or explicitly requesting a new instance; this guard runs before launch-time profile/mod application. Default launches retain normal URL handling. Voice chat may not work in this mode; live low-resolution/game-join/voice behavior remains unverified.
- **Roblox icon color:** Choose presets or a custom six-digit hex color from Mods → Icon Color. The app generates COLR/CPAL color tables for Player’s Regular and Filled BuilderIcons fonts, preserving their outlines and font-family metadata. The generated three-file pack starts disabled; enable it and Apply Mods when Player is closed. Enabling one generated icon-color pack disables the other generated color packs. Normal mod conflict detection and resource backup/restore apply. Only icons rendered through this font family are affected. Generation reads Player files without changing them; corrupt/missing fonts, unsupported family definitions, and symlinked sources stop generation. Actual in-game appearance still needs acceptance testing with Roblox.
- **Custom fonts:** Select a TTF/OTF font to build a mod that rewrites Roblox font-family asset references while preserving face weights/styles. Apply it through Mods. Enable only one font pack at a time.
- **Roblox updates:** Check Roblox LIVE, download the architecture-specific Player archive, validate archive paths, reject symlinks, verify the exact Player version and Roblox signing team, then replace the selected installation. The previous application is retained beside the new one. Old engine/mod backups are archived instead of reused for a different installation. Downloads can be cancelled. Optional automatic checks/installations run hourly while AppleBlox is open and Player is closed; no LaunchAgent is installed. There is no Studio/channel/version-pinning UI.
- **Accounts:** Sign in directly through a private Roblox website view (native WebView on macOS 26+, WKWebView fallback on earlier systems), or explicitly import Player’s current login. Sessions are validated with Roblox and stored in macOS Keychain, separately from public account metadata. Selecting an account and launching while Player is closed writes its session to Player’s CFNetwork cookie file with mode 0600; the original login is backed up in Keychain for restore. Credentials are never placed in command arguments, diagnostics, JSON settings, or history. Restoring/removing a local session does not revoke sessions on other devices. Real authenticated switching still needs user acceptance testing.
- **Bloxstrap SDK:** Separate opt-in SDK and game-control settings support the original app’s `SetRichPresence` messages: persistent text patches, clear/reset, start/end timers, and large/small Roblox asset thumbnails. User visibility/artwork/time settings take precedence. SDK state stays in memory and resets on game leave/change, Player exit, or disabled game control. Thumbnail lookups are cookie-free, asynchronous, bounded, cached, and restricted to numeric Roblox asset IDs and HTTPS Roblox CDN results. Unknown commands and `SetLaunchData` are ignored; server invites/deeplinks are not implemented. See [the protocol reference](https://bloxstraplabs.com/wiki/developers/bloxstraprpc/).
- **Discord presence:** Opt-in native Unix-socket IPC, using the original AppleBlox application ID by default (editable for fork branding). Handles handshake, ping/pong, acknowledgment, reconnection, and clearing on quit/disable. More → Integrations offers independent current-game, elapsed-time, artwork/creator, and game-page-button toggles. Current game, time, and button default on; artwork/creator defaults off, including when older settings are migrated. Hiding the current game suppresses its name, creator, artwork, and game-page link while allowing the timer to remain visible. Buttons open public game pages; they are not server joins or Discord invitations. Artwork/creator uses matching public Roblox metadata and HTTPS Roblox CDN thumbnails; absent/offline data falls back to the session name. Metadata uses the existing cookie-free catalog/cache, runs separately from log processing, cancels/discards obsolete sessions, and retries failures at most once per minute. The appearance artwork setting only controls local library rows; Discord artwork has its own explicit toggle. Changed payloads refresh on the next service tick (normally within two seconds); unchanged payloads are throttled. Discord desktop must be running; no Discord token is collected. Live display still needs acceptance testing with a running Discord client. Payload fields follow [Discord’s RPC activity format](https://docs.discord.com/developers/topics/rpc#setactivity).

- **Activity/history:** Opt-in log tailing detects new joins, returns to the desktop app, and log rotation. Stores up to 200 local sessions, with game names resolved through public Roblox endpoints. History can replay saved place IDs. Existing log lines are ignored at the initial baseline; credentials, raw log lines, server IPs, and job IDs are not recorded. Optional quit-after-game behavior requests a graceful Player exit. More → Integrations also offers “Quit AppleBlox when Roblox closes,” off by default. It exits only after the last Player instance closes, flushes tracked history first, and rechecks that no Player restarted. It stays open during launch/install/file operations or if the final history save fails. Opening AppleBlox without a running Player does not trigger quitting. An independent “Return to Roblox’s website when Player closes” toggle opens the fixed HTTPS Roblox homepage in the default browser after the last Player closes. It defaults off, does not trigger on startup or unrelated app exits, and opens the website before optional launcher termination. A browser handoff failure keeps AppleBlox open with an error.
- **Launch links:** The bundle advertises `appleblox-native://play?placeId=…`, `roblox`, and `roblox-player` schemes. Roblox schemes have alternate handler rank; use Integrations to explicitly choose AppleBlox or Roblox as the default through the macOS NSWorkspace API. Incoming requests require review and forward directly to the selected Player bundle, preventing a handler loop. Tokens in browser launch URLs are not logged.
- **Game profiles/migration:** Assign an engine profile to each saved game. It applies before a fresh Player session even when global automatic application is off; an already-running Player needs a restart to pick up changed flags. Import one or more original AppleBlox profile-wrapper JSON files, including game mappings. The import is all-or-nothing for native settings and rejects enabled unsupported flags.
- **Instances:** An optional macOS new-application-instance request is available. Roblox can still enforce its own single-instance rules, and processes share the same Player login. No semaphore bypass or private display API is used.

The native app does not yet reproduce the original online mod workshop, server-region picker, a full online game browser, custom app-icon presets, background updating while AppleBlox is quit, or all legacy appearance/preferences. Multi-instance behavior and FastFlag effects remain subject to the Roblox client. This is a functional native migration preview, not complete one-for-one parity with every original panel.

## Appearance and game library

More → Appearance saves System/Light/Dark theme selection, an app-specific reduced-animation preference, solid background controls, and an artwork toggle. macOS Reduce Motion and Reduce Transparency remain effective even if the corresponding app preference is off. These settings are added to the existing native settings file with backward-compatible defaults; the original rose palette and fork logo are retained.

My Games accepts numeric place IDs or canonical HTTPS Roblox `/games/…` URLs, including localized URLs. Short `/share` links are not resolved automatically. Query parameters such as private-server codes are discarded: saved entries always launch the public place ID. Names are suggested after a brief typing delay; custom titles and engine-profile assignments are preserved, and manual entry/save works without a successful lookup.

Saved games have compact artwork rows, name/place-ID search, saved-order/name sorting, a public Roblox page link, and individual metadata refresh. Only the saved library is searched; this does not search Roblox’s online catalog. Roblox’s public place-to-universe, game-details, and thumbnail endpoints supply names, creators, and icons without account cookies. Non-completed or unavailable icons use a placeholder. Metadata lives in `game-details-cache.json` beside native settings, is fresh for 30 minutes, and retains up to 200 entries for offline text fallback; image caching follows system HTTP cache behavior. Turning artwork off stops automatic row lookups and image loading; the Add/Edit editor can still look up a public game name.

New tests cover old/partial appearance settings, invalid settings preservation, accepted/rejected game links, API response handling, thumbnail placeholders and host validation, cache reuse, offline fallback, and lookup cancellation. Existing shortcuts and their IDs remain unchanged.

## Migration map

| Existing source | Native implementation |
| --- | --- |
| `roblox/path.ts`, `path-manager.ts` | `RobloxInstallation.swift`, `LauncherModel.refresh()` |
| `roblox/instance.ts` | NSWorkspace launching, running notifications, optional new-instance requests |
| `roblox/fflags.ts` | Engine profiles, presets, allowlist validation, JSON import/export, backup/restore |
| `roblox/mods.ts` | `ContentMods.swift`, Mods UI, custom font generation, transactional resource replacement |
| `roblox/downloader.ts`, `updates.ts` | `RobloxUpdates.swift`, signature-verified install and in-app automatic updates |
| `roblox/accounts.ts`, `tools/binarycookies.ts` | `AccountVault.swift`, `PlayerCookies.swift`, private web sign-in |
| `tools/rpc.ts`, `roblox/events/` | `DiscordPresence.swift`, `GameActivity.swift`, local play history |
| `roblox/delegate.ts` | Opt-in NSWorkspace scheme handling and reviewed direct URL forwarding |
| Legacy engine-profile files | `LegacyEngineProfile`, Integrations import, per-game profile bindings |

## Verification

`bash test.sh` runs 90 tests covering the original configuration/installation checks plus visual flag editing/migration, disabled override persistence, JSON import transactions, search/bulk removal, quality/distance/shadow/renderer migration and precedence, Legacy Resolution launch planning and fresh-instance guards, engine validation and recovery, mod transactions/conflicts/outside edits/symlinks, custom font-family rewrites, legacy profiles, game mappings, release/archive validation, binary cookie encoding/decoding with synthetic credentials, log tailing/rotation, SDK patch parsing/clear/reset, Unicode/timestamp bounds, thumbnail validation/caching/cancellation, all visibility combinations, ordered history persistence, and a local mock Discord IPC handshake/activity/ping exchange with visibility controls, late metadata, and duplicate suppression. No real account credentials, Keychain records, or installed Roblox resources are used in these tests.

The public LIVE endpoint and a real architecture-specific Roblox archive have also been checked; the archive passed extraction, bundle/version validation, and Roblox signature validation in a temporary workspace. The install/replacement transaction and previous-app retention were verified using temporary fixture applications; no system/user Player installation was changed. Isolated Mods UI checks verify rescan counts, invalid-pack/conflict feedback, Apply blocking and resolution, repaired files, per-pack Finder access, and guide/support link layout. No Player resources were applied during these UI checks. Isolated Discord/SDK UI checks verify new controls default off, dependent disabled states, compact SDK layout, and persistence after reopening; actual Discord display remains pending. UI checks also cover an isolated visual-editor profile: adding/searching/editing rows, disabled values, filtered bulk removal, invalid integer/JSON recovery, and Cancel preserving saved settings. Graphics/Mods UI checks cover experimental Vulkan help, independent quality/distance selection, retained disabled values, voxel control, Save/Cancel, summary fields, Legacy Resolution help/layout, and persistence after restart. No engine settings were applied to the installed Player. UI checks cover compact navigation, account sign-in loading and missing-session validation, live version checking, mod import, and generation of a custom-font pack from real Player font definitions. Authenticated switching, real Discord display, browser-default changes, and simultaneous Player behavior require live user acceptance testing.

## GitHub releases

The fork is [Belligerently/appleblox-native](https://github.com/Belligerently/appleblox-native). App-related branch pushes build universal ZIP/DMG packages: stable versions on `main` start at `0.1.0`, while other branches publish `-dev.N` prereleases. See [the release guide](../.github/RELEASING.md) for commit selection, retries, versioning, and current signing limitations.

The original Workshop catalog endpoint (`https://marketplace.appleblox.com/api/v1/mods`) returned HTTP 404 during implementation. Online Workshop browsing and downloads remain unported; no insecure endpoint fallback is used.

## Feature parity checklist

See [PARITY.md](PARITY.md) for the screenshot audit, completed ports, and remaining acceptance checks.

## Maintenance

More → Diagnostics → ••• offers Copy Diagnostics and Clear Game Details Cache. The copied report contains only app/macOS/Player versions, architecture, running/readability states, library/cache counts, and backup-availability flags. It excludes account/session data, game/profile names, local paths, URLs, raw logs, and activity messages; copying is local and does not submit a report.

Cache clearing requires confirmation and clears saved names, creators, and thumbnail links in memory and game-details-cache.json. Older in-flight requests are invalidated before they can refill it. Disk-write failures retain the existing cache. Saved games, engine profiles, mods, backups, accounts, history, and Player files are unchanged. macOS HTTP/image caches are unaffected; future lookups can refill public details. Appearance-only reset remains under More → Appearance.
