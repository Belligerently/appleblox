# AppleBlox Native completion checklist

Updated 2026-10-28. This is the combined working checklist; [PARITY.md](PARITY.md) contains the screenshot comparison and test evidence, and [SOURCE-PARITY.md](SOURCE-PARITY.md) contains the original Appearance/Misc/About source audit. [FULL-SOURCE-AUDIT.md](FULL-SOURCE-AUDIT.md) inventories every inherited route and nested action.

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
- [x] Public online experience browser: explicit keyword search, pagination, duplicate-safe save, website opening and existing-pipeline launch. Authenticated recents/server history remain separate below.
- [ ] Roblox background updating while AppleBlox is closed, with explicit management of any installed background helper.
- [ ] Native launcher self-updating and update recovery/trust handling.
- [x] Portable settings backup/restore: reviewed JSON with profiles, disabled flags, saved games/assignments, active palette and preferences; stale-review rejection and private previous-settings recovery. Credentials, paths and resource libraries are excluded.
- [ ] Decide whether full mod/icon/theme-library migration is also required; the implemented settings format is not a complete data archive.
- [ ] Decide whether an alternate notification backend is needed after validating native macOS delivery. AppleScript notifications remain unported.
- [x] Final source-to-native route and nested-menu inventory; findings reconciled below. This closes the audit task, not the newly identified features.
- [ ] Authenticated Roblox recent-game sync and manual refresh/merge with local history.
- [ ] Recorded server/job history, exact-server rejoin and last-server quick rejoin; distinct from Play Again.
- [x] Reviewed local play-history clearing with a private recovery copy, drained writers and a revision barrier against stale saves.
- [x] Desktop .webloc launch shortcut export (general launch or saved game), through native link confirmation and the existing launch pipeline; never overwrites existing files.
- [x] Flag row rename/copy, selected-row JSON clipboard export (including disabled values) and bulk enable/disable; draft-only until Save.
- [x] Local mod image previews (up to three bounded thumbnails) and byte-size/file summaries; scan/reload refreshes edited pack details.
- [ ] Decide first-run onboarding versus the existing guide and opt-in pages.
- [ ] Explicitly accept or implement the remaining source differences: manual cookie entry, whole-disk discovery, force-kill/binary instance patching, developer-only harness, and arbitrary CSS styling.
- [ ] Decide exact-server Discord join support; the current game button opens the experience page.

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
- [x] Pin all active workflow action references to full commit SHAs resolved from their existing versions; allow the pinned VirusTotal revision alongside the default branch’s existing v4 reference.
- [ ] After the pinned workflows merge, remove the temporary v4 allowlist entry and enable the repository SHA-only policy. Enabling it before merge would block old default-branch workflows.
- [ ] Review the 22 dependency alerts reported by GitHub on the default branch (including inherited legacy dependencies); establish native relevance and a remediation plan.
- [ ] Release signing/notarization and first-stable installation/update acceptance.
- [ ] Repeatable benchmark comparison: standard Roblox, AppleBlox with identical settings, then a tuned profile. Record frame consistency and average FPS without assuming an improvement.

## Definition of done

Feature parity is complete when every remaining original feature is implemented and verified, or has an explicitly accepted and documented native/platform difference, and the final source audit has no unexplained omissions. A release candidate additionally needs the live acceptance and release-readiness checks above. Automated tests alone do not close those live checks.
