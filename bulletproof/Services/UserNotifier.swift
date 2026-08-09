import Foundation
import UserNotifications
import os

nonisolated protocol NotificationCenterFacade: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func deliver(title: String, body: String) async
}

nonisolated struct SystemNotificationCenter: NotificationCenterFacade {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    func deliver(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// Failures inside a Services callback or hotkey flow are invisible to the
/// user, so every outcome that needs explaining goes through a notification
/// banner. Authorization is requested once at launch; a denied state is
/// logged here and surfaced in Settings, never silently re-prompted per post.
nonisolated struct UserNotifier {
    var center: any NotificationCenterFacade = SystemNotificationCenter()
    private static let logger = Logger(subsystem: "com.mahdiyusuf.bulletproof", category: "notifications")

    static func requestAuthorizationAtLaunch() {
        Task {
            _ = await SystemNotificationCenter().requestAuthorization()
        }
    }

    func post(title: String, body: String) {
        let center = center
        Task {
            await Self.deliver(title: title, body: body, via: center)
        }
    }

    static func deliver(title: String, body: String, via center: any NotificationCenterFacade) async {
        switch await center.authorizationStatus() {
        case .denied:
            logger.warning("Notification suppressed (authorization denied): \(title)")
        case .notDetermined:
            // Launch-time request raced or was dismissed; try once more.
            if await center.requestAuthorization() {
                await center.deliver(title: title, body: body)
            }
        default:
            await center.deliver(title: title, body: body)
        }
    }
}
