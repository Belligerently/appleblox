import SwiftUI

private struct ContributorCredit: Identifiable {
    let name: String
    let detail: String
    var profile: URL? = nil
    var id: String { name }
}

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    // Historical roles from the inherited contributor collection, not claims about current fork roles.
    private let original: [ContributorCredit] = [
        .init(name: "OrigamingWasTaken", detail: "Original app maintainer and main developer", profile: URL(string: "https://github.com/OrigamingWasTaken")),
        .init(name: "Satalights", detail: "Moderator and tester", profile: URL(string: "https://github.com/SoiKr")),
        .init(name: "allFiction", detail: "Moderator and tester", profile: URL(string: "https://github.com/AngrySausage")),
        .init(name: "TrisecTroop", detail: "Moderator and tester", profile: URL(string: "https://github.com/TrisecTroop")),
        .init(name: "n.u.g", detail: "Moderator and tester"),
        .init(name: "atomic", detail: "Tester and community support", profile: URL(string: "https://github.com/20ch")),
        .init(name: "BakaTheSussy", detail: "Liquid Glass icon artwork for the original app"),
        .init(name: "typeofnull", detail: "Original main logo; adapted for this fork’s red body and blue leaf"),
        .init(name: "abyzal.", detail: "First AppleBlox logo", profile: URL(string: "https://github.com/PurvisiLOL"))
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Credits & Inspiration").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("AppleBlox Native").font(.headline)
                        Link("Belligerently · native fork", destination: AppResources.repository)
                        Text("SwiftUI and AppKit interface, Swift services, and a small Objective-C display bridge. System symbols and bundled branding keep this page usable offline.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Original AppleBlox contributors").font(.headline)
                    Text("Names and historical roles retained from the original app’s contributor list.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(original) { contributor in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "person.crop.circle").font(.title3).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                if let profile = contributor.profile { Link(contributor.name, destination: profile).font(.callout.weight(.medium)) }
                                else { Text(contributor.name).font(.callout.weight(.medium)) }
                                Text(contributor.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Inspiration").font(.headline)
                        Link("Bloxstrap", destination: URL(string: "https://github.com/bloxstraplabs/bloxstrap")!)
                        Text("The original project’s inspiration for an alternative Roblox launcher.").font(.callout).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Legacy technologies").font(.headline)
                        Text("The inherited app used NeutralinoJS, Svelte, TypeScript and Icons8. Those credits remain with its preserved source; they describe the original app’s stack.")
                            .font(.callout).foregroundStyle(.secondary)
                        Link("Original AppleBlox source", destination: AppResources.upstream)
                    }
                    Link("GPL-3.0 license", destination: AppResources.license)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 4)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 520, height: 450)
    }
}
