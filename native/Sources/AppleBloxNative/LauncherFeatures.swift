import AppKit
import AppleBloxCore
import UniformTypeIdentifiers

extension LauncherModel {
    func setFeature(_ keyPath: WritableKeyPath<FeatureSettings, Bool>, _ value: Bool) {
        do {
            var next = configuration
            next.features[keyPath: keyPath] = value
            try persist(next)
            if keyPath == \.serverLocation { refreshServerActivity() }
            if keyPath == \.serverJoinedNotifications, !value {
                serverNoticePending = false
                // Do not interrupt a location lookup merely because alerts were disabled.
                if !next.features.serverLocation { refreshServerActivity() }
            }
            if !next.features.needsLogTracking {
                finishCurrentSession()
                Task { await logReader.reset() }
            }
            if !next.features.discordPresence { Task { await discord.disconnect() }; discordStatus = "Off" }
            if !next.features.allowsGamePresence { resetGamePresence() }
            if !next.features.discordArtwork {
                presenceArtworkTask?.cancel(); presenceArtworkTask = nil; presenceArtworkLookupID = nil
                gamePresenceArtwork = [:]
            }
            refreshPresenceArtworkIfNeeded()
            refreshCurrentGameDetailsIfNeeded()
        } catch { report(error) }
    }

