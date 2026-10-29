import Foundation

/// CFNetwork binary-cookie format. No credential values are included in errors or logs.
public enum PlayerCookies {
    public static func encode(session: String, now: Date = Date()) throws -> Data {
        guard !session.isEmpty, session.utf8.count < 32_768,
              session.utf8.allSatisfy({ $0 >= 32 && $0 < 127 && $0 != 59 }) else { throw FeatureError.message("Invalid Roblox session.") }
        let strings = [".roblox.com", ".ROBLOSECURITY", "/", session].map { Data(($0 + "\0").utf8) }
        var record = Data(count: 56)
        func set32(_ number: UInt32, _ offset: Int, in data: inout Data) {
            var number = number.littleEndian
            withUnsafeBytes(of: &number) { data.replaceSubrange(offset..<offset+4, with: $0) }
        }
        set32(5, 8, in: &record) // Secure + HttpOnly; offset 4 is the format version.
        for (index, string) in strings.enumerated() {
            set32(UInt32(record.count), 16 + index * 4, in: &record)
            record.append(string)
        }
        set32(UInt32(record.count), 0, in: &record)
        for (offset, date) in [(40, now.addingTimeInterval(31_536_000)), (48, now)] {
            var value = date.timeIntervalSinceReferenceDate.bitPattern.littleEndian
            withUnsafeBytes(of: &value) { record.replaceSubrange(offset..<offset+8, with: $0) }
        }
        var page = Data([0, 0, 1, 0])
        page.append(word(1, bigEndian: false)); page.append(word(16, bigEndian: false)); page.append(word(0, bigEndian: false)); page.append(record)
        var file = Data("cook".utf8)
        file.append(word(1, bigEndian: true)); file.append(word(UInt32(page.count), bigEndian: true)); file.append(page)
        let checksum = stride(from: 0, to: page.count, by: 4).reduce(UInt32(0)) { $0 &+ UInt32(page[$1]) }
        file.append(word(checksum, bigEndian: true))
        file.append(Data([0x07, 0x17, 0x20, 0x05, 0, 0, 0, 0x4b]))
        file.append(try PropertyListSerialization.data(fromPropertyList: ["NSHTTPCookieAcceptPolicy": 0], format: .binary, options: 0))
        return file
    }

    public static func session(from data: Data) throws -> String? {
        guard data.count >= 12, data.prefix(4) == Data("cook".utf8), data.count <= 4_194_304 else { throw malformed }
        let pages = Int(try uint32(data, 4, bigEndian: true))
        guard pages > 0, pages <= 4096, 8 + pages * 4 <= data.count else { throw malformed }
        var pageStart = 8 + pages * 4
        for index in 0..<pages {
            let size = Int(try uint32(data, 8 + index * 4, bigEndian: true))
            guard size >= 12, size <= data.count - pageStart else { throw malformed }
            let page = Data(data[pageStart..<pageStart + size])
            let count = Int(try uint32(page, 4))
            guard count <= 4096, 8 + count * 4 <= page.count else { throw malformed }
            for cookieIndex in 0..<count {
                let start = Int(try uint32(page, 8 + cookieIndex * 4))
                let length = Int(try uint32(page, start))
                guard length >= 56, start <= page.count - length else { throw malformed }
                let record = Data(page[start..<start + length])
                func string(_ field: Int) throws -> String {
                    let offset = Int(try uint32(record, field))
                    guard offset >= 56, offset < record.count, let end = record[offset...].firstIndex(of: 0),
                          let value = String(data: record[offset..<end], encoding: .utf8) else { throw malformed }
                    return value
                }
                let domain = try string(16)
                if try string(20) == ".ROBLOSECURITY", [".roblox.com", "roblox.com"].contains(domain.lowercased()) { return try string(28) }
            }
            pageStart += size
        }
        return nil
    }

    private static var malformed: FeatureError { .message("The Roblox cookie file is unreadable. It was left untouched.") }
    private static func uint32(_ data: Data, _ offset: Int, bigEndian: Bool = false) throws -> UInt32 {
        guard offset >= 0, offset <= data.count - 4 else { throw malformed }
        let number = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return bigEndian ? UInt32(bigEndian: number) : UInt32(littleEndian: number)
    }
    private static func word(_ number: UInt32, bigEndian: Bool) -> Data {
        var number = bigEndian ? number.bigEndian : number.littleEndian
        return withUnsafeBytes(of: &number) { Data($0) }
    }
}
