import Foundation
import GoogleMaps

enum GoogleMapsBootstrap {
    /// `GOOGLE_MAPS_IOS_API_KEY` in `Info.plist` (Maps SDK for iOS). Call once before any `GMSMapView` is created.
    static func configureIfPossible() {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_IOS_API_KEY") as? String else { return }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        GMSServices.provideAPIKey(key)
    }
}
