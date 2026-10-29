import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import AppleBloxCore

private func iconFixture(size: Int = 64) throws -> Data {
    let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let image = try #require(context.makeImage())
    let png = NSMutableData()
    let output = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(output, image, nil)
    #expect(CGImageDestinationFinalize(output))
    func number(_ value: Int) -> Data { Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]) }
    let payload = Data(png)
    return Data("icns".utf8) + number(payload.count + 16) + Data("icp6".utf8) + number(payload.count + 8) + payload
}
private struct IconEnvironment {
    let root: URL
    let resources: URL
    let data: URL
    let source: URL
    let bytes: Data
    let library: LauncherIconLibrary
    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ABIcons-\(UUID())")
        resources = root.appendingPathComponent("resources")
        data = root.appendingPathComponent("data")
        source = root.appendingPathComponent("My Icon.icns")
        bytes = try iconFixture()
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("LauncherIcons"), withIntermediateDirectories: true)
        for icon in BundledLauncherIcon.allCases { try bytes.write(to: resources.appendingPathComponent(icon.filename)) }
        try bytes.write(to: source)
        library = LauncherIconLibrary(dataDirectory: data, resources: resources)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
private actor IconDriver {
    var calls: [Data?] = []
    var fail = false
    func apply(_ bytes: Data?) throws {
        if fail { throw LauncherIconError.invalidIcon }
        calls.append(bytes)
    }
    func setFailure() { fail = true }
}

@Test func allBundledNativeIconsDecodeAndHaveBoundedPreviews() throws {
    let native = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for icon in BundledLauncherIcon.allCases where icon != .fork {
        let bytes = try Data(contentsOf: native.appendingPathComponent("Resources/\(icon.filename)"))
        let png = try LauncherIconLibrary.preview(bytes)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width <= 256 && image.height <= 256)
    }
}

@Test func importingCopiesIconsAndDuplicateNamesDoNotOverwrite() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let first = try await env.library.importIcon(from: env.source)
    let second = try await env.library.importIcon(from: env.source)
    #expect(first != second)
    let catalog = try await env.library.previews()
    #expect(catalog.icons.count == 9 && catalog.skipped == 0)
    #expect(catalog.icons.filter(\.isCustom).allSatisfy { $0.name == "My Icon" })
    #expect(try Data(contentsOf: env.source) == env.bytes)
    #expect(try await env.library.selected() == .default)
    let reloaded = LauncherIconLibrary(dataDirectory: env.data, resources: env.resources)
    #expect(try await reloaded.previews().icons.map(\.id) == catalog.icons.map(\.id))
}

@Test func invalidAndOversizedIconsNeverCreateLibraryEntries() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let invalid = [Data("not an icon".utf8), Data(repeating: 1, count: 8_388_609), Data("icns\0\0\0\u{10}bad data".utf8)]
    for bytes in invalid {
        try bytes.write(to: env.source)
        await #expect(throws: (any Error).self) { try await env.library.importIcon(from: env.source) }
    }
    let pngSource = env.root.appendingPathComponent("pretend.png")
    try env.bytes.write(to: pngSource)
    await #expect(throws: (any Error).self) { try await env.library.importIcon(from: pngSource) }
    #expect(try await env.library.previews().icons.count == 7)
}

@Test func linkedImportAndLibraryRootsAreRejected() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let alias = env.root.appendingPathComponent("alias.icns")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: env.source)
    await #expect(throws: (any Error).self) { try await env.library.importIcon(from: alias) }
    try FileManager.default.createDirectory(at: env.data, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: env.data.appendingPathComponent("launcher-icons"), withDestinationURL: env.resources)
    await #expect(throws: (any Error).self) { try await env.library.importIcon(from: env.source) }
    #expect(try Data(contentsOf: env.source) == env.bytes)
}

@Test func selectionAppliesPersistsAndDefaultRestoresWithoutDeletingImports() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let choice = try await env.library.importIcon(from: env.source)
    let driver = IconDriver()
    try await env.library.select(choice) { try await driver.apply($0) }
    #expect(try await env.library.selected() == choice)
    #expect(try await env.library.selectedData() == env.bytes)
    let reloaded = LauncherIconLibrary(dataDirectory: env.data, resources: env.resources)
    #expect(try await reloaded.selected() == choice)
    try await env.library.select(.default) { try await driver.apply($0) }
    #expect(try await env.library.selected() == .default)
    #expect(await driver.calls.count == 2)
    #expect(await driver.calls.last! == nil)
    #expect(try await env.library.previews().icons.count == 8)
}

@Test func failedApplyPreservesSelectionAndSourceFiles() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let choice = try await env.library.importIcon(from: env.source)
    let driver = IconDriver(); await driver.setFailure()
    await #expect(throws: (any Error).self) { try await env.library.select(choice) { try await driver.apply($0) } }
    #expect(try await env.library.selected() == .default)
    #expect(try Data(contentsOf: env.source) == env.bytes)
}

