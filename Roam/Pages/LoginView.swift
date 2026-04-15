import AuthenticationServices
import SwiftUI
import GoogleSignInSwift

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var isLoading = false
    @State private var appleRawNonce: String?
    @State private var showPrivacyPolicy = false
    #if DEBUG
    @State private var showDebugMenu = false
    #endif

    private let outerBackground = Color(red: 232 / 255, green: 230 / 255, blue: 238 / 255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    logoBlock
                    googleSection
                    dividerSection
                    featuresSection
                    privacyFooter
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 40)
            }
            .background(outerBackground)
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
            .sheet(isPresented: $showPrivacyPolicy) {
                SafariView(url: URL(string: "https://roam-alpha.web.app/privacy")!)
                    .ignoresSafeArea()
            }
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

            SignInWithAppleButton(.signIn) { request in
                let raw = AuthManager.makeAppleSignInRawNonce()
                appleRawNonce = raw
                request.nonce = AuthManager.appleSignInHashedNonce(rawNonce: raw)
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    Task { await completeAppleSignIn(authorization: authorization) }
                case .failure(let error):
                    if let authErr = error as? ASAuthorizationError, authErr.code == .canceled {
                        return
                    }
                    logError("Apple sign in failed", error)
                    authManager.errorMessage = errorMessage(for: error)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RoamColors.reviewBorder, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 4)
            .disabled(isLoading)
        }
    }

    private var dividerSection: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(RoamColors.reviewBorder)
                .frame(height: 1)
            Text("how it works")
                .font(RoamFont.mono(11, weight: .medium))
                .foregroundStyle(RoamColors.textMuted)
                .textCase(.uppercase)
            Rectangle()
                .fill(RoamColors.reviewBorder)
                .frame(height: 1)
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

    private var privacyFooter: some View {
        Button {
            showPrivacyPolicy = true
        } label: {
            Text("Privacy Policy")
                .font(RoamFont.mono(11))
                .foregroundStyle(RoamColors.textMuted)
                .underline()
        }
        .padding(.top, 28)
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

    private func completeAppleSignIn(authorization: ASAuthorization) async {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            authManager.errorMessage = AuthError.missingAppleIDToken.localizedDescription
            return
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            authManager.errorMessage = AuthError.missingAppleIDToken.localizedDescription
            return
        }
        guard let rawNonce = appleRawNonce else {
            authManager.errorMessage = AuthError.missingAppleIDToken.localizedDescription
            return
        }
        isLoading = true
        defer {
            isLoading = false
            appleRawNonce = nil
        }
        do {
            try await authManager.signInWithApple(
                idToken: idToken,
                rawNonce: rawNonce,
                fullName: credential.fullName
            )
        } catch {
            logError("Apple sign in failed", error)
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
