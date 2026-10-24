# AppleBlox Native — developer guide

A native macOS 14+ app developed inside the AppleBlox fork. The original Svelte/Neutralino implementation remains available at the repository root. AppleBlox's GPL-3.0 license and attribution continue to apply.

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

The native palette is derived directly from `frontend/src/theme.css`: rose primary `hsl(346.19, 64.65%, 42.16%)` (`#B12646`), neutral backgrounds (`#171717` / `#E6E6E6`), and the original card and foreground colors. Glass retains some translucency, so composited window pixels vary with the desktop.

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
- Create, edit, select, delete, import, and export named engine profiles. Presets cover automatic/Metal/OpenGL rendering, graphics quality, textures, fractional-scaling resolution, and gray sky. Custom JSON overrides presets and validates keys/types against the inherited AppleBlox local-client allowlist. Roblox may ignore flags depending on client version.
- Apply a profile now or opt into applying it before launch. Applying requires Roblox to be closed and replaces `Contents/MacOS/ClientSettings/ClientAppSettings.json`. The actor-backed file service stores the exact original bytes (or original absence) in `engine-backups/` before writing. Repeated applies preserve that original. Restore returns to those bytes and disables automatic application. Outside edits, symlinks, and corrupt backups block changes instead of being overwritten. File permission errors are surfaced; the app does not request administrator privileges.
- Save validated settings atomically. Invalid existing settings are preserved and block saving until moved aside and the app restarted.

Native settings live in `~/Library/Application Support/AppleBlox Native/native-settings.json`. Set `APPLEBLOX_NATIVE_DATA_DIR` to isolate test/demo data. Original AppleBlox engine-profile JSON files can be imported from Integrations. Other legacy preference panels are not automatically migrated.

## Mods, accounts, updates, and integrations

- **Content mods:** Import resource folders beginning with `content/`, `PlatformContent/`, or `ExtraContent/`. Toggle individual packs, apply explicitly or before fresh launches, and restore original resources. Textures, sounds, fonts, and JSON are supported; meshes, scripts, executables, symlinks, and conflicting replacements are rejected. Apply stages a complete resource tree and rolls back a failed replacement. Resource digests detect outside edits or a changed backup. Removed library entries keep their imported files in the Mods folder for recovery.
- **Roblox icon color:** Choose presets or a custom six-digit hex color from Mods → Icon Color. The app generates COLR/CPAL color tables for Player’s Regular and Filled BuilderIcons fonts, preserving their outlines and font-family metadata. The generated three-file pack starts disabled; enable it and Apply Mods when Player is closed. Enabling one generated icon-color pack disables the other generated color packs. Normal mod conflict detection and resource backup/restore apply. Only icons rendered through this font family are affected. Generation reads Player files without changing them; corrupt/missing fonts, unsupported family definitions, and symlinked sources stop generation. Actual in-game appearance still needs acceptance testing with Roblox.
- **Custom fonts:** Select a TTF/OTF font to build a mod that rewrites Roblox font-family asset references while preserving face weights/styles. Apply it through Mods. Enable only one font pack at a time.
- **Roblox updates:** Check Roblox LIVE, download the architecture-specific Player archive, validate archive paths, reject symlinks, verify the exact Player version and Roblox signing team, then replace the selected installation. The previous application is retained beside the new one. Old engine/mod backups are archived instead of reused for a different installation. Downloads can be cancelled. Optional automatic checks/installations run hourly while AppleBlox is open and Player is closed; no LaunchAgent is installed. There is no Studio/channel/version-pinning UI.
- **Accounts:** Sign in directly through a private Roblox website view (native WebView on macOS 26+, WKWebView fallback on earlier systems), or explicitly import Player’s current login. Sessions are validated with Roblox and stored in macOS Keychain, separately from public account metadata. Selecting an account and launching while Player is closed writes its session to Player’s CFNetwork cookie file with mode 0600; the original login is backed up in Keychain for restore. Credentials are never placed in command arguments, diagnostics, JSON settings, or history. Restoring/removing a local session does not revoke sessions on other devices. Real authenticated switching still needs user acceptance testing.
- **Discord presence:** Opt-in native Unix-socket IPC, using the original AppleBlox application ID by default (editable for fork branding). Handles handshake, ping/pong, acknowledgment, reconnection, and clearing on quit/disable. Publishes the current game name and public game-page link. Discord desktop must be running; no Discord token is collected. Live display still needs acceptance testing with a running Discord client.
- **Activity/history:** Opt-in log tailing detects new joins, returns to the desktop app, and log rotation. Stores up to 200 local sessions, with game names resolved through public Roblox endpoints. History can replay saved place IDs. Existing log lines are ignored at the initial baseline; credentials, raw log lines, server IPs, and job IDs are not recorded. Optional quit-after-game behavior requests a graceful Player exit.
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

`bash test.sh` runs 42 tests covering the original configuration/installation checks plus engine validation and recovery, mod transactions/conflicts/outside edits/symlinks, custom font-family rewrites, legacy profiles, game mappings, release/archive validation, binary cookie encoding/decoding with synthetic credentials, log tailing/rotation, ordered history persistence, and a local mock Discord IPC handshake/activity/ping exchange. No real account credentials, Keychain records, or installed Roblox resources are used in these tests.

The public LIVE endpoint and a real architecture-specific Roblox archive have also been checked; the archive passed extraction, bundle/version validation, and Roblox signature validation in a temporary workspace. The install/replacement transaction and previous-app retention were verified using temporary fixture applications; no system/user Player installation was changed. UI checks cover compact navigation, account sign-in loading and missing-session validation, live version checking, mod import, and generation of a custom-font pack from real Player font definitions. Authenticated switching, real Discord display, browser-default changes, and simultaneous Player behavior require live user acceptance testing.

## GitHub releases

The fork is [Belligerently/appleblox-native](https://github.com/Belligerently/appleblox-native). App-related branch pushes build universal ZIP/DMG packages: stable versions on `main` start at `0.1.0`, while other branches publish `-dev.N` prereleases. See [the release guide](../.github/RELEASING.md) for commit selection, retries, versioning, and current signing limitations.

The original Workshop catalog endpoint (`https://marketplace.appleblox.com/api/v1/mods`) returned HTTP 404 during implementation. Online Workshop browsing and downloads remain unported; no insecure endpoint fallback is used.
