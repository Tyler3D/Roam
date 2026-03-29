import FirebaseCore
import SwiftUI

@main
struct RoamApp: App {
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
            .environmentObject(shareIngress)
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
    }
}
