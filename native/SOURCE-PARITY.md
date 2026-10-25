# Original Appearance, Misc, and Info source audit

Audited the inherited source on the native development branch on 2026-10-25. This is a source comparison, not live UI or service verification. It supplements [the seven-screenshot checklist](PARITY.md); its 21/24 implemented count is unchanged. No app behavior, version, settings, credentials, or Player files were changed for this audit.

Status meanings: **Implemented** has a native equivalent; **Partial** covers some behavior with a specific gap; **Not ported** remains absent; **Adaptation** is a deliberate native/fork difference rather than identical legacy UI.

## Appearance

Sources: [Appearance.svelte](../legacy/frontend/src/windows/main/pages/Appearance.svelte), [icon manager](../legacy/frontend/src/windows/main/components/icon-manager/icon-manager.svelte), [theme input](../legacy/frontend/src/windows/main/components/theme-input/theme-input.svelte), [bootstrapper theme library](../legacy/frontend/src/windows/main/components/bootstrapper-theme/bootstrapper-theme.svelte).

| Original feature | Native status | Exact difference / remaining work |
| --- | --- | --- |
| Launcher app-icon library: built-in/original icons, previews, custom `.icns` upload, apply confirmation, delete and original-icon recovery | Not ported | Native ships the fixed red-body/blue-leaf fork icon. That branding is present, but there is no user-managed launcher-icon library. Roblox UI icon-color mods affect Player fonts and do not implement this feature. |
| Custom theme CSS: edit/save, reveal CSS file, reload | Partial / adaptation | Native has System/Light/Dark themes, the fork palette, reduced animation, solid backgrounds and appearance reset. Arbitrary theme editing/import/export is absent; legacy CSS cannot directly style SwiftUI views. A native theme format would be a separate design decision. |
| Bloxstrap/Fishstrap bootstrapper themes: XML/ZIP import with assets, preview library, activate, rename, delete, reveal, refresh | Not ported | Native has no themed bootstrapper renderer or theme-library workflow. This includes both the import/library UI and the launch-screen rendering implementation, not just reading XML. |

## Misc / System

Source: [Misc.svelte](../legacy/frontend/src/windows/main/pages/Misc.svelte). Native counterparts: [DiagnosticsView](Sources/AppleBloxNative/ContentView.swift), [maintenance actions](Sources/AppleBloxNative/LauncherMaintenance.swift), [notification service](Sources/AppleBloxNative/GameNotifications.swift), [launcher file/folder actions](Sources/AppleBloxNative/LauncherModel.swift).

| Original feature | Native status | Exact difference / remaining work |
| --- | --- | --- |
| Notification Sounds | Implemented | Separate opt-in system sound for native Server Joined alerts. Those are currently the native app's notification type; live sound/permission/Focus acceptance is still pending. |
| Alternative notifications through AppleScript | Not ported | Native uses UserNotifications with foreground banners. Whether an alternate delivery mechanism is needed remains a product decision; it is not required for the current native service to exist. |
| Allow fixed loading times | Not ported | No minimum-duration launch/bootstrapper steps. This is a cosmetic timing option, independent of download/install correctness; group with bootstrapper work if retained. |
| View Logs (AppleBlox's own log directory) | Partial | Native Diagnostics shows in-memory session activity and opens **Roblox's** log directory. Native does not yet persist its own rotating launcher logs or expose an equivalent launcher-log folder. |
| Copy Debug Report | Implemented / adaptation | Copy Diagnostics creates a fixed-field report. It deliberately excludes account data, names, paths, URLs, raw logs and activity messages; it is not a full copy of the legacy report's fields. |
| Export Debug Bundle (configuration, recent launcher logs, custom theme and summary ZIP) | Not ported | No native support-bundle export. Engine JSON export is a separate feature, not a debug bundle or complete settings backup. Define the included data and review flow before implementing this. |
| Documentation button | Partial | The local Mod Guide and linked resource guide exist; About links the fork/upstream repositories. There is no dedicated fork-documentation action matching the System page button. The old docs URL is a legacy destination, not proof of native-fork documentation. |
| AppleBlox Folder | Implemented / adaptation | Diagnostics → Open Native Data Folder opens the separate AppleBlox Native data directory. It correctly does not open or reuse legacy app data. |
| Roblox Folder (opens selected app's `Contents`) | Partial | Launcher/installation actions reveal the selected Player app in Finder. There is no direct `Contents` shortcut matching the original System button. |
| Reset AppleBlox: remove saved credentials, settings, mods, cache and app data, then quit; warning and typed confirmation | Not ported | Reset Appearance and cache cleanup are scoped operations, not a full reset. A native reset must account for Keychain entries and backups of applied Player changes so originals remain recoverable. No reset/deletion was performed in this audit. |

## Info / About

Sources: [Info.svelte](../legacy/frontend/src/windows/main/pages/Info.svelte), [contributor/technology collection](../legacy/frontend/src/windows/main/components/informations/informations.svelte). Native counterpart: [AboutView.swift](Sources/AppleBloxNative/AboutView.swift).

| Original feature | Native status | Exact difference / remaining work |
| --- | --- | --- |
| Individual developer, moderator/tester, artist, technology and inspiration cards with avatars/links | Partial / adaptation | Native has aggregate AppleBlox contributor credit, explicit @typeofnull logo credit and GPL-3.0 attribution, plus fork identity/version. Individual role/name cards and the inspiration collection are not displayed in About; the original list remains in `legacy/`. Legacy Svelte/Neutralino/TypeScript cards should not describe the native app's implementation. |
| Discord/community button | Partial | Mod Guide links the original community through the upstream contributing section. About has no direct community button matching the original Info page. A fork-specific community destination has not been configured. Link availability was not tested in this audit. |
| GitHub/source button | Implemented | Native About links both the fork and original AppleBlox repositories. |

## Resulting outside-screenshot backlog

The audit is complete; implementation of the missing items is not. These entries do not count toward screenshot completion.

- [x] Audit original Appearance, Misc and Info controls and their nested components.
- [ ] User-managed launcher-icon library, custom icon selection and recovery.
- [ ] Decide/design portable native custom themes; legacy CSS editing remains unported.
- [ ] Bootstrapper theme library and renderer, including XML/ZIP assets and library actions.
- [ ] Decide whether to retain fixed-duration bootstrapper steps.
- [ ] Persistent native launcher logs and a launcher-log folder action.
- [ ] Reviewed debug/support-bundle export; decide settings-backup requirements separately.
- [ ] Full native reset with recoverable handling of Player backups and saved credentials.
- [ ] Dedicated fork-documentation access and an optional direct Player `Contents` shortcut.
- [ ] Expanded native About credits/inspirations and community access.
- [ ] Decide whether an alternative notification backend is useful after native delivery acceptance.

Already tracked elsewhere: online Workshop, server-region selection, background updates while the launcher is closed, and native self-updating. Actual notifications, Discord, FPS/display restoration, simultaneous Players, authenticated accounts and in-game rendering remain acceptance work, not findings that this documentation audit verifies.

Suggested next small implementation cluster: About credits/community and documentation/folder shortcuts. Persistent logs plus a reviewed support bundle form a larger related cluster. Bootstrapper themes and full reset need their own implementation and validation work.