    func handlePlayerExit() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: RobloxInstallation.bundleIdentifier).isEmpty else { return }
        if configuration.features.returnToWebsite {
            // Use the fixed public homepage, never a launch URL containing account/session data.
            guard NSWorkspace.shared.open(URL(string: "https://www.roblox.com/")!) else {
                errorMessage = "Couldn’t open Roblox’s website in your default browser."
                return
            }
        }
        // Hand off the website before the optional launcher termination begins.
        quitLauncherAfterPlayerExit()
    }

    func quitLauncherAfterPlayerExit() {
        guard configuration.features.quitLauncherWithPlayer, !isBusy, !isQuittingAfterPlayer else { return }
        isQuittingAfterPlayer = true
        Task {
            defer { isQuittingAfterPlayer = false }
            await discord.disconnect()
            // Finish and flush history before terminating; older queued snapshots cannot replace this revision.
            finishCurrentSession()
            if canSaveHistory, configuration.features.trackHistory {
                historyRevision += 1
                do { try await historyStore.save(history, revision: historyRevision) }
                catch {
                    canSaveHistory = false
                    errorMessage = "AppleBlox stayed open because play history couldn’t be saved."
                    return
                }
            }
            guard configuration.features.quitLauncherWithPlayer, !isBusy,
                  NSRunningApplication.runningApplications(withBundleIdentifier: RobloxInstallation.bundleIdentifier).isEmpty else { return }
            NSApplication.shared.terminate(nil)
        }
    }

    func setDiscordClientID(_ id: String) throws {
        var next = configuration
        next.features.discordClientID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        try persist(next)
    }

    func prepareFeatureLaunch(_ installation: RobloxInstallation) async throws {
        if !isRunning && (configuration.features.trackHistory || configuration.features.discordPresence || configuration.features.quitAfterGame) {
            _ = try? await logReader.poll(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Roblox"))
        }
        if let id = configuration.features.selectedAccountID {
            guard !isRunning else { throw FeatureError.message("Quit Roblox before launching with a selected account.") }
            try await accountVault.activate(accountID: id)
        }
        if configuration.features.applyModsOnLaunch && !isRunning && (configuration.features.mods.contains { $0.enabled } || hasModBackup) {
            try await modStore.apply(configuration.features.mods, to: installation)
            await refreshModBackup()
            record("Applied enabled content mods before launch.")
        }
    }

    func importMod() async {
        guard !isBusy, canSave else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Content Mod"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        isWorkingFeature = true; defer { isWorkingFeature = false }
        do {
            let mod = try await modStore.importFolder(folder)
            var next = configuration
            next.features.mods.append(mod)
            try persist(next)
            modLibraryScan = nil
            featureStatus = "Imported \(mod.name) (\(mod.fileCount) \(mod.fileCount == 1 ? "file" : "files"))."
            record(featureStatus)
        } catch { report(error) }
    }

    func createIconColorMod(_ color: IconColor) async throws {
        guard !isBusy, canSave, let installation else { throw FeatureError.message("Choose a Roblox Player installation first.") }
        isWorkingFeature = true
        featureStatus = "Generating icon color mod…"
        defer { isWorkingFeature = false }
        let mod = try await modStore.importIconColor(color, installation: installation)
        var next = configuration
        next.features.mods.append(mod)
        try persist(next)
        modLibraryScan = nil
        featureStatus = "Created \(mod.name). Enable it, then Apply Mods to use it."
        record(featureStatus)
    }

    func toggleMod(_ mod: ContentMod, enabled: Bool) {
        do {
            var next = configuration
            guard let index = next.features.mods.firstIndex(where: { $0.id == mod.id }) else { return }
            if enabled, mod.iconColorHex != nil {
                for index in next.features.mods.indices where next.features.mods[index].iconColorHex != nil {
                    next.features.mods[index].enabled = false
                }
            }
            next.features.mods[index].enabled = enabled
            try persist(next)
            if let scan = modLibraryScan { featureStatus = scan.summary(for: next.features.mods) }
        } catch { report(error) }
    }

    func rescanMods() async {
        guard !isBusy, canSave else { return }
        isWorkingFeature = true
        featureStatus = "Scanning imported mod packs…"
        defer { isWorkingFeature = false }
        do {
            let report = try await modStore.scan(configuration.features.mods)
            var next = configuration
            next.features.mods = report.mods
            try persist(next)
            modLibraryScan = report
            featureStatus = report.summary(for: next.features.mods)
            record(featureStatus)
        } catch { report(error) }
    }

    func showModFiles(_ mod: ContentMod) async {
        do {
            let folder = try await modStore.checkedPackageURL(mod)
            guard NSWorkspace.shared.open(folder) else { throw FeatureError.message("Couldn’t open this pack’s folder in Finder.") }
        } catch { report(error) }
    }

    func modLibraryProblem(_ mod: ContentMod) -> String? {
        guard let scan = modLibraryScan else { return nil }
        if let issue = scan.issues.first(where: { $0.id == mod.id }) { return issue.message }
        if let conflict = scan.activeConflicts(in: configuration.features.mods).first(where: { $0.modIDs.contains(mod.id) }) {
            return "Conflicts at \(conflict.path)"
        }
        return nil
    }

    func importFont() async {
        guard !isBusy, canSave, let installation else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a Custom Roblox Font"
        panel.allowedContentTypes = [UTType(filenameExtension: "ttf")!, UTType(filenameExtension: "otf")!]
        guard panel.runModal() == .OK, let file = panel.url else { return }
        isWorkingFeature = true; defer { isWorkingFeature = false }
        do {
            let mod = try await modStore.importFont(file, installation: installation)
            var next = configuration
            next.features.mods.append(mod)
            try persist(next)
            modLibraryScan = nil
            featureStatus = "Imported \(mod.name). Apply Mods to use it. Enable one font mod at a time."
            record(featureStatus)
        } catch { report(error) }
    }

    func removeMod(_ mod: ContentMod) {
        do {
            var next = configuration
            next.features.mods.removeAll { $0.id == mod.id }
            try persist(next)
            modLibraryScan = nil
            // Keep imported content on disk, so removing a library record is recoverable.
            featureStatus = "Removed from library. Apply again to update Roblox; imported files remain in the Mods folder."
        } catch { report(error) }
    }

    func applyMods(restore: Bool = false) async {
        guard !isBusy, canSave, let installation else { return }
        guard restore || !configuration.features.mods.isEmpty || hasModBackup else { return }
        updateRunningStatus()
        guard !isRunning else { errorMessage = "Quit Roblox before changing content mods."; return }
        isWorkingFeature = true; featureStatus = restore ? "Restoring resources…" : "Backing up and applying content…"
        defer { isWorkingFeature = false }
        do {
            if restore {
                var next = configuration
                next.features.applyModsOnLaunch = false
                try persist(next)
                try await modStore.restore(installation)
            } else { try await modStore.apply(configuration.features.mods, to: installation) }
            featureStatus = restore ? "Original Roblox resources restored." : "Enabled mods applied. Ready for the next launch."
            record(featureStatus)
        } catch { featureStatus = "No changes applied."; report(error) }
        await refreshModBackup()
    }

    func refreshModBackup() async {
        guard let installation else { hasModBackup = false; return }
        let exists = await modStore.hasBackup(installation)
        if self.installation == installation { hasModBackup = exists }
    }

    func showNativeData() {
        do {
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(store.directory)
        } catch { report(error) }
    }

    func showModsFolder() {
        do {
            let folder = store.directory.appendingPathComponent("mods")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch { report(error) }
    }

    func checkForUpdates() async {
        guard !isCheckingUpdates, !isBusy else { return }
        isCheckingUpdates = true; updateStatus = "Checking Roblox LIVE…"
        defer { isCheckingUpdates = false }
        do {
            let release = try await updateService.latest()
            latestRelease = release
            updateStatus = release.version == installation?.version ? "Roblox is up to date (\(release.version))." : "Roblox \(release.version) is available."
        } catch { updateStatus = error.localizedDescription }
    }

    func startRobloxUpdate() {
        guard !isBusy, !isCheckingUpdates, canSave else { return }
        var target = installation?.url
        if target == nil || target?.lastPathComponent != "Roblox.app" {
            let panel = NSOpenPanel()
            panel.title = "Choose an Applications Folder"
            panel.prompt = "Install Here"
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            target = folder.appendingPathComponent("Roblox.app")
        }
        guard let target else { return }
        updateTask = Task { await installRobloxUpdate(at: target) }
    }

    private func installRobloxUpdate(at target: URL) async {
        guard !isBusy else { return }
        updateRunningStatus()
        guard !isRunning else { errorMessage = "Quit Roblox before installing an update."; return }
        isWorkingFeature = true
        defer { isWorkingFeature = false; updateTask = nil }
        let workspace = store.directory.appendingPathComponent("downloads/\(UUID())")
        defer { try? FileManager.default.removeItem(at: workspace) }
        do {
            updateStatus = "Checking the current Roblox release…"
            let release = try await updateService.latest()
            latestRelease = release
            updateStatus = "Downloading \(release.version) and verifying Roblox’s signature…"
            let staged = try await updateService.download(release, workspace: workspace)
            try Task.checkCancellation()
            updateRunningStatus()
            guard !isRunning else { throw FeatureError.message("Roblox started during the download. Quit it and retry the update.") }
            updateStatus = "Installing verified Player…"
            let old = installation
            previousInstallation = try await updateService.install(staged: staged, at: target)
            if let old {
                try await clientSettings.archiveBackup(for: old)
                try await modStore.archiveBackup(for: old)
            }
            var next = configuration
            next.customRobloxPath = target.path
            try persist(next)
            try didInstallPlayer(at: target)
            updateStatus = "Installed Roblox \(release.version). Profiles and mods remain in your library."
            record(updateStatus)
        } catch is CancellationError { updateStatus = "Update cancelled. The download workspace was removed." }
        catch { updateStatus = "Update stopped: \(error.localizedDescription)"; report(error) }
    }

    func saveAccount(session: String) async throws {
        guard !isBusy, canSave else { throw FeatureError.message("Wait for the current operation to finish.") }
        isWorkingFeature = true; defer { isWorkingFeature = false }
        let account = try await accountVault.identify(session: session)
        try await accountVault.save(session: session, accountID: account.id)
        try saveAccountRecord(account)
    }

    func importPlayerAccount() async {
        guard !isBusy, canSave else { return }
        isWorkingFeature = true; defer { isWorkingFeature = false }
        do { try saveAccountRecord(await accountVault.importCurrentLogin()) }
        catch { report(error) }
    }

    private func saveAccountRecord(_ account: RobloxAccount) throws {
        var next = configuration
        next.features.accounts.removeAll { $0.id == account.id }
        next.features.accounts.append(account)
        // Adding an account does not change Player's login until the user selects and launches it.
        try persist(next)
        record("Saved account @\(account.name) in Keychain.")
    }

    func selectAccount(_ id: Int64?) {
        do {
            var next = configuration
            next.features.selectedAccountID = id
            try persist(next)
        } catch { report(error) }
    }

    func removeAccount(_ account: RobloxAccount) async {
        guard !isBusy, canSave else { return }
        isWorkingFeature = true; defer { isWorkingFeature = false }
        do {
            try await accountVault.remove(accountID: account.id)
            var next = configuration
            next.features.accounts.removeAll { $0.id == account.id }
            if next.features.selectedAccountID == account.id { next.features.selectedAccountID = nil }
            try persist(next)
        } catch { report(error) }
    }

    func restorePlayerLogin() async {
        guard !isBusy, canSave else { return }
        updateRunningStatus()
        guard !isRunning else { errorMessage = "Quit Roblox before restoring its login."; return }
        isWorkingFeature = true; defer { isWorkingFeature = false }
        do {
            try await accountVault.restoreOriginalLogin()
            selectAccount(nil)
            record("Restored the original Player login.")
        } catch { report(error) }
    }

    func importLegacyProfiles() {
        guard !isBusy, canSave else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Original AppleBlox Profiles"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            guard panel.urls.count <= 50 else { throw EngineError.fileTooLarge }
            var files: [Data] = []
            var totalBytes = 0
            for url in panel.urls {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 1_048_577) ?? Data()
                totalBytes += data.count
                guard data.count <= 1_048_576, totalBytes <= 8_388_608 else { throw EngineError.fileTooLarge }
                files.append(data)
            }
            legacyImportReview = try LegacyProfileImportPlan(files: files, configuration: configuration)
        } catch { report(error) }
    }

    func commitLegacyImport(_ plan: LegacyProfileImportPlan) {
        guard !isBusy, canSave else { return }
        do {
            try persist(plan.applying(to: configuration))
            legacyImportReview = nil
            record("Imported \(plan.conversions.count) original profiles; \(plan.warnings.count) disabled-row warnings.")
        } catch { report(error) }
    }

    func receiveLaunchURL(_ url: URL) {
        do { pendingLink = try LaunchLink(url) }
        catch { errorMessage = "This launch link couldn’t be read." }
    }

    func setLinkHandling(_ enabled: Bool) async {
        guard !isBusy else { return }
        guard let target = enabled ? Bundle.main.bundleURL : (installation?.url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: RobloxInstallation.bundleIdentifier)) else {
            errorMessage = "Choose a Roblox installation first."
            return
        }
        isWorkingFeature = true; defer { isWorkingFeature = false }
        var changed: [(String, URL?)] = []
        do {
            for scheme in ["roblox", "roblox-player"] {
                let previous = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://")!)
                try await NSWorkspace.shared.setDefaultApplication(at: target, toOpenURLsWithScheme: scheme)
                changed.append((scheme, previous))
            }
            record(enabled ? "AppleBlox is now the Roblox browser-link handler." : "Browser links now open Roblox directly.")
        } catch {
            for (scheme, previous) in changed {
                if let previous { try? await NSWorkspace.shared.setDefaultApplication(at: previous, toOpenURLsWithScheme: scheme) }
            }
            report(error)
        }
    }

    func isLinkHandler() -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "roblox://")!) else { return false }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    func resetGamePresence() {
        presenceArtworkTask?.cancel(); presenceArtworkTask = nil; presenceArtworkLookupID = nil
        nextPresenceArtworkAttempt = .distantPast
        gamePresence = BloxstrapPresenceState()
        gamePresenceArtwork = [:]
    }

    func refreshPresenceArtworkIfNeeded() {
        guard configuration.features.allowsGamePresence, configuration.features.discordArtwork,
              let session = currentSession, presenceArtworkTask == nil, Date() >= nextPresenceArtworkAttempt else { return }
        let ids = gamePresence.assetIDs
        guard ids.contains(where: { gamePresenceArtwork[$0] == nil }) else { return }
        nextPresenceArtworkAttempt = Date().addingTimeInterval(10)
        let lookupID = UUID()
        presenceArtworkLookupID = lookupID
        presenceArtworkTask = Task {
            defer { if presenceArtworkLookupID == lookupID { presenceArtworkTask = nil; presenceArtworkLookupID = nil } }
            let images = await presenceArtworkCatalog.images(for: ids)
            guard !Task.isCancelled, presenceArtworkLookupID == lookupID, currentSession?.id == session.id,
                  configuration.features.allowsGamePresence, configuration.features.discordArtwork else { return }
            gamePresenceArtwork = images
        }
    }

    func finishCurrentSession() {
        resetServerActivity()
        resetGamePresence()
        gameDetailsTask?.cancel(); gameDetailsTask = nil; gameDetailsLookupID = nil
        currentGameDetails = nil
        nextGameDetailsAttempt = .distantPast
        guard let session = currentSession else { return }
        if let index = history.firstIndex(where: { $0.id == session.id }) {
            history[index].endedAt = Date()
            saveHistorySnapshot()
        }
        currentSession = nil
    }

    func refreshCurrentGameDetailsIfNeeded() {
        guard let session = currentSession, currentGameDetails == nil, gameDetailsTask == nil,
              Date() >= nextGameDetailsAttempt,
              configuration.features.trackHistory || (configuration.features.discordPresence && configuration.features.discordGameActivity) else { return }
        // Metadata must not suspend the log/presence loop. Failed lookups retry at most once a minute.
        nextGameDetailsAttempt = Date().addingTimeInterval(60)
        let lookupID = UUID()
        gameDetailsLookupID = lookupID
        gameDetailsTask = Task {
            defer { if gameDetailsLookupID == lookupID { gameDetailsTask = nil; gameDetailsLookupID = nil } }
            guard let details = try? await gameCatalog.game(for: session.placeID),
                  !Task.isCancelled, gameDetailsLookupID == lookupID, currentSession?.id == session.id else { return }
            currentGameDetails = details
            currentSession?.name = details.name
            if configuration.features.trackHistory, let index = history.firstIndex(where: { $0.id == session.id }) {
                history[index].name = details.name
                saveHistorySnapshot()
            }
        }
    }

    private func saveHistorySnapshot() {
        guard canSaveHistory else { return }
        let snapshot = history
        historyRevision += 1
        let revision = historyRevision
        Task {
            do { try await historyStore.save(snapshot, revision: revision) }
            catch { canSaveHistory = false; record("History couldn’t be saved; its existing file was preserved.") }
        }
    }

    func runServices() async {
        do { history = try await historyStore.load() }
        catch { canSaveHistory = false; record("History file is unreadable and has been preserved.") }
        var lastUpdateCheck = Date.distantPast
        while !Task.isCancelled {
            if (configuration.features.checkUpdatesOnOpen || configuration.features.automaticUpdates), !isBusy, Date().timeIntervalSince(lastUpdateCheck) > 3600 {
                lastUpdateCheck = Date()
                await checkForUpdates()
                if configuration.features.automaticUpdates, !isRunning, !isBusy,
                   let installation, let latestRelease, latestRelease.version != installation.version {
                    await installRobloxUpdate(at: installation.url)
                }
            }
            if configuration.features.needsLogTracking {
                do {
                    let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Roblox")
                    for event in try await logReader.poll(directory: logs) {
                        guard isRunning, configuration.features.needsLogTracking else { break }
                        switch event {
                        case .joining(let placeID):
                            finishCurrentSession()
                            let fallback = configuration.shortcuts.first { $0.placeID == placeID }?.name ?? "Place \(placeID)"
                            let session = PlaySession(placeID: placeID, name: fallback)
                            currentSession = session
                            if configuration.features.trackHistory {
                                history.insert(session, at: 0)
                                history = Array(history.prefix(200))
                                saveHistorySnapshot()
                            }
                            refreshCurrentGameDetailsIfNeeded()
                            record("Joined \(currentSession?.name ?? fallback).")
                        case .serverConnected(let endpoint):
                            guard let session = currentSession,
                                  serverConnection.connect(sessionID: session.id, endpoint: endpoint) else { continue }
                            serverNoticePending = configuration.features.serverJoinedNotifications
                            refreshServerActivity()
                        case .richPresence(let patch):
                            guard currentSession != nil, configuration.features.allowsGamePresence else { continue }
                            let previousIDs = gamePresence.assetIDs
                            gamePresence.apply(patch)
                            // Text-only updates must not repeatedly cancel an image lookup in flight.
                            let ids = gamePresence.assetIDs
                            if ids != previousIDs {
                                gamePresenceArtwork = gamePresenceArtwork.filter { ids.contains($0.key) }
                                presenceArtworkTask?.cancel(); presenceArtworkTask = nil; presenceArtworkLookupID = nil
                            }
                            refreshPresenceArtworkIfNeeded()
                        case .left:
                            let wasPlaying = currentSession != nil
                            finishCurrentSession()
                            if wasPlaying && configuration.features.quitAfterGame { quitRoblox() }
                        }
                    }
                } catch { record("Roblox logs couldn’t be read. Activity tracking will retry.") }
            }
            refreshCurrentGameDetailsIfNeeded()
            refreshPresenceArtworkIfNeeded()
            if configuration.features.discordPresence {
                do {
                    try await discord.update(clientID: configuration.features.discordClientID, session: currentSession, running: isRunning, options: configuration.features.discordOptions, game: currentGameDetails, custom: gamePresence, artwork: gamePresenceArtwork)
                    discordStatus = isRunning ? "Connected to Discord" : "Waiting for Roblox"
                } catch { discordStatus = error.localizedDescription }
            } else { await discord.disconnect() }
            do { try await Task.sleep(for: .seconds(2)) } catch { break }
        }
        gameDetailsTask?.cancel(); gameDetailsTask = nil; gameDetailsLookupID = nil
        resetGamePresence()
        resetServerActivity()
        await discord.disconnect()
    }
}
