import SwiftUI

private enum AboutSheet: String, Identifiable {
    case guide, credits
    var id: Self { self }
}

struct AboutView: View {
    @State private var sheet: AboutSheet?
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = (info["AppleBloxReleaseVersion"] ?? info["CFBundleShortVersionString"]) as? String else { return "Development build" }
        if let build = info["CFBundleVersion"] as? String { return "Version \(version) (\(build))" }
        return "Version \(version)"
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                AppleBloxForkLogo().frame(width: 42, height: 45).accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("AppleBlox Native").font(.title2.weight(.semibold))
                    Text(version).font(.caption).foregroundStyle(.secondary)
                }
                Text("A native SwiftUI launcher for Roblox on macOS.").font(.callout)
                HStack(spacing: 12) {
                    Button("Documentation", systemImage: "book") { sheet = .guide }
                    Button("Credits", systemImage: "person.2") { sheet = .credits }
                    Link("Support", destination: AppResources.support)
                }.controlSize(.small)
                HStack(spacing: 16) {
                    Link("Fork on GitHub", destination: AppResources.repository)
                    Link("Original AppleBlox", destination: AppResources.upstream)
                }.font(.callout)
                HStack(spacing: 16) {
                    Link("Original community", destination: AppResources.community)
                    Link("GPL-3.0 license", destination: AppResources.license)
                }.font(.caption)
                Text("Original logo by @typeofnull · Built on AppleBlox and its contributors.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $sheet) { page in
            switch page { case .guide: NativeGuideView(); case .credits: CreditsView() }
        }
    }
}
