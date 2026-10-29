import Foundation

public enum RobloxPlaceInput {
    public static func placeID(from input: String) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let game = try? GameShortcut(name: "Game", placeID: text) { return game.placeID }
        let candidate = text.hasPrefix("roblox.com/") || text.hasPrefix("www.roblox.com/") ? "https://" + text : text
        guard let url = URL(string: candidate), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), ["roblox.com", "www.roblox.com", "m.roblox.com"].contains(host),
              url.user == nil, url.password == nil, url.port == nil else { throw invalidInput }
        let parts = url.path.split(separator: "/")
        let gameIndex: Int
        if parts.first == "games" { gameIndex = 0 }
        else if parts.count >= 3, parts[0].range(of: #"^[a-z]{2}(?:-[a-z]{2})?$"#, options: .regularExpression) != nil,
                parts[1] == "games" { gameIndex = 1 }
        else { throw invalidInput }
        guard parts.count > gameIndex + 1 else { throw invalidInput }
        return try GameShortcut(name: "Game", placeID: String(parts[gameIndex + 1])).placeID
    }

    private static var invalidInput: FeatureError {
        .message("Enter a numeric place ID or a full https://www.roblox.com/games/… link. Short share links must be opened in a browser first.")
    }
}

public struct GameDetails: Codable, Equatable, Sendable {
    public let placeID: String
    public let universeID: UInt64
    public let name: String
    public let creator: String
    public let playing: Int?
    public let iconURL: URL?
    public let fetchedAt: Date
    public var websiteURL: URL { URL(string: "https://www.roblox.com/games/\(placeID)")! }
    public var isStale: Bool { Date().timeIntervalSince(fetchedAt) >= 1800 }

    static func permittedIcon(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(), host == "rbxcdn.com" || host.hasSuffix(".rbxcdn.com") else { return nil }
        return url
    }

    var isValid: Bool {
        (try? GameShortcut(name: name, placeID: placeID)) != nil && universeID > 0 && name.count <= 300 &&
        creator.count <= 300 && (playing == nil || playing! >= 0) &&
        (iconURL == nil || Self.permittedIcon(iconURL) != nil)
    }
}

public actor GameCatalog {
    public typealias Fetch = @Sendable (URL) async throws -> Data
    private let fetch: Fetch
    private let file: URL?
    private var cache: [String: GameDetails] = [:]
    private var cacheGeneration = 0

    public init(directory: URL? = nil, fetch: @escaping Fetch = GameCatalog.fetchPublicData) {
        self.fetch = fetch
        file = directory?.appendingPathComponent("game-details-cache.json")
        if let file, let data = try? Data(contentsOf: file), data.count <= 2_000_000,
           let entries = try? JSONDecoder().decode([GameDetails].self, from: data) {
            cache = Dictionary(entries.filter(\.isValid).prefix(200).map { ($0.placeID, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    public func cachedGame(for placeID: String) -> GameDetails? { cache[placeID] }
    public var cachedGameCount: Int { cache.count }

    @discardableResult
    public func clearCache() throws -> Int {
        if let file {
            let fm = FileManager.default
            let attributes: [FileAttributeKey: Any]?
            do { attributes = try fm.attributesOfItem(atPath: file.path) }
            catch {
                let error = error as NSError
                guard error.domain == NSCocoaErrorDomain,
                      [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue].contains(error.code) else { throw error }
                attributes = nil
            }
            if let attributes {
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      try fm.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.type] as? FileAttributeType == .typeDirectory else {
                    throw FeatureError.message("The game-details cache path is not a regular file in the app data folder.")
                }
                // Commit disk first: a failed write must retain the in-memory cache too.
                try Data("[]".utf8).write(to: file, options: .atomic)
            }
        }
        let count = cache.count
        cacheGeneration += 1
        cache.removeAll()
        return count
    }


    public func game(for input: String, refresh: Bool = false) async throws -> GameDetails {
        let placeID = try RobloxPlaceInput.placeID(from: input)
        let generation = cacheGeneration
        if !refresh, let cached = cache[placeID], !cached.isStale { return cached }
        do {
            struct Universe: Decodable { let universeId: UInt64 }
            struct Games: Decodable {
                struct Game: Decodable {
                    struct Creator: Decodable { let name: String }
                    let id: UInt64
                    let name: String
                    let creator: Creator
                    let playing: Int?
                }
                let data: [Game]
            }
            let universeData = try await fetch(URL(string: "https://apis.roblox.com/universes/v1/places/\(placeID)/universe")!)
            guard generation == cacheGeneration else { throw CancellationError() }
            let universe = try JSONDecoder().decode(Universe.self, from: universeData)
            guard universe.universeId > 0 else { throw FeatureError.message("This place is unavailable.") }
            let gameData = try await fetch(URL(string: "https://games.roblox.com/v1/games?universeIds=\(universe.universeId)")!)
            guard generation == cacheGeneration else { throw CancellationError() }
            let games = try JSONDecoder().decode(Games.self, from: gameData)
            guard let game = games.data.first(where: { $0.id == universe.universeId }), !game.name.isEmpty else {
                throw FeatureError.message("This experience is private, deleted, or unavailable.")
            }
            let icon = try await icon(for: universe.universeId)
            try Task.checkCancellation()
            guard generation == cacheGeneration else { throw CancellationError() }
            let result = GameDetails(placeID: placeID, universeID: universe.universeId, name: String(game.name.prefix(300)),
                                     creator: String(game.creator.name.prefix(300)), playing: game.playing.flatMap { $0 >= 0 ? $0 : nil },
                                     iconURL: icon, fetchedAt: Date())
            cache[placeID] = result
            let recent = cache.values.sorted { $0.fetchedAt > $1.fetchedAt }.prefix(200)
            cache = Dictionary(uniqueKeysWithValues: recent.map { ($0.placeID, $0) })
            if let file, let data = try? JSONEncoder().encode(Array(cache.values)) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            return result
        } catch {
            try Task.checkCancellation()
            guard generation == cacheGeneration else { throw CancellationError() }
            if let cached = cache[placeID] { return cached }
            throw error
        }
    }

    private func icon(for universeID: UInt64) async throws -> URL? {
        struct Icons: Decodable {
            struct Icon: Decodable { let targetId: UInt64; let state: String; let imageUrl: URL? }
            let data: [Icon]
        }
        do {
            let url = URL(string: "https://thumbnails.roblox.com/v1/games/icons?universeIds=\(universeID)&size=150x150&format=Png&isCircular=false")!
            let icons = try JSONDecoder().decode(Icons.self, from: await fetch(url))
            return GameDetails.permittedIcon(icons.data.first { $0.targetId == universeID && $0.state == "Completed" }?.imageUrl)
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    public static func fetchPublicData(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 1_000_000 else {
            throw FeatureError.message("Roblox game details are unavailable. Try again later; saved games still work.")
        }
        return data
    }
}
