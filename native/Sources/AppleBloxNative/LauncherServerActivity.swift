import AppleBloxCore
import Foundation

extension LauncherModel {
    func setServerNotifications(_ enabled: Bool) async {
        guard !isRequestingNotifications, !isBusy, canSave else { return }
        if !enabled { setFeature(\.serverJoinedNotifications, false); return }
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }
        do {
            let allowed = try await gameNotifications.enable()
            notificationStatus = await gameNotifications.status()
            guard allowed else { errorMessage = "Allow AppleBlox notifications in macOS Settings to enable Server Joined alerts."; return }
            setFeature(\.serverJoinedNotifications, true)
        } catch { errorMessage = "Couldn’t request notification permission." }
    }

    func resetServerActivity() {
        serverActivityTask?.cancel(); serverActivityTask = nil; serverActivityRequestID = nil
        serverConnection.reset(); serverNoticePending = false; serverRegion = nil
        serverLocationStatus = "Waiting for a new game server connection."
    }

    func refreshServerActivity() {
        serverActivityTask?.cancel(); serverActivityTask = nil
        serverActivityRequestID = nil; serverRegion = nil
        guard let session = currentSession, serverConnection.sessionID == session.id,
              let endpoint = serverConnection.endpoint else {
            serverLocationStatus = "Waiting for a new game server connection."
            return
        }
        let lookup = configuration.features.serverLocation
        serverLocationStatus = lookup ? "Looking up approximate server location…" : "Connected; location lookup is off."
        guard lookup || serverNoticePending else { return }
        let requestID = UUID()
        serverActivityRequestID = requestID
        serverActivityTask = Task {
            defer { if serverActivityRequestID == requestID { serverActivityTask = nil; serverActivityRequestID = nil } }
            var region: ServerRegion?
            if lookup { region = try? await serverLocations.region(for: endpoint) }
            guard !Task.isCancelled, serverActivityRequestID == requestID, currentSession?.id == session.id,
                  serverConnection.endpoint == endpoint else { return }
            if configuration.features.serverLocation {
                serverRegion = region
                serverLocationStatus = region.map { "Approximate location: \($0.description)" } ?? "Server location unavailable."
            }
            if serverNoticePending, configuration.features.serverJoinedNotifications {
                serverNoticePending = false
                guard serverNoticeLimiter.reserve() else { return }
                let notice = ServerJoinedNotice(region: configuration.features.serverLocation ? region : nil,
                                                sound: configuration.features.notificationSounds)
                do {
                    try await gameNotifications.show(notice, id: requestID) { [weak self] in
                        self?.serverActivityRequestID == requestID && self?.currentSession?.id == session.id &&
                        self?.configuration.features.serverJoinedNotifications == true
                    }
                }
                catch { notificationStatus = "The notification could not be delivered." }
            }
        }
    }
}
