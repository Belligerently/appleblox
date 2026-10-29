import AppKit
import AppleBloxCore
import UniformTypeIdentifiers

extension LauncherModel {
    func restoreSavedDockIcon() async {
        do {
            selectedLauncherIcon = try await launcherIconLibrary.selected()
            let bytes = try await launcherIconLibrary.selectedData()
            if let image = NSImage(data: bytes) { NSApplication.shared.applicationIconImage = image }
        } catch {
            selectedLauncherIcon = nil
            launcherIconStatus = "Saved icon unavailable. Restore Native Default to recover. Existing files were preserved."
        }
    }
    func loadLauncherIcons() async {
        guard !isBusy else { return }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        do {
            let catalog = try await launcherIconLibrary.previews()
            launcherIconPreviews = catalog.icons
            selectedLauncherIcon = try await launcherIconLibrary.selected()
            if catalog.skipped > 0 { launcherIconStatus = "Skipped \(catalog.skipped) unreadable imported icons. Their files were preserved." }
        } catch { launcherIconStatus = error.localizedDescription }
    }
    func importLauncherIcon() async {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Launcher Icon"
        panel.allowedContentTypes = [UTType(filenameExtension: "icns")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        do {
            _ = try await launcherIconLibrary.importIcon(from: url)
            let catalog = try await launcherIconLibrary.previews()
            launcherIconPreviews = catalog.icons
            launcherIconStatus = "Imported a copy. Apply an icon to use it; the source file is unchanged."
            record("Imported a launcher icon.")
        } catch { launcherIconStatus = error.localizedDescription }
    }
    func applyLauncherIcon(_ choice: LauncherIconChoice) async {
        guard !isBusy else { return }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        do {
            try await launcherIconLibrary.select(choice) { bytes in
                try await Self.setLauncherIcon(bytes)
            }
            selectedLauncherIcon = choice
            launcherIconStatus = "Dock icon applied and saved. Finder icons are unchanged."
            record("Changed the launcher icon.")
        } catch { launcherIconStatus = error.localizedDescription }
    }
    private static func setLauncherIcon(_ bytes: Data?) throws {
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension == "app", let defaultURL = bundle.url(forResource: "AppIcon-BlueLeaf-Charcoal", withExtension: "icns"),
              let defaultIcon = NSImage(contentsOf: defaultURL) else {
            throw FeatureError.message("Run the built AppleBlox Native app to change its Dock icon.")
        }
        let custom: NSImage?
        if let bytes {
            guard let image = NSImage(data: bytes) else { throw LauncherIconError.invalidIcon }
            custom = image
        } else { custom = nil }
        NSApplication.shared.applicationIconImage = custom ?? defaultIcon
    }
    func removeLauncherIcon(_ choice: LauncherIconChoice) async {
        guard !isBusy, case .custom(let id) = choice else { return }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        do {
            try await launcherIconLibrary.remove(id)
            let catalog = try await launcherIconLibrary.previews()
            launcherIconPreviews = catalog.icons
            launcherIconStatus = "Removed from the library. Its copy remains recoverable in the removed folder."
            record("Removed a launcher icon from the library.")
        } catch { launcherIconStatus = error.localizedDescription }
    }
    func revealLauncherIcons() async {
        do {
            let folder = try await launcherIconLibrary.revealDirectory()
            guard NSWorkspace.shared.open(folder) else { throw LauncherIconError.missingIcon }
        } catch { launcherIconStatus = error.localizedDescription }
    }
}
