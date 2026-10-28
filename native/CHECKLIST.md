# AppleBlox Native completion checklist

Updated 2026-10-28. This is the combined working checklist; [PARITY.md](PARITY.md) contains the screenshot comparison and test evidence, and [SOURCE-PARITY.md](SOURCE-PARITY.md) contains the original Appearance/Misc/About source audit.

A checked implementation item means native code exists, not that every real-game scenario has passed. Screenshot status is still **21 implemented (including experimental behavior), two unavailable flag controls, and one live Discord check pending**. That denominator does not cover the whole original app.

## Implemented native functionality

- [x] Compact SwiftUI shell, original AppleBlox palette/geometry, Liquid Glass fallbacks, accessibility preferences and offline guide/credits.
- [x] Player discovery, installation selection, launch/game links and process-aware instance controls.
- [x] Saved games, public metadata/artwork, local search/sorting, caching and per-game profile assignments.
- [x] Engine presets, renderer requests, independent quality/detail distance, textures, voxel controls, global/game profiles, reviewed original-profile imports and backup/restore.
- [x] Visual FastFlag rows, enabled/disabled state, search, bulk selection/removal and JSON import/export.
- [x] Content/font/interface-color mods, resource imports, rescanning/conflict reporting, installation guide and backup/restore.
- [x] Private account sign-in/import, Keychain session storage, account selection and original-login restoration.
- [x] Optional history, Discord presence/SDK controls, artwork/timer/privacy options, server-location lookup and joined-server notifications/sounds.
- [x] Optional website return and launcher exit after the last Player closes.
- [x] Verified Roblox updates with previous-installation preservation while the launcher is open.
- [x] Native JSON palette library with editing/previews/import/export/reload/reveal/removal/default recovery.
- [x] Saved Dock-icon library with original styles, custom ICNS imports, confirmed application and default recovery.
- [x] Safe persistent launcher events, fixed diagnostics, reviewed local support ZIP and scoped cache cleanup.
- [x] Reviewed reset with typed confirmation, drained writers, private native-data archive, preserved Player backups and scoped credential cleanup.

## Remaining functionality or explicit scope decisions

- [ ] Finder app-icon customization. The system call stalled during QA; only Dock customization is shipped.
- [ ] Bootstrapper theme library and renderer, including supported XML/ZIP assets, previews, activation, rename, removal, reveal and reload.
- [ ] Decide whether to retain fixed-duration loading/bootstrapper steps; implement and verify if retained.
- [ ] Online mod Workshop/catalog workflow; verify upstream service availability before choosing a compatible implementation or an agreed replacement.
- [ ] Server-region selection, distinct from displaying a joined server's location.
- [ ] Full online experience browser, distinct from the saved-game library.
- [ ] Roblox background updating while AppleBlox is closed, with explicit management of any installed background helper.
- [ ] Native launcher self-updating and update recovery/trust handling.
- [ ] Decide whether a portable full settings-backup workflow is required. A troubleshooting ZIP intentionally omits full configuration; reset recovery is a separate local archive.
- [ ] Decide whether an alternate notification backend is needed after validating native macOS delivery. AppleScript notifications remain unported.
- [ ] Final source-to-native pass over every original page and nested menu, reconciling any omissions into this checklist.

## Platform limitations and native adaptations

- [ ] Record final scope for lighting-technology selection and the general post-processing toggle. Their old flags are absent from the inherited allowlist; do not add ineffective controls or count them as working features.
- [x] Legacy CSS is replaced by the bounded native palette format. It does not provide arbitrary CSS layout/styling or bootstrapper XML rendering.
- [x] Support export uses reviewed, limited diagnostics instead of copying arbitrary configuration/account data.
- [x] Reset archives old native data and backups instead of permanently removing recoverable Player originals.

Unavailable or deliberately replaced behavior must remain documented. It only leaves the remaining scope when the native difference is explicitly accepted; it must not silently become a completed feature.

## Live acceptance still required

- [ ] Normal/game-link launch, multiple-Player creation/reuse/replacement, per-Player actions and last-Player close behavior.
- [ ] In-game graphics requests, CSG/voxel/texture behavior, font/icon recoloring, Legacy Resolution and restore operations.
- [ ] Authenticated account import/switch/original-login recovery and reset cleanup using a dedicated test account; verify unrelated credentials remain intact.
- [ ] Real Discord presence, SDK artwork/text/timers, privacy controls, reconnects, leave/rejoin and ambiguous multi-Player behavior.
- [ ] Actual server-log/provider behavior and macOS notification grant/denial, foreground/background delivery, sound, Focus and teleport suppression.
- [ ] Real FPS/display behavior, supported hardware checks, launch failures, normal quit and display restoration/hotplug cases. A 240 Hz virtual mode is not a guarantee of 240 FPS.
- [ ] Roblox install/update/rollback and restoring applied engine/mod backups after recovering a reset archive.
- [ ] Intel and minimum-supported-macOS runtime acceptance, plus the main supported Apple-silicon configuration.

## Release readiness, separate from feature parity

- [x] Main requires PRs, current branches, resolved review conversations and GitHub Actions plan/validate checks; no bypass actors are configured.
- [x] Main deletion/force pushes and native-v* tag updates/deletion/force pushes are blocked; new native release tags remain allowed.
- [x] Issues, private vulnerability reporting, dependency graph, vulnerability/malware alerts, secret scanning and push protection are enabled.
- [x] Actions default token remains read-only; Actions PR approval is disabled; external workflow runs require approval; allowed third-party actions are restricted.
- [x] Native contribution, security-reporting, PR and issue templates are committed to the development PR.
- [ ] Merge the reviewed native PR when ready. Guidance/templates become the default-branch experience after merge; settings protections are already live.
- [ ] Pin workflow action references to reviewed full commit SHAs before enabling SHA-only policy; keep the current working workflow compatible during migration.
- [ ] Release signing/notarization and first-stable installation/update acceptance.
- [ ] Repeatable benchmark comparison: standard Roblox, AppleBlox with identical settings, then a tuned profile. Record frame consistency and average FPS without assuming an improvement.

## Definition of done

Feature parity is complete when every remaining original feature is implemented and verified, or has an explicitly accepted and documented native/platform difference, and the final source audit has no unexplained omissions. A release candidate additionally needs the live acceptance and release-readiness checks above. Automated tests alone do not close those live checks.
