import Foundation
import Testing
@testable import AppleBloxCore

private struct PlayerFolderFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABFolder-\(UUID())")
    var app: URL { root.appendingPathComponent("Roblox.app") }
    var contents: URL { app.appendingPathComponent("Contents") }
    init() throws {
        let executable = contents.appendingPathComponent("MacOS/RobloxPlayer")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let info = ["CFBundleIdentifier": RobloxInstallation.bundleIdentifier, "CFBundlePackageType": "APPL", "CFBundleExecutable": "RobloxPlayer"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test func playerContentsShortcutResolvesTheValidatedSelectedBundle() throws {
    let fixture = try PlayerFolderFixture()
    defer { fixture.remove() }
    let installation = try RobloxInstallation.inspect(fixture.app)
    #expect(try installation.contentsDirectory().path == fixture.contents.path)
    let alias = fixture.root.appendingPathComponent("Alias.app")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.app)
    #expect(try RobloxInstallation.inspect(alias).contentsDirectory().path == fixture.contents.path)
}

@Test func playerContentsShortcutRejectsRedirectedContentsEvenWhenBundleLooksValid() throws {
    let fixture = try PlayerFolderFixture()
    defer { fixture.remove() }
    let installation = try RobloxInstallation.inspect(fixture.app)
    let outside = fixture.root.appendingPathComponent("Outside")
    try FileManager.default.moveItem(at: fixture.contents, to: outside)
    try FileManager.default.createSymbolicLink(at: fixture.contents, withDestinationURL: outside)
    #expect(throws: InstallationError.self) { try installation.contentsDirectory() }
    #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("Info.plist").path))
}

@Test func playerContentsShortcutRevalidatesAnInstallationChangedSinceDiscovery() throws {
    let fixture = try PlayerFolderFixture()
    defer { fixture.remove() }
    let installation = try RobloxInstallation.inspect(fixture.app)
    try FileManager.default.removeItem(at: fixture.contents.appendingPathComponent("MacOS/RobloxPlayer"))
    #expect(throws: InstallationError.self) { try installation.contentsDirectory() }
}
