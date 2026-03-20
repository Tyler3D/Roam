import FirebaseAuth
import SwiftUI

struct VerificationPendingView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.apiClient) private var apiClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var isResending = false
    @State private var isChecking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 56))
                        .foregroundStyle(ThemeColors.primary)

                    Text("Verify your email")
                        .font(.title2.bold())
                    Text("We sent a verification link to your email. Open it to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    Button("I verified my email") {
                        Task { await checkAndVerify() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ThemeColors.primary)
                    .disabled(isChecking)

                    Button("Resend verification email") {
                        Task { await resend() }
                    }
                    .disabled(isResending)
                }
                .padding(.top, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await refreshAndVerifyIfNeeded() }
                }
            }
        }
    }

    private func checkAndVerify() async {
        isChecking = true
        message = nil
        defer { isChecking = false }
        do {
            _ = try await authManager.getIdToken(forcingRefresh: true)
            try await apiClient.verifyBackendUser()
            try await authManager.reloadUser()
        } catch APIError.httpError(let status, _) where status == 403 {
            message = "Email not verified yet. Check your inbox and tap the link, then try again."
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshAndVerifyIfNeeded() async {
        do {
            _ = try await authManager.getIdToken(forcingRefresh: true)
            try await apiClient.verifyBackendUser()
        } catch {
            // Ignore; user can tap "I verified"
        }
    }

    private func resend() async {
        guard let user = authManager.user else { return }
        isResending = true
        defer { isResending = false }
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                user.sendEmailVerification { error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume() }
                }
            }
            message = "Verification email sent."
        } catch {
            message = error.localizedDescription
        }
    }
}

#Preview {
    VerificationPendingView()
        .environment(AuthManager())
        .environment(\.apiClient, APIClient(authManager: AuthManager(), appConfig: AppConfig()))
}
