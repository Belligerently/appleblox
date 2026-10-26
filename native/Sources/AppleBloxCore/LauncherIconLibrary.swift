import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

public enum BundledLauncherIcon: String, Codable, CaseIterable, Sendable {
    case fork, original, dark, clearLight, clearDark, tintedLight, tintedDark
    public var title: String {
        switch self {
        case .fork: "Native Default"
        case .original: "Original AppleBlox"
        case .dark: "Original Dark"
        case .clearLight: "Original Clear Light"
        case .clearDark: "Original Clear Dark"
        case .tintedLight: "Original Tinted Light"
        case .tintedDark: "Original Tinted Dark"
        }
    }
    var filename: String {
        switch self {
        case .fork: "AppIcon-BlueLeaf-Charcoal.icns"
        case .original: "LauncherIcons/Original.icns"
        case .dark: "LauncherIcons/dark.icns"
        case .clearLight: "LauncherIcons/clear_light.icns"
        case .clearDark: "LauncherIcons/clear_dark.icns"
        case .tintedLight: "LauncherIcons/tinted_light.icns"
        case .tintedDark: "LauncherIcons/tinted_dark.icns"
        }
    }
}
public enum LauncherIconChoice: Codable, Hashable, Sendable {
    case bundled(BundledLauncherIcon), custom(UUID)
    public static let `default`: Self = .bundled(.fork)
}
public struct LauncherIconPreview: Identifiable, Sendable {
    public let id: LauncherIconChoice
    public let name: String
    public let png: Data
    public var isCustom: Bool { if case .custom = id { true } else { false } }
}
public enum LauncherIconError: LocalizedError {
    case invalidIcon, missingIcon, libraryFull, busy, activeIcon, invalidSelection, rollbackFailed
    public var errorDescription: String? {
        switch self {
        case .invalidIcon: "Choose a valid ICNS icon up to 8 MiB, with image sizes no larger than 2048 pixels."
        case .missingIcon: "This icon is missing or unreadable. Its existing files were preserved."
        case .libraryFull: "The library holds up to 32 custom icons. Remove one before importing another."
        case .busy: "An icon change is already in progress."
        case .activeIcon: "Restore the default or apply another icon before removing the active icon."
        case .invalidSelection: "The saved icon selection is unreadable. Restore Native Default to recover; the old selection will be preserved."
        case .rollbackFailed: "The icon change could not be saved or rolled back. Restore Native Default to recover."
        }
    }
}

