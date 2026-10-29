import SwiftUI
import AppleBloxCore

private struct ExperienceSearchRequest: Equatable {
    let id = UUID()
    let query: String
    let session: UUID
    let page: String?
}

struct ExperienceBrowserView: View {
    let model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var request: ExperienceSearchRequest?
    @State private var results: [ExperienceResult] = []
    @State private var nextPage: String?
    @State private var loading = false
    @State private var failure: String?
    @State private var savedMessage: String?
    @State private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Browse Experiences").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField("Search Roblox experiences", text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search Roblox experiences").onSubmit(search)
                Button("Search", systemImage: "magnifyingglass", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || loading)
            }
            Text("Searches public Roblox results without your account or cookies. Results are not filtered using your account’s age settings. Roblox controls access when you play.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let failure {
                HStack {
                    Text(failure).font(.caption).foregroundStyle(.red).lineLimit(3)
                    Spacer()
                    Button("Retry") { if let request { self.request = .init(query: request.query, session: request.session, page: request.page) } }
                }
            }
            if !searched {
                ContentUnavailableView("Find your next game", systemImage: "magnifyingglass",
                    description: Text("Enter a name, then search to browse public experiences."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty && !loading && failure == nil {
                ContentUnavailableView.search(text: request?.query ?? "")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { game in
                    ExperienceBrowserRow(model: model, game: game) { save(game) }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
            HStack {
                if loading { ProgressView().controlSize(.small); Text("Searching…").font(.caption) }
                else { Text(savedMessage ?? "\(results.count) experiences loaded").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if let nextPage, let request {
                    Button("Load More") { self.request = .init(query: request.query, session: request.session, page: nextPage) }
                        .disabled(loading || results.count >= 500)
                }
            }
        }.padding(20).frame(width: 640, height: 470)
        .task(id: request) {
            guard let request else { return }
            loading = true; failure = nil
            do {
                let page = try await model.experienceSearch.search(request.query, session: request.session, page: request.page)
                try Task.checkCancellation()
                guard self.request == request else { return }
                let existing = request.page == nil ? [] : results
                var seen = Set(existing.map(\.id))
                results = Array((existing + page.results.filter { seen.insert($0.id).inserted }).prefix(500))
                nextPage = page.nextPage
                loading = false
            } catch {
                guard !Task.isCancelled, self.request == request else { return }
                failure = "Search couldn’t finish. Try again or open Roblox’s website. Loaded results and saved games are preserved."
                loading = false
            }
        }
    }
    private func search() {
        guard !loading else { return }
        results = []; nextPage = nil; savedMessage = nil; searched = true
        request = .init(query: query.trimmingCharacters(in: .whitespacesAndNewlines), session: UUID(), page: nil)
    }
    private func save(_ game: ExperienceResult) {
        do {
            try model.saveShortcut(id: nil, name: game.name, placeID: game.placeID)
            savedMessage = "Added \(game.name) to My Games."
        } catch { model.report(error) }
    }
}

private struct ExperienceBrowserRow: View {
    let model: LauncherModel
    let game: ExperienceResult
    let save: () -> Void
    private var saved: Bool { model.configuration.shortcuts.contains { $0.placeID == game.placeID } }
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name).font(.headline).lineLimit(2)
                Text(game.playing.map { "\($0.formatted()) playing when checked" } ?? "Place \(game.placeID)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "plus", action: save)
                .disabled(saved || !model.canSave || model.isBusy).accessibilityLabel("Save \(game.name)")
            Menu {
                Button("Play", systemImage: "play.fill") {
                    do {
                        let shortcut = try GameShortcut(name: game.name, placeID: game.placeID)
                        Task { await model.launch(shortcut: shortcut) }
                    } catch { model.report(error) }
                }.disabled(model.installation == nil || model.isBusy)
                Link("View on Roblox", destination: game.websiteURL)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Options for \(game.name)")
        }.padding(.vertical, 5)
    }
}
