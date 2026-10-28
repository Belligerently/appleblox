import AppleBloxCore
import AppKit
import UniformTypeIdentifiers

extension LauncherModel {
    func clearPlayHistory() async {
        guard !isBusy, canSaveHistory else { return }
        updateRunningStatus()
        guard !isRunning else { errorMessage = "Close every Roblox Player before clearing history."; return }
        isWorkingFeature = true; isClearingHistory = true
        defer { isWorkingFeature = false; isClearingHistory = false }
        await historyWriteTask?.value
        guard canSaveHistory else { return }
        historyRevision += 1
        let revision = historyRevision
        do {
            let recovery = try await historyStore.clear(revision: revision)
            history = []
            maintenanceStatus = recovery == nil ? "Cleared local history." : "Cleared local history. Previous sessions are preserved in history-recovery in the native data folder."
            record("Cleared local play history.")
        } catch { report(error) }
    }

    func exportLaunchShortcut(_ game: GameShortcut? = nil) async {
        guard !isBusy else { return }
        let panel = NSSavePanel()
        panel.title = "Export AppleBlox Launch Shortcut"
        panel.allowedContentTypes = [UTType(filenameExtension: "webloc") ?? .data]
        panel.nameFieldStringValue = game == nil ? "Launch AppleBlox.webloc" : "AppleBlox Game.webloc"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        panel.message = "Opens through AppleBlox’s confirmation and launch flow. Keep AppleBlox Native installed and launch it once to register its links. Existing files are never replaced."
        guard panel.runModal() == .OK, let target = panel.url else { return }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        do {
            let placeID = game?.placeID
            try await Task { @concurrent in try LaunchShortcut.save(placeID: placeID, to: target) }.value
            record("Exported an AppleBlox launch shortcut.")
        } catch { report(error) }
    }
}
