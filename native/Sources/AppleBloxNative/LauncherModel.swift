import AppKit
import AppleBloxCore
import Observation
import UniformTypeIdentifiers

struct ActivityEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
}

@MainActor @Observable
final class LauncherModel {
    private(set) var configuration = NativeConfiguration()
    private(set) var installation: RobloxInstallation?
    private(set) var activity: [ActivityEntry] = []
    private(set) var isLaunching = false
    private(set) var isRunning = false
    private(set) var isApplyingEngine = false
    private(set) var hasEngineBackup = false
    private(set) var engineStatus = "No settings applied this session."
    private(set) var status = "Checking for Roblox…"
    private(set) var canSave = true
    var errorMessage: String?
    let store: ConfigurationStore
    let clientSettings: ClientSettingsStore
    let modStore: ContentModStore
    let updateService = RobloxUpdateService()
    let accountVault: AccountVault
    let logReader = PlayerLogReader()
    let discord = DiscordPresenceClient()
    let historyStore: PlayHistoryStore
    let experienceSearch = ExperienceSearch()
    let settingsBackupService: SettingsBackupService
    var settingsBackupReview: SettingsBackupReview?
    var isRestoringSettings = false
    let gameCatalog: GameCatalog
    var isWorkingFeature = false
    var featureStatus = ""
    var hasModBackup = false
    var modPreviewRevision = 0
    var modLibraryScan: ModLibraryScan?
    var latestRelease: RobloxRelease?
    var updateStatus = "Check for the latest Roblox release."
    var isCheckingUpdates = false
    var updateTask: Task<Void, Never>?
    var previousInstallation: URL?
    let presenceArtworkCatalog = PresenceArtworkCatalog()
    var gamePresence = BloxstrapPresenceState()
    var gamePresenceArtwork: [String: URL] = [:]
    var presenceArtworkTask: Task<Void, Never>?
    var presenceArtworkLookupID: UUID?
    var nextPresenceArtworkAttempt = Date.distantPast
    let serverLocations = ServerLocationService()
    let gameNotifications = GameNotifications()
    var serverConnection = ServerConnectionTracker()
    var serverActivityTask: Task<Void, Never>?
    var serverActivityRequestID: UUID?
    var serverNoticePending = false
    var serverNoticeLimiter = ServerNoticeLimiter()
    var serverRegion: ServerRegion?
    var serverLocationStatus = "Waiting for a new game server connection."
    var notificationStatus = "Permission has not been requested"
    var isRequestingNotifications = false
    var playerInstances = PlayerInstances([])
    var needsPlayerLogBaseline = true
    let fpsSession = FPSWorkaroundSession(driver: NativeDisplayDriver())
    var fpsActive = false
    var fpsStatus = "Off"
    var currentSession: PlaySession?
    var currentGameDetails: GameDetails?
    var gameDetailsTask: Task<Void, Never>?
    var gameDetailsLookupID: UUID?
    var nextGameDetailsAttempt = Date.distantPast
    var history: [PlaySession] = []
    var canSaveHistory = true
    var isClearingHistory = false
    var historyRevision = 0
    var discordStatus = "Off"
    var maintenanceStatus = ""
    var isResetting = false
    var resetReview: NativeResetPlan?
    var resetCompleted = false
    var servicesTask: Task<Void, Never>?
    var servicesTaskID: UUID?
    var historyWriteTask: Task<Void, Never>?
    let resetService: NativeResetService
    let nativeThemes: NativeThemeStore
    let launcherIconLibrary: LauncherIconLibrary
    var launcherIconPreviews: [LauncherIconPreview] = []
    var selectedLauncherIcon: LauncherIconChoice? = .default
    var launcherIconStatus = "Choose an icon for this launcher."
    let launcherLogs: LauncherLogStore
    let supportExporter = SupportBundleExporter()
    var supportBundleReview: SupportBundleDraft?
    var launcherLogTask: Task<Void, Never>?
    var launcherLogWriteID: UUID?
    var canWriteLauncherLogs = true
    var launcherLogStatus = "Saved events exclude raw activity messages."
    var isQuittingAfterPlayer = false
    var legacyImportReview: LegacyProfileImportPlan?
    var pendingLink: LaunchLink?
    var isBusy: Bool { isResetting || isRestoringSettings || isLaunching || isApplyingEngine || isWorkingFeature }

