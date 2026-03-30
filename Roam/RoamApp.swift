import FirebaseCore
import SwiftUI
import UIKit

@main
struct RoamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Enable verbose Firebase logging in debug to diagnose token issues
        #if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.debug)
        #endif
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
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
    @State private var eventKitService = EventKitService()
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
            .environment(\.eventKitService, eventKitService)
            .environmentObject(shareIngress)
            .onOpenURL { url in
                if url.scheme?.lowercased() == "roam", url.host?.lowercased() == "share" {
                    SharedStore.markPendingShareHandoff()
                    shareIngress.prioritizeReelsTabForShareHandoff()
                }
            }
    }
}

