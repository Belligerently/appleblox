# AppleBlox Native

A compact SwiftUI Roblox launcher for macOS, forked from [AppleBlox](https://github.com/AppleBlox/appleblox).

[![Native build](https://github.com/Belligerently/appleblox-native/actions/workflows/build.yml/badge.svg)](https://github.com/Belligerently/appleblox-native/actions/workflows/build.yml)

The native app lives in [`native/`](native/README.md). It uses Liquid Glass on macOS 26 and later, with fallbacks for macOS 14 and 15. Its rose body and blue leaf preserve the original AppleBlox mark while distinguishing this fork.

## Downloads

[Stable releases](https://github.com/Belligerently/appleblox-native/releases/latest) · [All releases, including development builds](https://github.com/Belligerently/appleblox-native/releases)

Releases contain a universal application for Apple Silicon and Intel, packaged as a DMG and ZIP with SHA-256 checksums. Public native versioning starts at **0.1.0**. Development releases are marked as prereleases and do not replace the stable download.

The automated packages are currently ad-hoc signed, without Apple notarization. Signing with a Developer ID and notarization are separate distribution work still to be configured.

## Native features

- Compact launcher, saved games, per-game engine profiles, and diagnostics.
- Engine flag presets and JSON import/export, with backup and restore.
- Content and font mods, with resource validation and restore.
- Roblox Player installation checks and updates.
- Saved accounts backed by macOS Keychain.
- Optional Discord presence, activity tracking, and local play history.

See the [native documentation](native/README.md) for behavior, limitations, and features still awaiting live acceptance testing. Some original AppleBlox functionality remains to be ported. The inherited Svelte/Neutralino sources remain in this repository for reference; the release workflow builds the native application.

## Build locally

Requires macOS and Xcode with the macOS 26 SDK or later and Swift 6 support.

```sh
cd native
bash test.sh
bash build.sh
open 'dist/AppleBlox Native.app'
```

For the same universal application used in CI:

```sh
APPLEBLOX_UNIVERSAL=1 bash native/build.sh
```

Run that command from the repository root. No third-party Swift packages are required.

## Automatic releases

Every branch push is inspected for native app changes. Each qualifying commit is tested, built, packaged, and released:

- `main`: **0.1.0**, **0.1.1**, **0.1.2**, …
- Other branches: **0.1.0-dev.1**, **0.1.0-dev.2**, … before the first stable release. After 0.1.0, development builds target **0.1.1-dev.1**, and so on.
- Native sources, tests, resources, build scripts, the release automation, and `LICENSE` count as app changes. Markdown-only and legacy web-app changes do not publish releases.
- Multiple app commits in a push are processed individually. Merge commits are compared with their first parent; merged branch history is not replayed by a merge commit.
- A failed commit does not publish a release; other commits in that push are still attempted. Rerunning the failed job retries incomplete builds and skips already published commit/channel pairs.
- Native tags use `native-v0.1.0` and `native-v0.1.0-dev.1`, keeping upstream tags separate. Version metadata is stamped into the packaged app, without bot commits.

The [release guide](.github/RELEASING.md) covers setup and version policy.

## Attribution

AppleBlox Native retains the [GPL-3.0 license](LICENSE). Credit to AppleBlox and its contributors, @typeofnull for the original logo, and [Bloxstrap](https://github.com/pizzaboxer/bloxstrap) for the original project's inspiration. This fork is an independent project.
