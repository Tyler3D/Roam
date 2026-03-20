import Foundation

/// Parity with `frontend/.env` (Vite `VITE_*`). iOS reads bundled keys from `Info.plist` / `Bundle.main`.
///
/// | Frontend | iOS |
/// | --- | --- |
/// | `VITE_API_BASE_URL` | `ROAM_LOCAL_BASE_URL` / `ROAM_PRODUCTION_BASE_URL` (merged into `AppConfig.baseURL`) |
/// | `VITE_ENVIRONMENT` (`dev` / `prod`) | `AppConfig.networkEnv` (default **production** for new installs) |
/// | `VITE_FIREBASE_*` | **`GoogleService-Info.plist`** at repo root (Xcode target **Resources**). Download from Firebase Console → Project settings → Your apps → iOS. |
/// | `VITE_TRUSTED_AUTH_PROVIDERS` | **`ROAM_TRUSTED_AUTH_PROVIDERS`** in `Roam/Info.plist` (comma-separated Firebase `providerID`s, e.g. `google.com,password`) |
/// | `VITE_GOOGLE_MAPS_API_KEY` | Add to Info.plist when using Maps SDK (MapKit needs no key) |
///
/// **Google Sign-In URL scheme:** After replacing `GoogleService-Info.plist`, copy **`REVERSED_CLIENT_ID`** into
/// `Roam/Info.plist` → `CFBundleURLTypes` → `CFBundleURLSchemes` so OAuth can return to the app.
enum RoamBuildEnvironment {
    /// Keys in `Roam/Info.plist` (optional overrides).
    static let productionBaseURLPlistKey = "ROAM_PRODUCTION_BASE_URL"
    static let localBaseURLPlistKey = "ROAM_LOCAL_BASE_URL"
    static let stagingBaseURLPlistKey = "ROAM_STAGING_BASE_URL"
    static let trustedAuthProvidersPlistKey = "ROAM_TRUSTED_AUTH_PROVIDERS"
}
