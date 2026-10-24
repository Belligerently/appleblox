import Foundation

public struct IconColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    public init(hex: String) throws {
        let text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }), let value = UInt32(digits, radix: 16) else {
            throw FeatureError.message("Use a six-digit hex color, such as #0A84FF.")
        }
        red = UInt8((value >> 16) & 255)
        green = UInt8((value >> 8) & 255)
        blue = UInt8(value & 255)
    }
}

public enum IconFontColorizer {
    public static let resourcePath = "ExtraContent/LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons"

    public static func colorize(_ font: Data, color: IconColor) throws -> Data {
        guard font.count >= 12, font.count <= 20_971_520 else { throw invalidFont }
        let version = try read32(font, at: 0)
        guard [UInt32(0x00010000), 0x4F54544F].contains(version) else { throw invalidFont }
        let count = Int(try read16(font, at: 4))
        guard (1...512).contains(count), 12 + count * 16 <= font.count else { throw invalidFont }
        var tables: [String: Data] = [:]
        var ranges: [Range<Int>] = []
        for index in 0..<count {
            let entry = 12 + index * 16
            let tagBytes = font.subdata(in: entry..<entry + 4)
            guard tagBytes.allSatisfy({ (0x20...0x7E).contains($0) }),
                  let tag = String(data: tagBytes, encoding: .ascii), tables[tag] == nil else { throw invalidFont }
            let offset = Int(try read32(font, at: entry + 8))
            let length = Int(try read32(font, at: entry + 12))
            guard offset >= 12 + count * 16, offset % 4 == 0, offset <= font.count, length <= font.count - offset else { throw invalidFont }
            let range = offset..<offset + length
            guard !ranges.contains(where: { $0.overlaps(range) }) else { throw invalidFont }
            if length > 0 { ranges.append(range) }
            tables[tag] = font.subdata(in: range)
        }
        guard let maxp = tables["maxp"], maxp.count >= 6, var head = tables["head"], head.count >= 54,
              try read32(head, at: 12) == 0x5F0F3CF5 else { throw invalidFont }
        let glyphs = Int(try read16(maxp, at: 4))
        guard glyphs > 0 else { throw invalidFont }
        tables["COLR"] = colorLayers(glyphs: glyphs)
        tables["CPAL"] = palette(color)
        tables.removeValue(forKey: "DSIG")
        put32(0, in: &head, at: 8)
        tables["head"] = head
        let tags = tables.keys.sorted()
        let tableCount = tags.count
        let exponent = Int(log2(Double(tableCount)))
        let searchRange = (1 << exponent) * 16
        var output = Data()
        append32(version, to: &output)
        append16(tableCount, to: &output)
        append16(searchRange, to: &output)
        append16(exponent, to: &output)
        append16(tableCount * 16 - searchRange, to: &output)
        output.append(Data(repeating: 0, count: tableCount * 16))
        var headOffset = 0
        for (index, tag) in tags.enumerated() {
            guard let data = tables[tag] else { throw invalidFont }
            let offset = output.count
            let entry = 12 + index * 16
            output.replaceSubrange(entry..<entry + 4, with: tag.utf8)
            put32(checksum(data), in: &output, at: entry + 4)
            put32(UInt32(offset), in: &output, at: entry + 8)
            put32(UInt32(data.count), in: &output, at: entry + 12)
            output.append(data)
            while output.count % 4 != 0 { output.append(0) }
            if tag == "head" { headOffset = offset }
        }
        // OpenType's head directory checksum is calculated with checkSumAdjustment zero,
        // even after the final whole-file adjustment has been written into the head table.
        put32(0xB1B0AFBA &- checksum(output), in: &output, at: headOffset + 8)
        return output
    }

    static func family(_ data: Data) throws -> Data {
        guard data.count <= 1_048_576, var family = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var faces = family["faces"] as? [[String: Any]], !faces.isEmpty else { throw invalidFamily }
        var found: Set<String> = []
        for index in faces.indices {
            guard let asset = faces[index]["assetId"] as? String,
                  let stem = ["BuilderIcons-Regular", "BuilderIcons-Filled"].first(where: {
                      asset == "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/Font/\($0).ttf" ||
                      asset == "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/Font/\($0).otf"
                  }) else { throw invalidFamily }
            found.insert(stem)
            faces[index]["assetId"] = "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/Font/\(stem).otf"
        }
        guard found.count == 2 else { throw invalidFamily }
        family["faces"] = faces
        return try JSONSerialization.data(withJSONObject: family, options: [.prettyPrinted, .sortedKeys])
    }

    static func checksum(_ data: Data) -> UInt32 {
        var result: UInt32 = 0
        for offset in stride(from: 0, to: data.count, by: 4) {
            var word: UInt32 = 0
            for byte in 0..<4 { word = (word << 8) | (offset + byte < data.count ? UInt32(data[offset + byte]) : 0) }
            result = result &+ word
        }
        return result
    }

    private static func palette(_ color: IconColor) -> Data {
        var data = Data()
        for value in [0, 1, 1, 1] { append16(value, to: &data) }
        append32(14, to: &data)
        append16(0, to: &data)
        data.append(contentsOf: [color.blue, color.green, color.red, 255])
        return data
    }

    private static func colorLayers(glyphs: Int) -> Data {
        var data = Data()
        append16(0, to: &data)
        append16(glyphs, to: &data)
        append32(14, to: &data)
        append32(UInt32(14 + glyphs * 6), to: &data)
        append16(glyphs, to: &data)
        for glyph in 0..<glyphs {
            append16(glyph, to: &data); append16(glyph, to: &data); append16(1, to: &data)
        }
        for glyph in 0..<glyphs { append16(glyph, to: &data); append16(0, to: &data) }
        return data
    }

    private static func read16(_ data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= data.count - 2 else { throw invalidFont }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }
    private static func read32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= data.count - 4 else { throw invalidFont }
        return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
    private static func append16(_ value: Int, to data: inout Data) {
        data.append(contentsOf: [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }
    private static func append32(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }
    private static func put32(_ value: UInt32, in data: inout Data, at offset: Int) {
        data.replaceSubrange(offset..<offset + 4, with: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }
    private static var invalidFont: FeatureError { .message("This Player’s BuilderIcons font is missing, damaged, or unsupported. No icon mod was created.") }
    private static var invalidFamily: FeatureError { .message("This Player’s BuilderIcons family definition is unsupported. No icon mod was created.") }
}
