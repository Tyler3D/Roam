import FirebaseCore
import SwiftUI

@main
struct RoamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let env = AppConfig().networkEnv
        FirebaseEnvironment.configure(for: env)
        GoogleMapsBootstrap.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Creates AuthManager and APIClient from AppConfig; injects into environment.
private struct RootView: View {
    @State private var appConfig: AppConfig
    @State private var authManager: AuthManager
    @State private var apiClient: APIClient
    @State private var pushManager = PushNotificationManager()
    @State private var deepLinkRouter = DeepLinkRouter()
    @StateObject private var shareIngress = ShareIngressCoordinator()

    init() {
        let c = AppConfig()
        let auth = AuthManager()
        _appConfig = State(initialValue: c)
        _authManager = State(initialValue: auth)
        _apiClient = State(initialValue: APIClient(authManager: auth, appConfig: c))
    }

    var body: some View {
        ContentView()
            .environment(appConfig)
            .environment(authManager)
            .environment(\.apiClient, apiClient)
            .environment(pushManager)
            .environment(deepLinkRouter)
            .environmentObject(shareIngress)
            .onAppear {
                pushManager.configure(apiClient: apiClient)
                pushManager.requestPermission()
            }
            .onOpenURL { url in
                if url.scheme?.lowercased() == "roam", url.host?.lowercased() == "share" {
                    SharedStore.markPendingShareHandoff()
                    shareIngress.prioritizeReelsTabForShareHandoff()
                }
            }
            .onChange(of: appConfig.pendingEnvironmentSwitch) { _, isPending in
                guard isPending else { return }
                appConfig.pendingEnvironmentSwitch = false

                // Reconfigure Firebase for the new environment and sign out
                FirebaseEnvironment.reconfigure(to: appConfig.networkEnv)
                authManager.forceSignOut()
            }
            .onReceive(NotificationCenter.default.publisher(for: .roamPushNotificationTapped)) { notification in
                handlePushNotificationTap(userInfo: notification.userInfo)
            }
    }

    private func handlePushNotificationTap(userInfo: [AnyHashable: Any]?) {
        deepLinkRouter.pending = DeepLinkRouter.parse(userInfo: userInfo)
    }
}
