import Foundation
import Testing
@testable import AppleBloxCore

@Test func shortcutValidatesAndNormalizesInput() throws {
    let shortcut = try GameShortcut(name: "  My game  ", placeID: " 0001818\n")
    #expect(shortcut.name == "My game")
    #expect(shortcut.placeID == "1818")
    #expect(shortcut.launchURL.absoluteString == "roblox://experiences/start?placeId=1818")
    for invalid in ["", "0", "-1", "1&gameId=x", "123.4", "１２３", "18446744073709551616"] {
        #expect(throws: ConfigurationError.self) { try GameShortcut(name: "Game", placeID: invalid) }
    }
    #expect(throws: ConfigurationError.self) { try GameShortcut(name: " \n", placeID: "1818") }
}

@Test func settingsRoundTripPreservesIDsAndCustomPath() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(directory: directory)
    #expect(try store.load() == NativeConfiguration())
    var settings = NativeConfiguration()
    settings.customRobloxPath = "/Applications/Roblox.app"
    settings.shortcuts = [try GameShortcut(name: "Crossroads", placeID: "1818")]
    try store.save(settings)
    #expect(try store.load() == settings)
}

@Test func corruptedOrUnsupportedSettingsAreRejectedAndPreserved() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ConfigurationStore(directory: directory)
    for content in ["broken JSON", "{\"version\":99,\"shortcuts\":[]}",
                    "{\"version\":1,\"shortcuts\":[{\"id\":\"A0D0E3AC-4C49-4D15-81C0-015AB7AB2B23\",\"name\":\"x\",\"placeID\":\"&invalid\"}]}"] {
        let data = Data(content.utf8)
        try data.write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.fileURL) == data)
    }
}

@Test func invalidSaveDoesNotOverwriteExistingSettings() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(directory: directory)
    let settings = NativeConfiguration()
    try store.save(settings)
    let originalData = try Data(contentsOf: store.fileURL)
    var invalid = settings
    let shortcut = try GameShortcut(name: "Duplicate", placeID: "1818")
    invalid.shortcuts = [shortcut, shortcut]
    #expect(throws: ConfigurationError.self) { try store.save(invalid) }
    #expect(try Data(contentsOf: store.fileURL) == originalData)
}

@Test func installationRequiresPlayerIdentifierAndExecutable() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = directory.appendingPathComponent("Roblox.app")
    let contents = app.appendingPathComponent("Contents")
    let executables = contents.appendingPathComponent("MacOS")
    try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
    let executable = executables.appendingPathComponent("RobloxPlayer")
    try Data("fixture".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    func writeInfo(identifier: String, name: String = "RobloxPlayer") throws {
        let plist: [String: String] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": name,
                                      "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.2.3"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }
    try writeInfo(identifier: "com.roblox.RobloxStudio")
    #expect(throws: InstallationError.self) { try RobloxInstallation.inspect(app) }
    try writeInfo(identifier: RobloxInstallation.bundleIdentifier)
    let installation = try RobloxInstallation.inspect(app)
    #expect(installation.version == "1.2.3")
    #expect(RobloxInstallation.discover(candidates: [app, app, directory]).count == 1)
    try writeInfo(identifier: RobloxInstallation.bundleIdentifier, name: "../RobloxPlayer")
    #expect(throws: InstallationError.self) { try RobloxInstallation.inspect(app) }
    try writeInfo(identifier: RobloxInstallation.bundleIdentifier, name: "Missing")
    #expect(throws: InstallationError.self) { try RobloxInstallation.inspect(app) }
}

@Test func nativeDataDirectoryHonorsItsOwnOverride() {
    #expect(ConfigurationStore.defaultDirectory(environment: ["APPLEBLOX_NATIVE_DATA_DIR": "/tmp/native-tests"]).path == "/tmp/native-tests")
    #expect(ConfigurationStore.defaultDirectory(environment: ["APPLEBLOX_DATA_DIR": "/tmp/legacy-tests"]).lastPathComponent == "AppleBlox Native")
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("AppleBloxNativeTests-\(UUID().uuidString)")
}
