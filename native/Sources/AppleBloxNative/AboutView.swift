import SwiftUI

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = (info["AppleBloxReleaseVersion"] ?? info["CFBundleShortVersionString"]) as? String else { return "Development build" }
        if let build = info["CFBundleVersion"] as? String { return "Version \(version) (\(build))" }
        return "Version \(version)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                AppleBloxForkLogo()
                    .frame(width: 42, height: 45)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("AppleBlox Native").font(.title2.weight(.semibold))
                    Text(version).font(.caption).foregroundStyle(.secondary)
                }
                Text("A native SwiftUI launcher for Roblox on macOS.")
                    .font(.callout)
                HStack(spacing: 20) {
                    Link("Fork on GitHub", destination: URL(string: "https://github.com/Belligerently/appleblox-native")!)
                    Link("Original AppleBlox", destination: URL(string: "https://github.com/AppleBlox/appleblox")!)
                }
                .font(.callout)
                Divider().frame(maxWidth: 320)
                VStack(spacing: 4) {
                    Text("Built on the work of AppleBlox and its contributors.")
                    Text("Original logo by @typeofnull · GPL-3.0 license")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}
