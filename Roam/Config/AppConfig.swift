import Foundation
import Observation

private let appModeKey = "roam_app_mode"
private let stagingURLKey = "roam_staging_base_url"

enum AppMode: String, CaseIterable, Identifiable {
    case mock
    case local
    case staging

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mock: return "Mock"
        case .local: return "Local"
        case .staging: return "Staging"
        }
    }
}

@Observable
final class AppConfig {
    var currentMode: AppMode {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: appModeKey)
        }
    }

    /// Optional override for staging base URL (stored in UserDefaults). If nil, uses default from Info.plist or constant.
    var stagingBaseURLOverride: String? {
        didSet {
            UserDefaults.standard.set(stagingBaseURLOverride, forKey: stagingURLKey)
        }
    }

    var isNetworkEnabled: Bool { currentMode != .mock }

    /// Effective base URL for API calls. Nil in mock mode.
    var baseURL: String? {
        switch currentMode {
        case .mock:
            return nil
        case .local:
            return "http://localhost:8000"
        case .staging:
            return stagingBaseURLOverride ?? Self.defaultStagingBaseURL
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

    init() {
        let raw = UserDefaults.standard.string(forKey: appModeKey) ?? AppMode.local.rawValue
        self.currentMode = AppMode(rawValue: raw) ?? .local
        self.stagingBaseURLOverride = UserDefaults.standard.string(forKey: stagingURLKey)
    }
}
