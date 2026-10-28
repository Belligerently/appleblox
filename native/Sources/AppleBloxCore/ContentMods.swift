import CryptoKit
import Foundation
import CoreText
import ImageIO
import UniformTypeIdentifiers

public actor ContentModStore {
    public let directory: URL
    private let fm = FileManager.default
    public init(directory: URL) { self.directory = directory }
    private struct Manifest: Codable {
        let installation: String
        let version: String
        let originalDigest: String
        var appliedDigest: String
    }

    public func importIconColor(_ color: IconColor, installation: RobloxInstallation) throws -> ContentMod {
        let installation = try RobloxInstallation.inspect(installation.url)
        let resources = installation.url.appendingPathComponent("Contents/Resources")
        try requireDirectory(resources)
        let root = resources.appendingPathComponent(IconFontColorizer.resourcePath)
        try checkParents(of: root, inside: resources)
        try requireDirectory(root)
        let workspace = directory.appendingPathComponent("icon-import-\(UUID())")
        defer { try? fm.removeItem(at: workspace) }
        let output = workspace.appendingPathComponent(IconFontColorizer.resourcePath)
        try fm.createDirectory(at: output.appendingPathComponent("Font"), withIntermediateDirectories: true)
        for name in ["BuilderIcons-Regular", "BuilderIcons-Filled"] {
            try Task.checkCancellation()
            let source = root.appendingPathComponent("Font/\(name).ttf")
            try checkParents(of: source, inside: resources)
            let attributes = try fm.attributesOfItem(atPath: source.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 20_971_520 else { throw EngineError.unsafePath }
            let tinted = try IconFontColorizer.colorize(Data(contentsOf: source), color: color)
            let descriptors = CTFontManagerCreateFontDescriptorsFromData(tinted as CFData)
            guard CFArrayGetCount(descriptors) == 1 else {
                throw FeatureError.message("macOS could not read the generated icon font. No mod was created.")
            }
            try tinted.write(to: output.appendingPathComponent("Font/\(name).otf"), options: .atomic)
        }
        let family = root.appendingPathComponent("BuilderIcons.json")
        try checkParents(of: family, inside: resources)
        let attributes = try fm.attributesOfItem(atPath: family.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else { throw EngineError.unsafePath }
        try IconFontColorizer.family(Data(contentsOf: family)).write(to: output.appendingPathComponent("BuilderIcons.json"), options: .atomic)
        try Task.checkCancellation()
        var mod = try importFolder(workspace)
        mod.name = "Icons \(color.hex)"
        mod.iconColorHex = color.hex
        mod.enabled = false
        return mod
    }

    public func importFont(_ font: URL, installation: RobloxInstallation) throws -> ContentMod {
        guard ["ttf", "otf"].contains(font.pathExtension.lowercased()),
              try fm.attributesOfItem(atPath: font.path)[.type] as? FileAttributeType == .typeRegular,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(font as CFURL), CFArrayGetCount(descriptors) > 0 else {
            throw FeatureError.message("Choose a valid TrueType or OpenType font.")
        }
        let installation = try RobloxInstallation.inspect(installation.url)
        let workspace = directory.appendingPathComponent("font-import-\(UUID())")
        defer { try? fm.removeItem(at: workspace) }
        let fontRoot = workspace.appendingPathComponent("content/fonts")
        let families = fontRoot.appendingPathComponent("families")
        try fm.createDirectory(at: families, withIntermediateDirectories: true)
        let filename = "AppleBlox-\(UUID().uuidString).\(font.pathExtension.lowercased())"
        try fm.copyItem(at: font, to: fontRoot.appendingPathComponent(filename))
        let originalFamilies = installation.url.appendingPathComponent("Contents/Resources/content/fonts/families")
        try requireDirectory(originalFamilies)
        var count = 0
        for file in try fm.contentsOfDirectory(at: originalFamilies, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            guard try fm.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType == .typeRegular else { throw EngineError.unsafePath }
            let data = try Self.fontFamily(Data(contentsOf: file), asset: "rbxasset://fonts/\(filename)")
            try data.write(to: families.appendingPathComponent(file.lastPathComponent), options: .atomic)
            count += 1
        }
        guard count > 0 else { throw FeatureError.message("This Player has no font family definitions to customize.") }
        var mod = try importFolder(workspace)
        mod.name = "Font: \(font.deletingPathExtension().lastPathComponent)"
        return mod
    }

    static func fontFamily(_ data: Data, asset: String) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var faces = object["faces"] as? [[String: Any]], !faces.isEmpty else {
            throw FeatureError.message("A Roblox font family definition is unreadable.")
        }
        for index in faces.indices { faces[index]["assetId"] = asset }
        object["faces"] = faces
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    public func importFolder(_ source: URL) throws -> ContentMod {
        let files = try modFiles(source)
        let mod = ContentMod(name: source.lastPathComponent, fileCount: files.count)
        let target = directory.appendingPathComponent("packages/\(mod.id.uuidString)")
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: false)
        do {
            for path in files {
                let out = target.appendingPathComponent(path)
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source.appendingPathComponent(path), to: out)
            }
        } catch { try? fm.removeItem(at: target); throw error }
        return mod
    }

    public func checkedPackageURL(_ mod: ContentMod) throws -> URL {
        let root = directory.standardizedFileURL
        try requireDirectory(root)
        let package = packageURL(mod).standardizedFileURL
        try checkParents(of: package, inside: root)
        try requireDirectory(package)
        return package
    }

    /// Reads only registered imported copies. Removed entries and backups are never rediscovered.
    public func scan(_ mods: [ContentMod]) throws -> ModLibraryScan {
        guard Set(mods.map(\.id)).count == mods.count else { throw FeatureError.message("The mod library has duplicate records.") }
        var updated = mods
        var issues: [ModLibraryIssue] = []
        var claims: [String: (path: String, indices: [Int])] = [:]
        for index in mods.indices {
            try Task.checkCancellation()
            let mod = mods[index]
            do {
                let files = try modFiles(checkedPackageURL(mod))
                updated[index].fileCount = files.count
                for path in files {
                    let key = path.lowercased()
                    if var claim = claims[key] {
                        if !claim.indices.contains(index) { claim.indices.append(index) }
                        claims[key] = claim
                    } else { claims[key] = (path, [index]) }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { issues.append(ModLibraryIssue(id: mod.id, name: mod.name, message: error.localizedDescription)) }
        }
        let overlaps = claims.values.filter { $0.indices.count > 1 }.map { claim in
            ModLibraryConflict(path: claim.path, modIDs: claim.indices.map { mods[$0].id }, names: claim.indices.map { mods[$0].name })
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return ModLibraryScan(mods: updated, issues: issues, overlaps: overlaps)
    }

    /// Registered local packs only; thumbnails never read Player resources or create disk caches.
    public func visualSummary(_ mod: ContentMod) throws -> ModVisualSummary {
        let root = try checkedPackageURL(mod)
        let files = try modFiles(root)
        var bytes: Int64 = 0
        var previews: [ModThumbnail] = []
        for path in files {
            try Task.checkCancellation()
            let url = root.appendingPathComponent(path)
            try checkParents(of: url, inside: root)
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw EngineError.unsafePath }
            bytes += (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if previews.count < 3, ["png", "jpg", "jpeg", "webp", "bmp", "tga"].contains(url.pathExtension.lowercased()),
               let image = try? Self.thumbnail(url) {
                previews.append(ModThumbnail(path: path, png: image))
            }
        }
        return ModVisualSummary(byteCount: bytes, fileCount: files.count, thumbnails: previews)
    }
    private static func thumbnail(_ url: URL) throws -> Data {
        guard let bytes = try SupportFiles.readRegular(url, limit: 8_388_608),
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              (1...32).contains(CGImageSourceGetCount(source)),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...16384).contains(width), (1...16384).contains(height), width * height <= 40_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 192, kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw EngineError.unsafePath }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw EngineError.unsafePath }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw EngineError.unsafePath }
        return output as Data
    }

    public func hasBackup(_ installation: RobloxInstallation) -> Bool {
        fm.fileExists(atPath: backupFolder(installation).appendingPathComponent("manifest.json").path)
    }

    public func archiveBackup(for installation: RobloxInstallation) throws {
        let source = backupFolder(installation)
        guard fm.fileExists(atPath: source.path) else { return }
        let archive = directory.appendingPathComponent("previous-installations", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.moveItem(at: source, to: archive.appendingPathComponent(UUID().uuidString))
    }

    public func apply(_ mods: [ContentMod], to installation: RobloxInstallation) throws {
        let installation = try RobloxInstallation.inspect(installation.url)
        let resources = installation.url.appendingPathComponent("Contents/Resources")
        try requireDirectory(resources)
        let backup = backupFolder(installation)
        let manifestURL = backup.appendingPathComponent("manifest.json")
        let currentDigest = try digest(resources)
        let manifest: Manifest
        if fm.fileExists(atPath: manifestURL.path) {
            let existing = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            guard existing.installation == installation.url.path, existing.version == installation.version,
                  existing.appliedDigest == currentDigest,
                  existing.originalDigest == (try digest(backup.appendingPathComponent("Resources"))) else { throw changedError }
            manifest = existing
        } else {
            try fm.createDirectory(at: backup, withIntermediateDirectories: true)
            let original = backup.appendingPathComponent("Resources")
            // A prior interrupted backup is never treated as complete.
            if fm.fileExists(atPath: original.path) { try fm.removeItem(at: original) }
            try fm.copyItem(at: resources, to: original)
            manifest = Manifest(installation: installation.url.path, version: installation.version, originalDigest: currentDigest, appliedDigest: currentDigest)
            try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        }
        let stage = resources.deletingLastPathComponent().appendingPathComponent(".appleblox-mod-stage-\(UUID())")
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: backup.appendingPathComponent("Resources"), to: stage)
        var claimed = Set<String>()
        for mod in mods where mod.enabled {
            let package = try checkedPackageURL(mod)
            for path in try modFiles(package) {
                guard claimed.insert(path.lowercased()).inserted else {
                    throw FeatureError.message("Two enabled mods replace \(path). Disable one before applying.")
                }
                let target = stage.appendingPathComponent(path)
                try checkParents(of: target, inside: stage)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: package.appendingPathComponent(path), to: target)
            }
        }
        var next = manifest
        next.appliedDigest = try digest(stage)
        try replaceDirectory(resources, with: stage, manifestURL: manifestURL, manifest: JSONEncoder().encode(next))
    }

    public func restore(_ installation: RobloxInstallation) throws {
        let installation = try RobloxInstallation.inspect(installation.url)
        let resources = installation.url.appendingPathComponent("Contents/Resources")
        let backup = backupFolder(installation)
        let manifestURL = backup.appendingPathComponent("manifest.json")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        let original = backup.appendingPathComponent("Resources")
        let current = try digest(resources)
        let originalDigest = try digest(original)
        guard manifest.installation == installation.url.path, manifest.version == installation.version,
              originalDigest == manifest.originalDigest,
              current == manifest.appliedDigest || current == originalDigest else { throw changedError }
        let stage = resources.deletingLastPathComponent().appendingPathComponent(".appleblox-mod-restore-\(UUID())")
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: original, to: stage)
        try replaceDirectory(resources, with: stage, manifestURL: nil, manifest: nil)
        try fm.removeItem(at: backup)
    }

    public func packageURL(_ mod: ContentMod) -> URL { directory.appendingPathComponent("packages/\(mod.id.uuidString)") }
    public func backupsURL() -> URL { directory.appendingPathComponent("backups") }

    private var changedError: FeatureError { .message("Roblox resources changed after the backup, possibly from an update. Nothing was overwritten. Keep the backup and use a fresh installation before reapplying mods.") }
    private func backupFolder(_ installation: RobloxInstallation) -> URL {
        let key = SHA256.hash(data: Data(installation.url.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("backups/\(key)")
    }

    private func requireDirectory(_ url: URL) throws {
        guard try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory else { throw EngineError.unsafePath }
    }

    private func modFiles(_ source: URL) throws -> [String] {
        try requireDirectory(source)
        let root = source.standardizedFileURL.resolvingSymlinksInPath()
        var enumerationError: Error?
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles], errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw EngineError.unsafePath }
        var result: [String] = []
        var paths = Set<String>()
        var bytes = 0
        let extensions: Set<String> = ["png", "jpg", "jpeg", "webp", "bmp", "tga", "dds", "ktx", "ktx2", "ogg", "mp3", "wav", "ttf", "otf", "json"]
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as? FileAttributeType
            guard type == .typeRegular || type == .typeDirectory else { throw EngineError.unsafePath }
            if type == .typeDirectory { continue }
            let path = try relativePath(url, inside: root)
            guard ["content/", "PlatformContent/", "ExtraContent/"].contains(where: { path.hasPrefix($0) }), extensions.contains(url.pathExtension.lowercased()) else {
                throw FeatureError.message("Unsupported mod file: \(path). Use textures, sounds, fonts, or JSON under content, PlatformContent, or ExtraContent.")
            }
            guard paths.insert(path.lowercased()).inserted else { throw FeatureError.message("A mod contains resource paths that differ only by letter case.") }
            bytes += (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard bytes <= 536_870_912, result.count < 10_000 else { throw FeatureError.message("A mod must contain at most 10,000 files and 512 MB of content.") }
            result.append(path)
        }
        if let enumerationError { throw enumerationError }
        guard !result.isEmpty else { throw FeatureError.message("The folder has no mod content. Choose a folder whose children mirror Roblox’s Resources folder.") }
        return result.sorted()
    }

    private func checkParents(of target: URL, inside root: URL) throws {
        var url = target
        while url.path != root.path {
            if let attributes = try? fm.attributesOfItem(atPath: url.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw EngineError.unsafePath }
            url.deleteLastPathComponent()
        }
    }

    private func relativePath(_ url: URL, inside root: URL) throws -> String {
        let normalized = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent)
        let base = root.pathComponents
        guard Array(normalized.pathComponents.prefix(base.count)) == base else { throw EngineError.unsafePath }
        return normalized.pathComponents.dropFirst(base.count).joined(separator: "/")
    }

    private func digest(_ source: URL) throws -> String {
        try requireDirectory(source)
        let root = source.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { throw EngineError.unsafePath }
        var paths: [URL] = []
        for case let url as URL in enumerator { paths.append(url) }
        var hash = SHA256()
        for url in paths.sorted(by: { $0.path < $1.path }) {
            hash.update(data: Data((try relativePath(url, inside: root) + "\0").utf8))
            let type = try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
            if type == .typeRegular {
                hash.update(data: Data("file\0".utf8))
                var contents = SHA256()
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { contents.update(data: data) }
                hash.update(data: Data(contents.finalize()))
            } else if type == .typeSymbolicLink {
                hash.update(data: Data("link\0".utf8))
                hash.update(data: Data(SHA256.hash(data: Data(try fm.destinationOfSymbolicLink(atPath: url.path).utf8))))
            } else { hash.update(data: Data("directory\0".utf8)) }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func replaceDirectory(_ target: URL, with stage: URL, manifestURL: URL?, manifest: Data?) throws {
        let previous = target.deletingLastPathComponent().appendingPathComponent(".appleblox-resources-\(UUID())")
        try fm.moveItem(at: target, to: previous)
        do {
            try fm.moveItem(at: stage, to: target)
            if let manifestURL, let manifest { try manifest.write(to: manifestURL, options: .atomic) }
        } catch {
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: previous, to: target)
            throw error
        }
        try? fm.removeItem(at: previous)
    }
}

public struct ModThumbnail: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let png: Data
}
public struct ModVisualSummary: Sendable {
    public let byteCount: Int64
    public let fileCount: Int
    public let thumbnails: [ModThumbnail]
}
