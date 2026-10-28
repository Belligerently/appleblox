import SwiftUI
import AppKit
import AppleBloxCore
import UniformTypeIdentifiers

private struct ThemeDraft: Identifiable {
    let id = UUID()
    var recordID: UUID?
    var theme: NativeThemeDocument
}
struct NativeThemeLibraryView: View {
    let model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var records: [NativeThemeRecord] = []
    @State private var draft: ThemeDraft?
    @State private var status = "Native JSON themes change colors; legacy CSS and bootstrapper XML are separate formats."
    @State private var removal: NativeThemeRecord?
    @State private var confirmRemove = false
    @State private var working = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Native Themes").font(.title2.bold())
                Spacer()
                Button("New", systemImage: "plus") { draft = ThemeDraft(theme: NativeThemeDocument()) }
                Button("Import…") { Task { await importFile() } }
                Menu {
                    Button("Reload Library") { Task { await reload() } }
                    Button("Show Theme Folder") { Task { await reveal(nil) } }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Theme library actions")
            }
            List(records) { record in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8).fill(NativePalette.color(record.theme.accent)).frame(width: 32, height: 32)
                    VStack(alignment: .leading) {
                        Text(record.theme.name).font(.headline)
                        if model.configuration.appearance.customThemeID == record.id { Text("Applied").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Apply") { apply(record) }.controlSize(.small)
                    Menu {
                        Button("Edit…") { draft = ThemeDraft(recordID: record.id, theme: record.theme) }
                        Button("Reload and Apply") { Task { await reloadAndApply(record.id) } }
                        Button("Export…") { Task { await export(record) } }
                        Button("Show File") { Task { await reveal(record.id) } }
                        Button("Remove…") { removal = record; confirmRemove = true }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                }.padding(.vertical, 4)
            }.listStyle(.plain).overlay {
                if records.isEmpty { Text("No custom themes. Create one or import native theme JSON.").foregroundStyle(.secondary).multilineTextAlignment(.center).padding() }
            }
            Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Use Original Palette") { apply(nil) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 560, height: 430).disabled(working || model.isBusy)
        .task { await reload() }
        .sheet(item: $draft) { draft in
            NativeThemeEditor(initial: draft.theme) { theme in
                let id = try await model.nativeThemes.save(theme, id: draft.recordID)
                if model.configuration.appearance.customThemeID == id {
                    var next = model.configuration
                    next.appearance.customTheme = theme
                    try model.persist(next)
                }
                await reload()
            }
        }
        .confirmationDialog("Remove this theme?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Theme") { Task { await remove() } }
        } message: { Text("Its file is kept in the library’s removed folder for recovery. An applied palette stays active until you choose another one or Use Original Palette.") }
    }
    private func reload() async {
        do {
            let snapshot = try await model.nativeThemes.list(); records = snapshot.records
            status = snapshot.skipped == 0 ? "Preview or edit before applying. Reload reads any local JSON edits." : "Skipped \(snapshot.skipped) unreadable themes; files were preserved."
        } catch { status = error.localizedDescription }
    }
    private func apply(_ record: NativeThemeRecord?) {
        do {
            var next = model.configuration
            next.appearance.customTheme = try record?.theme.validated(); next.appearance.customThemeID = record?.id
            try model.persist(next)
            status = record == nil ? "Original palette restored." : "Applied \(record!.theme.name)."
        } catch { status = error.localizedDescription }
    }
    private func reloadAndApply(_ id: UUID) async {
        do { apply(NativeThemeRecord(id: id, theme: try await model.nativeThemes.read(id))); await reload() }
        catch { status = error.localizedDescription }
    }
    private func importFile() async {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        working = true; defer { working = false }
        do { try await model.nativeThemes.importFile(url); await reload() }
        catch { status = error.localizedDescription }
    }
    private func export(_ record: NativeThemeRecord) async {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "AppleBlox-theme-\(String(UUID().uuidString.prefix(8))).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Write exactly the validated native document; no paths, assets or executable content.
            try record.theme.json.write(to: url, options: .atomic)
            status = "Exported native theme JSON."
        } catch { status = error.localizedDescription }
    }
    private func reveal(_ id: UUID?) async {
        do {
            if let id { NSWorkspace.shared.activateFileViewerSelecting([try await model.nativeThemes.file(id)]) }
            else { let url = try await model.nativeThemes.folder(); _ = NSWorkspace.shared.open(url) }
        } catch { status = error.localizedDescription }
    }
    private func remove() async {
        guard let removal else { return }
        do { try await model.nativeThemes.remove(removal.id); await reload() }
        catch { status = error.localizedDescription }
    }
}
private struct NativeThemeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var theme: NativeThemeDocument
    @State private var error: String?
    @State private var saving = false
    let save: (NativeThemeDocument) async throws -> Void
    init(initial: NativeThemeDocument, save: @escaping (NativeThemeDocument) async throws -> Void) {
        _theme = State(initialValue: initial); self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Native Theme").font(.title2.bold())
            Form {
                TextField("Name", text: $theme.name)
                colorRow("Accent", value: $theme.accent)
                colorRow("Light background", value: $theme.lightBackground)
                colorRow("Light cards", value: $theme.lightCard)
                colorRow("Dark background", value: $theme.darkBackground)
                colorRow("Dark cards", value: $theme.darkCard)
            }.formStyle(.columns).frame(height: 220)
            HStack(spacing: 12) { preview(dark: false); preview(dark: true) }
            Text(error ?? "Use #RRGGBB colors. Readability is checked before saving.")
                .font(.caption).foregroundStyle(error == nil ? Color.secondary : Color.red).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Theme") {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await save(theme.validated()); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 520, height: 490).disabled(saving).interactiveDismissDisabled(saving)
    }
    private func colorRow(_ name: String, value: Binding<String>) -> some View {
        HStack {
            TextField(name, text: value).font(.system(.body, design: .monospaced))
            RoundedRectangle(cornerRadius: 4).fill(NativePalette.color(value.wrappedValue)).frame(width: 24, height: 20).accessibilityHidden(true)
        }
    }
    private func preview(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(dark ? "Dark preview" : "Light preview").font(.caption.bold())
            Text("Example card").font(.caption).padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(NativePalette.color(dark ? theme.darkCard : theme.lightCard), in: .rect(cornerRadius: 5))
            Text("Accent control").font(.caption).foregroundStyle(.white).padding(5)
                .background(NativePalette.color(theme.accent), in: .rect(cornerRadius: 5))
        }.padding(10).frame(maxWidth: .infinity).foregroundStyle(dark ? Color(white: 0.9) : .black)
            .background(NativePalette.color(dark ? theme.darkBackground : theme.lightBackground), in: .rect(cornerRadius: 8))
    }
}
