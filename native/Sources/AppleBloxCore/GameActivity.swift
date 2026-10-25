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
    case serverConnected(ServerEndpoint)
    case richPresence(BloxstrapPresencePatch)
    public static func parse(_ line: String) -> PlayerLogEvent? {
        if let endpoint = ServerEndpoint.parse(line) { return .serverConnected(endpoint) }
        if line.contains("[FLog::Output] [BloxstrapRPC]") {
            return BloxstrapPresencePatch.parse(line).map(PlayerLogEvent.richPresence)
        }
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
    private struct Cursor { var offset: UInt64 = 0; var remainder = Data() }
    private var cursors: [URL: Cursor] = [:]
    private var didBaseline = false
    public init() {}
    public func reset() { cursors = [:]; didBaseline = false }
    public func poll(directory: URL, now: Date = Date()) throws -> [PlayerLogEvent] {
        try Task.checkCancellation()
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { didBaseline = true; return [] }
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey])
            .filter { $0.pathExtension == "log" && $0.lastPathComponent.lowercased().contains("player") }
        guard urls.count <= 5000 else { throw FeatureError.message("Too many Player logs to track safely.") }
        var candidates: [(URL, Date, UInt64)] = []
        for url in urls {
            try Task.checkCancellation()
            let info = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true else { continue }
            candidates.append((url, info.contentModificationDate ?? .distantPast, UInt64(max(0, info.fileSize ?? 0))))
        }
        if !didBaseline {
            // Baseline every existing Player log. Returning to an older file must not replay another instance's history.
            cursors = Dictionary(uniqueKeysWithValues: candidates.map { ($0.0, Cursor(offset: $0.2)) })
            didBaseline = true
            return []
        }
        guard let (latest, modified, _) = candidates.max(by: { $0.1 < $1.1 }), now.timeIntervalSince(modified) < 300 else { return [] }
        let existing = Set(candidates.map { $0.0 })
        cursors = cursors.filter { existing.contains($0.key) }
        var cursor = cursors[latest] ?? Cursor()
        let handle = try FileHandle(forReadingFrom: latest)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end < cursor.offset { cursor = Cursor() }
        try handle.seek(toOffset: cursor.offset)
        let data = try handle.read(upToCount: 262_144) ?? Data()
        cursor.offset += UInt64(data.count)
        cursor.remainder.append(data)
        guard let newline = cursor.remainder.lastIndex(of: 10) else {
            if cursor.remainder.count > 262_144 { cursor.remainder = Data() }
            cursors[latest] = cursor
            return []
        }
        let complete = cursor.remainder.prefix(through: newline)
        cursor.remainder = Data(cursor.remainder.suffix(from: newline + 1))
        cursors[latest] = cursor
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
