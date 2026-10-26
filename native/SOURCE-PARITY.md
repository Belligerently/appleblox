# Original Appearance, Misc, and Info source audit

Audited the inherited source on the native development branch on 2026-10-25. This is a source comparison, not live UI or service verification. It supplements [the seven-screenshot checklist](PARITY.md); its 21/24 implemented count is unchanged. The initial audit was documentation-only. The table below is maintained as native features are implemented; it does not certify live acceptance.

Status meanings: **Implemented** has a native equivalent; **Partial** covers some behavior with a specific gap; **Not ported** remains absent; **Adaptation** is a deliberate native/fork difference rather than identical legacy UI.

## Appearance

Sources: [Appearance.svelte](../legacy/frontend/src/windows/main/pages/Appearance.svelte), [icon manager](../legacy/frontend/src/windows/main/components/icon-manager/icon-manager.svelte), [theme input](../legacy/frontend/src/windows/main/components/theme-input/theme-input.svelte), [bootstrapper theme library](../legacy/frontend/src/windows/main/components/bootstrapper-theme/bootstrapper-theme.svelte).

| Original feature | Native status | Exact difference / remaining work |
| --- | --- | --- |
| Launcher app-icon library: built-in/original icons, previews, custom `.icns` upload, apply confirmation, delete and original-icon recovery | Partial / adaptation | Appearance → Manage Launcher Icons provides the Native default, six inherited styles, ICNS imports, previews, confirmed application, persisted Dock selection, recoverable removal and default restoration. Finder customization remains unimplemented: the macOS custom-file-icon call stalled in isolated QA and is excluded from this build. Bundled resources are never replaced. Applied icons must be changed before removal; removed copies remain in launcher-icons/removed. |
| Custom theme CSS: edit/save, reveal CSS file, reload | Partial / adaptation | Native has System/Light/Dark themes, the fork palette, reduced animation, solid backgrounds and appearance reset. Arbitrary theme editing/import/export is absent; legacy CSS cannot directly style SwiftUI views. A native theme format would be a separate design decision. |
| Bloxstrap/Fishstrap bootstrapper themes: XML/ZIP import with assets, preview library, activate, rename, delete, reveal, refresh | Not ported | Native has no themed bootstrapper renderer or theme-library workflow. This includes both the import/library UI and the launch-screen rendering implementation, not just reading XML. |

## Misc / System

Source: [Misc.svelte](../legacy/frontend/src/windows/main/pages/Misc.svelte). Native counterparts: [DiagnosticsView](Sources/AppleBloxNative/ContentView.swift), [maintenance actions](Sources/AppleBloxNative/LauncherMaintenance.swift), [notification service](Sources/AppleBloxNative/GameNotifications.swift), [launcher file/folder actions](Sources/AppleBloxNative/LauncherModel.swift).

