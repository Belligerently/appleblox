import Foundation

public struct ExperienceResult: Identifiable, Equatable, Sendable {
    public var id: String { placeID }
    public let placeID: String
    public let universeID: UInt64
    public let name: String
    public let playing: Int?
    public var websiteURL: URL { URL(string: "https://www.roblox.com/games/\(placeID)")! }
}
public struct ExperienceSearchPage: Sendable {
    public let results: [ExperienceResult]
    public let nextPage: String?
}
public actor ExperienceSearch {
    private let fetch: GameCatalog.Fetch
    public init(fetch: @escaping GameCatalog.Fetch = GameCatalog.fetchPublicData) { self.fetch = fetch }
    public func search(_ query: String, session: UUID, page: String? = nil) async throws -> ExperienceSearchPage {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...100).contains(query.count), !query.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              page == nil || (page!.utf8.count <= 4096 && !page!.isEmpty) else {
            throw FeatureError.message("Enter an experience name between 2 and 100 characters.")
        }
        var url = URLComponents(string: "https://apis.roblox.com/search-api/omni-search")!
        url.queryItems = [.init(name: "searchQuery", value: query), .init(name: "sessionId", value: session.uuidString),
                          .init(name: "pageType", value: "all")]
        if let page { url.queryItems?.append(.init(name: "pageToken", value: page)) }
        let bytes = try await fetch(url.url!)
        try Task.checkCancellation()
        guard bytes.count <= 1_000_000 else { throw FeatureError.message("The search response is too large. Try a more specific name.") }
        struct Response: Decodable {
            struct Group: Decodable {
                struct Entry: Decodable {
                    let rootPlaceId: UInt64?
                    let universeId: UInt64?
                    let name: String?
                    let playerCount: Int?
                    let isSponsored: Bool?
                }
                let contentGroupType: String
                let contents: [Entry]
            }
            let searchResults: [Group]
            let nextPageToken: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: bytes)
        var seen = Set<String>()
        let results = response.searchResults.filter { $0.contentGroupType == "Game" }.flatMap(\.contents).compactMap { game -> ExperienceResult? in
            guard game.isSponsored != true, let place = game.rootPlaceId, place > 0,
                  let universe = game.universeId, universe > 0, let name = game.name,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 300,
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  seen.insert(String(place)).inserted else { return nil }
            return ExperienceResult(placeID: String(place), universeID: universe, name: name,
                playing: game.playerCount.flatMap { $0 >= 0 ? $0 : nil })
        }
        let next = response.nextPageToken.flatMap { !$0.isEmpty && $0.utf8.count <= 4096 && $0 != page ? $0 : nil }
        return ExperienceSearchPage(results: Array(results.prefix(100)), nextPage: next)
    }
}
