import AppleBloxCore
import Foundation
import UserNotifications

@MainActor final class GameNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self }

    func enable() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }
    func status() async -> String {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: "Allowed by macOS"
        case .denied: "Blocked in macOS notification settings"
        case .notDetermined: "Permission has not been requested"
        default: "Unavailable"
        }
    }
    func show(_ notice: ServerJoinedNotice, id: UUID, shouldDeliver: @MainActor () -> Bool) async throws {
        let settings = await center.notificationSettings()
        guard !Task.isCancelled, shouldDeliver(),
              settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = notice.sound ? .default : nil
        try await center.add(UNNotificationRequest(identifier: "server-\(id)", content: content, trigger: nil))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
