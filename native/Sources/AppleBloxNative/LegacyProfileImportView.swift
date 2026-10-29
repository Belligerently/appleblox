import AppleBloxCore
import SwiftUI

struct LegacyProfileImportView: View {
    let model: LauncherModel
    let plan: LegacyProfileImportPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Profile Import").font(.title2.bold())
            Text("Profiles: \(plan.conversions.count) · New saved games: \(plan.addedGames) · Updated assignments: \(plan.updatedAssignments)")
                .font(.callout)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.conversions, id: \.profile.id) { conversion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversion.profile.name).font(.headline)
                            Text("\(conversion.kind == .game ? "Game overlay" : "Global profile") · Games: \(conversion.placeIDs.count) · Enabled flags: \(conversion.profile.customFlags.count) · Disabled: \(conversion.profile.disabledCustomFlags.count)")
                                .font(.caption).foregroundStyle(.secondary)
                            if !conversion.placeIDs.isEmpty {
                                Text("Place IDs: " + conversion.placeIDs.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    if !plan.warnings.isEmpty {
                        Text("Import warnings: \(plan.warnings.count)").font(.headline)
                        ForEach(Array(plan.warnings.prefix(20).enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.caption).foregroundStyle(.secondary)
                        }
                        if plan.warnings.count > 20 {
                            Text("Showing the first 20 warnings. Original profile files are kept unchanged.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Game profiles overlay the selected profile. Global profiles stay unselected until you choose them. Player files are unchanged until Apply or a configured launch.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { model.legacyImportReview = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import Profiles") { model.commitLegacyImport(plan) }.launchButtonStyle().keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || !model.canSave)
            }
        }.padding(20).frame(width: 550, height: 390)
    }
}
