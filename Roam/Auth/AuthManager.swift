import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import GoogleSignInSwift
import Observation
import Security

@Observable
final class AuthManager {
    var user: FirebaseAuth.User?
    var isLoading = true
    var errorMessage: String?

    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                self?.user = firebaseUser
                self?.isLoading = false
            }
        }
    }

    deinit {
        if let handle = authListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var isSignedIn: Bool { user != nil }

    var isVerified: Bool {
        RoamVerificationPolicy.userMeetsVerificationPolicy(user: user)
    }

    // MARK: - Email / Password

    @MainActor
    func signIn(email: String, password: String) async throws {
        errorMessage = nil
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        user = result.user
    }

    @MainActor
    func signUp(email: String, password: String) async throws {
        errorMessage = nil
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        user = result.user
    }

    @MainActor
    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    // MARK: - Google Sign-In

    @MainActor
    func signInWithGoogle() async throws {
        errorMessage = nil
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            throw AuthError.noRootViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingGoogleIDToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        user = authResult.user
    }

    // MARK: - Sign In with Apple

    /// Random nonce for the Apple request; store the return value and pass the same string to `signInWithApple`.
    static func makeAppleSignInRawNonce() -> String {
        randomNonceString(length: 32)
    }

    /// SHA256 (hex) of `rawNonce` for `ASAuthorizationAppleIDRequest.nonce`.
    static func appleSignInHashedNonce(rawNonce: String) -> String {
        sha256Hex(rawNonce)
    }

    @MainActor
    func signInWithApple(
        idToken: String,
        rawNonce: String,
        fullName: PersonNameComponents?
    ) async throws {
        errorMessage = nil
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        user = authResult.user
    }

    // MARK: - Sign Out

    @MainActor
    func signOut() {
        errorMessage = nil
        do {
            try Auth.auth().signOut()
            user = nil
            ReelThumbnailDiskCache.clearAll()
            SavedReelsListDiskCache.clearAll()
            ReelsGridPreviewSnapshot.clear()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called when switching Firebase environments. Clears local state without
    /// relying on the (possibly deleted) FirebaseApp.
    @MainActor
    func forceSignOut() {
        errorMessage = nil
        user = nil
        ReelThumbnailDiskCache.clearAll()
        SavedReelsListDiskCache.clearAll()
        ReelsGridPreviewSnapshot.clear()
    }

    // MARK: - Token

    @MainActor
    func getIdToken(forcingRefresh force: Bool = false) async throws -> String {
        guard let user else { throw AuthError.notSignedIn }
        return try await user.getIDToken(forcingRefresh: force)
    }

    /// Reloads the current Firebase user (e.g. after email verification).
    @MainActor
    func reloadUser() async throws {
        guard let user else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.reload { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        self.user = Auth.auth().currentUser
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case notSignedIn
    case missingClientID
    case noRootViewController
    case missingGoogleIDToken
    case missingAppleIDToken

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .missingClientID: return "Missing Firebase client ID"
        case .noRootViewController: return "Cannot find root view controller"
        case .missingGoogleIDToken: return "Missing Google ID token"
        case .missingAppleIDToken: return "Missing Apple identity token"
        }
    }
}

// MARK: - Apple sign-in nonce (Firebase docs pattern)

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        let randoms: [UInt8] = (0 ..< 16).map { _ in
            var random: UInt8 = 0
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }
            return random
        }

        for random in randoms {
            if remainingLength == 0 {
                break
            }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }

    return result
}

private func sha256Hex(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.map { String(format: "%02x", $0) }.joined()
}
