import FirebaseCore
import SwiftUI

@main
struct RoamApp: App {
    init() {
        let modeRaw = UserDefaults.standard.string(forKey: "roam_app_mode") ?? AppMode.local.rawValue
        if modeRaw != AppMode.mock.rawValue {
            FirebaseApp.configure()
        }
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
        let isMock = c.currentMode == .mock
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
            .onChange(of: appConfig.currentMode) { _, newMode in
                let isMock = (newMode == .mock)
                if isMock {
                    authManager = AuthManager(isMock: true)
                } else {
                    if FirebaseApp.app() == nil { FirebaseApp.configure() }
                    authManager = AuthManager(isMock: false)
                }
                apiClient = APIClient(authManager: authManager, appConfig: appConfig)
            }
    }
}
