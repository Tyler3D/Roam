import SwiftUI

struct SignupView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.apiClient) private var apiClient
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var isLoading = false
    @State private var errorText: String?

    private var passwordChecks: PasswordValidation { PasswordValidation(password: password) }
    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
        && !email.trimmingCharacters(in: .whitespaces).isEmpty
        && isValidEmail(email.trimmingCharacters(in: .whitespaces))
        && passwordChecks.allPassed
        && !isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    signupCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }
            .background(ThemeColors.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .preferredColorScheme(.light)
        }
    }

    private var signupCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create your account")
                    .font(.title2.bold())
                Text("Start saving places from your reels.")
                    .font(.subheadline)
                    .foregroundStyle(ThemeColors.mutedForeground)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Username")
                    .font(.subheadline.weight(.medium))
                TextField("yourname", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                Text("Email")
                    .font(.subheadline.weight(.medium))
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                Text("Password")
                    .font(.subheadline.weight(.medium))
                SecureField("Create a password", text: $password)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                passwordChecklist
            }

            if let errorText {
                Text(errorText)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await signUp() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Create account")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(ThemeColors.primary)
            .disabled(!canSubmit)
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

    private var passwordChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            passwordRule(met: passwordChecks.minLength, text: "Longer than 8 characters")
            passwordRule(met: passwordChecks.hasLowercase, text: "One lowercase letter")
            passwordRule(met: passwordChecks.hasUppercase, text: "One uppercase letter")
            passwordRule(met: passwordChecks.hasNumber, text: "One number")
        }
        .font(.subheadline)
        .foregroundStyle(ThemeColors.mutedForeground)
    }

    private func passwordRule(met: Bool, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(met ? ThemeColors.primary : ThemeColors.mutedForeground)
            Text(text)
        }
    }

    private func isValidEmail(_ string: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return string.range(of: pattern, options: .regularExpression) != nil
    }

    private func signUp() async {
        if let msg = PasswordValidation.message(for: password) {
            errorText = msg
            return
        }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            try await authManager.signUp(email: email, password: password)

            if let apiClient {
                try await apiClient.ensureBackendUser(username: username)
            }

            dismiss()
        } catch {
            logError("Sign up / ensureBackendUser failed", error)
            errorText = errorMessage(for: error)
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
    SignupView()
        .environment(AuthManager())
        .environment(\.apiClient, APIClient(authManager: AuthManager(), appConfig: AppConfig()))
}