    init(directory: URL = ConfigurationStore.defaultDirectory()) {
        accountVault = AccountVault(service: AccountVault.service(for: directory))
        resetService = NativeResetService(dataDirectory: directory)
        nativeThemes = NativeThemeStore(dataDirectory: directory)
        launcherIconLibrary = LauncherIconLibrary(dataDirectory: directory,
            resources: Bundle.main.resourceURL ?? directory.appendingPathComponent("missing-resources"))
        launcherLogs = LauncherLogStore(dataDirectory: directory)
        store = ConfigurationStore(directory: directory)
        settingsBackupService = SettingsBackupService(directory: directory)
        clientSettings = ClientSettingsStore(directory: directory.appendingPathComponent("engine-backups", isDirectory: true))
        modStore = ContentModStore(directory: directory.appendingPathComponent("mods", isDirectory: true))
        historyStore = PlayHistoryStore(directory: directory)
        gameCatalog = GameCatalog(directory: directory)
        do {
            configuration = try store.load()
        } catch {
            canSave = false
            errorMessage = "Couldn’t read native settings. The file has been preserved. \(error.localizedDescription)"
        }
        fpsStatus = configuration.features.experimentalFPSWorkaround ? "Will start before the next fresh Player launch." : "Off"
        record("AppleBlox Native started.", event: .appStarted)
        refresh()
    }

