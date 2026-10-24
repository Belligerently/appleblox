# AppleBlox Native — SwiftUI migration

A native macOS 14+ app developed inside the AppleBlox fork. The original Svelte/Neutralino implementation remains available at the repository root. AppleBlox's GPL-3.0 license and attribution continue to apply.

## Build and run

Requires macOS 14+ and Xcode with a Swift 6 toolchain. No third-party Swift dependencies. The scripts prefer `/Applications/Xcode.app` when standalone Command Line Tools are selected, without changing the system selection. Override with `DEVELOPER_DIR` if needed. Current SDK 27 Command Line Tools omit the SwiftUI macro plugin needed by `@State`.

```sh
cd native
bash build.sh
open 'dist/AppleBlox Native.app'
```

Open `native/Package.swift` in Xcode to edit the package. The bundle script supplies the app metadata and a local ad-hoc signature. This preview is not notarized or prepared for public distribution.

```sh
bash test.sh
```

Swift language mode is explicitly 6, with complete concurrency checking. There is no default actor isolation or upcoming-feature override. UI state and AppKit operations are isolated to `MainActor`; the core uses Sendable value types. Launching uses the async NSWorkspace API and targets the selected Roblox Player bundle directly.

## Compact Liquid Glass interface

The default window is 660 × 460 points (minimum 580 × 390), with top navigation instead of a sidebar. On macOS 26+, navigation and launch controls use native Liquid Glass. Earlier systems use material and bordered-control fallbacks. The window uses native translucency on macOS 15+ and respects Reduce Transparency and Reduce Motion. Game rows, editing sheets, installation details, and diagnostics use compact spacing.

The native palette is derived directly from `frontend/src/theme.css`: rose primary `hsl(346.19, 64.65%, 42.16%)` (`#B12646`), neutral backgrounds (`#171717` / `#E6E6E6`), and the original card and foreground colors. Glass retains some translucency, so composited window pixels vary with the desktop.

Tab selection uses one moving highlight; page changes crossfade in a fixed content area. Navigation from Quick Play follows the same path as the tabs. Refresh feedback and launch-progress changes animate locally; saved game rows animate on insert/remove. Reduce Motion disables these custom animations.

## Fork branding

The original AppleBlox geometry is preserved exactly: tilted square, square opening, bite, and leaf. The body retains the original rose gradient (`#CE0D3E` → `#850828`); the leaf uses a blue gradient (`#58BFFF` → `#0A84FF`) to distinguish this fork. The macOS icon tile has subtle blue and rose lighting. There is no fork badge or fork-shaped cutout. Original logo credit: @typeofnull, as credited by AppleBlox. The inherited GPL-3.0 license continues to apply.

- `Resources/Branding/AppleBloxFork.svg` is the reusable vector mark.
- `ForkLogoGeometry.swift` shares the mark geometry between the SwiftUI view and the icon renderer.
- `AppleBloxForkLogo.swift` draws the mark at native resolution in the header and launcher.
- `Scripts/RenderBranding.swift` generates a transparent PNG and a complete icon set. The bundle script converts it to ICNS for the Dock and Finder. Generated assets live under `.build/branding/`.

## Available in this milestone

- Detect Player in system/user Applications folders or through Launch Services; select another app with a native file picker.
- Validate the exact Player bundle identifier and executable, excluding Studio.
- Open Roblox, with an error alert if the installation disappears or Launch Services rejects the request.
- Create, edit, and remove saved game shortcuts using a numeric place ID. Play sends a deep link to the selected Player; joining depends on Roblox authentication and game availability.
- Inspect the detected version/path, reveal the app, open Roblox logs, and read session activity.
- Save validated settings atomically. Invalid existing settings are preserved and block saving until moved aside and the app restarted.

Native settings live in `~/Library/Application Support/AppleBlox Native/native-settings.json`. Set `APPLEBLOX_NATIVE_DATA_DIR` to isolate test/demo data. Legacy AppleBlox settings are not imported yet.

## Migration map

| Existing source | Native equivalent / next step |
| --- | --- |
| `roblox/path.ts`, `path-manager.ts` | `AppleBloxCore/RobloxInstallation.swift`, `LauncherModel.refresh()` |
| `roblox/instance.ts` launch via `open -a` | `LauncherModel.launch()` using NSWorkspace |
| Svelte main window | Compact SwiftUI navigation, Liquid Glass controls, and native forms |
| File-backed settings | Separate typed JSON store with validation and atomic saves |
| `roblox/fflags.ts`, `mods.ts` | Pending: supported settings, backup and restore |
| `roblox/downloader.ts`, `updates.ts` | Pending: installation/update lifecycle |
| `tools/rpc.ts`, `roblox/events/` | Pending: presence and event tracking |
| `roblox/delegate.ts`, bootstrap sidecar | Pending: URL registration/delegation; this preview does not claim Roblox URL schemes |

This is the first working slice of the migration. FastFlags, mods, automatic updates, multi-instance support, account management, Discord presence, and external deep-link interception are not implemented. Game shortcuts are not engine-setting profiles. Running status refreshes manually. The native app does not edit the Roblox bundle or install anything.

## Verification

Core tests cover numeric ID validation, settings round trips, corrupt/unsupported settings, duplicate IDs, non-destructive validation failures, app bundle validation, and isolated data directories. UI and Launch Services behavior should also be checked on macOS with an installed Roblox Player. Do not use Roblox credentials or authentication tickets in test fixtures.
