import AppKit
import AppleBloxCore
import SwiftUI
import UniformTypeIdentifiers

private struct EngineDraft: Identifiable {
    var id: UUID { profile.id }
    let profile: EngineProfile
}

struct EngineView: View {
    let model: LauncherModel
    @State private var draft: EngineDraft?
    @State private var confirmRestore = false
    @State private var confirmDelete = false
    @Environment(\.colorScheme) private var colorScheme

    private var profile: EngineProfile? { model.configuration.engine.selectedProfile }
    private var busy: Bool { model.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PageHeading(title: "Engine", subtitle: "Graphics and FastFlags, saved in profiles.")
                Menu {
                    Button("New Profile…", systemImage: "plus") { draft = EngineDraft(profile: EngineProfile(name: "New Profile")) }
                    Button("Import JSON…", systemImage: "square.and.arrow.down", action: importProfile)
                    Divider()
                    Button("Export Flags…", systemImage: "square.and.arrow.up", action: model.exportEngineProfile)
                    Button("Delete Profile…", role: .destructive) { confirmDelete = true }
                        .disabled(model.configuration.engine.profiles.count < 2)
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Engine profile actions")
                .disabled(!model.canSave || busy)
            }
            HStack {
                Picker("Profile", selection: Binding(get: { model.configuration.engine.selectedProfileID }, set: model.selectEngineProfile)) {
                    ForEach(model.configuration.engine.profiles) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().accessibilityLabel("Engine profile").frame(maxWidth: .infinity)
                Button("Edit…", systemImage: "slider.horizontal.3") {
                    if let profile { draft = EngineDraft(profile: profile) }
                }
            }
            .disabled(!model.canSave || busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let profile {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                EngineSummaryField(title: "Renderer", value: profile.renderer.title)
                                EngineSummaryField(title: "Quality", value: profile.separateQualityAndDistance ? (profile.graphicsQuality.map(String.init) ?? "Default") : "Default")
                                EngineSummaryField(title: "Textures", value: profile.textureQuality.map { "Level \($0)" } ?? "Default")
                            }
                            GridRow {
                                EngineSummaryField(title: "Full resolution", value: profile.fullResolution ? "On" : "Default")
                                EngineSummaryField(title: "Gray sky", value: profile.graySky ? "On" : "Default")
                                EngineSummaryField(title: "Custom flags", value: "\(profile.customFlags.count) on · \(profile.disabledCustomFlags.count) off")
                            }
                            GridRow {
                                EngineSummaryField(title: "Object detail distance", value: profile.objectDetailDistance.title)
                                EngineSummaryField(title: "Voxel shadows", value: profile.disableVoxelShadows ? "Disabled" : "Default")
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppleBloxTheme.card(for: colorScheme).opacity(0.75), in: .rect(cornerRadius: 14))
                    }
                    Toggle("Apply selected profile before launch", isOn: Binding(
                        get: { model.configuration.engine.applyOnLaunch }, set: model.setApplyEngineOnLaunch
                    ))
                    .controlSize(.small).disabled(!model.canSave || busy)
                    Text("Apply replaces ClientAppSettings.json and backs up the original. Quit Roblox first; client updates may reset it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollIndicators(.automatic)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        Task { await model.applyEngineProfile() }
                    } label: {
                        Label(model.isApplyingEngine ? "Working…" : "Apply Now", systemImage: "checkmark.circle")
                    }
                    .launchButtonStyle()
                    .disabled(!model.canSave || busy || model.isRunning || model.installation == nil)
                    Button("Restore Original…") { confirmRestore = true }
                        .disabled(!model.canSave || busy || model.isRunning || !model.hasEngineBackup)
                    Spacer()
                    if model.hasEngineBackup { Image(systemName: "externaldrive.badge.checkmark").help("Original settings backed up") }
                }
                Text(model.isRunning ? "Quit Roblox to apply or restore settings." : model.engineStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
        .sheet(item: $draft) { EngineProfileEditor(model: model, profile: $0.profile) }
        .confirmationDialog("Restore the original Roblox settings?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore Original") { Task { await model.restoreEngineSettings() } }
        } message: { Text("This restores the file from before the first Apply and turns off Apply on launch. Your profiles are kept.") }
        .confirmationDialog("Delete this engine profile?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Profile", role: .destructive) { if let profile { model.removeEngineProfile(profile) } }
        } message: { Text("This removes the saved profile. Settings already applied to Roblox stay in place until you apply another profile or restore.") }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import FastFlags JSON"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_048_576 else { throw EngineError.fileTooLarge }
            var imported = EngineProfile(name: url.deletingPathExtension().lastPathComponent)
            imported.customFlags = try FastFlags.parse(String(contentsOf: url, encoding: .utf8))
            draft = EngineDraft(profile: imported)
        } catch { model.errorMessage = error.localizedDescription }
    }
}

private struct EngineSummaryField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
