import Combine
import CoreLocation
import Foundation

/// Requests **When In Use** location so `GMSMapView` can show the user dot (`isMyLocationEnabled`).
final class MapLocationAuthorizer: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUseIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
}
