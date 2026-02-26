import Foundation
import Observation

private let networkEnvKey = "roam_network_env"
private let appModeKey = "roam_app_mode"
private let stagingURLKey = "roam_staging_base_url"

// MARK: - App Mode (feature selection)

enum AppMode: String, CaseIterable, Identifiable {
    case reelIngestionMVP
    case timeEstimatesMVP

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reelIngestionMVP: return "Reel Ingestion MVP"
        case .timeEstimatesMVP: return "Time estimates MVP"
        }
    }
}

// MARK: - Network Env (backend selection)

enum NetworkEnv: String, CaseIterable, Identifiable {
    case mock
    case local
    case staging
    case production

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mock: return "Mock"
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

    /// When true, auth is bypassed and mock sign-in is used.
    var isMockAuth: Bool { networkEnv == .mock }

    var isNetworkEnabled: Bool { networkEnv != .mock }

    /// Effective base URL for API calls. Nil in mock mode.
    var baseURL: String? {
        switch networkEnv {
        case .mock:
            return nil
        case .local:
            return "http://localhost:8000"
        case .staging:
            return stagingBaseURLOverride ?? Self.defaultStagingBaseURL
        case .production:
            return Self.defaultProductionBaseURL
        }
    }

    /// Shown in debug menu. Mock: "No network"; else the base URL.
    var effectiveBaseURLDisplay: String {
        guard let baseURL else { return "No network" }
        return baseURL
    }

    private static var defaultStagingBaseURL: String {
        (Bundle.main.infoDictionary?["ROAM_STAGING_BASE_URL"] as? String) ?? "https://your-staging-url.run.app"
    }

    private static var defaultProductionBaseURL: String {
        (Bundle.main.infoDictionary?["ROAM_PRODUCTION_BASE_URL"] as? String) ?? ""
    }

    init() {
        // Migrate: old roam_app_mode held mock/local/staging/production (network env)
        let networkEnvRaw = UserDefaults.standard.string(forKey: networkEnvKey)
        let legacyRaw = UserDefaults.standard.string(forKey: "roam_app_mode")

        if networkEnvRaw == nil, let legacy = legacyRaw, NetworkEnv(rawValue: legacy) != nil {
            UserDefaults.standard.set(legacy, forKey: networkEnvKey)
            UserDefaults.standard.set(AppMode.reelIngestionMVP.rawValue, forKey: appModeKey)
        }

        let envRaw = UserDefaults.standard.string(forKey: networkEnvKey) ?? NetworkEnv.local.rawValue
        let modeRaw = UserDefaults.standard.string(forKey: appModeKey) ?? AppMode.reelIngestionMVP.rawValue
        self.networkEnv = NetworkEnv(rawValue: envRaw) ?? .local
        self.appMode = AppMode(rawValue: modeRaw) ?? .reelIngestionMVP
        self.stagingBaseURLOverride = UserDefaults.standard.string(forKey: stagingURLKey)
    }
}
