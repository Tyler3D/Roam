import SwiftUI

/// After sign-in (local/staging): syncs with backend, then shows ChooseUsernameView, VerificationPendingView, or main content.
struct AuthGateView<MainContent: View>: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.apiClient) private var apiClient
    @ViewBuilder let mainContent: () -> MainContent

    @State private var syncCompleted = false
    @State private var hasBackendUser = false
    @State private var syncError: String?

    var body: some View {
        Group {
            if !syncCompleted {
                ProgressView("Syncing…")
            } else if let syncError {
                VStack(spacing: 16) {
                    Text("Sync failed")
                        .font(.headline)
                    Text(syncError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
        .task {
            await sync()
        }
    }

    private func sync() async {
        guard let apiClient else {
            syncError = "No API client"
            syncCompleted = true
            return
        }
        do {
            hasBackendUser = try await apiClient.syncBackendUser()
            syncCompleted = true
        } catch {
            syncError = error.localizedDescription
            syncCompleted = true
        }
    }
}
