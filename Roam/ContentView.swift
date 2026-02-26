import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppConfig.self) private var appConfig
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [SharedItem] = []
    @State private var showDebugMenu = false

    var body: some View {
        Group {
            if appConfig.isMockAuth {
                // Mock: skip auth, show feature directly
                featureContent
            } else if authManager.isLoading {
                ProgressView("Loading...")
            } else if authManager.isSignedIn {
                AuthGateView { featureContent }
            } else {
                LoginView()
            }
        }
        .environment(authManager)
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) {
            DebugMenuView()
        }
        #endif
    }


    @ViewBuilder
    private var featureContent: some View {
        NavigationStack {
            switch appConfig.appMode {
            case .reelIngestionMVP:
                ReelIngestionView(items: $items, showDebugMenu: $showDebugMenu)
            case .timeEstimatesMVP:
                TimeEstimatesPlaceholderView(showDebugMenu: $showDebugMenu)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppConfig())
        .environment(AuthManager())
        .environment(\.apiClient, APIClient(authManager: AuthManager(), appConfig: AppConfig()))
}
