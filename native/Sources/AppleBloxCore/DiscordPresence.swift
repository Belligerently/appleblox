import Darwin
import Foundation

public actor DiscordPresenceClient {
    private var descriptor: Int32 = -1
    private var clientID: String?
    private var lastActivity: String?
    private var lastSent = Date.distantPast
    private let socketRoots: [String]?
    public init(socketRoots: [String]? = nil) { self.socketRoots = socketRoots }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    public func update(clientID: String, session: PlaySession?, running: Bool) throws {
        guard running else { disconnect(); return }
        let activityKey = "\(clientID):\(session?.id.uuidString ?? "home"):\(session?.name ?? "")"
        do {
            if descriptor < 0 || self.clientID != clientID {
                disconnect()
                try connect(clientID: clientID)
            }
            if lastActivity == activityKey && Date().timeIntervalSince(lastSent) < 15 { return }
            var activity: [String: Any] = ["details": String((session?.name ?? "Browsing Roblox").prefix(128)), "state": "Playing with AppleBlox Native"]
            if let session {
                activity["timestamps"] = ["start": Int(session.startedAt.timeIntervalSince1970)]
                activity["buttons"] = [["label": "View game", "url": "https://www.roblox.com/games/\(session.placeID)/"]]
            }
            let nonce = UUID().uuidString
            try send(opcode: 1, data: JSONSerialization.data(withJSONObject: ["cmd": "SET_ACTIVITY", "args": ["pid": ProcessInfo.processInfo.processIdentifier, "activity": activity], "nonce": nonce]))
            let response = try receiveFrame()
            guard response["evt"] as? String != "ERROR", response["nonce"] as? String == nonce else {
                throw FeatureError.message("Discord rejected the activity update.")
            }
            lastActivity = activityKey
            lastSent = Date()
        } catch { disconnect(); throw error }
    }

    public func disconnect() {
        if descriptor >= 0 { Darwin.close(descriptor) }
        descriptor = -1; clientID = nil; lastActivity = nil
    }

    private func connect(clientID: String) throws {
        let env = ProcessInfo.processInfo.environment
        let roots = socketRoots ?? [env["XDG_RUNTIME_DIR"], env["TMPDIR"], env["TMP"], env["TEMP"], "/tmp"].compactMap { $0 }
        for root in roots {
            for index in 0...9 {
                let path = URL(fileURLWithPath: root).appendingPathComponent("discord-ipc-\(index)").path
                var address = sockaddr_un()
                let bytes = Array(path.utf8) + [0]
                guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { continue }
                address.sun_family = sa_family_t(AF_UNIX)
                address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
                withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
                let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { continue }
                let connected = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
                }
                guard connected == 0 else { Darwin.close(fd); continue }
                descriptor = fd
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                var noSignal: Int32 = 1
                _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
                _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
                do {
                    try send(opcode: 0, data: JSONSerialization.data(withJSONObject: ["v": 1, "client_id": clientID]))
                    let response = try receiveFrame()
                    guard response["evt"] as? String == "READY" else { throw FeatureError.message("Discord did not accept the application ID.") }
                    self.clientID = clientID
                    return
                } catch { disconnect(); throw error }
            }
        }
        throw FeatureError.message("Discord desktop isn’t available. Open Discord to connect Rich Presence.")
    }

    public static func frame(opcode: UInt32, data: Data) -> Data {
        var opcode = opcode.littleEndian
        var length = UInt32(data.count).littleEndian
        var frame = withUnsafeBytes(of: &opcode) { Data($0) }
        frame.append(withUnsafeBytes(of: &length) { Data($0) })
        frame.append(data)
        return frame
    }

    private func send(opcode: UInt32, data: Data) throws {
        let frame = Self.frame(opcode: opcode, data: data)
        var offset = 0
        try frame.withUnsafeBytes { bytes in
            while offset < bytes.count {
                let count = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                guard count > 0 else { throw FeatureError.message("Discord disconnected.") }
                offset += count
            }
        }
    }

    private func read(_ length: Int) throws -> Data {
        var data = Data(count: length)
        var offset = 0
        try data.withUnsafeMutableBytes { bytes in
            while offset < length {
                let count = Darwin.recv(descriptor, bytes.baseAddress!.advanced(by: offset), length - offset, 0)
                guard count > 0 else { throw FeatureError.message("Discord stopped responding.") }
                offset += count
            }
        }
        return data
    }

    private func receiveFrame() throws -> [String: Any] {
        for _ in 0..<8 {
            let header = try read(8)
            let opcode = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
            let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
            guard length <= 65_536 else { throw FeatureError.message("Invalid Discord IPC frame.") }
            let payload = try read(Int(length))
            if opcode == 3 { try send(opcode: 4, data: payload); continue }
            guard opcode == 1, let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                throw FeatureError.message("Discord closed the IPC connection.")
            }
            return object
        }
        throw FeatureError.message("Discord did not acknowledge the update.")
    }
}
