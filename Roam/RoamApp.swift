import FirebaseCore
import SwiftUI

@main
struct RoamApp: App {
    init() {
        // Always configure Firebase at launch. Mock network mode uses `AuthManager(isMock: true)`,
        // which never touches `Auth.auth()` in `init`, but switching Mock → Prod must find Firebase
        // already configured before a real `AuthManager` is created.
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Creates AuthManager and APIClient from AppConfig; injects into environment. Recreates them when app mode changes.
private struct RootView: View {
    @State private var appConfig = AppConfig()
    @State private var authManager: AuthManager
    @State private var apiClient: APIClient

    init() {
        let c = AppConfig()
        let isMock = c.networkEnv == .mock
        let auth = AuthManager(isMock: isMock)
        _appConfig = State(initialValue: c)
        _authManager = State(initialValue: auth)
        _apiClient = State(initialValue: APIClient(authManager: auth, appConfig: c))
    }

    var body: some View {
        ContentView()
            .environment(appConfig)
            .environment(authManager)
            .environment(\.apiClient, apiClient)
            .onChange(of: appConfig.networkEnv) { _, newEnv in
                let isMock = (newEnv == .mock)
                if isMock {
                    authManager = AuthManager(isMock: true)
                } else {
                    authManager = AuthManager(isMock: false)
                }
                apiClient = APIClient(authManager: authManager, appConfig: appConfig)
            }
    }
}
