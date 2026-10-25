import Foundation

/// The inherited SDK integration supports SetRichPresence. Launch-data/invite commands are ignored.
public struct BloxstrapPresencePatch: Decodable, Equatable, Sendable {
    public let details: String?
    public let state: String?
    public let timeStart: Int64?
    public let timeEnd: Int64?
    public let largeImage: Image?
    public let smallImage: Image?

    public struct Image: Decodable, Equatable, Sendable {
        public let assetId: String?
        public let hoverText: String?
        public let clear: Bool?
        public let reset: Bool?
        private enum CodingKeys: String, CodingKey { case assetId, hoverText, clear, reset }
        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? values.decode(Int64.self, forKey: .assetId), number > 0 {
                assetId = String(number)
            } else if let string = try values.decodeIfPresent(String.self, forKey: .assetId) {
                let id = string.hasPrefix("rbxassetid://") ? String(string.dropFirst(13)) : string
                guard let number = Int64(id), number > 0, id.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                    throw FeatureError.message("Invalid SDK asset ID.")
                }
                assetId = String(number)
            } else { assetId = nil }
            hoverText = try values.decodeIfPresent(String.self, forKey: .hoverText)
            clear = try values.decodeIfPresent(Bool.self, forKey: .clear)
            reset = try values.decodeIfPresent(Bool.self, forKey: .reset)
        }
    }

    public static func parse(_ line: String) -> Self? {
        let marker = "[FLog::Output] [BloxstrapRPC] "
        guard line.utf8.count <= 16_384, let range = line.range(of: marker) else { return nil }
        struct Message: Decodable { let command: String; let data: BloxstrapPresencePatch }
        guard let message = try? JSONDecoder().decode(Message.self, from: Data(line[range.upperBound...].utf8)),
              message.command == "SetRichPresence",
              [message.data.timeStart, message.data.timeEnd].compactMap({ $0 }).allSatisfy({ (0...253_402_300_799).contains($0) }) else { return nil }
        return message.data
    }
}

public enum PresenceOverride<Value: Equatable & Sendable>: Equatable, Sendable {
    case standard, cleared, value(Value)
}

public struct BloxstrapPresenceState: Equatable, Sendable {
    public struct Image: Equatable, Sendable {
        public var assetID: String?
        public var hoverText: String?
        public var hidden = false
        mutating func apply(_ patch: BloxstrapPresencePatch.Image) {
            if patch.reset == true { self = .init(); return }
            if let clear = patch.clear { hidden = clear }
            if let id = patch.assetId { assetID = id }
            if let text = patch.hoverText { hoverText = text == "<reset>" ? nil : BloxstrapPresenceState.text(text) }
        }
    }
    public private(set) var details: PresenceOverride<String> = .standard
    public private(set) var state: PresenceOverride<String> = .standard
    public private(set) var timeStart: PresenceOverride<Int64> = .standard
    public private(set) var timeEnd: PresenceOverride<Int64> = .standard
    public private(set) var largeImage = Image()
    public private(set) var smallImage = Image()
    public init() {}

    public mutating func apply(_ patch: BloxstrapPresencePatch) {
        func string(_ value: String) -> PresenceOverride<String> {
            if value == "<reset>" { return .standard }
            let cleaned = Self.text(value)
            return cleaned.unicodeScalars.count < 2 ? .cleared : .value(cleaned)
        }
        if let value = patch.details { details = string(value) }
        if let value = patch.state { state = string(value) }
        if let value = patch.timeStart { timeStart = value == 0 ? .cleared : .value(value) }
        if let value = patch.timeEnd { timeEnd = value == 0 ? .cleared : .value(value) }
        if let value = patch.largeImage { largeImage.apply(value) }
        if let value = patch.smallImage { smallImage.apply(value) }
    }
    public var assetIDs: [String] {
        Array(Set([largeImage, smallImage].filter { !$0.hidden }.compactMap(\.assetID))).sorted()
    }
    static func text(_ value: String) -> String {
        let clean = value.components(separatedBy: .controlCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Discord limits activity strings by bytes; don't split a Unicode scalar.
        var output = ""
        for scalar in clean.unicodeScalars {
            guard output.utf8.count + scalar.utf8.count <= 128 else { break }
            output.unicodeScalars.append(scalar)
        }
        return output
    }
}

/// Resolves only numeric Roblox asset IDs through the public thumbnail API, never game-provided URLs.
public actor PresenceArtworkCatalog {
    public typealias Fetch = @Sendable (URL) async throws -> Data
    private let fetch: Fetch
    private var cache: [String: URL] = [:]
    private var nextAttempt = Date.distantPast
    public init(fetch: @escaping Fetch = GameCatalog.fetchPublicData) { self.fetch = fetch }

    public func images(for ids: [String], now: Date = Date()) async -> [String: URL] {
        let valid = Array(Set(ids.filter { id in
            id.allSatisfy({ $0.isASCII && $0.isNumber }) && (Int64(id) ?? 0) > 0
        })).sorted().prefix(2)
        let missing = valid.filter { cache[$0] == nil }
        if !missing.isEmpty, now >= nextAttempt {
            nextAttempt = now.addingTimeInterval(10)
            let url = URL(string: "https://thumbnails.roblox.com/v1/assets?assetIds=\(missing.joined(separator: ","))&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false")!
            struct Response: Decodable {
                struct Entry: Decodable { let targetId: Int64; let state: String; let imageUrl: String? }
                let data: [Entry]
            }
            if let bytes = try? await fetch(url), !Task.isCancelled, bytes.count <= 65_536,
               let response = try? JSONDecoder().decode(Response.self, from: bytes) {
                for entry in response.data where entry.state == "Completed" && missing.contains(String(entry.targetId)) {
                    if let url = entry.imageUrl.flatMap(URL.init(string:)), let permitted = GameDetails.permittedIcon(url), permitted.absoluteString.utf8.count <= 1024 {
                        if cache.count >= 128 { cache.removeAll() }
                        cache[String(entry.targetId)] = permitted
                    }
                }
            }
        }
        return Dictionary(uniqueKeysWithValues: valid.compactMap { id in cache[id].map { (id, $0) } })
    }
}
