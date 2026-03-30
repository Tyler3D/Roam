import SwiftUI

/// After sign-in (local/staging): syncs with backend, then shows ChooseUsernameView, VerificationPendingView, or main content.
struct AuthGateView<MainContent: View>: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.apiClient) private var apiClient
    @ViewBuilder let mainContent: () -> MainContent

    @State private var syncCompleted = false
    @State private var hasBackendUser = false
    @State private var syncError: String?
    @State private var retryTrigger = 0
    #if DEBUG
    @State private var showDebugMenu = false
    #endif

    var body: some View {
        Group {
            if !syncCompleted {
                SplashScreen(status: "Syncing…")
            } else if let error = syncError {
                VStack(spacing: 16) {
                    Text("Sync failed")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        syncError = nil
                        syncCompleted = false
                        retryTrigger += 1
                    }
                    #if DEBUG
                    Button {
                        showDebugMenu = true
                    } label: {
                        Label("Debug", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.bordered)
                    #endif
                }
                .padding()
            } else if !hasBackendUser {
                ChooseUsernameView(onSuccess: { hasBackendUser = true })
            } else if !authManager.isVerified {
                VerificationPendingView()
            } else {
                mainContent()
            }
        }
        .task(id: retryTrigger) {
            await sync()
        }
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) {
            DebugMenuView()
        }
        #endif
    }

    private func sync() async {
        // Align backend environment to the app's Firebase project without touching GoogleService-Info.plist
        await apiClient.autoAlignEnvironmentIfNeeded()
        do {
            hasBackendUser = try await apiClient.syncBackendUser()
            syncCompleted = true
        } catch {
            syncError = error.localizedDescription
            syncCompleted = true
        }
    }
}
