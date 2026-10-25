import SwiftUI

/// Bundled, native instructions: reading help requires neither network access nor a web renderer.
struct NativeGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AppleBlox Native Guide").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topic("Get started", "Use Installation under More to choose Roblox Player or check for a Roblox update. Launcher opens the selected installation. My Games saves numeric place IDs or full Roblox game-page links; your Player login determines which account joins.")
                    topic("Engine profiles", "Choose a profile in Engine, then Edit its presets or custom flags. Save Profile stores the draft; Apply Now writes settings to Player and backs up its original file. Quit every Player first. A game can have its own profile; imported game overlays can include the selected profile’s flags.")
                    topic("Content mods", "In Mods, import a folder containing content, PlatformContent or ExtraContent. Enable the packs you want, rescan to check files/conflicts, then Apply Mods with Player closed. Font and Icon Color create packs. The Mod Guide has folder examples and supported resource types.")
                    topic("Accounts", "Accounts under More offers private website sign-in and explicit import of Player’s current login. Saved sessions use macOS Keychain. Selecting an account changes Player’s login on the next fresh launch; separate Player instances do not isolate accounts.")
                    topic("Activity and privacy", "Integrations controls optional local history, Discord presence, server-location lookup and notifications. Location lookup sends the server’s public IPv4 address to ipinfo.io. Notifications ask macOS permission when enabled. Game-specific tracking pauses with multiple Players and resumes at the next single-Player game join.")
                    topic("Updates", "Installation checks and installs Roblox LIVE updates while keeping the previous app. Automatic checks/installations require AppleBlox to stay open. These update Roblox Player; native launcher self-updating has not been implemented.")
                    topic("Restore and troubleshoot", "Engine’s Restore Original and Mods’ Restore Resources use the saved backups. They are separate from Reset Appearance. Diagnostics shows this session’s launcher activity; Roblox Logs opens Player’s logs. Copy Diagnostics produces a fixed-field report that excludes account data, names, paths, URLs and raw logs.")
                    topic("Experimental features", "Engine → Feature Support explains rendering limitations and the default-off temporary-display FPS workaround. Actual FPS/display behavior still needs hardware testing. Roblox can ignore flags or reuse/close requested additional Players. Lighting technology and a general post-processing toggle are unavailable.")
                    Divider()
                    Link("Report a Native issue", destination: AppResources.support)
                    Link("Source and release information", destination: AppResources.repository)
                    Text("This guide is included with the app. External links open in your browser; no report or account data is sent automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 4)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 540, height: 450)
    }
    private func topic(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
