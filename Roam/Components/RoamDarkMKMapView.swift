import MapKit
import SwiftUI
import UIKit

// MARK: - Teardrop image (mock SVG → bitmap)

enum MapTeardropPinBitmap {
    private static let viewBox = CGSize(width: 28, height: 35)

    static func uiImage(color: UIColor, selected: Bool, scale: CGFloat = 0) -> UIImage {
        let s = UIScreen.main.scale
        let mult: CGFloat = selected ? 1.2 : 1
        let w = viewBox.width * mult
        let h = viewBox.height * mult
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale > 0 ? scale : s
        format.opaque = false
        let r = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        return r.image { _ in
            let sx = w / viewBox.width
            let sy = h / viewBox.height
            let path = teardropPath(sx: sx, sy: sy)
            color.setFill()
            path.fill()
            path.lineWidth = 0.5
            UIColor.black.withAlphaComponent(0.2).setStroke()
            path.stroke()

            let cx = 14 * sx
            let cy = 12 * sy
            let outer = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: 5 * min(sx, sy), startAngle: 0, endAngle: .pi * 2, clockwise: true)
            UIColor.black.withAlphaComponent(0.2).setFill()
            outer.fill()

            let inner = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: 3.8 * min(sx, sy), startAngle: 0, endAngle: .pi * 2, clockwise: true)
            UIColor.white.withAlphaComponent(0.92).setFill()
            inner.fill()
        }
    }

    private static func teardropPath(sx: CGFloat, sy: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 14 * sx, y: 0))
        p.addCurve(
            to: CGPoint(x: 2 * sx, y: 12.5 * sy),
            controlPoint1: CGPoint(x: 7 * sx, y: 0),
            controlPoint2: CGPoint(x: 2 * sx, y: 5.5 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 14 * sx, y: 35 * sy),
            controlPoint1: CGPoint(x: 2 * sx, y: 21.5 * sy),
            controlPoint2: CGPoint(x: 14 * sx, y: 35 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 26 * sx, y: 12.5 * sy),
            controlPoint1: CGPoint(x: 14 * sx, y: 35 * sy),
            controlPoint2: CGPoint(x: 26 * sx, y: 21.5 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 14 * sx, y: 0),
            controlPoint1: CGPoint(x: 26 * sx, y: 5.5 * sy),
            controlPoint2: CGPoint(x: 21 * sx, y: 0)
        )
        p.close()
        return p
    }
}

// MARK: - Annotation

final class RoamMapPinAnnotation: NSObject, MKAnnotation {
    let pin: APIClient.CollectionMapPinDTO
    var coordinate: CLLocationCoordinate2D

    init(pin: APIClient.CollectionMapPinDTO, coordinate: CLLocationCoordinate2D) {
        self.pin = pin
        self.coordinate = coordinate
        super.init()
    }

    var title: String? { pin.pinTitle }
}

// MARK: - Annotation view

final class RoamTeardropAnnotationView: MKAnnotationView {
    private let imgView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        canShowCallout = false
        addSubview(imgView)
    }

    func configure(color: UIColor, selected: Bool) {
        let img = MapTeardropPinBitmap.uiImage(color: color, selected: selected)
        imgView.image = img
        let size = img.size
        bounds = CGRect(origin: .zero, size: size)
        imgView.frame = bounds
        centerOffset = CGPoint(x: 0, y: -size.height / 2 + 2)
    }
}

// MARK: - UIViewRepresentable

struct RoamDarkMKMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    /// Increment when pins / selection change to programmatically fit the camera.
    var fitToken: Int
    var pins: [(APIClient.CollectionMapPinDTO, CLLocationCoordinate2D)]
    var selectedPinId: UUID?
    var onSelectPin: (APIClient.CollectionMapPinDTO) -> Void
    var onUserRegionChange: ((MKCoordinateRegion) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        if #available(iOS 17.0, *) {
            map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        }
        map.region = region
        context.coordinator.lastAppliedFitToken = fitToken
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.lastAppliedFitToken != fitToken {
            context.coordinator.lastAppliedFitToken = fitToken
            mapView.setRegion(region, animated: true)
        }

        let newIds = Set(pins.map(\.0.id))
        let existing = mapView.annotations.compactMap { $0 as? RoamMapPinAnnotation }
        let oldIds = Set(existing.map(\.pin.id))
        if newIds != oldIds {
            let toRemove = existing.filter { !newIds.contains($0.pin.id) }
            mapView.removeAnnotations(toRemove)
            for (pin, coord) in pins where !oldIds.contains(pin.id) {
                mapView.addAnnotation(RoamMapPinAnnotation(pin: pin, coordinate: coord))
            }
        }

        for ann in mapView.annotations {
            guard let pinAnn = ann as? RoamMapPinAnnotation,
                  let view = mapView.view(for: pinAnn) as? RoamTeardropAnnotationView else { continue }
            let uiColor = UIColor(MapPinPalette.color(forIndex: pinAnn.pin.colorIndex))
            view.configure(color: uiColor, selected: pinAnn.pin.id == selectedPinId)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RoamDarkMKMapView
        var lastAppliedFitToken: Int?

        init(_ parent: RoamDarkMKMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? RoamMapPinAnnotation else { return nil }
            let id = "teardrop"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? RoamTeardropAnnotationView)
                ?? RoamTeardropAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            let uiColor = UIColor(MapPinPalette.color(forIndex: ann.pin.colorIndex))
            view.configure(color: uiColor, selected: ann.pin.id == parent.selectedPinId)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let ann = view.annotation as? RoamMapPinAnnotation else { return }
            parent.onSelectPin(ann.pin)
            mapView.deselectAnnotation(view.annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
            parent.onUserRegionChange?(mapView.region)
        }
    }
}
