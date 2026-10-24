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
    private(set) var status = "Checking for Roblox…"
    private(set) var canSave = true
    var errorMessage: String?
    let store: ConfigurationStore

    init(directory: URL = ConfigurationStore.defaultDirectory()) {
        store = ConfigurationStore(directory: directory)
        do {
            configuration = try store.load()
        } catch {
            canSave = false
            errorMessage = "Couldn’t read native settings. The file has been preserved. \(error.localizedDescription)"
        }
        refresh()
    }

    func refresh() {
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
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: RobloxInstallation.bundleIdentifier).isEmpty
        status = installation == nil ? "Roblox not found" : (isRunning ? "Roblox is running" : "Ready to launch")
        record(installation.map { "Detected Roblox \($0.version)." } ?? "No Roblox Player found. Choose an installation to continue.")
    }

    func chooseInstallation() {
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
        do {
            var next = configuration
            next.customRobloxPath = nil
            try persist(next)
            refresh()
        } catch { report(error) }
    }

    func saveShortcut(id: UUID?, name: String, placeID: String) throws {
        let shortcut = try GameShortcut(id: id ?? UUID(), name: name, placeID: placeID)
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

    func launch(shortcut: GameShortcut? = nil) async {
        guard !isLaunching else { return }
        isLaunching = true
        defer { isLaunching = false }
        do {
            guard let installation else { throw InstallationError.missingInstallation }
            let verified = try RobloxInstallation.inspect(installation.url)
            let options = NSWorkspace.OpenConfiguration()
            options.activates = true
            if let shortcut {
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

    private func persist(_ next: NativeConfiguration) throws {
        guard canSave else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Settings are unreadable. Move native-settings.json out of the data folder and restart to create fresh settings."])
        }
        try store.save(next)
        configuration = next
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        record("Error: \(error.localizedDescription)")
    }

    private func record(_ message: String) {
        activity.insert(ActivityEntry(message: message), at: 0)
        if activity.count > 100 { activity.removeLast(activity.count - 100) }
    }
}
