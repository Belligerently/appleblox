import Foundation

public struct ServerEndpoint: Equatable, Sendable {
    public let address: String
    public let port: Int
    public init(address: String, port: Int) throws {
        guard Self.publicIPv4(address), (1...65535).contains(port) else { throw FeatureError.message("Not a public IPv4 server endpoint.") }
        self.address = address; self.port = port
    }
    public static func publicIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part), (0...255).contains(number), String(number) == part else { return false }
            octets.append(number)
        }
        let a = octets[0], b = octets[1], c = octets[2]
        // Exclude private, loopback, link-local, shared, test, benchmark, multicast and reserved space.
        return !(a == 0 || a == 10 || a == 127 || a >= 224 || (a == 100 && (64...127).contains(b)) ||
                 (a == 169 && b == 254) || (a == 172 && (16...31).contains(b)) ||
                 (a == 192 && (b == 168 || b == 0 || (b == 88 && c == 99))) ||
                 (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) || (a == 203 && b == 0 && c == 113))
    }
    public static func parse(_ line: String) -> ServerEndpoint? {
        guard line.utf8.count <= 4096, !line.contains("[FLog::Output]"),
              let range = line.range(of: #"\[FLog::Network\] serverId:\s*([0-9.]+)\|([0-9]+)\s*$"#, options: .regularExpression) else { return nil }
        let endpoint = line[range].components(separatedBy: "serverId:").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = endpoint.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = Int(parts[1]) else { return nil }
        return try? Self(address: String(parts[0]), port: port)
    }
}

public struct ServerRegion: Equatable, Sendable {
    public let city: String?
    public let region: String?
    public let country: String
    public var description: String { [city, region, country].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", ") }
    public static func decode(_ bytes: Data, address: String) throws -> Self {
        struct Response: Decodable { let ip: String; let city: String?; let region: String?; let country: String?; let bogon: Bool? }
        guard bytes.count <= 16_384 else { throw FeatureError.message("Server location is unavailable.") }
        let response = try JSONDecoder().decode(Response.self, from: bytes)
        guard response.ip == address, response.bogon != true, let country = response.country,
              country.utf8.count == 2, country.allSatisfy({ $0.isASCII && $0.isUppercase }) else { throw FeatureError.message("Server location is unavailable.") }
        func text(_ value: String?) -> String? {
            guard let value else { return nil }
            let clean = value.components(separatedBy: .controlCharacters).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : String(clean.prefix(80))
        }
        return Self(city: text(response.city), region: text(response.region), country: country)
    }
}

public actor ServerLocationService {
    public typealias Fetch = @Sendable (URL) async throws -> Data
    private let fetch: Fetch
    private var cache: [String: ServerRegion] = [:]
    private var nextRequest = Date.distantPast
    public init(fetch: @escaping Fetch = GameCatalog.fetchPublicData) { self.fetch = fetch }
    public func region(for endpoint: ServerEndpoint, now: Date = Date()) async throws -> ServerRegion {
        try Task.checkCancellation()
        if let cached = cache[endpoint.address] { return cached }
        guard now >= nextRequest else { throw FeatureError.message("Server location lookup is cooling down.") }
        nextRequest = now.addingTimeInterval(10)
        // Always include the validated server IP; never call the provider's self-location endpoint.
        let url = URL(string: "https://ipinfo.io/\(endpoint.address)/json")!
        let bytes = try await fetch(url)
        try Task.checkCancellation()
        let result = try ServerRegion.decode(bytes, address: endpoint.address)
        if cache.count >= 100 { cache.removeAll() }
        cache[endpoint.address] = result
        return result
    }
}

public struct ServerConnectionTracker: Sendable {
    public private(set) var sessionID: UUID?
    public private(set) var endpoint: ServerEndpoint?
    public init() {}
    @discardableResult public mutating func connect(sessionID: UUID, endpoint: ServerEndpoint) -> Bool {
        guard self.sessionID != sessionID || self.endpoint != endpoint else { return false }
        self.sessionID = sessionID; self.endpoint = endpoint
        return true
    }
    public mutating func reset() { sessionID = nil; endpoint = nil }
}

public struct ServerJoinedNotice: Equatable, Sendable {
    public let title = "Server Joined"
    public let body: String
    public let sound: Bool
    public init(region: ServerRegion?, sound: Bool) {
        body = region.map { "Approximate server location: \($0.description)." } ?? "Connected to a Roblox game server."
        self.sound = sound
    }
}

public struct ServerNoticeLimiter: Sendable {
    private var nextAllowed = Date.distantPast
    public init() {}
    public mutating func reserve(now: Date = Date()) -> Bool {
        guard now >= nextAllowed else { return false }
        nextAllowed = now.addingTimeInterval(10)
        return true
    }
}
