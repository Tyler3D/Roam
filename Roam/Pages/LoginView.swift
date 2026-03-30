import SwiftUI
import GoogleSignInSwift

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var isLoading = false
    @State private var email = ""
    @State private var password = ""
    @State private var showSignup = false
    @State private var showResetPassword = false
    #if DEBUG
    @State private var showDebugMenu = false
    #endif

    private let outerBackground = Color(red: 232 / 255, green: 230 / 255, blue: 238 / 255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    logoBlock
                    emailSection
                    authLinksSection
                    dividerWithLabel("or continue with")
                    googleSection
                    dividerWithLabel("how it works")
                    featuresSection
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 40)
            }
            .background(outerBackground)
            .sheet(isPresented: $showSignup) {
                SignupView()
            }
            .sheet(isPresented: $showResetPassword) {
                ResetPasswordView()
            }
            .alert("Error", isPresented: .constant(authManager.errorMessage != nil)) {
                Button("OK") { authManager.errorMessage = nil }
            } message: {
                Text(authManager.errorMessage ?? "")
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

    private var logoBlock: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RoamColors.surface)
                    .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 4)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(RoamColors.reviewBorder, lineWidth: 1.5)
                RoamNeedleLogoView(size: 56)
            }
            .frame(width: 88, height: 88)
            .padding(.bottom, 20)

            Text("roam")
                .font(RoamFont.mono(32, weight: .bold))
                .foregroundStyle(RoamColors.text)
                .padding(.bottom, 8)

            Text("Save places from reels.\nShare them with people you love.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(RoamColors.textMid)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
    }

    private var googleSection: some View {
        VStack(spacing: 16) {
            if let msg = authManager.errorMessage {
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(RoamColors.error)
                    .multilineTextAlignment(.center)
            }

            GoogleSignInButton(scheme: .light, style: .wide, state: isLoading ? .disabled : .normal) {
                Task { await signInWithGoogle() }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RoamColors.reviewBorder, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 4)
            .disabled(isLoading)
        }
    }

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Email")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(RoamColors.text)

            TextField("you@example.com", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.next)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoamColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(RoamColors.reviewBorder, lineWidth: 1)
                )

            if let emailMessage = emailValidationMessage {
                Text(emailMessage)
                    .font(.caption)
                    .foregroundStyle(RoamColors.error)
            }

            Text("Password")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(RoamColors.text)

            SecureField("Enter your password", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoamColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(RoamColors.reviewBorder, lineWidth: 1)
                )
                .onSubmit {
                    guard canSubmitEmailPassword, !isLoading else { return }
                    Task { await signInWithEmailPassword() }
                }

            if let passwordMessage = passwordValidationMessage {
                Text(passwordMessage)
                    .font(.caption)
                    .foregroundStyle(RoamColors.error)
            }

            Button {
                Task { await signInWithEmailPassword() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign in")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(RoamColors.reviewAccent)
            .disabled(isLoading || !canSubmitEmailPassword)

            if let message = formValidationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(RoamColors.textMid)
            }
        }
        .padding(.bottom, 10)
    }

    private var authLinksSection: some View {
        HStack {
            Button("Create account") {
                showSignup = true
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(RoamColors.reviewAccent)

            Spacer()

            Button("Forgot password?") {
                showResetPassword = true
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(RoamColors.textMid)
        }
        .padding(.bottom, 10)
    }

    private func dividerWithLabel(_ label: String) -> some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(RoamColors.reviewBorder)
                .frame(height: 1)
            Rectangle()
                .fill(RoamColors.reviewBorder)
                .frame(height: 1)
        }
        .overlay(alignment: .center) {
            Text(label)
                .font(RoamFont.mono(11, weight: .medium))
                .foregroundStyle(RoamColors.textMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 8)
                .background(outerBackground)
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(
                icon: "film.stack",
                title: "Share a reel",
                detail: "from Instagram or TikTok"
            )
            featureRow(
                icon: "mappin.and.ellipse",
                title: "Places appear",
                detail: "on your personal map"
            )
            featureRow(
                icon: "person.2.fill",
                title: "Share collections",
                detail: "with friends and partners"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(RoamColors.reviewAccentLight)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(RoamColors.reviewAccent)
            }
            (Text(title).fontWeight(.semibold).foregroundStyle(RoamColors.text)
                + Text(" ")
                + Text(detail).foregroundStyle(RoamColors.textMid))
                .font(.system(size: 13))
                .multilineTextAlignment(.leading)
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

    private var canSubmitEmailPassword: Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidEmail(normalizedEmail) && password.count >= 6
    }

    private var emailValidationMessage: String? {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else { return nil }
        return isValidEmail(normalizedEmail) ? nil : "Enter a valid email address."
    }

    private var passwordValidationMessage: String? {
        guard !password.isEmpty else { return nil }
        return password.count >= 6 ? nil : "Password must be at least 6 characters."
    }

    private var formValidationMessage: String? {
        guard !canSubmitEmailPassword else { return nil }
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty {
            return "Enter your email and password to continue."
        }
        return nil
    }

    private func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let localPart = parts[0]
        let domainPart = parts[1]
        guard !localPart.isEmpty, !domainPart.isEmpty else { return false }
        return domainPart.contains(".")
    }

    private func signInWithEmailPassword() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch {
            logError("Email/password sign in failed", error)
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
