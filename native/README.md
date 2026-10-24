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
| Svelte main window | SwiftUI NavigationSplitView and native forms |
| File-backed settings | Separate typed JSON store with validation and atomic saves |
| `roblox/fflags.ts`, `mods.ts` | Pending: supported settings, backup and restore |
| `roblox/downloader.ts`, `updates.ts` | Pending: installation/update lifecycle |
| `tools/rpc.ts`, `roblox/events/` | Pending: presence and event tracking |
| `roblox/delegate.ts`, bootstrap sidecar | Pending: URL registration/delegation; this preview does not claim Roblox URL schemes |

This is the first working slice of the migration. FastFlags, mods, automatic updates, multi-instance support, account management, Discord presence, and external deep-link interception are not implemented. Game shortcuts are not engine-setting profiles. Running status refreshes manually. The native app does not edit the Roblox bundle or install anything.

## Verification

Core tests cover numeric ID validation, settings round trips, corrupt/unsupported settings, duplicate IDs, non-destructive validation failures, app bundle validation, and isolated data directories. UI and Launch Services behavior should also be checked on macOS with an installed Roblox Player. Do not use Roblox credentials or authentication tickets in test fixtures.