    func refresh() {
        guard !isBusy else { return }
        var candidates: [URL] = []
        if let customPath = configuration.customRobloxPath {
            candidates.append(URL(fileURLWithPath: customPath))
        }
        candidates.append(URL(fileURLWithPath: "/Applications/Roblox.app"))
        candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Roblox.app"))
        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: RobloxInstallation.bundleIdentifier) {
            candidates.append(registered)
        }
        installation = RobloxInstallation.discover(candidates: candidates).first
        hasEngineBackup = false
        updateRunningStatus()
        status = installation == nil ? "Roblox not found" : (isRunning ? "Roblox is running" : "Ready to launch")
        record(installation.map { "Detected Roblox \($0.version)." } ?? "No Roblox Player found. Choose an installation to continue.", event: .playerDetected, count: installation == nil ? 0 : 1)
        Task { await refreshEngineBackup() }
        Task { await refreshModBackup() }
    }

    func updateRunningStatus() {
        let next = PlayerInstances(Set(NSRunningApplication.runningApplications(withBundleIdentifier: RobloxInstallation.bundleIdentifier).map(\.processIdentifier)))
        let lastClosed = next.lastPlayerClosed(comparedTo: playerInstances)
        if next != playerInstances {
            if next.count > 0 && playerInstances.count > 0 { needsPlayerLogBaseline = true }
            record("Roblox Players running: \(next.count).", event: .playerCountChanged, count: next.count)
            finishCurrentSession()
        }
        playerInstances = next
        isRunning = next.count > 0
        status = installation == nil ? "Roblox not found" : (isRunning ? "Roblox is running (\(next.count))" : "Ready to launch")
        if lastClosed {
            guard stopFPSWorkaround() else { return }
            handlePlayerExit()
        }
    }

    func quitRoblox() {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: RobloxInstallation.bundleIdentifier)
        let accepted = applications.map { $0.terminate() }
        if accepted.contains(false) { errorMessage = "Roblox declined to quit. You can close it from its own menu." }
        else if !applications.isEmpty { record("Asked Roblox to quit.") }
    }

    func chooseInstallation() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Roblox Player"
        panel.prompt = "Choose Roblox"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let selected = try RobloxInstallation.inspect(url)
            var next = configuration
            next.customRobloxPath = selected.url.path
            try persist(next)
            refresh()
        } catch { report(error) }
    }

    func useAutomaticDetection() {
        guard !isBusy else { return }
        do {
            var next = configuration
            next.customRobloxPath = nil
            try persist(next)
            refresh()
        } catch { report(error) }
    }

    func didInstallPlayer(at url: URL) throws {
        installation = try RobloxInstallation.inspect(url)
        hasEngineBackup = false
        hasModBackup = false
        updateRunningStatus()
    }

    func saveShortcut(id: UUID?, name: String, placeID: String, engineProfileID: UUID? = nil) throws {
        var shortcut = try GameShortcut(id: id ?? UUID(), name: name, placeID: RobloxPlaceInput.placeID(from: placeID))
        shortcut.engineProfileID = engineProfileID
        var next = configuration
        if let index = next.shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            next.shortcuts[index] = shortcut
        } else {
            next.shortcuts.append(shortcut)
        }
        try persist(next)
        record("Saved game shortcut: \(shortcut.name).")
    }

    func removeShortcut(_ shortcut: GameShortcut) {
        do {
            var next = configuration
            next.shortcuts.removeAll { $0.id == shortcut.id }
            try persist(next)
            record("Removed game shortcut: \(shortcut.name).")
        } catch { report(error) }
    }

    func launch(shortcut: GameShortcut? = nil, link: LaunchLink? = nil) async {
        guard !isBusy else { return }
        updateRunningStatus()
        isLaunching = true
        record("Requested a Player launch.", event: .launchRequested)
        let before = playerInstances
        var startedDisplayHere = false
        defer { isLaunching = false }
        do {
            guard let installation else { throw InstallationError.missingInstallation }
            let verified = try RobloxInstallation.inspect(installation.url)
            let requestedURL = try link?.isLauncherOnly == true ? nil : (link?.url ?? shortcut?.validated().launchURL)
            let plan = try PlayerLaunchPlan(url: requestedURL, legacyResolution: configuration.features.legacyResolution,
                                            newInstance: configuration.features.newPlayerInstance, playerRunning: isRunning)
            startedDisplayHere = try await fpsSession.prepare(enabled: configuration.features.experimentalFPSWorkaround, players: before)
            fpsActive = fpsSession.active
            if fpsActive { fpsStatus = "Temporary 240 Hz display active while Players are running." }
            let mappedGame = shortcut ?? link?.placeID.flatMap { id in configuration.shortcuts.first { $0.placeID == id } }
            let linkedProfile = mappedGame?.engineProfileID.flatMap { id in configuration.engine.profiles.first { $0.id == id } }
            if (configuration.engine.applyOnLaunch || linkedProfile != nil) && !isRunning {
                guard let profile = linkedProfile ?? configuration.engine.selectedProfile else { throw EngineError.invalidProfiles }
                try await clientSettings.apply(configuration.engine.resolvedFlags(for: profile.id), to: verified)
                await refreshEngineBackup()
                engineStatus = "Applied \(profile.name) before launch."
                record(engineStatus, event: .engineApplied)
            } else if configuration.engine.applyOnLaunch {
                record("Using the running Player. Engine changes apply to the next fresh Roblox session.")
            }
            try await prepareFeatureLaunch(verified)
            let options = NSWorkspace.OpenConfiguration()
            options.activates = true
            options.createsNewApplicationInstance = plan.createsNewInstance
            options.arguments = plan.arguments
            let application: NSRunningApplication
            if let url = plan.urlToOpen {
                application = try await NSWorkspace.shared.open([url], withApplicationAt: verified.url, configuration: options)
            } else {
                application = try await NSWorkspace.shared.openApplication(at: verified.url, configuration: options)
            }
            // A Launch Services return value alone doesn't prove a second Player remained alive.
            try await Task.sleep(for: .milliseconds(750))
            updateRunningStatus()
            let outcome = PlayerLaunchOutcome.evaluate(requestNew: plan.createsNewInstance, before: before.ids,
                                                       after: playerInstances.ids, reportedPID: application.processIdentifier)
            switch outcome {
            case .opened: status = "Opened Roblox"
            case .newInstance: status = "Opened a new Roblox Player"
            case .replacedExisting: status = "Roblox opened a new Player and closed the previous Players"
            case .reusedExisting: status = "Roblox reused an existing Player"
            case .unconfirmed:
                status = "Player launch could not be confirmed"
                try fpsSession.launchFailed(startedHere: startedDisplayHere, players: playerInstances)
                fpsActive = fpsSession.active
            }
            record(status, event: .launchCompleted)
        } catch {
            let launchError = error
            updateRunningStatus()
            do { try fpsSession.launchFailed(startedHere: startedDisplayHere || fpsSession.active, players: playerInstances) }
            catch { report(error) }
            fpsActive = fpsSession.active
            status = "Launch failed"
            report(launchError)
        }
    }

    func revealInstallation() {
        guard let installation else { return }
        NSWorkspace.shared.activateFileViewerSelecting([installation.url])
    }

    func openPlayerContents() {
        guard let installation else { errorMessage = "Choose a Roblox installation first."; return }
        do {
            let folder = try installation.contentsDirectory()
            guard NSWorkspace.shared.open(folder) else { throw FeatureError.message("Couldn’t open Player’s Contents folder in Finder.") }
        } catch { report(error) }
    }

    func openRobloxLogs() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Roblox")
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Roblox hasn’t created its logs folder on this Mac yet."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func saveEngineProfile(_ profile: EngineProfile) throws {
        let profile = try profile.validated()
        var next = configuration
        if let index = next.engine.profiles.firstIndex(where: { $0.id == profile.id }) {
            next.engine.profiles[index] = profile
        } else { next.engine.profiles.append(profile) }
        next.engine.selectedProfileID = profile.id
        try persist(next)
        record("Saved engine profile: \(profile.name).", event: .profileSaved)
    }

    func selectEngineProfile(_ id: UUID) {
        do {
            var next = configuration
            next.engine.selectedProfileID = id
            try persist(next)
        } catch { report(error) }
    }

    func removeEngineProfile(_ profile: EngineProfile) {
        guard configuration.engine.profiles.count > 1 else { return }
        do {
            var next = configuration
            next.engine.profiles.removeAll { $0.id == profile.id }
            for index in next.shortcuts.indices where next.shortcuts[index].engineProfileID == profile.id { next.shortcuts[index].engineProfileID = nil }
            if next.engine.selectedProfileID == profile.id { next.engine.selectedProfileID = next.engine.profiles[0].id }
            try persist(next)
        } catch { report(error) }
    }

    func setApplyEngineOnLaunch(_ enabled: Bool) {
        do {
            var next = configuration
            next.engine.applyOnLaunch = enabled
            try persist(next)
        } catch { report(error) }
    }

    func applyEngineProfile() async {
        guard !isBusy else { return }
        updateRunningStatus()
        guard !isRunning else { errorMessage = "Quit Roblox before applying engine settings."; return }
        guard let installation, let profile = configuration.engine.selectedProfile else { return }
        isApplyingEngine = true
        defer { isApplyingEngine = false }
        do {
            try await clientSettings.apply(profile.resolvedFlags(), to: installation)
            engineStatus = "Applied \(profile.name). Ready for the next Roblox launch."
            record(engineStatus, event: .engineApplied)
        } catch { report(error) }
        await refreshEngineBackup()
    }

    func restoreEngineSettings() async {
        guard !isBusy else { return }
        updateRunningStatus()
        guard !isRunning else { errorMessage = "Quit Roblox before restoring engine settings."; return }
        guard let installation else { return }
        isApplyingEngine = true
        defer { isApplyingEngine = false }
        do {
            // Disable automatic application first so the next launch keeps the restored settings.
            var next = configuration
            next.engine.applyOnLaunch = false
            try persist(next)
            try await clientSettings.restore(installation)
            engineStatus = "Restored the original settings. Apply on launch is off."
            record(engineStatus, event: .engineRestored)
        } catch { report(error) }
        await refreshEngineBackup()
    }

    func exportEngineProfile() {
        guard let profile = configuration.engine.selectedProfile else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ClientAppSettings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(FastFlags.json(profile.resolvedFlags()).utf8).write(to: url, options: .atomic)
            record("Exported engine flags for \(profile.name).")
        } catch { report(error) }
    }

    private func refreshEngineBackup() async {
        guard let installation else { hasEngineBackup = false; return }
        let exists = await clientSettings.hasBackup(for: installation)
        if self.installation == installation { hasEngineBackup = exists }
    }

    func persist(_ next: NativeConfiguration) throws {
        guard canSave, !isResetting, !isRestoringSettings else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Settings are unreadable. Move native-settings.json out of the data folder and restart to create fresh settings."])
        }
        try store.save(next)
        configuration = next
        record("Saved native settings.", event: .settingsSaved)
    }

    func restoreSettings(_ plan: SettingsRestorePlan) async throws {
        guard !isBusy, canSave else { throw SettingsBackupError.changed }
        updateRunningStatus()
        guard !isRunning, !fpsActive else { throw FeatureError.message("Close every Roblox Player before restoring settings.") }
        isRestoringSettings = true
        defer { isRestoringSettings = false }
        let recovery = try await settingsBackupService.restore(plan, current: configuration)
        configuration = plan.restored
        fpsStatus = "Off"
        await discord.disconnect()
        resetGamePresence()
        resetServerActivity()
        maintenanceStatus = "Settings restored. Previous settings: \(recovery.lastPathComponent) in settings-recovery. Review integrations and launch automation before enabling them again."
        record("Restored a reviewed settings backup.")
        isRestoringSettings = false
        refresh()
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
        record("Error: \(error.localizedDescription)", event: .operationFailed, failure: SafeLogFailure(error))
    }

    func record(_ message: String, event: LauncherLogEvent = .activity, count: Int? = nil, failure: SafeLogFailure? = nil) {
        activity.insert(ActivityEntry(message: message), at: 0)
        if activity.count > 100 { activity.removeLast(activity.count - 100) }
        guard canWriteLauncherLogs, !isResetting else { return }
        // Preserve UI event order across asynchronous actor writes. Never persist `message`.
        let previous = launcherLogTask
        let writeID = UUID()
        launcherLogWriteID = writeID
        let date = Date()
        launcherLogTask = Task { [weak self, launcherLogs] in
            await previous?.value
            guard let self, self.canWriteLauncherLogs else { return }
            do { try await launcherLogs.append(event, count: count, failure: failure, date: date) }
            catch {
                self.canWriteLauncherLogs = false
                self.launcherLogStatus = "Saved logs unavailable. Existing files were preserved; restart to retry."
            }
            if self.launcherLogWriteID == writeID { self.launcherLogTask = nil }
        }
    }
}
