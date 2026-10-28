import AppleBloxCore
import SwiftUI

private struct ShortcutDraft: Identifiable {
    let id = UUID()
    let shortcut: GameShortcut?
}

struct GamesView: View {
    let model: LauncherModel
    @State private var draft: ShortcutDraft?
    @State private var query = ""
    @State private var sortByName = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var games: [GameShortcut] {
        let matches = model.configuration.shortcuts.filter {
            query.isEmpty || $0.name.localizedStandardContains(query) || $0.placeID.contains(query)
        }
        return sortByName ? matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : matches
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeading(title: "My Games", subtitle: "Your favorite experiences, a click away.")
            HStack {
                TextField("Search saved games", text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search saved games")
                Picker("Order", selection: $sortByName) {
                    Text("Saved order").tag(false)
                    Text("Name").tag(true)
                }
                .labelsHidden().frame(width: 112).accessibilityLabel("Game sort order")
                Button("Add Game", systemImage: "plus") { draft = ShortcutDraft(shortcut: nil) }
                    .launchButtonStyle().controlSize(.small).disabled(!model.canSave)
            }
            if model.configuration.shortcuts.isEmpty {
                ContentUnavailableView {
                    Label("Your games belong here", systemImage: "gamecontroller")
                } description: {
                    Text("Paste a Roblox game link or add a numeric place ID.")
                } actions: {
                    Button("Add Your First Game") { draft = ShortcutDraft(shortcut: nil) }
                        .disabled(!model.canSave)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if games.isEmpty {
                ContentUnavailableView {
                    Label("No matching games", systemImage: "magnifyingglass")
                } description: { Text("Try another name or place ID.") }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(games) { shortcut in
                    SavedGameRow(model: model, shortcut: shortcut, edit: { draft = ShortcutDraft(shortcut: shortcut) })
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .animation(systemReduceMotion || appReduceMotion ? nil : .smooth(duration: 0.2), value: games)
            }
        }
        .sheet(item: $draft) { draft in
            ShortcutEditor(model: model, shortcut: draft.shortcut)
        }
    }
}

private struct SavedGameRow: View {
    let model: LauncherModel
    let shortcut: GameShortcut
    let edit: () -> Void
    @State private var details: GameDetails?
    @State private var refreshID = 0
    private var artwork: Bool { model.configuration.appearance.showGameArtwork }

    var body: some View {
        HStack(spacing: 10) {
            GameArtwork(url: artwork ? details?.iconURL : nil, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(shortcut.name).font(.headline).lineLimit(1)
                if let details, artwork {
                    Text(details.creator + (details.isStale ? " · Saved details" : ""))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Place ID \(shortcut.placeID)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button("Play", systemImage: "play.fill") { Task { await model.launch(shortcut: shortcut) } }
                .disabled(model.installation == nil || model.isBusy)
            Menu {
                Button("Edit…", action: edit).disabled(!model.canSave)
                Link("View on Roblox", destination: URL(string: "https://www.roblox.com/games/\(shortcut.placeID)")!)
                Button("Refresh Game Details") { refreshID += 1 }.disabled(!artwork)
                Divider()
                Button("Remove", role: .destructive) { model.removeShortcut(shortcut) }.disabled(!model.canSave)
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Options for \(shortcut.name)")
        }
        .padding(.vertical, 4)
        .task(id: "\(shortcut.placeID)-\(artwork)-\(refreshID)") {
            guard artwork else { details = nil; return }
            details = await model.gameCatalog.cachedGame(for: shortcut.placeID)
            if let loaded = try? await model.gameCatalog.game(for: shortcut.placeID, refresh: refreshID > 0), !Task.isCancelled {
                details = loaded
            }
        }
    }
}

struct GameArtwork: View {
    @Environment(\.nativePalette) private var palette
    let url: URL?
    var size: CGFloat = 48

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    palette.accent.opacity(0.12)
                    Image(systemName: "gamecontroller.fill").font(.system(size: size * 0.4)).foregroundStyle(palette.accent)
                }
            }
        }
        .frame(width: size, height: size).clipShape(.rect(cornerRadius: 9))
        .accessibilityHidden(true)
    }
}

private struct ShortcutEditor: View {
    let model: LauncherModel
    let shortcut: GameShortcut?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var placeID: String
    @State private var engineProfileID: UUID?
    @State private var validationMessage: String?
    @State private var lookupMessage: String?
    @State private var details: GameDetails?
    @State private var isLookingUp = false
    @State private var suggestedName: String?

    init(model: LauncherModel, shortcut: GameShortcut?) {
        self.model = model
        self.shortcut = shortcut
        // These values seed a private draft once per sheet presentation.
        self.name = shortcut?.name ?? ""
        self.placeID = shortcut?.placeID ?? ""
        self.engineProfileID = shortcut?.engineProfileID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(shortcut == nil ? "Add a game" : "Edit game").font(.title2.bold())
            Form {
                TextField("Roblox URL or place ID", text: $placeID)
                TextField("Name", text: $name)
                Picker("Engine profile", selection: $engineProfileID) {
                    Text("Use selected global profile").tag(UUID?.none)
                    ForEach(model.configuration.engine.profiles) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if isLookingUp {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking up public game details…").font(.caption) }
            } else if let details {
                HStack(spacing: 10) {
                    GameArtwork(url: model.configuration.appearance.showGameArtwork ? details.iconURL : nil)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(details.name).font(.headline).lineLimit(2)
                        Text("By \(details.creator)").font(.caption).foregroundStyle(.secondary)
                        if let playing = details.playing, !details.isStale {
                            Text("\(playing.formatted()) playing when checked").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Use Name") { name = details.name }.controlSize(.small)
                }
            } else {
                Text(lookupMessage ?? "Use a full roblox.com/games/… link or a numeric place ID. You can enter a name manually when offline.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    .font(.callout).accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Game") {
                    do {
                        try model.saveShortcut(id: shortcut?.id, name: name, placeID: placeID, engineProfileID: engineProfileID)
                        dismiss()
                    } catch { validationMessage = error.localizedDescription }
                }
                .launchButtonStyle().keyboardShortcut(.defaultAction).disabled(!model.canSave)
            }
        }
        .padding(22).frame(width: 430)
        .task(id: placeID) {
            details = nil
            if name == suggestedName { name = ""; suggestedName = nil }
            lookupMessage = nil
            isLookingUp = false
            guard let id = try? RobloxPlaceInput.placeID(from: placeID) else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                isLookingUp = true
                let loaded = try await model.gameCatalog.game(for: id)
                try Task.checkCancellation()
                details = loaded
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == suggestedName {
                    name = loaded.name
                    suggestedName = loaded.name
                }
                isLookingUp = false
            } catch {
                guard !Task.isCancelled else { return }
                lookupMessage = "Details couldn’t be loaded. Enter a name to save this game manually."
                isLookingUp = false
            }
        }
    }
}
