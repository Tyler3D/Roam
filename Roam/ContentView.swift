import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppConfig.self) private var appConfig
    @Environment(\.apiClient) private var apiClient
    #if DEBUG
    @State private var showDebugMenu = false
    #endif

    var body: some View {
        Group {
            if authManager.isLoading {
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
        switch appConfig.appMode {
        case .mainRoam:
            MainTabShell(apiClient: apiClient, showDebugMenu: showDebugMenuBinding)
        case .reelIngestionMVP:
            NavigationStack {
                ReelsPage()
                    .environment(\.roamStores, RoamStores(api: apiClient))
                    #if DEBUG
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                showDebugMenu = true
                            } label: {
                                Image(systemName: "wrench.and.screwdriver")
                            }
                        }
                    }
                    #endif
            }
        case .timeEstimatesMVP:
            NavigationStack {
                TimeEstimatesPlaceholderView(showDebugMenu: showDebugMenuBinding)
            }
        }
    }

    private var showDebugMenuBinding: Binding<Bool> {
        #if DEBUG
        $showDebugMenu
        #else
        .constant(false)
        #endif
    }
}

#Preview {
    ContentView()
        .environment(AppConfig())
        .environment(AuthManager())
        .environment(\.apiClient, APIClient(authManager: AuthManager(), appConfig: AppConfig()))
        .environmentObject(ShareIngressCoordinator())
}
