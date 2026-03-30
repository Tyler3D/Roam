import EventKit
import SwiftUI

private struct APIClientKey: EnvironmentKey {
    static var defaultValue: APIClient {
        APIClient.previewForSwiftUIPreviews
    }
}

extension EnvironmentValues {
    var apiClient: APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

private struct EventKitServiceKey: EnvironmentKey {
    static let defaultValue = EventKitService()
}

extension EnvironmentValues {
    var eventKitService: EventKitService {
        get { self[EventKitServiceKey.self] }
        set { self[EventKitServiceKey.self] = newValue }
    }
}
