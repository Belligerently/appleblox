import AppKit
import AppleBloxCore
import UniformTypeIdentifiers

extension LauncherModel {
    func diagnosticsReport() async -> DiagnosticsReport {
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
        return report
    }

    func copyDiagnostics() async {
        let report = await diagnosticsReport()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(report.text, forType: .string) {
            maintenanceStatus = "Copied diagnostics without account data, names, paths, URLs, or raw logs."
        } else { errorMessage = "Couldn’t copy diagnostics to the clipboard." }
    }

    func openLauncherLogs() async {
        do {
            let directory = try await launcherLogs.checkedDirectory()
            if !NSWorkspace.shared.open(directory) { throw SupportFileError.unsafeFile }
        } catch { report(error) }
    }

    func prepareSupportBundle() async {
        guard !isBusy else { return }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        await launcherLogTask?.value
        let report = await diagnosticsReport()
        let logs = try? await launcherLogs.snapshot()
        do {
            supportBundleReview = try SupportBundleDraft(report: report,
                settings: canSave ? SupportSettingsSummary(configuration: configuration) : nil, logs: logs)
        } catch { self.report(error) }
    }

    func saveSupportBundle(_ draft: SupportBundleDraft, includeLogs: Bool) async throws -> Bool {
        guard !isBusy else { return false }
        let panel = NSSavePanel()
        panel.title = "Save Reviewed Support Bundle"
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "AppleBlox-support-\(String(UUID().uuidString.prefix(8))).zip"
        panel.message = "Choose a new filename. Existing support bundles are never replaced. Nothing is uploaded."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        do { try await supportExporter.save(draft, includeLogs: includeLogs, to: url) }
        catch {
            record("Support export failed.", event: .operationFailed, failure: SafeLogFailure(error))
            throw error
        }
        maintenanceStatus = "Saved the reviewed support ZIP. Nothing was uploaded."
        record("Exported a reviewed support bundle.", event: .supportExported)
        return true
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