| Original feature | Native status | Exact difference / remaining work |
| --- | --- | --- |
| Notification Sounds | Implemented | Separate opt-in system sound for native Server Joined alerts. Those are currently the native app's notification type; live sound/permission/Focus acceptance is still pending. |
| Alternative notifications through AppleScript | Not ported | Native uses UserNotifications with foreground banners. Whether an alternate delivery mechanism is needed remains a product decision; it is not required for the current native service to exist. |
| Allow fixed loading times | Not ported | No minimum-duration launch/bootstrapper steps. This is a cosmetic timing option, independent of download/install correctness; group with bootstrapper work if retained. |
| View Logs (AppleBlox's own log directory) | Implemented / adaptation | Diagnostics → Open Launcher Logs opens the native logs folder. A private atomic journal retains up to four 64 KiB event segments across restarts. Only typed timestamps/codes/counts/numeric errors are saved; raw activity messages remain in memory. Roblox Logs is separate. Corrupt/oversized/linked journals are preserved and writing stops for this session. |
| Copy Debug Report | Implemented / adaptation | Copy Diagnostics creates a fixed-field report. It deliberately excludes account data, names, paths, URLs, raw logs and activity messages; it is not a full copy of the legacy report's fields. |
| Export Debug Bundle (configuration, recent launcher logs, custom theme and summary ZIP) | Implemented / adaptation | Diagnostics → Export Support Bundle reviews exact diagnostics, fixed preference summary, optional saved events, and README before local ZIP export. Unreadable settings/logs are omitted with notes. No raw configuration, arbitrary files, credentials, names/IDs, paths/URLs, engine values, themes, mods or backups are copied. No upload or existing-export replacement. A full settings backup remains separate and unimplemented. |
| Documentation button | Implemented / adaptation | About and Diagnostics open an offline Native Guide covering launch, profiles, mods, accounts, privacy, updates, restore/troubleshooting and experimental features. It is native content included with the executable, not the legacy documentation site. Source/support links are also available. |
| AppleBlox Folder | Implemented / adaptation | Diagnostics → Open Native Data Folder opens the separate AppleBlox Native data directory. It correctly does not open or reuse legacy app data. |
| Roblox Folder (opens selected app's `Contents`) | Implemented | Installation → Open Contents and Diagnostics → Open Player Contents open the selected bundle’s validated folder. The shortcut rechecks Player and rejects symlinked/redirected Contents or a stale bundle before handing it to Finder. |
| Reset AppleBlox: remove saved credentials, settings, mods, cache and app data, then quit; warning and typed confirmation | Not ported | Reset Appearance and cache cleanup are scoped operations, not a full reset. A native reset must account for Keychain entries and backups of applied Player changes so originals remain recoverable. No reset/deletion was performed in this audit. |

## Info / About

Sources: [Info.svelte](../legacy/frontend/src/windows/main/pages/Info.svelte), [contributor/technology collection](../legacy/frontend/src/windows/main/components/informations/informations.svelte). Native counterpart: [AboutView.swift](Sources/AppleBloxNative/AboutView.swift).

| Original feature | Native status | Exact difference / remaining work |
| --- | --- | --- |
| Individual developer, moderator/tester, artist, technology and inspiration cards with avatars/links | Implemented / adaptation | About → Credits lists all nine original contributors with historical roles, fork identity, the current native stack, legacy technology attribution, Bloxstrap inspiration, and the GPL link. System symbols replace remote avatars so credits work offline without image requests. Unambiguous profile links are retained; n.u.g is unlinked because the inherited URL duplicates TrisecTroop’s identity. No new identity was guessed. |
| Discord/community button | Implemented / adaptation | About directly exposes Original community through the upstream contributing section, matching the existing Mod Guide destination. Fork Support opens the fork issue tracker. The old `appleblox.com/discord` redirect could not be verified during implementation, so it is not used and no fork Discord invite is invented. External destinations still require network access. |
| GitHub/source button | Implemented | Native About links both the fork and original AppleBlox repositories. |

## Resulting outside-screenshot backlog

The audit is complete; implementation of the missing items is not. These entries do not count toward screenshot completion.

- [x] Audit original Appearance, Misc and Info controls and their nested components.
- [x] Dock-icon library: bundled/original previews, custom ICNS import, saved selection, confirmed apply, recoverable removal and default recovery.
- [ ] Finder app-icon customization; the native system call stalled in isolated QA and is not shipped.
- [ ] Decide/design portable native custom themes; legacy CSS editing remains unported.
- [ ] Bootstrapper theme library and renderer, including XML/ZIP assets and library actions.
- [ ] Decide whether to retain fixed-duration bootstrapper steps.
- [x] Persistent native launcher logs and a launcher-log folder action.
- [x] Reviewed debug/support-bundle export; full settings backup remains separate and unimplemented.
- [ ] Full native reset with recoverable handling of Player backups and saved credentials.
- [x] Dedicated offline fork documentation and direct validated Player `Contents` shortcuts.
- [x] Expanded native About credits/inspirations and community/support access.
- [ ] Decide whether an alternative notification backend is useful after native delivery acceptance.

Already tracked elsewhere: online Workshop, server-region selection, background updates while the launcher is closed, and native self-updating. Actual notifications, Discord, FPS/display restoration, simultaneous Players, authenticated accounts and in-game rendering remain acceptance work, not findings that this documentation audit verifies.

Completed clusters: saved Dock-icon library (Finder changes remain pending); About credits/community, offline documentation and folder shortcuts; persistent bounded event logs and reviewed local support ZIP export. Bootstrapper themes, full settings backup and full reset need their own implementation and validation work.
