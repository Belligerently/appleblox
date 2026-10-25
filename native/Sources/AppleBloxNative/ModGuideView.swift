import AppleBloxCore
import SwiftUI

struct ModGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installing Content Mods").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    step("1. Prepare a resource folder", "Extract the download, then choose the pack folder containing one or more of content, PlatformContent, or ExtraContent. Import the folder, not the ZIP or an individual texture.")
                    Text("My Pack/\n  content/textures/example.png\n  PlatformContent/…\n  ExtraContent/…")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: .rect(cornerRadius: 10))
                    step("2. Import and choose packs", "Use Import in Mods. Enable the packs you want, then choose Rescan Library from the page’s ••• menu to check them. Packs replacing the same resource conflict; disable one. Font and Icon Color generate packs directly.")
                    step("3. Apply when Player is closed", "Quit Roblox, then use Apply Mods. The original resources are backed up. Apply enabled mods to new Roblox sessions can do this automatically before a fresh launch. Some resources may no longer be used by current Roblox versions.")
                    step("Edit an imported pack", "Choose Show Files from that pack’s ••• menu. Edit this imported copy, then Rescan Library to refresh counts and findings. The original download folder is separate. Import new packs explicitly; rescanning does not discover removed or unregistered folders.")
                    step("Restore or remove", "Restore Resources returns Player to its pre-mod backup. Removing a library entry keeps its imported files for recovery; apply again to update Player. Rescanning only reads packs and updates library counts—it does not modify Player or backups.")
                    Text("Supported resources: images (PNG, JPG, WebP, BMP, TGA, DDS, KTX/KTX2), sounds (OGG, MP3, WAV), fonts (TTF/OTF), and JSON. Packs are limited to 10,000 files and 512 MB. Scripts, executables, meshes, and symbolic links are rejected.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Guides & communities").font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        Link("AppleBlox Native support", destination: URL(string: "https://github.com/Belligerently/appleblox-native/issues")!)
                        Link("Original AppleBlox community", destination: URL(string: "https://github.com/AppleBlox/appleblox#contributing")!)
                        Link("Roblox mods on GameBanana", destination: URL(string: "https://gamebanana.com/games/2879")!)
                        Link("Bloxstrap resource-mod guide", destination: URL(string: "https://bloxstraplabs.com/wiki/features/modding/")!)
                    }
                    .font(.callout)
                    Text("Other projects have their own support channels. Use this fork’s issue tracker for Native bugs; the folder locations in Bloxstrap’s Windows guide differ from this app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.trailing, 6)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 520, height: 500)
    }

    private func step(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ModScanResultsView: View {
    let scan: ModLibraryScan
    let mods: [ContentMod]
    @Environment(\.dismiss) private var dismiss

    private var conflicts: [ModLibraryConflict] { scan.activeConflicts(in: mods) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mod Library Scan").font(.title2.bold())
            Text(scan.summary(for: mods)).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if scan.issues.isEmpty && conflicts.isEmpty {
                        ContentUnavailableView("Packs checked", systemImage: "checkmark.circle", description: Text("No invalid packs or enabled conflicts were found. Apply Mods when Player is closed to use your edited files."))
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(scan.issues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(issue.name, systemImage: "exclamationmark.triangle").font(.headline)
                            Text(issue.message).font(.callout).foregroundStyle(.secondary)
                            Text("Fix the files and rescan, or disable this pack before applying.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(conflicts, id: \.path) { conflict in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conflict.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            Text(conflict.names.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                            Text("Disable a pack replacing this resource.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 560, height: 440)
    }
}
