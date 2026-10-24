import AppKit
import SwiftUI

@main
struct AppleBloxApp: App {
    @State private var model = LauncherModel()

    init() {
        if let url = Bundle.main.url(forResource: "AppIcon-BlueLeaf-Charcoal", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        Window("AppleBlox Native", id: "compact-launcher") {
            ContentView(model: model)
                .tint(AppleBloxTheme.primary)
        }
        .defaultSize(width: 660, height: 460)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Roblox") {
                Button("Launch Roblox") { Task { await model.launch() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.installation == nil || model.isBusy)
                Button("Refresh Installation", action: model.refresh)
                Button("Choose Installation…", action: model.chooseInstallation)
            }
        }
    }
}
