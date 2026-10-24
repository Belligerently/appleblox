import SwiftUI

@main
struct AppleBloxApp: App {
    @State private var model = LauncherModel()

    var body: some Scene {
        Window("AppleBlox Native", id: "main") {
            ContentView(model: model)
                .tint(.orange)
        }
        .defaultSize(width: 1000, height: 700)
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
