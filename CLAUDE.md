# AppleBlox Native — repository guidance

## Native fork development

This repository is `Belligerently/appleblox-native`, an independent SwiftUI fork of AppleBlox. The native app is developed under `native/` on `swiftui-foundation` (PR #1) until merged into `main`. The root README describes the fork. Do not use the legacy Bun build, package version, or upstream download URLs for native releases.

Native commands, from the repository root:

```sh
bash native/test.sh
bash native/build.sh
APPLEBLOX_UNIVERSAL=1 bash native/build.sh
python3 -m unittest discover -s .github/scripts -p 'test_*.py' -v
```

Use full Xcode 27 or later. Native source uses Swift 6 language mode and supports macOS 14+ at runtime. SwiftUI/AppKit state belongs on `MainActor`; core file services and concurrency boundaries are documented in `native/README.md`. Keep the native data store separate from legacy preferences and preserve the original GPL-3.0 license and logo attribution.

The native CI workflow is `.github/workflows/build.yml`; version policy is in `.github/RELEASING.md` and `.github/scripts/release_config.json`. Main produces stable versions starting at 0.1.0; other branches produce prereleases. Documentation-only commits do not produce native releases. Packages are ad-hoc signed, without notarization.

Before the native PR is merged, the native paths above exist only on its development branch. `docs/LEGACY.md` identifies inherited source and credits.

## Repository layout

- `native/`: active SwiftUI app, tests, assets, and build scripts.
- `legacy/`: self-contained inherited Svelte/Neutralino app, including its dependency manifests, build configuration, tests, screenshots, license copy, and historical documentation. Run legacy commands from that directory; see [its guidance](legacy/CLAUDE.md).
- `.github/`: active repository automation and native fork branding.
- `docs/LEGACY.md`: migration-reference overview and upstream credits.

The native build does not read or package files from `legacy/`. Keep application-specific legacy files inside that folder when retaining upstream reference code.
