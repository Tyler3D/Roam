import FirebaseAuth
import Foundation

/// Matches `frontend/src/auth/verificationPolicy.ts` and backend `TRUSTED_AUTH_PROVIDERS` defaults.
enum RoamVerificationPolicy {
    static var trustedProviderIDs: Set<String> {
        let trimmed = (Bundle.main.object(forInfoDictionaryKey: RoamBuildEnvironment.trustedAuthProvidersPlistKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = trimmed.isEmpty ? "google.com,password" : trimmed
        return Set(
            source.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    /// Email verified, or signed in with a provider we treat as verified (configurable; default includes `password` like web).
    static func userMeetsVerificationPolicy(user: User?) -> Bool {
        guard let user else { return false }
        if user.isEmailVerified { return true }
        let ids = user.providerData.map(\.providerID)
        if ids.contains("password") { return true }
        return ids.contains { trustedProviderIDs.contains($0) }
    }
}
