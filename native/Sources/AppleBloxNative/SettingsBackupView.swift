import AppKit
import SwiftUI
import AppleBloxCore
import UniformTypeIdentifiers

extension LauncherModel {
    func prepareSettingsExport() {
        guard !isBusy, canSave else { return }
        do { settingsBackupReview = SettingsBackupReview(document: try SettingsBackupDocument(configuration: configuration)) }
        catch { report(error) }
    }
    func prepareSettingsImport() async {
        guard !isBusy, canSave else { return }
        let panel = NSOpenPanel()
        panel.title = "Review Settings Backup"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        do {
            let plan = try await settingsBackupService.prepare(from: source, current: configuration)
            settingsBackupReview = SettingsBackupReview(document: plan.document, restore: plan)
        } catch { report(error) }
    }
    func saveSettingsBackup(_ review: SettingsBackupReview) async throws -> Bool {
        guard !isBusy else { return false }
        let panel = NSSavePanel()
        panel.title = "Save Settings Backup"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AppleBlox-settings-\(String(UUID().uuidString.prefix(8))).json"
        panel.message = "This readable file includes game names and engine flag values. Keep it private. Existing files are never replaced."
        guard panel.runModal() == .OK, let target = panel.url else { return false }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        try await settingsBackupService.export(review.document, to: target)
        maintenanceStatus = "Saved a portable settings backup. Credentials, mod files and Player backups were excluded."
        record("Exported a portable settings backup.")
        return true
    }
}

struct SettingsBackupReviewView: View {
    let model: LauncherModel
    let review: SettingsBackupReview
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var failure: String?
    @State private var confirmed = false
    private var restoring: Bool { review.restore != nil }
    private var config: NativeConfiguration { review.document.configuration }
    private var preview: String {
        guard let data = try? review.document.data else { return "Unreadable backup" }
        let text = String(decoding: data.prefix(65_536), as: UTF8.self)
        return text + (data.count > 65_536 ? "\n… Preview limited to 64 KiB. The complete settings document is saved." : "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(restoring ? "Restore Settings Backup" : "Export Settings Backup").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(config.shortcuts.count) saved games · \(config.engine.profiles.count) engine profiles")
                        .font(.headline)
                    Text("Includes appearance, the active custom palette, saved games and profile assignments, engine profiles/flags and preferences. Names and flag values are readable in this file; keep it private.")
                    Text("Excludes accounts and sessions, installation paths, mod files, icon/theme libraries, history, logs and Player backups. This is a settings backup, not a complete data archive.")
                    if restoring {
                        Text("Replaces saved games, profiles, appearance and preferences. Current accounts, mod records, installation selection and resource backups stay intact. A private copy of the previous settings is saved in the native data folder’s settings-recovery directory.")
                        Text("Launch application, FPS workaround, Discord/SDK, tracking, notifications, server lookup, update checks and automatic updates start OFF after restore. Review and enable them again in their pages. Roblox must be closed; restoring does not change Player files.")
                    }
                    DisclosureGroup("Preview backup JSON") {
                        Text(preview)
                            .font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 0, maxHeight: .infinity)
            if restoring { Toggle("Replace these settings and keep the recovery copy", isOn: $confirmed) }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red).lineLimit(3) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(restoring ? "Restore Settings" : "Save Backup…") {
                    working = true
                    Task {
                        defer { working = false }
                        do {
                            if let plan = review.restore { try await model.restoreSettings(plan); dismiss() }
                            else if try await model.saveSettingsBackup(review) { dismiss() }
                        } catch { failure = error.localizedDescription }
                    }
                }.disabled(model.isBusy || (restoring && !confirmed))
            }
        }.padding(20).frame(width: 580, height: 450)
        .disabled(working).interactiveDismissDisabled(working)
    }
}
