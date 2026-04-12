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
