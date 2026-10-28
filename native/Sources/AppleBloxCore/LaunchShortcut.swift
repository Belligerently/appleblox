import Foundation

public enum LaunchShortcut {
    public static func data(placeID: String? = nil) throws -> Data {
        let url: String
        if let placeID {
            let id = try GameShortcut(name: "Shortcut", placeID: placeID).placeID
            url = "appleblox-native://play?placeId=\(id)"
        } else { url = "appleblox-native://launch" }
        return try PropertyListSerialization.data(fromPropertyList: ["URL": url], format: .xml, options: 0)
    }
    public static func save(placeID: String? = nil, to destination: URL) throws {
        guard destination.isFileURL, destination.pathExtension.lowercased() == "webloc" else {
            throw FeatureError.message("Choose a new .webloc filename for the launch shortcut.")
        }
        let parent = SupportFiles.canonicalBase(destination.deletingLastPathComponent())
        try SupportFiles.validateAncestors(parent)
        let target = parent.appendingPathComponent(destination.lastPathComponent)
        let stage = parent.appendingPathComponent(".shortcut-\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: stage) }
        try SupportFiles.writePrivate(data(placeID: placeID), to: stage)
        do { try FileManager.default.linkItem(at: stage, to: target) }
        catch { throw FeatureError.message("Couldn’t save the shortcut. Choose a writable folder and a filename that does not already exist.") }
    }
}