/// Disk work and ImageIO decoding stay off the UI actor. Only small PNG previews cross to SwiftUI.
public actor LauncherIconLibrary {
    private struct Metadata: Codable { let version: Int; let name: String }
    private struct Selection: Codable { let version: Int; let choice: LauncherIconChoice }
    private let directory: URL
    private let resources: URL
    private var applying = false
    public init(dataDirectory: URL, resources: URL) {
        directory = SupportFiles.canonicalBase(dataDirectory).appendingPathComponent("launcher-icons", isDirectory: true)
        self.resources = resources
    }
    private func checkedDirectory() throws -> URL {
        try SupportFiles.prepareDirectory(directory)
        return directory
    }
    private func package(_ id: UUID) throws -> URL {
        let folder = try checkedDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
        try SupportFiles.validateAncestors(folder)
        guard FileManager.default.fileExists(atPath: folder.path) else { throw LauncherIconError.missingIcon }
        return folder
    }
    private func customIDs() throws -> [UUID] {
        let names = try FileManager.default.contentsOfDirectory(atPath: checkedDirectory().path)
        let ids = names.compactMap(UUID.init(uuidString:)).sorted { $0.uuidString < $1.uuidString }
        guard ids.count <= 32 else { throw LauncherIconError.libraryFull }
        return ids
    }
    private func data(for choice: LauncherIconChoice) throws -> Data {
        let url: URL
        switch choice {
        case .bundled(let icon): url = resources.appendingPathComponent(icon.filename)
        case .custom(let id): url = try package(id).appendingPathComponent("icon.icns")
        }
        guard let bytes = try SupportFiles.readRegular(url, limit: 8_388_608) else { throw LauncherIconError.missingIcon }
        return bytes
    }
    public func selected() throws -> LauncherIconChoice {
        let file = try checkedDirectory().appendingPathComponent("selection.json")
        guard let bytes = try SupportFiles.readRegular(file, limit: 4096) else { return .default }
        guard let value = try? JSONDecoder().decode(Selection.self, from: bytes), value.version == 1 else { throw LauncherIconError.invalidSelection }
        return value.choice
    }
    public func selectedData() throws -> Data {
        let bytes = try data(for: selected())
        _ = try Self.preview(bytes)
        return bytes
    }
    public func previews() throws -> (icons: [LauncherIconPreview], skipped: Int) {
        var skipped = 0
        var result = try BundledLauncherIcon.allCases.map { icon in
            LauncherIconPreview(id: .bundled(icon), name: icon.title, png: try Self.preview(data(for: .bundled(icon))))
        }
        for id in try customIDs() {
            do {
                let folder = try package(id)
                guard let bytes = try SupportFiles.readRegular(folder.appendingPathComponent("name.json"), limit: 1024),
                  let metadata = try? JSONDecoder().decode(Metadata.self, from: bytes), metadata.version == 1,
                  Self.validName(metadata.name) else { throw LauncherIconError.missingIcon }
                result.append(LauncherIconPreview(id: .custom(id), name: metadata.name, png: try Self.preview(data(for: .custom(id)))))
            } catch { skipped += 1 }
        }
        return (result, skipped)
    }
    public func importIcon(from source: URL) throws -> LauncherIconChoice {
        guard !applying else { throw LauncherIconError.busy }
        guard source.isFileURL, source.pathExtension.lowercased() == "icns",
              let bytes = try SupportFiles.readRegular(source, limit: 8_388_608) else { throw LauncherIconError.invalidIcon }
        _ = try Self.preview(bytes)
        guard try customIDs().count < 32 else { throw LauncherIconError.libraryFull }
        let title = String(source.deletingPathExtension().lastPathComponent.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80))
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Icon" : title
        let id = UUID()
        let stage = directory.appendingPathComponent(".import-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        try SupportFiles.writePrivate(bytes, to: stage.appendingPathComponent("icon.icns"))
        try SupportFiles.writePrivate(JSONEncoder().encode(Metadata(version: 1, name: name)), to: stage.appendingPathComponent("name.json"))
        try FileManager.default.moveItem(at: stage, to: directory.appendingPathComponent(id.uuidString))
        return .custom(id)
    }
    /// Removed packages remain recoverable and are never rediscovered as active library entries.
    public func remove(_ id: UUID) throws {
        guard !applying else { throw LauncherIconError.busy }
        guard try selected() != .custom(id) else { throw LauncherIconError.activeIcon }
        let folder = try package(id)
        let removed = directory.appendingPathComponent("removed", isDirectory: true)
        try SupportFiles.prepareDirectory(removed)
        try FileManager.default.moveItem(at: folder, to: removed.appendingPathComponent("\(id.uuidString)-\(UUID())"))
    }
    public func revealDirectory() throws -> URL { try checkedDirectory() }

    /// Driver changes the Dock image only. If saving fails, restore the previous appearance.
    public func select(_ choice: LauncherIconChoice, apply: @Sendable (Data?) async throws -> Void) async throws {
        guard !applying else { throw LauncherIconError.busy }
        applying = true
        defer { applying = false }
        let old = try? selected()
        guard old != nil || choice == .default else { throw LauncherIconError.invalidSelection }
        let nextData = choice == .default ? nil : try data(for: choice)
        // A missing old asset must not prevent explicit recovery to the built-in default.
        if let nextData { _ = try Self.preview(nextData) }
        let oldData: Data? = old == .default ? nil : (try? old.flatMap { try data(for: $0) })
        try await apply(nextData)
        do { try saveSelection(choice) }
        catch {
            do { try await apply(oldData) }
            catch { throw LauncherIconError.rollbackFailed }
            throw error
        }
    }
    private func saveSelection(_ choice: LauncherIconChoice) throws {
        let file = try checkedDirectory().appendingPathComponent("selection.json")
        let original = try SupportFiles.readRegular(file, limit: 4096)
        if let original, (try? JSONDecoder().decode(Selection.self, from: original))?.version != 1 {
            guard choice == .default else { throw LauncherIconError.invalidSelection }
            try SupportFiles.writePrivate(original, to: directory.appendingPathComponent("selection-preserved-\(UUID()).json"))
        }
        let stage = directory.appendingPathComponent(".selection-\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: stage) }
        try SupportFiles.writePrivate(JSONEncoder().encode(Selection(version: 1, choice: choice)), to: stage)
        guard try SupportFiles.readRegular(file, limit: 4096) == original else { throw LauncherIconError.invalidSelection }
        if original == nil { try FileManager.default.linkItem(at: stage, to: file) }
        else if Darwin.rename(stage.path, file.path) != 0 { throw LauncherIconError.invalidSelection }
    }
    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 80 && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    public static func preview(_ bytes: Data) throws -> Data {
        guard bytes.count >= 16, bytes.count <= 8_388_608, bytes.prefix(4) == Data("icns".utf8) else { throw LauncherIconError.invalidIcon }
        let length = bytes[4..<8].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length == bytes.count,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, CGImageSourceGetCount(source) <= 32 else { throw LauncherIconError.invalidIcon }
        var bestIndex = 0
        var largestSize = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...2048).contains(width), (1...2048).contains(height) else { throw LauncherIconError.invalidIcon }
            if width * height > largestSize { largestSize = width * height; bestIndex = index }
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, bestIndex, options as CFDictionary) else { throw LauncherIconError.invalidIcon }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw LauncherIconError.invalidIcon }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw LauncherIconError.invalidIcon }
        return output as Data
    }
}
