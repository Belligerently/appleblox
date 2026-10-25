import AppKit
import AppleBloxCore
import SwiftUI
import UniformTypeIdentifiers

private enum EngineEditorPage: String, CaseIterable {
    case presets = "Presets", flags = "Flags", json = "JSON"
}

struct EngineProfileEditor: View {
    let model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile: EngineProfile
    @State private var flags: FlagEditorDraft
    @State private var page = EngineEditorPage.presets
    @State private var flagsJSON = ""
    @State private var query = ""
    @State private var selected: Set<UUID> = []
    @State private var showAdd = false
    @State private var message: String?

    init(model: LauncherModel, profile: EngineProfile) {
        self.model = model
        self.profile = profile
        self.flags = FlagEditorDraft(profile: profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Engine Profile").font(.title2.bold())
                Spacer()
                TextField("Profile name", text: $profile.name).textFieldStyle(.roundedBorder)
                    .frame(width: 230).accessibilityLabel("Profile name")
            }
            Picker("Editor", selection: Binding(get: { page }, set: switchPage)) {
                ForEach(EngineEditorPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Group {
                switch page {
                case .presets: presets
                case .flags: flagList
                case .json: jsonEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(3)
            }
            HStack {
                Text("Save stores the profile. Apply changes Roblox.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Profile", action: save).launchButtonStyle().keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || !model.canSave)
            }
        }
        .padding(20).frame(width: 640, height: page == .presets ? 430 : 500)
        .onChange(of: flagsJSON) { message = nil }
        .sheet(isPresented: $showAdd) {
            AddFlagPicker(existing: Set(flags.rows.map(\.name))) { name in
                do { try flags.add(name); query = ""; message = nil }
                catch { message = error.localizedDescription }
            }
        }
    }

    private var presets: some View {
        Form {
            Section("Graphics") {
                Picker("Graphics API", selection: $profile.renderer) {
                    ForEach(GraphicsRenderer.allCases) { Text($0.title).tag($0) }
                }
                if profile.renderer == .vulkan {
                    Text("Requests the original AppleBlox Vulkan flags. Support depends on Roblox’s macOS Player; it may ignore them or fall back to another renderer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Quality & distance") {
                Toggle("Separate graphics quality and distance", isOn: Binding(
                    get: { profile.separateQualityAndDistance },
                    set: { enabled in
                        if enabled, profile.graphicsQuality == nil { profile.graphicsQuality = 5 }
                        profile.separateQualityAndDistance = enabled
                    }
                ))
                Picker("Base graphics quality", selection: Binding(
                    get: { profile.graphicsQuality ?? 5 }, set: { profile.graphicsQuality = $0 }
                )) {
                    ForEach(1...21, id: \.self) { Text("Level \($0)").tag($0) }
                }
                .disabled(!profile.separateQualityAndDistance)
                Picker("Object detail distance", selection: $profile.objectDetailDistance) {
                    ForEach(ObjectDetailDistance.allCases) { Text($0.title).tag($0) }
                }
                Text("Base quality is independent of Roblox’s in-game distance slider. Object detail distance controls CSG mesh detail; it does not load streamed objects farther away. Low quality can hide objects in some games.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Visuals") {
                Picker("Texture quality", selection: $profile.textureQuality) {
                    Text("Roblox default").tag(Int?.none)
                    ForEach(0...3, id: \.self) { Text("Level \($0)").tag(Optional($0)) }
                }
                Toggle("Full resolution with fractional scaling", isOn: $profile.fullResolution)
                Toggle("Simple gray sky", isOn: $profile.graySky)
                Toggle("Disable voxel shadows", isOn: $profile.disableVoxelShadows)
                Text("Pauses Roblox’s voxelizer. Effects depend on the experience’s lighting; this does not disable every kind of shadow.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Enabled custom flags override these presets. Disabling a custom row lets the corresponding preset take effect again. Roblox may ignore flags depending on its version.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).controlSize(.small).scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private var visible: [FlagEditorRow] { flags.matching(query) }

    private var flagList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search flags or values", text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search FastFlags")
                Button("Add Flag…", systemImage: "plus") { showAdd = true }
                Menu {
                    Button("Import JSON…", action: importJSON)
                    Button("Export Enabled JSON…", action: exportJSON)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Flag JSON actions")
            }
            HStack {
                Toggle("Select visible flags", isOn: Binding(
                    get: { !visible.isEmpty && Set(visible.map(\.id)).isSubset(of: selected) },
                    set: { value in
                        if value { selected.formUnion(visible.map(\.id)) }
                        else { selected.subtract(visible.map(\.id)) }
                    }
                )).disabled(visible.isEmpty)
                Spacer()
                Text("\(selected.count) selected").foregroundStyle(.secondary)
                Button("Remove Selected", systemImage: "trash") {
                    flags.remove(selected); selected = []; message = nil
                }.disabled(selected.isEmpty)
            }
            .font(.caption).controlSize(.small)
            if flags.rows.isEmpty {
                ContentUnavailableView("No custom flags", systemImage: "flag", description: Text("Add an allowed flag or import JSON."))
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(visible) { row in
                    FlagEditorRowView(row: Binding(
                        get: { flags.rows.first(where: { $0.id == row.id }) ?? row },
                        set: { updated in
                            if let index = flags.rows.firstIndex(where: { $0.id == updated.id }) {
                                flags.rows[index] = updated; message = nil
                            }
                        }
                    ), selected: Binding(
                        get: { selected.contains(row.id) },
                        set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) } }
                    ))
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
            Text("\(flags.rows.filter(\.enabled).count) enabled · \(flags.rows.filter { !$0.enabled }.count) disabled. Selection is kept when filtering.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .controlSize(.small)
    }

    private var jsonEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Import JSON…", action: importJSON)
                Button("Export Enabled JSON…", action: exportJSON)
                Spacer()
            }.controlSize(.small)
            TextEditor(text: $flagsJSON).font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden).padding(8)
                .background(.quaternary, in: .rect(cornerRadius: 10))
                .accessibilityLabel("Custom FastFlags JSON")
            Text("JSON contains enabled custom overrides only. Disabled rows stay in the profile. Import replaces enabled overrides; a matching disabled row becomes enabled.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func switchPage(_ next: EngineEditorPage) {
        do {
            if page == .json { try flags.replaceEnabledJSON(flagsJSON); pruneSelection() }
            if next == .json { flagsJSON = try flags.enabledJSON() }
            page = next; message = nil
        } catch { message = error.localizedDescription }
    }

    private func pruneSelection() { selected.formIntersection(flags.rows.map(\.id)) }

    private func save() {
        do {
            if page == .json { try flags.replaceEnabledJSON(flagsJSON) }
            try model.saveEngineProfile(flags.applying(to: profile))
            dismiss()
        } catch { message = error.localizedDescription }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.title = "Import Enabled FastFlags"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_048_576 else { throw EngineError.fileTooLarge }
            try flags.replaceEnabledJSON(String(contentsOf: url, encoding: .utf8))
            flagsJSON = try flags.enabledJSON(); pruneSelection(); message = nil
        } catch { message = error.localizedDescription }
    }

    private func exportJSON() {
        do {
            var snapshot = flags
            if page == .json { try snapshot.replaceEnabledJSON(flagsJSON) }
            let data = Data(try snapshot.enabledJSON().utf8)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "CustomFastFlags.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic); message = nil
        } catch { message = error.localizedDescription }
    }
}

private struct FlagEditorRowView: View {
    @Binding var row: FlagEditorRow
    @Binding var selected: Bool

    private var valid: Bool { (try? row.validatedValue()) != nil }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Select \(row.name)", isOn: $selected).labelsHidden().toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.system(.caption, design: .monospaced)).lineLimit(2)
                    .textSelection(.enabled).help(row.name)
                if !valid { Text("Enter a 32-bit whole number.").font(.caption2).foregroundStyle(.red) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.isBoolean {
                Picker("Value for \(row.name)", selection: $row.value) {
                    Text("true").tag("true")
                    Text("false").tag("false")
                }.labelsHidden().frame(width: 100)
            } else {
                TextField("Integer", text: $row.value).textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced)).frame(width: 100)
                    .accessibilityLabel("Value for \(row.name)")
            }
            Toggle("Enable \(row.name)", isOn: $row.enabled).labelsHidden().toggleStyle(.switch)
                .help("Disabled custom overrides are saved but not applied.")
        }
        .padding(.vertical, 5)
    }
}

private struct AddFlagPicker: View {
    let existing: Set<String>
    let add: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var available: [String] {
        FastFlags.allowed.sorted().filter { !existing.contains($0) && (query.isEmpty || $0.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add FastFlag").font(.title2.bold())
            TextField("Search allowed flags", text: $query).textFieldStyle(.roundedBorder)
            List(available, id: \.self) { name in
                Button { add(name); dismiss() } label: {
                    Text(name).font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }.buttonStyle(.plain).accessibilityLabel("Add \(name)")
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            if available.isEmpty { Text("No unused allowed flags match.").font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 490, height: 380)
    }
}