@Test func failedPreferenceSaveRollsBackAppearanceAndPreservesLinkedFile() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let directory = try await env.library.revealDirectory()
    let preserve = env.root.appendingPathComponent("preserve.json")
    let original = Data("preserve me".utf8); try original.write(to: preserve)
    try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("selection.json"), withDestinationURL: preserve)
    let driver = IconDriver()
    await #expect(throws: (any Error).self) { try await env.library.select(.default) { try await driver.apply($0) } }
    #expect(await driver.calls.count == 2)
    #expect(try Data(contentsOf: preserve) == original)
}

@Test func corruptAndFutureSelectionCanRecoverDefaultWithBackup() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let directory = try await env.library.revealDirectory()
    let file = directory.appendingPathComponent("selection.json")
    for bytes in [Data("broken".utf8), Data(#"{"version":99,"choice":{"bundled":{"_0":"fork"}}}"#.utf8)] {
        try bytes.write(to: file)
        await #expect(throws: (any Error).self) { try await env.library.selected() }
        try await env.library.select(.default) { _ in }
        #expect(try await env.library.selected() == .default)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("selection-preserved-") }
        #expect(try backups.contains { try Data(contentsOf: $0) == bytes })
    }
}

@Test func removedIconsAreRecoverableAndActiveIconsCannotBeRemoved() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let choice = try await env.library.importIcon(from: env.source)
    guard case .custom(let id) = choice else { Issue.record("Expected custom icon"); return }
    try await env.library.select(choice) { _ in }
    await #expect(throws: (any Error).self) { try await env.library.remove(id) }
    try await env.library.select(.default) { _ in }
    try await env.library.remove(id)
    #expect(try await env.library.previews().icons.count == 7)
    let directory = try await env.library.revealDirectory()
    let removed = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("removed"), includingPropertiesForKeys: nil)
    #expect(removed.count == 1)
    #expect(try Data(contentsOf: removed[0].appendingPathComponent("icon.icns")) == env.bytes)
    #expect(try Data(contentsOf: env.source) == env.bytes)
    await #expect(throws: (any Error).self) { try await env.library.select(choice) { _ in Issue.record("Missing icon reached apply driver") } }
}

@Test func corruptImportedPackagesAreSkippedAndUnknownFilesPreserved() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let choice = try await env.library.importIcon(from: env.source)
    guard case .custom(let id) = choice else { Issue.record("Expected custom icon"); return }
    let directory = try await env.library.revealDirectory()
    let file = directory.appendingPathComponent(id.uuidString).appendingPathComponent("icon.icns")
    let broken = Data("broken".utf8); try broken.write(to: file)
    let notes = directory.appendingPathComponent("notes.txt"); try Data("preserve".utf8).write(to: notes)
    let catalog = try await env.library.previews()
    #expect(catalog.icons.count == 7 && catalog.skipped == 1)
    #expect(try Data(contentsOf: file) == broken)
    #expect(try String(contentsOf: notes, encoding: .utf8) == "preserve")
}

private actor IconApplyGate {
    var started = false
    var ready: CheckedContinuation<Void, Never>?
    var pending: CheckedContinuation<Void, Never>?
    func suspend() async {
        await withCheckedContinuation { continuation in
            pending = continuation; started = true; ready?.resume(); ready = nil
        }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { ready = $0 }
    }
    func release() { pending?.resume(); pending = nil }
}

@Test func concurrentIconMutationsCannotRaceAnApply() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    let choice = try await env.library.importIcon(from: env.source)
    let gate = IconApplyGate()
    let task = Task { try await env.library.select(choice) { _ in await gate.suspend() } }
    await gate.waitUntilStarted()
    await #expect(throws: (any Error).self) { try await env.library.select(.default) { _ in Issue.record("Concurrent driver called") } }
    await #expect(throws: (any Error).self) { try await env.library.importIcon(from: env.source) }
    if case .custom(let id) = choice {
        await #expect(throws: (any Error).self) { try await env.library.remove(id) }
    }
    await gate.release(); try await task.value
    #expect(try await env.library.selected() == choice)
}

@Test func iconLibraryEnforcesItsImportLimitAndPixelBounds() async throws {
    let env = try IconEnvironment(); defer { env.cleanup() }
    for _ in 0..<32 { _ = try await env.library.importIcon(from: env.source) }
    await #expect(throws: (any Error).self) { try await env.library.importIcon(from: env.source) }
    #expect(try await env.library.previews().icons.count == 39)
    let oversized = try iconFixture(size: 2049)
    #expect(throws: (any Error).self) { try LauncherIconLibrary.preview(oversized) }
}
