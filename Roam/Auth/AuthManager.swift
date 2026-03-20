import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import GoogleSignInSwift
import Observation

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

    // MARK: - Sign Out

    @MainActor
    func signOut() {
        errorMessage = nil
        do {
            try Auth.auth().signOut()
            user = nil
            ReelThumbnailDiskCache.clearAll()
            SavedReelsListDiskCache.clearAll()
        } catch {
            errorMessage = error.localizedDescription
        }
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

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .missingClientID: return "Missing Firebase client ID"
        case .noRootViewController: return "Cannot find root view controller"
        case .missingGoogleIDToken: return "Missing Google ID token"
        }
    }
}
