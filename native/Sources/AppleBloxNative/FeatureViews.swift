import AppKit
import AppleBloxCore
import SwiftUI

struct ModsView: View {
    let model: LauncherModel
    @State private var confirmRestore = false
    @State private var showIconColor = false
    @State private var showModGuide = false
    @State private var showScanResults = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PageHeading(title: "Content Mods", subtitle: "Textures, sounds, and fonts in resource folders.")
                Button("Import…", systemImage: "plus") { Task { await model.importMod() } }
                    .disabled(model.isBusy || !model.canSave)
                Button("Icon Color…", systemImage: "paintpalette") { showIconColor = true }
                    .disabled(model.isBusy || !model.canSave || model.installation == nil)
                Button("Font…", systemImage: "textformat") { Task { await model.importFont() } }
                    .disabled(model.isBusy || !model.canSave || model.installation == nil)
                Menu {
                    Button("Rescan Library", systemImage: "arrow.clockwise") { Task { await model.rescanMods() } }
                        .disabled(model.isBusy || !model.canSave || model.configuration.features.mods.isEmpty)
                    Button("Scan Results…", systemImage: "list.bullet.clipboard") { showScanResults = true }
                        .disabled(model.modLibraryScan == nil)
                    Divider()
                    Button("Mod Guide…", systemImage: "book") { showModGuide = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Mod library actions")
            }
            if model.configuration.features.mods.isEmpty {
                ContentUnavailableView("No content mods", systemImage: "shippingbox", description: Text("Import a resource folder beginning with content, PlatformContent, or ExtraContent.").font(.callout))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(model.configuration.features.mods) { mod in
                    HStack {
                        Toggle(isOn: Binding(get: { mod.enabled }, set: { model.toggleMod(mod, enabled: $0) })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mod.name).font(.callout.weight(.medium))
                                Text(mod.iconColorHex.map { "Roblox icon color · \($0)" } ?? (mod.fileCount == 1 ? "1 resource file" : "\(mod.fileCount) resource files")).font(.caption).foregroundStyle(.secondary)
                                if let problem = model.modLibraryProblem(mod) {
                                    Label(problem, systemImage: "exclamationmark.triangle")
                                        .font(.caption).foregroundStyle(.red).lineLimit(2).help(problem)
                                }
                            }
                        }
                        .disabled(model.isBusy || !model.canSave)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Menu {
                            Button("Show Files", systemImage: "folder") { Task { await model.showModFiles(mod) } }
                            Button("Remove from Library", systemImage: "minus.circle", role: .destructive) { model.removeMod(mod) }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for \(mod.name)")
                        .disabled(model.isBusy || !model.canSave)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
            Toggle("Apply enabled mods to new Roblox sessions", isOn: Binding(get: { model.configuration.features.applyModsOnLaunch }, set: { model.setFeature(\.applyModsOnLaunch, $0) }))
                .controlSize(.small).disabled(model.isBusy || !model.canSave)
            HStack {
                Button("Apply Mods") { Task { await model.applyMods() } }.launchButtonStyle()
                    .disabled(model.isBusy || !model.canSave || model.isRunning || model.installation == nil || (model.configuration.features.mods.isEmpty && !model.hasModBackup) || model.modLibraryScan?.blocksApplying(model.configuration.features.mods) == true)
                Button("Restore Resources…") { confirmRestore = true }
                    .disabled(model.isBusy || !model.canSave || model.isRunning || !model.hasModBackup)
                Spacer()
                Button("Mods Folder", action: model.showModsFolder).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            Text(model.isWorkingFeature ? model.featureStatus : (model.featureStatus.isEmpty ? "Quit Roblox before applying. Original resources are backed up; conflicting mods are rejected." : model.featureStatus))
                .font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .sheet(isPresented: $showIconColor) { IconColorEditor(model: model) }
        .sheet(isPresented: $showModGuide) { ModGuideView() }
        .sheet(isPresented: $showScanResults) {
            if let scan = model.modLibraryScan { ModScanResultsView(scan: scan, mods: model.configuration.features.mods) }
        }
        .confirmationDialog("Restore Roblox’s original resources?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore Resources") { Task { await model.applyMods(restore: true) } }
        } message: { Text("Restores the pre-mod backup and disables applying mods on launch. Your imported mods stay in the library.") }
    }
}

struct AccountsView: View {
    let model: LauncherModel
    @State private var showLogin = false
    @State private var removal: RobloxAccount?
    @State private var confirmRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PageHeading(title: "Accounts", subtitle: "Sessions are kept in this Mac’s Keychain.")
                Button("Sign In…", systemImage: "person.badge.plus") { showLogin = true }
                    .disabled(model.isBusy || !model.canSave)
            }
            Picker("Launch as", selection: Binding(get: { model.configuration.features.selectedAccountID }, set: model.selectAccount)) {
                Text("Use Player’s current login").tag(Int64?.none)
                ForEach(model.configuration.features.accounts) { Text("@" + $0.name).tag(Optional($0.id)) }
            }
            .disabled(model.isBusy || !model.canSave)
            if model.configuration.features.accounts.isEmpty {
                ContentUnavailableView("No saved accounts", systemImage: "person.crop.circle", description: Text("Sign in on Roblox’s website or import Player’s current login.").font(.callout))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(model.configuration.features.accounts) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.displayName).font(.callout.weight(.medium))
                            Text("@\(account.name)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if account.id == model.configuration.features.selectedAccountID { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppleBloxTheme.primary) }
                        Button("Remove…") { removal = account }.controlSize(.small)
                            .disabled(model.isBusy || !model.canSave)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
            HStack {
                Button("Import Player Login") { Task { await model.importPlayerAccount() } }
                Button("Restore Original Login…") { confirmRestore = true }
                    .disabled(model.isRunning)
            }
            .controlSize(.small).disabled(model.isBusy || !model.canSave)
            Text("Quit Roblox before launching a different account. The first switch saves Player’s original login in Keychain so you can restore it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showLogin) { AccountLoginView(model: model) }
        .confirmationDialog("Remove this saved account?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            Button("Remove Account", role: .destructive) {
                if let account = removal { removal = nil; Task { await model.removeAccount(account) } }
            }
        } message: { Text("Removes its saved Keychain session from AppleBlox. It does not sign out other devices or change the current Player login.") }
        .confirmationDialog("Restore the original Player login?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore Login") { Task { await model.restorePlayerLogin() } }
        }
    }
}

