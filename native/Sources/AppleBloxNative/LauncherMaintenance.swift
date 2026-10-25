import AppKit
import AppleBloxCore

extension LauncherModel {
    func copyDiagnostics() async {
        let cacheCount = await gameCatalog.cachedGameCount
        let info = Bundle.main.infoDictionary ?? [:]
        var report = DiagnosticsReport()
        report.appVersion = (info["AppleBloxReleaseVersion"] ?? info["CFBundleShortVersionString"]) as? String ?? "Development"
        report.appBuild = info["CFBundleVersion"] as? String ?? "Unknown"
        #if arch(arm64)
        report.architecture = "arm64"
        #elseif arch(x86_64)
        report.architecture = "x86_64"
        #endif
        report.playerVersion = installation?.version
        report.playerRunning = isRunning
        report.settingsReadable = canSave
        report.gameCount = configuration.shortcuts.count
        report.profileCount = configuration.engine.profiles.count
        report.modCount = configuration.features.mods.count
        report.metadataCount = cacheCount
        report.hasEngineBackup = hasEngineBackup
        report.hasModBackup = hasModBackup
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(report.text, forType: .string) {
            maintenanceStatus = "Copied diagnostics without account data, names, paths, URLs, or raw logs."
        } else { errorMessage = "Couldn’t copy diagnostics to the clipboard." }
    }

    func clearGameDetailsCache() async {
        guard !isBusy else { return }
        isWorkingFeature = true
        maintenanceStatus = "Clearing saved game details…"
        defer { isWorkingFeature = false }
        gameDetailsTask?.cancel(); gameDetailsTask = nil; gameDetailsLookupID = nil
        do {
            let count = try await gameCatalog.clearCache()
            currentGameDetails = nil
            nextGameDetailsAttempt = Date().addingTimeInterval(60)
            maintenanceStatus = "Cleared \(count) cached \(count == 1 ? "game" : "games"). New lookups fetch fresh details."
            record("Cleared the public game-details cache.")
        } catch {
            maintenanceStatus = "The game-details cache could not be cleared."
            report(error)
        }
    }
}
