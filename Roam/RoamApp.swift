import FirebaseCore
import SwiftUI

@main
struct RoamApp: App {
    init() {
        FirebaseApp.configure()
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
    }
}
