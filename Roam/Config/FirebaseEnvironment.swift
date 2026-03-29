import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import Foundation

/// Manages Firebase configuration switching between production and staging.
///
/// Both environments read config values from `Info.plist` dictionaries:
/// - Production / Local: `ROAM_PRODUCTION_FIREBASE`
/// - Staging: `ROAM_STAGING_FIREBASE`
///
/// Call `configure(for:)` on launch and `reconfigure(to:)` when the user switches environment
/// in the debug menu. Reconfiguring deletes the current `FirebaseApp`, signs out, and
/// re-initialises with the new project's options.
enum FirebaseEnvironment {

    private static let productionKey = "ROAM_PRODUCTION_FIREBASE"
    private static let stagingKey = "ROAM_STAGING_FIREBASE"

    /// Configure Firebase for the given network environment.
    /// Call once at app launch.
    static func configure(for env: NetworkEnv) {
        let key = plistKey(for: env)
        if let options = options(from: key) {
            FirebaseApp.configure(options: options)
        } else {
            // Fallback to bundled GoogleService-Info.plist if Info.plist dict is missing
            FirebaseApp.configure()
        }
    }

    /// Tear down the current Firebase app, sign out, and reconfigure for a new environment.
    /// Returns `true` if reconfiguration succeeded.
    @discardableResult
    static func reconfigure(to env: NetworkEnv) -> Bool {
        // Sign out first so no stale token lingers
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()

        // Delete the default app
        if let app = FirebaseApp.app() {
            app.delete { _ in }
        }

        configure(for: env)

        return FirebaseApp.app() != nil
    }

    // MARK: - Private

    private static func plistKey(for env: NetworkEnv) -> String {
        switch env {
        case .staging:
            return stagingKey
        case .local, .production:
            return productionKey
        }
    }

    private static func options(from plistKey: String) -> FirebaseOptions? {
        guard let dict = Bundle.main.infoDictionary?[plistKey] as? [String: Any],
              let apiKey = dict["API_KEY"] as? String,
              let googleAppID = dict["GOOGLE_APP_ID"] as? String else {
            return nil
        }

        let options = FirebaseOptions(googleAppID: googleAppID, gcmSenderID: dict["GCM_SENDER_ID"] as? String ?? "")
        options.apiKey = apiKey
        options.clientID = dict["CLIENT_ID"] as? String
        options.projectID = dict["PROJECT_ID"] as? String
        options.storageBucket = dict["STORAGE_BUCKET"] as? String
        options.bundleID = dict["BUNDLE_ID"] as? String ?? Bundle.main.bundleIdentifier ?? ""
        return options
    }
}
