import FirebaseMessaging
import UIKit
import UserNotifications

@MainActor
@Observable
final class PushNotificationManager: NSObject {
    private(set) var fcmToken: String?
    private(set) var permissionGranted = false

    private var apiClient: APIClient?

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
        Messaging.messaging().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            Task { @MainActor in
                self.permissionGranted = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func registerTokenWithBackend() {
        guard let token = fcmToken, let api = apiClient else { return }
        Task {
            do {
                try await api.registerDeviceToken(fcmToken: token)
            } catch {
                // Token registration is best-effort; retry on next app launch.
            }
        }
    }

    func unregisterTokenFromBackend() {
        guard let token = fcmToken, let api = apiClient else { return }
        Task {
            try? await api.unregisterDeviceToken(fcmToken: token)
        }
    }

    /// Deliver any unread notifications as local banners so the user sees
    /// what they missed while signed out.
    func deliverMissedNotifications(from api: APIClient) {
        Task {
            guard let notifications = try? await api.listNotifications() else { return }
            let unread = notifications.filter { !$0.isRead }
            guard !unread.isEmpty else { return }

            let center = UNUserNotificationCenter.current()
            for (index, notification) in unread.prefix(5).enumerated() {
                let content = UNMutableNotificationContent()
                content.title = notification.title
                if let body = notification.body {
                    content.body = body
                }
                content.sound = .default

                // Stagger slightly so they don't collapse
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(1 + index),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "missed-\(notification.id)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }
    }
}

extension PushNotificationManager: @preconcurrency MessagingDelegate {
    nonisolated func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let fcmToken else { return }
        Task { @MainActor in
            self.fcmToken = fcmToken
            self.registerTokenWithBackend()
        }
    }
}
