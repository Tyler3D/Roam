import CoreLocation
import GoogleMaps
import MapKit
import SwiftUI
import UIKit

/// Google Maps layer with teardrop pins; mirrors `RoamDarkMKMapView`’s binding + `fitToken` contract.
struct RoamGoogleMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var fitToken: Int
    var pins: [(APIClient.CollectionMapPinDTO, CLLocationCoordinate2D)]
    var selectedPinId: UUID?
    /// Insets for visible map content (category row, bottom sheet). Drives `GMSMapView.padding` and camera fitting.
    var mapInsets: UIEdgeInsets
    var onSelectPin: (APIClient.CollectionMapPinDTO) -> Void
    var onUserRegionChange: ((MKCoordinateRegion) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let zoom = Self.zoomLevel(for: region.span)
        let camera = GMSCameraPosition.camera(withTarget: region.center, zoom: zoom)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = true
        mapView.overrideUserInterfaceStyle = .light
        mapView.settings.compassButton = false
        mapView.settings.rotateGestures = true
        mapView.settings.tiltGestures = true
        context.coordinator.mapView = mapView
        context.coordinator.lastAppliedFitToken = fitToken
        context.coordinator.applyPins(to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self

        mapView.padding = mapInsets

        if context.coordinator.lastAppliedFitToken != fitToken {
            context.coordinator.lastAppliedFitToken = fitToken
            context.coordinator.fitCamera(to: pins.map(\.1), in: mapView, animated: true)
        }

        context.coordinator.applyPins(to: mapView)
    }

    private static func zoomLevel(for span: MKCoordinateSpan) -> Float {
        let delta = max(span.latitudeDelta, span.longitudeDelta)
        guard delta > 0 else { return 12 }
        let z = log2(360.0 / delta)
        return Float(min(20, max(1, z)))
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: RoamGoogleMapView
        weak var mapView: GMSMapView?
        var lastAppliedFitToken: Int?
        private var markersByPinId: [UUID: GMSMarker] = [:]

        init(_ parent: RoamGoogleMapView) {
            self.parent = parent
        }

        func fitCamera(to coordinates: [CLLocationCoordinate2D], in mapView: GMSMapView, animated: Bool) {
            let inset = parent.mapInsets
            let edge = UIEdgeInsets(
                top: inset.top + 24,
                left: inset.left + 16,
                bottom: inset.bottom + 24,
                right: inset.right + 16
            )
            guard !coordinates.isEmpty else { return }
            if coordinates.count == 1 {
                let c = coordinates[0]
                let camera = GMSCameraPosition.camera(withTarget: c, zoom: 14)
                if animated {
                    mapView.animate(to: camera)
                } else {
                    mapView.camera = camera
                }
                return
            }
            let first = coordinates[0]
            var bounds = GMSCoordinateBounds(coordinate: first, coordinate: first)
            for c in coordinates.dropFirst() {
                bounds = bounds.includingCoordinate(c)
            }
            let update = GMSCameraUpdate.fit(bounds, with: edge)
            if animated {
                mapView.animate(with: update)
            } else {
                mapView.moveCamera(update)
            }
        }

        func applyPins(to mapView: GMSMapView) {
            let wanted = Set(parent.pins.map(\.0.id))
            for (id, m) in markersByPinId where !wanted.contains(id) {
                m.map = nil
                markersByPinId.removeValue(forKey: id)
            }

            for (pin, coord) in parent.pins {
                let marker: GMSMarker
                if let existing = markersByPinId[pin.id] {
                    marker = existing
                } else {
                    marker = GMSMarker()
                    marker.userData = pin.id.uuidString
                    markersByPinId[pin.id] = marker
                }
                marker.position = coord
                marker.title = pin.pinTitle
                let uiColor = UIColor(MapPinPalette.color(forIndex: pin.colorIndex))
                let selected = pin.id == parent.selectedPinId
                marker.icon = MapTeardropPinBitmap.uiImage(color: uiColor, selected: selected)
                marker.groundAnchor = CGPoint(x: 0.5, y: 1)
                marker.zIndex = selected ? 10 : 0
                marker.map = mapView
            }
        }

        func mapView(_ mapView: GMSMapView, idleAt _: GMSCameraPosition) {
            let r = Self.mkRegion(from: mapView)
            parent.onUserRegionChange?(r)
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let idString = marker.userData as? String,
                  let uuid = UUID(uuidString: idString),
                  let pair = parent.pins.first(where: { $0.0.id == uuid }) else { return false }
            parent.onSelectPin(pair.0)
            return true
        }

        private static func mkRegion(from mapView: GMSMapView) -> MKCoordinateRegion {
            let projection = mapView.projection
            let topLeft = projection.coordinate(for: CGPoint(x: 0, y: 0))
            let bottomRight = projection.coordinate(for: CGPoint(x: mapView.bounds.width, y: mapView.bounds.height))
            let center = mapView.camera.target
            let latDelta = max(abs(topLeft.latitude - bottomRight.latitude), 0.001) * 1.05
            let lonDelta = max(abs(topLeft.longitude - bottomRight.longitude), 0.001) * 1.05
            return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
        }
    }
}
