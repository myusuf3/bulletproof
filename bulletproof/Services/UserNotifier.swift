import Foundation
import UserNotifications
import os

/// Failures inside a Services callback are invisible to the user, so every
/// outcome that needs explaining goes through a notification banner.
nonisolated struct UserNotifier {
    private static let logger = Logger(subsystem: "com.mahdiyusuf.bulletproof", category: "notifications")

    func post(title: String, body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.alert]) else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } catch {
                Self.logger.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}
