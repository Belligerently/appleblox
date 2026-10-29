import SwiftUI

struct EngineCompatibilityView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feature Support").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    support("FPS workaround — experimental", "Requests the original approach: a temporary 240 Hz virtual display. Default off, one online display, fresh Player only. Actual FPS and display restoration still need live testing; Roblox’s in-game frame-rate setting also applies.")
                    support("Lighting technology — unavailable", "The old lighting override flags are outside the inherited local-client allowlist. The current original AppleBlox source no longer offers this control. Lighting is controlled by Roblox and the experience.")
                    support("General visual-effects toggle — unavailable", "The old post-processing override is outside the inherited allowlist. Gray sky, textures, object detail and voxelizer controls remain separate supported flag requests.")
                    support("Multiple Players — best effort", "Uses macOS’s new-instance request and checks the returned process against running Players. Roblox can reuse or close it. Account isolation is not provided. Per-game activity pauses while more than one Player runs.")
                    Link("Bloxstrap’s removed-feature notes", destination: URL(string: "https://bloxstraplabs.com/versions/2.10.0/")!)
                    Link("Original AppleBlox engine controls", destination: URL(string: "https://github.com/AppleBlox/appleblox/blob/main/frontend/src/windows/main/pages/Engine.svelte")!)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 540, height: 410)
    }
    private func support(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }
}
