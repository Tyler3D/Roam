import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppConfig.self) private var appConfig
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [SharedItem] = []
    #if DEBUG
    @State private var showDebugMenu = false
    #endif

    var body: some View {
        Group {
            if authManager.isLoading {
                ProgressView("Loading...")
            } else if authManager.isSignedIn {
                if appConfig.currentMode == .mock {
                    mainContent
                } else {
                    AuthGateView { mainContent }
                }
            } else {
                LoginView()
            }
        }
        .environment(authManager)
    }

    private var mainContent: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Roams Yet",
                        systemImage: "square.and.arrow.up",
                        description: Text("Share a link from Safari, Instagram, or TikTok to see it here.")
                    )
                } else {
                    List(items) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.url ?? item.text ?? "Unknown")
                                    .font(.body)
                                    .lineLimit(2)

                                Text(item.dateShared, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Roam")
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showDebugMenu = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                }
                #endif
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        authManager.signOut()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
                if !items.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Clear All", role: .destructive) {
                            SharedStore.clearAll()
                            items = []
                        }
                    }
                }
            }
            .onAppear {
                items = SharedStore.loadAll()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    items = SharedStore.loadAll()
                }
            }
            #if DEBUG
            .sheet(isPresented: $showDebugMenu) {
                DebugMenuView()
            }
            #endif
        }
    }
}

#Preview {
    ContentView()
        .environment(AppConfig())
        .environment(AuthManager())
        .environment(\.apiClient, APIClient(authManager: AuthManager(), appConfig: AppConfig()))
}
