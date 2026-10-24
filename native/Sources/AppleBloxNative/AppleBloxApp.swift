import SwiftUI

@main
struct AppleBloxApp: App {
    @State private var model = LauncherModel()

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
                    .disabled(model.installation == nil || model.isLaunching)
                Button("Refresh Installation", action: model.refresh)
                Button("Choose Installation…", action: model.chooseInstallation)
            }
        }
    }
}
