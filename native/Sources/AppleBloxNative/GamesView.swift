import AppleBloxCore
import SwiftUI

private struct ShortcutDraft: Identifiable {
    let id = UUID()
    let shortcut: GameShortcut?
}

struct GamesView: View {
    let model: LauncherModel
    @State private var draft: ShortcutDraft?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeading(title: "My Games", subtitle: "Your favorite experiences, a click away.")
            HStack {
                Text(model.configuration.shortcuts.count == 1 ? "1 saved game" : "\(model.configuration.shortcuts.count) saved games").foregroundStyle(.secondary)
                Spacer()
                Button("Add Game", systemImage: "plus") { draft = ShortcutDraft(shortcut: nil) }
                    .launchButtonStyle().controlSize(.small).disabled(!model.canSave)
            }
            if model.configuration.shortcuts.isEmpty {
                ContentUnavailableView {
                    Label("Your games belong here", systemImage: "gamecontroller")
                } description: {
                    Text("Add a name and place ID from a Roblox game’s URL.")
                } actions: {
                    Button("Add Your First Game") { draft = ShortcutDraft(shortcut: nil) }
                        .disabled(!model.canSave)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.configuration.shortcuts) { shortcut in
                    HStack(spacing: 10) {
                        Image(systemName: "gamecontroller.fill").font(.title3).foregroundStyle(AppleBloxTheme.primary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(shortcut.name).font(.headline)
                            Text("Place ID \(shortcut.placeID)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Play", systemImage: "play.fill") { Task { await model.launch(shortcut: shortcut) } }
                            .disabled(model.installation == nil || model.isLaunching)
                        Menu {
                            Button("Edit…") { draft = ShortcutDraft(shortcut: shortcut) }
                            Button("Remove", role: .destructive) { model.removeShortcut(shortcut) }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Options for \(shortcut.name)")
                        .disabled(!model.canSave)
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.configuration.shortcuts)
            }
        }
        .sheet(item: $draft) { draft in
            ShortcutEditor(model: model, shortcut: draft.shortcut)
        }
    }
}

private struct ShortcutEditor: View {
    let model: LauncherModel
    let shortcut: GameShortcut?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var placeID: String
    @State private var validationMessage: String?

    init(model: LauncherModel, shortcut: GameShortcut?) {
        self.model = model
        self.shortcut = shortcut
        // These inputs seed the editor's local draft once per sheet presentation.
        self.name = shortcut?.name ?? ""
        self.placeID = shortcut?.placeID ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(shortcut == nil ? "Add a game" : "Edit game").font(.title2.bold())
            Form {
                TextField("Name", text: $name)
                TextField("Place ID", text: $placeID)
            }
            Text("In roblox.com/games/123456789/Game-Name, the place ID is 123456789.")
                .font(.callout).foregroundStyle(.secondary)
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    .font(.callout).accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Game") {
                    do {
                        try model.saveShortcut(id: shortcut?.id, name: name, placeID: placeID)
                        dismiss()
                    } catch { validationMessage = error.localizedDescription }
                }
                .launchButtonStyle().keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 380)
    }
}
