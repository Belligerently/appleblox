import Darwin
import Foundation
import Security

private final class RobloxRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Authenticated requests never follow redirects or forward session headers elsewhere.
        completionHandler(nil)
    }
}

public actor AccountVault {
    private let service = "io.github.Belligerently.AppleBloxNative.sessions"
    public let cookieFile: URL
    public init(cookieFile: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/HTTPStorages/com.roblox.RobloxPlayer.binarycookies")) { self.cookieFile = cookieFile }
    private struct OriginalLogin: Codable { let original: Data? }

    public func identify(session: String) async throws -> RobloxAccount {
        _ = try PlayerCookies.encode(session: session)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let client = URLSession(configuration: configuration, delegate: RobloxRedirectPolicy(), delegateQueue: nil)
        defer { client.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://users.roblox.com/v1/users/authenticated")!)
        request.timeoutInterval = 20
        request.setValue(".ROBLOSECURITY=\(session)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await client.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FeatureError.message("This Roblox session is expired or couldn’t be validated. Sign in again.") }
        let account = try JSONDecoder().decode(RobloxAccount.self, from: data)
        guard account.id > 0 else { throw FeatureError.message("Roblox returned an invalid account.") }
        return account
    }

    public func save(session: String, accountID: Int64) throws { try write(Data(session.utf8), key: "account-\(accountID)") }
    public func remove(accountID: Int64) throws { try remove(key: "account-\(accountID)") }
    public func hasOriginalLogin() throws -> Bool { try read(key: "original-player-login") != nil }

    public func importCurrentLogin() async throws -> RobloxAccount {
        try checkCookiePath()
        let data = try Data(contentsOf: cookieFile)
        guard let session = try PlayerCookies.session(from: data) else { throw FeatureError.message("Roblox has no saved login on this Mac.") }
        let account = try await identify(session: session)
        try save(session: session, accountID: account.id)
        return account
    }

    public func activate(accountID: Int64) async throws {
        guard let credential = try read(key: "account-\(accountID)"), let session = String(data: credential, encoding: .utf8) else { throw FeatureError.message("This account has no saved session. Sign in again.") }
        let verified = try await identify(session: session)
        guard verified.id == accountID else { throw FeatureError.message("The saved session belongs to a different account. Sign in again.") }
        try checkCookiePath()
        if try read(key: "original-player-login") == nil {
            let original = FileManager.default.fileExists(atPath: cookieFile.path) ? try Data(contentsOf: cookieFile) : nil
            try write(JSONEncoder().encode(OriginalLogin(original: original)), key: "original-player-login")
        }
        try writeCookieFile(PlayerCookies.encode(session: session))
    }

    public func restoreOriginalLogin() throws {
        guard let snapshot = try read(key: "original-player-login") else { throw FeatureError.message("No original Player login has been backed up.") }
        let original = try JSONDecoder().decode(OriginalLogin.self, from: snapshot)
        try checkCookiePath()
        if let data = original.original { try writeCookieFile(data) }
        else if FileManager.default.fileExists(atPath: cookieFile.path) { try FileManager.default.removeItem(at: cookieFile) }
        try remove(key: "original-player-login")
    }

    private func checkCookiePath() throws {
        for url in [cookieFile.deletingLastPathComponent(), cookieFile] {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw EngineError.unsafePath }
        }
    }
    private func writeCookieFile(_ data: Data) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: cookieFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = cookieFile.deletingLastPathComponent().appendingPathComponent(".appleblox-cookie-\(UUID())")
        defer { try? fm.removeItem(at: temporary) }
        guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw FeatureError.message("Couldn’t write the Player login file.") }
        guard Darwin.rename(temporary.path, cookieFile.path) == 0 else { throw FeatureError.message("Couldn’t replace the Player login file.") }
    }
    private func query(_ key: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key] }
    private func read(key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw keychainError(status) }
        return result as? Data
    }
    private func write(_ data: Data, key: String) throws {
        let query = query(key)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrSynchronizable as String] = false
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw keychainError(added) }
        } else if status != errSecSuccess { throw keychainError(status) }
    }
    private func remove(key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }
    private func keychainError(_ status: OSStatus) -> FeatureError {
        .message("Keychain couldn’t complete the request: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))")
    }
}