struct IntegrationsView: View {
    let model: LauncherModel
    @State private var clientID = ""
    @State private var handlesLinks = false
    var body: some View {
        Form {
            Section("Discord Rich Presence") {
                featureToggle("Enable Discord Rich Presence", \.discordPresence)
                featureToggle("Show current game", \.discordGameActivity)
                    .disabled(!model.configuration.features.discordPresence)
                featureToggle("Show elapsed play time", \.discordPlayTime)
                    .disabled(!model.configuration.features.discordPresence)
                featureToggle("Show game artwork and creator", \.discordArtwork)
                    .disabled(!model.configuration.features.discordPresence || !model.configuration.features.discordGameActivity)
                featureToggle("Show game-page button", \.discordGameButton)
                    .disabled(!model.configuration.features.discordPresence || !model.configuration.features.discordGameActivity)
                Text("Hiding the current game also hides its artwork, creator, and link. Elapsed time can remain visible.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.discordStatus).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Application ID", text: $clientID)
                    Button("Save") { do { try model.setDiscordClientID(clientID) } catch { model.errorMessage = error.localizedDescription } }
                }
                .disabled(model.isBusy || !model.canSave)
                Text("Uses Discord desktop’s local IPC connection. The inherited AppleBlox application ID is the default; enter your own ID for separate fork branding.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Bloxstrap SDK") {
                featureToggle("Enable Bloxstrap SDK compatibility", \.bloxstrapSDK)
                featureToggle("Allow games to customize Discord presence", \.gameControlledPresence)
                    .disabled(!model.configuration.features.bloxstrapSDK || !model.configuration.features.discordPresence || !model.configuration.features.discordGameActivity)
                Text("Supports SetRichPresence messages from the current game. Your game-visibility, artwork, and elapsed-time controls still apply. Changes reset when you leave or disable game control.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("SDK images use public Roblox asset thumbnails. Launch-data and server-invite commands are not supported.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Play history & behavior") {
                featureToggle("Keep up to 200 recent game sessions", \.trackHistory)
                featureToggle("Quit Player after leaving a game", \.quitAfterGame)
                featureToggle("Return to Roblox’s website when Player closes", \.returnToWebsite)
                featureToggle("Quit AppleBlox when Roblox closes", \.quitLauncherWithPlayer)
                Text("Quits after the last Player instance closes. AppleBlox stays open if a launch, install, or file operation is in progress.")
                    .font(.caption).foregroundStyle(.secondary)
                featureToggle("Request a new Player instance", \.newPlayerInstance)
                Text("New instances use macOS’s standard launch option. Roblox may still restrict simultaneous sessions; separate instances share Player’s login.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Browser links") {
                LabeledContent("Current handler", value: handlesLinks ? "AppleBlox Native" : "Another app")
                HStack {
                    Button("Use AppleBlox") { Task { await model.setLinkHandling(true); handlesLinks = model.isLinkHandler() } }
                    Button("Use Roblox Directly") { Task { await model.setLinkHandling(false); handlesLinks = model.isLinkHandler() } }
                }
                Text("Roblox browser links can pass through your selected profiles and mods. Incoming requests are reviewed before forwarding.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Migration") {
                Button("Import Original AppleBlox Profiles…", action: model.importLegacyProfiles)
                    .disabled(model.isBusy || !model.canSave)
                Text("Choose one or more JSON files from the original profiles folder. Game-specific profiles also create or update saved game links. Unsupported flags stop the import without changing native settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).controlSize(.small).scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent).contentMargins(.top, 0, for: .scrollContent)
        .onAppear { clientID = model.configuration.features.discordClientID; handlesLinks = model.isLinkHandler() }
    }

    private func featureToggle(_ title: String, _ key: WritableKeyPath<FeatureSettings, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { model.configuration.features[keyPath: key] }, set: { model.setFeature(key, $0) }))
            .disabled(model.isBusy || !model.canSave)
    }
}

struct HistoryView: View {
    let model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeading(title: "Play History", subtitle: model.configuration.features.trackHistory ? "Recent games, stored locally on this Mac." : "Enable play history in Integrations to record new sessions.")
            if model.history.isEmpty {
                ContentUnavailableView("No recorded sessions", systemImage: "clock", description: Text("History starts with game joins observed after tracking is enabled. Existing Roblox logs are not imported."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(model.history) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.name).font(.callout.weight(.medium))
                            Text(session.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if session.id == model.currentSession?.id { Text("Playing").font(.caption).foregroundStyle(.green) }
                        Button("Play Again", systemImage: "play.fill") {
                            if let game = try? GameShortcut(name: session.name, placeID: session.placeID) { Task { await model.launch(shortcut: game) } }
                        }
                        .controlSize(.small).disabled(model.isBusy || model.installation == nil)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
    }
}

struct UpdateControls: View {
    let model: LauncherModel
    @State private var confirmInstall = false
    var body: some View {
        Section("Roblox Updates") {
            Text(model.updateStatus).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Check Latest") { Task { await model.checkForUpdates() } }
                    .disabled(model.isCheckingUpdates || model.isBusy)
                Button(model.installation == nil ? "Install Roblox…" : "Download & Install…") { confirmInstall = true }
                    .disabled(model.isBusy || model.isCheckingUpdates || model.isRunning || !model.canSave)
                if model.updateTask != nil {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { model.updateTask?.cancel() }
                }
            }
            Toggle("Check on open and hourly while AppleBlox is open", isOn: Binding(get: { model.configuration.features.checkUpdatesOnOpen }, set: { model.setFeature(\.checkUpdatesOnOpen, $0) }))
                .disabled(model.isBusy || !model.canSave)
            Toggle("Install updates automatically while Player is closed", isOn: Binding(get: { model.configuration.features.automaticUpdates }, set: { model.setFeature(\.automaticUpdates, $0) }))
                .disabled(model.isBusy || !model.canSave)
            if let previous = model.previousInstallation {
                Button("Show Previous Installation") { NSWorkspace.shared.activateFileViewerSelecting([previous]) }
            }
            Text("Downloads Roblox LIVE for this Mac, verifies Roblox’s signature, and retains the previous app beside the new installation. Automatic updates run only while AppleBlox is open.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Install the latest Roblox LIVE release?", isPresented: $confirmInstall, titleVisibility: .visible) {
            Button("Download and Install", action: model.startRobloxUpdate)
        } message: { Text("The selected Player installation will be replaced after verification. The previous app and old settings backups are kept. Mods can be reapplied on the next launch.") }
    }
}
