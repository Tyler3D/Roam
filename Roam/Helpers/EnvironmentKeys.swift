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
