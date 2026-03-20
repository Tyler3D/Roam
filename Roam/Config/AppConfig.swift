import Foundation
import Observation

private let networkEnvKey = "roam_network_env"
private let appModeKey = "roam_app_mode"
private let stagingURLKey = "roam_staging_base_url"

// MARK: - App Mode (feature selection)

enum AppMode: String, CaseIterable, Identifiable {
    /// Full Roam tab shell (ideas, drafts, plans, map, reels).
    case mainRoam = "mainRoam"
    /// QA: reels grid + inbox only (UserDefaults key name kept for compatibility).
    case reelIngestionMVP = "reelIngestionMVP"
    case timeEstimatesMVP = "timeEstimatesMVP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mainRoam: return "Main Roam"
        case .reelIngestionMVP: return "Reel queue only"
        case .timeEstimatesMVP: return "Time estimates MVP"
        }
    }
}

// MARK: - Network Env (backend selection)

enum NetworkEnv: String, CaseIterable, Identifiable {
    case local
    case staging
    case production

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .staging: return "Staging"
        case .production: return "Production"
        }
    }
}

// MARK: - AppConfig

@Observable
final class AppConfig {
    var appMode: AppMode {
        didSet {
            UserDefaults.standard.set(appMode.rawValue, forKey: appModeKey)
        }
    }

    var networkEnv: NetworkEnv {
        didSet {
            UserDefaults.standard.set(networkEnv.rawValue, forKey: networkEnvKey)
        }
    }

    /// Optional override for staging base URL (stored in UserDefaults). If nil, uses default from Info.plist or constant.
    var stagingBaseURLOverride: String? {
        didSet {
            UserDefaults.standard.set(stagingBaseURLOverride, forKey: stagingURLKey)
        }
    }

    /// Effective base URL for API calls (no trailing slash). `APIClient` paths are `/api/...` like `frontend/src/lib/api.ts`.
    var baseURL: String {
        switch networkEnv {
        case .local:
            return Self.defaultLocalBaseURL
        case .staging:
            return Self.normalizedBaseURL(stagingBaseURLOverride ?? Self.defaultStagingBaseURL)
        case .production:
            return Self.normalizedBaseURL(Self.defaultProductionBaseURL)
        }
    }

    /// Shown in debug menu.
    var effectiveBaseURLDisplay: String { baseURL }

    private static var defaultLocalBaseURL: String {
        let fromPlist = Bundle.main.infoDictionary?[RoamBuildEnvironment.localBaseURLPlistKey] as? String
        return Self.normalizedBaseURL(fromPlist ?? "http://localhost:8000")
    }

    private static var defaultStagingBaseURL: String {
        let fromPlist = Bundle.main.infoDictionary?[RoamBuildEnvironment.stagingBaseURLPlistKey] as? String
        return Self.normalizedBaseURL(fromPlist ?? "https://your-staging-url.run.app")
    }

    /// Default prod API host (same as `VITE_API_BASE_URL` when frontend points at gateway). Paths add `/api/...`.
    private static var defaultProductionBaseURL: String {
        let fromPlist = Bundle.main.infoDictionary?[RoamBuildEnvironment.productionBaseURLPlistKey] as? String
        return Self.normalizedBaseURL(fromPlist ?? "https://roam-gateway-cm0ahzq6.ue.gateway.dev")
    }

    private static func normalizedBaseURL(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    init() {
        Self.migrateOffMockNetworkPreference()

        // Migrate: old roam_app_mode held local/staging/production (network env)
        let networkEnvRaw = UserDefaults.standard.string(forKey: networkEnvKey)
        let legacyRaw = UserDefaults.standard.string(forKey: "roam_app_mode")

        if networkEnvRaw == nil, let legacy = legacyRaw, NetworkEnv(rawValue: legacy) != nil {
            UserDefaults.standard.set(legacy, forKey: networkEnvKey)
            UserDefaults.standard.set(AppMode.mainRoam.rawValue, forKey: appModeKey)
        }

        let envRaw = UserDefaults.standard.string(forKey: networkEnvKey) ?? NetworkEnv.production.rawValue
        let modeRaw = UserDefaults.standard.string(forKey: appModeKey) ?? AppMode.mainRoam.rawValue
        self.networkEnv = NetworkEnv(rawValue: envRaw) ?? .production
        self.appMode = AppMode(rawValue: modeRaw) ?? .mainRoam
        self.stagingBaseURLOverride = UserDefaults.standard.string(forKey: stagingURLKey)
    }

    /// Former "Mock" network mode stored `mock` in UserDefaults; map to production.
    private static func migrateOffMockNetworkPreference() {
        if UserDefaults.standard.string(forKey: networkEnvKey) == "mock" {
            UserDefaults.standard.set(NetworkEnv.production.rawValue, forKey: networkEnvKey)
        }
        if UserDefaults.standard.string(forKey: "roam_app_mode") == "mock" {
            UserDefaults.standard.set(NetworkEnv.production.rawValue, forKey: networkEnvKey)
            UserDefaults.standard.set(AppMode.mainRoam.rawValue, forKey: appModeKey)
        }
    }
}
