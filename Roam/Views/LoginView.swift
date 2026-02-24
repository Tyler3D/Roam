import SwiftUI
import GoogleSignInSwift

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppConfig.self) private var appConfig
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showSignup = false
    @State private var showResetPassword = false
    #if DEBUG
    @State private var showDebugMenu = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    loginCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
            .background(ThemeColors.background)
            .alert("Error", isPresented: .constant(authManager.errorMessage != nil)) {
                Button("OK") { authManager.errorMessage = nil }
            } message: {
                Text(authManager.errorMessage ?? "")
            }
            .sheet(isPresented: $showSignup) {
                SignupView()
            }
            .sheet(isPresented: $showResetPassword) {
                ResetPasswordView()
            }
            #if DEBUG
            .sheet(isPresented: $showDebugMenu) {
                DebugMenuView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDebugMenu = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                }
            }
            #endif
            .preferredColorScheme(.light)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "map.fill")
                .font(.system(size: 52))
                .foregroundStyle(ThemeColors.primary)
            Text("Roam")
                .font(.largeTitle.bold())
            Text("Save and discover places from your reels")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome back")
                    .font(.title2.bold())
                Text("Sign in to keep saving date ideas.")
                    .font(.subheadline)
                    .foregroundStyle(ThemeColors.mutedForeground)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Email")
                    .font(.subheadline.weight(.medium))
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                Text("Password")
                    .font(.subheadline.weight(.medium))
                SecureField("••••••••", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
            }

            if let msg = authManager.errorMessage {
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await signIn() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(ThemeColors.primary)
            .disabled(email.isEmpty || password.isEmpty || isLoading)

            GoogleSignInButton(scheme: .light, style: .standard, state: .normal) {
                Task { await signInWithGoogle() }
            }
            .disabled(isLoading)

            if appConfig.currentMode == .mock {
                Button("Sign in (Mock)") {
                    Task { @MainActor in authManager.signInMock() }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            VStack(alignment: .leading, spacing: 12) {
                Button("Forgot password?") {
                    showResetPassword = true
                }
                .font(.subheadline)
                .foregroundStyle(ThemeColors.primary)

                HStack(spacing: 4) {
                    Text("New here?")
                        .font(.subheadline)
                        .foregroundStyle(ThemeColors.mutedForeground)
                    Button("Create an account") {
                        showSignup = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(ThemeColors.primary)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemeColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(ThemeColors.border, lineWidth: 1)
        )
        .shadow(color: ThemeColors.shadow, radius: 8, x: 0, y: 2)
    }

    private func signIn() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.signIn(email: email, password: password)
        } catch {
            logError("Sign in failed", error)
            authManager.errorMessage = errorMessage(for: error)
        }
    }

    private func signInWithGoogle() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.signInWithGoogle()
        } catch {
            logError("Google sign in failed", error)
            authManager.errorMessage = errorMessage(for: error)
        }
    }

}

// MARK: - Error logging (visible in Xcode Debug Console)

private func logError(_ context: String, _ error: Error) {
    let ns = error as NSError
    print("[Roam] \(context): \(ns.domain) \(ns.code) \(ns.localizedDescription)")
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
        print("[Roam]   underlying: \(underlying.domain) \(underlying.code) \(underlying.localizedDescription)")
    }
    print("[Roam]   userInfo: \(ns.userInfo)")
}

private func errorMessage(for error: Error) -> String {
    let ns = error as NSError
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, !underlying.localizedDescription.isEmpty {
        return "\(ns.localizedDescription): \(underlying.localizedDescription)"
    }
    return ns.localizedDescription
}

#Preview {
    LoginView()
        .environment(AppConfig())
        .environment(AuthManager())
}
