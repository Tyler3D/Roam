import Foundation
import GoogleMaps
import GooglePlacesSwift

enum GoogleMapsBootstrap {
    /// `GOOGLE_MAPS_IOS_API_KEY` in `Info.plist` for Maps SDK and Places SDK (New). Call once at launch.
    static func configureIfPossible() {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_IOS_API_KEY") as? String else { return }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        GMSServices.provideAPIKey(key)
        _ = PlacesClient.provideAPIKey(key)
    }
}
