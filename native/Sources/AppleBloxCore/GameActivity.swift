import Foundation

public struct PlaySession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let placeID: String
    public var name: String
    public let startedAt: Date
    public var endedAt: Date?
    public init(placeID: String, name: String, startedAt: Date = Date()) {
        id = UUID(); self.placeID = placeID; self.name = name; self.startedAt = startedAt
    }
}

public enum PlayerLogEvent: Equatable, Sendable {
    case joining(String), left
    public static func parse(_ line: String) -> PlayerLogEvent? {
        if line.contains("[FLog::Output] ! Joining game"),
           let range = line.range(of: #"\bplace\s+(\d+)\b"#, options: .regularExpression) {
            let id = line[range].split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
            if let game = try? GameShortcut(name: "Game", placeID: id) { return .joining(game.placeID) }
        }
        if line.contains("[FLog::SingleSurfaceApp] returnToLuaApp") || line.contains("[FLog::Network] Time to disconnect replication data") { return .left }
        return nil
    }
}

public actor PlayerLogReader {
    private var file: URL?
    private var offset: UInt64 = 0
    private var remainder = Data()
    private var didBaseline = false
    public init() {}
    public func reset() { file = nil; offset = 0; remainder = Data(); didBaseline = false }
    public func poll(directory: URL, now: Date = Date()) throws -> [PlayerLogEvent] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { didBaseline = true; return [] }
        let candidates = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "log" && $0.lastPathComponent.lowercased().contains("player") }
        let newest = try candidates.map { ($0, try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) }.max { $0.1 < $1.1 }
        guard let (latest, modified) = newest, now.timeIntervalSince(modified) < 300 else { didBaseline = true; return [] }
        let handle = try FileHandle(forReadingFrom: latest)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if file != latest || end < offset {
            let ignoreExisting = !didBaseline
            file = latest; offset = ignoreExisting ? end : 0; remainder = Data(); didBaseline = true
            // Ignore the initial existing log, but read newly created/rotated logs from the beginning.
            if ignoreExisting { return [] }
        }
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: 262_144) ?? Data()
        offset += UInt64(data.count)
        remainder.append(data)
        guard let lastNewline = remainder.lastIndex(of: 10) else {
            if remainder.count > 262_144 { remainder = Data() }
            return []
        }
        let complete = remainder.prefix(through: lastNewline)
        remainder = Data(remainder.suffix(from: lastNewline + 1))
        return String(decoding: complete, as: UTF8.self).split(separator: "\n").compactMap { PlayerLogEvent.parse(String($0)) }
    }
}

public actor PlayHistoryStore {
    let file: URL
    private var newestRevision = -1
    public init(directory: URL) { file = directory.appendingPathComponent("play-history.json") }
    public func load() throws -> [PlaySession] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([PlaySession].self, from: Data(contentsOf: file))
    }
    public func save(_ history: [PlaySession], revision: Int? = nil) throws {
        if let revision, revision <= newestRevision { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(history.prefix(200))).write(to: file, options: .atomic)
        if let revision { newestRevision = revision }
    }
}

public enum RobloxGameDirectory {
    public static func name(for placeID: String) async throws -> String {
        let valid = try GameShortcut(name: "Game", placeID: placeID).placeID
        struct Universe: Decodable { let universeId: UInt64 }
        struct Games: Decodable { struct Game: Decodable { let name: String }; let data: [Game] }
        func data(_ url: String) async throws -> Data {
            var request = URLRequest(url: URL(string: url)!)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FeatureError.message("Game information is unavailable.") }
            return data
        }
        let universe = try JSONDecoder().decode(Universe.self, from: await data("https://apis.roblox.com/universes/v1/places/\(valid)/universe"))
        let games = try JSONDecoder().decode(Games.self, from: await data("https://games.roblox.com/v1/games?universeIds=\(universe.universeId)"))
        return games.data.first?.name ?? "Place \(valid)"
    }
}
