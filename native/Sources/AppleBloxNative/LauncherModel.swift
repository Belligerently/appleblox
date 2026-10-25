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
    let accountVault = AccountVault()
    let logReader = PlayerLogReader()
    let discord = DiscordPresenceClient()
    let historyStore: PlayHistoryStore
    let gameCatalog: GameCatalog
    var isWorkingFeature = false
    var featureStatus = ""
    var hasModBackup = false
    var latestRelease: RobloxRelease?
    var updateStatus = "Check for the latest Roblox release."
    var isCheckingUpdates = false
    var updateTask: Task<Void, Never>?
    var previousInstallation: URL?
    var currentSession: PlaySession?
    var history: [PlaySession] = []
    var canSaveHistory = true
    var historyRevision = 0
    var discordStatus = "Off"
    var isQuittingAfterPlayer = false
    var pendingLink: LaunchLink?
    var isBusy: Bool { isLaunching || isApplyingEngine || isWorkingFeature }

    init(directory: URL = ConfigurationStore.defaultDirectory()) {
        store = ConfigurationStore(directory: directory)
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
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: RobloxInstallation.bundleIdentifier).isEmpty
        status = installation == nil ? "Roblox not found" : (isRunning ? "Roblox is running" : "Ready to launch")
        record(installation.map { "Detected Roblox \($0.version)." } ?? "No Roblox Player found. Choose an installation to continue.")
        Task { await refreshEngineBackup() }
        Task { await refreshModBackup() }
    }

    func updateRunningStatus() {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: RobloxInstallation.bundleIdentifier).isEmpty
        let playerClosed = isRunning && !running
        if running != isRunning {
            record(running ? "Roblox started." : "Roblox quit.")
            if !running { finishCurrentSession() }
        }
        isRunning = running
        status = installation == nil ? "Roblox not found" : (running ? "Roblox is running" : "Ready to launch")
        if playerClosed { quitLauncherAfterPlayerExit() }
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
        defer { isLaunching = false }
        do {
            guard let installation else { throw InstallationError.missingInstallation }
            let verified = try RobloxInstallation.inspect(installation.url)
            let linkedProfile = shortcut?.engineProfileID.flatMap { id in configuration.engine.profiles.first { $0.id == id } }
            if (configuration.engine.applyOnLaunch || linkedProfile != nil) && !isRunning {
                guard let profile = linkedProfile ?? configuration.engine.selectedProfile else { throw EngineError.invalidProfiles }
                try await clientSettings.apply(profile.resolvedFlags(), to: verified)
                await refreshEngineBackup()
                engineStatus = "Applied \(profile.name) before launch."
                record(engineStatus)
            } else if configuration.engine.applyOnLaunch {
                record("Using the running Player. Engine changes apply to the next fresh Roblox session.")
            }
            try await prepareFeatureLaunch(verified)
            let options = NSWorkspace.OpenConfiguration()
            options.activates = true
            options.createsNewApplicationInstance = configuration.features.newPlayerInstance
            if let link {
                _ = try await NSWorkspace.shared.open([link.url], withApplicationAt: verified.url, configuration: options)
            } else if let shortcut {
                let validShortcut = try shortcut.validated()
                _ = try await NSWorkspace.shared.open([validShortcut.launchURL], withApplicationAt: verified.url, configuration: options)
            } else {
                _ = try await NSWorkspace.shared.openApplication(at: verified.url, configuration: options)
            }
            isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: RobloxInstallation.bundleIdentifier).isEmpty
            status = "Opened Roblox"
            record(shortcut.map { "Sent launch request for \($0.name)." } ?? "Opened Roblox Player.")
        } catch {
            status = "Launch failed"
            report(error)
        }
    }

    func revealInstallation() {
        guard let installation else { return }
        NSWorkspace.shared.activateFileViewerSelecting([installation.url])
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
        record("Saved engine profile: \(profile.name).")
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
            record(engineStatus)
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
            record(engineStatus)
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
        guard canSave else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Settings are unreadable. Move native-settings.json out of the data folder and restart to create fresh settings."])
        }
        try store.save(next)
        configuration = next
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
        record("Error: \(error.localizedDescription)")
    }

    func record(_ message: String) {
        activity.insert(ActivityEntry(message: message), at: 0)
        if activity.count > 100 { activity.removeLast(activity.count - 100) }
    }
}
